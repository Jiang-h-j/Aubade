# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n00-foundation-data/01-foundation-data-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-13T15:12:49+08:00

## 上一次 TRD 开发

N00 切片 01「工程骨架 + SwiftData 数据层最小闭环」全部落地并验证通过：手工构造可编译运行的 Xcode 工程（iOS 17+、SwiftUI、零三方依赖）、四个 @Model（Transaction / LedgerCategory / Budget / BalanceBaseline，金额全 Decimal）、三个 Codable 枚举、单一 ModelContainer 封装点（PersistenceController）、8 条预置分类首次幂等装载、薄 CRUD 封装（LedgerStore）、DEBUG-only 调试入口，以及覆盖 PRD 验收 2/3/4/5 的 10 个单元测试。

开发中定位并修复两个真实缺陷（已入关键决策 7/8）：
- 模型名 Category 与 ObjC runtime `typedef ... *Category` 冲突 → 全局改名 LedgerCategory（用户拍板）。
- SwiftData 悬垂 context：`makeInMemoryContainer().mainContext` 链式取用致容器被释放、insert/save 时 SIGTRAP → 测试改为持有容器。

## 涉及文件和符号

新增源码（Aubade/）：AubadeApp.swift、ContentView.swift、Models/{Enums,Transaction,LedgerCategory,Budget,BalanceBaseline}.swift、Persistence/{PersistenceController,PresetCategories}.swift、Store/LedgerStore.swift、Debug/DebugMenuView.swift。
新增测试（AubadeTests/）：ModelCRUDTests、DecimalPrecisionTests、PresetCategoryTests、RelationshipTests。
工程文件：Aubade.xcodeproj/project.pbxproj（手工构造，objectVersion 77 file-system-synchronized groups）+ 共享 scheme Aubade.xcscheme。
关键符号：PersistenceController.makeContainer/makeInMemoryContainer、PresetCategories.seedIfNeeded、LedgerStore（createCategory/createTransaction/updateTransaction/presetCategories/fetch/delete）。

## 验证情况

- 编译：`xcodebuild -scheme Aubade -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED（验证点 1）。
- 单测：`xcodebuild test`（iPhone 17 Pro / iOS 26.5 模拟器）→ 10/10 passed，TEST SUCCEEDED（验证点 2/3/4/5）。
- 审阅类验证点 6/7/8/9：容器单点（全仓仅 PersistenceController 两处构造 ModelContainer）、非实体状态未入库（四模型无 Key/通知/阈值/周期规则）、无 App Group（0 个 .entitlements、无 groupContainer）、sms/text→text 归一有注释——全部通过。
- jflow-review 代码自评审：PASS（1 轮 / max 3）。两个只读子 agent（上游一致性+范围、SwiftData 技术正确性+健壮性）均无阻断项；确认两个坑修复彻底、产品代码无同类悬垂隐患。已采纳非阻断建议 1（改名决策补登 slice-progress 关键决策 7/8）；其余非阻断建议（PersistenceController enum vs struct、seed 静默吞错、updatedAt 断言偏弱、手建分类默认 sortOrder）不改，理由见评审。

## 遗留风险和注意事项

- 工程文件手工构造（本机无 xcodegen/tuist）：已被 xcodebuild 成功解析+编译+测试，但日后用 Xcode GUI 增删文件仍走 file-system-synchronized groups 自动纳入，新增 target 或 build setting 需谨慎手改 pbxproj。
- 环境依赖：本机 Xcode 26.6 + iOS 26.5 模拟器 runtime 已装；换机需重新 `xcodebuild -downloadPlatform iOS`。
- N01~N07 引用分类模型一律用 `LedgerCategory`（非 Category）；任何 SwiftData 代码禁止链式 `container().mainContext`，须先持有容器。
- Bundle ID 占位 com.aubade.app，真机自签名时按开发者账号调整（不影响本片验收）。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
N00 只有这一个切片，完成即节点闭环。下一步：complete-trd 推进状态 → git 提交（type[scope]: 规范）→ 更新 DAG 标记 N00 完成 → 按 DAG 找下一个可开发节点，将 next_action 指向生成该节点 PRD（进入普通 Jflow 节点 PRD/TRD/dev）。恢复文件：`.claude/jflow/current.json`、`docs/design/aubade-v1-dev-dag.md`、本节点 `99-slice-progress.md`。
