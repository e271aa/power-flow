import Foundation

/// Os textos do detalhe da bateria e da linha «Bateria» que leva até lá.
///
/// Como o `PanelCopy`: a vista não monta frases nem decide o que aparece.
public struct BatteryCopy: Equatable, Sendable {
    public struct Metric: Equatable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable {
            case health, cycles, temperature, adapter, untilFull, remaining
        }

        public let kind: Kind
        public let label: String
        public let value: String
        /// Uma linha mais pequena por baixo do valor. `nil`: não há.
        public let detail: String?

        public var id: Kind { kind }
    }

    /// Por baixo do título: o adaptador ligado, ou «Da bateria».
    public let subtitle: String
    public let percent: String
    /// O que a bateria está a fazer, numa frase.
    public let state: String
    public let metrics: [Metric]
    /// O texto da caixa «Porque não está a carregar». Só em pausa e com razão conhecida.
    public let why: String?
    /// «Saúde 80 % · 649 ciclos», para a linha de navegação.
    public let rowSummary: String

    public init(snapshot: PowerSnapshot, panel: PanelState, language: String = L10n.language) {
        let format = PFFormat(locale: Locale(identifier: language))
        func text(_ key: String, _ args: CVarArg...) -> String {
            L10n.string(key, language: language, args: args)
        }

        let battery = snapshot.battery
        let unplugged = snapshot.source == .battery
        let adapter = unplugged ? text("n_unplugged") : Self.adapter(battery, format: format)

        subtitle = unplugged ? text("src_battery") : adapter
        percent = format.percent(battery.percentage)

        switch panel.batteryActivity {
        case .charging:  state = text("b_state_in", format.watts(snapshot.adapterToBattery))
        case .supplying: state = text("b_state_out", format.watts(snapshot.batteryToSystem))
        case .idle:      state = text("b_state_paused")
        }

        let health = battery.healthPercent.map { format.percent($0) } ?? "—"
        let capacity = battery.healthPercent == nil ? nil
            : text("b_cap", format.mAhValue(battery.fullChargeCapacity), format.mAhValue(battery.designCapacity))

        var metrics = [
            Metric(kind: .health, label: text("b_health"), value: health, detail: capacity),
            Metric(kind: .cycles, label: text("b_cycles"), value: format.integer(battery.cycleCount), detail: nil),
            Metric(kind: .temperature, label: text("b_temp"),
                   value: snapshot.batteryTemperature.map { format.celsius($0) } ?? "—", detail: nil),
            Metric(kind: .adapter, label: text("b_adapter"), value: adapter, detail: nil),
        ]
        // O tempo segue a regra do painel: «restante» só em bateria, «até
        // 100 %» só a carregar, nenhum em pausa.
        switch panel.time {
        case .untilFull(let minutes):
            metrics.append(Metric(kind: .untilFull, label: text("b_until"),
                                  value: format.duration(minutes: minutes), detail: nil))
        case .remaining(let minutes):
            metrics.append(Metric(kind: .remaining, label: text("b_left"),
                                  value: format.duration(minutes: minutes), detail: nil))
        case .none:
            break
        }
        self.metrics = metrics

        // Sem leituras do SMC, os avisos que levam números (temperatura,
        // consumo) não se conseguem escrever; os outros, sim.
        switch panel.pauseReason {
        case .temperature?, .weakAdapter?:
            why = panel.kind == .unavailable ? nil
                : PanelCopy.banner(panel.pauseReason!, snapshot: snapshot, language: language).text
        case let reason?:
            why = PanelCopy.banner(reason, snapshot: snapshot, language: language).text
        case nil:
            why = nil
        }

        rowSummary = text("r_batt_sub", health, format.integer(battery.cycleCount))
    }

    /// «USB-C · 67 W». O nome que o IORegistry dá já traz muitas vezes a
    /// potência («67W USB-C Power Adapter»); aí não se repete.
    private static func adapter(_ battery: BatteryInfo, format: PFFormat) -> String {
        let name = battery.adapterName.trimmingCharacters(in: .whitespaces)
        guard battery.adapterWatts > 0 else { return name.isEmpty ? "—" : name }
        let rated = format.watts(Double(battery.adapterWatts), decimals: 0)
        if name.isEmpty { return rated }
        let compact = name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: PFFormat.nbsp, with: "")
        return compact.contains("\(battery.adapterWatts)W") ? name : name + " · " + rated
    }
}
