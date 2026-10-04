import Foundation

/// Os textos do painel para um instantâneo: cabeçalho, aviso, nós e VoiceOver.
///
/// A vista não monta frases nem decide o que escrever; recebe isto. As regras
/// são as do handoff («Quando aparece cada estado» e «Diagrama de fluxo»).
public struct PanelCopy: Equatable, Sendable {
    public struct Banner: Equatable, Sendable {
        public let title: String?
        public let text: String
        public let isAttention: Bool
    }

    /// O valor de um nó: um número com unidade, ou uma palavra («Em pausa», «Desligado»).
    public struct NodeValue: Equatable, Sendable {
        public let text: String
        public let isWord: Bool
    }

    /// «Consumo agora», ou «A medir…» enquanto estabiliza.
    public let caption: String
    public let hero: String
    public let origin: String
    /// O que vem depois da origem, sem o separador. `nil`: não há nada a dizer.
    public let status: String?
    public let banner: Banner?
    /// A estabilizar: os números mostram-se em `fg2`.
    public let isDimmed: Bool

    public let adapter: NodeValue
    public let system: NodeValue
    public let battery: NodeValue
    /// «Bateria · 52 %».
    public let batteryLabel: String

    public let voAdapter: String
    public let voSystem: String
    public let voBattery: String?
    /// Um rótulo por aresta com caudal, pela ordem em que se desenham.
    public let voFlows: [FlowEdgeKind: String]
    /// O diagrama inteiro numa frase, para quem não quer percorrer as partes.
    public let voDiagram: String

    public init(snapshot: PowerSnapshot, panel: PanelState,
                language: String = L10n.language) {
        let format = PFFormat(locale: Locale(identifier: language))
        func text(_ key: String, _ args: CVarArg...) -> String {
            L10n.string(key, language: language, args: args)
        }

        let battery = snapshot.battery
        let system = snapshot.systemTotal ?? 0
        let percent = format.percent(battery.percentage)
        let rated = format.watts(Double(battery.adapterWatts), decimals: 0)
        let settling = panel.kind == .settling

        isDimmed = settling
        caption = text(settling ? "hero_measuring" : "hero_now")
        hero = format.watts(system)

        switch panel.origin {
        case .mains:             origin = text("src_mains")
        case .battery:           origin = text("src_battery")
        case .adapter:           origin = text("src_adapter")
        case .adapterAndBattery: origin = text("src_both")
        }

        switch (panel.kind, panel.time) {
        case (.settling, _):
            status = text("st_settling", format.integer(Int(snapshot.settleRemaining.rounded(.up))))
        case (.onBattery, .remaining(let minutes)):
            status = text("st_left", format.duration(minutes: minutes))
        case (.charging, .untilFull(let minutes)):
            status = text("st_charging", format.duration(minutes: minutes))
        case (.paused, _) where panel.banner != nil:
            status = text("st_paused", percent)
        default:
            status = nil
        }

        switch panel.banner {
        case .assist:
            banner = Banner(title: text("ban_assist_t"),
                            text: text("ban_assist", format.watts(system), rated,
                                       format.watts(snapshot.adapterInput ?? 0)),
                            isAttention: true)
        case .temperature:
            let degrees = snapshot.batteryTemperature.map { format.celsius($0) } ?? "—"
            banner = Banner(title: nil, text: text("ban_temp", degrees), isAttention: true)
        case .weakAdapter:
            banner = Banner(title: nil, text: text("ban_weak", rated, format.watts(system)),
                            isAttention: true)
        case .optimized:
            banner = Banner(title: nil, text: text("ban_optimized"), isAttention: false)
        case .standby:
            banner = Banner(title: nil, text: text("ban_standby"), isAttention: false)
        case nil:
            banner = nil
        }

        // O que sai do adaptador, não a leitura em bruto: assim o número é
        // sempre a soma das setas que dele partem. A estabilizar ainda não há
        // setas, e mostra-se a leitura.
        let unplugged = panel.origin == .battery
        let adapterOut = settling
            ? snapshot.adapterInput ?? 0
            : snapshot.adapterToSystem + snapshot.adapterToBattery
        adapter = unplugged
            ? NodeValue(text: text("n_unplugged"), isWord: true)
            : NodeValue(text: format.watts(adapterOut), isWord: false)
        self.system = NodeValue(text: format.watts(system), isWord: false)

        batteryLabel = text("n_battery") + " · " + percent
        let charge = format.watts(snapshot.adapterToBattery)
        let supply = format.watts(snapshot.batteryToSystem)
        switch panel.batteryActivity {
        case .charging:  self.battery = NodeValue(text: "+" + charge, isWord: false)
        case .supplying: self.battery = NodeValue(text: "\u{2212}" + supply, isWord: false)
        case .idle:      self.battery = NodeValue(text: text("n_paused"), isWord: true)
        }

        voAdapter = unplugged ? text("vo_adapter_off") : text("vo_adapter", format.watts(adapterOut))
        voSystem = text("vo_system", format.watts(system))
        if panel.showsBattery {
            switch panel.batteryActivity {
            case .charging:  voBattery = text("vo_battery_in", percent, charge)
            case .supplying: voBattery = text("vo_battery_out", percent, supply)
            case .idle:      voBattery = text("vo_battery_idle", percent)
            }
        } else {
            voBattery = nil
        }

        var flows: [FlowEdgeKind: String] = [:]
        var sentences = [voAdapter, voSystem] + [voBattery].compactMap { $0 }
        if !settling {
            for edge in FlowLayout.edges(hasBattery: panel.showsBattery) {
                let watts = snapshot.watts(on: edge)
                guard watts > PanelState.edgeThreshold else { continue }
                let key: String
                switch edge {
                case .adapterToSystem:  key = "vo_flow_ad_sys"
                case .adapterToBattery: key = "vo_flow_ad_bat"
                case .batteryToSystem:  key = "vo_flow_bat_sys"
                }
                let label = text(key, format.watts(watts))
                flows[edge] = label
                sentences.append(label)
            }
        }
        voFlows = flows
        voDiagram = sentences.joined(separator: ". ")
    }
}
