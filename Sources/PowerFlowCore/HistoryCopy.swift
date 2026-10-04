import Foundation

/// Os textos do gráfico do histórico para uma série: eixos, pico, média, nota e VoiceOver.
public struct HistoryCopy: Equatable, Sendable {
    public struct AxisLabel: Equatable, Sendable, Identifiable {
        /// 0 é a borda esquerda da área de dados, 1 a direita.
        public let position: Double
        public let text: String

        public var id: Double { position }
    }

    /// De cima para baixo: «40 W», «20», «0».
    public let yLabels: [String]
    public let xLabels: [AxisLabel]
    /// «Pico 41,9 W».
    public let peak: String?
    /// «36,5 W», para pôr depois de «Média».
    public let average: String?
    /// A nota de histórico curto. `nil` quando o período está cheio, e nos 2 min.
    public let note: String?
    /// O gráfico numa frase, para o VoiceOver.
    public let description: String

    private let language: String
    private let period: HistoryPeriod
    private let end: Date
    private let timeZone: TimeZone

    public init(series: HistorySeries, language: String = L10n.language,
                timeZone: TimeZone = .current) {
        let format = PFFormat(locale: Locale(identifier: language))
        func text(_ key: String, _ args: CVarArg...) -> String {
            L10n.string(key, language: language, args: args)
        }
        self.language = language
        self.timeZone = timeZone
        period = series.period
        end = series.end

        let top = series.yMax
        yLabels = [format.watts(top, decimals: 0), format.wattsValue(top / 2, decimals: 0), "0"]

        let minus = "\u{2212}"
        let now = text("h_now")
        switch series.period {
        case .twoMinutes:
            xLabels = [AxisLabel(position: 0, text: minus + format.minutes(2)),
                       AxisLabel(position: 0.5, text: minus + format.minutes(1)),
                       AxisLabel(position: 1, text: now)]
        case .oneHour:
            xLabels = [AxisLabel(position: 0, text: minus + format.hours(1)),
                       AxisLabel(position: 0.5, text: minus + format.minutes(30)),
                       AxisLabel(position: 1, text: now)]
        case .day:
            func clock(hoursAgo: Double) -> String {
                format.clock(series.end.addingTimeInterval(-hoursAgo * 3600), timeZone: timeZone)
            }
            xLabels = [AxisLabel(position: 0, text: clock(hoursAgo: 24)),
                       AxisLabel(position: 1.0 / 3, text: clock(hoursAgo: 16)),
                       AxisLabel(position: 2.0 / 3, text: clock(hoursAgo: 8)),
                       AxisLabel(position: 1, text: now)]
        }

        peak = series.peak.map { text("h_peak") + " " + format.watts($0.system) }
        average = series.average.map { format.watts($0) }

        if series.period != .twoMinutes, series.isShort, !series.isEmpty {
            note = text("h_fresh", format.duration(minutes: max(1, Int(series.coverage / 60))))
        } else {
            note = nil
        }

        let periodName: String
        switch series.period {
        case .twoMinutes: periodName = text("h_2m")
        case .oneHour:    periodName = text("h_1h")
        case .day:        periodName = text("h_24h")
        }
        if let peakSample = series.peak, let average = series.average {
            var sentences = [text("vo_hist", periodName, format.watts(average),
                                  format.watts(peakSample.system),
                                  Self.when(peakSample.time, period: series.period, end: series.end,
                                            language: language, timeZone: timeZone))]
            let adapter = series.samples.compactMap(\.adapter)
            if !adapter.isEmpty {
                sentences.append(text("vo_hist_ad", format.watts(adapter.reduce(0, +) / Double(adapter.count))))
            }
            if !series.gaps.isEmpty { sentences.append(text("vo_hist_gap")) }
            description = sentences.joined(separator: " ")
        } else {
            description = text("vo_hist_empty")
        }
    }

    /// Quando foi um ponto: «agora», «há 45 s», «há 12 min» ou «às 09:20».
    public func when(_ sample: HistorySeries.Sample) -> String {
        Self.when(sample.time, period: period, end: end, language: language, timeZone: timeZone)
    }

    private static func when(_ time: Date, period: HistoryPeriod, end: Date,
                             language: String, timeZone: TimeZone) -> String {
        let format = PFFormat(locale: Locale(identifier: language))
        let ago = max(0, end.timeIntervalSince(time))
        switch period {
        case .twoMinutes:
            let seconds = Int(ago.rounded())
            return seconds < 1 ? L10n.string("h_now", language: language)
                : L10n.string("h_ago", language: language, args: [format.seconds(seconds)])
        case .oneHour:
            let minutes = Int((ago / 60).rounded())
            return minutes < 1 ? L10n.string("h_now", language: language)
                : L10n.string("h_ago", language: language, args: [format.minutes(minutes)])
        case .day:
            return L10n.string("h_at", language: language, args: [format.clock(time, timeZone: timeZone)])
        }
    }
}
