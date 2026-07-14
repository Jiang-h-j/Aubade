import SwiftUI

/// 账单流水单行（切片 03）：左分类彩标（emoji + 名）+ 中商户/备注摘要 + 右方向金额。
///
/// 取色/金额格式与记账页最近记录（切片 02 `RecentTransactionRow`）同源：`CategoryStyle` 走
/// **主 API** `color(name:direction:)`（nil 分类走方向兜底，勿用便利 `color(for:)` 丢方向），
/// `AmountFormat.signedString` 出符号千分位串。
struct LedgerRowView: View {
    let tx: Transaction

    /// 商户 > 备注 > 兜底显示发生时间（避免与分类名行重复）。
    private var subtitle: String {
        if let m = tx.merchant, !m.isEmpty { return m }
        if let n = tx.note, !n.isEmpty { return n }
        return tx.occurredAt.formatted(date: .omitted, time: .shortened)
    }

    private var categoryName: String {
        tx.category?.name ?? "未分类"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(CategoryStyle.emoji(for: tx.category))
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(
                    CategoryStyle.color(name: tx.category?.name, direction: tx.direction).opacity(0.15),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(AmountFormat.signedString(tx.amount, direction: tx.direction))
                .font(.body.monospacedDigit())
                .foregroundStyle(AmountFormat.color(for: tx.direction))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
