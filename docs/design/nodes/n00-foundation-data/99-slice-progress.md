# N00 工程地基 + 数据层 · 切片进度

> 恢复入口：本文件 + `00-index.md` + `01-foundation-data-trd.md` + 节点 PRD + DAG。

## 切片状态

| 序号 | 切片 | 状态 | 说明 |
|---|---|---|---|
| 01 | 工程骨架 + SwiftData 数据层最小闭环 | 待开发（TRD 已出，待自评审 + 用户 TRD 评审） | 单切片；覆盖 PRD 全部 6 项范围 + 8 条验收 |

## 关键决策与边界（须随节点长期保留）

1. **App Group 路线（PRD 评审已定）**：截图后台走 **in-app App Intents** → 本片**不配置 App Group**，`ModelContainer` 用默认（非共享）配置。对应验收 8 的可审阅证据 = 无 App Group entitlement + `ModelConfiguration` 未传 `groupContainer`。
2. **迁移对冲的边界**：容器创建收敛到 `PersistenceController.makeContainer()` 单点，日后改独立扩展进程只改这一处**代码**；但**已积累数据的目录搬迁不在对冲范围内**，若 N06 真机验证被迫切换，需在 N06 单独评估搬迁逻辑。ViewModel/Store 只持注入的 `ModelContext`、永不自建容器（保留余地的硬约束）。
3. **`source` 枚举归一**：技术基线 §8 写作 `sms/text`，含斜杠不合法作 Swift case / 稳定 RawValue，落地为 `text`（语义等价：短信/任意文本入口）。此为唯一措辞→标识符归一，非静默改动。
4. **预置装载幂等判据**：`fetchCount(isPreset==true) == 0` 才装载，而非"计数是否为 8"——避免用户日后删除某预置分类后重启被补回（分类可增删改是 §8/N07 语义）。验收 4「再启动仍 8 条」在未经用户改动前提下成立。
5. **剩余金额不建字段**：`BalanceBaseline` 只存 `initialAmount` + `establishedAt`，剩余是派生值（§8），派生计算在 N02。
6. **删除规则**：`Category` 对 `Transaction` 用 `.nullify`（删分类不删账单，账单是用户资产）。

## 下游契约（对 N01~N06 承诺，须稳定）

- 四模型字段与技术基线 §8 一致、金额 `Decimal`。
- 单一可共享 `ModelContainer`（in-app 后台链路可直接复用）。
- 首启后 8 条预置分类可查询。
- 读写经注入的 `ModelContext` / `LedgerStore`。

## 自评审记录

**结论：PASS（1 轮，max 3）**。两个只读子 agent 并行评审：

- **上游一致性**：四模型逐字段对齐技术基线 §8 无编造/遗漏；金额三处 Decimal；枚举取值正确（`sms/text→text` 归一可追溯）；预置 8 条 isPreset+sortOrder；剩余金额正确地不建字段；非实体状态未入库；App Group in-app 路线 + 迁移对冲边界如实无夸大；未越界 N01~N07；9 条验证点覆盖 PRD 8 条验收 + DAG 退出标准且可客观观察。无阻断项。
- **技术可实现性**：`@Model`/`@Attribute(.unique)`/`Decimal`/`Codable` 枚举/单端 `inverse`+`.nullify`/`Schema`/`ModelConfiguration`/`ModelContainer(for:configurations:)`/`mainContext`/`#Predicate`/`fetchCount`/`insert`/`save` 均为 iOS 17 SwiftData 真实且正确用法（与 Xcode 默认模板一致）；关系语义、幂等判据、`.task` 时机在单用户主线程下无缺陷；4 个内存容器单测可跑通并证明验收；分层克制未过度设计。无阻断项。

**已采纳的非阻断修订**（5 条）：

1. 验收 3 去掉恒真的 `amount is Decimal` 类型断言（避免编译器 always-true 告警），只留值相等。
2. 验收 5 补明"删分类需 `context.save()`（必要时重新 fetch）才稳定观察到 `category==nil`"。
3. 验收 1 的 `xcodebuild` destination 改用 `generic/platform=iOS Simulator`，不依赖本机具体模拟器名/版本。
4. 验收 4 措辞对齐 PRD"再次启动仍 8 条"，点明"未经用户删改前提"。
5. `Category.transactions` 反向关系处加锚定说明（§8 单向关系的 SwiftData 反向端，非新增业务字段）。

## 用户评审记录

- 2026-07-13：用户明确「TRD 评审通过」。TRD 产物入库并推送，N00 进入开发（jflow-dev），首个切片 01 工程骨架 + SwiftData 数据层最小闭环。
