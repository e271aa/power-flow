import PowerFlowCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        let panel = monitor.panel

        VStack(alignment: .leading, spacing: 14) {
            if panel.kind != .unavailable {
                FlowDiagram(snapshot: monitor.snapshot, panel: panel)

                Divider().opacity(0.5)
                BreakdownView(slices: monitor.snapshot.breakdown)

                Divider().opacity(0.5)
                HistoryChart(samples: monitor.history.recent(seconds: 120))

                if panel.showsBattery {
                    Divider().opacity(0.5)
                    BatteryHealthView(battery: monitor.snapshot.battery,
                                      temperature: monitor.snapshot.batteryTemperature,
                                      time: panel.time)
                }
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
            Label(L10n.string("u_title"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text(L10n.string("u_body"))
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
            Button(L10n.string("m_quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var sourceLabel: String {
        switch monitor.panel.origin {
        case .battery:
            return L10n.string("v1_source_battery")
        case .mains, .adapter, .adapterAndBattery:
            let name = monitor.snapshot.battery.adapterName
            return name.isEmpty ? L10n.string("v1_source_mains") : name
        }
    }
}
