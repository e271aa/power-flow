import Foundation

/// Os textos e as contas da vista «Consumo por app».
///
/// Como o `BatteryCopy`: a vista não soma, não ordena e não monta frases.
public struct AppsCopy: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let key: String
        public let name: String
        public let bundleIdentifier: String?
        /// O pid para ativar a app com um clique. `nil` se já terminou.
        public let pid: pid_t?
        public let isRunning: Bool
        /// «terminou», ao lado do nome de uma app que já não corre. A cor
        /// `fg2` não chega sozinha.
        public let endedLabel: String?
        public let value: String
        /// A quota do consumo do sistema, de 0 a 1: a largura da barra.
        public let fraction: Double
        public let accessibilityLabel: String

        public var id: String { key }
    }

    /// Até cinco apps.
    public static let maxRows = 5
    /// Abaixo disto uma app não tem linha: o valor escrito seria «0,0 W», e
    /// um zero não pode passar por medição. Fica em «Sistema e outros».
    public static let minimumWatts = 0.1
    /// A barra mais curta que ainda se vê, como no protótipo.
    static let minimumBar = 0.015

    public let title: String
    public let subtitle: String
    /// Verdadeiro até haver a primeira média: a vista mostra `waiting`.
    public let isWaiting: Bool
    public let waiting: String
    public let rows: [Row]
    /// As chaves pela ordem das linhas, para a vista as segurar com o rato por cima.
    public let order: [String]
    public let otherName: String
    public let otherValue: String
    public let otherFraction: Double
    public let otherNote: String
    /// Sem leitura do consumo do sistema não há resto nem total.
    public let hasTotal: Bool
    public let totalLabel: String
    public let total: String
    public let footnote: String
    public let otherAccessibilityLabel: String

    /// `systemAverage`: o consumo médio do sistema na mesma janela.
    /// `frozenOrder`: as linhas de antes, pela mesma ordem. Com o rato por
    /// cima da lista, a ordem não muda; os valores sim.
    public init(report: AppEnergyReport, systemAverage: Double?, frozenOrder: [String]? = nil,
                language: String = L10n.language) {
        let format = PFFormat(locale: Locale(identifier: language))
        func text(_ key: String, _ args: CVarArg...) -> String {
            L10n.string(key, language: language, args: args)
        }

        title = text("a_title")
        waiting = text("a_wait")
        isWaiting = report.measuredAt == nil
        if report.span >= report.window - 1 || isWaiting {
            subtitle = text("a_sub")
        } else {
            // «Média dos últimos 25 s»; a partir de 2 min, em minutos.
            let seconds = Int(report.span.rounded())
            subtitle = text("a_sub_part", seconds < 120 ? format.seconds(seconds) : format.minutes(seconds / 60))
        }

        var chosen: [AppUsage]
        if let frozenOrder {
            let current = Dictionary(report.apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            chosen = frozenOrder.compactMap { current[$0] }
        } else {
            chosen = Array(report.apps.filter { $0.watts >= Self.minimumWatts }.prefix(Self.maxRows))
        }

        // A soma das apps nunca passa o consumo do sistema: se passar (a
        // média das apps e a do sistema não vêm do mesmo sensor), as apps
        // encolhem na mesma proporção e o resto fica a zero.
        let sum = chosen.reduce(0) { $0 + $1.watts }
        if let systemAverage, systemAverage > 0, sum > systemAverage {
            let scale = systemAverage / sum
            chosen = chosen.map { var app = $0; app.watts *= scale; return app }
        }
        // Os valores escritos têm uma casa decimal. O resto calcula-se com
        // eles já arredondados, para a coluna somar à vista o total escrito:
        // arredondar cada um por si dava 0,1 W a mais ou a menos.
        func tenth(_ watts: Double) -> Double { (watts * 10).rounded() / 10 }
        let shown = chosen.reduce(0) { $0 + tenth($1.watts) }

        let ended = text("a_ended")
        rows = chosen.map { app in
            let value = format.watts(tenth(app.watts))
            let fraction = systemAverage.map { $0 > 0 ? app.watts / $0 : 0 } ?? 0
            let name = app.isRunning ? app.name : text("a_name_ended", app.name, ended)
            return Row(key: app.key, name: app.name, bundleIdentifier: app.bundleIdentifier,
                       pid: app.isRunning ? app.pid : nil, isRunning: app.isRunning,
                       endedLabel: app.isRunning ? nil : ended, value: value,
                       fraction: max(Self.minimumBar, min(1, fraction)),
                       accessibilityLabel: text("vo_app", name, value))
        }
        order = chosen.map(\.key)

        otherName = text("a_other")
        otherNote = text("a_other_note")
        totalLabel = text("a_total")
        hasTotal = systemAverage != nil
        let other = max(0, tenth(systemAverage ?? 0) - shown)
        otherValue = format.watts(tenth(other))
        otherFraction = systemAverage.map { $0 > 0 ? min(1, other / $0) : 0 } ?? 0
        total = systemAverage.map { format.watts(tenth($0)) } ?? "—"
        footnote = text(report.method == .energy ? "a_est" : "a_est_cpu")
        otherAccessibilityLabel = text("vo_app", otherName, otherValue)
    }
}
