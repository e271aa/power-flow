import XCTest
@testable import PowerFlowCore

final class HistoryStoreTests: XCTestCase {
    /// Um instante alinhado com os intervalos de 30 s e de 10 min.
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("powerflow-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
    }

    /// Alimenta o histórico a 1 Hz, de `from` até `to` segundos depois do início.
    private func feed(_ store: HistoryStore, from: Int = 0, to: Int,
                      system: (Int) -> Double = { _ in 10 },
                      adapter: (Int) -> Double? = { _ in nil }) {
        for second in from..<to {
            store.append(system: system(second), adapter: adapter(second),
                         at: start.addingTimeInterval(Double(second)))
        }
    }

    // MARK: - Redução de resolução

    func testTrintaLeiturasDaoUmPontoComAMedia() {
        let store = HistoryStore()
        // Primeiro meio minuto: 0…29 W (média 14,5). Segundo: sempre 40 W.
        feed(store, to: 61, system: { $0 < 30 ? Double($0) : 40 })

        let points = store.points(.oneHour)
        XCTAssertEqual(points.count, 2, "só os intervalos fechados entram no anel")
        XCTAssertEqual(points[0].system, 14.5, accuracy: 0.0001)
        XCTAssertEqual(points[0].t, start)
        XCTAssertEqual(points[1].system, 40, accuracy: 0.0001)
        XCTAssertEqual(points[1].t, start.addingTimeInterval(30))
    }

    func testDezMinutosDaoUmPontoDoAnelPersistido() {
        let store = HistoryStore()
        var closed = 0
        for second in 0...1200 {
            if store.append(system: second < 600 ? 10 : 20, adapter: nil,
                            at: start.addingTimeInterval(Double(second))) { closed += 1 }
        }
        XCTAssertEqual(closed, 2, "avisa quando fecha um intervalo de 10 min")
        XCTAssertEqual(store.points(.day).map(\.system), [10, 20])
    }

    /// O adaptador só conta num intervalo se esteve ligado em metade dele.
    func testAMediaDoAdaptadorIgnoraOsSegundosSemCabo() {
        let store = HistoryStore()
        feed(store, to: 91, adapter: { second in
            if second < 30 { return second < 20 ? 60 : nil }  // 20 de 30: conta
            if second < 60 { return second < 40 ? 60 : nil }  // 10 de 30: não conta
            return nil
        })
        XCTAssertEqual(store.points(.oneHour).map(\.adapter), [60, nil, nil])
    }

    // MARK: - Anel cheio

    func testOsAneisNaoCrescemParaLaDaCapacidade() {
        let store = HistoryStore()
        feed(store, to: 4000, system: { Double($0) })

        let seconds = store.points(.twoMinutes)
        XCTAssertEqual(seconds.count, 120)
        XCTAssertEqual(seconds.first?.system, 3880)
        XCTAssertEqual(seconds.last?.system, 3999)

        // 4000 s são 133 intervalos de 30 s fechados; ficam os últimos 120.
        let halfMinutes = store.points(.oneHour)
        XCTAssertEqual(halfMinutes.count, 120)
        XCTAssertEqual(halfMinutes.first?.t, start.addingTimeInterval(13 * 30))
    }

    // MARK: - Lacunas

    func testOMacADormirDeixaUmaLacunaENaoUmaDescidaAZero() {
        let store = HistoryStore()
        feed(store, to: 40)
        feed(store, from: 70, to: 100)   // 30 s sem leituras
        let now = start.addingTimeInterval(99)

        let series = store.series(for: .twoMinutes, now: now)
        XCTAssertEqual(series.samples.count, 70)
        XCTAssertEqual(series.gaps.count, 1)
        XCTAssertEqual(series.gaps.first.map { $0.count }, 30)
        XCTAssertEqual(Set(series.samples.map(\.segment)), [0, 1], "a lacuna parte a linha em duas")
        XCTAssertFalse(series.samples.contains { $0.system == 0 })
        XCTAssertEqual(series.samples.last?.slot, 119, "o último ponto é o «agora»")
    }

    /// Uma leitura que se atrasa um ou dois segundos não é o Mac a dormir.
    func testUmaFalhaCurtaNaoPartALinha() {
        let store = HistoryStore()
        feed(store, to: 40)
        feed(store, from: 43, to: 100)
        let series = store.series(for: .twoMinutes, now: start.addingTimeInterval(99))
        XCTAssertTrue(series.gaps.isEmpty)
        XCTAssertEqual(Set(series.samples.map(\.segment)), [0])
    }

    /// Antes da primeira leitura não é lacuna: ainda não havia histórico.
    func testHistoricoCurtoNaoELacuna() {
        let store = HistoryStore()
        feed(store, to: 18 * 60)
        let now = start.addingTimeInterval(18 * 60 - 1)

        let hour = store.series(for: .oneHour, now: now)
        XCTAssertTrue(hour.gaps.isEmpty)
        XCTAssertTrue(hour.isShort)
        XCTAssertEqual(hour.coverage, 18 * 60 - 1, accuracy: 1)
        XCTAssertEqual(hour.samples.last?.slot, 119, "o intervalo em curso é o «agora»")
        XCTAssertFalse(store.isAvailable(.day, now: now), "24 h pede uma hora de dados")
        XCTAssertTrue(store.isAvailable(.oneHour, now: now))

        feed(store, from: 18 * 60, to: 3601)
        XCTAssertTrue(store.isAvailable(.day, now: start.addingTimeInterval(3600)))
        XCTAssertFalse(store.series(for: .oneHour, now: start.addingTimeInterval(3600)).isShort)
    }

