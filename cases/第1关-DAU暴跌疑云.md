# 第1关 · DAU 暴跌疑云

> **难度**：★★☆☆☆ | **核心指标**：DAU（日活跃用户数） | **委托方**：咕噜严选（电商 App） | **报案人**：运营 · 小周 | **预计用时**：40 分钟 | **数据库**：`case01_dau`
>
> 坑点预告：埋点丢失、重复上报、空值（通关后回来看这行）

[上一关：第0关 新人报到](./第0关-新人报到.md) | [返回目录](../README.md) | [下一关：第2关 活跃天数口径迷局](./第2关-活跃天数口径迷局.md)

---

## ⓪ 前情提要

上周五，你只用一条 `GROUP BY` 就拆穿了练习库「人数暴涨」的假象，领到第一枚徽章「🛡️ 入职打卡」。局里那台老咖啡机第一次为你亮起了绿灯。

周一清晨 8:47，卷宗交接口的红灯突然亮起——加急件。档案员阿卷抱着一份贴着红色封条的卷宗小跑过来：

> "咕噜严选的运营小周在电话里都快哭了。**DAU 一夜之间跌了三分之一**，老板下午两点要解释。探长说，这个案子，归你了。不过先别冲——办案之前，先把卷宗读完。"

## 一、【案情通报】

凌晨一点，咕噜严选的运营小周发来加急委托。她盯着周报里的折线图，声音发紧：

> "10 月 15 日，**DAU 从 12 掉到 8**，一夜跌了三分之一。投放没停、活动没撤、竞品也没大动作——用户就像凭空消失了一样。而且更邪门的是，报表组自己人打起来了：一个说跌到 8，一个说跌到 4，两份数据对不上。"

陈探长合上卷宗，看向你：

> "『用户消失』的案子，十有八九藏在三处：**埋点丢失、重复上报、空值**。别急着怀疑业务，先怀疑数据。带好工具，去现场。"

**任务目标**：算出 10-13 ~ 10-16 每日的真实 DAU，验证「暴跌」是否存在，并找出「消失的用户」到底去了哪里。

## 二、【指标卷宗】DAU 的四种统计实现口径

同一个 DAU，四套实现，四个数。办案前先分清报案人手里拿的是哪一套。

### 口径 A：客户端埋点启动口径

- **计算逻辑**：客户端上报 `app_launch`（启动）事件，按天去重。
- **适用场景**：App 产品最常用的口径，行为颗粒度细。
- **歧义坑点**：弱网环境下客户端会**重试上报**（同一次启动报两条）；版本发布当天新版本埋点可能**丢失或字段错位**——本案权犯。

### 口径 B：服务端日志口径

- **计算逻辑**：用网关/接口日志代替埋点，按天去重请求用户。
- **适用场景**：埋点不可靠时的兜底，或对账用。
- **歧义坑点**：接口轮询、爬虫、推送拉起都会打进日志，**DAU 天然虚高**，和客户端口径永远对不齐。

### 口径 C：登录账号口径

- **计算逻辑**：只统计带 `user_id` 的记录，按天去重登录用户。
- **适用场景**：强账号体系（社交、会员制电商）。
- **歧义坑点**：游客（未登录，`user_id` 为 NULL）被整体漏掉。内容社区、工具类产品游客占比能到三成，这一漏就是一个坑——本案第二个权犯。

### 口径 D：设备口径

- **计算逻辑**：按 `device_id` 去重。
- **适用场景**：电商大促、投放评估（不怕未登录）。
- **歧义坑点**：一人多设备（手机 + 平板）会被算成多人；卸载重装换设备号，老用户变"新人"。

### 行业差异速记

| 行业 | 惯用口径 | 特殊之处 |
|---|---|---|
| 电商 | 行为/设备口径混合 | 大促日要区分自然活跃与促销拉动；游客浏览多，口径必须含游客 |
| 在线教育 | 登录口径为主 | 账号体系强，但试听课用户常跨端，设备口径补盲 |
| 内容平台 | 设备口径为主 | 游客占比极高，`user_id` 空值是常态，COALESCE 是标配 |

### 面试标准回答话术

