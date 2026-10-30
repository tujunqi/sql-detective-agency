-- =====================================================================
-- 指标探案馆 · 数字侦探局
-- tools/模拟数据生成模板.sql —— 复用造数模板（MySQL 8.0）
-- =====================================================================
-- 用途：给自定义关卡/练习造带"脏数据"的模拟数据。
-- 用法：在 DataGrip 中连接 MySQL 8.0，整段或按模板分块运行。
-- 注意：所有模板先 DROP 再建，重复运行会重置 demo 库。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 模板 0 · 演示库初始化与重置脚本模板
-- 每个关卡的"案发现场"脚本都遵循这个骨架：DROP → CREATE → USE → 建表 → 插入
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS demo_generator;
CREATE DATABASE demo_generator DEFAULT CHARACTER SET utf8mb4;
USE demo_generator;

-- 通用行为日志表（可按需增减字段）
CREATE TABLE demo_event_log (
  id          INT AUTO_INCREMENT PRIMARY KEY COMMENT '日志流水号',
  user_id     VARCHAR(32) NULL COMMENT '用户ID（游客为 NULL，制造空值坑）',
  device_id   VARCHAR(64) NOT NULL COMMENT '设备号',
  event_name  VARCHAR(64) NOT NULL COMMENT '事件名',
  event_time  DATETIME    NOT NULL COMMENT '事件时间',
  platform    VARCHAR(16) NOT NULL COMMENT '平台',
  app_version VARCHAR(16) NOT NULL COMMENT '版本'
) COMMENT '演示用行为日志';

-- ---------------------------------------------------------------------
-- 模板 1 · 递归 CTE 生成日历序列（日期维度表）
-- 场景：对账、补齐无数据日期、按天 JOIN
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS demo_calendar;
CREATE TABLE demo_calendar (
  d DATE PRIMARY KEY COMMENT '自然日'
) COMMENT '日历维度表';

INSERT INTO demo_calendar (d)
WITH RECURSIVE dates(d) AS (
  SELECT DATE('2026-09-01')                          -- 起点
  UNION ALL
  SELECT d + INTERVAL 1 DAY FROM dates WHERE d < '2026-09-30'  -- 终点
)
SELECT d FROM dates;

-- 验收：应返回 30 行
SELECT COUNT(*) AS calendar_days FROM demo_calendar;

-- ---------------------------------------------------------------------
-- 模板 2 · 递归 CTE 批量生成行为数据（第 9 关同款）
-- 场景：批量制造规整背景数据，再手工 INSERT 少量脏数据（爬虫/连点/挂起）
-- ---------------------------------------------------------------------
INSERT INTO demo_event_log (user_id, device_id, event_name, event_time, platform, app_version)
WITH RECURSIVE seq(n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 200   -- 生成 200 行
)
SELECT
  CONCAT('u', LPAD(CEILING(n / 4), 3, '0')),               -- 每 4 行一个用户 → 50 个用户
  CONCAT('dev_u', LPAD(CEILING(n / 4), 3, '0')),
  'app_launch',
  '2026-09-15 08:00:00' + INTERVAL (n - 1) * 7 MINUTE,     -- 每 7 分钟一条
  CASE WHEN n % 2 = 0 THEN 'ios' ELSE 'android' END,       -- 平台交替
  CASE WHEN n % 10 = 0 THEN '3.2.0' ELSE '3.1.9' END       -- 每 10 条混入一个新版本
FROM seq;

-- 验收：200 行，50 个用户
SELECT COUNT(*) AS rows_total, COUNT(DISTINCT user_id) AS users FROM demo_event_log;

