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
        case .soc:      return L10n.string("bd_soc")
        case .mainRail: return L10n.string("bd_main")
        case .other:    return L10n.string("bd_rest")
        }
    }

    private func color(_ kind: BreakdownSlice.Kind) -> Color {
        switch kind {
        case .soc:      return PFColor.blue
        case .mainRail: return PFColor.blue2
        case .other:    return PFColor.rest
        }
    }

    var body: some View {
        let total = max(slices.reduce(0) { $0 + $1.watts }, 0.001)

        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string("bd_title"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: PFRadius.appBar, style: .continuous)
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
                            Text(PFFormat().watts(slice.watts))
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
