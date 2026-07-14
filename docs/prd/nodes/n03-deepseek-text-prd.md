# N03 DeepSeek 解析 + 文本识别

> 本节点是 Aubade v1 开发 DAG 的第四个节点，依赖 **N00 工程地基 + 数据层** 与 **N01 手动记账 + 账单列表/编辑**（均已完成）。对应技术基线模块 **M4 AI 解析层（DeepSeek Client）** + **M2.2 文本识别入口**。
>
> 里程碑意义：**第一个 AI 入口 —— 粘贴短信一键记账**。这是全局 PRD 最核心的"降本"功能：把一段工行短信/含金额文字，一步变成已入账、带分类的结构化账单，不用逐字手输。它也是后续 N04 语音 / N05 相册截图 / N06 快捷指令后台入账**共用的解析层与结果卡片**的首次落地——本节点把"取文本 → DeepSeek 解析 → 直接入账 → 结果卡片"这条链路跑通，后面三个 AI 节点只替换"文本从哪来"。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（主流程 C 文本识别、业务规则 1/2/3/6/11、验收点 4/6/11/13）、原型 markdown `docs/design/aubade-v1-prototype.md`（§4.2 记账入口、§4.3 结果卡片、§5 状态与异常）、**已实现的原型 demo `prototype/app/`（`app.js` 文本识别流程 / `data.js` 识别结果契约 —— UI 形态与交互以此 demo 为准）**、技术基线 `docs/design/aubade-v1-technical-baseline.md`（M4、§7.2 前台识别状态机、§9.1 DeepSeek 契约、§9.2 本地识别边界、§11 展开项 3/5/7）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N03 小节）。
> 代码事实来源：直接阅读 N00/N01 已落地源码（本仓库无 `.codegraph/` 索引，代码量小，逐文件阅读，行号为本 PRD 写作时快照，可能有 ±1 漂移）。
>
> **原型 demo 关键实现事实（本节点 UI 与交互直接对齐）**：文本识别入口 `app.js:323` `openTextInput`（子页：粘贴 textarea + 「读取剪贴板」按钮 + 「识别并记账」按钮，识别前先 `needKeyBlocked` 拦截）；识别中态 `app.js:350` `recognizeFlow`（全屏 spinner「正在识别文本… / DeepSeek 提取金额与分类」）；识别失败 `app.js:370` `recognizeFailed`（「没能识别出金额」对话框 → 「转手动填写」带出原文 / 「取消」回记账页）；结果卡片 `app.js:378` `openResultCard`（金额/方向/分类/时间/商户/备注 + 折叠原文，头部「✓ 已记一笔」，「删除」二次确认撤销 / 「完成」保存）；无 Key 拦截 `app.js:301` `needKeyBlocked`（「需要先配置 DeepSeek…请先在『我的 → DeepSeek API Key』里填写。手动记账不受影响。」）；文本识别结果契约 `data.js:47` `MOCK_RECOGNIZE.text`（amount/dir/time/merchant/note/raw，工行短信含尾号 1234 → cardTail）；示例文本 `data.js:55` `SAMPLE_TEXT`。

## 给用户看的摘要

做完这个节点，你的记账 App 迎来**第一个 AI 入口**——记账不再只能一个字一个字手填，**粘贴一段文字就能记一笔**：

1. **记账页「文本识别」入口真正可用**：打开「记账」Tab，点「📋 文本识别」（现在还是"敬请期待"占位），进入一个粘贴页——把一段含金额的文字（最常见是工行的消费/到账短信，也可以是支付结果、聊天里的一句话）粘进去，或点「读取剪贴板」一键带入刚复制的内容。
2. **一键识别并直接入账**：点「识别并记账」，App 把这段**文本**（只有文本，不含任何图片）发给 DeepSeek，解析出**金额、支出还是收入、时间、商户、分类**，**直接记成一笔正式账单**——不用你再逐项填。
3. **弹出结果卡片，可当场改**：入账后立刻弹出一张卡片给你看一眼——金额多少、归到哪类、什么时间、哪个商户，还能展开看"识别到的原始文本"。哪项识别得不对，当场就能改；要是这笔根本不想记，点「删除这笔」（二次确认）就撤销掉。改完的账单，剩余金额和统计（N02 做的）会立刻跟着变。
4. **没配 Key 时给明确提示，手动记账照常用**：DeepSeek 要用你自己的 API Key。还没填 Key 就点识别，会弹提示引导你去填；本节点提供一个**最小的 Key 填写入口**（填进去存在手机本地的钥匙串里）。没填 Key 完全不影响手动记账。
5. **识别不出金额不报错、不丢字**：如果这段文字压根没有有效金额，App 不会报错或乱记，而是提示你"没识别出金额"，并把**原文保留**下来，一键转成手动填写继续补录。

