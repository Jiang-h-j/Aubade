# N06 截图·快捷指令后台入账 + 通知

> 本节点是 Aubade v1 开发 DAG 的**第七个、也是最复杂的节点**,依赖 **N03 DeepSeek 解析 + 文本识别**（已完成）与 **N05 截图·相册选图**（已完成）。对应技术基线模块 **M2.5 截图·快捷指令后台入账（主入口）+ M7 通知**。
>
> 里程碑意义：**打通 PRD 第一主流程、也是"最省事"的记账主入口**——在支付宝/微信/银行付款结果页用 iOS 快捷指令随手一截，图片自动发给 Aubade，**App 在后台一口气跑完 本机 OCR → DeepSeek 解析 → 直接入账 → 弹一条本地通知**，全程不打断用户。这是把 N05 已落地的"本机 OCR 能力"和 N03 已落地的"解析入账链路"从**前台 UI 触发**搬到**后台 App Intent 触发**——OCR、解析、归一、落库全部复用，本节点净新增的是 **App Intents 入口 + 后台链路编排 + 本地通知 + 后台各分支兜底**。★ **必须真机验证**（后台时间预算、快捷指令传图、后台通知在模拟器测不准），风险隔离在开发顺序最后。
>
> 上游事实来源：全局 PRD `docs/prd/aubade-v1-prd.md`（主流程 A 截图识别 `:32-39`、验收点 1 快捷指令后台入账+通知 `:110`、验收点 11 未配置 Key 提示 `:120`、验收点 13 后台失败不误记 `:122`、业务规则 12 本地优先 `:106`、来源字段 `:78`）、开发 DAG `docs/design/aubade-v1-dev-dag.md`（N06 小节 `:204-216`）、技术基线 `docs/design/aubade-v1-technical-baseline.md`（后台链路 §7.3 `:186-210`、方案 B 降级 `:206`、App Intent 接口边界 §9.3 `:273-275`、本地通知 `:61/:104`、来源枚举 `:234`、imageRef `:236`、错误类型 `:266`、App Intent 存储共享+建库时机 §11 `:314`、后台时间预算与降级判定 §11 `:315`、真机验收要求 `:307-308`、后台链路最终形态 `:329`）。
> 代码事实来源：直接阅读 N00~N05 已落地源码（本仓库无 `.codegraph/` 索引,逐文件阅读,行号为本 PRD 写作时快照,可能有 ±1 漂移）。
>
> **本节点两项关键决策已由用户拍板（非待确认项,TRD 直接据此落地）**：
> 1. **存储共享路线 = in-app App Intents**：App Intent 定义在**主 App target 内**（非独立扩展进程）,系统在后台唤醒主 App 进程执行 `perform()`,**直接共享现有 `PersistenceController.makeContainer()` 的 ModelContainer**——**无需 App Group、不改 N00 建库配置、不迁移 N01~N05 已有数据**（对齐 `PersistenceController.swift:14-16` "in-app 路线 → 默认非共享配置" 现状注释与技术基线 §11 "in-app App Intents 路线则 M1 无需 App Group"）。
> 2. **完成门禁 = 延续 N03/N04/N05 约定**：代码结构正确可编译 + DEBUG mock 后台链路端到端跑通 + 单测覆盖后台各分支即可标 done；真机（后台时间预算、快捷指令传图机制、后台通知）由用户后续自测,**不阻塞节点完成**。真机若实测后台预算普遍不足,触发技术基线 §7.3 **方案 B 降级**,届时另行调整（见 §7）。
>
> **N05/N03/N00 复用锚点（本节点直接复用,不重造、不改签名）**：
> - **OCR 能力** `TextRecognizing` 协议（`Aubade/Features/Recognition/Screenshot/TextRecognizing.swift:13-18`,`@MainActor`,入参 `imageData: Data`,**脱 View、脱相册 UI,注释明写"可被 N06 快捷指令后台链路独立调用"**）+ 真实实现 `VisionTextRecognizer`（`VisionTextRecognizer.swift:9-39`,Vision 纯本机、perform 派后台队列）+ mock `MockTextRecognizer`（`MockTextRecognizer.swift`,定值星巴克/¥88.50）。**N06 后台链路直接调用此协议做 OCR,图片不外传。**
> - **解析+归一+落库编排** `RecognitionEntry.recognizeAndSave(text:categories:parser:store:now:source:rawText:)`（`Aubade/Features/Recognition/TextRecognitionView.swift:12-40`,`@MainActor static`）：串 `parser.parse` → `RecognitionNormalizer` 归一 → `store.createTransaction`,**关键不变量"任何失败都发生在 `createTransaction` 之前,识别失败不产生脏账"**（`:6-7` 注释）。`source`/`rawText` 已参数化,**N06 传 `.screenshotShortcut` + 带 `[快捷指令]` 前缀原文即可,无需改签名**。
> - **DeepSeek 解析层** `DeepSeekClient`（`Parsing/DeepSeekClient.swift:9-39`）：**已内置 `timeout = 20`s 明确超时**（`:14`,正是 §7.3 要求的"给 DeepSeek 调用设明确超时"）、**不自动重试**（`:6-8` 注释）、失败即抛可区分 `RecognitionError`（`.timeout`/`.network`/`.noKey`/`.invalidResponse`）——**N06 后台超时/失败分支直接复用这套错误类型**；协议 `TransactionParsing` + mock `MockTransactionParser`（`.screenshotSample` 定值 88.5/支出/星巴克/食）。
> - **落库** `LedgerStore.createTransaction(...)`（`Store/LedgerStore.swift:48-61`）已支持 `source:`/`rawText:`/`imageRef:` 入参；`TransactionSource.screenshotShortcut` 枚举**已存在**（`Models/Enums.swift:13`,N00 预置,**当前无任何调用方,N06 首次使用**）；`Transaction.imageRef` 字段已就绪（`Models/Transaction.swift:16`,注释明写"清理逻辑在 N06/M9"）。
> - **Keychain 读 Key** `KeychainStore.shared.deepSeekKey` / `.isConfigured`（`Persistence/KeychainStore.swift:22-35/:54-56`）：**`kSecAttrAccessibleAfterFirstUnlock`**（`:43`）——首次解锁后后台进程可读；因走 in-app 路线（进程内共享）,后台读 Key 无 access group 障碍。
> - **归一兜底** `RecognitionNormalizer`（金额/时间/分类归一,无金额抛 `.noAmount`）、`PresetCategories`、`RecognitionError`（`Parsing/RecognitionError.swift`）。

