import PowerFlowCore
import SwiftUI

/// O detalhe da bateria, no nível 2 do painel.
struct BatteryDetailView: View {
    let copy: BatteryCopy
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSubHeader(title: L10n.string("r_batt"), subtitle: copy.subtitle, back: back)

            VStack(alignment: .leading, spacing: 1) {
                Text(copy.percent)
                    .pfType(.display)
                    .monospacedDigit()
                    .kerning(-0.28)
                    .foregroundStyle(PFColor.fg)
                Text(copy.state)
                    .pfType(.body)
                    .foregroundStyle(PFColor.fg2)
            }
            .accessibilityElement(children: .combine)
            .padding(EdgeInsets(top: 14, leading: PFSpace.popoverMargin, bottom: 6,
                                trailing: PFSpace.popoverMargin))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: PFSpace.l, alignment: .topLeading),
                                     count: 2),
                      alignment: .leading, spacing: PFSpace.m) {
                ForEach(copy.metrics) { metric in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.label)
                            .pfType(.secondary)
                            .foregroundStyle(PFColor.fg2)
                        Text(metric.value)
                            .pfType(.value)
                            .monospacedDigit()
                            .foregroundStyle(PFColor.fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let detail = metric.detail {
                            Text(detail)
                                .pfType(.minimum)
                                .monospacedDigit()
                                .foregroundStyle(PFColor.fg2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(EdgeInsets(top: PFSpace.s, leading: PFSpace.popoverMargin, bottom: 14,
                                trailing: PFSpace.popoverMargin))

            if let why = copy.why {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("b_why"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(why)
                        .pfType(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(PFColor.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, PFSpace.m)
                .background {
                    RoundedRectangle(cornerRadius: PFRadius.banner, style: .continuous).fill(PFColor.fill)
                }
                .accessibilityElement(children: .combine)
                .padding(EdgeInsets(top: 0, leading: PFSpace.popoverMargin, bottom: PFSpace.l,
                                    trailing: PFSpace.popoverMargin))
            }
        }
    }
}

/// «Consumo por app». O conteúdo é da Fase 7; por agora só o que já se sabe: o total.
struct AppsView: View {
    let total: String
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSubHeader(title: L10n.string("a_title"), subtitle: L10n.string("a_sub"), back: back)

            HStack {
                Text(L10n.string("a_total"))
                Spacer(minLength: PFSpace.s)
                Text(total).fontWeight(.semibold).monospacedDigit()
            }
            .font(PFFont.body)
            .foregroundStyle(PFColor.fg)
            .padding(.vertical, 10)
            .padding(.horizontal, PFSpace.popoverMargin)
            .accessibilityElement(children: .combine)
        }
    }
}
