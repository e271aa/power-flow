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
