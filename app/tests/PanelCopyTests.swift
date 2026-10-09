import XCTest
@testable import PowerFlowCore

/// Os textos do painel para os nove estados do protótipo, em PT-PT.
final class PanelCopyTests: XCTestCase {
    private let nb = PFFormat.nbsp

    private func copy(_ fixture: PanelFixture, language: String = "pt-PT") -> PanelCopy {
        PanelCopy(snapshot: fixture.snapshot, panel: fixture.panel, language: language)
    }

    // MARK: - Cabeçalho

    func testCabecalhoACarregar() {
        let c = copy(.charging)
        XCTAssertEqual(c.caption, "Consumo agora")
        XCTAssertEqual(c.hero, "36,1\(nb)W")
        XCTAssertEqual(c.origin, "Do adaptador")
        // O bug: o «% e» de «100 % em» era lido como um especificador de formato.
        XCTAssertEqual(c.status, "a carregar, 100 % em 1\(nb)h\(nb)5\(nb)min")
        XCTAssertFalse(c.isDimmed)
    }

    func testCabecalhoEmPausaSoDizAPercentagemQuandoHaRazao() {
        XCTAssertEqual(copy(.optimized).status, "carga em pausa aos 80\(nb)%")

        var full = PanelFixture.optimized.snapshot
        full.battery.notChargingReason = 0
        full.battery.isFullyCharged = true
        let panel = PanelState(snapshot: full, sensorsAvailable: true)
        XCTAssertNil(PanelCopy(snapshot: full, panel: panel, language: "pt-PT").status)
    }

    func testCabecalhoEmBateriaMostraOTempoRestante() {
        let c = copy(.battery)
        XCTAssertEqual(c.origin, "Da bateria")
        XCTAssertEqual(c.status, "5\(nb)h\(nb)40\(nb)min restantes")
    }

    func testCabecalhoComABateriaAAjudarNaoTemEstado() {
        let c = copy(.assist)
        XCTAssertEqual(c.origin, "Do adaptador e da bateria")
        XCTAssertNil(c.status)
    }

    func testCabecalhoSemBateria() {
        let c = copy(.nobattery)
        XCTAssertEqual(c.origin, "Da corrente")
        XCTAssertNil(c.status)
        XCTAssertNil(c.voBattery)
    }

    func testCabecalhoAEstabilizar() {
        let c = copy(.warming)
        XCTAssertEqual(c.caption, "A medir…")
        XCTAssertEqual(c.status, "valores estáveis dentro de 3\(nb)s")
        XCTAssertTrue(c.isDimmed)
        XCTAssertNil(c.banner, "nunca há aviso durante a estabilização")
        XCTAssertTrue(c.voFlows.isEmpty, "a estabilizar nenhuma aresta está acesa")
    }

    // MARK: - Aviso

    func testAvisos() {
        let assist = copy(.assist).banner
        XCTAssertEqual(assist?.title, "A bateria está a ajudar")
        XCTAssertEqual(assist?.text, "O Mac pede 41,8\(nb)W e o adaptador de 30\(nb)W só dá 29,6\(nb)W. "
            + "Um adaptador mais potente evita a descarga.")
        XCTAssertEqual(assist?.isAttention, true)

        XCTAssertEqual(copy(.temperature).banner?.text,
                       "Pausa por temperatura: a bateria está a 41,3\(nb)°C. A carga retoma quando arrefecer.")
        XCTAssertEqual(copy(.weak).banner?.text,
                       "O adaptador de 20\(nb)W não chega para carregar enquanto o Mac gasta 18,7\(nb)W.")

        let optimized = copy(.optimized).banner
        XCTAssertNil(optimized?.title)
        XCTAssertEqual(optimized?.isAttention, false)

        XCTAssertNil(copy(.charging).banner)
        XCTAssertNil(copy(.battery).banner)
    }

    // MARK: - Nós

