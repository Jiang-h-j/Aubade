# TRD 切片进度

- 最近完成 TRD：`docs/design/nodes/n04-voice-capture/03-voice-panel-wiring-debug-trd.md`
- 下一个 TRD：`全部完成`
- 更新时间：2026-07-15T12:56:41+08:00

## 上一次 TRD 开发

N04 语音记账切片03「语音面板 UI + 状态机 + RecordTabView 🎤 接线 + 复用 N03 结果卡片 + DEBUG 语音 mock 开关」完成，N04 在模拟器(mock 注入)可完整验收：点🎤 → 语音面板 → 按住松手(mock=成功)→ 转场识别中 → 弹结果卡片(金额20/支出/分类"行"/来源语音/原文带 `[语音转文字]` 前缀)。

- **语音面板 `VoiceCaptureView`(新增)**：`VoicePhase` 局部状态机(idle/recording/transcribing/failed)；`DragGesture(minimumDistance:0)` 实现"按住录音、松手结束"；面板侧 60s 计时到点触发等价 finish()；权限被拒/本机不可用/空结果/failed 四类降级文案，不崩溃；成功回调 `onRecognized` 把纯口语交回上层。
- **`RecordTabView` 🎤 入口接线**：`:92` 占位改真入口——先复用 N03 无 Key 拦截(有 Key→呈现面板、无 Key→拦截 alert +「去填写」开 `KeySetupSheet`)；单一 `fullScreenCover(item: $voiceRoute)` + `enum VoiceRoute{panel/recognizing(spoken)}` 驱动"面板→复用识别页"同一 presentation 换 item(避开双 cover 时序竞态)；注入 `makeVoiceTranscriber()`(DEBUG `MockVoiceTranscriber` 读 @AppStorage、Release `SpeechVoiceTranscriber`)+ `voiceParser`(DEBUG 固定 `.voiceSample`、Release `DeepSeekClient`，与文本 mock 分开互不污染)；`voiceRawText` 拼 `[语音转文字]\n"口语"` 前缀。
- **`TextRecognitionView` 扩展(向后兼容)**：新增 `presetText`/`source`/`rawTextOverride` 三个带默认值(nil/.text/nil)可选入参；`onAppear` 在 presetText 非 nil 时自动识别一次(`hasAutoRecognized` 防重入)；`recognize()` 直接读 `presetText ?? text` 并透传 source/rawText。默认值保证 N03 文本入口零回归。语音成功链路经此复用 N03 整套识别中→入账(source=.voice)→结果卡片/失败转手动，零改 `RecognitionResultCard`(仍 private)与失败分支。
- **DEBUG 语音 mock 开关**：新增 `DebugVoiceMockSettings.behaviorKey`(与文本 mock 分开一个 key)+ `DebugMenuView` 新增「N04 调试(语音 mock)」Section Picker 五态(成功/空结果/麦克风被拒/语音被拒/本机不可用)，tag 对齐 `MockVoiceTranscriber.Behavior` rawValue。

## 涉及文件和符号

新增：
- `Aubade/Features/Recognition/Voice/VoiceCaptureView.swift`(`VoiceCaptureView` + `VoicePhase`，@MainActor View)

改动：
- `Aubade/Features/Record/RecordTabView.swift`(顶层新增 `enum VoiceRoute`；state 新增 voiceRoute/showVoiceKeyBlockedAlert/showingVoiceKeySheet + DEBUG voiceMockRaw；🎤 入口 action；`makeVoiceTranscriber()`/`voiceParser`/`voiceRawText()`；单一 fullScreenCover(item:)；无 Key alert + KeySetupSheet)
- `Aubade/Features/Recognition/TextRecognitionView.swift`(`TextRecognitionView` 加 presetText/source/rawTextOverride + hasAutoRecognized + onAppear 自动识别；recognize() 读 presetText ?? text、透传 source/rawTextOverride。`RecognitionEntry.recognizeAndSave` 签名未改——切片01已参数化)
- `Aubade/Debug/DebugMenuView.swift`(新增 `enum DebugVoiceMockSettings` + voiceMockRaw @AppStorage + 语音 mock Picker Section)

未改(守纪)：切片01/02 契约 `VoiceTranscribing`/`MockVoiceTranscriber`/`SpeechVoiceTranscriber` 零改动；`RecognitionResultCard` 仍 private 未动；N03 失败分支(alert/转手动/重试/识别中遮罩)零改；`LedgerStore`/`TransactionEditor`/`recognizeAndSave` 签名与 N01/N02/N03 既有行为不变；📷 截图入口保持占位(N05)；无 N07 权限统一收口。