> "DAU 我会先钉三件事：**活跃定义**（埋点、服务端还是登录口径）、**去重键**（user_id、device_id 还是 COALESCE 兜底）、**数据完整性**（版本发布、弱网重试、上报延迟都会污染数字）。口径不钉死，DAU 没有意义。"

### 新手最容易踩的错误统计方式

1. **`COUNT(*)` 当 DAU**：数的是上报次数不是人数，重复上报直接中毒。
2. **`COUNT(DISTINCT user_id)` 直接上**：NULL 游客被静默忽略，游客占比高的产品天天少算一截。
3. **不校验埋点完整性就下结论**：看到跌就归因业务，实际是某个端、某个版本当天根本没上报。

## 三、【案发现场】

### 表结构说明

**表名：`app_event_log`（App 埋点事件表）**

| 字段名 | 类型 | 说明 |
|---|---|---|
| id | INT 自增主键 | 日志流水号 |
| user_id | VARCHAR(32) 可空 | 用户 ID；**游客为 NULL（空值坑）** |
| device_id | VARCHAR(64) | 设备号，全量非空 |
| event_name | VARCHAR(64) | 事件名，本案只关心 `app_launch` |
| event_time | DATETIME | 事件时间 |
| platform | VARCHAR(16) | ios / android |
| app_version | VARCHAR(16) | 客户端版本 |

### 现场还原 SQL（建表 + 模拟数据）

DataGrip 连接 MySQL 8.0 后整段运行。重复运行会先重置，放心执行。