    // MARK: - Gravar e reler

    func testGravarERelerMantemAs24Horas() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let store = HistoryStore(fileURL: file, now: start)
        feed(store, to: 3 * 3600 + 200, system: { Double($0 / 600) }, adapter: { $0 < 3600 ? 60 : nil })
        try store.save()

        let later = start.addingTimeInterval(3 * 3600 + 260)
        let reopened = HistoryStore(fileURL: file, now: later)
        XCTAssertEqual(reopened.points(.day), store.points(.day))
        XCTAssertEqual(reopened.points(.day).count, 18)
        XCTAssertEqual(reopened.points(.day).first?.adapter, 60)
        XCTAssertNil(reopened.points(.day).last?.adapter)
        XCTAssertTrue(reopened.isAvailable(.day, now: later), "as 24 h continuam disponíveis depois de reabrir")
        XCTAssertEqual(reopened.coverage(now: later), 3 * 3600 + 260, accuracy: 1)

        // O intervalo que ia a meio continua: os 200 s de antes contam com os de agora.
        reopened.append(system: 18, adapter: nil, at: later)
        let series = reopened.series(for: .day, now: later)
        XCTAssertEqual(series.samples.count, 19)
        XCTAssertEqual(series.samples.last?.system ?? 0, 18, accuracy: 0.0001)
        XCTAssertTrue(series.gaps.isEmpty)
    }

    func testOQueTemMaisDe24HorasNaoVolta() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let store = HistoryStore(fileURL: file, now: start)
        feed(store, to: 2 * 3600 + 1)
        try store.save()

        // 23 h depois só sobra a última hora do que foi gravado: seis
        // intervalos fechados e o que ia a meio quando a app fechou.
        let nextDay = start.addingTimeInterval(25 * 3600)
        let reopened = HistoryStore(fileURL: file, now: nextDay)
        XCTAssertEqual(reopened.points(.day).count, 7)
        XCTAssertEqual(reopened.points(.day).first?.t, start.addingTimeInterval(3600))

        // E o tempo com a app fechada fica como lacuna, não como zero.
        reopened.append(system: 5, adapter: nil, at: nextDay)
        let series = reopened.series(for: .day, now: nextDay)
        XCTAssertEqual(series.gaps.count, 1)
        XCTAssertEqual(series.samples.last?.system, 5)
    }

    /// A app fechou ao fim de um minuto: só há o intervalo que ia a meio.
    func testUmMinutoDeHistoricoTambemSeGuarda() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let store = HistoryStore(fileURL: file, now: start)
        feed(store, to: 75, system: { _ in 13 })
        try store.save()

        let later = start.addingTimeInterval(120)
        let reopened = HistoryStore(fileURL: file, now: later)
        XCTAssertTrue(reopened.points(.day).isEmpty, "o intervalo ainda não fechou")
        XCTAssertEqual(reopened.series(for: .day, now: later).samples.map(\.system), [13])
        XCTAssertEqual(reopened.coverage(now: later), 120, accuracy: 1)
    }

    func testFicheiroEstragadoOuEmFaltaComecaVazio() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertTrue(HistoryStore(fileURL: file, now: start).points(.day).isEmpty)

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("isto não é JSON".utf8).write(to: file)
        XCTAssertTrue(HistoryStore(fileURL: file, now: start).points(.day).isEmpty)
    }

    // MARK: - O que o gráfico mostra

    func testEixoMediaEPico() {
        let store = HistoryStore()
        feed(store, to: 120, system: { $0 == 60 ? 37.5 : 20 }, adapter: { _ in 30 })
        let series = store.series(for: .twoMinutes, now: start.addingTimeInterval(119))

        XCTAssertEqual(series.peak?.system, 37.5)
        XCTAssertEqual(series.peak?.slot, 60)
        XCTAssertEqual(series.average ?? 0, (119 * 20 + 37.5) / 120, accuracy: 0.0001)
        // 37,5 × 1,08 = 40,5: já não cabe nos 40.
        XCTAssertEqual(series.yMax, 60)
        XCTAssertTrue(series.hasAdapter)
        XCTAssertTrue(series.hasBatteryArea)
        XCTAssertEqual(series.nearest(to: 59.6)?.slot, 60)
    }

    func testSemAdaptadorNaoHaAreaDaBateria() {
        let store = HistoryStore()
        feed(store, to: 120)
        let series = store.series(for: .twoMinutes, now: start.addingTimeInterval(119))
        XCTAssertFalse(series.hasAdapter)
        XCTAssertFalse(series.hasBatteryArea)
        XCTAssertEqual(series.yMax, 20)
    }
}