    func testValoresDosNos() {
        let charging = copy(.charging)
        XCTAssertEqual(charging.adapter, .init(text: "65,0\(nb)W", isWord: false))
        XCTAssertEqual(charging.system, .init(text: "36,1\(nb)W", isWord: false))
        XCTAssertEqual(charging.battery, .init(text: "+28,9\(nb)W", isWord: false))
        XCTAssertEqual(charging.batteryLabel, "Bateria · 52\(nb)%")

        // O sinal de menos é o tipográfico, não o hífen.
        XCTAssertEqual(copy(.assist).battery, .init(text: "\u{2212}12,2\(nb)W", isWord: false))
        XCTAssertEqual(copy(.battery).adapter, .init(text: "Desligado", isWord: true))
    }

    /// A bateria parada mostra a palavra, nunca «0,0 W».
    func testBateriaParadaDizEmPausa() {
        for fixture in [PanelFixture.optimized, .temperature, .weak, .warming] {
            XCTAssertEqual(copy(fixture).battery, .init(text: "Em pausa", isWord: true), "\(fixture)")
        }
    }

    // MARK: - VoiceOver

    func testRotulosDeVoiceOver() {
        let charging = copy(.charging)
        XCTAssertEqual(charging.voAdapter, "Adaptador, 65,0\(nb)W a entrar")
        XCTAssertEqual(charging.voSystem, "Sistema, a consumir 36,1\(nb)W")
        XCTAssertEqual(charging.voBattery, "Bateria, 52\(nb)%, a carregar a 28,9\(nb)W")
        XCTAssertEqual(charging.voFlows, [
            .adapterToSystem: "Do adaptador para o sistema: 36,1\(nb)W",
            .adapterToBattery: "Do adaptador para a bateria: 28,9\(nb)W",
        ])

        // O protótipo esquecia a aresta bateria → sistema no rótulo combinado.
        let assist = copy(.assist)
        XCTAssertEqual(assist.voFlows[.batteryToSystem], "Da bateria para o sistema: 12,2\(nb)W")
        XCTAssertTrue(assist.voDiagram.hasSuffix("Da bateria para o sistema: 12,2\(nb)W"))

        XCTAssertEqual(copy(.battery).voAdapter, "Adaptador desligado")
        XCTAssertEqual(copy(.optimized).voBattery, "Bateria, 80\(nb)%, carga em pausa")
    }

    func testOsMesmosEstadosEmIngles() {
        XCTAssertEqual(copy(.charging, language: "en").status, "charging, full in 1\(nb)h\(nb)5\(nb)min")
        XCTAssertEqual(copy(.battery, language: "en").battery.text, "\u{2212}9.4\(nb)W")
    }

    // MARK: - Os estados de teste são os do protótipo

    func testCadaEstadoDeTesteDaOEstadoCerto() {
        let expected: [PanelFixture: PanelState.Kind] = [
            .charging: .charging, .optimized: .paused, .temperature: .paused, .weak: .paused,
            .assist: .assisting, .battery: .onBattery, .nobattery: .noBattery,
            .unavailable: .unavailable, .warming: .settling,
        ]
        for fixture in PanelFixture.allCases {
            XCTAssertEqual(fixture.panel.kind, expected[fixture], "\(fixture)")
        }
    }

    // MARK: - Geometria

    func testOChevronApontaNoSentidoDoCaudal() {
        // Adaptador → sistema é uma reta para a direita: a ponta fica à frente das hastes.
        let straight = FlowLayout.chevron(on: FlowLayout.curve(.adapterToSystem), size: 6)
        XCTAssertEqual(straight.tip.x, 164 + 3, accuracy: 0.001)
        XCTAssertEqual(straight.tip.y, 24, accuracy: 0.001)
        XCTAssertEqual(straight.start.x, 164 - 3.6, accuracy: 0.001)
        XCTAssertEqual(abs(straight.start.y - straight.end.y), 12, accuracy: 0.001)

        // Bateria → sistema acaba a subir: a ponta fica acima das hastes.
        let rising = FlowLayout.chevron(on: FlowLayout.curve(.batteryToSystem), size: 6)
        XCTAssertLessThan(rising.tip.y, min(rising.start.y, rising.end.y))
    }

