import XCTest
@testable import PowerFlowCore

/// Teste de fumo: prova que o target de testes compila, liga ao
/// `PowerFlowCore` e que o modelo responde. Não lê sensores.
final class SmokeTests: XCTestCase {
    /// Com o cabo desligado, tudo o que o sistema consome sai da bateria.
    func testEmBateriaOConsumoSaiTodoDaBateria() {
        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = false
        snapshot.systemTotal = 12.5

        XCTAssertEqual(snapshot.source, .battery)
        XCTAssertEqual(snapshot.batteryToSystem, 12.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.adapterToSystem, 0)
        XCTAssertEqual(snapshot.adapterToBattery, 0)
    }

    /// Com o cabo ligado e a carregar, o que entra reparte-se pelo sistema
    /// e pela bateria sem sobrar nem faltar.
    func testACarregarOBalancoFecha() {
        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = true
        snapshot.adapterInput = 60
        snapshot.systemTotal = 20

        XCTAssertEqual(snapshot.source, .adapter)
        XCTAssertEqual(snapshot.adapterToSystem, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot.adapterToBattery, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.batteryToSystem, 0)
    }

    /// O histórico é um anel: cheio, deita fora a amostra mais antiga e
    /// devolve as restantes por ordem cronológica.
    func testHistoricoEUmAnelPorOrdemCronologica() {
        let history = PowerHistory(capacity: 3)
        for watts in [1.0, 2.0, 3.0, 4.0] {
            var snapshot = PowerSnapshot()
            snapshot.systemTotal = watts
            history.append(snapshot)
        }

        XCTAssertEqual(history.samples.map(\.systemTotal), [2, 3, 4])
        XCTAssertEqual(history.recent(seconds: 2).map(\.systemTotal), [3, 4])
        XCTAssertEqual(history.peakSystemTotal, 4)
    }
}
