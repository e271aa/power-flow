import Foundation

/// Verificações do modelo de fluxo, sobre instantâneos sintéticos.
///
/// Não usa XCTest de propósito: com apenas as Command Line Tools instaladas
/// (sem o Xcode completo) o XCTest não está disponível, e a app inteira é
/// construída para viver nessas condições. Corre com `PowerFlow --selftest`.
public enum SelfTest {
    private static var failures = 0
    private static var checks = 0

    public static func run() -> Int32 {
        failures = 0
        checks = 0

        adapterChargingBalances()
        batteryAssistUnderLoad()
        onBatteryUsesSystemTotal()
        noPhantomChargeWhenNotCharging()
        samplingNoiseIsNotAssist()
        degradesWithoutSystemTotal()
        batteryHealthAndReason()
        smootherAverages()
        smootherSlidesWindow()
        smootherIgnoresMissingKeys()
        smootherAlignsAdapterWithDelay()
        noAssistWhileWindowIsFilling()
        transientSpikeDoesNotShowAsAssist()
        sustainedDeficitStillShowsAsAssist()

        print(failures == 0
              ? "\n\(checks) verificações, todas passaram."
              : "\n\(checks) verificações, \(failures) falharam.")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Casos

    /// Com o cabo ligado e a carregar, os dois ramos têm de somar a entrada.
    private static func adapterChargingBalances() {
        var snapshot = charging(input: 65.2, total: 30.0)
        expect(snapshot.adapterToSystem, 30.0, "adaptador -> sistema")
        expect(snapshot.adapterToBattery, 35.2, "adaptador -> bateria")
        expect(snapshot.batteryToSystem, 0, "sem assistência")
        expect(snapshot.adapterToSystem + snapshot.adapterToBattery, 65.2, "balanço total")
        snapshot.systemTotal = 10
        expect(snapshot.adapterToBattery, 55.2, "carga sobe quando o sistema alivia")
    }

    /// Quando o sistema pede mais do que o adaptador dá, a bateria assiste.
    private static func batteryAssistUnderLoad() {
        let snapshot = connectedNotCharging(input: 20, total: 30)
        expect(snapshot.batteryToSystem, 10, "assistência da bateria")
        expect(snapshot.adapterToSystem, 20, "adaptador dá o que pode")
        expect(snapshot.adapterToBattery, 0, "não carrega enquanto assiste")
    }

    /// Sem cabo, todo o consumo sai da bateria.
    private static func onBatteryUsesSystemTotal() {
        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = false
        snapshot.systemTotal = 12.5
        snapshot.batteryMagnitude = 11.0
        expect(snapshot.batteryToSystem, 12.5, "bateria -> sistema")
        expect(snapshot.adapterToSystem, 0, "adaptador inativo")
        expect(snapshot.adapterToBattery, 0, "não carrega sem cabo")
    }

    /// Com o cabo ligado mas sem carregar, o excedente não pode aparecer
    /// como carga — seria uma seta a mentir.
    private static func noPhantomChargeWhenNotCharging() {
        let snapshot = connectedNotCharging(input: 30, total: 20)
        expect(snapshot.adapterToBattery, 0, "sem carga fantasma")
    }

    /// Diferenças pequenas entre entrada e consumo são ruído, não assistência.
    private static func samplingNoiseIsNotAssist() {
        let snapshot = connectedNotCharging(input: 20, total: 21)
        expect(snapshot.batteryToSystem, 0, "1 W de desvio é ruído")
    }

    /// Sem a chave do consumo total, o modelo ainda tem de dar algo coerente.
    private static func degradesWithoutSystemTotal() {
        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = true
        snapshot.adapterInput = 60
        snapshot.systemTotal = nil
        snapshot.batteryMagnitude = 40
        expect(snapshot.adapterToBattery, 40, "recorre a V x A")
        expect(snapshot.adapterToSystem, 20, "resto vai para o sistema")
    }

    private static func batteryHealthAndReason() {
        var info = BatteryInfo()
        info.designCapacity = 6075
        info.fullChargeCapacity = 4964
        expectNear(info.healthPercent ?? 0, 81.7, tolerance: 0.1, "saúde da bateria")

        info.designCapacity = 0
        expectNil(info.healthPercent, "sem capacidade de fábrica não há saúde")

        var opt = BatteryInfo()
        opt.isExternalConnected = true
        opt.notChargingReason = 16777216
        expectEqual(opt.chargingExplanation, "Carga otimizada da Apple", "motivo traduzido")
    }

    /// A média é campo a campo sobre a janela.
    private static func smootherAverages() {
        var smoother = PowerSmoother(windowSize: 3)
        smoother.add(rails(input: 10, total: 10))
        smoother.add(rails(input: 20, total: 30))
        let result = smoother.add(rails(input: 30, total: 20))
        expect(result.adapterInput ?? 0, 20, "média da entrada")
        expect(result.systemTotal ?? 0, 20, "média do consumo")
    }

    /// Passada a capacidade, a leitura mais antiga sai.
    private static func smootherSlidesWindow() {
        var smoother = PowerSmoother(windowSize: 2)
        smoother.add(rails(input: 100, total: 100))
        smoother.add(rails(input: 10, total: 10))
        let result = smoother.add(rails(input: 20, total: 20))
        expect(result.adapterInput ?? 0, 15, "os 100 W saíram da janela")
    }

    /// Uma chave inexistente não pode arrastar a média para baixo.
    private static func smootherIgnoresMissingKeys() {
        var smoother = PowerSmoother(windowSize: 3)
        var missing = RailReading()
        missing.systemTotal = 10
        missing.adapterInput = nil
        smoother.add(missing)
        var present = RailReading()
        present.systemTotal = 20
        present.adapterInput = 40
        let result = smoother.add(present)
        expect(result.adapterInput ?? -1, 40, "média só sobre o valor presente")
        expect(result.systemTotal ?? 0, 15, "o outro campo faz média normal")
    }

    /// A janela do adaptador tem de recuar, para compensar o atraso de 0.9 s
    /// do registo do consumo. Sem isto, uma descida na entrada aparecia como
    /// assistência da bateria que nunca existiu.
    private static func smootherAlignsAdapterWithDelay() {
        var smoother = PowerSmoother(windowSize: 2, adapterDelay: 2)
        smoother.add(rails(input: 10, total: 10))
        smoother.add(rails(input: 10, total: 10))
        smoother.add(rails(input: 20, total: 20))
        let result = smoother.add(rails(input: 20, total: 20))

        expect(result.systemTotal ?? 0, 20, "consumo usa a janela recente")
        expect(result.adapterInput ?? 0, 10, "entrada usa a janela recuada")
    }

    /// Nos primeiros segundos após o arranque as séries ainda não estão
    /// alinhadas. Sem esta salvaguarda, cada lançamento da app mostrava uma
    /// seta de bateria falsa durante cerca de quatro segundos.
    private static func noAssistWhileWindowIsFilling() {
        var smoother = PowerSmoother(windowSize: 4, adapterDelay: 2)
        smoother.add(rails(input: 12, total: 20))
        let early = smoother.average
        expectFalse(smoother.isAligned, "janela ainda a encher")

        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.isAligned = false
        snapshot.apply(early)
        expect(snapshot.batteryToSystem, 0, "sem seta durante o arranque")

        for _ in 0..<5 { smoother.add(rails(input: 12, total: 20)) }
        expectTrue(smoother.isAligned, "janela cheia depois de encher")
    }

    /// O caso que motivou a suavização: com o carregador ligado e a carga
    /// travada, um pico isolado punha a seta da bateria acesa durante um
    /// segundo inteiro. Números medidos a 20 Hz no M1 Pro.
    private static func transientSpikeDoesNotShowAsAssist() {
        var smoother = PowerSmoother(windowSize: 15)
        for _ in 0..<14 { smoother.add(rails(input: 23.5, total: 23.3)) }
        let averaged = smoother.add(rails(input: 15.0, total: 22.0))

        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.apply(averaged)
        expect(snapshot.batteryToSystem, 0, "pico isolado não acende a seta")
    }

    /// Mas um défice que se mantém tem de continuar a aparecer.
    private static func sustainedDeficitStillShowsAsAssist() {
        var smoother = PowerSmoother(windowSize: 15)
        for _ in 0..<15 { smoother.add(rails(input: 20, total: 30)) }

        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.apply(smoother.average)
        expect(snapshot.batteryToSystem, 10, "défice sustentado continua visível")
    }

    private static func rails(input: Double, total: Double) -> RailReading {
        var reading = RailReading()
        reading.adapterInput = input
        reading.systemTotal = total
        return reading
    }

    // MARK: - Construtores

    private static func charging(input: Double, total: Double) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = true
        snapshot.adapterInput = input
        snapshot.systemTotal = total
        return snapshot
    }

