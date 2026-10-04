import PowerFlowCore
import SwiftUI

/// Para onde vão os watts dentro do sistema.
///
/// É o que o AlDente não mostra: não só quanto a máquina consome, mas
/// que parte dela está a consumir.
struct BreakdownView: View {
    let slices: [BreakdownSlice]

    private func label(_ kind: BreakdownSlice.Kind) -> String {
        switch kind {
        case .soc:      return "SoC (CPU/GPU)"
        case .mainRail: return "Ecrã e I/O"
        case .other:    return "Outros"
        }
    }

    private func color(_ kind: BreakdownSlice.Kind) -> Color {
        switch kind {
        case .soc:      return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .mainRail: return Color(red: 0.30, green: 0.70, blue: 0.85)
        case .other:    return Color.secondary.opacity(0.45)
        }
    }

    var body: some View {
        let total = max(slices.reduce(0) { $0 + $1.watts }, 0.001)

        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Repartição do consumo")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(slice.kind))
                                .frame(width: max(proxy.size.width * slice.watts / total - 2, 2))
                        }
                    }
                }
                .frame(height: 8)

                HStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 4) {
                            Circle().fill(color(slice.kind)).frame(width: 6, height: 6)
                            Text(label(slice.kind))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f W", slice.watts))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