    func testAsArestasVaoDePortaAPorta() {
        for edge in FlowEdgeKind.allCases {
            let curve = FlowLayout.curve(edge)
            let from = FlowLayout.frame(of: edge.from), to = FlowLayout.frame(of: edge.to)
            XCTAssertTrue(from.insetBy(dx: -0.001, dy: -0.001).contains(curve.p0), "\(edge) não sai do nó de origem")
            XCTAssertTrue(to.insetBy(dx: -0.001, dy: -0.001).contains(curve.p3), "\(edge) não chega ao nó de destino")
        }
        XCTAssertEqual(FlowLayout.edges(hasBattery: false), [.adapterToSystem])
        XCTAssertEqual(FlowLayout.height(hasBattery: false), 48)
    }
}

extension LocalizationTests {
    /// Um «%» solto num texto com argumentos é lido como especificador de
    /// formato. Foi o que aconteceu a «a carregar, 100 % em %@».
    func testTextosComArgumentosNaoTemPercentagemSolta() throws {
        for language in ["pt-PT", "en"] {
            let url = try XCTUnwrap(L10n.tableURL(language: language))
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            for (key, value) in table where value.contains("%@") || value.contains("$@") {
                let rest = value.replacingOccurrences(of: "%%|%(\\d+\\$)?@", with: "", options: .regularExpression)
                XCTAssertFalse(rest.contains("%"), "«\(key)» em \(language) tem um % por escapar: \(value)")
            }
        }
    }
}

/// Os textos do detalhe da bateria (frames B4 a B6 do handoff) e a barra de repartição.
final class BatteryCopyTests: XCTestCase {
    private let nb = PFFormat.nbsp

    private func copy(_ fixture: PanelFixture, language: String = "pt-PT",
                      _ change: (inout PowerSnapshot) -> Void = { _ in }) -> BatteryCopy {
        var snapshot = fixture.snapshot
        snapshot.battery.fullChargeCapacity = 4860
        snapshot.battery.designCapacity = 6075
        snapshot.battery.cycleCount = 649
        change(&snapshot)
        let panel = PanelState(snapshot: snapshot, sensorsAvailable: fixture.sensorsAvailable)
        return BatteryCopy(snapshot: snapshot, panel: panel, language: language)
    }

    /// B4: em pausa. Sem tempo nenhum, e com a caixa «Porque não está a carregar».
    func testEmPausa() {
        let c = copy(.optimized)
        XCTAssertEqual(c.subtitle, "USB-C · 67\(nb)W")
        XCTAssertEqual(c.percent, "80\(nb)%")
        XCTAssertEqual(c.state, "Carga em pausa")
        XCTAssertEqual(c.metrics.map(\.kind), [.health, .cycles, .temperature, .adapter])
        XCTAssertEqual(c.metrics[0].value, "80\(nb)%")
        // Em PT-PT os números de quatro algarismos não levam separador de milhares.
        XCTAssertEqual(c.metrics[0].detail, "4860 de 6075 mAh")
        XCTAssertEqual(c.metrics[1].value, "649")
        XCTAssertEqual(c.metrics[2].value, "27,2\(nb)°C")
        XCTAssertEqual(c.why, "Carga otimizada da Apple: termina perto da hora a que costumas desligar o cabo.")
        XCTAssertEqual(c.rowSummary, "Saúde 80\(nb)% · 649 ciclos")
    }

    /// B5: a carregar. Aparece «Até 100 %» e não há caixa.
    func testACarregar() {
        let c = copy(.charging)
        XCTAssertEqual(c.state, "A carregar a 28,9\(nb)W")
        XCTAssertEqual(c.metrics.map(\.kind), [.health, .cycles, .temperature, .adapter, .untilFull])
        XCTAssertEqual(c.metrics.last?.label, "Até 100 %")
        XCTAssertEqual(c.metrics.last?.value, "1\(nb)h\(nb)5\(nb)min")
        XCTAssertNil(c.why)
    }

