# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/b02-edit-loop-categories/02-category-store-trd.md`
- 下一个 TRD：`docs/design/nodes/b02-edit-loop-categories/03-category-manage-ui-trd.md`
- 更新时间：2026-07-20T10:29:44+08:00

## 上一次 TRD 开发

B02 切片02「R4 分类 Store 能力」：在 `LedgerStore` 补齐分类的「改」「删」两项纯后台能力，正确性全部用单测焊死，不涉及 UI（UI 归切片03）。

- `updateCategory(_:name:icon:color:)`：改自定义分类名称/图标/颜色；预置拒改（`presetImmutable`）；同方向重名（排除自身）拒绝（`duplicateName`）；方向不可改（签名不含 direction）。判重用全量 fetch 内存过滤，对齐 `setBudget` 范式。
- `deleteCategory(_:)`：预置拒删（`presetUndeletable`）；删前把该分类账单逐笔按方向转兜底分类（支出「其他」/收入「其他收入」，与 `RecognitionNormalizer` 同一常量口径）再删，保证账单不丢分类；兜底缺失（异常态）走 `.nullify`。改 tx.category 与 delete 在同一 `save()` 落库。
- `enum CategoryError: Error`：3 个 case（presetImmutable/presetUndeletable/duplicateName），只做类型区分，文案由 UI 决定。
- 引用计数不新增方法，UI 直读 `category.transactions.count`（TRD 定）。

## 涉及文件和符号

- `Aubade/Store/LedgerStore.swift`：新增 `updateCategory`、`deleteCategory`、文件末尾 `enum CategoryError`。泛型 `delete<T>` 仅因新方法插入而下移，逻辑未动。
- `AubadeTests/CategoryStoreTests.swift`（新增）：10 个单测覆盖 TRD 验证点 1-9、11。文件系统同步 group，自动纳入 target，未改 pbxproj。
- 未改：模型、`RecognitionNormalizer`、`PresetCategories`、`RelationshipTests`、泛型删除路径。

## 验证情况

- **单测**：`xcodebuild test`（iPhone 17 Pro 模拟器）两轮均 `** TEST SUCCEEDED **`。`CategoryStoreTests` 10/10、`RelationshipTests` 2/2（验证点10 泛型删除仍 nullify）、`PresetCategoryTests` 2/2（验证点12 预置幂等）。12 个验证点全落实（10 直接测 + 2 回归）。
- **jflow-review**：1/3 轮 PASS，双只读子 agent（SwiftData正确性/逻辑 + TRD符合度/测试覆盖/范围守界）均无阻断项。采纳 1 条高价值防御加固：`deleteCategory` 兜底查找加 `$0.id != category.id`，防「用户建同名『其他』自定义分类删它时账单被 nullify 丢分类」；加固后重跑 14 测试仍全绿。

## 遗留风险和注意事项

- **`updateCategory` 未做 name trim/空校验**：可落地空名或「食」vs「食 」绕过判重的分类。TRD 未要求，归切片03 UI 层兜空/空白校验。
- **兜底缺失防御分支（走 .nullify）无独立单测**：TRD 明言正常库不触发（预置兜底不可删），无验证点要求；可在后续切片补一条防御测试。
- **`fallbackName` 两处内联字面量**（`LedgerStore` 与 `RecognitionNormalizer`）：TRD 已明确选内联，当前合规；后续重构可抽单一来源常量规避改名漂移。
- **本片是切片03 的依赖前置**：03（分类管理 UI）消费本片 `updateCategory`/`deleteCategory` 方法签名与 `CategoryError`，签名已定稿。

## 下一次开发

1. 读取 `current.json.next_trd`，确认值仍为 `docs/design/nodes/b02-edit-loop-categories/03-category-manage-ui-trd.md`。
2. 读取该 TRD 同目录的 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `docs/design/nodes/b02-edit-loop-categories/03-category-manage-ui-trd.md`，只实现该 TRD 切片。

补充说明：
1. 读 `current.json.next_trd`，应指向 `docs/design/nodes/b02-edit-loop-categories/03-category-manage-ui-trd.md`（B02 最后一个切片）。
2. 读该 TRD 同目录 `99-slice-progress.md` 和 `.claude/jflow` handoff。
3. 打开 `03-category-manage-ui-trd.md`，只实现该切片：我的页分类区放开全部分类 + 可管理列表 + 分类编辑器 sheet（`RootTabView.swift` 改造），消费本片 Store 方法。
4. 03 是 B02 收尾切片：落地后按 `00-index.md`「收尾回归」统一复跑全量单测，再更新 DAG 节点状态。
