# N07 切片进度

> 由 `jflow_state.py discover-trds` 维护有序列表与 `next_trd`；本文件记录人读进度与切片间依赖。

## 切片清单

| 序 | 文件 | 状态 | 单一职责 | 依赖 |
|---|---|---|---|---|
| 01 | `01-config-center-budget-threshold-trd.md` | 待开发 | 生产配置中心 `AppConfig` + 超支阈值可配（`budgetProgress` 加阈值入参 + 生产/测试全调用点同步）+ 我的页阈值设置项 | N02 |
| 02 | `02-profile-budget-key-category-trd.md` | 待开发 | 我的页预算设置 sheet + Key 状态行（复用 `KeySetupSheet`）+ 分类只读查看 | 切片 01、N02/N03/N00 |
| 03 | `03-onboarding-flow-trd.md` | 待开发 | 首次引导两步（初始总额→Key 提示→落记账页）+ `hasOnboarded` 标志 + `ContentView` 根分流 | 切片 01/02 |
| 04 | `04-notification-toggle-permission-trd.md` | 待开发 | 通知开关 gating（`send` 内读 `AppConfig`）+ 我的页开关 + 统一权限降级 `PermissionDenialNotice` | 切片 01/02、N06/N04 |

## 关键顺序理由

- **01 必须最先**：唯一有签名波及的改动（`budgetProgress` 加入参），波及生产调用点 + 测试调用点共 6 处；`AppConfig` 是后续三片共同依赖的配置底座。
- **02 在 01 后**：纯新增 UI，复用 01 的金额校验范式与 `AppConfig`；与 03/04 正交。
- **03 在 02 后**：改根路由分流点 `ContentView`，引导步②复用 02 已验证的 `KeySetupSheet` 唤起手法 + 01 的 `hasOnboarded`。
- **04 最后**：gating 依赖 01 的 `notificationsEnabled`；统一降级是横切 N04/N06 呈现层收敛，放最后避免与前三片新增 UI 交叉。

## 全节点唯一签名改动（红线）

`StatisticsAggregator.budgetProgress` 加 `nearThreshold: Int = AppConfig.overspendThresholdDefault` 入参——连带同步：
- 生产调用点：`AnalyticsTabView.budgetProgressView:310`
- 测试调用点：`StatisticsAggregatorTests.swift:184-200`（**PRD 未点明，切片 01 显式覆盖**）

其余全为新增 UI 消费既有能力，不改 `LedgerStore`/`KeychainStore`/`Budget`/`LedgerCategory`/`NotificationSending`/发送器对外签名。

## 进度记录

- 2026-07-15：TRD 拆分为 4 切片，自评审前落盘。
