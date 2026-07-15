import Foundation
import SwiftData

/// 后台截图入账编排核心（脱 View、脱 AppIntent 框架、脱真系统通知）。顺序严格按技术基线 §7.3：
/// 本机 OCR → 读 Key → 解析归一落库 → 发通知意图。任何一步失败都绝不记错账。
///
/// 钉 @MainActor：与 recognizeAndSave / ModelContext 落库线程约束一致（context 非 Sendable）。
@MainActor
struct BackgroundIntakeService {
    let recognizer: any TextRecognizing
    let parser: TransactionParsing
    let store: LedgerStore
    let categories: [LedgerCategory]
    let notifier: any NotificationSending
    var keychain = KeychainStore.shared     // 默认 .shared；测试可注入造态
    let now: () -> Date                      // 注入当前时刻（测试固定）
    let imageStore: FailedImageStoring       // 失败原图留存（本片 no-op；真实实现切片 02）

    /// 入口：收到截图数据 → 跑完整条后台链路。
    /// 不抛错——后台任务须自收敛：所有失败落通知意图 + 及时返回，不把错误抛给系统。
    func intake(imageData: Data) async {
        // ① 本机 OCR（图片不外传）。.empty / .failed → 保留原图、发失败通知、不记账。
        let ocrText: String
        do {
            ocrText = try await recognizer.recognizeText(in: imageData)
        } catch {
            let ref = imageStore.save(imageData)
            await notifier.send(.failure(imageRef: ref, rawText: nil))
            return
        }

        // ② 读 Key——无 Key 直接结束（不解析、不记账）。
        guard keychain.isConfigured else {
            await notifier.send(.missingKey)
            return
        }

        // ③ 解析→归一→落库。复用 recognizeAndSave 的"落库前失败不产生脏账"不变量。
        //    前缀 [快捷指令] 对齐 N05 [截图识别] / N04 [语音转文字]：parse 输入用纯 OCR 文本，
        //    落库 rawText 带前缀，二者经 recognizeAndSave 的 text/rawText 分离。
        let prefixedRawText = "[快捷指令]\n" + ocrText
        do {
            let tx = try await RecognitionEntry.recognizeAndSave(
                text: ocrText, categories: categories,
                parser: parser, store: store, now: now(),
                source: .screenshotShortcut,
                rawText: prefixedRawText)
            // ④ 成功 → 发成功通知（imageRef 恒 nil，成功不留存原图）。
            await notifier.send(.success(
                transactionID: tx.id,
                amountText: AmountFormat.plainString(tx.amount),
                categoryName: tx.category?.name,
                merchant: tx.merchant))
        } catch {
            // ⑤ 解析/归一/落库失败 → 回滚清除可能残留的 pending insert（守脏账，对齐 TextRecognitionView 手法），
            //    保留原图、发失败通知（带原文供补录带入）、不记账。
            store.context.rollback()
            let ref = imageStore.save(imageData)
            await notifier.send(.failure(imageRef: ref, rawText: prefixedRawText))
        }
    }
}
