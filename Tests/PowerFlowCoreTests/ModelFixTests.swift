import XCTest
@testable import PowerFlowCore

/// Um teste por bug corrigido na Fase 1. Cada um foi visto a falhar com o
/// bug de volta.
final class ModelFixTests: XCTestCase {
    // MARK: - E4: Mac sem bateria

    /// O bug: sem o serviço da bateria, `ExternalConnected` vinha a falso e
    /// o modelo punha a energia toda a sair de uma bateria que não existe.
    func testE4SemBateriaAEnergiaVemDaCorrente() {
        var snapshot = PowerSnapshot()   // o que o `BatteryReader` devolve sem bateria
        snapshot.systemTotal = 8.5

        XCTAssertEqual(snapshot.source, .adapter)
        XCTAssertEqual(snapshot.batteryToSystem, 0)
        XCTAssertEqual(snapshot.adapterToBattery, 0)
        XCTAssertEqual(snapshot.adapterToSystem, 8.5, accuracy: 0.001)
    }

    /// Num Mac de secretária a entrada pode ler menos do que o consumo. A
    /// diferença não é assistência: não há bateria para assistir.
    func testE4SemBateriaNuncaHaAssistencia() {
        var snapshot = PowerSnapshot()
        snapshot.adapterInput = 20
        snapshot.systemTotal = 30

        XCTAssertEqual(snapshot.batteryToSystem, 0)
        XCTAssertEqual(snapshot.adapterToSystem, 30, accuracy: 0.001)
    }

    func testE4SemBateriaOPainelNaoMostraBateria() {
        var snapshot = PowerSnapshot()
        snapshot.systemTotal = 8.5

        let panel = PanelState(snapshot: snapshot, sensorsAvailable: true)
        XCTAssertFalse(panel.showsBattery)
        XCTAssertEqual(panel.batteryActivity, .idle)
    }

    // MARK: - E5: identidade das fatias

    /// O bug: cada leitura dava um `UUID` novo a cada fatia.
    func testE5AsFatiasMantemAIdentidadeEntreLeituras() {
        var first = PowerSnapshot()
        first.systemTotal = 10
        first.socPower = 2
        first.mainRailPower = 3

        var second = first
        second.systemTotal = 14
        second.socPower = 5

        XCTAssertEqual(first.breakdown.map(\.kind), [.soc, .mainRail, .other])
        XCTAssertEqual(first.breakdown.map(\.id), second.breakdown.map(\.id))
        XCTAssertEqual(first.breakdown.map(\.id), first.breakdown.map(\.id))
    }

    func testAsFatiasSomamOConsumoDoSistema() {
        var snapshot = PowerSnapshot()
        snapshot.systemTotal = 10
        snapshot.socPower = 2
        snapshot.mainRailPower = 3

        XCTAssertEqual(snapshot.breakdown.map(\.watts), [2, 3, 5])
    }

    func testSemLeiturasNaoHaFatias() {
        XCTAssertTrue(PowerSnapshot().breakdown.isEmpty)
    }

    // MARK: - Reduzir Movimento

    /// O bug: a app ignorava a definição e as partículas continuavam.
    func testReduzirMovimentoTiraAsParticulasEMantemOResto() {
        let moving = EdgeFlow(watts: 30, reduceMotion: false)
        let still = EdgeFlow(watts: 30, reduceMotion: true)

        XCTAssertTrue(moving.hasParticles)
        XCTAssertFalse(still.hasParticles)
        XCTAssertTrue(still.isActive)
        XCTAssertEqual(still.tubeWidth, moving.tubeWidth)
        XCTAssertEqual(still.chevronSize, moving.chevronSize)
    }