## 给用户看的摘要

做完这个节点,你的记账 App 迎来**最核心、最省事的记账主入口**——**截图后台自动记账**：

1. **付款页随手一截,后台自动记一笔**：在支付宝/微信/银行的付款结果页,用你在「快捷指令」App 里配好的那个动作（截屏 → 发送给 Aubade）随手一触发,**不用打开 App、不用切来切去**——Aubade 在后台自己把截图里的字读出来（本机 OCR,图片不离开手机）、发给 DeepSeek 解析出金额/分类、**直接记成一笔正式账单**,然后弹**一条本地通知**告诉你"已记一笔 · ¥88.50 · 食"。
2. **点通知能看能改**：点那条成功通知,直接跳到**结果卡片**（和文本/语音/相册识别一模一样的那张）——金额多少、归到哪类、识别到的原文,都能当场看、当场改；不想记点「删除这笔」撤销。
3. **识别不出来也不会乱记**：万一后台没读出金额、或网络不通、或识别超时,**绝不会记一笔错账**——而是弹一条"没识别出,点此补录"的通知,**原始截图会留着**；你点通知进 App,原文/原图带进手动补录页,手动补一笔即可。
4. **没配 Key 会提醒**：还没填 DeepSeek Key 就触发快捷指令,后台不会闷头失败——会弹一条通知提示你"请先在 App 里配置 Key",不会乱记账。
5. **App 内还留了一张说明卡**：「记账」Tab 的「📷 截图识别」说明卡（N05 已做）里那个**「▶︎ 演示：模拟收到一张快捷指令截图」**按钮,本节点把它接成**真实演示**——点一下就用一张内置样例截图走完整条后台链路（本机 OCR → 解析 → 入账 → 通知）,让你在没配快捷指令、甚至在模拟器上也能亲眼看到主入口长什么样。

**这一节点不做什么**（都在后面节点或已在别处）：**权限统一收口与"我的页"设置、首次引导、通知开关**（N07——本节点只做后台入账自身必需的一次通知权限申请与被拒兜底）；相册选图前台链路（N05 已做）；语音/文本记账（N04/N03 已做）。OCR 能力、DeepSeek 解析层、归一/落库、结果卡片、手动补录页、无 Key 判定 **已在 N00/N03/N05 做好,本节点直接复用、不重做、不改签名**。

## 目标

1. **App Intents 暴露"记录 Aubade 截图"后台动作（M2.5 净新增,in-app 路线）**：用 **App Intents** 在**主 App target 内**定义一个可被 iOS 快捷指令调用的动作（技术基线 §9.3 `:273-275`）,**参数为一张图片**（`IntentFile`/`ImageFile` 具体类型留 TRD）；`perform()` 在系统后台唤醒的主 App 进程内执行 §7.3 后台链路。**因走 in-app App Intents（用户已拍板）,后台进程直接共享现有 `PersistenceController` 的 ModelContainer 与 Keychain,无需 App Group、不改 N00 建库、不迁移已有数据。** 同时暴露 `AppShortcutsProvider` 让动作在快捷指令库可见（具体形态留 TRD）。
2. **后台链路编排 OCR→Key→解析→入账→通知（M2.5 净新增编排,复用既有能力）**：把 §7.3 的后台流程编排成**脱 View、可注入、可单测**的核心单元（对齐 `RecognitionEntry` 的"脱 View 可测核心"范式）：
   - ① 收到图片 → 调 `TextRecognizing.recognizeText(in:)` 本机 OCR（复用 N05,图片不外传）；
   - ② 读 `KeychainStore.deepSeekKey`,**无 Key → 发"请先配置 Key"通知、结束、不记账**（验收点 11 后台部分）；
   - ③ OCR 出文本 → 复用 `RecognitionEntry.recognizeAndSave`（`source: .screenshotShortcut` + `rawText` 带 `[快捷指令]` 前缀）跑 DeepSeek 解析→归一→落库；
   - ④ **成功入账 → 发"已记一笔 · 金额 · 分类"成功通知**（带 transaction 标识供点击跳转）；
   - ⑤ **失败/超时/无网/无金额/OCR 空 → 不记账、保留原图、发"没识别出,点此补录"失败通知**（复用 `DeepSeekClient` 已内置的 20s 超时与可区分 `RecognitionError`；复用 `recognizeAndSave` "落库前失败不产生脏账"不变量）。
