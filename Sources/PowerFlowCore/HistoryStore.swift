import Foundation

/// Os três períodos do histórico. O valor em bruto é o que fica em `pf.historyPeriod`.
public enum HistoryPeriod: String, CaseIterable, Sendable {
    case twoMinutes = "2m"
    case oneHour = "1h"
    case day = "24h"

    /// Segundos que cada ponto cobre.
    public var resolution: TimeInterval {
        switch self {
        case .twoMinutes: return 1
        case .oneHour:    return 30
        case .day:        return 600
        }
    }

    public var slots: Int { self == .day ? 144 : 120 }

    public var duration: TimeInterval { resolution * Double(slots) }

    /// Quantos pontos seguidos em falta fazem uma lacuna. Menos do que isto é
    /// uma leitura que se atrasou, e a linha passa por cima.
    var gapSlots: Int {
        switch self {
        case .twoMinutes: return 5
        case .oneHour:    return 2
        case .day:        return 1
        }
    }
}

/// Um ponto do histórico: a média do consumo num intervalo, e a da entrada do
/// adaptador quando havia cabo e bateria.
public struct HistoryPoint: Codable, Equatable, Sendable {
    /// O início do intervalo.
    public var t: Date
    public var system: Double
    public var adapter: Double?

    public init(t: Date, system: Double, adapter: Double?) {
        self.t = t
        self.system = system
        self.adapter = adapter
    }
}

/// O histórico de potência em três resoluções.
///
/// Cada leitura de 1 Hz entra no anel de 1 s e nas médias de 30 s e de 10 min
/// em curso. Quando um intervalo fecha, a média vai para o anel dessa
/// resolução. Só o de 10 min fica em disco: são 24 h em 144 pontos.
///
/// O Mac a dormir, ou a app fechada, não deixam pontos. Não se guarda `nil`:
/// a lacuna vê-se ao pôr os pontos na grelha de tempo de um período.
public final class HistoryStore {
    /// Uma média em curso: o que já entrou no intervalo que ainda não fechou.
    struct Pending: Codable, Equatable {
        var bucket: Int
        var systemSum: Double
        var count: Int
        var adapterSum: Double
        var adapterCount: Int

        mutating func add(system: Double, adapter: Double?) {
            systemSum += system
            count += 1
            if let adapter {
                adapterSum += adapter
                adapterCount += 1
            }
        }

        func point(resolution: TimeInterval) -> HistoryPoint {
            // O adaptador só conta se esteve ligado em metade do intervalo.
            let adapter = adapterCount * 2 >= count && adapterCount > 0
                ? adapterSum / Double(adapterCount) : nil
            return HistoryPoint(t: Date(timeIntervalSince1970: Double(bucket) * resolution),
                                system: systemSum / Double(max(count, 1)), adapter: adapter)
        }
    }

    private struct File: Codable {
        var version = 1
        var points: [HistoryPoint]
        var pending: Pending?
    }

    private var rings: [HistoryPeriod: [HistoryPoint]] = [.twoMinutes: [], .oneHour: [], .day: []]
    private var pending: [HistoryPeriod: Pending] = [:]