    /// As fórmulas do handoff: k = √(min(W, 70) / 70) e sw = 2,5 + 9·k.
    func testAsArestasSeguemAsFormulasDoHandoff() {
        let full = EdgeFlow(watts: 70, reduceMotion: false)
        XCTAssertEqual(full.tubeWidth, 11.5, accuracy: 0.001)
        XCTAssertEqual(full.coreWidth, 2.98, accuracy: 0.001)
        XCTAssertEqual(full.chevronSize, 7.05, accuracy: 0.001)
        XCTAssertEqual(full.particleDiameter, 8.05, accuracy: 0.001)
        XCTAssertEqual(full.particleSpeed, 60, accuracy: 0.001)

        // Acima de 70 W a espessura já não cresce.
        XCTAssertEqual(EdgeFlow(watts: 140, reduceMotion: false).tubeWidth, 11.5, accuracy: 0.001)

        let quarter = EdgeFlow(watts: 17.5, reduceMotion: false)
        XCTAssertEqual(quarter.tubeWidth, 7, accuracy: 0.001)
        XCTAssertEqual(quarter.particleSpeed, 37, accuracy: 0.001)

        // As partículas nunca ficam abaixo de 4 pt: com menos não se viam.
        XCTAssertEqual(EdgeFlow(watts: 1, reduceMotion: false).particleDiameter, 4, accuracy: 0.001)
        // E ficam sempre dentro do tubo e mais largas do que o núcleo.
        for watts in [0.5, 5, 12, 36, 70] {
            let flow = EdgeFlow(watts: watts, reduceMotion: false)
            XCTAssertGreaterThan(flow.particleDiameter, flow.coreWidth + 1.5, "\(watts) W")
            XCTAssertLessThanOrEqual(flow.particleDiameter, max(flow.tubeWidth, 4), "\(watts) W")
        }
    }

    func testArestaSemCaudalFicaApagada() {
        let idle = EdgeFlow(watts: 0.1, reduceMotion: false)
        XCTAssertFalse(idle.isActive)
        XCTAssertFalse(idle.hasParticles)
    }

    /// A estabilizar nenhum caudal é de confiança: as arestas ficam em trilho.
    func testAEstabilizarNenhumaArestaAcende() {
        let flow = EdgeFlow(watts: 30, isSuppressed: true, reduceMotion: false)
        XCTAssertFalse(flow.isActive)
        XCTAssertFalse(flow.hasParticles)
    }

    // MARK: - Os dois ritmos de amostragem

    private func rails(input: Double, total: Double) -> RailReading {
        var reading = RailReading()
        reading.adapterInput = input
        reading.systemTotal = total
        return reading
    }

    func testAMediaLentaAlinhaAoFimDeQuatroLeituras() {
        var smoother = DualRateSmoother()
        for _ in 0..<3 { smoother.addSlow(rails(input: 20, total: 20)) }
        XCTAssertFalse(smoother.isSettled)

        smoother.addSlow(rails(input: 20, total: 20))
        XCTAssertTrue(smoother.isSettled)
    }

    /// D5: a 1 Hz uma amostra pode cair entre a atualização dos dois
    /// registos e falhar o recuo por um segundo inteiro. A média lenta dá
    /// números, mas a diferença entre eles não se lê como assistência.
    func testD5A1HzADiferencaNaoSeLeComoAssistencia() {
        var smoother = DualRateSmoother()
        for _ in 0..<10 { smoother.addSlow(rails(input: 20, total: 29.5)) }

        XCTAssertTrue(smoother.isSettled)
        XCTAssertFalse(smoother.isAligned)

        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = true
        snapshot.apply(smoother.average)
        snapshot.isAligned = smoother.isAligned
        XCTAssertEqual(snapshot.batteryToSystem, 0)
    }

