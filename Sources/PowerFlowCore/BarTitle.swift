import Foundation

/// O que o item da barra de menus mostra, como função do instantâneo.
///
/// Como o `PanelCopy`: o controlador do item não formata nem decide; recebe
/// o que desenhar, a dica e o valor do VoiceOver. A bateria e os watts são
/// uma só imagem (`MenuBarIcon`), por isso não há título no botão.
public struct BarItem: Hashable, Sendable {
    /// O que a imagem leva, depois de ter em conta o Mac: sem bateria, tudo
    /// cai em «Só watts» (o valor guardado não muda).
    public enum Content: Hashable, Sendable {
        case battery, batteryWatts, watts
        /// O ícone da app (os três nós do diagrama) e os watts.
        case flowWatts
    }

    /// A leitura do consumo que o item mostra.
    public enum Reading: Hashable, Sendable {
        /// Watts inteiros.
        case watts(Int)
        /// Os primeiros segundos, antes de as médias estabilizarem.
        case settling
        /// Sem leitura dos sensores.
        case unavailable
    }

    public let content: Content
    /// 0 a 100. Vem do IORegistry: não depende dos sensores.
    public let percent: Int
    /// Os algarismos dentro da bateria. A dica e o VoiceOver dizem a
    /// percentagem na mesma.
    public let showsPercent: Bool
    /// A carregar, pelo IORegistry. É o que a dica e o VoiceOver dizem.
    public let isCharging: Bool
    /// O raio. Como no ícone do sistema, aparece com o cabo ligado, também com
    /// a carga em pausa (medido na barra, aos 80 % em pausa).
    public let showsBolt: Bool
    public let hasBattery: Bool
    /// A energia vem da bateria (sem o cabo). No ícone da app, o nó do
    /// adaptador fica vazado.
    public let isOnBattery: Bool
    public var reading: Reading

    /// Um item com valores fixos: os mosaicos das Definições e a pré-visualização.
    public init(content: Content, percent: Int, isCharging: Bool, showsBolt: Bool? = nil,
                showsPercent: Bool = true, hasBattery: Bool = true, isOnBattery: Bool = false,
                reading: Reading) {
        self.content = content
        self.isOnBattery = isOnBattery
        self.percent = min(max(percent, 0), 100)
        self.showsPercent = showsPercent
        self.isCharging = isCharging
        self.showsBolt = showsBolt ?? isCharging
        self.hasBattery = hasBattery
        self.reading = reading
    }

    public static func content(mode: BarMode, hasBattery: Bool) -> Content {
        if mode == .flowWatts { return .flowWatts }
        guard hasBattery else { return .watts }
        switch mode {
        case .battery, .batteryPlain: return .battery
        case .batteryWatts, .batteryPlainWatts: return .batteryWatts
        case .watts, .flowWatts: return .watts
        }
    }

    public init(mode: BarMode, snapshot: PowerSnapshot, sensorsAvailable: Bool) {
        let battery = snapshot.battery
        hasBattery = battery.isPresent
        content = Self.content(mode: mode, hasBattery: battery.isPresent)
        percent = min(max(battery.percentage, 0), 100)
        showsPercent = mode.showsPercent
        isCharging = battery.isPresent && battery.isCharging && snapshot.source == .adapter
        showsBolt = battery.isPresent && snapshot.source == .adapter
        isOnBattery = snapshot.source == .battery
        reading = Self.reading(snapshot: snapshot, sensorsAvailable: sensorsAvailable)
    }

    /// Sem leitura, ou nos primeiros segundos, não há número: nunca «0 W»,
    /// que seria uma medição inventada.
    public static func reading(snapshot: PowerSnapshot, sensorsAvailable: Bool) -> Reading {
        guard sensorsAvailable, let total = snapshot.systemTotal else { return .unavailable }
        guard snapshot.isSettled else { return .settling }
        return .watts(Int(max(total, 0).rounded()))
    }

    // MARK: - Texto

    /// Espaço fino inseparável, só na barra: poupa largura ao «W».
    public static let narrowSpace = "\u{202F}"

    /// «15 W», ou «—» sem número.
    public func wattsText(language: String = L10n.language) -> String {
        guard case .watts(let value) = reading else { return "—" }
        let format = PFFormat(locale: Locale(identifier: language))
        return format.wattsValue(Double(value), decimals: 0) + Self.narrowSpace + "W"
    }

    /// O texto mais largo que o lugar dos watts tem de levar, para a largura
    /// do item não mudar com o valor. Com algarismos tabulares, qualquer
    /// número de três algarismos mede o mesmo.
    public static let widestWatts = "188" + narrowSpace + "W"

    /// A dica do item: o que ele mostra, por extenso.
    public func toolTip(language: String = L10n.language) -> String {
        let format = PFFormat(locale: Locale(identifier: language))
        let pct = format.percent(percent)
        func string(_ key: String, _ args: [CVarArg] = []) -> String {
            L10n.string(key, language: language, args: args)
        }
        switch (reading, hasBattery) {
        case (.watts(let value), true):
            let watts = format.watts(Double(value), decimals: 0)
            return string(isCharging ? "tt_bar_charging" : "tt_bar", [watts, pct])
        case (.watts(let value), false):
            return string("tt_bar_nobattery", [format.watts(Double(value), decimals: 0)])
        case (.settling, true): return string("tt_bar_settling", [pct])
        case (.settling, false): return string("tt_bar_settling_nobattery")
        case (.unavailable, true): return string("tt_bar_off", [pct])
        case (.unavailable, false): return string("tt_bar_off_nobattery")
        }
    }

    /// O valor que o VoiceOver lê. Muda ao mesmo ritmo do desenho.
    public func accessibilityValue(language: String = L10n.language) -> String {
        func string(_ key: String, _ args: [CVarArg] = []) -> String {
            L10n.string(key, language: language, args: args)
        }
        switch (reading, hasBattery) {
        case (.watts(let value), true):
            return string(isCharging ? "ax_bar_value_charging" : "ax_bar_value", [value, percent])
        case (.watts(let value), false): return string("ax_bar_value_nobattery", [value])
        case (.settling, true): return string("ax_bar_value_settling", [percent])
        case (.settling, false): return string("ax_bar_value_settling_nobattery")
        case (.unavailable, true): return string("ax_bar_value_off", [percent])
        case (.unavailable, false): return string("ax_bar_value_off_nobattery")
        }
    }
}

/// Segura o que o item mostra para ele mudar, no máximo, de 2 em 2 s.
///
/// O item da barra redesenha-se a cada mudança; um consumo que oscila a 1 Hz
/// faria o número tremer. O valor pedido vai mudando; o mostrado só o
/// acompanha passados 2 s da última mudança. As ordens do utilizador (outro
/// modo) passam logo.
public struct BarTitleThrottle {
    public static let minimumInterval: TimeInterval = 2

    private var current: AnyHashable?
    private var changedAt: Date?

    public init() {}

    /// O que mostrar agora, tendo `wanted` como o valor atual.
    public mutating func shown<Value: Hashable>(for wanted: Value, at now: Date,
                                                immediately: Bool = false) -> Value {
        if let shown = current as? Value, let changedAt, !immediately {
            if shown == wanted { return shown }
            if now.timeIntervalSince(changedAt) < Self.minimumInterval { return shown }
        }
        current = wanted
        changedAt = now
        return wanted
    }
}