3. **UNUserNotificationCenter 本地通知（M7 净新增）**：构造并发送后台入账结果通知（技术基线 `:61/:104`）——成功通知含**金额 + 分类**（可含商户）,失败通知含"点此补录",无 Key 通知含"去配置"；通知 **点击路由**：成功 → 结果卡片（复用 N03 `RecognitionResultCard`,带出 tx）、失败 → 手动补录（复用 N03 转手动,带出原文/原图）。**通知权限申请**（首次后台入账前或首次进 App 时申请,时机留 TRD；被拒时后台链路仍应完成入账、仅无通知可发,不崩溃）。
4. **后台失败原图临时留存与清理（M2.5 净新增,衔接 imageRef）**：后台链路**失败时保留原图**供点通知补录（技术基线 §7.3 `:208`）、**成功入账或用户放弃后清理**；原图存本机临时目录,`Transaction.imageRef` 记录引用（失败补录场景才落 `imageRef`,成功入账后是否留存/多久清理的具体策略留 TRD,但"失败保留、成功/放弃清理"原则已定）。
5. **"演示：模拟快捷指令截图"接成真实后台链路演示（M2.5,把 N05 占位替换为真实链路）**：N05 已在 `ScreenshotIntakeSheet.swift:26/:52-56` 把「▶︎ 演示：模拟收到一张快捷指令截图」按钮做成"敬请期待/后续版本提供"占位。**本节点把它接成真实演示**——点击用一张**内置样例截图**（或 mock 图片数据）直接调用**同一条后台链路核心单元**跑完 OCR→解析→入账→通知,使**模拟器/未配快捷指令时也能肉眼验收整条主链路**（这是本节点在无真机时的主要可观察验收路径）。
6. **后台链路可注入 + DEBUG mock（可测性,对齐 N03/N04/N05 注入范式）**：后台链路核心单元的 OCR provider、parser 均可注入（复用 N05 `TextRecognizing`、N03 `TransactionParsing` 及其 mock）,通知发送抽象成可注入协议（便于单测断言"发了哪种通知"而不真弹系统通知）；DEBUG 下"演示"按钮与 mock 开关（复用 N05 `DebugScreenshotMockSettings`、N03 mock 行为）驱动无真图片、无真网络的端到端验收。

## 当前理解

### N00/N03/N05 已交付、本节点直接复用的能力（本节点不重做、不改签名）

- **OCR 能力（N05 交付,专为 N06 复用而脱 View 设计）** `TextRecognizing`（`Screenshot/TextRecognizing.swift:13-18`）：`@MainActor protocol`,`func recognizeText(in imageData: Data) async throws -> String`,读不出字抛 `.empty`、解码/请求失败抛 `.failed`（`TextRecognizeError`）。**注释 `:10-11` 明写"脱 View、脱相册 UI：入参是图片数据,可被 N06 快捷指令后台链路独立调用"**——N06 后台链路拿到图片 `Data` 直接调它,不碰任何相册 UI。真实 `VisionTextRecognizer`（`:9-39`,Vision 纯本机、perform 派 `DispatchQueue.global`、`recognitionLanguages = ["zh-Hans","zh-Hant"]`）、mock `MockTextRecognizer`（定值 `sampleRecognizedText = "星巴克咖啡\n实付金额 ¥88.50\n..."`）。
- **解析+归一+落库编排** `RecognitionEntry.recognizeAndSave`（`TextRecognitionView.swift:12-40`,`@MainActor static`）：`parser.parse` → `RecognitionNormalizer`（金额/时间/分类）→ `store.createTransaction`,返回落库 `Transaction`。**关键不变量：任何失败（parse 抛错 / 归一抛 `.noAmount`）都在 `createTransaction` 之前,保证识别失败不产生脏账**（`:6-7`）。`source`（默认 `.text`）、`rawText`（默认 `nil`）已参数化（`:23-24`）——**N06 传 `source: .screenshotShortcut` + `rawText:` 带 `[快捷指令]` 前缀,零签名改动**。
- **DeepSeek 解析层** `DeepSeekClient`（`Parsing/DeepSeekClient.swift:9-39`）：**已内置 `timeout: TimeInterval = 20`**（`:14`,注释"明确超时（技术基线 §11 落地值）"）、`.timedOut → RecognitionError.timeout` / 其它 → `.network`（`:29-32`）、非 2xx → `.invalidResponse`、无 Key → `.noKey`；**不自动重试**（`:6-8`,"避免对计费 API 隐式重试放大成本"）。**§7.3 要求的"给 DeepSeek 调用设明确超时、超时即走失败分支绝不悬挂"在 N03 已实现,N06 后台链路直接复用这套超时+错误类型。**
- **落库层** `LedgerStore.createTransaction(amount:direction:occurredAt:category:merchant:note:cardTail:source:rawText:imageRef:)`（`LedgerStore.swift:48-61`）：已支持 `source:`/`rawText:`/`imageRef:`；内部 `context.insert` + `context.save`。`TransactionSource.screenshotShortcut`（`Enums.swift:13`）**已定义、当前零调用方**,N06 后台入账首次使用。`Transaction.imageRef`（`Transaction.swift:16`）已就绪。
- **Keychain** `KeychainStore.shared.deepSeekKey`（`KeychainStore.swift:22-35`）/`.isConfigured`（`:54-56`）：`kSecAttrAccessibleAfterFirstUnlock`（`:43`）设备首次解锁后即可读——后台进程可读到 Key（in-app 路线进程内共享,无 access group 障碍）。
- **结果卡片 + 转手动补录** `RecognitionResultCard`（`TextRecognitionView.swift:268-298`,private,复用 `TransactionEditor(.edit)` + 折叠原文 + 改/删撤销）；失败转手动 `ManualEntryView(prefillNote:)`（`Record/ManualEntryView.swift`,N03 已用作"转手动带原文"）——**N06 通知点击路由的落点复用这两个,不新造。** 因 `RecognitionResultCard` 是 private,通知路由如何复用"经 tx 打开结果卡片"（是否走 `TextRecognitionView` 已有的 `resultTx` 通路、或另找入口）留 TRD。
- **截图说明卡** `ScreenshotIntakeSheet`（`Screenshot/ScreenshotIntakeSheet.swift`）：N05 已做,含「演示」占位按钮（`:26` 触发 `showDemoPlaceholder`、`:52-56` 弹"敬请期待"alert）——**N06 把该占位替换为真实后台链路演示**（§5）。
- **provider/解析器注入 + DEBUG mock 范式** `RecordTabView`（`Record/RecordTabView.swift:105-131`）：`makeTextRecognizer()` DEBUG 走 `MockTextRecognizer`、Release 走 `VisionTextRecognizer`；`screenshotParser` DEBUG 固定 `.screenshotSample`、Release 走 `DeepSeekClient`；`screenshotRawText(ocrText:)`（`:129-131`）拼 `[截图识别]\n<OCR文本>` 前缀——**N06 后台链路照此注入范式,前缀改 `[快捷指令]`。**

