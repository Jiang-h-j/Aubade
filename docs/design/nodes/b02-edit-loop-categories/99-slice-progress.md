# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/b02-edit-loop-categories/01-recent-delete-trd.md`
- 下一个 TRD：`docs/design/nodes/b02-edit-loop-categories/02-category-store-trd.md`
- 更新时间：2026-07-19T20:57:01+08:00

## 上一次 TRD 开发

B02 切片01「R3 最近记录删除」：记账页 `RecordTabView` 的「最近记录」区从手搓 `VStack+ForEach+Button+Divider`（无删除入口）改造为 `List+ForEach+.swipeActions`，接入左滑删除 + 页面级二次确认，交互对齐账单页 `LedgerTabView`。删除后 `@Query` 自动刷新，最近记录/剩余总额/统计同步更新。点行进编辑行为保留不变。

## 涉及文件和符号

单文件改动：`Aubade/Features/Record/RecordTabView.swift`
- 新增 `@State private var pendingDelete: Transaction?`（左滑删除二次确认目标）
- 新增 `recentRowHeight: CGFloat = 60` 常量（List 嵌 ScrollView 固定行高，注释含取值推导与单行定高脆弱点）
- `recentSection` 内容区：`VStack` → `List`，加 `.swipeActions(edge:.trailing)`（置 pendingDelete）、`.scrollDisabled(true)`、`.scrollContentBackground(.hidden)`、`.frame(height: count*60)`、逐行 `.listRowInsets(EdgeInsets())/.listRowSeparator(.hidden)/.listRowBackground(.clear)`；外层保留 `RoundedRectangle(cornerRadius:12)` 圆角容器
- body 末尾追加页面级 `.confirmationDialog("删除这笔账单？"/"删除后无法恢复")`（照抄账单页文案）
- 新增私有 `deleteConfirmBinding`（pendingDelete!=nil 即弹/关闭清空）与 `delete(_:)`（复用 `EditorActions.makeDelete(store:tx:)` + 清 pendingDelete）
- 顺手更正 `editSheet` 过时注释（原引「切片03」，实为本切片）

不改：`RecentTransactionRow`、`recentFour`/`@Query`、`editSheet` 行为、账单页、`EditorActions`、数据模型。

## 验证情况

- **编译**：`xcodebuild -scheme Aubade -destination 'iPhone 17' Debug build` 两次均 BUILD SUCCEEDED。
- **静态截图验证（模拟器）**：单行数据下 List 渲染正常——高度未塌陷、圆角卡片贴合内容无多余空白、List 默认背景已消隐、行观感（emoji 圆标+分类名+时间+金额）与改造前一致。
- **jflow-review**：1/3 轮 PASS，双只读子 agent（代码正确性/SwiftUI-SwiftData 陷阱 + TRD符合度/范围守界）均无阻断项。已采纳两条高置信非阻断建议：行高 56→60（补计右侧 body+caption 文字块高度）、修正 editSheet 过时切片编号注释。SwiftData 删除路径与账单页同构、无悬垂 SIGTRAP 风险（删除走页面级 confirmationDialog、不在 sheet 内触发）。
- **手势类验证点归用户手动验收**：左滑删除主路径、二次确认、取消不误删、点击进编辑仍在——受 macOS 沙箱 TCC 限制（辅助访问被拒 -1719，simctl 无 tap、无 idb/cliclick）无法程序化注入触摸手势。用户已明确表示验证由其自己做、待所有节点开发完成后验收。

## 遗留风险和注意事项

- **固定行高 60 依赖「行恒为单行定高」**：`RecentTransactionRow` 当前 subtitle `.lineLimit(1)`、单行结构，假设成立。若日后行内容可换行或用户开 Dynamic Type 大字号，`.frame(height: count*60)` 会裁切/留白，须改测量或动态算高方案。此约束已写进代码注释。
- **左滑手势与 `.scrollDisabled(true)` 并存**：横向 swipe 与被禁的纵向 scroll pan 是不同识别器，理论上仍可触发，但需用户真机确认左滑能正常唤出删除。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/b02-edit-loop-categories/02-category-store-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/b02-edit-loop-categories/02-category-store-trd.md`，只实现该 TRD 切片。

补充说明：
- 本切片（01）已完成、待 complete-trd 推进状态并提交。
- 下一个切片：**B02 切片02「R4 分类 Store 能力」**，TRD 路径 `docs/design/nodes/b02-edit-loop-categories/02-category-store-trd.md`。产物：`LedgerStore.swift` 新增 `updateCategory`/分类删除（预置保护+引用计数+删已引用先按方向转兜底再删）+ 单测。02 与 01 独立、与 03 是依赖前置（03 消费 02 的方法签名）。
- 首次提交前需按 jflow-dev 规则确认分支策略（config.json main_branch 为 null）。