-- ---------------------------------------------------------------------
-- 模板 3 · 存储过程：随机行为生成器（带脏数据注入）
-- 场景：需要随机性（金额、时长、行为类型）时用 RAND()；循环内可埋坑
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS gen_random_events;
DELIMITER $$
CREATE PROCEDURE gen_random_events(IN p_rows INT, IN p_dirty_ratio INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  DECLARE dirty INT;
  WHILE i < p_rows DO
    SET dirty = FLOOR(RAND() * 100);
    IF dirty < p_dirty_ratio THEN
      -- 脏数据：10% 概率生成"游客空值 + 重复上报"
      INSERT INTO demo_event_log (user_id, device_id, event_name, event_time, platform, app_version)
      VALUES (NULL, CONCAT('dev_dirty_', FLOOR(RAND() * 5) + 1), 'app_launch',
              '2026-09-20 03:00:00' + INTERVAL FLOOR(RAND() * 600) MINUTE,
              'android', '3.2.0');
      -- 同一设备立刻再报一次（模拟弱网重试）
      INSERT INTO demo_event_log (user_id, device_id, event_name, event_time, platform, app_version)
      VALUES (NULL, CONCAT('dev_dirty_', FLOOR(RAND() * 5) + 1), 'app_launch',
              '2026-09-20 03:00:00' + INTERVAL FLOOR(RAND() * 600) MINUTE,
              'android', '3.2.0');
    ELSE
      -- 正常数据：随机用户、随机平台
      INSERT INTO demo_event_log (user_id, device_id, event_name, event_time, platform, app_version)
      VALUES (CONCAT('u', LPAD(FLOOR(RAND() * 50) + 1, 3, '0')),
              CONCAT('dev_u', LPAD(FLOOR(RAND() * 50) + 1, 3, '0')),
              'app_launch',
              '2026-09-20 09:00:00' + INTERVAL FLOOR(RAND() * 720) MINUTE,
              IF(RAND() < 0.5, 'ios', 'android'), '3.1.9');
    END IF;
    SET i = i + 1;
  END WHILE;
END$$
DELIMITER ;

CALL gen_random_events(100, 10);   -- 生成 100 轮，其中约 10% 为脏数据（每轮 2 行）

-- 验收：检查空值与重复上报是否落地
SELECT SUM(user_id IS NULL) AS guest_rows,                          -- 游客空值行
       COUNT(*) - COUNT(DISTINCT device_id) AS extra_rows_per_dev   -- 同设备多行（重复上报迹象）
FROM demo_event_log
WHERE event_name = 'app_launch' AND DATE(event_time) = '2026-09-20';

DROP PROCEDURE IF EXISTS gen_random_events;   -- 用完即删，保持库整洁

-- ---------------------------------------------------------------------
-- 模板 4 · 常用"埋坑"片段速查
-- 复制到任意关卡的 INSERT 里，即可注入对应坑点
-- ---------------------------------------------------------------------
-- 坑① 空值：游客 user_id 置 NULL（device_id 保留）
--   (NULL, 'dev_guest_01', 'app_launch', '2026-09-20 10:00:00', 'ios', '3.1.9')

-- 坑② 重复上报：同一用户同一天插 2 条，时间差几秒（弱网重试）
--   ('u5', 'dev_u5', 'app_launch', '2026-09-20 07:58:00', 'android', '3.1.9'),
--   ('u5', 'dev_u5', 'app_launch', '2026-09-20 07:58:06', 'android', '3.1.9')

-- 坑③ 埋点丢失：某天某平台的用户整段缺席（直接不插）
--   —— 对照正常日少插 4 行即可，SQL 里无需任何特殊写法

-- 坑④ 时间戳越界：leave_time 落到第二天（挂起会话）
--   ('w37','s0037','2026-09-20 23:10:00','2026-09-21 02:40:00', 12600, 8)

-- 坑⑤ 刷量节拍：同设备等间隔高频（5 秒一次 × N 行），且不产生曝光

-- 坑⑥ 拆单：子单 parent_order_id 指向主单
--   ('o01', ..., NULL), ('o02', ..., 'o01')

-- 坑⑦ 0 元单：status='paid' 但 pay_amount=0（试购/体验课）

-- 坑⑧ 汇总双跑：数仓日汇总表中某天的数值 = 明细实际值 × 2

-- ---------------------------------------------------------------------
-- 清理
-- ---------------------------------------------------------------------
-- DROP DATABASE IF EXISTS demo_generator;
