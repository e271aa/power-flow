import Foundation

/// O que o painel mostra, calculado a partir do instantâneo.
///
/// É uma função pura: as vistas não decidem estados, recebem este. A ordem
/// dos testes é a da tabela «Quando aparece cada estado» do handoff, de cima
/// para baixo, e é ela que resolve os casos em que duas condições se cruzam
/// (um Mac sem bateria nunca está «em bateria», por exemplo).
public struct PanelState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A1: o adaptador alimenta o sistema e carrega a bateria.
        case charging
        /// A2: cabo ligado e bateria parada.
        case paused
        /// A3: cabo ligado e a bateria a ajudar o adaptador.
        case assisting
        /// A4: cabo desligado.
        case onBattery
        /// A5: Mac sem bateria.
        case noBattery
        /// A6: o SMC não deu as chaves de potência.
        case unavailable
        /// A7: no arranque, a média móvel ainda está a encher.
        case settling
    }

    /// De onde vem a energia, para o cabeçalho.
    public enum Origin: Equatable, Sendable {
        case mains
        case battery
        case adapter
        case adapterAndBattery
    }

    public enum Banner: Equatable, Sendable {
        case assist
        case temperature
        case weakAdapter
        case optimized
        case standby

        /// Os avisos de atenção levam o fundo âmbar; os outros são neutros.
        public var isAttention: Bool {
            switch self {
            case .assist, .temperature, .weakAdapter: return true
            case .optimized, .standby: return false
            }
        }
    }

    /// O tempo só existe em dois estados: em bateria («restantes») e a
    /// carregar («100 % em…»). Com a carga em pausa não se mostra nenhum,
    /// mesmo que o IORegistry ainda traga um `TimeRemaining` antigo.
    public enum Time: Equatable, Sendable {
        case none
        case remaining(minutes: Int)
        case untilFull(minutes: Int)
    }

    /// O que a bateria está a fazer. Parada mostra-se «Em pausa», nunca 0 W.
    public enum BatteryActivity: Equatable, Sendable {
        case charging
        case supplying
        case idle
    }

    /// Caudal acima do qual uma aresta se acende.
    public static let edgeThreshold: Double = 0.15
    /// Caudal bateria → sistema, com o cabo ligado, acima do qual se fala em
    /// «bateria a ajudar» (D5). É o mesmo valor com que o modelo separa a
    /// assistência do ruído.
    public static let assistThreshold: Double = PowerSnapshot.assistTolerance

    public let kind: Kind
    public let origin: Origin
    public let banner: Banner?
    public let time: Time
    public let batteryActivity: BatteryActivity
    /// Falso num Mac sem bateria: não há nó nem detalhe de bateria.
    public let showsBattery: Bool
    /// Porque é que a bateria não carrega com o cabo ligado, mesmo quando o
    /// painel não o mostra em aviso (a estabilizar, ou sem leituras do SMC).
    /// Vem só do IORegistry.
    public let pauseReason: Banner?

    public init(snapshot: PowerSnapshot, sensorsAvailable: Bool) {
        let battery = snapshot.battery
        let isAssisting = snapshot.source == .adapter
            && snapshot.batteryToSystem > Self.assistThreshold
        let isCharging = snapshot.adapterToBattery > Self.edgeThreshold

        let underlying: Kind
        if !battery.isPresent {
            underlying = .noBattery
        } else if snapshot.source == .battery {
            underlying = .onBattery
        } else if isAssisting {
            underlying = .assisting
        } else if isCharging {
            underlying = .charging
        } else {
            underlying = .paused
        }

        if !sensorsAvailable {
            kind = .unavailable
        } else if !snapshot.isSettled {
            kind = .settling
        } else {
            kind = underlying
        }

        showsBattery = sensorsAvailable && battery.isPresent

        // A origem não espera pela estabilização nem pelo SMC: saber se o
        // cabo está ligado vem do IORegistry.
        switch underlying {
        case .noBattery: origin = .mains
        case .onBattery: origin = .battery
        case .assisting: origin = .adapterAndBattery
        default:         origin = .adapter
        }

        pauseReason = battery.isPresent && snapshot.source == .adapter && !battery.isCharging
            ? Self.pauseBanner(reason: battery.notChargingReason, isFullyCharged: battery.isFullyCharged)
            : nil

        switch kind {
        case .assisting: banner = .assist
        case .paused:    banner = Self.pauseBanner(reason: battery.notChargingReason,
                                                   isFullyCharged: battery.isFullyCharged)
        default:         banner = nil
        }

        switch (kind, battery.minutesRemaining) {
        case (.onBattery, let minutes?): time = .remaining(minutes: minutes)
        case (.charging, let minutes?):  time = .untilFull(minutes: minutes)
        default:                         time = .none
        }

        if !battery.isPresent {
            batteryActivity = .idle
        } else if isCharging {
            batteryActivity = .charging
        } else if snapshot.batteryToSystem > Self.edgeThreshold {
            batteryActivity = .supplying
        } else {
            batteryActivity = .idle
        }
    }

    /// O `NotChargingReason` é uma máscara de bits, por isso podem vir
    /// várias razões juntas. Mostra-se uma só, pela prioridade do handoff:
    /// temperatura > adaptador fraco > carga otimizada > em espera.
    private static func pauseBanner(reason: Int, isFullyCharged: Bool) -> Banner? {
        guard !isFullyCharged else { return nil }
        if reason & 16 != 0 { return .temperature }
        if reason & 1024 != 0 { return .weakAdapter }
        if reason & 16_777_216 != 0 { return .optimized }
        if reason & 128 != 0 { return .standby }
        return nil
    }
}