**这一节点不做什么**（都在后面节点）：语音记账（N04）、截图/相册选图识别（N05）、快捷指令后台入账 + 通知（N06）；我的页完整设置、DeepSeek Key 的"已配置✓/去填写"完整状态展示与分类管理、首次引导（N07）；预算/统计/剩余金额已在 N02 做完，本节点只是"识别入账后它们自动同步"。

## 目标

1. **DeepSeek 解析层（M4）**：实现 `DeepSeek Client` —— 用 `URLSession` 调 DeepSeek 的 **OpenAI 兼容 Chat Completions HTTP 接口**，**仅传文本**；输入 = 原始文本 + 当前分类清单 + 输出 JSON 约束，输出 = 金额 / 方向 / 时间 / 商户 / 卡尾号 / 分类名（技术基线 §9.1）。**以协议抽象 + mock 注入**（技术基线 M4 关键约束、§10 单测口径），真实实现与 mock 实现共用同一解析契约。
2. **解析结果归一与分类兜底（M4）**：DeepSeek 原始响应 → 结构化账单字段的映射与归一——金额转 `Decimal`（元，保 `Decimal` 精度不经 Double，对齐 `DecimalPrecisionTests`）；无时间取当前时间且**不越未来**（对齐 N01 禁未来口径）；方向识别（支出/收入）；分类名匹配本地 `LedgerCategory`（按 `name` + `direction`），**不匹配按方向兜底**到"其他"（支出）/"其他收入"（收入，`PresetCategories.income` 末项）。**解析不出有效金额 = 失败**（技术基线 §9.1）。
3. **错误类型可区分（M4）**：定义可区分的错误类型——**无 Key / 网络失败 / 超时 / 无金额 / 非法响应**（技术基线 §9.1、§7.2 状态机分支），供入口层决定"转手动补录"还是"提示配置 Key"。
4. **文本识别入口（M2.2）**：把 `RecordTabView`（`Aubade/Features/Record/RecordTabView.swift:73` 现为「敬请期待」占位）的「文本识别」接成真实入口——粘贴框 + 「读取剪贴板」（`UIPasteboard` 一键带入）+ 「识别并记账」，串起技术基线 §7.2 前台识别状态机：`idle → 识别中（禁重复提交）→ 成功入账并弹结果卡片 / 失败保留原文转手动`。
5. **识别结果直接入账 + 结果卡片**：识别成功后**直接写入 `Transaction`**（`source = .text`、落 `rawText` 原文、可含 `merchant`/`cardTail`），并弹出**结果卡片**——**复用 N01 的 `TransactionEditor`**（`Aubade/Features/Editor/TransactionEditor.swift:16`，其 `rawText` 折叠原文位、`merchant` 字段、`onDelete` 删除钩子**正是为识别结果卡片预留**，见该文件 `:13`/`:24` 注释）。卡片"完成"= 保留修改（走 update）、"删除这笔"= 撤销入账（二次确认）。
6. **无 Key 拦截 + 最小 Key 填写入口 + Keychain 封装**：识别前若未配置 Key，弹拦截提示（对齐 demo `needKeyBlocked`），提供「去填写」进入一个**最小 Key 填写 sheet**；`DeepSeek Key` 存 **Keychain**（技术基线 §7.4：不落库、不入源码、不进 UserDefaults）。做 Keychain 读写封装 + "已配置"判定（Key 非空存在）。**完整的"已配置✓/去填写"状态展示与我的页 Key 行 → N07**（本节点不改 N02 的我的页现有内容）。
7. **实时同步**：识别入账/在结果卡片改删后，账单列表、剩余金额、统计（N01/N02 已做）**自动刷新**（依赖 SwiftData `@Query` 变更驱动，与 N01/N02 同机制，本节点不新增同步逻辑）。
8. 所有读写经注入的 `ModelContext` / `LedgerStore`，**不自建 `ModelContainer`**（延续 N00/N01/N02 硬约束）；识别入账走 `LedgerStore.createTransaction`（`Aubade/Store/LedgerStore.swift:48`，已支持 `source`/`rawText`/`merchant`/`cardTail`/`imageRef` 全字段，无需改签名）。

