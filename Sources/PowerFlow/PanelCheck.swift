import AppKit
import PowerFlowCore

/// Verificação do painel na app verdadeira: `PowerFlow --panel-check`.
///
/// Abre o painel, fecha-o e confirma o que fica a correr em cada estado.
/// O que decide é o CPU que o processo gastou em cada janela, contra o
/// orçamento D6. Os despertares da thread principal vão só como informação:
/// dizem porquê (uma animação desenhada pela app acorda-a a cada fotograma),
/// mas também sobem quando o rato passa por cima do painel.
extension StatusItemController {
    /// Orçamento D6, em percentagem de um núcleo.
    private static let openBudget = 8.0
    private static let reducedMotionBudget = 3.0
    private static let closedBudget = 1.0

    private static let openWindow: TimeInterval = 5
    /// Fechado, o orçamento é apertado e uma janela curta apanhava ruído.
    private static let closedWindow: TimeInterval = 10

    /// Segundos de CPU, de utilizador e de sistema, gastos pelo processo.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double {
            Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    func runPanelCheck() {
        setvbuf(stdout, nil, _IOLBF, 0)

        var wakeups = 0
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, 0
        ) { _, _ in wakeups += 1 }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)

        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("  \(ok ? "ok    " : "FALHOU")  \(label)")
            if !ok { failures += 1 }
        }
        func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                MainActor.assumeIsolated { work() }
            }
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var before: [CGPoint] = []
        var cpuAtStart = 0.0

        print("== Verificação do painel (Reduzir Movimento: \(reduceMotion ? "ligado" : "desligado")) ==")

        // Aos 5 s o item já está na barra; antes disso o painel não abre.
        let opened: TimeInterval = 5
        after(opened) {
            self.holdPanel()
            check(self.popover?.isShown == true, "o painel abre por código")
        }
        after(opened + 1) {
            wakeups = 0
            cpuAtStart = Self.cpuSeconds()
            before = self.particlePositions()
        }
        after(opened + 1 + Self.openWindow) {
            // Um clique no item fecha o painel. Se foi isso que aconteceu,
            // a janela não mediu o painel aberto.
            guard self.popover?.isShown == true else {
                print("  Inconclusivo: o painel foi fechado por fora a meio. Repete sem clicar.")
                exit(3)
            }
            let cpu = (Self.cpuSeconds() - cpuAtStart) / Self.openWindow * 100
            let budget = reduceMotion ? Self.reducedMotionBudget : Self.openBudget
            let positions = self.particlePositions()

            check(cpu <= budget,
                  String(format: "aberto: %.1f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, budget, Double(wakeups) / Self.openWindow))
            check(self.monitor?.isSamplingFast == true, "aberto: leituras a 10 Hz ligadas")

            if reduceMotion {
                check(positions.isEmpty,
                      "Reduzir Movimento: sem partículas (\(positions.count))")
            } else {
                let moved = zip(before, positions).filter { $0 != $1 }.count
                check(!positions.isEmpty && moved == positions.count,
                      "partículas a mover-se: \(moved) de \(positions.count)")
                check(Set(positions.map { "\(Int($0.x)),\(Int($0.y))" }).count > 1,
                      "partículas repartidas pelo caminho")
            }

            self.closePanel()
        }
        let closed = opened + 2 + Self.openWindow
        after(closed) {
            wakeups = 0
            cpuAtStart = Self.cpuSeconds()
        }
        after(closed + Self.closedWindow) {
            let cpu = (Self.cpuSeconds() - cpuAtStart) / Self.closedWindow * 100

            check(self.popover?.isShown == false, "o painel fecha por código")
            check(self.popover?.contentViewController == nil,
                  "fechado: o conteúdo do painel deixou de existir")
            check(self.monitor?.isSamplingFast == false, "fechado: leituras a 10 Hz paradas")
            check(cpu <= Self.closedBudget,
                  String(format: "fechado: %.2f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, Self.closedBudget, Double(wakeups) / Self.closedWindow))

            print(failures == 0 ? "Painel: tudo certo." : "Painel: \(failures) falha(s).")
            exit(failures == 0 ? 0 : 1)
        }
    }

    /// Onde está cada partícula neste instante, lido da camada que o Core
    /// Animation está a apresentar.
    private func particlePositions() -> [CGPoint] {
        guard let root = popover?.contentViewController?.view else { return [] }
        return Self.particleHosts(in: root)
            .flatMap(\.particleLayers)
            .compactMap { $0.presentation()?.position }
    }

    private static func particleHosts(in view: NSView) -> [ParticleHostView] {
        var found = view.subviews.flatMap { particleHosts(in: $0) }
        if let host = view as? ParticleHostView { found.append(host) }
        return found
    }
}
