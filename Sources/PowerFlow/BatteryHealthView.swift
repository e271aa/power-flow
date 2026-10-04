import PowerFlowCore
import SwiftUI

/// Saúde e estado da bateria, por baixo do diagrama.
struct BatteryHealthView: View {
    let battery: BatteryInfo
    let temperature: Double?
    /// O tempo a mostrar, já decidido pelo `PanelState`.
    let time: PanelState.Time

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Bateria")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)

            // Grelha de duas colunas: o suficiente para caber sem apertar.
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    metric("Carga", "\(battery.percentage) %")
                    metric("Ciclos", "\(battery.cycleCount)")
                }
                VStack(alignment: .leading, spacing: 5) {
                    if let health = battery.healthPercent {
                        metric("Saúde", String(format: "%.0f %%", health))
                    }
                    if let temperature {
                        metric("Temperatura", String(format: "%.1f °C", temperature))
                    }
                }
                Spacer(minLength: 0)
            }

            if let explanation = battery.chargingExplanation {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(FlowNode.battery.tint)
                    Text(explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }

            if let timeText {
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var timeText: String? {
        switch time {
        case .none:                       return nil
        case .remaining(let minutes):     return "\(duration(minutes)) restantes"
        case .untilFull(let minutes):     return "\(duration(minutes)) até carregar"
        }
    }

    private func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours) h \(rest) min" : "\(rest) min"
    }
}