```sql
-- =============================================
-- 第1关 · 案发现场还原脚本（咕噜严选 · 埋点事件表）
-- 运行环境：MySQL 8.0，DataGrip 中整段执行
-- 样例数据为脱敏小样本，量级缩小，规律与真实业务一致
-- =============================================
DROP DATABASE IF EXISTS case01_dau;
CREATE DATABASE case01_dau DEFAULT CHARACTER SET utf8mb4;
USE case01_dau;

CREATE TABLE app_event_log (
  id          INT AUTO_INCREMENT PRIMARY KEY COMMENT '日志流水号',
  user_id     VARCHAR(32) NULL COMMENT '用户ID，游客为NULL',
  device_id   VARCHAR(64) NOT NULL COMMENT '设备号',
  event_name  VARCHAR(64) NOT NULL COMMENT '事件名',
  event_time  DATETIME    NOT NULL COMMENT '事件时间',
  platform    VARCHAR(16) NOT NULL COMMENT '平台 ios/android',
  app_version VARCHAR(16) NOT NULL COMMENT '客户端版本'
) COMMENT 'App 埋点事件表';

-- 模拟数据：10-13 ～ 10-16 四天 launch 埋点（含三种坑）
INSERT INTO app_event_log (user_id, device_id, event_name, event_time, platform, app_version) VALUES
-- 10-13：iOS u1~u4 + Android u5~u8 + 游客4（正常日）
('u1','dev_u1','app_launch','2026-10-13 08:01:00','ios','3.1.9'),
('u2','dev_u2','app_launch','2026-10-13 08:15:00','ios','3.1.9'),
('u3','dev_u3','app_launch','2026-10-13 09:02:00','ios','3.1.9'),
('u4','dev_u4','app_launch','2026-10-13 12:30:00','ios','3.1.9'),
('u5','dev_u5','app_launch','2026-10-13 07:55:00','android','3.1.9'),
('u6','dev_u6','app_launch','2026-10-13 09:10:00','android','3.1.9'),
('u7','dev_u7','app_launch','2026-10-13 19:40:00','android','3.1.9'),
('u8','dev_u8','app_launch','2026-10-13 21:05:00','android','3.1.9'),
(NULL,'dev_g01','app_launch','2026-10-13 10:12:00','ios','3.1.9'),
(NULL,'dev_g02','app_launch','2026-10-13 11:48:00','android','3.1.9'),
(NULL,'dev_g03','app_launch','2026-10-13 16:33:00','ios','3.1.9'),
(NULL,'dev_g04','app_launch','2026-10-13 22:20:00','android','3.1.9'),
-- 10-14：同上，但 u5、u6 弱网重试各多报 1 条（重复上报坑）
('u1','dev_u1','app_launch','2026-10-14 08:03:00','ios','3.1.9'),
('u2','dev_u2','app_launch','2026-10-14 08:44:00','ios','3.1.9'),
('u3','dev_u3','app_launch','2026-10-14 09:21:00','ios','3.1.9'),
('u4','dev_u4','app_launch','2026-10-14 13:12:00','ios','3.1.9'),
('u5','dev_u5','app_launch','2026-10-14 07:58:00','android','3.1.9'),
('u6','dev_u6','app_launch','2026-10-14 09:15:00','android','3.1.9'),
('u5','dev_u5','app_launch','2026-10-14 07:58:06','android','3.1.9'),
('u6','dev_u6','app_launch','2026-10-14 09:15:11','android','3.1.9'),
('u7','dev_u7','app_launch','2026-10-14 20:02:00','android','3.1.9'),
('u8','dev_u8','app_launch','2026-10-14 21:36:00','android','3.1.9'),
(NULL,'dev_g01','app_launch','2026-10-14 09:40:00','ios','3.1.9'),
(NULL,'dev_g02','app_launch','2026-10-14 12:05:00','android','3.1.9'),
(NULL,'dev_g03','app_launch','2026-10-14 15:26:00','ios','3.1.9'),
(NULL,'dev_g04','app_launch','2026-10-14 23:02:00','android','3.1.9'),
-- 10-15：版本 3.2.0 上线，iOS 端 launch 埋点全军覆没（埋点丢失坑）
('u5','dev_u5','app_launch','2026-10-15 08:02:00','android','3.2.0'),
('u6','dev_u6','app_launch','2026-10-15 09:18:00','android','3.2.0'),
('u7','dev_u7','app_launch','2026-10-15 19:55:00','android','3.2.0'),
('u8','dev_u8','app_launch','2026-10-15 21:22:00','android','3.2.0'),
(NULL,'dev_g01','app_launch','2026-10-15 10:05:00','android','3.2.0'),
(NULL,'dev_g02','app_launch','2026-10-15 13:47:00','android','3.2.0'),
(NULL,'dev_g03','app_launch','2026-10-15 17:31:00','android','3.2.0'),
(NULL,'dev_g04','app_launch','2026-10-15 22:10:00','android','3.2.0'),
-- 10-16：恢复正常，仅 u7 又重试多报 1 条
('u1','dev_u1','app_launch','2026-10-16 08:06:00','ios','3.2.0'),
('u2','dev_u2','app_launch','2026-10-16 08:52:00','ios','3.2.0'),
('u3','dev_u3','app_launch','2026-10-16 09:30:00','ios','3.2.0'),
('u4','dev_u4','app_launch','2026-10-16 12:44:00','ios','3.2.0'),
('u5','dev_u5','app_launch','2026-10-16 07:50:00','android','3.2.0'),
('u6','dev_u6','app_launch','2026-10-16 09:02:00','android','3.2.0'),
('u7','dev_u7','app_launch','2026-10-16 19:58:00','android','3.2.0'),
('u7','dev_u7','app_launch','2026-10-16 19:58:05','android','3.2.0'),
('u8','dev_u8','app_launch','2026-10-16 21:15:00','android','3.2.0'),
(NULL,'dev_g01','app_launch','2026-10-16 10:22:00','ios','3.2.0'),
(NULL,'dev_g02','app_launch','2026-10-16 12:39:00','android','3.2.0'),
(NULL,'dev_g03','app_launch','2026-10-16 16:05:00','ios','3.2.0'),
(NULL,'dev_g04','app_launch','2026-10-16 22:41:00','android','3.2.0');
```

## 四、【探案任务】

> ⏱️ **限时挑战**：第 2 步建议给自己计时 **5 分钟**——在真实客户端里这是"限时解码"环节。限时内拼出正确 SQL 可得金牌侦探评级；超时也能通关，别怕。

### 第 1 步 · 口径对齐（先选题，再动手）

小周要的"今天有多少真人来了"，下面哪种统计方式是对的？

- A. `COUNT(*)` 按天统计 `app_launch` 的次数——启动多少次算多少
- B. `COUNT(DISTINCT user_id)` 按天去重——只数登录的注册用户
- C. `COUNT(DISTINCT COALESCE(user_id, device_id))`——注册用户按账号、游客按设备，全量去重

<details>
<summary>点击核对答案</summary>