## 当前理解

### 数据底座与写入能力已就绪（N00/N01 交付，本节点消费；N03 无需改 Schema）

- **`Transaction`**（`Aubade/Models/Transaction.swift:5`）：识别目标字段已全部就位 —— `amount: Decimal`（第 7，正值）、`direction`（第 8）、`occurredAt`（第 9，识别不到时取当前）、`category: LedgerCategory?`（第 10）、`merchant`（第 12）、`cardTail`（第 13，**仅记录、不参与统计**——识别落库但不在编辑 UI 暴露）、`source: TransactionSource`（第 14）、`rawText`（第 15，识别原文）、`imageRef`（第 16，截图用，本节点恒 nil）。
- **`TransactionSource.text`**（`Aubade/Models/Enums.swift:16`）：文本/短信入口来源枚举值**已存在**，本节点识别入账即用 `.text`。
- **`LedgerStore.createTransaction`**（`Aubade/Store/LedgerStore.swift:48`）：签名已含 `merchant`/`cardTail`/`source`/`rawText`/`imageRef`，识别入账**直接调用即可，无需改签名**；内部自动填 `createdAt`/`updatedAt`。`updateTransaction`（`:64`）供结果卡片"完成"改后回写。
- **分类清单与兜底源**：`PresetCategories.expense`（`Aubade/Persistence/PresetCategories.swift:7` = 衣/食/住/行/玩/其他）、`PresetCategories.income`（`:8` = 工作/其他收入）—— 组装 DeepSeek prompt 的"当前分类清单"与分类兜底匹配都以库中 `LedgerCategory`（`Aubade/Models/LedgerCategory.swift:8`，按 `name`+`direction`）为准。

### 可复用的 N01 编辑器体系（直接复用，结果卡片不新造）

- **`TransactionEditor`**（`Aubade/Features/Editor/TransactionEditor.swift:16`）：`:12`/`:24` 注释明确"**N03~N06 的截图/语音/文本识别结果卡片直接复用它**"。已预留：`rawText: String?` 参数（声明于 `:24`、init 于 `:35`/`:40`——**当前 body 尚未渲染它**，本节点需**新增一个折叠原文 Section 到 editor body** 消费该参数，属实现补充、不改签名，见需求范围 §5）、`merchant` 字段（`showsMerchant`，`:51`，edit 模式显示）、`onDelete: (() -> Void)?`（`:24`，删除钩子，注入即渲染"删除这笔"）。字段序（金额/方向/分类/时间/商户/备注）对齐原型 §4.3。**结果卡片 = 以识别结果预填的 `TransactionEditor`**（呈现为 edit 模式或专门的 result 模式，留 TRD）。
- **`TransactionDraft`**（`Aubade/Features/Editor/TransactionDraft.swift:7`）：纯值表单状态，金额以串保存、`parsedAmount`/`isValid`/`normalizedMerchant`/`normalizedNote` 归一——识别结果可构造为 draft 回填编辑器。
- **`EditorActions`**（`Aubade/Features/Editor/EditorActions.swift:7`）：现有 `makeUpdate`/`makeDelete`（**仅 edit 模式**）。识别入账是 **create 语义**（`createTransaction` + `source=.text`/`rawText`），需**新增识别入账的落库构造**（本节点新增，仿 `EditorActions` 风格）。
- **`RecordTabView`**（`Aubade/Features/Record/RecordTabView.swift:8`）：已有 `@Binding var selection: AppTab`（`:10`）、`@Query categories`（`:18`）、`sheet`/`editSheet` 范式（`:50`/`:131`）。「文本识别」入口现为 `placeholderEntryTitle = "文本识别"` 弹「敬请期待」（`:73`）——本节点替换为真实入口触发。
- **`CategoryStyle`**（emoji/color 主 API）、**`AmountFormat`**（plainString/signedString/color）—— 结果卡片与原文展示的配色/格式化沿用。