    /// Onde o anel de 10 min se guarda. `nil`: só em memória.
    public let fileURL: URL?

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PowerFlow/history.json")
    }

    public init(fileURL: URL? = nil, now: Date = Date()) {
        self.fileURL = fileURL
        load(now: now)
    }

    public func points(_ period: HistoryPeriod) -> [HistoryPoint] { rings[period] ?? [] }

    /// Enche um anel de uma vez. Serve os estados de teste do `--snapshot`.
    func seed(_ points: [HistoryPoint], for period: HistoryPeriod) {
        rings[period] = Array(points.suffix(period.slots))
    }

    private static func bucket(_ date: Date, _ period: HistoryPeriod) -> Int {
        Int((date.timeIntervalSince1970 / period.resolution).rounded(.down))
    }

    // MARK: - Entrada

    /// Uma leitura de 1 Hz. Devolve verdadeiro quando fechou um intervalo de
    /// 10 min, que é quando vale a pena gravar.
    @discardableResult
    public func append(system: Double, adapter: Double?, at date: Date = Date()) -> Bool {
        let second = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        push(HistoryPoint(t: second, system: system, adapter: adapter), to: .twoMinutes)

        var closedDay = false
        for period in [HistoryPeriod.oneHour, .day] {
            let bucket = Self.bucket(date, period)
            if let current = pending[period], current.bucket != bucket {
                push(current.point(resolution: period.resolution), to: period)
                pending[period] = nil
                if period == .day { closedDay = true }
            }
            var current = pending[period]
                ?? Pending(bucket: bucket, systemSum: 0, count: 0, adapterSum: 0, adapterCount: 0)
            current.add(system: system, adapter: adapter)
            pending[period] = current
        }
        return closedDay
    }

    private func push(_ point: HistoryPoint, to period: HistoryPeriod) {
        var ring = rings[period] ?? []
        // Duas leituras no mesmo intervalo: fica a mais recente.
        if ring.last?.t == point.t { ring.removeLast() }
        ring.append(point)
        if ring.count > period.slots { ring.removeFirst(ring.count - period.slots) }
        rings[period] = ring
    }

    // MARK: - Disco

    private func load(now: Date) {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let file = try? decoder.decode(File.self, from: data) else { return }

        // O que tem mais de 24 h já não cabe no período.
        let oldest = now.addingTimeInterval(-HistoryPeriod.day.duration)
        rings[.day] = Array(file.points.filter { $0.t >= oldest && $0.t <= now }
            .sorted { $0.t < $1.t }.suffix(HistoryPeriod.day.slots))

        // A app pode ter fechado a meio de um intervalo. Se reabrir dentro
        // dele, a média continua; senão, fica como o ponto que chegou a ser.
        if let saved = file.pending, saved.count > 0 {
            if saved.bucket == Self.bucket(now, .day) {
                pending[.day] = saved
            } else if Double(saved.bucket) * HistoryPeriod.day.resolution >= oldest.timeIntervalSince1970 {
                push(saved.point(resolution: HistoryPeriod.day.resolution), to: .day)
                rings[.day]?.sort { $0.t < $1.t }
            }
        }
    }

    /// Grava o anel de 10 min. Não faz nada sem ficheiro.
    public func save() throws {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(File(points: rings[.day] ?? [], pending: pending[.day]))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Saída

    /// Há quanto tempo há histórico, contado até `now`.
    public func coverage(now: Date = Date()) -> TimeInterval {
        // Os intervalos em curso também contam: logo depois de reabrir, o
        // de 10 min pode ser tudo o que há.
        let closed = HistoryPeriod.allCases.compactMap { rings[$0]?.first?.t }
        let open = pending.map { Date(timeIntervalSince1970: Double($0.value.bucket) * $0.key.resolution) }
        return (closed + open).min().map { max(0, now.timeIntervalSince($0)) } ?? 0
    }

    /// O consumo médio do sistema nos últimos `seconds` até `now`. É o total
    /// da vista «Consumo por app», que mostra médias da mesma janela.
    ///
    /// Até 2 min vem das leituras de 1 s; acima, dos pontos de 30 s, com o
    /// intervalo em curso a pesar as leituras que já tem. `nil`: sem dados.
    public func average(over seconds: TimeInterval, now: Date = Date()) -> Double? {
        let from = now.addingTimeInterval(-seconds)
        if seconds <= HistoryPeriod.twoMinutes.duration {
            let values = (rings[.twoMinutes] ?? []).filter { $0.t > from && $0.t <= now }.map(\.system)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let period = HistoryPeriod.oneHour
        var sum = 0.0, weight = 0.0
        for point in rings[period] ?? [] where point.t >= from && point.t <= now {
            sum += point.system * period.resolution
            weight += period.resolution
        }
        if let current = pending[period], current.count > 0 {
            sum += current.systemSum
            weight += Double(current.count)
        }
        return weight > 0 ? sum / weight : nil
    }

    /// «24 h» só faz sentido com pelo menos uma hora de dados.
    public func isAvailable(_ period: HistoryPeriod, now: Date = Date()) -> Bool {
        period != .day || coverage(now: now) >= 3600
    }

    /// Os pontos de um período, postos na grelha de tempo que acaba em `now`.
    public func series(for period: HistoryPeriod, now: Date = Date()) -> HistorySeries {
        let last = Self.bucket(now, period)
        let first = last - (period.slots - 1)
        var values = [HistoryPoint?](repeating: nil, count: period.slots)

        var source = rings[period] ?? []
        // O intervalo em curso ainda não está no anel, mas é o «agora» do gráfico.
        if let current = pending[period], current.count > 0 {
            source.append(current.point(resolution: period.resolution))
        }
        for point in source {
            let slot = Self.bucket(point.t, period) - first
            if values.indices.contains(slot) { values[slot] = point }
        }

        var samples: [HistorySeries.Sample] = []
        var gaps: [ClosedRange<Int>] = []
        var segment = 0
        var adapterSegment = 0
        var missing = 0
        for (slot, value) in values.enumerated() {
            guard let value else { missing += 1; continue }
            // Uma falha comprida no meio dos dados é uma lacuna e parte a
            // linha. Antes do primeiro ponto não é lacuna: ainda não havia histórico.
            if missing >= period.gapSlots, !samples.isEmpty {
                gaps.append((slot - missing)...(slot - 1))
                segment += 1
            }
            missing = 0
            if value.adapter != nil, let previous = samples.last,
               previous.adapter == nil || previous.segment != segment {
                adapterSegment += 1
            }
            samples.append(HistorySeries.Sample(slot: slot, time: value.t, system: value.system,
                                                adapter: value.adapter, segment: segment,
                                                adapterSegment: adapterSegment))
        }
        return HistorySeries(period: period, end: now, samples: samples, gaps: gaps,
                             coverage: coverage(now: now))
    }
}

/// O que o gráfico desenha para um período.
public struct HistorySeries: Equatable, Sendable {
    public struct Sample: Equatable, Sendable, Identifiable {
        /// A posição na grelha do período: 0 é o mais antigo.
        public let slot: Int
        public let time: Date
        public let system: Double
        public let adapter: Double?
        /// Muda a cada lacuna: os pontos de segmentos diferentes não se ligam.
        public let segment: Int
        /// O mesmo para a linha do adaptador, que também parte quando o cabo sai.
        public let adapterSegment: Int

        public var id: Int { slot }
    }

    public let period: HistoryPeriod
    /// O instante a que «agora» se refere.
    public let end: Date
    /// Só os pontos com dados, por ordem.
    public let samples: [Sample]
    /// Intervalos sem dados no meio do período: o Mac a dormir, ou a app fechada.
    public let gaps: [ClosedRange<Int>]
    /// Há quanto tempo há histórico.
    public let coverage: TimeInterval

    /// Os máximos do eixo. O handoff pára nos 100; um adaptador de 140 W passa disso.
    private static let ceilings: [Double] = [10, 20, 40, 60, 80, 100, 150, 200, 300]

    public var isEmpty: Bool { samples.isEmpty }

    public var hasAdapter: Bool { samples.contains { $0.adapter != nil } }

    /// A área da bateria só se anuncia na legenda se chegar a ver-se.
    public var hasBatteryArea: Bool {
        samples.contains { sample in sample.adapter.map { abs($0 - sample.system) > 0.8 } ?? false }
    }

    public var average: Double? {
        samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.system } / Double(samples.count)
    }

    public var peak: Sample? { samples.max { $0.system < $1.system } }

    /// O primeiro máximo «redondo» com 8 % de folga sobre o maior valor à vista.
    public var yMax: Double {
        let top = samples.reduce(0) { max($0, $1.system, $1.adapter ?? 0) }
        return Self.ceilings.first { $0 >= top * 1.08 } ?? Self.ceilings.last!
    }

    /// O histórico é mais curto do que o período, e o gráfico tem um bocado vazio à esquerda.
    public var isShort: Bool { coverage < period.duration - period.resolution }

    /// O ponto mais perto de uma posição da grelha, para a leitura por ponteiro.
    public func nearest(to slot: Double) -> Sample? {
        samples.min { abs(Double($0.slot) - slot) < abs(Double($1.slot) - slot) }
    }
}
