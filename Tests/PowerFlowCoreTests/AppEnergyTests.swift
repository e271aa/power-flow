import XCTest
@testable import PowerFlowCore

/// Um sistema de mentira: contadores, pais e responsáveis escritos à mão.
private final class FakeReader: ProcessEnergyReading {
    var method: AppEnergyMethod
    var counters: [pid_t: ProcessCounter] = [:]
    var parents: [pid_t: pid_t] = [:]
    var responsibles: [pid_t: pid_t] = [:]
    var clock: UInt64 = 1_000

    init(method: AppEnergyMethod = .energy) { self.method = method }

    func absoluteTime() -> UInt64 { clock }
    func readAll() -> [pid_t: ProcessCounter] { counters }
    func responsible(for pid: pid_t) -> pid_t? { responsibles[pid] }
    func parent(of pid: pid_t) -> pid_t? { parents[pid] ?? 1 }

    /// Soma `watts × seconds` ao contador de cada processo, em nJ (ou ns de CPU).
    func run(_ load: [pid_t: Double], seconds: Double) {
        for (pid, rate) in load {
            // Um processo novo nasce agora, depois da última leitura.
            var counter = counters[pid] ?? ProcessCounter(value: 0, start: clock + 1)
            counter.value += UInt64(rate * seconds * 1e9)
            counters[pid] = counter
        }
        clock += UInt64(seconds * 1e9)
    }
}

