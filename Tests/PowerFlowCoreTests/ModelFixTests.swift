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

        XCTAssertGreaterThan(moving.particleCount, 0)
        XCTAssertEqual(still.particleCount, 0)
        XCTAssertTrue(still.isActive)
        XCTAssertEqual(still.lineWidth, moving.lineWidth)
    }

    /// As partículas mudaram de técnica, não de aspeto: os números são os
    /// do desenho antigo.
    func testAsArestasTemOAspetoDeAntes() {
        let full = EdgeFlow(watts: 60, reduceMotion: false)
        XCTAssertEqual(full.lineWidth, 6, accuracy: 0.001)
        XCTAssertEqual(full.particleCount, 12)
        XCTAssertEqual(full.particleSpeed, 0.55, accuracy: 0.001)
        XCTAssertEqual(full.particleRadius, 4.0, accuracy: 0.001)

        let quarter = EdgeFlow(watts: 15, reduceMotion: false)
        XCTAssertEqual(quarter.lineWidth, 4, accuracy: 0.001)
        XCTAssertEqual(quarter.particleCount, 7)
        XCTAssertEqual(quarter.particleSpeed, 0.325, accuracy: 0.001)
        XCTAssertEqual(quarter.particleRadius, 2.9, accuracy: 0.001)
    }

    func testArestaSemCaudalFicaApagada() {
        let idle = EdgeFlow(watts: 0.1, reduceMotion: false)
        XCTAssertFalse(idle.isActive)
        XCTAssertEqual(idle.lineWidth, 2)
        XCTAssertEqual(idle.particleCount, 0)
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
