# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/b02-edit-loop-categories/03-category-manage-ui-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-20T10:54:14+08:00

## 上一次 TRD 开发

B02 切片03「R4 分类管理 UI」:把「我的」页只读分类展示改造成可管理列表 + 新增分类编辑器 sheet,消费切片02 已定稿的 Store 方法(未改02)。B02 收尾切片。

- 分类区 `@Query` 从「仅预置」放开为「全部分类」(去掉 isPreset filter,改名 `categories`),按 direction 分组 + sortOrder 排序。
- 只读标签流 → 可管理行列表:预置行「预置 · 锁定」点击弹 alert 不进编辑器、无删除入口;自定义行「编辑 ›」点击进编辑器;底部「＋ 新增自定义分类」;header 从「分类(预置)」改「分类」。
- 新增 `CategoryEditorSheet`(仿 BudgetEditSheet,NavigationStack+Form):新增可选方向、编辑锁方向;名称限 6 字 + 去空白;图标 16 选一、颜色 8 选一(对齐原型候选值)。保存:新增走 `createCategory`(UI 层同方向判重,因02不判重)+ sortOrder 取全局 max+1 排末尾;编辑走 `updateCategory`(02 内建判重),catch `duplicateName` 与新增文案统一「该方向已有同名分类」。
- 删除入口在编辑器内:二次确认带引用数 + 方向化兜底名(收入显「其他收入」纠原型 bug);**先 dismiss 再 deleteCategory** 防 SwiftData 悬垂 SIGTRAP(复刻 DeepLinkResultSheet 范式)。
- 预置行图标/颜色为 nil 走 `CategoryStyle` 兜底;自定义行用自带 icon/color,新建 `Color(hex:)` 私有扩展解析 hex(项目此前无此工具)。

## 涉及文件和符号

- `Aubade/Features/AppShell/RootTabView.swift`(唯一改动文件,全内联无新建文件):
  - `ProfilePlaceholderView`:`@Query categories`(改名放开)、`@State editorRoute`/`showingPresetLockedAlert`、`.sheet(item:)`+`.alert`、`categorySection`/`categoryRows`/`categoryRow`/`categoryBadge`(替换旧 `categoryTags`)。
  - 新增私有类型:`CategoryEditorRoute: Identifiable`(.create/.edit)、`CategoryEditorChoices`(16图标+8色常量)、`CategoryEditorSheet`、`extension Color { init?(hex:) }`。
- 未改:切片02 的 `LedgerStore` 分类方法/`CategoryError`、`LedgerCategory` 模型、`CategoryStyle`、识别链路、`RecordTabView` 分类选择器(其 `@Query categories` 已天然取全部,新增分类自动可见)。

## 验证情况

- **编译**:`xcodebuild build`(iPhone 17 Pro)`** BUILD SUCCEEDED **`;App 启动渲染正常。
- **收尾回归全量单测**(PRD 验收11):`xcodebuild test` **161 tests, 0 failures, ** TEST SUCCEEDED ****。含 CategoryStoreTests、RelationshipTests(泛型删除仍 nullify)、PresetCategoryTests(预置幂等)、B01 剩余总额及识别/统计全部既有测试,无回归。
- **jflow-review**:1/3 轮 PASS。双只读子 agent(SwiftData正确性/生命周期 + TRD符合度/验收覆盖/范围守界)均零阻断。核实:删除时序严格「先dismiss再delete」、@Query 改名全文件零残留、`Color(hex:)` 全局唯一、判重限定同方向、方向锁定/名称限6字/兜底文案方向化全部落实、未越界改02/模型。
- **UI 手势验收待用户**:模拟器手动走验证点1-9(增/改/删/预置锁定/删已引用转兜底/删不崩)归用户验收——simctl 无点击能力,按项目约定手势验证归用户。

## 遗留风险和注意事项

- **`project.pbxproj` 会话前既存改动**(objectVersion 77→71 + section 重排,疑 Xcode 版本差异),与切片03 无关(本片全内联无新文件)。提交策略待与用户确认,未擅自纳入本次提交。
- 新增判重/sortOrder 基于 `@Query` 内存快照,单用户无并发写、编辑态另有02库级判重双保险,可接受。
- deleteMessage 承诺「转到其他/其他收入」,deleteCategory 兜底缺失时走 .nullify——仅「预置删光」异常态分叉,正常态(预置不可删)兜底恒存在,文案与行为一致。
- 编辑态 `@State direction` 初始化为 c.direction 但不显示/不参与保存,死值无害。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
- **B02 三切片(01最近记录删除/02分类Store/03分类管理UI)全部落地并通过评审**,B02 节点开发完成。
- **下一步**:更新 DAG(`docs/design/batch01-feedback-fixes-dev-dag.md`)b02 节点状态为完成;确认 batch01 是否还有下一个可开发节点——有则 next_action 指向生成该节点 PRD(`jflow-start`),无则按 config.json.main_branch 处理主线。
- **git 待办**:切片03 改动(RootTabView.swift)提交策略待用户确认分支;pbxproj 既存改动如何处理待用户确认。