final class AppEnergySamplerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let safari = RunningApp(pid: 100, key: "com.apple.Safari", name: "Safari",
                                    bundleIdentifier: "com.apple.Safari")
    private let figma = RunningApp(pid: 500, key: "com.figma.Desktop", name: "Figma",
                                   bundleIdentifier: "com.figma.Desktop")

    private func watts(_ report: AppEnergyReport, _ key: String) -> Double? {
        report.apps.first { $0.key == key }?.watts
    }

    func testAPrimeiraLeituraSoMarcaOPontoDePartida() {
        let reader = FakeReader()
        reader.run([100: 2], seconds: 60)
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        let report = sampler.report(at: t0)
        XCTAssertNil(report.measuredAt)
        XCTAssertTrue(report.apps.isEmpty)
    }

    func testUmServicoXPCContaParaAAppResponsavelEMesmoSendoFilhoDoLaunchd() {
        // O WebContent do Safari: filho do launchd (pid 1), responsável o Safari.
        let reader = FakeReader()
        reader.parents[200] = 1
        reader.responsibles[200] = 100
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        reader.run([100: 0.5, 200: 2], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)

        XCTAssertEqual(watts(sampler.report(at: t0 + 5), safari.key) ?? 0, 2.5, accuracy: 1e-6)
    }

    func testSemResponsavelUmAuxiliarContaPeloPai() {
        // O «Helper (Renderer)» de um Electron: filho da app.
        let reader = FakeReader()
        reader.parents[300] = 301
        reader.parents[301] = 100
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        reader.run([300: 1.5], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)

        XCTAssertEqual(watts(sampler.report(at: t0 + 5), safari.key) ?? 0, 1.5, accuracy: 1e-6)
    }

    func testUmProcessoSemAppFicaForaDaLista() {
        let reader = FakeReader()
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        reader.run([100: 1, 400: 3], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)

        let report = sampler.report(at: t0 + 5)
        XCTAssertEqual(report.apps.map(\.key), [safari.key])
        XCTAssertEqual(report.apps[0].watts, 1, accuracy: 1e-6)
    }

    func testAMediaCobreSoOsUltimos5Min() {
        let reader = FakeReader()
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        var t = t0
        // 5 min a 1 W, depois 5 min a 3 W, de 5 em 5 s.
        for rate in [1.0, 3.0] {
            for _ in 0..<60 {
                reader.run([100: rate], seconds: 5)
                t += 5
                sampler.sample(at: t, apps: [safari], socPower: nil)
            }
        }
        let report = sampler.report(at: t)
        XCTAssertEqual(report.span, 300, accuracy: 1e-6)
        XCTAssertEqual(watts(report, safari.key) ?? 0, 3, accuracy: 1e-6)
    }

    func testReabrirDentroDaJanelaDaLogoAMediaDoQueSeGastouFechado() {
        let reader = FakeReader()
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        reader.run([100: 1], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)
        // Vista fechada 2 min a 4 W: nada corre, mas o contador continua.
        reader.run([100: 4], seconds: 120)
        sampler.sample(at: t0 + 125, apps: [safari], socPower: nil)

        let report = sampler.report(at: t0 + 125)
        XCTAssertEqual(report.span, 125, accuracy: 1e-6)
        XCTAssertEqual(watts(report, safari.key) ?? 0, (5 + 480) / 125, accuracy: 1e-6)
    }

    func testParadoMaisDoQueAJanelaRecomecaDoZero() {
        let reader = FakeReader()
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        reader.run([100: 1], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)
        reader.run([100: 9], seconds: 400)
        sampler.sample(at: t0 + 405, apps: [safari], socPower: nil)

        XCTAssertNil(sampler.report(at: t0 + 405).measuredAt)
    }

    func testUmaAppQueTerminouContinuaNaListaMarcadaComoTerminada() {
        let reader = FakeReader()
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari, figma], socPower: nil)
        reader.run([100: 1, 500: 2], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari, figma], socPower: nil)
        reader.counters[500] = nil
        reader.run([100: 1], seconds: 5)
        sampler.sample(at: t0 + 10, apps: [safari], socPower: nil)

        let report = sampler.report(at: t0 + 10)
        let ended = report.apps.first { $0.key == figma.key }
        XCTAssertEqual(ended?.isRunning, false)
        XCTAssertEqual(ended?.name, "Figma")
        XCTAssertNil(ended?.pid)
        XCTAssertEqual(ended?.watts ?? 0, 1, accuracy: 1e-6)    // 10 J em 10 s
        XCTAssertEqual(report.apps.first { $0.key == safari.key }?.isRunning, true)
    }

    func testUmPidReutilizadoNaoDaUmaDiferencaNegativa() {
        let reader = FakeReader()
        reader.counters[200] = ProcessCounter(value: 50_000_000_000, start: 1)
        reader.parents[200] = 100
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari], socPower: nil)
        // O processo morreu e outro nasceu com o mesmo pid depois da leitura.
        reader.clock += 1_000
        reader.counters[200] = ProcessCounter(value: 5_000_000_000, start: reader.clock)
        reader.clock += 5_000_000_000
        sampler.sample(at: t0 + 5, apps: [safari], socPower: nil)

        XCTAssertEqual(watts(sampler.report(at: t0 + 5), safari.key) ?? 0, 1, accuracy: 1e-6)
    }

    func testSemV6ReparteAPotenciaDoSoCPeloTempoDeCPU() {
        let reader = FakeReader(method: .cpuTime)
        let sampler = AppEnergySampler(reader: reader)
        sampler.sample(at: t0, apps: [safari, figma], socPower: 10)
        // CPU em núcleos: Safari 0,5, Figma 1,5, um serviço do sistema 2.
        reader.run([100: 0.5, 500: 1.5, 400: 2], seconds: 5)
        sampler.sample(at: t0 + 5, apps: [safari, figma], socPower: 10)

        let report = sampler.report(at: t0 + 5)
        XCTAssertEqual(report.method, .cpuTime)
        XCTAssertEqual(watts(report, safari.key) ?? 0, 1.25, accuracy: 1e-6)
        XCTAssertEqual(watts(report, figma.key) ?? 0, 3.75, accuracy: 1e-6)
    }
}

final class AppsCopyTests: XCTestCase {
    private let nb = PFFormat.nbsp

    private func report(_ apps: [AppUsage], span: TimeInterval = 300,
                        method: AppEnergyMethod = .energy) -> AppEnergyReport {
        AppEnergyReport(apps: apps, span: span, method: method, measuredAt: Date())
    }

