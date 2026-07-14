# N04 语音记账 — TRD 索引

> 节点 PRD：`docs/prd/nodes/n04-voice-capture-prd.md`（已评审通过）。
> 上游代码事实：N00 数据层 + N01 手动记账/编辑器 + N02 剩余/统计 + **N03 DeepSeek 解析 + 文本识别**（已完成，提交 133d1c4）。
> UI 与交互事实来源：已实现原型 demo `prototype/app/`（`app.js:310` `openVoiceCapture` 语音流程 / `data.js:45` 语音识别契约）。
> 本节点无 `.codegraph/` 索引，代码事实来自逐文件阅读，行号为写作时快照（可能 ±1 漂移）。

## 里程碑意义

N04 是**第一个"本机系统能力 → 文本 → 复用 N03 解析层"的识别入口**。N03 已把"取文本 → DeepSeek 解析 → 直接入账 → 结果卡片 → 失败转手动"整条链路跑通;N04 **只替换"文本从哪来"**——在这条链路前面加一段 **iOS Speech 本机语音转文字**(按住说话 → 识别中 → 结果卡片)。语音不外传,只有转出的文本才交给 DeepSeek。它也为 N05(截图 OCR)"本机识别 → 文本 → 复用解析层"范式先行验证。

## 切片划分与顺序

N04 拆成 **3 个单一职责切片**,按"先纯逻辑底座、再真实系统能力、后 UI 接线闭环"排序,每片可独立编译:

| 切片 | 名称 | 单一职责 | 依赖 | 覆盖 PRD 验收 |
|---|---|---|---|---|
| 01 | 语音转文字 provider 底座 + `recognizeAndSave` 参数化 | **纯逻辑地基,零 UI、脱真麦克风**:`VoiceTranscribing` 协议 + `VoiceTranscribeError` + `MockVoiceTranscriber`(五态) + `recognizeAndSave` 向后兼容参数化 `source`/`rawText` + `MockTransactionParser.voiceSample`(20/行) + 全分支单测 | N03 | 验收 9(单测)、为 1/8 提供底座 |
| 02 | 真实 SFSpeech provider + 权限申请与降级 | `SpeechVoiceTranscriber`(真实 `SFSpeechRecognizer(zh-CN)`+`AVAudioEngine`,强制 on-device、60s 上限) + 麦克风/语音识别权限(首次按下录音申请)+ 被拒/不可用降级 + Info.plist UsageDescription | 切片 01 | 验收 8(隐私/本机)、4/5(真机降级半) |
| 03 | 语音面板 UI + 状态机 + 入口接线 + 结果卡片复用 + DEBUG mock | `RecordTabView`🎤 接线(无 Key 拦截前置)+ `VoiceCaptureView`(按住说话/录音中/转文字中/降级)+ 复用 N03 成功/失败/结果卡片(经扩展 `TextRecognitionView` 预置文本自动识别)+ voice provider 注入 + DebugMenu 语音 mock 开关 | 切片 01/02 | 验收 1/2/3/4/5/6/7/10 |

### 为什么这样拆

- **切片 01 是纯逻辑底座**:provider 协议/mock、`recognizeAndSave` 参数化、语音 mock 定值全无 UI 与硬件依赖,可完全脱环境单测(PRD 验收 9)。先把"语音→文字"契约与"记成 `.voice` 账单"落库焊死,风险最低,后两片直接消费。**本切片对 N03 已落地代码的签名改动(`recognizeAndSave` 加带默认值的 `source`/`rawText`)向后兼容、N03 调用零改;另一处向后兼容扩展(`TextRecognitionView` 加预置文本参数)在切片 03。**
- **切片 02 交付真实系统能力**:真实 `SFSpeechRecognizer`+`AVAudioEngine`、权限、on-device、60s 全是与 iOS 系统 API 打交道的净新增,依赖真机真麦克风,独立成片便于聚焦系统 API 正确性与隐私边界;它只实现切片 01 的协议,不接入口,对既有链路零影响。
- **切片 03 接成可用闭环**:入口接线 + 语音面板 + 状态机 + 复用 N03 成功/失败态 + DEBUG mock。核心接缝(N03 `RecognitionResultCard` 是 private)在此解决:**扩展 `TextRecognitionView` 支持"预置文本 + 自动识别 + source/rawText",让语音转出文本后复用整个文本识别成功/失败/结果卡片**,零改 N03 结构。DEBUG 语音 mock 支撑模拟器无麦克风肉眼验收全路径。

