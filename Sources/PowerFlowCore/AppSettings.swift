import Foundation

/// O que se mostra ao lado do ícone na barra de menus. Guardado em `pf.barMode`.
public enum BarMode: String, CaseIterable, Sendable {
    case icon, iconWatts, iconPercent, watts

    public static let `default` = BarMode.iconWatts

    public var showsIcon: Bool { self != .watts }
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

    public static func barMode(_ defaults: UserDefaults = .standard) -> BarMode {
        defaults.string(forKey: barModeKey).flatMap(BarMode.init(rawValue:)) ?? .default
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