    func testOEstadoACarregarDaOsNumerosDoProtótipo() {
        let fixture = PanelFixture.charging
        let copy = AppsCopy(report: fixture.apps(language: "pt-PT"),
                            systemAverage: fixture.snapshot.systemTotal, language: "pt-PT")
        XCTAssertEqual(copy.title, "Consumo por app")
        XCTAssertEqual(copy.subtitle, "Média dos últimos 5 min")
        XCTAssertEqual(copy.rows.map(\.name), ["Xcode", "Safari", "Docker", "Figma", "Música"])
        XCTAssertEqual(copy.rows.map(\.value), ["9,6\(nb)W", "3,2\(nb)W", "2,7\(nb)W", "1,9\(nb)W", "0,6\(nb)W"])
        // 36,1 − 18,0 = 18,1: a conta fecha com o total.
        XCTAssertEqual(copy.otherValue, "18,1\(nb)W")
        XCTAssertEqual(copy.total, "36,1\(nb)W")
        XCTAssertEqual(copy.rows[0].fraction, 9.6 / 36.1, accuracy: 1e-9)
        XCTAssertEqual(copy.otherFraction, 18.1 / 36.1, accuracy: 1e-9)
        XCTAssertEqual(copy.footnote, "Valores por app estimados a partir da energia de CPU de cada processo.")
    }

    func testOsValoresEscritosSomamOTotalEscrito() {
        // Assistência: 22,65 W de apps em 41,8 W. Arredondado por si, o resto
        // dava 19,2 W e a coluna somava 41,9 W.
        let fixture = PanelFixture.assist
        let copy = AppsCopy(report: fixture.apps(language: "pt-PT"),
                            systemAverage: fixture.snapshot.systemTotal, language: "pt-PT")
        func number(_ text: String) -> Double {
            Double(text.replacingOccurrences(of: "\(nb)W", with: "").replacingOccurrences(of: ",", with: ".")) ?? .nan
        }
        XCTAssertEqual(copy.otherValue, "19,1\(nb)W")
        let column = copy.rows.reduce(0) { $0 + number($1.value) } + number(copy.otherValue)
        XCTAssertEqual(column, number(copy.total), accuracy: 1e-9)
    }

    func testEmInglesAMusicaEMusic() {
        let fixture = PanelFixture.charging
        let copy = AppsCopy(report: fixture.apps(language: "en"),
                            systemAverage: fixture.snapshot.systemTotal, language: "en")
        XCTAssertEqual(copy.rows.last?.name, "Music")
        XCTAssertEqual(copy.otherName, "System & other")
        XCTAssertEqual(copy.rows[0].value, "9.6\(nb)W")
    }

    func testASomaDasAppsNuncaPassaOConsumoDoSistema() {
        let copy = AppsCopy(report: report([AppUsage(key: "a", name: "A", watts: 12),
                                            AppUsage(key: "b", name: "B", watts: 4)]),
                            systemAverage: 8, language: "pt-PT")
        XCTAssertEqual(copy.rows.map(\.value), ["6,0\(nb)W", "2,0\(nb)W"])
        XCTAssertEqual(copy.otherValue, "0,0\(nb)W")
        XCTAssertEqual(copy.total, "8,0\(nb)W")
    }

    func testNoMaximoCincoAppsESoComUmaDecimaDeWattOuMais() {
        let apps = (0..<7).map { AppUsage(key: "k\($0)", name: "App \($0)", watts: 2 - Double($0) * 0.3) }
            + [AppUsage(key: "z", name: "Zero", watts: 0.04)]
        let copy = AppsCopy(report: report(apps), systemAverage: 20, language: "pt-PT")
        XCTAssertEqual(copy.rows.count, 5)
        XCTAssertFalse(copy.rows.contains { $0.key == "z" })

        let few = AppsCopy(report: report([AppUsage(key: "a", name: "A", watts: 0.06)]),
                           systemAverage: 5, language: "pt-PT")
        XCTAssertTrue(few.rows.isEmpty)
        XCTAssertEqual(few.otherValue, "5,0\(nb)W")
    }

