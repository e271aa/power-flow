import PowerFlowCore
import SwiftUI

/// Para onde vão os watts dentro do sistema.
///
/// É o que o AlDente não mostra: não só quanto a máquina consome, mas
/// que parte dela está a consumir.
struct BreakdownView: View {
    let snapshot: PowerSnapshot

    private struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let watts: Double
        let color: Color
    }

    private var slices: [Slice] {
        var result: [Slice] = []
        if let soc = snapshot.socPower {
            result.append(Slice(label: "SoC (CPU/GPU)", watts: soc,
                                color: Color(red: 0.55, green: 0.45, blue: 0.95)))
        }
        if let main = snapshot.mainRailPower {
            result.append(Slice(label: "Ecrã e I/O", watts: main,
                                color: Color(red: 0.30, green: 0.70, blue: 0.85)))
        }
        if let other = snapshot.otherPower, other > 0.1 {
            result.append(Slice(label: "Outros", watts: other,
                                color: Color.secondary.opacity(0.45)))
        }
        return result
    }

    var body: some View {
        let slices = slices
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
                                .fill(slice.color)
                                .frame(width: max(proxy.size.width * slice.watts / total - 2, 2))
                        }
                    }
                }
                .frame(height: 8)
                .animation(.easeOut(duration: 0.45), value: total)

                HStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 4) {
                            Circle().fill(slice.color).frame(width: 6, height: 6)
                            Text(slice.label)
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
