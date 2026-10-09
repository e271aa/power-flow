import Foundation

/// O que o item da barra de menus mostra. Guardado em `pf.barMode`.
public enum BarMode: String, CaseIterable, Sendable {
    /// Pela ordem dos mosaicos das Definições.
    case battery, batteryWatts, batteryPlain, batteryPlainWatts, flowWatts, watts

    public static let `default` = BarMode.batteryWatts

    /// Desenha a bateria. «Ícone e watts» e «Só watts» não a desenham, por
    /// isso servem também um Mac sem bateria.
    public var showsBattery: Bool { self != .watts && self != .flowWatts }

    /// A percentagem dentro da bateria. Sem ela, a bateria fica como a do
    /// sistema com «Mostrar percentagem» desligado.
    public var showsPercent: Bool { self == .battery || self == .batteryWatts }

    /// Os quatro modos da 2.0 passam aos três de agora. «Só ícone» fica com a
    /// bateria sozinha; «Ícone e %» também, porque a percentagem já está dentro
    /// dela. Um valor que não se conhece vale a omissão.
    public static func migrating(_ raw: String?) -> BarMode {
        switch raw {
        case "icon", "iconPercent": .battery
        case "iconWatts": .batteryWatts
        default: raw.flatMap(BarMode.init(rawValue:)) ?? .default
        }
    }

    static let legacyValues: Set<String> = ["icon", "iconWatts", "iconPercent"]
}

/// Quantas vezes por segundo se lê o SMC com o painel aberto. Guardado em
/// `pf.sampleRate`. Com o painel fechado são sempre 1 Hz.
public enum SampleRate: String, CaseIterable, Sendable {
    case low, normal, high

    public static let `default` = SampleRate.normal

    /// O ritmo rápido de leitura, ou `nil` em «Baixa»: a 1 Hz já é o ritmo lento.
    public var fastHz: Int? {
        switch self {
        case .low: nil
        case .normal: 2
        case .high: 10
        }
    }

    /// O ritmo rápido que deve estar a correr. Com o painel fechado nenhum (E1):
    /// as leituras de 10 Hz com o painel escondido custavam metade do CPU fechado.
    public func fastHz(panelIsOpen: Bool) -> Int? {
        panelIsOpen ? fastHz : nil
    }
}

/// As preferências guardadas em `UserDefaults`. O arranque com a sessão não
/// está aqui: vive no `SMAppService`, que é quem sabe se está ligado.
public enum AppSettings {
    public static let barModeKey = "pf.barMode"
    public static let sampleRateKey = "pf.sampleRate"
    /// Verdadeiro depois de «Percebi» no cartão de primeiro arranque.
    public static let firstRunDoneKey = "pf.firstRunDone"

    public static let alertAssistKey = "pf.alert.assist"
    public static let alertAssistDelayKey = "pf.alert.assistDelay"
    public static let alertTempKey = "pf.alert.temp"
    public static let alertTempLimitKey = "pf.alert.tempLimit"
    public static let alertWeakKey = "pf.alert.weak"

    /// O modo guardado. Um valor da 2.0 é migrado e o novo fica escrito logo
    /// na primeira leitura, para as Definições já o mostrarem.
    public static func barMode(_ defaults: UserDefaults = .standard) -> BarMode {
        let raw = defaults.string(forKey: barModeKey)
        let mode = BarMode.migrating(raw)
        if let raw, BarMode.legacyValues.contains(raw) {
            defaults.set(mode.rawValue, forKey: barModeKey)
        }
        return mode
    }

    public static func sampleRate(_ defaults: UserDefaults = .standard) -> SampleRate {
        defaults.string(forKey: sampleRateKey).flatMap(SampleRate.init(rawValue:)) ?? .default
    }

    public static func firstRunDone(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: firstRunDoneKey)
    }

    /// Os alertas. Uma chave que não existe vale a omissão do handoff, e não
    /// `false`: dois dos três alertas vêm ligados.
    public static func alerts(_ defaults: UserDefaults = .standard) -> AlertSettings {
        var settings = AlertSettings()
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        settings.assist = bool(alertAssistKey, settings.assist)
        settings.temperature = bool(alertTempKey, settings.temperature)
        settings.weakAdapter = bool(alertWeakKey, settings.weakAdapter)
        let delay = defaults.integer(forKey: alertAssistDelayKey)
        if AlertSettings.assistDelays.contains(delay) { settings.assistDelay = delay }
        if defaults.object(forKey: alertTempLimitKey) != nil {
            let limit = defaults.integer(forKey: alertTempLimitKey)
            settings.temperatureLimit = min(max(limit, AlertSettings.temperatureLimits.lowerBound),
                                            AlertSettings.temperatureLimits.upperBound)
        }
        return settings
    }
}