## 验证情况

- **编译**：iPhone 17 Pro 模拟器 `xcodebuild build` Debug，首次通过；第1轮评审修复后重新编译仍 BUILD SUCCEEDED(唯一 warning 为 AppIntents 元数据无害提示，与本片无关)。
- **单测**：`xcodebuild test` 全绿(107 tests, 0 failures)，含切片01 `RecognitionEntryVoiceTests`(source=.voice/带前缀 rawText/向后兼容默认 .text)与 N03 `RecognitionEntryTests` 无回归；修复后重跑仍全绿。
- **jflow-review**：2/3 轮 PASS(max 3)。第1轮双只读子 agent 独立评审——①守纪/N03不回归/验收覆盖角度 PASS(核心接缝守纪、RecognitionResultCard 仍 private、验收1-10全覆盖、provider 注入分离、无越界)；②并发/状态机角度 FAIL，确认 1 个真实阻断：`DragGesture.onChanged` 高频连触发下，start() 抛权限错使 phase=.failed 而手指仍按住时，原 `phase==.idle || isFailed` 守卫会反复放行 start()(每秒数十次抖 AVAudioSession)。主控裁决同源 agent 另一次运行误报的"finishRecording 守卫写反可重入"实为误报(外层 `guard phase==.recording`+同步置 .transcribing 已防重入)。已修复阻断1：引入 `isPressing` 按压闸门(一次物理按压只 start 一次，与 phase 正交)+ `didClose` 取消守卫(双指取消竞态)+ onDisappear 补 cancel Task(防60s Task 存活)，并删除失引用的 isFailed。第2轮只读子 agent 复核 PASS，逐点确认三处修复闭合、且"失败→松手→重按=新录音"回归路径通畅未卡死、isPressing 无死锁。

## 遗留风险和注意事项

- **真机自测未做(可选，不阻塞)**：模拟器无麦克风，走 mock 全路径；真机"按住→依次弹语音+麦克风授权→说话→finish 出文本→断网仍本机转出→关权限抛 denied 不崩溃"链路留有真机时验，节点门禁走 mock 不受阻。
- **[非阻断] SpeechVoiceTranscriber.start() 权限后缺 cancel 检查**：切片02 provider 既有设计(非本片引入)——start() 在 await 权限后、installTap 前无 `Task.checkCancellation()`，理论上权限已授权的极小同步窗口内 close 与在途 start 竞争可能重起采音；触发条件苛刻(权限未决时系统 alert 模态挡住取消)。可留后续切片处理。
- **[非阻断] 极端手势中断 isPressing 兜底**：onChanged 触发后 onEnded 未配对(系统级手势抢占且视图未销毁)理论上可致 isPressing 滞留；实践中 DragGesture 按住场景 onEnded 可靠触发、中断多伴随视图销毁(新实例复位)，当前实现已够用。
- **DEBUG 语音 parser 恒成功**：voiceParser 固定 `.voiceSample` 恒成功，"语音转出文本→parse 失败(network/noAmount)→转手动/重试"这条 N03 复用分支在 DEBUG 语音 mock 下走不到；需 Release 真实 DeepSeek 或临时切 voiceParser mock 行为触发。属可接受(该失败分支已由 N03 文本入口验收)。
- **无 Key alert 文案**：语音 alert message 用「语音记账要用到 DeepSeek…」而非 TRD §40 字面的「识别类记账…」，属本入口更贴切的合理措辞，非缺陷。

## 下一次开发

全部 TRD 已完成。下一次若继续，请从 PRD 验收标准和最终验证情况开始检查。

补充说明：
1. 读取 `current.json`：切片03 完成后 N04 三片全部完成，`next_trd` 应为空/N04 无后续切片。
2. N04 是节点最后一个切片——需更新开发 DAG `docs/design/aubade-v1-dev-dag.md` 的 N04 节点状态为完成，并按 DAG 找下一个可开发节点(N04/N05 相互独立，N05 截图 OCR 可能是下一个)，把 `next_action` 指向生成该节点 PRD(走 jflow-start/jflow-trd)。
3. 提交：本 feature 首次提交，current 分支 `feat/n04`——按 Jflow 规则首次提交前需询问用户「直接提交当前分支 feat/n04 还是新开 feature 分支」，用户明确后本 feature 后续沿用。commit 信息遵循 `type[scope]:`。
4. 若要真机验收 N04：在真机跑"按住说话→授权→本机转文字→入账→结果卡片"，验证隐私边界(requiresOnDeviceRecognition、断网可转出)。
