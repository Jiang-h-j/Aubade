import Foundation

/// 文本识别的界面状态机（视图局部 @State 驱动，不引额外框架）。
///
/// 成功不设独立 phase——识别成功即入账并 dismiss 回记账页；
/// 切片 03 才在成功后改为弹结果卡片。
enum RecognitionPhase: Equatable {
    case idle                       // 编辑文本，可提交
    case recognizing                // 识别中：禁重复提交 + 全屏 spinner
    case failed(RecognitionError)   // 失败：按错误显示对应文案（转手动在切片 03）
}
