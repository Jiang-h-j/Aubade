# TRD 01 - M4 解析底座（协议 + 归一兜底 + 错误 + mock + 真实 Client + Keychain）

> 节点 PRD：`docs/prd/nodes/n03-deepseek-text-prd.md`。上游：N00 数据层 + N01 编辑器（f1257e6）。
> 行号为写作时快照，可能 ±1 漂移。

## 给用户看的摘要

这一片是"看不见的地基"——它本身没有界面，但把后面两片要用的**解析大脑**先搭好、用单测焊死：

- 把「一段文字 → 金额/方向/时间/商户/卡尾号/分类」这条解析能力，定义成一个可替换的协议：真机上用真实 DeepSeek，测试和演示时用假的（mock）替换，两者说同一种"话"。
- 把 DeepSeek 返回的原始结果**归一**成能直接入账的字段：金额转成精确的 `Decimal`（不丢分）、没时间就用当前时间且不会记到未来、分类名对不上就自动兜底到"其他/其他收入"。
- 把可能出错的情况分门别类：没配 Key / 没网 / 超时 / 没识别出金额 / 返回乱码——后面识别页据此决定"提示配 Key"还是"转手动补录"。
- 把 DeepSeek 的 API Key 安全存进手机钥匙串（Keychain），并能判断"到底配没配"。

这片**做完你还看不到新界面**（下一片才有）；它的正确性全部由单元测试证明。

## 本 TRD 负责什么

M4 解析层的**纯逻辑地基**（PRD 目标 1/2/3/6-Keychain，需求范围 §1/§2/§3/§6-Keychain/§9）：

1. **解析协议** `TransactionParsing`：`parse(text:categories:) async throws -> ParsedTransaction`，输入原文 + 当前分类清单，输出结构化结果或抛可区分错误。
2. **解析结果值类型** `ParsedTransaction`（DeepSeek 原始字段的中间载体）+ **归一纯函数** `RecognitionNormalizer`（原始 → 可落库字段：金额 Decimal、时间兜当前不越未来、方向、分类兜底、卡尾号）。
3. **可区分错误** `RecognitionError` enum：无 Key / 网络失败 / 超时 / 无金额 / 非法响应。
4. **mock 实现** `MockTransactionParser`：可配成功（对齐 `MOCK_RECOGNIZE.text`）/ 无金额 / 网络失败 / 超时 / 非法响应，供单测/预览/DEBUG。
5. **真实实现** `DeepSeekClient`：`URLSession` 调 DeepSeek OpenAI 兼容 Chat Completions，Key 取自 Keychain，仅传文本，JSON output。（编译交付；联网验收由用户后续自测。）
6. **Keychain 封装** `KeychainStore`：DeepSeek Key 读/写/删 + "已配置"判定。

## 当前代码事实与上下游