    /// Abrir o painel liga o ritmo rápido com a janela vazia. Se a média
    /// rápida respondesse logo, o painel voltava a «A estabilizar» a cada
    /// abertura.
    func testAbrirOPainelNaoVoltaAEstabilizar() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }

        smoother.setFast(true)
        smoother.addFast(rails(input: 50, total: 40))

        XCTAssertTrue(smoother.isSettled)
        XCTAssertFalse(smoother.isAligned)
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 18, accuracy: 0.001,
                       "enquanto a média rápida enche, responde a lenta")
    }

    func testAMediaRapidaRespondeDepoisDeEncher() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }

        smoother.setFast(true)
        for _ in 0..<40 { smoother.addFast(rails(input: 50, total: 40)) }

        XCTAssertTrue(smoother.isAligned)
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 40, accuracy: 0.001)
    }

    /// Fechado o painel, responde a média lenta, e a rápida é deitada fora:
    /// ao reabrir, o que lá estava já não é recente.
    func testFechadoOPainelSoContaOLento() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }
        smoother.setFast(true)
        for _ in 0..<40 { smoother.addFast(rails(input: 50, total: 40)) }

        smoother.setFast(false)
        smoother.addFast(rails(input: 50, total: 40))
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 18, accuracy: 0.001)

        smoother.setFast(true)
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 18, accuracy: 0.001,
                       "ao reabrir, a média rápida recomeça vazia")
    }

    /// D5: o consumo é a entrada com 1,0 s de atraso. Com o recuo certo,
    /// uma rampa de carga não deixa diferença nenhuma entre os dois; com
    /// 0,9 s ficava cerca de 1 W, que se lia como a bateria a ajudar.
    func testD5UmaRampaDeCargaNaoPareceAssistencia() {
        var smoother = DualRateSmoother()
        smoother.setFast(true)

        // 60 amostras a 10 Hz: 10 W parados, depois uma rampa de 3 W por
        // amostra. O consumo repete a entrada dez amostras mais tarde.
        let input = (0..<60).map { 10 + 3 * Double(max(0, $0 - 20)) }
        for index in input.indices {
            smoother.addFast(rails(input: input[index], total: input[max(0, index - 10)]))
        }

        let average = smoother.average
        XCTAssertEqual(average.systemTotal ?? 0, average.adapterInput ?? -1, accuracy: 0.001)
    }

    /// D5: nos 4 s depois de ligar o cabo, a janela ainda tem a entrada a
    /// zero de quando estava desligado. Isso não é a bateria a ajudar.
    func testD5LigarOCaboNaoPareceAssistencia() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 0, total: 16)) }
        smoother.setFast(true)
        for _ in 0..<40 { smoother.addFast(rails(input: 0, total: 16)) }
        XCTAssertTrue(smoother.isAligned)

        smoother.sourceChanged()
        for _ in 0..<10 { smoother.addFast(rails(input: 16, total: 16)) }
        XCTAssertFalse(smoother.isAligned)
        XCTAssertTrue(smoother.isSettled, "os números continuam a mostrar-se")

        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = true
        snapshot.apply(smoother.average)
        snapshot.isAligned = smoother.isAligned
        XCTAssertEqual(snapshot.batteryToSystem, 0)
    }

    // MARK: - E2: instância única

    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("powerflow-teste-\(UUID().uuidString)")
            .appendingPathComponent("instance.lock")
    }

    /// O bug: nada impedia uma segunda instância de arrancar.
    func testE2ASegundaInstanciaNaoFicaComOTrinco() {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        guard case .acquired(let first) = InstanceLock.acquire(at: url) else {
            return XCTFail("a primeira instância devia ficar com o trinco")
        }
        guard case .heldByAnother = InstanceLock.acquire(at: url) else {
            return XCTFail("a segunda instância não podia ficar com o trinco")
        }
        withExtendedLifetime(first) {}
    }

    /// Quando a primeira sai, o trinco fica livre para a seguinte.
    func testE2OTrincoSoltaSeQuandoAInstanciaSai() {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            guard case .acquired = InstanceLock.acquire(at: url) else {
                return XCTFail("a primeira instância devia ficar com o trinco")
            }
        }
        guard case .acquired = InstanceLock.acquire(at: url) else {
            return XCTFail("depois de a primeira sair, o trinco devia estar livre")
        }
    }
}