**选 C**。A 是"人次"不是"人数"，重复上报会中毒（10-14 光 u5、u6 就多报 2 条）；B 会把 `user_id` 为 NULL 的游客全体隐身，每天凭空少 4 人；C 用 `COALESCE` 做空值兜底——注册用户取 `user_id`，游客自动回落到 `device_id`，一个人都不会漏。

</details>

### 第 2 步 · 基础核算（限时 5 分钟）

用锁定口径写出 SQL：输出 10-13 ~ 10-16 每日的 DAU（注册 + 游客全量），验证"暴跌"是否真实存在。

<details>
<summary>卡住了？点击看提示</summary>

骨架：`SELECT DATE(event_time), COUNT(DISTINCT COALESCE(user_id, device_id)) FROM app_event_log WHERE event_name = 'app_launch' GROUP BY DATE(event_time)`。归天用 `DATE()`，去重兜底用 `COALESCE`。

</details>

### 第 3 步 · 真相追踪

10-15 的 DAU 从 12 掉到 8——"消失的 4 个人"是谁？他们是真的没来，还是来了没留痕？用 SQL 从三个方向排查：**按平台拆分**、**找重复上报**、**查空值游客**。

<details>
<summary>点击看提示</summary>

三个排查动作：① 按天 × platform 分组，看哪个平台哪天"消失"；② 按 天 + user_id 分组 `HAVING COUNT(*) > 1` 揪出重复上报；③ `SUM(user_id IS NULL)` 数一数游客行数，再对比 `COUNT(DISTINCT user_id)` 和 `COUNT(DISTINCT COALESCE(user_id, device_id))` 的差。

</details>

## 五、【真相大白】

### 5.1 异常根因拆解

跑完现场数据，真相分三层：

1. **「暴跌」本身是假的**：10-15 全量 DAU 12 → 8，减少的 4 人全部是 **iOS 用户**。当天版本 3.2.0 上线，iOS 端 launch 埋点字段升级失败，4 名 iOS 用户**来了但没留痕**——用户没有消失，是 iOS 的埋点消失了。
2. **两份报表打架的原因**：一份用"人次"口径（被 Android 重复上报污染：10-14 多报 2 条、10-16 多报 1 条），一份用 `COUNT(DISTINCT user_id)`（16 行游客记录被静默忽略）。同一个事实，两种错法，两个数。
3. **日常就在发生的慢性病**：重复上报和游客空值不只在 10-15 存在——它们天天都在让数字失真，只是没人对照过正确口径。

### 5.2 参考答案 SQL（逐行注释）

```sql
USE case01_dau;

-- 【第2步 · 正确口径的每日 DAU】
SELECT
  DATE(event_time)                               AS stat_date,  -- 归天：取出自然日
  COUNT(DISTINCT COALESCE(user_id, device_id))   AS dau_all,    -- 全量去重：注册按账号、游客按设备兜底
  COUNT(DISTINCT user_id)                        AS dau_reg,    -- 对照：只数注册用户（会漏游客）
  COUNT(*)                                       AS event_rows  -- 对照：上报人次（会被重复上报污染）
FROM app_event_log
WHERE event_name = 'app_launch'                                 -- 只看启动事件
GROUP BY DATE(event_time)
ORDER BY stat_date;
-- 结果：10-13 全量12/注册8/人次12；10-14 全量12/注册8/人次14；10-15 全量8/注册4/人次8；10-16 全量12/注册8/人次13
-- 结论：全量 DAU 12 → 8 → 12，暴跌只发生在 10-15

-- 【第3步-① · 平台拆分：消失的4人在哪个端】
SELECT
  DATE(event_time) AS stat_date,
  platform,
  COUNT(DISTINCT COALESCE(user_id, device_id)) AS dau
FROM app_event_log
WHERE event_name = 'app_launch'
GROUP BY DATE(event_time), platform
ORDER BY stat_date, platform;
-- 结果：10-13/14/16 每天 ios、android 各 6 人；10-15 只有 android 8 人——iOS 整端消失
-- 且 10-15 的版本号全部是 3.2.0，指向"版本发布当天 iOS 埋点升级失败"

-- 【第3步-② · 揪出重复上报】
SELECT
  DATE(event_time) AS stat_date,
  user_id,
  COUNT(*)         AS launch_times
FROM app_event_log
WHERE user_id IS NOT NULL
  AND event_name = 'app_launch'
GROUP BY DATE(event_time), user_id
HAVING COUNT(*) > 1
ORDER BY stat_date, user_id;
-- 结果：10-14 的 u5、u6 各 2 次（弱网重试），10-16 的 u7 2 次

-- 【第3步-③ · 空值游客盘点】
SELECT
  COUNT(*)                                     AS total_rows,   -- 全部上报行数
  SUM(user_id IS NULL)                         AS guest_rows,   -- 游客行数（user_id 为 NULL）
  COUNT(DISTINCT user_id)                      AS distinct_uid, -- 只数注册：8 人
  COUNT(DISTINCT COALESCE(user_id, device_id)) AS distinct_real -- 正确全量：12 人
FROM app_event_log
WHERE event_name = 'app_launch';
-- 结果：47 行上报中 16 行是游客；两种数法差 4 人/天——这就是两份报表打架的根源
```

