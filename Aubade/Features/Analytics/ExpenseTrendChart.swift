import SwiftUI
import Charts

/// 支出趋势折线图（N02 切片 03，验收 5）：消费 `StatisticsAggregator.expenseTrend` 的 `[(label, value)]`，
/// 用 iOS 16+ 原生 Swift Charts 渲染折线 + 面积渐变 + 峰值高亮 + 峰值/均值副标题。
///
/// 选型：Swift Charts 是系统框架、零第三方依赖，原生覆盖折线/面积渐变/标注（TRD §1）。
/// demo 用 SVG 仅因它是网页原型；此处只复刻视觉效果（折线 + 面积 + 峰值/均值），不复刻 SVG。
/// `Decimal → Double` 仅用于绘图坐标，不参与金额计算，精度无关。
struct ExpenseTrendChart: View {
    /// 来自 `expenseTrend`：桶跟随粒度（year=12月/month=当月每日/week&day=所在周7天）。
    let series: [(label: String, value: Decimal)]

    private var values: [Double] {
        series.map { ($0.value as NSDecimalNumber).doubleValue }
    }

    /// 峰值 = 最大桶（对齐 demo `Math.max(...values)`）。
    private var peak: Decimal {
        series.map(\.value).max() ?? 0
    }

    /// 均值 = 总和 / 桶数（对齐 demo `sum/values.length`，除数为全部桶含 0 桶）。
    private var average: Decimal {
        guard !series.isEmpty else { return 0 }
        let sum = series.reduce(Decimal(0)) { $0 + $1.value }
        var avg = sum / Decimal(series.count)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &avg, 0, .plain)
        return rounded
    }

    /// 峰值桶下标（高亮点用）；多个等值取首个，对齐 demo `indexOf(max)`。
    private var peakIndex: Int? {
        guard let maxV = series.map(\.value).max(), maxV > 0 else { return nil }
        return series.firstIndex { $0.value == maxV }
    }

    /// x 轴标签稀疏化：桶多时（当月每日 28~31 桶）只显示首/中/尾，避免标签重叠。
    /// 桶数 ≤ 12（周档 7 天 / 年档 12 月）全显示；> 12（当月每日）抽首、中、尾三个。
    private func axisLabel(at index: Int) -> String? {
        let n = series.count
        guard n > 0 else { return nil }
        if n <= 12 { return series[index].label }
        let marks: Set<Int> = [0, n / 2, n - 1]
        return marks.contains(index) ? series[index].label : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            Text("峰值 ¥\(AmountFormat.plainString(peak)) · 均值 ¥\(AmountFormat.plainString(average))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("序号", index), y: .value("支出", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                AreaMark(x: .value("序号", index), y: .value("支出", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
            }
            if let peakIndex {
                PointMark(x: .value("序号", peakIndex),
                          y: .value("支出", values[peakIndex]))
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .top) {
                        Text("¥\(AmountFormat.plainString(peak))")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: Array(0..<series.count)) { value in
                if let index = value.as(Int.self), let label = axisLabel(at: index) {
                    AxisValueLabel {
                        Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
    }
}