### 界面骨架与调试入口现状

- **文本识别入口挂载点**：`RecordTabView` 四入口网格的「📋 文本识别」`EntryButton`（`:73`）。本节点改其 action 为进入文本识别页（其余三入口"截图/语音"保持占位，属 N04/N05/N06）。
- **DEBUG 入口范式**：`DebugMenuView`（`Aubade/Debug/DebugMenuView.swift`，仅 DEBUG）已有"写预算/初始总额"调试按钮范式。本节点可在此补：**写/清 DeepSeek Key**（供真机自测真实 Key）、**mock 解析开关**（模拟成功/失败/无金额，支撑肉眼验收识别中/结果卡片/失败转手动路径，对齐 demo `simFail`/`simNoKey`）。
- **预览/单测容器**：`PersistenceController.makeInMemoryContainer()` 供文本识别页预览与结果卡片入账单测。

### 解析层的注入与可测性（技术基线 M4 关键约束）

- DeepSeek 调用以**协议抽象**（如 `TransactionParsing` 协议：`func parse(text:categories:) async throws -> ...`）+ **mock 实现**注入，真实 `DeepSeekClient`（URLSession）与 mock 实现同契约。**本节点可观察验收以 mock 注入端到端跑通 + 归一/兜底/错误分类单测为准**（用户已拍板，见已确认约定 1）；真实 Key 联网端到端由用户后续自测。
- endpoint、模型名（默认 `deepseek-chat`）、prompt 文案、JSON schema、超时值、重试策略 → **TRD 落地**（技术基线 §9.1、§11 第 3 项）。

## 涉及的现有链路

- **被扩展/接线**：
  - `RecordTabView` 「文本识别」`EntryButton`（`:73`）→ 触发真实文本识别页（替换"敬请期待"占位）；其余入口与结构不动。
  - `DebugMenuView`（DEBUG）→ 新增写/清 Key + mock 解析开关调试项（其余不动）。
- **被复用（只读消费，不改签名）**：
  - `TransactionEditor`（含 `rawText`/`merchant`/`onDelete` 预留位）、`TransactionDraft`、`EditorActions`（现有 update/delete 构造）。
  - `LedgerStore.createTransaction`/`updateTransaction`/`delete`；`PersistenceController.makeInMemoryContainer()`。
  - `Transaction`/`LedgerCategory` 模型与 `TransactionDirection`/`TransactionSource` 枚举；`PresetCategories.expense/income` 清单。
  - `CategoryStyle`（color/emoji）、`AmountFormat`（plain/signed/color）。
- **本节点新增（下游 N04/N05/N06 依赖）**：
  - **解析协议 + DeepSeek Client + mock**（`TransactionParsing` 协议、`DeepSeekClient`、mock 实现）：N04/N05/N06 复用同一解析层。
  - **解析结果归一/兜底纯函数**（响应 → 结构化字段：金额/时间/方向/分类兜底）与**错误类型 enum**。
  - **识别入账的落库构造**（create + `source`/`rawText`）与**前台识别状态机驱动**（idle/识别中/成功/失败）。
  - **文本识别页** + **结果卡片**（复用 `TransactionEditor`）+ **无 Key 拦截提示** + **最小 Key 填写 sheet**。
  - **Keychain 封装**（Key 读写 + "已配置"判定）：N06 后台读 Key、N07 完整设置界面复用。
- **无既有调用方冲突**：解析层/识别页/Key sheet 为全新代码；除给「文本识别」入口接线、`DebugMenuView` 补调试项外，不改 N00/N01/N02 的模型字段、`LedgerStore` 现有方法签名、`TransactionEditor` 签名（仅传入其已有参数）、N02 的我的页/统计/汇总卡逻辑。

## 需求范围

### 1. DeepSeek 解析层（M4，协议抽象 + mock）
- 定义解析**协议**（输入：原始文本 + 当前分类清单；输出：金额/方向/时间/商户/卡尾号/分类名的结构化结果或抛错）。
- **真实实现**：`URLSession` 调 DeepSeek OpenAI 兼容 Chat Completions 接口，Key 来自 Keychain，仅传文本，要求返回结构化 JSON；带**明确超时**。
- **mock 实现**：供单测/预览/DEBUG 演示，可模拟成功（对齐 `MOCK_RECOGNIZE.text`：256 元支出、京东商城、尾号 1234、时间 15:22）/ 失败 / 无金额。
- endpoint/模型名/prompt/JSON schema/超时/重试数值 **留 TRD**（技术基线 §11 第 3 项）。