### 存储与建库现状（N00 交付,本节点消费,按用户拍板"in-app 路线"无需改）

- **`PersistenceController.makeContainer()`**（`Persistence/PersistenceController.swift:17-21`）：当前 **in-app 路线、默认非共享配置、不配置 App Group**（`:14-16` 注释）；**注释明写"日后若改独立扩展进程 + App Group,只改这一处 config … 若发生在 N06 评估"**。**用户已拍板走 in-app App Intents,本节点沿用现有容器、不动此处、不迁移数据。** App Intent 在后台唤醒的主 App 进程内 `perform()`,通过既有注入方式拿到同一 `mainContext`（后台如何获取 container/context——是否复用 `AubadeApp.container`、后台 `@MainActor` 落库的线程约束——留 TRD）。
- **N06 净新增能力在项目中确认为零**：`UNUserNotification*`、`import AppIntents`/`AppIntent`/`AppShortcut`、App Group/共享容器 **全零命中**（本 PRD 写作时 `rg` 核实）——通知、App Intents 都是本节点首次引入；可复用的是 N03~N05 的能力与注入**范式**,不是现成的后台/通知代码。

### 可测性（对齐技术基线 §10、N03/N04/N05 范式）

- 测试框架 **XCTest**（`AubadeTests/` 平铺）；已有 `RecognitionEntryTests`（编排落库）、`RecognitionEntryScreenshotTests`（`source=.screenshotAlbum` 落库断言）、`RecognitionEntryVoiceTests`（`.voice`）、`ScreenshotOCRProviderTests`（OCR provider 分支）、`MockParserTests`、`ResultCardActionsTests`。
- **`RecognitionEntryScreenshotTests` 的 `source=.screenshotAlbum` 落库断言范式可直接照搬**——N06 补一条 `source=.screenshotShortcut` 落库断言。
- **后台链路核心单元**应抽成**脱 View、脱 App Intent 框架、脱真图片/真网络/真系统通知**的可注入单元（mock OCR provider + mock parser + `PersistenceController.makeInMemoryContainer()` + mock 通知发送器）,单测覆盖：成功入账（落 `.screenshotShortcut` + `[快捷指令]` 前缀 rawText + 金额 Decimal 无误差）→ 发成功通知；无 Key → 不落库 + 发无 Key 通知；OCR 空/OCR 失败 → 不落库 + 发失败通知 + 保留原图；解析超时/网络/无金额 → 不落库（守脏账不变量）+ 发失败通知 + 保留原图。

## 涉及的现有链路

- **被扩展/接线**：
  - `ScreenshotIntakeSheet`「演示」按钮（`ScreenshotIntakeSheet.swift:26/:52-56`,现"敬请期待"占位）→ 接成真实后台链路演示（§5）。
  - `DebugMenuView`（DEBUG）→ 可能补后台链路/通知相关 mock 开关（复用 N05 `DebugScreenshotMockSettings`,是否新增留 TRD）。
  - `Info.plist` 生成配置（pbxproj `INFOPLIST_KEY_*`）→ 若通知/后台需要新增权限描述/后台模式键,照 N04/N05 方式落地（具体键留 TRD）。
  - App target 配置 → 新增 App Intents 暴露（in-app,不新建 extension target）。
- **被复用（只读消费,不改签名）**：
  - `TextRecognizing`/`VisionTextRecognizer`/`MockTextRecognizer`（OCR 能力,N05 已脱 View 供 N06 复用）。
  - `RecognitionEntry.recognizeAndSave`（传 `.screenshotShortcut` + 带前缀 rawText,N05/N04 已参数化,零签名改动）。
  - `DeepSeekClient`（含 20s 超时）/`TransactionParsing`/`MockTransactionParser`（`.screenshotSample`）、`RecognitionNormalizer`、`RecognitionError`。
  - `LedgerStore.createTransaction`（`source`/`rawText`/`imageRef`）、`TransactionSource.screenshotShortcut`、`Transaction.imageRef`、`PersistenceController`（in-app 容器）、`KeychainStore`（后台读 Key）。
  - `RecognitionResultCard`（成功通知落点）、`ManualEntryView(prefillNote:)`（失败补录落点）、`KeySetupSheet`（无 Key 引导,若在 App 内路由）。
