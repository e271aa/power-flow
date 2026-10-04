import AppKit
import PowerFlowCore
import SwiftUI
import UniformTypeIdentifiers

/// O que a vista «Consumo por app» recebe: as médias das apps e a do sistema
/// na mesma janela.
struct AppsInput {
    var report: AppEnergyReport = .empty()
    /// `nil`: sem leitura do consumo do sistema.
    var systemAverage: Double?
}

/// «Consumo por app», no nível 2 do painel.
struct AppsView: View {
    let input: AppsInput
    let back: () -> Void

    /// A ordem das linhas enquanto o rato está por cima da lista: assim uma
    /// linha não foge de baixo do ponteiro quando chega a média seguinte.
    @State private var frozenOrder: [String]?

    private static let rowHeight: CGFloat = 42
    private static let iconSize: CGFloat = 24
    private static let valueWidth: CGFloat = 60
    /// O que o fundo do hover sai para cada lado das linhas.
    private static let hoverInset: CGFloat = 6

    var body: some View {
        let copy = AppsCopy(report: input.report, systemAverage: input.systemAverage,
                            frozenOrder: frozenOrder)

        VStack(alignment: .leading, spacing: 0) {
            PanelSubHeader(title: copy.title, subtitle: copy.subtitle, back: back)

            VStack(alignment: .leading, spacing: 0) {
                if copy.isWaiting {
                    waiting(copy)
                } else {
                    ForEach(copy.rows) { row in
                        appRow(row)
                    }
                    if copy.hasTotal {
                        otherRow(copy)
                        Text(copy.otherNote)
                            .pfType(.minimum)
                            .foregroundStyle(PFColor.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(EdgeInsets(top: 0, leading: Self.iconSize + 10, bottom: 10, trailing: 0))
                    }
                }
            }
            .padding(EdgeInsets(top: 6, leading: PFSpace.popoverMargin, bottom: PFSpace.xs,
                                trailing: PFSpace.popoverMargin))
            .onHover { inside in
                frozenOrder = inside ? copy.order : nil
            }

            VStack(spacing: 0) {
                Rectangle().fill(PFColor.sep).frame(height: 1)
                HStack {
                    Text(copy.totalLabel)
                    Spacer(minLength: PFSpace.s)
                    Text(copy.total).fontWeight(.semibold).monospacedDigit()
                }
                .font(PFFont.body)
                .foregroundStyle(PFColor.fg)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, PFSpace.popoverMargin)

            Text(copy.footnote)
                .pfType(.minimum)
                .foregroundStyle(PFColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 0, leading: PFSpace.popoverMargin, bottom: 14,
                                    trailing: PFSpace.popoverMargin))
        }
    }

    private func waiting(_ copy: AppsCopy) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
                .frame(width: Self.iconSize, height: Self.iconSize)
            Text(copy.waiting)
                .font(PFFont.body)
                .foregroundStyle(PFColor.fg2)
            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
    }

    private func appRow(_ row: AppsCopy.Row) -> some View {
        Button {
            guard let pid = row.pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
            if #available(macOS 14, *) {
                app.activate()
            } else {
                app.activate(options: [])
            }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: AppIcons.icon(key: row.key, bundleIdentifier: row.bundleIdentifier, pid: row.pid))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .opacity(row.isRunning ? 1 : 0.5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: PFSpace.xs) {
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let ended = row.endedLabel {
                            Text(ended).lineLimit(1).fixedSize()
                        }
                    }
                    .font(.system(size: 13))
                    .frame(height: 16)
                    .foregroundStyle(row.isRunning ? PFColor.fg : PFColor.fg2)

                    bar(fraction: row.fraction, color: PFColor.blue)
                }

                Text(row.value)
                    .font(PFFont.title)
                    .monospacedDigit()
                    .foregroundStyle(PFColor.fg)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
            .padding(.horizontal, Self.hoverInset)
            .frame(height: Self.rowHeight)
        }
        .buttonStyle(PFHoverButtonStyle(radius: PFRadius.button))
        .disabled(row.pid == nil)
        .padding(.horizontal, -Self.hoverInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(row.pid == nil ? [] : .isButton)
    }

    private func otherRow(_ copy: AppsCopy) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 13))
                .foregroundStyle(PFColor.fg2)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background {
                    RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous).fill(PFColor.fill)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(copy.otherName)
                    .font(.system(size: 13))
                    .foregroundStyle(PFColor.fg)
                    .frame(height: 16)
                bar(fraction: copy.otherFraction, color: PFColor.rest)
            }

            Text(copy.otherValue)
                .font(PFFont.title)
                .monospacedDigit()
                .foregroundStyle(PFColor.fg)
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.otherAccessibilityLabel)
    }

    /// A barra de 4 pt: trilho `fill`, valor na cor da linha.
    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(PFColor.fill)
                Capsule().fill(color).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Os ícones das apps, guardados por chave: uma app que terminou continua a
/// ter o seu.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(key: String, bundleIdentifier: String?, pid: pid_t?) -> NSImage {
        if let cached = cache[key] { return cached }
        let icon = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
            ?? bundleIdentifier
                .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        cache[key] = icon
        return icon
    }
}