    /// B6: em bateria, em inglês. Aparece o tempo restante e o adaptador está desligado.
    func testEmBateriaEmIngles() {
        let c = copy(.battery, language: "en")
        XCTAssertEqual(c.subtitle, "From the battery")
        XCTAssertEqual(c.state, "Supplying 9.4\(nb)W to the system")
        XCTAssertEqual(c.metrics.map(\.kind), [.health, .cycles, .temperature, .adapter, .remaining])
        XCTAssertEqual(c.metrics[3].value, "Unplugged")
        XCTAssertEqual(c.metrics[4].value, "5\(nb)h\(nb)40\(nb)min")
        XCTAssertNil(c.why)
    }

    /// Com a bateria a ajudar não há caixa: o aviso do painel já explica.
    func testABateriaAAjudarNaoTemCaixa() {
        XCTAssertNil(copy(.assist).why)
        XCTAssertEqual(copy(.assist).state, "A fornecer 12,2\(nb)W ao sistema")
    }

    /// Sem leituras do SMC a razão continua a vir do IORegistry, mas só as
    /// que não levam números.
    func testSemSensoresARazaoContinuaAVer() {
        XCTAssertEqual(copy(.unavailable).why?.hasPrefix("Carga otimizada"), true)
        XCTAssertNil(copy(.unavailable) { $0.battery.notChargingReason = 1024 }.why)
        XCTAssertEqual(copy(.unavailable).metrics[2].value, "27,2\(nb)°C")
    }

    func testONomeDoAdaptadorNaoRepeteAPotencia() {
        let named = copy(.optimized) { $0.battery.adapterName = "67W USB-C Power Adapter" }
        XCTAssertEqual(named.subtitle, "67W USB-C Power Adapter")
        let unnamed = copy(.optimized) { $0.battery.adapterName = "" }
        XCTAssertEqual(unnamed.subtitle, "67\(nb)W")
    }

    func testSemCapacidadesASaudeFicaPorDizer() {
        let c = copy(.optimized) { $0.battery.designCapacity = 0 }
        XCTAssertEqual(c.metrics[0].value, "—")
        XCTAssertNil(c.metrics[0].detail)
    }
}

final class BreakdownTests: XCTestCase {
    func testSemRailPrincipalFicamDuasFatias() {
        var snapshot = PanelFixture.charging.snapshot
        snapshot.mainRailPower = nil
        XCTAssertEqual(snapshot.breakdown.map(\.kind), [.soc, .other])
        XCTAssertEqual(snapshot.breakdown.map(\.watts).reduce(0, +), 36.1, accuracy: 0.001)
    }

    /// Sem SoC não há resto que se calcule, e a secção não aparece.
    func testSemSoCNaoHaReparticao() {
        var snapshot = PanelFixture.charging.snapshot
        snapshot.socPower = nil
        XCTAssertTrue(snapshot.breakdown.isEmpty)
    }

    func testAsLargurasSaoProporcionaisEEnchemABarra() {
        let widths = BreakdownLayout.widths(for: [24.0, 5.9, 6.2], total: 328)
        XCTAssertEqual(widths.reduce(0, +) + 4, 328, accuracy: 0.001)
        XCTAssertEqual(widths[0] / widths[1], 24.0 / 5.9, accuracy: 0.001)
    }

    func testUmaFatiaMinimaNaoDesaparece() {
        let widths = BreakdownLayout.widths(for: [30, 0.2, 5], total: 328)
        XCTAssertEqual(widths[1], 4, accuracy: 0.001)
        XCTAssertEqual(widths.reduce(0, +) + 4, 328, accuracy: 0.001)
        XCTAssertEqual(widths[0] / widths[2], 6, accuracy: 0.001)

        XCTAssertEqual(BreakdownLayout.widths(for: [10, 0], total: 100), [94, 4])
        XCTAssertEqual(BreakdownLayout.widths(for: [], total: 100), [])
    }
}
