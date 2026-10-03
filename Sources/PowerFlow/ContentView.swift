import PowerFlowCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if monitor.isAvailable {
                FlowDiagram(snapshot: monitor.snapshot)
                    .frame(height: 235)

                Divider().opacity(0.5)
                BreakdownView(snapshot: monitor.snapshot)

                Divider().opacity(0.5)
                HistoryChart(samples: monitor.history.recent(seconds: 120))

                Divider().opacity(0.5)
                BatteryHealthView(battery: monitor.snapshot.battery,
                                  temperature: monitor.snapshot.batteryTemperature)
            } else {
                unavailable
            }

            Divider().opacity(0.5)
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sensores indisponíveis", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text("Não foi possível ler as chaves de potência do SMC neste Mac. "
                 + "Corre `PowerFlow --dump` no Terminal para ver o diagnóstico.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text(sourceLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var sourceLabel: String {
        switch monitor.snapshot.source {
        case .adapter:
            let name = monitor.snapshot.battery.adapterName
            return name.isEmpty ? "Ligado à corrente" : name
        case .battery:
            return "A funcionar com bateria"
        }
    }
}
