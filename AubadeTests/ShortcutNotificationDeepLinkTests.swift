import XCTest
import UserNotifications
@testable import Aubade

/// TRD 02 §验证点 6：切片 02 可测部分的纯函数 / 冒烟单测——
/// ① UNUserNotificationCenterNotifier.makeContent：IntakeNotification → title/body/userInfo 映射（不真弹）；
/// ② TemporaryImageStore：save → load → remove → purgeAll 冒烟（真读写临时目录）；
/// ③ AppDelegate.intent：通知 userInfo → DeepLinkIntent 解析（含空串/坏值降级）。
/// 真弹通知 / 真点击 / 真机后台由用户自测。
@MainActor
final class ShortcutNotificationDeepLinkTests: XCTestCase {

    // MARK: - ① makeContent：三类通知的 title/body/userInfo

    func testSuccessContentFullFields() {
        let id = UUID()
        let content = UNUserNotificationCenterNotifier.makeContent(
            for: .success(transactionID: id, amountText: "88.50", categoryName: "食", merchant: "星巴克"))

        XCTAssertEqual(content.title, "已记一笔")
        XCTAssertEqual(content.body, "¥88.50 · 食 · 星巴克")
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.kind] as? String,
                       UNUserNotificationCenterNotifier.Kind.success)
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.txID] as? String, id.uuidString)
    }

    func testSuccessContentOmitsNilCategoryAndMerchant() {
        let content = UNUserNotificationCenterNotifier.makeContent(
            for: .success(transactionID: UUID(), amountText: "12.00", categoryName: nil, merchant: nil))
        // 分类/商户为 nil 时省略，只留金额
        XCTAssertEqual(content.body, "¥12.00")
    }

    func testSuccessContentOmitsMerchantOnly() {
        let content = UNUserNotificationCenterNotifier.makeContent(
            for: .success(transactionID: UUID(), amountText: "5.00", categoryName: "食", merchant: nil))
        XCTAssertEqual(content.body, "¥5.00 · 食")
    }

    func testSuccessContentTreatsEmptyStringAsOmitted() {
        // 空串（非 nil）与 nil 同样省略，不产生尾部 " · "
        let content = UNUserNotificationCenterNotifier.makeContent(
            for: .success(transactionID: UUID(), amountText: "9.00", categoryName: "", merchant: ""))
        XCTAssertEqual(content.body, "¥9.00")
    }

    func testFailureContentCarriesImageRefAndRawText() {
        let content = UNUserNotificationCenterNotifier.makeContent(
            for: .failure(imageRef: "abc.img", rawText: "[快捷指令]\n星巴克 88.50"))

        XCTAssertEqual(content.title, "没识别出这张截图")
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.kind] as? String,
                       UNUserNotificationCenterNotifier.Kind.failure)
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.imageRef] as? String, "abc.img")
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.rawText] as? String, "[快捷指令]\n星巴克 88.50")
    }

    func testFailureContentNilFieldsBecomeEmptyString() {
        // OCR 本身失败：imageRef/rawText 皆 nil → userInfo 存空串（解析侧再还原为 nil）
        let content = UNUserNotificationCenterNotifier.makeContent(for: .failure(imageRef: nil, rawText: nil))
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.imageRef] as? String, "")
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.rawText] as? String, "")
    }

    func testMissingKeyContent() {
        let content = UNUserNotificationCenterNotifier.makeContent(for: .missingKey)
        XCTAssertEqual(content.title, "请先配置 DeepSeek Key")
        XCTAssertEqual(content.userInfo[UNUserNotificationCenterNotifier.Key.kind] as? String,
                       UNUserNotificationCenterNotifier.Kind.missingKey)
    }

    // MARK: - ② TemporaryImageStore：save → load → remove → purgeAll

    func testImageStoreSaveLoadRemove() throws {
        let store = TemporaryImageStore()
        let data = Data([0x0A, 0x0B, 0x0C])

        let ref = try XCTUnwrap(store.save(data), "save 应返回非 nil imageRef")
        XCTAssertEqual(store.loadImage(ref: ref), data, "load 应取回原数据")

        store.remove(ref: ref)
        XCTAssertNil(store.loadImage(ref: ref), "remove 后应取不到")
    }

    func testImageStorePurgeAllClearsResiduals() throws {
        let store = TemporaryImageStore()
        let ref1 = try XCTUnwrap(store.save(Data([0x01])))
        let ref2 = try XCTUnwrap(store.save(Data([0x02])))

        store.purgeAll()
        XCTAssertNil(store.loadImage(ref: ref1))
        XCTAssertNil(store.loadImage(ref: ref2))
    }

    func testImageStoreLoadMissingReturnsNil() {
        // 未 save 过的 ref → nil，不崩溃
        XCTAssertNil(TemporaryImageStore().loadImage(ref: "does-not-exist.img"))
    }

    // MARK: - ③ AppDelegate.intent：userInfo → DeepLinkIntent

    func testIntentSuccessParsesTransactionID() {
        let id = UUID()
        let intent = AppDelegate.intent(from: [
            UNUserNotificationCenterNotifier.Key.kind: UNUserNotificationCenterNotifier.Kind.success,
            UNUserNotificationCenterNotifier.Key.txID: id.uuidString,
        ])
        XCTAssertEqual(intent, .openTransaction(id))
    }

    func testIntentSuccessWithBadUUIDReturnsNil() {
        let intent = AppDelegate.intent(from: [
            UNUserNotificationCenterNotifier.Key.kind: UNUserNotificationCenterNotifier.Kind.success,
            UNUserNotificationCenterNotifier.Key.txID: "not-a-uuid",
        ])
        XCTAssertNil(intent)
    }

    func testIntentFailureCarriesRawTextAndImageRef() {
        let intent = AppDelegate.intent(from: [
            UNUserNotificationCenterNotifier.Key.kind: UNUserNotificationCenterNotifier.Kind.failure,
            UNUserNotificationCenterNotifier.Key.rawText: "[快捷指令]\nfoo",
            UNUserNotificationCenterNotifier.Key.imageRef: "x.img",
        ])
        XCTAssertEqual(intent, .manualEntry(rawText: "[快捷指令]\nfoo", imageRef: "x.img"))
    }

    func testIntentFailureEmptyStringsBecomeNil() {
        // 发送侧用空串占位 optional → 解析还原为 nil
        let intent = AppDelegate.intent(from: [
            UNUserNotificationCenterNotifier.Key.kind: UNUserNotificationCenterNotifier.Kind.failure,
            UNUserNotificationCenterNotifier.Key.rawText: "",
            UNUserNotificationCenterNotifier.Key.imageRef: "",
        ])
        XCTAssertEqual(intent, .manualEntry(rawText: nil, imageRef: nil))
    }

    func testIntentMissingKey() {
        let intent = AppDelegate.intent(from: [
            UNUserNotificationCenterNotifier.Key.kind: UNUserNotificationCenterNotifier.Kind.missingKey,
        ])
        XCTAssertEqual(intent, .configureKey)
    }

    func testIntentUnknownKindReturnsNil() {
        XCTAssertNil(AppDelegate.intent(from: [UNUserNotificationCenterNotifier.Key.kind: "bogus"]))
        XCTAssertNil(AppDelegate.intent(from: [:]))
    }

    // MARK: - ④ 失败补录预填备注：去 [快捷指令] 前缀

    func testPrefillNoteStripsShortcutPrefix() {
        XCTAssertEqual(
            RecordTabView.prefillNote(fromRawText: "[快捷指令]\n星巴克 88.50"),
            "星巴克 88.50")
    }

    func testPrefillNoteNilStaysNil() {
        XCTAssertNil(RecordTabView.prefillNote(fromRawText: nil))
    }

    func testPrefillNoteWithoutPrefixReturnsAsIs() {
        XCTAssertEqual(RecordTabView.prefillNote(fromRawText: "无前缀原文"), "无前缀原文")
    }
}