- **模型（消费，不改）**：`Transaction`（`Aubade/Models/Transaction.swift:5`）字段 `amount: Decimal`（`:7`，正值）、`direction`（`:8`）、`occurredAt`（`:9`）、`category: LedgerCategory?`（`:10`）、`merchant`（`:12`）、`cardTail`（`:13`）、`source`（`:14`）、`rawText`（`:15`）。`TransactionSource.text` 已存在（`Enums.swift:16`）。`TransactionDirection`（`Enums.swift:4`）= `.expense/.income`。
- **分类源（消费）**：`LedgerCategory`（`Aubade/Models/LedgerCategory.swift:8`）按 `name`（`:10`）+ `direction`（`:11`）匹配。`PresetCategories.expense`（`Persistence/PresetCategories.swift:7` = 衣/食/住/行/玩/**其他**）、`PresetCategories.income`（`:8` = 工作/**其他收入**）——兜底目标即各方向末项。
- **金额精度基准**：`TransactionDraft.parsedAmount`（`Editor/TransactionDraft.swift:38`）用 `Decimal(string:)`（locale 无关、以 `.` 为小数点）；本片金额归一沿用同构造，保 Decimal 不经 Double（对齐 `DecimalPrecisionTests`）。
- **禁未来口径**：N01 编辑器 `DatePicker(in: ...Date())`（`TransactionEditor.swift:144`）——本片时间归一 clamp 未来到当前，语义一致。
- **单测范式**：`AubadeTests/*` 均 `@MainActor final class ... XCTestCase`；涉库测试**必须持有 `container`**（`ModelCRUDTests.swift:9-11` setUp/tearDown），禁 `makeInMemoryContainer().mainContext` 链式（悬垂 context SIGTRAP）。纯函数测试可不建容器；分类兜底需库中 `LedgerCategory` 参与匹配则建内存容器 + `PresetCategories.seedIfNeeded`。
- **demo 契约**：`data.js:47` `MOCK_RECOGNIZE.text` = `{amount:256, dir:'expense', cat:'其他', time:'2026-07-10 15:22', merchant:'京东商城', raw:工行短信(尾号1234)}`；`data.js:55` `SAMPLE_TEXT`。**mock 恒返回此定值**（cat 为"其他"）——验收观察链路与字段落库，非通用真解析。
- **DeepSeek 契约（技术基线 §9.1）**：默认模型 `deepseek-chat`、OpenAI 兼容 `/chat/completions`、JSON output mode。endpoint/prompt/schema/超时/重试数值本片落地（见下）。

## 设计方案

新建目录 `Aubade/Features/Recognition/`（本节点解析层与识别页归属；与 `Analytics/` 平级）。纯逻辑文件放其下 `Parsing/` 子目录，Keychain 放 `Aubade/Persistence/`（与 `PersistenceController` 同层，属基础设施）。

### 1. 解析结果值类型 + 协议（`Recognition/Parsing/TransactionParsing.swift`）

```
/// DeepSeek 解析出的**原始中间结果**（未归一：金额是串、时间可空、分类名是自由文本）。
/// 归一（→ Decimal/兜时间/兜分类）由 RecognitionNormalizer 负责，协议只管"取到什么"。
struct ParsedTransaction {
    let amountText: String        // DeepSeek 返回的金额原文（如 "256.00"）；空/非数→归一判无金额
    let direction: TransactionDirection
    let occurredAt: Date?         // 解析不到为 nil（归一取当前）
    let merchant: String?
    let cardTail: String?
    let categoryName: String?     // DeepSeek 给的分类名自由文本（归一按 name+direction 匹配库/兜底）
}

/// 文本 → 结构化账单的解析能力。真实(DeepSeekClient)与 mock 同契约，注入以便单测与 N04~N06 复用。
protocol TransactionParsing {
    /// - categories: 当前库中分类清单（组 prompt 的"可选分类"提示；归一兜底在 Normalizer）。
    /// - 解析不出有效金额、网络失败、超时、非法响应、无 Key 时抛 RecognitionError。
    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction
}
```

- 协议只吐 `ParsedTransaction`（原始），**归一与落库分离**——单测可分别测"解析取值"与"归一规则"。

### 2. 可区分错误（`Recognition/Parsing/RecognitionError.swift`）

```
/// 识别失败的可区分类型，供入口层分支（PRD §3、技术基线 §7.2）。
enum RecognitionError: Error, Equatable {
    case noKey            // Keychain 无有效 Key → 拦截提示配置（不进行识别）
    case network          // 连接失败/无网络 → 提示失败、保留原文
    case timeout          // 超时 → 提示失败、保留原文
    case noAmount         // 解析不出有效金额 → 保留原文转手动（PRD 已确认约定：无金额=失败）
    case invalidResponse  // 非法响应（非 JSON/缺字段/HTTP 非 2xx）→ 提示失败、保留原文
}
```

- 入口层映射（切片 02/03 消费）：`noKey`→拦截；`noAmount`→转手动带原文；`network/timeout/invalidResponse`→提示对应失败+保留原文（可重试/转手动）。

### 3. 归一纯函数（`Recognition/Parsing/RecognitionNormalizer.swift`）

无状态 enum，注入数据 + `now`（测试可注入固定时刻），不触库、不联网：

```
enum RecognitionNormalizer {
    /// 金额：ParsedTransaction.amountText → Decimal（元，不经 Double）。空/非数/<=0 → 抛 .noAmount。
    static func amount(_ text: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let d = Decimal(string: trimmed), d > 0 else {
            throw RecognitionError.noAmount
        }
        return d
    }

    /// 时间：nil → now；晚于 now → clamp 到 now（禁未来，对齐 N01）。
    static func occurredAt(_ date: Date?, now: Date) -> Date {
        guard let date else { return now }
        return date > now ? now : date
    }

    /// 分类兜底：按 name+direction 匹配库中分类；不匹配 → 该方向兜底（支出"其他"/收入"其他收入"）。
    /// 方向与分类矛盾（匹配到的分类方向≠direction）也以 direction 为准取兜底。
    static func category(name: String?, direction: TransactionDirection,
                         in categories: [LedgerCategory]) -> LedgerCategory? {
        if let name, let hit = categories.first(where: { $0.name == name && $0.direction == direction }) {
            return hit
        }
        let fallbackName = (direction == .expense) ? "其他" : "其他收入"
        return categories.first { $0.name == fallbackName && $0.direction == direction }
    }
}
```

- 兜底名"其他"/"其他收入"取自 `PresetCategories.expense.last`/`income.last`（`:7`/`:8`），与库预置一致；库里没有该兜底分类（异常态）返回 nil，落库为未分类（`Transaction.category` 可空，`Transaction.swift:10`）。
- `amount` 抛 `.noAmount` 是"无金额=失败"的落点；调用方（入口层）捕获转手动。

### 4. mock 实现（`Recognition/Parsing/MockTransactionParser.swift`）

```
/// 可配置行为的 mock，供单测/预览/DEBUG（PRD §1、已确认约定 1）。
struct MockTransactionParser: TransactionParsing {
    enum Behavior { case success, noAmount, network, timeout, invalidResponse }
    var behavior: Behavior = .success

    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction {
        switch behavior {
        case .network:         throw RecognitionError.network
        case .timeout:         throw RecognitionError.timeout
        case .invalidResponse: throw RecognitionError.invalidResponse
        case .noAmount:        throw RecognitionError.noAmount   // 或返回 amountText="" 由归一抛（见验证点）
        case .success:
            // 对齐 data.js:47 MOCK_RECOGNIZE.text 定值（工行短信样例）
            return ParsedTransaction(
                amountText: "256.00", direction: .expense,
                occurredAt: <解析 "2026-07-10 15:22">, merchant: "京东商城",
                cardTail: "1234", categoryName: "其他")
        }
    }
}
```

- `success` 恒返回样例定值（含 cardTail 1234），对齐 demo；`noAmount` 兼顾两种口径（直接抛 / 返回空 amountText 让归一抛），单测各覆盖一条。

### 5. 真实 DeepSeekClient（`Recognition/Parsing/DeepSeekClient.swift`）

`URLSession` 调 OpenAI 兼容接口。**编译交付、结构正确即可**，联网验收由用户后续自测（已确认约定 1）：

```
struct DeepSeekClient: TransactionParsing {
    var keychain: KeychainStore = .shared
    var session: URLSession = .shared
    var model = "deepseek-chat"
    var endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    var timeout: TimeInterval = 20          // 明确超时（技术基线 §11 第 3 项落地值）

    func parse(text: String, categories: [LedgerCategory]) async throws -> ParsedTransaction {
        guard let key = keychain.deepSeekKey, !key.isEmpty else { throw RecognitionError.noKey }
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encodeBody(text: text, categories: categories)  // messages + response_format:{type:"json_object"}
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError where e.code == .timedOut { throw RecognitionError.timeout }
        catch { throw RecognitionError.network }
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RecognitionError.invalidResponse
        }
        return try decode(data)   // 解 choices[0].message.content 里的 JSON → ParsedTransaction；缺字段→invalidResponse
    }
}
```

- **prompt 骨架**（`encodeBody`）：system 交代"从文本提取记账字段，只输出 JSON"，user 拼 `文本 + 可选分类名清单（categories.map name）+ 目标 JSON schema`（字段：amount/direction/occurredAt/merchant/cardTail/category）。仅传文本，无图片/语音（隐私边界）。
- **重试策略**：本节点**不做自动重试**（失败即抛，入口层给"重试"按钮由用户手动再触发）——避免对计费 API 隐式重试放大成本；技术基线 §11"重试策略待定"落为"手动重试"。此决策写入本 TRD，切片 02 据此设计失败态。
- endpoint/model/timeout 为常量默认值，DEBUG 或 N07 可覆盖（本节点不做设置界面）。

### 6. Keychain 封装（`Aubade/Persistence/KeychainStore.swift`）

Security 框架最小封装，仅存 DeepSeek Key：

```
/// DeepSeek API Key 的 Keychain 读写（技术基线 §7.4：不落库/不进 UserDefaults/不入源码）。
/// 最小闭环：读/写/删 + "已配置"判定。完整状态展示与我的页 Key 行 → N07。
struct KeychainStore {
    static let shared = KeychainStore()
    private let service = "com.aubade.deepseek"
    private let account = "api-key"

    var deepSeekKey: String? { get { /* SecItemCopyMatching → String */ } }
    func setDeepSeekKey(_ key: String) { /* SecItemDelete 再 SecItemAdd（写侧唯一化，对称 setBudget） */ }
    func clearDeepSeekKey() { /* SecItemDelete */ }
    var isConfigured: Bool { (deepSeekKey?.isEmpty == false) }   // "已配置" = 非空存在
}
```

- 写用"先 delete 再 add"保证唯一（与 `LedgerStore.setBudget` 写侧唯一化同风格，`LedgerStore.swift:83`）。
- `isConfigured` 即无 Key 拦截的判据（切片 02 消费）。**不做 Key 格式/联网校验**（→ N07）。

## 修改点

| 文件 | 改动 |
|---|---|
| `Aubade/Features/Recognition/Parsing/TransactionParsing.swift` | **新增**：`ParsedTransaction` + `TransactionParsing` 协议 |
| `Aubade/Features/Recognition/Parsing/RecognitionError.swift` | **新增**：`RecognitionError` enum（5 类） |
| `Aubade/Features/Recognition/Parsing/RecognitionNormalizer.swift` | **新增**：`amount`/`occurredAt`/`category` 归一纯函数 |
| `Aubade/Features/Recognition/Parsing/MockTransactionParser.swift` | **新增**：可配置 mock |
| `Aubade/Features/Recognition/Parsing/DeepSeekClient.swift` | **新增**：URLSession 真实实现（编译交付） |
| `Aubade/Persistence/KeychainStore.swift` | **新增**：Keychain 读写 + isConfigured |
| `AubadeTests/RecognitionNormalizerTests.swift` | **新增**：归一/兜底/错误单测（见验证点） |
| `AubadeTests/MockParserTests.swift` | **新增**：mock 各行为 → 对应错误/成功值 |

不改任何 N00/N01/N02 现有文件（本片全为新增文件）。

## 验证点

单测（`@MainActor`；分类兜底测试建内存容器 + `PresetCategories.seedIfNeeded` 并**持有 container**；纯金额/时间测试可不建容器）：

1. **金额→Decimal**：`amount("256.00")==Decimal(string:"256.00")`；`amount("0.1")` 等无浮点误差；`amount("")`/`amount("abc")`/`amount("0")`/`amount("-5")` 均抛 `.noAmount`。
2. **时间兜底/禁未来**：`occurredAt(nil, now:T)==T`；`occurredAt(T-3600, now:T)==T-3600`（过去保留）；`occurredAt(T+3600, now:T)==T`（未来 clamp 到 now）。
3. **分类精确匹配**：库中有"食/支出"，`category(name:"食", direction:.expense, in:)` 命中"食"。
4. **分类兜底（不匹配）**：`category(name:"停车费", direction:.expense, in:)` → "其他"；`direction:.income` 不匹配 → "其他收入"。
5. **方向矛盾以方向为准**：`category(name:"食"(支出分类), direction:.income, in:)` → 不取"食"，兜底到"其他收入"。
6. **兜底分类缺失**：库中删掉"其他" → `category(...expense)` 返回 nil（落未分类，不崩）。
7. **mock 行为**：`MockTransactionParser(behavior:.success).parse` 返回 amountText="256.00"/merchant="京东商城"/cardTail="1234"/categoryName="其他"；`.network`→`.network`、`.timeout`→`.timeout`、`.invalidResponse`→`.invalidResponse`、`.noAmount`→`.noAmount`（`await`/`XCTAssertThrowsError` 断言错误类型）。
8. **端到端归一（mock→归一）**：`.success` 的 `ParsedTransaction` 经 `RecognitionNormalizer` → amount=256(Decimal 精确)、occurredAt=样例时间(不越未来)、direction=.expense、category 命中或兜底。

（真实 `DeepSeekClient` 联网不在单测范围——已确认约定 1；仅保证编译通过、结构正确。Keychain 读写在切片 02 经 Key sheet + DEBUG 肉眼验；本片可选加一条 KeychainStore set→get→clear 冒烟测试。）

## 不做什么

- **不做任何 UI**：文本识别页、Key sheet、结果卡片、DEBUG 入口全在切片 02/03。
- **不做真实 Key 联网验收**：`DeepSeekClient` 编译交付，联网端到端由用户后续自测（已确认约定 1）。
- **不做自动重试**：失败即抛，重试为用户手动再触发（本 TRD 决策）。
- **不做 Key 格式校验/联网测活**、我的页 Key 行、完整状态展示 → N07。
- **不改** N00/N01/N02 模型字段、`LedgerStore` 签名、编辑器体系。
