# N03 DeepSeek 解析 + 文本识别 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n03-deepseek-text-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动记账/编辑器 + N02 剩余/统计（提交 f1257e6）。
> UI 与交互事实来源：已实现原型 demo `prototype/app/`（`app.js` 文本识别流程 / `data.js` 识别契约）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 切片划分与顺序

N03 拆成 **3 个单一职责切片**，按"先纯逻辑底座、再入口闭环、后结果卡片精修"排序，每片可独立编译运行与验收：

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | M4 解析底座（协议 + 归一兜底 + 错误 + mock + 真实 Client + Keychain） | DeepSeek 解析层的**纯逻辑地基**：解析协议 + 响应→结构化字段归一/分类兜底纯函数 + 可区分错误类型 + mock 实现 + 真实 `DeepSeekClient`(URLSession) + `KeychainStore`（Key 读写 / "已配置"判定）。全部可单测、零 UI | N00/N01 | 验收 8、9（协议/隐私/单测），为 1/2/6/7 提供底座 |
| 02 | 文本识别入口 + 无 Key 拦截 + 最小 Key sheet + 识别状态机 | `RecordTabView`「文本识别」接线；文本识别页（粘贴 textarea + 读剪贴板 + 识别并记账）；无 Key 拦截 → 最小 Key sheet；识别中状态机（禁重复提交）；识别成功 → **直接入账**（本片入账后回记账页，最近记录可见）；失败 → 提示原因 | 切片 01 | 验收 1（入账链路）、5（无 Key 拦截+填写）、7（失败提示半） |
| 03 | 结果卡片（复用 TransactionEditor）+ 失败转手动 + DEBUG | 识别成功后弹**结果卡片**：复用 `TransactionEditor` 的 `.edit(tx)` 模式 + 新增折叠原文 Section（消费 `rawText`）+ `onDelete` 二次确认撤销入账；失败**转手动**带原文预填；`DebugMenuView` 补写/清 Key + mock 解析开关 | 切片 02 | 验收 2、3、4、6、7（转手动）、10 |

### 为什么这样拆

- **切片 01 是纯逻辑底座**：解析协议 / 归一兜底 / 错误分类 / mock / 真实 Client / Keychain 全无 UI 依赖，可完全脱网单测（PRD 验收 8/9、已确认约定 1/5）。这是 N04/N05/N06 共用的解析层首次落地，先把契约与单测焊死，风险最低、后两片直接消费。
- **切片 02 打通入口主链路**：接线 + 识别页 + Key 边界 + 状态机 + 入账，交付"粘贴→识别→入账"最短可观察闭环。结果卡片精细交互（改/删/折叠原文）留切片 03，避免本片过大。本片识别成功后先回记账页（最近记录 +1），肉眼即可验入账成功。
- **切片 03 精修结果卡片 + 失败分支 + 调试**：结果卡片复用 N01 `TransactionEditor`（新增折叠原文 Section、注入 onDelete 撤销），失败转手动带原文，DEBUG 补 Key/mock 开关支撑全路径肉眼验收。全部建立在前两片之上，无回改底座与状态机。

## 切片文件

- `01-parsing-core-trd.md`
- `02-text-entry-key-trd.md`
- `03-result-card-fallback-debug-trd.md`

## 全节点共用的关键约束（三片都遵守）

1. **不自建 `ModelContainer`**：一律注入 `ModelContext` / `LedgerStore(context)`，禁链式 `container().mainContext`（N00 SIGTRAP 陷阱，见 memory 与 `PersistenceController.swift:7`、`ModelCRUDTests.swift:9-10` 注释）。识别入账走 `LedgerStore.createTransaction`（`:48`，已含全字段，**不改签名**）。
2. **金额纯 `Decimal`**：解析金额转 `Decimal` 不经 `Double`（`Decimal(string:)`），对齐 `DecimalPrecisionTests` 与 `TransactionDraft.parsedAmount`（`:38`）。
3. **解析层协议抽象 + mock 注入**（技术基线 M4 硬约束）：DeepSeek 调用经 `TransactionParsing` 协议注入；真实 `DeepSeekClient` 与 mock 同契约。**可观察验收以 mock 端到端 + 单测为准**，真实 Key 联网为用户后续自测，不阻塞节点（PRD 已确认约定 1）。
4. **解析不出有效金额 = 失败**：不误记脏账、不丢原文（技术基线 §9.1、PRD §2/§7）。
5. **隐私边界**：文本识别仅把**文本**发 DeepSeek（无图片/语音）；Key 仅存 **Keychain**，不落 SwiftData、不进源码/UserDefaults/日志（技术基线 §7.4、PRD 已确认约定 7）。
6. **时间不越未来**：解析出的时间若晚于当前，clamp 到当前（对齐 N01 禁未来口径 `TransactionEditor.swift:144` `in: ...Date()`）。
7. **结果卡片复用 `TransactionEditor`**：不新造识别结果卡片组件；走 `.edit(tx)` 模式（识别已先入账、tx 已在库），新增折叠原文 Section 消费其已声明的 `rawText` 参数（`:24`，**不改签名**），`onDelete` 注入撤销（PRD 已确认约定 4/6）。
8. **配色/格式化复用**：金额走 `AmountFormat`，分类色/emoji 走 `CategoryStyle`。
9. **无 Key 拦截文案不指向 N07 我的页 Key 行**：「去填写」直开最小 Key sheet，裁去 demo `needKeyBlocked`（`app.js:301`）的"我的→Key"指向，避免死链（PRD 已确认约定 8）。
10. **不越界**：语音 → N04；截图/相册 → N05；快捷指令后台 → N06；我的页完整 Key 状态展示 / 分类管理 / 首次引导 / 通知 → N07。本节点 Key 只做"最小填写 sheet + Keychain 读写"；不改 N01/N02 既有行为、`imageRef` 恒 nil。
