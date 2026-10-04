import Foundation

/// Os três alertas do handoff (secção E).
public enum AlertKind: String, CaseIterable, Sendable {
    /// A bateria ajuda o adaptador com o cabo ligado.
    case assist
    /// A bateria passou do limite de temperatura.
    case temperature
    /// O adaptador não chega para o que o Mac pede.
    case weakAdapter
}

/// O que as Definições dizem sobre os alertas. As omissões são as do handoff.
public struct AlertSettings: Equatable, Sendable {
    /// As esperas que o menu «Avisar depois de» oferece, em segundos.
    public static let assistDelays = [10, 30, 120]
    /// O passo do «Acima de», em °C.
    public static let temperatureLimits = 35...50

    public var assist = true
    /// Segundos seguidos de assistência antes de avisar.
    public var assistDelay = 30
    public var temperature = true
    public var temperatureLimit = 40
    public var weakAdapter = false

    public init() {}

    public func isEnabled(_ kind: AlertKind) -> Bool {
        switch kind {
        case .assist: assist
        case .temperature: temperature
        case .weakAdapter: weakAdapter
        }
    }

    /// «10 s», «30 s», «2 min», para o menu «Avisar depois de».
    public static func delayLabel(_ seconds: Int, format: PFFormat = PFFormat()) -> String {
        seconds < 60 ? format.seconds(seconds) : format.minutes(seconds / 60)
    }

    /// Quanto tempo seguido a condição tem de durar para o alerta disparar.
    public func delay(_ kind: AlertKind) -> TimeInterval {
        switch kind {
        case .assist: TimeInterval(assistDelay)
        case .temperature: 60
        case .weakAdapter: 120
        }
    }
}

/// A máquina de estados de um alerta: inativo → pendente → disparado → a rearmar.
///
/// Dispara uma vez por episódio. O episódio só acaba depois de 5 min seguidos
/// sem a condição; se ela voltar antes disso, é o mesmo episódio e não há
/// segundo aviso.
public struct AlertTracker: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// A condição dura desde `since`, ainda não o bastante.
        case pending(since: Date)
        /// Já avisou; a condição continua.
        case fired
        /// Já avisou; a condição desapareceu em `since`.
        case rearming(since: Date)
    }

    /// Tempo seguido sem a condição para o episódio acabar.
    public static let rearmInterval: TimeInterval = 5 * 60
    /// Um intervalo maior do que este entre duas leituras (o Mac a dormir, a
    /// app parada) não conta como observado: a condição pode ter ido e vindo
    /// sem ninguém ver. O pendente e o rearmar recomeçam a contar.
    public static let maximumGap: TimeInterval = 10

    public private(set) var phase: Phase = .idle
    private var lastUpdate: Date?

    public init() {}

    /// Avança com uma leitura. Devolve verdadeiro quando o alerta dispara.
    public mutating func update(condition: Bool, delay: TimeInterval, now: Date) -> Bool {
        let gap = lastUpdate.map { now.timeIntervalSince($0) > Self.maximumGap } ?? false
        lastUpdate = now

        switch phase {
        case .idle:
            guard condition else { return false }
            phase = .pending(since: now)
            return firePending(since: now, delay: delay, now: now)
        case .pending(let since):
            guard condition else { phase = .idle; return false }
            if gap { phase = .pending(since: now); return firePending(since: now, delay: delay, now: now) }
            return firePending(since: since, delay: delay, now: now)
        case .fired:
            if !condition { phase = .rearming(since: now) }
            return false
        case .rearming(let since):
            if condition {
                phase = .fired
            } else if gap {
                phase = .rearming(since: now)
            } else if now.timeIntervalSince(since) >= Self.rearmInterval {
                phase = .idle
            }
            return false
        }
    }

    private mutating func firePending(since: Date, delay: TimeInterval, now: Date) -> Bool {
        guard now.timeIntervalSince(since) >= delay else { return false }
        phase = .fired
        return true
    }

    /// Um alerta desligado esquece o episódio em que ia.
    public mutating func reset() {
        phase = .idle
        lastUpdate = nil
    }
}

/// Uma notificação pronta a mostrar.
public struct AlertEvent: Equatable, Sendable {
    public let kind: AlertKind
    public let title: String
    public let body: String
}

