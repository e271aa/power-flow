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
            || forceReduceMotion
        var before: [CGFloat] = []
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
            before = self.particlePhases()
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
            let phases = self.particlePhases()

            check(cpu <= budget,
                  String(format: "aberto: %.1f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, budget, Double(wakeups) / Self.openWindow))
            let expectedHz = AppSettings.sampleRate().fastHz
            check(self.monitor?.fastHz == expectedHz,
                  "aberto: leituras rápidas a \(self.monitor?.fastHz.map { "\($0) Hz" } ?? "1 Hz (Baixa)"), como nas Definições")

            if reduceMotion {
                check(phases.isEmpty,
                      "Reduzir Movimento: sem partículas (\(phases.count) arestas com elas)")
            } else {
                let moved = zip(before, phases).filter { $0 != $1 }.count
                check(!phases.isEmpty && moved == phases.count,
                      "partículas a mover-se: em \(moved) de \(phases.count) arestas")
            }

        }

        // Navegação: entrar no nível 2 como os botões entram, e voltar pelo teclado.
        let navigated = opened + 1 + Self.openWindow
        var mainHeight: CGFloat = 0
        after(navigated + 0.1) {
            mainHeight = self.popover?.contentSize.height ?? 0
            self.navigation?.push(.battery, reduceMotion: reduceMotion)
        }
        after(navigated + 1.0) {
            let height = self.popover?.contentSize.height ?? 0
            check(self.navigation?.route == .battery, "push para a bateria")
            check(height > 0 && height != mainHeight,
                  String(format: "a altura do painel acompanha a vista: %.0f pt no nível 1, %.0f pt na bateria",
                         mainHeight, height))
            self.sendKey("\u{1B}", code: 53)
        }
        after(navigated + 1.6) {
            check(self.navigation?.route == .main && self.popover?.isShown == true,
                  "Esc volta ao nível 1 sem fechar o painel")
            self.navigation?.push(.apps, reduceMotion: reduceMotion)
        }
        after(navigated + 2.9) {
            check(self.navigation?.route == .apps, "push para «Por app»")
            check(self.apps.isSampling, "«Por app»: o amostrador por app está ligado")
            let height = self.popover?.contentSize.height ?? 0
            check(self.apps.report.measuredAt != nil,
                  "«Por app»: há média 1,3 s depois de entrar (\(self.apps.report.apps.count) apps)")
            check(height > 0 && height != mainHeight,
                  String(format: "a altura acompanha «Por app»: %.0f pt no nível 1, %.0f pt em «Por app»",
                         mainHeight, height))
            self.sendKey("[", code: 33, modifiers: .command)
        }
        after(navigated + 3.5) {
            check(self.navigation?.route == .main && self.popover?.isShown == true,
                  "⌘[ volta ao nível 1 sem fechar o painel")
            check(!self.apps.isSampling, "de volta ao nível 1: o amostrador por app parou")
            // Fechar o painel com a vista Apps aberta também o pára.
            self.navigation?.push(.apps, reduceMotion: reduceMotion)
        }
        after(navigated + 4.0) {
            check(self.apps.isSampling, "«Por app» outra vez: o amostrador volta a ligar")
        }

        // As Definições chegam ao monitor e ao item pelo `UserDefaults`, como
        // quando a janela as muda. Guardam-se as do utilizador e repõem-se.
        let defaults = UserDefaults.standard
        let savedRate = defaults.object(forKey: AppSettings.sampleRateKey)
        let savedMode = defaults.object(forKey: AppSettings.barModeKey)
        after(navigated + 4.2) {
            defaults.set("high", forKey: AppSettings.sampleRateKey)
            defaults.set("watts", forKey: AppSettings.barModeKey)
        }
        after(navigated + 4.6) {
            let bar = self.barButtonState
            check(self.monitor?.fastHz == 10, "Definições: «Alta» põe o painel aberto a 10 Hz")
            check(!bar.hasImage && bar.title.contains("W"), "Definições: «Só watts» tira o ícone (título «\(bar.title)»)")
            defaults.set("low", forKey: AppSettings.sampleRateKey)
            defaults.set("icon", forKey: AppSettings.barModeKey)
        }
        after(navigated + 5.0) {
            let bar = self.barButtonState
            check(self.monitor?.isSamplingFast == false, "Definições: «Baixa» deixa o painel aberto a 1 Hz")
            check(bar.hasImage && bar.title.isEmpty, "Definições: «Só ícone» tira o título")
            defaults.set("normal", forKey: AppSettings.sampleRateKey)
            defaults.set("iconPercent", forKey: AppSettings.barModeKey)
        }
        after(navigated + 5.4) {
            let bar = self.barButtonState
            check(self.monitor?.fastHz == 2, "Definições: «Normal» põe o painel aberto a 2 Hz")
            let hasBattery = self.monitor?.snapshot.battery.isPresent == true
            check(bar.hasImage && bar.title.hasSuffix(hasBattery ? "%" : "W"),
                  "Definições: «Ícone e %» mostra «\(bar.title)»")
            if let savedRate { defaults.set(savedRate, forKey: AppSettings.sampleRateKey) } else { defaults.removeObject(forKey: AppSettings.sampleRateKey) }
            if let savedMode { defaults.set(savedMode, forKey: AppSettings.barModeKey) } else { defaults.removeObject(forKey: AppSettings.barModeKey) }
        }
        // Primeiro arranque: o cartão aparece, «Percebi» (Return) grava
        // `pf.firstRunDone`, e reaberto o painel já não o tem.
        let savedFirstRun = defaults.object(forKey: AppSettings.firstRunDoneKey)
        after(navigated + 5.8) {
            self.navigation?.pop(animated: false, reduceMotion: true)
            defaults.set(false, forKey: AppSettings.firstRunDoneKey)
        }
        after(navigated + 6.4) {
            check(FirstRunCard.shownCount == 1, "primeiro arranque: o cartão aparece")
            self.sendKey("\r", code: 36)
        }
        after(navigated + 7.0) {
            check(AppSettings.firstRunDone(), "«Percebi» (Return) grava pf.firstRunDone")
            check(FirstRunCard.shownCount == 0, "depois de «Percebi» o cartão sai")
            self.closePanel()
        }
        after(navigated + 7.4) { self.holdPanel() }
        after(navigated + 8.0) {
            check(self.popover?.isShown == true && FirstRunCard.shownCount == 0,
                  "reaberto, o cartão não volta")
            if let savedFirstRun { defaults.set(savedFirstRun, forKey: AppSettings.firstRunDoneKey) } else { defaults.removeObject(forKey: AppSettings.firstRunDoneKey) }
        }

        after(navigated + 8.2) {
            self.closePanel()
        }
        let closed = navigated + 8.9
        after(closed) {
            wakeups = 0
            cpuAtStart = Self.cpuSeconds()
        }
        after(closed + Self.closedWindow) {
            let cpu = (Self.cpuSeconds() - cpuAtStart) / Self.closedWindow * 100

            check(self.popover?.isShown == false, "o painel fecha por código")
            check(self.popover?.contentViewController == nil,
                  "fechado: o conteúdo do painel deixou de existir")
            check(self.monitor?.isSamplingFast == false, "fechado: leituras rápidas paradas (1 Hz)")
            check(!self.apps.isSampling, "fechado: o amostrador por app parado")
            check(cpu <= Self.closedBudget,
                  String(format: "fechado: %.2f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, Self.closedBudget, Double(wakeups) / Self.closedWindow))

            print(failures == 0 ? "Painel: tudo certo." : "Painel: \(failures) falha(s).")
            exit(failures == 0 ? 0 : 1)
        }
    }

    /// Uma tecla premida na janela do painel, como se viesse do teclado.
    private func sendKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        guard let window = popover?.contentViewController?.view.window,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: code)
        else { return }
        NSApp.sendEvent(event)
    }

    /// Em que ponto vai o tracejado de cada aresta neste instante, lido da
    /// camada que o Core Animation está a apresentar.
    private func particlePhases() -> [CGFloat] {
        guard let root = popover?.contentViewController?.view else { return [] }
        return Self.particleHosts(in: root).flatMap(\.particlePhases)
    }

    private static func particleHosts(in view: NSView) -> [ParticleHostView] {
        var found = view.subviews.flatMap { particleHosts(in: $0) }
        if let host = view as? ParticleHostView { found.append(host) }
        return found
    }
}
