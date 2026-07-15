import Foundation

/// 后台失败时把原图写本机临时目录，返回 imageRef（文件名）。供点通知补录时取回；
/// 成功入账不留原图（imageRef 恒 nil，不经此 store），仅失败分支调 save（约定 8）。
///
/// @MainActor 与协议 FailedImageStoring 隔离一致（只在 BackgroundIntakeService 调用链内被调）。
struct TemporaryImageStore: FailedImageStoring {
    /// 临时目录：temporaryDirectory/AubadeShortcutIntake（仅存后台失败待补录原图，非长期图库；v1 不做图库）。
    private var dir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AubadeShortcutIntake", isDirectory: true)
    }

    func save(_ imageData: Data) -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".img"
        guard (try? imageData.write(to: dir.appendingPathComponent(name))) != nil else { return nil }
        return name                                     // imageRef = 文件名（相对临时目录）
    }

    func loadImage(ref: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(ref))
    }

    func remove(ref: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(ref))
    }

    /// App 启动清理上次残留：待补录意图只在"通知还在通知中心且未处理"期间有效，
    /// 重启后不做跨启动持久化补录队列（尽力而为），残留由此兜底，避免过度设计。
    func purgeAll() {
        try? FileManager.default.removeItem(at: dir)
    }
}
