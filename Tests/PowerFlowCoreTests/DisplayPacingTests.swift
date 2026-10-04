import XCTest
@testable import PowerFlowCore

/// Fase 11: a aresta que se apaga espera 1 s, e os números mudam no máximo
/// 2 vezes por segundo. Cada teste foi visto a falhar com a regra tirada.
final class DisplayPacingTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    // MARK: - EdgeHold

    func testArestaAcendeLogo() {
        var hold = EdgeHold()
        XCTAssertEqual(hold.update(active: [.adapterToBattery], at: t0), [.adapterToBattery])
    }

    /// O bug: a 0,15 W o caudal passa o limiar para um lado e para o outro e a aresta piscava.
    func testArestaSoApagaDepoisDe1sAbaixo() {
        var hold = EdgeHold()
        _ = hold.update(active: [.adapterToBattery], at: t0)
        XCTAssertEqual(hold.update(active: [], at: t0 + 1), [.adapterToBattery], "primeira leitura abaixo: espera")
        XCTAssertEqual(hold.update(active: [], at: t0 + 1.5), [.adapterToBattery], "0,5 s abaixo: ainda espera")
        XCTAssertEqual(hold.update(active: [], at: t0 + 2), [], "1 s abaixo: apaga")
    }

    /// As publicações são de 1 Hz e o temporizador atrasa-se ou adianta-se uns milissegundos.
    func testUmSegundoComFolgaDoTemporizador() {
        var hold = EdgeHold()
        _ = hold.update(active: [.batteryToSystem], at: t0)
        _ = hold.update(active: [], at: t0 + 1)
        XCTAssertEqual(hold.update(active: [], at: t0 + 1.98), [])
    }

    func testVoltarAcimaRecomecaAEspera() {
        var hold = EdgeHold()
        _ = hold.update(active: [.adapterToBattery], at: t0)
        _ = hold.update(active: [], at: t0 + 1)
        _ = hold.update(active: [.adapterToBattery], at: t0 + 1.5)
        XCTAssertEqual(hold.update(active: [], at: t0 + 2), [.adapterToBattery])
        XCTAssertEqual(hold.update(active: [], at: t0 + 2.5), [.adapterToBattery])
        XCTAssertEqual(hold.update(active: [], at: t0 + 3), [])
    }

    func testUmaArestaQueNuncaAcendeuNaoFicaAcesa() {
        var hold = EdgeHold()
        XCTAssertEqual(hold.update(active: [], at: t0), [])
    }

    func testHeldDaSoAsQueEstaoAEspera() {
        var hold = EdgeHold()
        var charging = PowerSnapshot()
        charging.adapterInput = 65
        charging.systemTotal = 36.1
        charging.battery.isPresent = true
        charging.battery.isExternalConnected = true
        charging.battery.isCharging = true
        XCTAssertGreaterThan(charging.adapterToBattery, PanelState.edgeThreshold)
        XCTAssertEqual(hold.held(for: charging, at: t0), [])

        var full = charging
        full.adapterInput = 36.1
        full.battery.isCharging = false
        XCTAssertEqual(full.adapterToBattery, 0, accuracy: 0.001)
        XCTAssertEqual(hold.held(for: full, at: t0 + 1), [.adapterToBattery])
        XCTAssertEqual(hold.held(for: full, at: t0 + 2), [])
    }

    func testArestaAEsperaContinuaAcesaNoDesenho() {
        XCTAssertFalse(EdgeFlow(watts: 0.05, reduceMotion: false).isActive)
        XCTAssertTrue(EdgeFlow(watts: 0.05, isHeld: true, reduceMotion: false).isActive)
        XCTAssertFalse(EdgeFlow(watts: 0.05, isSuppressed: true, isHeld: true, reduceMotion: false).isActive,
                       "a estabilizar nenhuma aresta acende")
    }

    // MARK: - PublishGate

    func testPrimeiraPublicacaoNaoEspera() {
        XCTAssertEqual(PublishGate().wait(at: t0), 0)
    }

    /// O bug: o tique de 1 Hz e o aviso do sistema deram três publicações no mesmo segundo.
    func testDuasPublicacoesFicamA05sNoMinimo() {
        var gate = PublishGate()
        gate.published(at: t0)
        XCTAssertEqual(gate.wait(at: t0 + 0.11), 0.39, accuracy: 0.001)
        XCTAssertEqual(gate.wait(at: t0 + 0.5), 0)
        XCTAssertEqual(gate.wait(at: t0 + 1), 0)
    }

    /// Publicar sempre que o portão deixa: nunca mais de 2 numa janela de 1 s.
    func testNuncaMaisDeDuasPorSegundo() {
        var gate = PublishGate()
        var times: [Double] = []
        // Pedidos a cada 0,1 s durante 5 s.
        for step in 0..<50 {
            let now = t0 + Double(step) * 0.1
            if gate.wait(at: now) == 0 {
                gate.published(at: now)
                times.append(Double(step) * 0.1)
            }
        }
        for start in times {
            XCTAssertLessThanOrEqual(times.filter { $0 >= start && $0 < start + 0.999 }.count, 2)
        }
    }
}

/// Fase 11: a língua e os formatadores ficam guardados. A cache não pode
/// esconder uma mudança de língua nem misturar locales.
final class FormatCacheTests: XCTestCase {
    override func tearDown() {
        L10n.languageOverride = nil
        super.tearDown()
    }

    func testMudarALinguaMudaOsTextos() {
        L10n.languageOverride = ["en"]
        XCTAssertEqual(L10n.language, "en")
        let english = L10n.string("n_battery")
        L10n.languageOverride = ["pt-PT"]
        XCTAssertEqual(L10n.language, "pt-PT")
        XCTAssertNotEqual(L10n.string("n_battery"), english)
    }

    func testFormatadoresNaoMisturamLocalesNemCasas() {
        let pt = PFFormat(locale: Locale(identifier: "pt-PT"))
        let en = PFFormat(locale: Locale(identifier: "en"))
        XCTAssertEqual(pt.watts(12.34), "12,3\u{00A0}W")
        XCTAssertEqual(en.watts(12.34), "12.3\u{00A0}W")
        XCTAssertEqual(pt.watts(12.34, decimals: 0), "12\u{00A0}W")
        XCTAssertEqual(pt.watts(12.34), "12,3\u{00A0}W", "a mesma locale com outras casas não estraga a primeira")
        XCTAssertEqual(en.mAh(6075), "6,075\u{00A0}mAh")
        XCTAssertEqual(en.integer(6075), "6075", "agrupamento é outra chave")
    }
}