    private static func connectedNotCharging(input: Double, total: Double) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = false
        snapshot.adapterInput = input
        snapshot.systemTotal = total
        return snapshot
    }

    // MARK: - Asserções

    private static func expect(_ actual: Double, _ expected: Double, _ label: String) {
        expectNear(actual, expected, tolerance: 0.001, label)
    }

    private static func expectNear(_ actual: Double, _ expected: Double,
                                   tolerance: Double, _ label: String) {
        checks += 1
        if abs(actual - expected) <= tolerance {
            print("  ok   \(label)")
        } else {
            failures += 1
            print(String(format: "  FALHA %@ — esperado %.3f, obtido %.3f", label, expected, actual))
        }
    }

    private static func expectTrue(_ value: Bool, _ label: String) {
        checks += 1
        if value { print("  ok   \(label)") }
        else { failures += 1; print("  FALHA \(label) — esperado verdadeiro") }
    }

    private static func expectFalse(_ value: Bool, _ label: String) {
        checks += 1
        if !value { print("  ok   \(label)") }
        else { failures += 1; print("  FALHA \(label) — esperado falso") }
    }

    private static func expectNil<T>(_ value: T?, _ label: String) {
        checks += 1
        if value == nil { print("  ok   \(label)") }
        else { failures += 1; print("  FALHA \(label) — esperado nil") }
    }

    private static func expectEqual(_ actual: String?, _ expected: String, _ label: String) {
        checks += 1
        if actual == expected { print("  ok   \(label)") }
        else {
            failures += 1
            print("  FALHA \(label) — esperado \"\(expected)\", obtido \"\(actual ?? "nil")\"")
        }
    }
}