### 5.3 错误写法对比

**错误写法一：`COUNT(*)` 当 DAU（人次口径）**

```sql
SELECT DATE(event_time) AS stat_date, COUNT(*) AS dau   -- 错：这是上报人次
FROM app_event_log
WHERE event_name = 'app_launch'
GROUP BY DATE(event_time)
ORDER BY stat_date;
```

错在哪：数的是行数不是人。10-14 算出 **14**，正确是 **12，虚高 2 人（+17%）**；10-16 算出 13，正确 12，虚高 8%。重复上报哪天发生，哪天就虚高——平时没人发现，是因为没人跑过正确口径。

**错误写法二：`COUNT(DISTINCT user_id)` 直接当全量 DAU**

```sql
SELECT DATE(event_time) AS stat_date,
       COUNT(DISTINCT user_id) AS dau   -- 错：NULL 游客被静默忽略
FROM app_event_log
WHERE event_name = 'app_launch'
GROUP BY DATE(event_time)
ORDER BY stat_date;
```

错在哪：`COUNT(DISTINCT ...)` 不数 NULL。游客 4 人/天全部隐身：每天得出 8、8、4、8，而正确全量是 12、12、8、12——**每天少 4 人，事发日 4 vs 8 直接腰斩（-50%）**。小周看到的"跌到 4"的报表，就是它。

## 六、【侦探办案笔记】

### 本关指标口径总结

- DAU 要钉死三件事：**活跃定义、去重键、数据完整性**。
- `COALESCE(user_id, device_id)` 是处理"注册 + 游客"混合人群的标配去重键。
- 人数口径天然免疫重复上报；人次口径（`COUNT(*)`）对重试上报零抵抗力。
- 数字异常时第一反应不是"业务出事了"，而是"**数据还完整吗**"——按平台、版本、时段三个维度拆开看。

### 业务方对齐口径的标准提问话术

1. "这个 DAU 数的是**人、设备还是次数**？游客算不算？"
2. "**埋点完整性**最近有没有发版？要不要我按平台和版本拆一下？"
3. "两份报表数字对不上时，先把**各自的 SQL** 拉出来对一遍，再讨论业务。"

### 同类异常排查的通用方法论

"人数类指标暴跌"三板斧：

1. **拆维度**：天 × 平台 × 版本 × 渠道，找到"哪个切片归零"；
2. **查污染**：重复上报（`HAVING COUNT(*) > 1`）、空值（`SUM(col IS NULL)`）、刷量（设备频率异常）；
3. **对口径**：把两份打架的报表 SQL 并排跑，找到分子分母的差异。

### 解锁成就徽章

🏆 **「埋点猎人」**——你识破了"用户凭空消失"的假象，救下了小周下午两点的汇报。经验 +15%，侦探等级：见习侦探 → **C级侦探**。徽章档案见 [成就徽章系统](../docs/成就徽章系统.md)。

---

> **下关预告** · 第2关 活跃天数口径迷局：深夜十一点，启航课堂的产品经理老李发来消息："人均月活跃天数 8.5 天，行业顶尖！"五分钟后，教务主任拍着桌子回怼："最多 5 天，数据组别掺水！"——同一批学生，两个数字，中间隔着一条没钉死的口径。这一次，你会站谁那边？
