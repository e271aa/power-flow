import XCTest
@testable import PowerFlowCore

/// As Definições (`pf.*`), o título da barra e o ritmo de amostragem.
final class SettingsTests: XCTestCase {
    private let nb = PFFormat.nbsp

    private func freshDefaults() -> UserDefaults {
        let name = "pf.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: - Preferências

    func testOmissoesSaoAsDoHandoff() {
        let defaults = freshDefaults()
        XCTAssertEqual(AppSettings.barMode(defaults), .batteryWatts)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .normal)
        XCTAssertNil(defaults.string(forKey: "pf.barMode"), "a omissão não se escreve")
    }

    func testAsEscolhasPersistemPelasChavesDoHandoff() {
        let defaults = freshDefaults()
        defaults.set("battery", forKey: "pf.barMode")
        defaults.set("high", forKey: "pf.sampleRate")
        XCTAssertEqual(AppSettings.barMode(defaults), .battery)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .high)
        // O que a vista escreve é o que o item lê.
        XCTAssertEqual(AppSettings.barModeKey, "pf.barMode")
        XCTAssertEqual(AppSettings.sampleRateKey, "pf.sampleRate")
    }

    func testUmValorDesconhecidoVoltaAOmissao() {
        let defaults = freshDefaults()
        defaults.set("lixo", forKey: "pf.barMode")
        defaults.set("lixo", forKey: "pf.sampleRate")
        XCTAssertEqual(AppSettings.barMode(defaults), .batteryWatts)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .normal)
    }

    /// Quem tinha cada modo da 2.0 fica com o previsto, e o valor novo fica escrito.
    func testOsModosDa20MigramNaPrimeiraLeitura() {
        let expected: [(String, BarMode)] = [("icon", .battery), ("iconWatts", .batteryWatts),
                                             ("iconPercent", .battery), ("watts", .watts)]
        for (old, new) in expected {
            let defaults = freshDefaults()
            defaults.set(old, forKey: "pf.barMode")
            XCTAssertEqual(AppSettings.barMode(defaults), new, "«\(old)»")
            XCTAssertEqual(defaults.string(forKey: "pf.barMode"), new.rawValue, "«\(old)» fica escrito como «\(new.rawValue)»")
        }
    }

    func testFrequenciaDeAmostragem() {
        XCTAssertNil(SampleRate.low.fastHz, "Baixa: com o painel aberto fica a 1 Hz")
        XCTAssertEqual(SampleRate.normal.fastHz, 2)
        XCTAssertEqual(SampleRate.high.fastHz, 10)
    }

    // MARK: - Item da barra

    private let thin = BarItem.narrowSpace

    private func snapshot(watts: Double?, percent: Int = 80, battery: Bool = true,
                          charging: Bool = false, plugged: Bool = true, settled: Bool = true) -> PowerSnapshot {
        var s = PowerSnapshot()
        s.systemTotal = watts
        s.battery.isPresent = battery
        s.battery.percentage = percent
        s.battery.isCharging = charging
        s.battery.isExternalConnected = plugged
        s.isSettled = settled
        return s
    }

    private func item(_ s: PowerSnapshot, mode: BarMode = .batteryWatts, sensors: Bool = true) -> BarItem {
        BarItem(mode: mode, snapshot: s, sensorsAvailable: sensors)
    }

    func testOsTresModos() {
        XCTAssertEqual(BarItem.content(mode: .battery, hasBattery: true), .battery)
        XCTAssertEqual(BarItem.content(mode: .batteryWatts, hasBattery: true), .batteryWatts)
        XCTAssertEqual(BarItem.content(mode: .watts, hasBattery: true), .watts)
        XCTAssertTrue(BarMode.battery.showsBattery)
        XCTAssertTrue(BarMode.batteryWatts.showsBattery)
        XCTAssertFalse(BarMode.watts.showsBattery, "«Só watts» não tem bateria")
    }

    /// E4: num Mac sem bateria não se desenha bateria, em nenhum modo.
    func testSemBateriaTudoCaiNosWatts() {
        for mode in BarMode.allCases {
            XCTAssertEqual(item(snapshot(watts: 9, battery: false), mode: mode).content, .watts, "\(mode)")
        }
        XCTAssertFalse(item(snapshot(watts: 9, battery: false, charging: true)).isCharging)
    }

    func testOsWattsSaoInteirosComEspacoFino() {
        XCTAssertEqual(item(snapshot(watts: 15.4)).wattsText(language: "pt-PT"), "15\(thin)W")
        XCTAssertEqual(item(snapshot(watts: 119.6)).wattsText(language: "en"), "120\(thin)W")
        XCTAssertEqual(item(snapshot(watts: 4.6)).reading, .watts(5))
    }

    func testSemLeituraNaoHaZeroInventado() {
        XCTAssertEqual(item(snapshot(watts: nil)).reading, .unavailable)
        XCTAssertEqual(item(snapshot(watts: 15), sensors: false).reading, .unavailable)
        XCTAssertEqual(item(snapshot(watts: nil)).wattsText(language: "pt-PT"), "—")
    }

    func testNosPrimeirosSegundosNaoHaNumero() {
        let settling = item(snapshot(watts: 15, settled: false))
        XCTAssertEqual(settling.reading, .settling)
        XCTAssertEqual(settling.wattsText(language: "pt-PT"), "—")
        // A bateria desenha-se na mesma: a carga vem do IORegistry.
        XCTAssertEqual(settling.content, .batteryWatts)
        XCTAssertEqual(settling.percent, 80)
    }

    /// O raio vem do IORegistry, como no ícone do sistema. A carga em pausa usa a variante normal.
    func testORaioSoAparecerACarregar() {
        XCTAssertTrue(item(snapshot(watts: 15, charging: true)).isCharging)
        XCTAssertFalse(item(snapshot(watts: 15, charging: false)).isCharging, "em pausa, com o cabo")
        XCTAssertFalse(item(snapshot(watts: 15, charging: true, plugged: false)).isCharging, "em bateria")
        XCTAssertTrue(item(snapshot(watts: 15, charging: true), sensors: false).isCharging,
                      "sem sensores o raio continua a saber-se")
    }

    func testAPercentagemFicaEntre0E100() {
        XCTAssertEqual(item(snapshot(watts: 15, percent: 104)).percent, 100)
        XCTAssertEqual(item(snapshot(watts: 15, percent: -3)).percent, 0)
    }

    func testDica() {
        let nb = PFFormat.nbsp
        XCTAssertEqual(item(snapshot(watts: 15.2)).toolTip(language: "pt-PT"),
                       "PowerFlow · O Mac está a gastar 15\(nb)W · Bateria a 80\(nb)%")
        XCTAssertEqual(item(snapshot(watts: 15, charging: true)).toolTip(language: "en"),
                       "PowerFlow · Your Mac is using 15\(nb)W · Battery at 80\(nb)%, charging")
        XCTAssertEqual(item(snapshot(watts: 9, battery: false)).toolTip(language: "pt-PT"),
                       "PowerFlow · O Mac está a gastar 9\(nb)W")
        XCTAssertEqual(item(snapshot(watts: nil)).toolTip(language: "pt-PT"),
                       "PowerFlow · Sem leitura do consumo · Bateria a 80\(nb)%")
        XCTAssertEqual(item(snapshot(watts: nil, battery: false)).toolTip(language: "en"),
                       "PowerFlow · No power reading")
        XCTAssertEqual(item(snapshot(watts: 15, settled: false)).toolTip(language: "pt-PT"),
                       "PowerFlow · A medir o consumo… · Bateria a 80\(nb)%")
    }

    func testVoiceOver() {
        XCTAssertEqual(item(snapshot(watts: 15)).accessibilityValue(language: "pt-PT"),
                       "15 watts, bateria a 80 por cento")
        XCTAssertEqual(item(snapshot(watts: 15, charging: true)).accessibilityValue(language: "en"),
                       "15 watts, battery at 80 percent, charging")
        XCTAssertEqual(item(snapshot(watts: 9, battery: false)).accessibilityValue(language: "pt-PT"), "9 watts")
        XCTAssertEqual(item(snapshot(watts: nil)).accessibilityValue(language: "pt-PT"),
                       "Consumo indisponível, bateria a 80 por cento")
    }

    /// O que muda o desenho é a chave inteira; o mesmo instantâneo dá o mesmo item.
    func testOMesmoInstantaneoDaOMesmoItem() {
        XCTAssertEqual(item(snapshot(watts: 15.2)), item(snapshot(watts: 14.9)))
        XCTAssertNotEqual(item(snapshot(watts: 15)), item(snapshot(watts: 15, percent: 81)))
        XCTAssertNotEqual(item(snapshot(watts: 15)), item(snapshot(watts: 15, charging: true)))
    }

    // MARK: - No máximo de 2 em 2 s

    func testOTituloNaoMudaMaisDeUmaVezEm2s() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(throttle.shown(for: "10 W", at: t0), "10 W")
        // Leituras a 1 Hz, sempre diferentes: o texto mostrado segura 2 s.
        XCTAssertEqual(throttle.shown(for: "11 W", at: t0 + 1), "10 W")
        XCTAssertEqual(throttle.shown(for: "12 W", at: t0 + 1.99), "10 W")
        XCTAssertEqual(throttle.shown(for: "13 W", at: t0 + 2), "13 W")
        XCTAssertEqual(throttle.shown(for: "14 W", at: t0 + 3), "13 W")
        XCTAssertEqual(throttle.shown(for: "15 W", at: t0 + 4), "15 W")
    }

    func testMudancasSeguidasNuncaFicamAMenosDe2s() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var changes: [TimeInterval] = []
        var last: String?
        // 120 s de leituras a 4 Hz, com o texto a mudar em todas.
        for step in 0..<480 {
            let t = Double(step) * 0.25
            let shown = throttle.shown(for: "\(step) W", at: t0 + t)
            if shown != last { changes.append(t); last = shown }
        }
        let gaps = zip(changes, changes.dropFirst()).map { $1 - $0 }
        XCTAssertGreaterThan(changes.count, 30)
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 2)
    }

    func testOTextoIgualNaoReinicia() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = throttle.shown(for: "10 W", at: t0)
        _ = throttle.shown(for: "10 W", at: t0 + 1.5)
        // Passaram 2 s desde a mudança, não desde a última leitura.
        XCTAssertEqual(throttle.shown(for: "11 W", at: t0 + 2), "11 W")
    }

    /// O valor dos watts segura 2 s; a percentagem e o raio não passam pelo filtro.
    func testOFiltroTambemServeAsLeituras() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(throttle.shown(for: BarItem.Reading.watts(15), at: t0), .watts(15))
        XCTAssertEqual(throttle.shown(for: BarItem.Reading.watts(16), at: t0 + 1), .watts(15))
        XCTAssertEqual(throttle.shown(for: BarItem.Reading.unavailable, at: t0 + 2), .unavailable)
    }

    func testMudarDeModoPassaLogo() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = throttle.shown(for: "36 W", at: t0)
        XCTAssertEqual(throttle.shown(for: "80 %", at: t0 + 0.1, immediately: true), "80 %")
        // E a contagem recomeça aí.
        XCTAssertEqual(throttle.shown(for: "81 %", at: t0 + 1), "80 %")
    }

    // MARK: - Ritmo de amostragem

    private func rails(input: Double, total: Double) -> RailReading {
        var reading = RailReading()
        reading.adapterInput = input
        reading.systemTotal = total
        return reading
    }

    /// A 2 Hz a janela são 3 s (6 amostras) e o recuo 1 s (2 amostras).
    func testA2HzAJanelaSaoOsMesmos3sEORecuoOMesmo1s() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }
        smoother.setFast(true, hz: 2)
        XCTAssertEqual(smoother.fastHz, 2)

        for _ in 0..<7 { smoother.addFast(rails(input: 50, total: 40)) }
        XCTAssertFalse(smoother.isAligned, "6 + 2 amostras para encher")
        smoother.addFast(rails(input: 50, total: 40))
        XCTAssertTrue(smoother.isAligned)
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 40, accuracy: 0.001)
    }

    func testA2HzUmaRampaDeCargaNaoParecAssistencia() {
        var smoother = DualRateSmoother()
        smoother.setFast(true, hz: 2)
        // 10 W parados e uma rampa de 15 W por amostra; o consumo repete a
        // entrada duas amostras (1 s) mais tarde.
        let input = (0..<30).map { 10 + 15 * Double(max(0, $0 - 10)) }
        for index in input.indices {
            smoother.addFast(rails(input: input[index], total: input[max(0, index - 2)]))
        }
        XCTAssertEqual(smoother.average.systemTotal ?? 0, smoother.average.adapterInput ?? -1, accuracy: 0.001)
    }

    func testMudarOHzRecomecaAJanela() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }
        smoother.setFast(true, hz: 10)
        for _ in 0..<40 { smoother.addFast(rails(input: 50, total: 40)) }
        XCTAssertTrue(smoother.isAligned)

        smoother.setFast(true, hz: 2)
        XCTAssertFalse(smoother.isAligned, "as amostras de 10 Hz não servem a 2 Hz")
        XCTAssertEqual(smoother.fastHz, 2)
    }

    func testOTempoParaEstabilizarSegueOHz() {
        var smoother = DualRateSmoother()
        smoother.setFast(true, hz: 2)
        // Nenhuma leitura lenta: a rápida são 8 amostras a 2 Hz, 4 s; a lenta, 4 s também.
        XCTAssertEqual(smoother.settleRemaining, 4, accuracy: 0.001)
    }
}
