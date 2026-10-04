import PowerFlowCore
import SwiftUI

extension BreakdownSlice.Kind {
    var label: String {
        switch self {
        case .soc:      return L10n.string("bd_soc")
        case .mainRail: return L10n.string("bd_main")
        case .other:    return L10n.string("bd_rest")
        }
    }

    /// Preenchimento. Nunca é texto.
    var color: Color {
        switch self {
        case .soc:      return PFColor.blue
        case .mainRail: return PFColor.blue2
        case .other:    return PFColor.rest
        }
    }
}

/// «Onde se gasta»: para onde vão os watts dentro do sistema.
///
/// O resto da placa não é medido, é a diferença. Por isso desenha-se
/// tracejado: a cor sozinha não chegava para o distinguir de uma medição.
struct BreakdownView: View {
    let slices: [BreakdownSlice]
    /// `nil`: sem botão «Por app».
    var openApps: (() -> Void)?

    private static let barHeight: CGFloat = 10
    private static let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: PFSpace.s) {
            HStack(spacing: PFSpace.s) {
                Text(L10n.string("bd_title"))
                    .pfType(.title)
                    .foregroundStyle(PFColor.fg)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let openApps {
                    Button(action: openApps) {
                        HStack(spacing: 2) {
                            Text(L10n.string("bd_byapp"))
                                .font(PFFont.secondary)
                                .foregroundStyle(PFColor.fg)
                            PFDisclosure()
                        }
                        .padding(.leading, PFSpace.s)
                        .padding(.trailing, PFSpace.xs)
                        // 22 pt à vista; a área de clique tem os 24 pt mínimos.
                        .frame(height: 24)
                    }
                    .buttonStyle(PFHoverButtonStyle(radius: PFRadius.segment))
                    .padding(.trailing, -PFSpace.xs)
                    .padding(.vertical, -3.5)
                }
            }

            bar

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PFSpace.s, alignment: .topLeading),
                                     count: 3),
                      alignment: .leading, spacing: PFSpace.s) {
                ForEach(slices) { slice in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            BreakdownSwatch(kind: slice.kind)
                                .frame(width: 8, height: 8)
                            // Quebra em vez de cortar ou de encolher abaixo de 11 pt.
                            Text(slice.kind.label)
                                .pfType(.secondary)
                                .foregroundStyle(PFColor.fg2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(PFFormat().watts(slice.watts))
                            .pfType(.title)
                            .monospacedDigit()
                            .foregroundStyle(PFColor.fg)
                            .padding(.leading, 14)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if slices.contains(where: { $0.kind == .other }) {
                Text(L10n.string("bd_rest_note"))
                    .pfType(.minimum)
                    .foregroundStyle(PFColor.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let widths = BreakdownLayout.widths(for: slices.map(\.watts), total: proxy.size.width,
                                                gap: Self.gap)
            HStack(spacing: Self.gap) {
                ForEach(Array(zip(slices, widths)), id: \.0.id) { slice, width in
                    BreakdownSwatch(kind: slice.kind, radius: PFRadius.breakdownBar,
                                    stripe: 2, space: 2.5)
                        .frame(width: width)
                }
            }
        }
        .frame(height: Self.barHeight)
        .accessibilityHidden(true)
    }
}

/// Um bocado de barra ou uma amostra da legenda. O resto é tracejado a 135°,
/// com contorno, para se ler como «não medido» sem depender da cor.
private struct BreakdownSwatch: View {
    let kind: BreakdownSlice.Kind
    var radius: CGFloat = PFRadius.appBar
    var stripe: CGFloat = 1.5
    var space: CGFloat = 1.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if kind == .other {
            Canvas { context, size in
                // Riscos a 135°: descem da direita para a esquerda.
                let period = (stripe + space) * 2.0.squareRoot()
                var x = -size.height
                while x < size.width + size.height {
                    var line = Path()
                    line.move(to: CGPoint(x: x + size.height, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(kind.color), lineWidth: stripe)
                    x += period
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(kind.color, lineWidth: 1) }
        } else {
            shape.fill(kind.color)
        }
    }
}