## 切片文件

- `01-voice-provider-source-trd.md`
- `02-speech-provider-permission-trd.md`
- `03-voice-panel-wiring-debug-trd.md`

## 全节点共用的关键约束（三片都遵守）

1. **转出文本后的链路 100% 复用 N03,不重写**（DAG N04 "复用 N03 解析链路与结果卡片"、PRD 已确认约定 2）:不重做 DeepSeek 解析层、`RecognitionNormalizer` 归一、`RecognitionError`、结果卡片 `RecognitionResultCard`、无 Key 拦截、Key sheet、Keychain。语音只新增"按住说话 → 本机转文字"前置段。
2. **对 N03 的签名改动仅两处、均向后兼容**（PRD 已确认约定 3）:(a) `recognizeAndSave` 加 `source: = .text`、`rawText: = nil`（切片 01）;(b) `TextRecognitionView` 加 `presetText`/`source`/`rawTextOverride`（切片 03，均带默认值）。两处都带默认值,N03 现有调用(`TextRecognitionView.recognize()`、`RecordTabView` 的 `TextRecognitionView(parser:categories:)`)行为逐字节不变;不改 `LedgerStore.createTransaction`（`:47` 已支持 `source`/`rawText`）、`RecognitionResultCard`、`TransactionEditor` 签名。
3. **语音本机、强制 on-device、不外传**（全局 PRD 业务规则 12、PRD 已确认约定 1、验收 8）:`requiresOnDeviceRecognition = true` + 先 check `supportsOnDeviceRecognition`;中文本机不可用则降级提示,**不回退云端**。只有转出的**文本**经 N03 链路发 DeepSeek,无录音/图片上传。
4. **provider 协议抽象 + mock 注入**（PRD 已确认约定 8、对齐 N03 `TransactionParsing` 范式）:录音转文字经 `VoiceTranscribing` 协议注入;真实 `SpeechVoiceTranscriber` 与 `MockVoiceTranscriber` 同契约。**可观察验收以 DEBUG mock 端到端 + 单测为准**,真机真麦克风+真实 Key 为用户后续自测,不阻塞节点(PRD 已确认约定 6)。
5. **账单来源落 `.voice`、原文带 `[语音转文字]` 前缀**（PRD 已确认约定 3/11）:语音入账 `source=.voice`（`Enums.swift:15` 已有枚举）;`rawText` = `[语音转文字]\n"<口语原句>"`(对齐 demo `data.js:45`)。parse 收纯口语、落库 rawText 带前缀,二者经切片 01 `rawText ?? text` 分离。
6. **验收定值来自新增语音 mock,不复用 N03 success**（PRD §6/验收 1）:语音成功定值 = 金额 20 / 支出 / 分类"行"(新增 `MockTransactionParser.voiceSample`),与 N03 文本 `.success`(256/京东/其他)并存不替换。归一命中预置支出分类"行"（`PresetCategories.swift:7`）。
7. **权限时机 = 首次按下录音、收口留 N07**（PRD 已确认约定 5/9）:进语音面板不弹权限,用户按下录音键才申请麦克风+语音识别;被拒/受限给明确降级、不崩溃、不阻塞手动记账与文本识别。我的页权限状态、首次引导集中申请、统一"去设置"收口均留 N07。
8. **最长录音 60s**（PRD 已确认约定 10）:单次按住达 60s 自动结束并转文字,防超长/误触长按。
9. **不自建 `ModelContainer`**:一律注入 `ModelContext`/`LedgerStore(context)`,禁链式 `container().mainContext`(N00 SIGTRAP 陷阱,见 memory)。语音入账仍走 `recognizeAndSave` → `LedgerStore.createTransaction`。
10. **不越界**:截图/相册 → N05;快捷指令后台 → N06;权限统一收口/我的页/首次引导 → N07。本节点只做**语音**入口 + 语音记账自身必需的一次权限申请与被拒降级;不改 N01/N02/N03 既有行为,`imageRef` 恒 nil。
