import Foundation

/// O título do item da barra de menus: o que se escreve e com que frequência
/// pode mudar.
///
/// Como o `PanelCopy`: o controlador do item não formata nem decide; pede o
/// texto e a regra de quando o mostrar.
public enum BarTitle {
    /// O que o título mostra, depois de ter em conta o Mac. «Ícone e %» num Mac
    /// sem bateria não tem percentagem para mostrar: cai nos watts.
    public enum Content: Equatable, Sendable {
        case empty, watts, percent
    }

    public static func content(mode: BarMode, hasBattery: Bool) -> Content {
        switch mode {
        case .icon: .empty
        case .iconWatts, .watts: .watts
        case .iconPercent: hasBattery ? .percent : .watts
        }
    }

    /// «36 W» (inteiro) ou «80 %», com espaço não separável. Sem leitura do
    /// consumo, um travessão: nunca «0 W», que seria uma medição inventada.
    public static func text(_ content: Content, snapshot: PowerSnapshot,
                            language: String = L10n.language) -> String {
        let format = PFFormat(locale: Locale(identifier: language))
        switch content {
        case .empty:
            return ""
        case .watts:
            return snapshot.systemTotal.map { format.watts($0, decimals: 0) } ?? "—"
        case .percent:
            return format.percent(snapshot.battery.percentage)
        }
    }

    /// A dica do item, que diz o que o título diz mais o que ele é.
    public static func toolTip(snapshot: PowerSnapshot, sensorsAvailable: Bool,
                               language: String = L10n.language) -> String {
        guard sensorsAvailable, let total = snapshot.systemTotal else {
            return L10n.string("tt_status_off", language: language)
        }
        return L10n.string("tt_status", language: language,
                           args: [PFFormat(locale: Locale(identifier: language)).watts(total)])
    }
}

/// Segura o título para ele mudar, no máximo, de 2 em 2 s.
///
/// O item da barra redesenha-se a cada mudança e empurra os vizinhos quando a
/// largura varia; um consumo que oscila a 1 Hz faria o título tremer. O texto
/// pedido vai mudando; o mostrado só o acompanha passados 2 s da última
/// mudança. As ordens do utilizador (outro modo) passam logo.
public struct BarTitleThrottle {
    public static let minimumInterval: TimeInterval = 2

    public private(set) var shown: String?
    private var changedAt: Date?

    public init() {}

    /// O que mostrar agora, tendo `wanted` como o texto atual.
    public mutating func shown(for wanted: String, at now: Date, immediately: Bool = false) -> String {
        if let current = shown, let changedAt, !immediately {
            if current == wanted { return current }
            if now.timeIntervalSince(changedAt) < Self.minimumInterval { return current }
        }
        shown = wanted
        changedAt = now
        return wanted
    }
}