### 2. 解析结果归一与分类兜底（M4，纯函数、可单测）
- **金额**：DeepSeek 金额 → `Decimal`（元），不经 Double；解析不出有效金额 → 判**失败**。
- **时间**：解析出时间则用之，**不到取当前时间**；**不越未来**（若解析出未来时间，clamp 到当前，与 N01 禁未来一致）。
- **方向**：区分支出/收入（工行短信"支出/消费" vs "收入/入账"语义）。
- **分类兜底**：DeepSeek 分类名匹配库中 `LedgerCategory`（`name`+`direction`）；不匹配 → 按方向兜底到"其他"/"其他收入"；方向与分类矛盾时以方向为准取该方向兜底分类。
- **卡尾号**：解析出则落 `cardTail`（仅记录，不在结果卡片编辑 UI 暴露）。

### 3. 错误类型（M4）
- 定义可区分错误：**无 Key / 网络失败 / 超时 / 无金额 / 非法响应**。
- 入口层据此分支：无 Key → 拦截提示配置；无金额 → 保留原文转手动；网络/超时/非法响应 → 提示失败并保留原文（可转手动/重试，重试策略留 TRD）。

### 4. 文本识别入口与状态机（M2.2，对齐 demo `openTextInput`/`recognizeFlow`）
- 从记账页「文本识别」进入文本识别页：**粘贴 textarea**（placeholder 举例工行短信）+ **「读取剪贴板」**（`UIPasteboard.general.string` 一键带入，空剪贴板给轻提示）+ **「识别并记账」**。
- 点识别前先**无 Key 拦截**（见 §6）；文本为空给提示。
- **识别中态**：明确的"识别中" spinner（对齐 demo「正在识别文本… / DeepSeek 提取金额与分类」），**禁止重复提交**。
- 识别页的呈现方式（push/sheet）、识别中态样式 **留 TRD**；PRD 只约束上述可观察行为。

### 5. 识别成功：直接入账 + 结果卡片（复用 TransactionEditor）
- 识别成功 → **直接 `createTransaction` 入账**（`source=.text`、落 `rawText`、含解析出的 `merchant`/`cardTail`/`category`）。
- 弹出**结果卡片**：复用 `TransactionEditor`，头部示意"已记一笔"（对齐 demo `justAdded`），预填识别结果，**折叠展示识别原文**（`rawText`），字段可当场改。
- **「完成」** = 保留修改回写（走 update）；**「删除这笔」** = 撤销入账，**二次确认**（对齐 demo `openResultCard` r-del）。
- 改/删后账单列表、剩余、统计自动刷新（§7 同步，不新增逻辑）。
- 结果卡片的呈现载体与 `TransactionEditor` 复用形态（edit 模式 vs 新增 result 模式）**留 TRD**。

### 6. 无 Key 拦截 + 最小 Key 填写 + Keychain（M4 密钥边界）
- 识别前若 Keychain 无有效 Key → 弹拦截（对齐 demo `needKeyBlocked` 文案："识别类记账要用到 DeepSeek…手动记账不受影响"），提供「去填写」。
- **最小 Key 填写 sheet**：输入框 + 保存，写 Keychain；"已配置"判定 = Key 非空存在。
- **Keychain 封装**：读/写/删 DeepSeek Key 的最小接口（技术基线 §11 第 5 项）。
- **不做**：我的页 Key 行、"已配置✓/去填写"完整状态卡、Key 校验/联网测活 → **N07**。本节点 Key sheet 是"能填能存能被识别读到"的最小闭环。

### 7. 识别失败：保留原文转手动（对齐 demo `recognizeFailed`）
- 无金额/网络失败/超时/非法响应 → **不报错崩溃、不丢原文**；提示对应失败原因。
- 无金额场景：提示"没识别出金额，原文已保留"，一键**转手动填写**（用识别原文预填 `note`/供参考，走 N01 手动表单/编辑器）。
- 网络类失败：提示失败，原文保留，可重试或转手动（重试策略留 TRD）。