/// Decide quando avisar, a partir dos instantâneos de 1 Hz.
///
/// Corre com o painel aberto ou fechado, sobre o mesmo instantâneo que a
/// barra recebe. Não lê nada nem mostra nada: recebe o instantâneo e devolve
/// as notificações a mostrar. O relógio é injetado, para os testes.
public struct AlertMonitor {
    public private(set) var trackers: [AlertKind: AlertTracker] = [:]
    private let clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    public func phase(_ kind: AlertKind) -> AlertTracker.Phase {
        trackers[kind]?.phase ?? .idle
    }

    public mutating func update(snapshot: PowerSnapshot, sensorsAvailable: Bool,
                                settings: AlertSettings,
                                language: String = L10n.language) -> [AlertEvent] {
        let now = clock()
        var events: [AlertEvent] = []
        for kind in AlertKind.allCases {
            var tracker = trackers[kind] ?? AlertTracker()
            if settings.isEnabled(kind) {
                let condition = Self.condition(kind, snapshot: snapshot,
                                               sensorsAvailable: sensorsAvailable, settings: settings)
                if tracker.update(condition: condition, delay: settings.delay(kind), now: now) {
                    events.append(Self.event(kind, snapshot: snapshot, language: language))
                }
            } else {
                tracker.reset()
            }
            trackers[kind] = tracker
        }
        return events
    }

    // MARK: - Condições

    /// O que a bateria dá ao sistema com o cabo ligado: consumo menos entrada.
    ///
    /// Não é o `batteryToSystem` do diagrama, que só existe com `isAligned`
    /// (10 Hz ou 2 Hz, painel aberto; D5). Com o painel fechado, ou em
    /// «Baixa», a média é de 1 Hz e a diferença pode ter um desalinhamento de
    /// um segundo numa rampa de carga. Esse erro dura o que dura a rampa, e o
    /// alerta pede a condição seguida durante pelo menos 10 s; medido na
    /// Fase 9, a 1 Hz, nunca passou de 2 s seguidos acima de 1,5 W.
    public static func assistWatts(_ snapshot: PowerSnapshot) -> Double {
        guard snapshot.battery.isPresent, snapshot.source == .adapter, snapshot.isSettled,
              let total = snapshot.systemTotal, let input = snapshot.adapterInput
        else { return 0 }
        return max(0, total - input)
    }

    public static func condition(_ kind: AlertKind, snapshot: PowerSnapshot,
                                 sensorsAvailable: Bool, settings: AlertSettings) -> Bool {
        let battery = snapshot.battery
        guard battery.isPresent else { return false }
        switch kind {
        case .assist:
            return sensorsAvailable && assistWatts(snapshot) > PanelState.assistThreshold
        case .temperature:
            guard let degrees = snapshot.batteryTemperature else { return false }
            return degrees > Double(settings.temperatureLimit)
        case .weakAdapter:
            guard snapshot.source == .adapter else { return false }
            if battery.notChargingReason & 1024 != 0 { return true }
            // O adaptador no limite e a bateria sem carregar.
            guard sensorsAvailable, !battery.isCharging, battery.adapterWatts > 0,
                  let input = snapshot.adapterInput else { return false }
            return input >= Double(battery.adapterWatts) - 2
        }
    }

    // MARK: - Textos

    /// O título e o corpo, com os números do instantâneo em que disparou.
    public static func event(_ kind: AlertKind, snapshot: PowerSnapshot,
                             language: String = L10n.language) -> AlertEvent {
        let format = PFFormat(locale: Locale(identifier: language))
        func text(_ key: String, _ args: CVarArg...) -> String {
            L10n.string(key, language: language, args: args)
        }
        let system = format.watts(snapshot.systemTotal ?? 0, decimals: 0)

        switch kind {
        case .assist:
            return AlertEvent(kind: kind, title: text("n_assist_t"),
                              body: text("n_assist_b", system,
                                         format.watts(snapshot.adapterInput ?? 0, decimals: 0)))
        case .temperature:
            let degrees = snapshot.batteryTemperature.map { format.celsius($0, decimals: 0) } ?? "—"
            // «A carga parou» só é verdade quando o macOS a parou pelo calor.
            let paused = snapshot.source == .adapter && snapshot.battery.notChargingReason & 16 != 0
            return AlertEvent(kind: kind, title: text("n_temp_t", degrees),
                              body: text(paused ? "n_temp_b" : "n_temp_b_hot"))
        case .weakAdapter:
            let rated = format.watts(Double(snapshot.battery.adapterWatts), decimals: 0)
            return AlertEvent(kind: kind, title: text("n_weak_t"), body: text("n_weak_b", rated, system))
        }
    }
}