    func testComORatoPorCimaAOrdemNaoMudaMasOsValoresSim() {
        let before = AppsCopy(report: report([AppUsage(key: "a", name: "A", watts: 3),
                                              AppUsage(key: "b", name: "B", watts: 1)]),
                              systemAverage: 10, language: "pt-PT")
        XCTAssertEqual(before.order, ["a", "b"])

        let swapped = report([AppUsage(key: "b", name: "B", watts: 5),
                              AppUsage(key: "a", name: "A", watts: 2),
                              AppUsage(key: "c", name: "C", watts: 1)])
        let held = AppsCopy(report: swapped, systemAverage: 10, frozenOrder: before.order, language: "pt-PT")
        XCTAssertEqual(held.rows.map(\.key), ["a", "b"])
        XCTAssertEqual(held.rows.map(\.value), ["2,0\(nb)W", "5,0\(nb)W"])

        let released = AppsCopy(report: swapped, systemAverage: 10, language: "pt-PT")
        XCTAssertEqual(released.rows.map(\.key), ["b", "a", "c"])
    }

    func testUmaAppTerminadaDizQueTerminouENaoSeAtiva() {
        let copy = AppsCopy(report: report([AppUsage(key: "f", name: "Figma", watts: 1.9,
                                                     isRunning: false, pid: nil)]),
                            systemAverage: 10, language: "pt-PT")
        let row = copy.rows[0]
        XCTAssertFalse(row.isRunning)
        XCTAssertEqual(row.endedLabel, "terminou")
        XCTAssertNil(row.pid)
        XCTAssertEqual(row.accessibilityLabel, "Figma, terminou: 1,9\(nb)W")
    }

    func testAntesDos5MinOSubtituloDizQuantoTempoAMediaCobre() {
        XCTAssertEqual(AppsCopy(report: report([], span: 25), systemAverage: 5, language: "pt-PT").subtitle,
                       "Média dos últimos 25\(nb)s")
        XCTAssertEqual(AppsCopy(report: report([], span: 150), systemAverage: 5, language: "pt-PT").subtitle,
                       "Média dos últimos 2\(nb)min")
        XCTAssertEqual(AppsCopy(report: report([], span: 299.5), systemAverage: 5, language: "pt-PT").subtitle,
                       "Média dos últimos 5 min")

        let waiting = AppsCopy(report: .empty(), systemAverage: 5, language: "pt-PT")
        XCTAssertTrue(waiting.isWaiting)
        XCTAssertEqual(waiting.waiting, "A medir…")
    }

    func testSemV6ONotaDizDeOndeVemAEstimativa() {
        let copy = AppsCopy(report: report([], method: .cpuTime), systemAverage: 5, language: "pt-PT")
        XCTAssertEqual(copy.footnote,
                       "Valores por app estimados a partir do tempo de CPU de cada processo e do consumo do SoC.")
    }

    func testSemLeituraDoSistemaNaoHaRestoNemTotal() {
        let copy = AppsCopy(report: report([AppUsage(key: "a", name: "A", watts: 1)]),
                            systemAverage: nil, language: "pt-PT")
        XCTAssertFalse(copy.hasTotal)
        XCTAssertEqual(copy.total, "—")
    }
}

final class HistoryAverageTests: XCTestCase {
    func testAMediaDe5MinUsaOsPontosDe30sEOIntervaloEmCurso() {
        let start = Date(timeIntervalSince1970: 1_000_020)    // múltiplo de 30 s
        let store = HistoryStore()
        for i in 0..<300 {
            store.append(system: i < 200 ? 10 : 20, adapter: nil, at: start + Double(i))
        }
        let now = start + 299
        XCTAssertEqual(store.average(over: 300, now: now) ?? 0, 4000.0 / 300, accuracy: 1e-9)
        XCTAssertEqual(store.average(over: 60, now: now) ?? 0, 20, accuracy: 1e-9)
        XCTAssertNil(HistoryStore().average(over: 300, now: now))
    }
}