### 8. DEBUG 调试入口（支撑 mock 端到端肉眼验收）
- 在 `DebugMenuView` 补：**写/清 DeepSeek Key**（真机自测真实 Key）、**mock 解析开关**（成功/失败/无金额），使模拟器/真机能肉眼走通识别中 → 结果卡片 → 失败转手动 → 无 Key 拦截全路径。

### 9. 单元测试（技术基线 §10 单测口径）
- DeepSeek 响应 → 结构化字段的**映射与归一**：金额转 Decimal、无时间取当前、方向、分类兜底（不匹配 → 其他/其他收入、方向矛盾以方向为准）。
- **错误类型**判定：无金额/非法响应/（mock 模拟的）网络失败可区分。
- 识别入账落库：`source=.text`、`rawText` 保留、金额 `Decimal` 无浮点误差。
- 以 **mock 解析实现**注入，脱离网络与真实 Key。

## 不做什么

以下均属其他节点，本节点**不实现**：
- **语音记账**（Speech 转文字）→ N04；**截图·相册选图 + Vision OCR** → N05；**快捷指令 App Intents 后台入账 + 通知** → N06。本节点只做**文本**入口与共用解析层。
- **我的页完整设置**：DeepSeek Key 的"已配置✓/去填写"完整状态展示与我的页 Key 行、Key 联网校验、分类管理界面、首次启动引导、通知开关、权限申请 → N07。本节点 Key 只做"最小填写 sheet + Keychain 读写"。
- **图片/语音相关**：`imageRef` 落库、原图临时留存与清理 → N05/N06/M9。
- **真实 Key 联网端到端作为本节点闭环门禁**：本节点可观察验收以 mock 注入端到端 + 归一/错误单测为准（用户已拍板）；真实 Key 联网解析由用户后续自测，不阻塞节点完成。
- 不改动 N00/N01/N02 的模型字段、`LedgerStore` 现有方法签名、`TransactionEditor` 签名、`PersistenceController` 容器配置、N01 记账/账单/编辑既有行为、N02 统计/剩余/汇总卡逻辑。

## 验收标准

（对齐 DAG 中 N03 的"退出标准（可观察）"与全局 PRD 验收点 4 / 6 / 11 / 13 的前台部分。可用模拟器 mock 注入肉眼观察，解析归一/兜底/错误另以单元测试佐证；真实 Key 联网端到端为用户后续自测。）

1. **文本识别入账（PRD 验收点 4，mock 注入观察）**：在记账页点「文本识别」进入粘贴页，粘贴/读剪贴板带入一条工行消费短信（或含金额文字），点「识别并记账」，经"识别中"后**直接生成一笔已入账账单**，并弹出结果卡片。mock 注入下**以样例工行短信为准**（对齐 `data.js:55` `SAMPLE_TEXT` 与 `data.js:47` `MOCK_RECOGNIZE.text`）：方向=支出、金额=256（`Decimal` 无浮点误差）、时间=短信时间（无则当前且不越未来）、商户=京东商城、卡尾号=1234。（真实任意短信的解析准确性由用户后续用真实 Key 自测，见已确认约定 1；mock 恒返回样例定值，验收观察链路与字段落库正确性，非通用真解析。）
2. **自动带分类且可改（PRD 验收点 6 分类部分）**：识别入账的账单**带一个自动分类**（DeepSeek 分类名匹配本地分类，不匹配兜底"其他"）；在结果卡片可改分类/金额/方向/时间/商户/备注，「完成」后改动生效；改后统计与剩余（N02）自动刷新。
3. **结果卡片撤销**：结果卡片点「删除这笔」经二次确认后撤销入账，账单不再存在，列表/剩余/统计同步。
4. **识别原文可见**：结果卡片可展开查看"识别到的原始文本"（`rawText`）。
5. **无 Key 拦截 + 最小填写（PRD 验收点 11 前台部分）**：Keychain 无 Key 时点识别，弹明确拦截提示且**不进行识别**；「去填写」进入 Key 填写 sheet，填入并保存后（写 Keychain），再次识别不再被拦截；**全程手动记账不受影响**（可正常手动记一笔）。
6. **无法解析金额不报错（PRD 验收点 13 前台部分）**：对一段无有效金额的文字识别，**不报错崩溃、不误记账单**，提示"没识别出金额、原文已保留"，可一键转手动填写且原文带入。
7. **网络类失败保留原文**：mock 模拟网络失败/超时/非法响应时，提示对应失败、原文保留、不生成脏账（可转手动/重试）。
8. **解析归一单测**：单测覆盖——金额→Decimal、无时间取当前、方向识别、分类兜底（不匹配→其他/其他收入、方向矛盾以方向为准）、错误类型可区分；均以 mock 注入、脱离网络。
9. **协议抽象与隐私边界**：DeepSeek 调用经协议注入（mock 可替换真实实现）；解析只发**文本**（无图片/语音）；Key 仅存 Keychain（不落 SwiftData、不进源码/日志）。
10. **不越界**：无语音/截图/相册入口；我的页除 N02 已有内容外不新增正式 Key 行（仅最小填写 sheet 从拦截进入）；不改 N01/N02 既有行为；不建统计缓存。