- **本节点新增**：
  - **App Intent**（"记录 Aubade 截图"动作,参数=图片,`perform()` 后台执行）+ `AppShortcutsProvider`。
  - **后台链路核心单元**（脱 View、可注入、可单测的 OCR→Key→解析→入账→通知编排）。
  - **本地通知发送与点击路由**（UNUserNotificationCenter,成功/失败/无 Key 三类 + 点击跳结果卡片/补录）。
  - **原图临时留存与清理**（失败保留、成功/放弃清理,落 `imageRef`）。
  - 「演示」按钮真实链路接线。
- **无既有调用方冲突**：App Intent/通知/后台编排/原图留存为全新代码；`recognizeAndSave`/OCR provider/`createTransaction` 均已参数化就绪,N06 只新增 `.screenshotShortcut` 调用方与后台编排；除接「演示」按钮、可能补 DEBUG 开关、加必要 Info.plist 键外,不改 N01~N05 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard`/`ScreenshotIntakeSheet` 相册流程/语音/文本相关签名与既有行为。

## 需求范围

### 1. App Intents 暴露后台截图动作（M2.5,in-app 路线,用户已拍板）
- 在**主 App target 内**定义一个 `AppIntent`——"记录 Aubade 截图",**参数为一张图片**（`@Parameter` 图片类型 `IntentFile`/`ImageFile` 具体留 TRD）；`perform()` 后台执行 §7.3 链路,返回轻量结果（是否需要 `ProvidesDialog`/`ReturnsValue` 留 TRD,但**不弹前台 UI**）。
- 暴露 `AppShortcutsProvider` 让动作在「快捷指令」App 可搜到（触发短语/图标留 TRD）。
- **不新建 App Extension target、不配 App Group**——in-app App Intents 直接共享主 App 的 `ModelContainer` 与 Keychain（用户已拍板,对齐 `PersistenceController.swift:14-16`）。
- 后台如何在 `perform()` 内拿到与主 App 同一的 `ModelContext`（复用 `AubadeApp.container.mainContext` 还是别的注入方式）、后台 `@MainActor` 落库的线程约束 → 留 TRD。

### 2. 后台链路编排（M2.5,复用 N05 OCR + N03 解析入账）
- 编排成**脱 View、脱 App Intent 框架依赖、可注入、可单测**的核心单元（对齐 `RecognitionEntry` 脱 View 可测范式）,顺序严格按 §7.3：
  1. 收到图片 `Data` → `TextRecognizing.recognizeText(in:)` 本机 OCR（图片不外传）；OCR 抛 `.empty`/`.failed` → 走失败分支（§第 4 点）。
  2. 读 `KeychainStore.deepSeekKey`——无 Key → **发无 Key 通知、结束、不记账、不解析**（验收点 11 后台）。
  3. OCR 文本 → `RecognitionEntry.recognizeAndSave(text: OCR文本, source: .screenshotShortcut, rawText: "[快捷指令]\n"+OCR文本, parser:, store:, now:)`：复用 DeepSeek 解析（含 20s 超时）→ 归一 → 落库。
  4. 成功 → 发成功通知（§3）；返回。
  5. 解析/归一失败（`RecognitionError.timeout`/`.network`/`.noAmount`/`.invalidResponse`）→ **不记账（复用 `recognizeAndSave` 落库前失败不产生脏账不变量）、保留原图、发失败通知**（§3/§4）。
- **超时兜底靠 `DeepSeekClient` 已内置的 20s 超时**（§7.3 "给 DeepSeek 调用设明确超时；超时即走失败通知分支,绝不生成脏账、绝不悬挂"）——N06 不新造超时机制,复用即可；后台整体是否再加一层"总时间预算保护"留 TRD（真机数据决定）。
- 账单 `source` 落 `.screenshotShortcut`（区别于 N05 相册的 `.screenshotAlbum`）；`rawText` 加 `[快捷指令]` 前缀（对齐 N05 `[截图识别]`/N04 `[语音转文字]` 前缀范式,`RecordTabView.swift:129-131`；确切格式换行/包裹留 TRD,但"带 `[快捷指令]` 前缀"已定）。

### 3. 本地通知（M7,UNUserNotificationCenter）
- **成功通知**：标题/正文含**金额 + 分类**（可含商户）,如"已记一笔 · ¥88.50 · 食"（技术基线 `:104` "成功含金额+分类+商户+查看/修改",确切文案留 TRD）；`userInfo` 带 **transaction 标识**（id）供点击跳转。
- **失败通知**："没识别出,点此补录"（技术基线 `:104`）；`userInfo` 带**原图/原文引用**供补录带入。
- **无 Key 通知**：提示"请先在 App 里配置 DeepSeek Key"（验收点 11 后台）。
- **点击路由**：成功 → 打开**结果卡片**（复用 `RecognitionResultCard`,按 tx id 取账单带入；private 卡片如何复用留 TRD）；失败 → 打开**手动补录**（复用 `ManualEntryView(prefillNote:)` 带出原文,原图带入留 TRD——若需给 `ManualEntryView` 加"原图引用"入参,照 N04 给 `recognizeAndSave` 加带默认值参数范式做**零签名改动扩展**,不破坏 N03 既有调用）；无 Key → 打开 Key 配置（复用 `KeySetupSheet` 或引导,留 TRD）。路由承接点（`AubadeApp`/`ContentView` 的 `UNUserNotificationCenterDelegate` 与深链状态）留 TRD。
- **通知权限申请**：首次需要发通知前或首次进 App 时申请（时机留 TRD；与 N07 统一收口不重复——本节点只做后台入账自身必需的申请）；**权限被拒时后台链路仍完成 OCR→解析→入账（成功仍落账）,仅无法弹通知,不崩溃、不误记**（被拒降级细节留 TRD）。

### 4. 后台各失败/边界兜底（M2.5,守"不误记脏账"红线）
- **无 Key**（§2.2）：不 OCR 后续解析、不记账,发无 Key 通知。
- **OCR 空结果 `.empty` / OCR 失败 `.failed`**：不记账、保留原图、发失败通知（"没识别出,点此补录"）,点通知进补录。
- **解析超时 `.timeout` / 无网 `.network` / 无金额 `.noAmount` / 非法响应 `.invalidResponse`**：复用 `recognizeAndSave` "落库前失败" 不变量 → **不记账**、保留原图、发失败通知。
- **绝不生成脏账、绝不悬挂**（§7.3 硬约束）：任一失败分支都不得留下半条账单；后台任务及时结束。
- **原图留存/清理**（§5 目标 4）：失败分支保留原图（存本机临时目录、`imageRef` 记录引用供补录）；成功入账 / 用户放弃补录后清理。具体临时目录位置、清理触发点（App 启动扫、补录完成后删、成功后是否即删）留 TRD,但"失败保留、成功/放弃清理"原则已定。

### 5. 「演示」按钮接真实后台链路 + 无真机可观察验收（M2.5）
- 把 `ScreenshotIntakeSheet`「▶︎ 演示：模拟收到一张快捷指令截图」按钮（`:26/:52-56` 现"敬请期待"占位）接成**真实调用同一条后台链路核心单元**：用一张**内置样例截图 / mock 图片数据**（DEBUG 可用 `MockTextRecognizer.success` 定值路径）跑完 OCR→Key 判定→解析→入账→通知。
- 目的：**模拟器 / 未配快捷指令时,也能在 App 内点「演示」肉眼走通整条主链路**（本节点无真机时的主要可观察验收路径）,并弹真实本地通知、点击跳结果卡片。
- 「演示」使用的样例定值对齐 demo `data.js:43`（星巴克 88.5/支出/食）与 `MockTextRecognizer.sampleRecognizedText`；DEBUG 可复用 N05 `DebugScreenshotMockSettings` 切成功/空/失败观察各分支通知。

### 6. 可注入 + DEBUG mock（可测性 + 供后台链路端到端验收）
- 后台链路核心单元的 **OCR provider、parser、通知发送、当前时刻、ModelContext** 均可注入（OCR/parser 复用 N05/N03 mock；**通知发送抽象成可注入协议**,使单测断言"发了哪类通知"而非真弹系统通知；`now` 注入固定时间；context 用 in-memory 容器）。
- DEBUG「演示」按钮 + 复用 N05 `DebugScreenshotMockSettings` mock 开关驱动无真图片、无真网络端到端；真实 App Intent 后台触发、真机通知交付由用户真机自测。

### 7. 方案 B 降级（仅真机实测后台预算普遍不足时触发,本节点默认不实现）
- **默认走"后台全流程入账"**（技术基线 §7.3 `:186`、§11 `:329` "已确认"）——本节点按全流程实现。
- **方案 B 降级仅作已知预案,不在本节点默认实现**：若用户真机实测发现后台预算普遍不足以完成一次 DeepSeek 往返（§7.3 `:206`）,则降级为"后台只做 OCR + 保存原始文本 + 发通知,DeepSeek 解析与入账改由用户点通知进 App 前台完成"。**此判定需真机数据支撑**（用户自测）,触发后另行调整 TRD 与实现；本 PRD 记录该预案存在,但**不把方案 B 实现列入本节点默认交付范围**（避免在无真机数据时预造降级分支）。

### 8. 单元测试（对齐技术基线 §10、N03/N04/N05 范式）
- **`source=.screenshotShortcut` 落库**：mock OCR 文本（含金额）+ mock parser 注入后台链路核心单元,断言落库 `source=.screenshotShortcut`、`rawText` 保留（带 `[快捷指令]` 前缀）、金额 `Decimal` 无浮点误差（照搬 `RecognitionEntryScreenshotTests` 补一条）。
- **后台各分支**（脱真图片/真网络/真系统通知,用 mock 通知发送器）：成功→落库+成功通知；无 Key→不落库+无 Key 通知；OCR 空/失败→不落库+失败通知+保留原图；解析超时/无网/无金额→不落库（守脏账不变量）+失败通知+保留原图。
- **不回归**：N05 `.screenshotAlbum`、N04 `.voice`、N03 `.text` 既有落库行为不受影响（复核既有 `RecognitionEntry*Tests`）；`recognizeAndSave`/OCR provider 零签名改动。

## 不做什么

以下均属其他节点或已在别处,本节点**不实现**：
- **独立扩展进程 + App Group + 数据迁移**（用户已拍板走 in-app App Intents）：不新建 App Extension target、不配 App Group 共享容器、不改 `PersistenceController` 建库配置、不迁移 N01~N05 已有数据。
- **权限统一收口与设置界面**（N07）：我的页通知开关、权限状态展示、首次引导集中申请、相册/麦克风/语音/通知统一"去设置"收口——本节点只做后台入账**自身必需**的一次通知权限申请与被拒兜底。
- **相册选图前台链路**（N05 已完成）：不碰 `ScreenshotIntakeSheet` 的 PhotosPicker 相册流程、不碰 `.screenshotAlbum` 链路（仅把同卡内「演示」按钮接后台链路）。
- **语音/文本记账**（N04/N03 已完成）：不碰语音/文本入口与既有行为。
- **重做 N00/N03/N05 已交付部分**：OCR 能力（`TextRecognizing`/`VisionTextRecognizer`）、DeepSeek 解析层、归一/兜底、错误类型、结果卡片 `RecognitionResultCard`、手动补录 `ManualEntryView`、无 Key 判定 `KeychainStore`、`recognizeAndSave`/OCR provider 参数化——**全部复用,不重写、不改签名**。
- **真机端到端作为本节点门禁**：可观察验收以 **DEBUG「演示」按钮 mock 端到端 + 单测**为准（用户已拍板延续 N03/N04/N05 约定）；真实快捷指令触发、真机后台执行、真机通知交付、后台时间预算与传图机制由用户后续真机自测,**不阻塞节点完成**。
- **方案 B 降级实现**（§7）：默认不实现,仅记录预案；真机数据触发后另行调整。
- **原图长期留存/图库管理**（v1 不做,全局 PRD `:105/:127`）：只做后台失败补录所需的**临时**原图留存与清理,不做原图相册/附件管理。
- 不改 N00~N05 的模型字段、`LedgerStore`/`TransactionEditor`/`RecognitionResultCard`/`ScreenshotIntakeSheet` 相册流程/语音/文本相关签名与既有行为。

## 验收标准

（对齐 DAG 中 N06 的"退出标准（可观察,真机）"`:215` 与全局 PRD 验收点 1/11 后台/13 后台。**完成门禁 = DEBUG「演示」mock 端到端 + 单测**（用户已拍板延续前节点约定）；真机快捷指令端到端为用户后续自测。真机相关项在验收里标注"真机自测"。）

1. **「演示」后台链路端到端（本节点主可观察验收,PRD 验收点 1 的 mock 等价）**：记账页点「📷 截图识别」弹说明卡,点「▶︎ 演示：模拟收到一张快捷指令截图」（DEBUG OCR mock=成功）→ 后台链路核心单元跑完 本机 OCR → 读 Key → DeepSeek 解析 → **直接生成一笔已入账账单** → 弹**成功本地通知**（含金额/分类,如"已记一笔 · ¥88.50 · 食"）。落库字段：金额/方向/分类/商户按 mock 定值（星巴克 88.5/支出/食）、金额 `Decimal` 无浮点误差、**来源=`TransactionSource.screenshotShortcut`**、原文保留 OCR 文字（带 `[快捷指令]` 前缀）。
2. **真机快捷指令后台入账（PRD 验收点 1,真机自测）**：真机触发配好的快捷指令把付款截图发给 Aubade,后台完成本机 OCR→解析→直接生成已入账带分类账单并弹含金额/分类的本地通知（真实 Key + 真机,用户自测）。
3. **成功通知点击 → 结果卡片可改/撤销（复用 N03）**：点成功通知打开结果卡片,可改金额/方向/分类/时间/商户/备注,「完成」后改动生效、统计与剩余（N02）自动刷新；「删除这笔」二次确认后撤销入账、列表/剩余/统计同步；可展开查看识别原文（带 `[快捷指令]` 前缀）。
4. **后台失败不误记 + 失败通知 + 补录（PRD 验收点 13 后台）**：（DEBUG OCR mock=空/失败,或 mock parser=无金额/网络/超时）后台**不生成任何账单**、**保留原图**、弹"没识别出,点此补录"失败通知；点失败通知进手动补录页、带出原文（原图带入为真机/后续项）。
5. **无 Key 后台提示（PRD 验收点 11 后台）**：Keychain 无 Key 时触发「演示」/快捷指令,后台**不记账**、弹"请先配置 Key"通知；点击进 Key 配置引导；全程不崩溃、手动记账不受影响。
6. **不生成脏账、不悬挂（§7.3 硬约束）**：任一失败分支（无 Key/OCR 空/OCR 失败/超时/无网/无金额/非法响应）都不留半条账单、后台任务及时结束——单测覆盖各分支"未落库"断言。
7. **隐私边界（PRD 业务规则 12）**：图片用 Vision 本机 OCR（图片不外传）；只有 OCR 出的**文本**经 N03 链路发 DeepSeek；无图片上传、无录音。
8. **存储共享正确（in-app 路线）**：「演示」按钮在主 App 进程内跑后台链路核心单元,落的账单立即出现在账单 Tab/最近记录/统计（验证核心单元写的是主 App 同一 `ModelContainer`）。**真机 App Intent 后台进程与主 App 共享同一存储**由 in-app 同进程架构天然保证 + 用户真机自测确认（不涉及 App Group、不迁移数据）。
9. **`source=.screenshotShortcut` 与后台分支单测**：单测覆盖——后台链路成功落库 `source=.screenshotShortcut`、`rawText` 带前缀、金额 Decimal 无误差；无 Key/OCR 空/OCR 失败/超时/无网/无金额各分支"不落库 + 发对应通知（mock 通知发送器断言）+ 失败保留原图"；N05 `.screenshotAlbum`/N04 `.voice`/N03 `.text` 不回归；均 mock 注入、脱真图片/真网络/真系统通知。
10. **不越界**：不做独立扩展进程/App Group/数据迁移（in-app 路线）；不做权限统一收口/我的页设置/首次引导/通知开关（留 N07）；不碰 N05 相册流程与其它入口既有行为；不重写 N03/N05 OCR/解析层/结果卡片/Key；`recognizeAndSave`/OCR provider 零签名改动；不默认实现方案 B 降级（仅记录预案）。

## 已确认约定

（以下由上游 PRD/技术基线/DAG 定死、由 N00~N05 既有实现约束、或由用户本轮拍板,作为既定实现约束,非待确认项。TRD 直接据此落地。）

1. **存储共享 = in-app App Intents（用户本轮拍板）**：App Intent 定义在主 App target 内,后台唤醒主 App 进程执行 `perform()`,直接共享现有 `PersistenceController` 的 ModelContainer 与 Keychain；**不建 App Extension、不配 App Group、不改 N00 建库、不迁移 N01~N05 数据**（对齐 `PersistenceController.swift:14-16` in-app 路线注释、技术基线 §11 `:314` "in-app App Intents 路线则 M1 无需 App Group"）。
2. **完成门禁 = 延续 N03/N04/N05 约定（用户本轮拍板）**：代码可编译 + DEBUG「演示」mock 后台链路端到端跑通 + 单测覆盖后台各分支即可标 done；真机（后台时间预算、快捷指令传图、后台通知交付）由用户后续自测,不阻塞节点完成。
3. **后台链路走全流程入账、OCR 后 100% 复用 N03/N05**（技术基线 §7.3 `:186`、§11 `:329` 已确认）：后台顺序=本机 OCR（复用 N05 `TextRecognizing`）→ 读 Key → DeepSeek 解析（复用 N03 `DeepSeekClient`,含 20s 超时）→ 归一 → 落库（复用 `RecognitionEntry.recognizeAndSave`）→ 通知；不重写 OCR/解析/归一/落库/结果卡片/补录。
4. **超时兜底复用 `DeepSeekClient` 已内置 20s 超时**（`DeepSeekClient.swift:14`,技术基线 §7.3 "给 DeepSeek 调用设明确超时；超时即走失败分支绝不悬挂绝不脏账"）：N06 不新造超时,复用既有超时 + 可区分 `RecognitionError`；是否再加后台总时间预算保护由真机数据决定（留 TRD）。
5. **账单来源落 `.screenshotShortcut`、rawText 加 `[快捷指令]` 前缀**（全局 PRD 来源字段 `:78`、技术基线 `:234` "区分快捷指令 vs 相册仅作回溯"、`Enums.swift:13` 已有枚举、对齐 N05 `[截图识别]`/N04 `[语音转文字]` 前缀范式）：后台入账 `source=.screenshotShortcut`（当前零调用方,N06 首次用）；`recognizeAndSave` 已参数化,零签名改动,只新增 `.screenshotShortcut` 调用方。
6. **不误记脏账是红线**（技术基线 §7.3 "绝不生成脏账、绝不悬挂"、全局 PRD 验收点 13）：复用 `recognizeAndSave` "任何失败都在 createTransaction 之前" 不变量（`TextRecognitionView.swift:8-9`）；后台任一失败分支不留半条账单。
7. **后台失败保留原图、成功/放弃清理**（技术基线 §7.3 `:208`、`Transaction.imageRef` `:16` 注释 "清理逻辑在 N06/M9"）：失败分支临时留存原图供补录（落 `imageRef`）、成功入账或放弃补录后清理；临时目录位置/清理触发点具体策略留 TRD,原则已定。
8. **本地通知用 UNUserNotificationCenter,三类 + 点击路由**（技术基线 `:61/:104`）：成功（金额+分类,点击→结果卡片）、失败（点此补录,点击→手动补录带原文/原图）、无 Key（点击→Key 配置）；具体文案、`userInfo` 结构、深链承接点留 TRD。
9. **通知权限本节点只做自身必需申请,统一收口留 N07**（DAG N07 范围 `:227`、`:224` "通知开关"）：申请时机留 TRD；被拒时后台仍完成入账、仅不发通知、不崩溃。
10. **可测性：后台链路脱 View、脱 App Intent 框架、可注入 + mock**（技术基线 §10、对齐 N05 `TextRecognizing` 脱 View 设计 `TextRecognizing.swift:10-11` "可被 N06 后台链路独立调用"）：核心单元注入 OCR provider/parser/通知发送/now/context；通知发送抽象成可注入协议以便单测断言而不真弹通知；「演示」按钮 + N05 `DebugScreenshotMockSettings` 支撑无真图片/真网络端到端。
11. **方案 B 降级仅记录预案、本节点默认不实现**（技术基线 §7.3 `:206`、§11 `:315/:329`）：默认全流程入账；仅真机实测后台预算普遍不足时触发降级,需真机数据支撑,触发后另行调整,不在无数据时预造降级分支。
12. **App Intents 相关 Info.plist/target 配置照 N04/N05 `GENERATE_INFOPLIST_FILE` 方式落地**（`project.pbxproj` 现状、N04/N05 已用 `INFOPLIST_KEY_*` 加权限键）：若通知/后台需新增 Info.plist 键（如通知用途）,以 `INFOPLIST_KEY_*` build setting 落地；App Intents 在主 target 暴露、不新建 extension target（键名/配置留 TRD）。
