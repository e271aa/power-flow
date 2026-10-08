import AppKit
import PowerFlowCore
import SwiftUI

/// `--window --growth-probe [s]`: confere que nada se acumula com o painel a receber leituras.
///
/// Na Fase 16 o CPU do painel aberto subia cerca de 0,1 pontos por hora. A
/// causa: as séries do histórico eram um `Canvas` e, com o gráfico de 2 min
/// cheio, redesenhavam-se a cada segundo numa superfície própria do RenderBox.
/// Cada superfície devolvida deixava um temporizador de limpeza
/// (`RB::SurfacePool::collect`) que se volta a agendar enquanto houver
/// superfícies à espera, e havia sempre: ficava um temporizador a mais por
/// segundo, até o painel fechar.
///
/// A sonda mostra o painel com o histórico de 2 min cheio, dá-lhe uma leitura
/// nova por segundo e conta as fontes de dispatch vivas no princípio e no
/// fim, com o `heap` do sistema. Sai com 0 se não cresceram, 1 se cresceram
/// e 2 se não conseguiu medir: sem contagem, ou com a janela tapada (uma
/// janela que não se vê não se redesenha, e o defeito não aparecia).
@MainActor
final class GrowthProbe {
    let feed = MotionProbe.Feed(.charging)
    let navigation = PanelNavigation()
    private let seconds: Double
    private let window: NSWindow
    private var ticker: Timer?
    private var ticks = 0
    private var visibleTicks = 0
    private var activity: NSObjectProtocol?

    /// As fontes do sistema vão e vêm: medido, o painel parado oscila 2 ou 3.
    /// Com o defeito são cerca de 0,95 a mais por segundo.
    static let tolerance = 5
    /// Antes da primeira contagem: o painel monta-se e as fontes do arranque
    /// saem (medido: 68 aos 4 s, 63 daí em diante).
    private static let settle = 10.0

    init(seconds: Double, window: NSWindow) {
        self.seconds = seconds
        self.window = window
    }

    func run() {
        // Sem isto o App Nap espaçava as leituras de uma janela que não está à frente.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "sonda de crescimento")
        print(String(format: "== Sonda de crescimento: histórico de 2 min cheio, uma leitura por segundo, %.0f s ==",
                     seconds))
        fflush(stdout)

        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        after(Self.settle) {
            (self.ticks, self.visibleTicks) = (0, 0)
            let first = Self.liveDispatchSources()
            self.after(self.seconds) { self.finish(first: first, last: Self.liveDispatchSources()) }
        }
    }

    /// Uma leitura de 1 Hz no histórico, a variar para o desenho mudar sempre.
    private func tick() {
        let now = Date()
        let base = feed.current.systemTotal ?? 10
        let wave = 1 + 0.25 * sin(now.timeIntervalSince1970 / 7)
        feed.history.append(system: base * wave, adapter: feed.current.adapterInput, at: now)
        feed.set(feed.current)
        ticks += 1
        if window.occlusionState.contains(.visible) { visibleTicks += 1 }
    }

    private func finish(first: Int?, last: Int?) {
        ticker?.invalidate()
        guard let first, let last else {
            print("não medido: o /usr/bin/heap não deu a contagem das fontes de dispatch")
            exit(2)
        }
        guard visibleTicks == ticks else {
            print("não medido: a janela só esteve à vista em \(visibleTicks) de \(ticks) leituras")
            exit(2)
        }
        let grew = last - first
        print(String(format: "fontes de dispatch vivas: %d → %d (%+d em %.0f s; aceita-se até +%d)",
                     first, last, grew, seconds, Self.tolerance))
        print(grew <= Self.tolerance ? "certo" : "FALHOU: as fontes de dispatch acumulam-se com o painel aberto")
        exit(grew <= Self.tolerance ? 0 : 1)
    }

    private func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(body) }
    }

    /// As fontes de dispatch vivas neste processo (`dispatch_source_t`),
    /// contadas pelo `heap`. `nil`: o `heap` não correu ou não as listou.
    ///
    /// O `heap` suspende o processo enquanto o lê, por isso escreve para um
    /// ficheiro: com um pipe ninguém o esvaziava.
    static func liveDispatchSources() -> Int? {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("powerflow-heap-\(getpid()).txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        guard let handle = try? FileHandle(forWritingTo: output) else { return nil }

        let heap = Process()
        heap.executableURL = URL(fileURLWithPath: "/usr/bin/heap")
        heap.arguments = ["\(getpid())"]
        heap.standardOutput = handle
        heap.standardError = FileHandle.nullDevice
        do { try heap.run() } catch { return nil }
        heap.waitUntilExit()
        try? handle.close()

        guard let text = try? String(contentsOf: output, encoding: .utf8) else { return nil }
        return dispatchSources(inHeapOutput: text)
    }

    /// Cada linha do `heap`: contagem, bytes, média, classe, tipo, binário.
    nonisolated static func dispatchSources(inHeapOutput text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 4, fields[3] == "dispatch_source_t" { return Int(fields[0]) }
        }
        return nil
    }
}
