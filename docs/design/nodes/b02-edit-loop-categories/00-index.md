# B02 编辑闭环：最近记录删除 + 自定义分类 · TRD 索引

> 节点 PRD：`docs/prd/nodes/b02-edit-loop-categories-prd.md`（R3 + R4，已获用户评审通过）。
> 批次上游：批次 PRD `docs/prd/batch01-feedback-fixes-prd.md`、原型 `docs/design/batch01-feedback-fixes-prototype.md`、技术基线 `docs/design/batch01-feedback-fixes-technical-baseline.md`、DAG `docs/design/batch01-feedback-fixes-dev-dag.md`（决策 D1/D2/D3）。
> 代码事实来源：本仓库无 `.codegraph/`，行号来自本次手动读源码核实（可能 ±1 漂移）。
> 开放项已定：预置分类锁全部字段（禁删、禁改名、禁改图标/颜色），PRD 默认口径，用户未要求放开。

## 切片划分与顺序

按"UI 独立块先行、逻辑焊死后接 UI"拆三片。R3 与 R4 无代码耦合，可独立验证；R4 内部 Store 能力（02）是 UI（03）的依赖，必须先落。

| 序号 | 切片 | 负责 | 依赖 | 主要产物 |
|---|---|---|---|---|
| 01 | R3 最近记录删除 | 记账页最近记录左滑删除 + 二次确认，交互对齐账单页 | 无 | `RecordTabView.swift` 改造 |
| 02 | R4 分类 Store 能力 | `updateCategory` / 分类删除（预置保护 + 引用计数 + 删已引用先转对应兜底再删） | 无 | `LedgerStore.swift` 新增方法 + 单测 |
| 03 | R4 分类管理 UI | 我的页分类区放开全部分类 + 可管理列表 + 分类编辑器 sheet | 02 | `RootTabView.swift` 改造 |

- 01 与 02 相互独立，谁先都行；03 依赖 02 的 Store 方法签名定稿。
- 三片都不改数据模型、不动识别链路、不做视觉重做（B04 范畴）。

## 切片文档

- [01 R3 最近记录删除](01-recent-delete-trd.md)
- [02 R4 分类 Store 能力](02-category-store-trd.md)
- [03 R4 分类管理 UI](03-category-manage-ui-trd.md)
- [切片进度](99-slice-progress.md)

## 收尾回归（PRD 验收 11）

三片全部落地后，收尾统一复跑全量单测，确认无回归：B01 剩余总额口径、既有账单/识别/统计功能、`RelationshipTests`（泛型删除仍 nullify）、`PresetCategoryTests`（预置幂等）。数据模型无变更，回归面主要是分类删除新路径与最近记录结构改动的外溢。此回归归最后落地的切片收尾执行。

## 全局不做什么

- 不改 `LedgerCategory` / `Transaction` 模型字段，无 SwiftData 迁移（迁移是 B03）。
- 不动 DeepSeek prompt / `RecognitionEntry` / `RecognitionNormalizer` 逻辑（R4 自动分类天然生效，验证归 B03）。
- 不引入暖白/晨曦/珊瑚青绿视觉 token（R6/B04）。
- 不改账单页删除、不改预置 seed / 幂等逻辑。
- 不引入原型自造侧滑手势 `swipeRow`，对齐账单页原生 `List.swipeActions`。
