import Charts
import PowerFlowCore
import SwiftUI

/// Consumo do sistema nos últimos minutos.
struct HistoryChart: View {
    let samples: [PowerHistory.Sample]

    var body: some View {
        if samples.count > 2 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.string("v1_last", PFFormat().integer(samples.count)))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.4)
                    Spacer()
                    Text(L10n.string("h_peak") + " " + PFFormat().watts(samples.map(\.systemTotal).max() ?? 0))
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                Chart {
                    ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                        AreaMark(
                            x: .value("t", index),
                            y: .value("W", sample.systemTotal)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [PFColor.blue.opacity(0.45),
                                         PFColor.blue.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("t", index),
                            y: .value("W", sample.systemTotal)
                        )
                        .foregroundStyle(PFColor.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel().font(.system(size: 8))
                    }
                }
                .frame(height: 58)
            }
        }
    }
}