## 已确认约定

（以下在 PRD 评审前已由用户拍板或由已实现原型 demo / 技术基线定死，作为既定实现约束，非待确认项。TRD 直接据此落地。）

1. **验收深度 = Mock 端到端打通 + 单测**（用户已拍板）：本节点"可观察验收"以 **mock 解析实现注入下文本识别链路完整跑通**（粘贴/读剪贴板 → 识别中 → 入账 → 结果卡片可改/删 → 失败转手动 → 无 Key 拦截）+ **归一/兜底/错误分类单测**为准。真实 DeepSeek Key 联网端到端解析作为用户后续自测，不阻塞本节点闭环。默认模型 `deepseek-chat` + JSON output mode（具体 TRD 落地）。
2. **Key 入口 = 最小正式填写 sheet + Keychain 封装**（用户已拍板）：做 Keychain 读写封装 + 一个**最小 Key 填写 sheet**（从文本识别"未配置 Key"拦截的「去填写」进入，可真机填真实 Key 自测）。**不改 N02 的我的页**；完整"已配置✓/去填写"状态展示与我的页 Key 行留 **N07**。
3. **文本识别 UI 形态以 demo 为准**：粘贴框 + 读剪贴板 + 识别按钮、全屏识别中 spinner、结果卡片（金额/方向/分类/时间/商户/备注 + 折叠原文 + 已记一笔/删除/完成）、失败对话框转手动、无 Key 拦截对话框 —— 均由 demo `app.js` 定死（`openTextInput`/`recognizeFlow`/`openResultCard`/`recognizeFailed`/`needKeyBlocked`），非待确认项。
4. **结果卡片复用 `TransactionEditor`**：不新造识别结果卡片组件，复用其已预留的 `rawText`/`merchant`/`onDelete`（`TransactionEditor.swift:24`）。呈现形态（edit 模式或新增 result 模式）TRD 定。
5. **解析层协议抽象 + mock 注入**（技术基线 M4 硬约束）：DeepSeek 以协议注入，便于单测与 N04/N05/N06 复用；解析不出金额 = 失败，走保留原文转手动。
6. **卡尾号仅记录不编辑**：`cardTail` 解析出即落库（`Transaction.cardTail`），但**不在结果卡片编辑 UI 暴露**（与模型注释"仅记录、不参与分账户统计"及原型 §4.3 字段序一致）。
7. **隐私边界**：文本识别仅把**文本**发 DeepSeek（本节点无图片/语音）；Key 仅存 Keychain（技术基线 §7.4）。
8. **无 Key 拦截文案不得指向 N07 我的页 Key 行**（TRD 守则）：demo `needKeyBlocked`（`app.js:301`）原文引导"去『我的 → DeepSeek API Key』填写"并跳我的页——但我的页 Key 行属 **N07**，本节点未建。故本节点拦截的「去填写」**直接开最小 Key sheet**，文案裁去"我的→Key"指向，避免死链。TRD 落地拦截文案与路由时须守住此切分。
9. **网络类失败的提示文案/重试入口 TRD 补齐**（TRD 守则）：demo `simFail` 仅覆盖"无金额"路径，未区分网络失败/超时/非法响应的视觉。这三类错误类型是技术基线 §9.1 强制、属 M4 范围（非臆造），本节点定义错误类型并保证"不报错、保留原文"；其**提示文案与是否提供重试入口的具体设计留 TRD**（技术基线 §11 重试策略待定）。
