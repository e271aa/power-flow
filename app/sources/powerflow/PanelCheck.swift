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

        // `--panel-trace <ficheiro>`: cada ação, cada verificação e cada mudança
        // do que os passos leem, com a hora, para as falhas intermitentes.
        let trace = panelTrace.map { PanelTrace(path: $0) }
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("  \(ok ? "ok    " : "FALHOU")  \(label)")
            trace?.write("\(ok ? "ok" : "FALHOU"): \(label)")
            if !ok { failures += 1 }
        }
        func act(_ label: String) { trace?.write("ação: \(label)") }
        // Os passos correm por ordem, cada um à distância certa do anterior.
        // Agendados todos ao começar com `asyncAfter`, chegavam até 5 % do
        // prazo atrasados (1,2 s aos 24 s), e dois passos seguidos podiam
        // correr com 0,02 s entre eles em vez de 0,6 s (Fase 14).
        var steps: [(at: TimeInterval, work: @MainActor () -> Void)] = []
        func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
            steps.append((seconds, work))
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || forceReduceMotion
        var before: [CGFloat] = []
        var cpuAtStart = 0.0
        var windowStart = Date()

        print("== Verificação do painel (Reduzir Movimento: \(reduceMotion ? "ligado" : "desligado")) ==")

        // O cartão de primeiro arranque só entra no passo dele: à vista desde o
        // início, o Return não lhe chegava (visto na Fase 10, também na Fase 9).
        // O valor do utilizador repõe-se no fim da verificação.
        let savedFirstRun = UserDefaults.standard.object(forKey: AppSettings.firstRunDoneKey)
        UserDefaults.standard.set(true, forKey: AppSettings.firstRunDoneKey)

        // Aos 5 s o item já está na barra; antes disso o painel não abre.
        let opened: TimeInterval = 5
        after(opened) {
            self.holdPanel()
            check(self.popover?.isShown == true, "o painel abre por código")
        }
        after(opened + 1) {
            wakeups = 0
            cpuAtStart = Self.cpuSeconds()
            windowStart = Date()
            before = self.particlePhases()
        }
        after(opened + 1 + Self.openWindow) {
            // Um clique no item fecha o painel. Se foi isso que aconteceu,
            // a janela não mediu o painel aberto.
            guard self.popover?.isShown == true else {
                print("  Inconclusivo: o painel foi fechado por fora a meio. Repete sem clicar.")
                exit(3)
            }
            let elapsed = Date().timeIntervalSince(windowStart)
            let cpu = (Self.cpuSeconds() - cpuAtStart) / elapsed * 100
            let budget = reduceMotion ? Self.reducedMotionBudget : Self.openBudget
            let phases = self.particlePhases()

            check(cpu <= budget,
                  String(format: "aberto: %.1f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, budget, Double(wakeups) / elapsed))
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
        if let trace {
            after(navigated) { trace.watch(self) }
            after(navigated + 13.2) { trace.stopWatching() }
        }
        after(navigated + 0.1) {
            mainHeight = self.popover?.contentSize.height ?? 0
            act("push bateria")
            self.navigation?.push(.battery, reduceMotion: reduceMotion)
        }
        after(navigated + 1.0) {
            let height = self.popover?.contentSize.height ?? 0
            check(self.navigation?.route == .battery, "push para a bateria")
            check(height > 0 && height != mainHeight,
                  String(format: "a altura do painel acompanha a vista: %.0f pt no nível 1, %.0f pt na bateria",
                         mainHeight, height))
            act("tecla Esc")
            self.sendKey("\u{1B}", code: 53)
        }
        after(navigated + 1.6) {
            check(self.navigation?.route == .main && self.popover?.isShown == true,
                  "Esc volta ao nível 1 sem fechar o painel")
            act("push «Por app»")
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
            act("tecla ⌘[")
            self.sendKey("[", code: 33, modifiers: .command)
        }
        after(navigated + 3.5) {
            check(self.navigation?.route == .main && self.popover?.isShown == true,
                  "⌘[ volta ao nível 1 sem fechar o painel")
            check(!self.apps.isSampling, "de volta ao nível 1: o amostrador por app parou")
            // Fechar o painel com a vista Apps aberta também o pára.
            act("push «Por app» outra vez")
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
            let bar = self.shownBar
            check(self.monitor?.fastHz == 10, "Definições: «Alta» põe o painel aberto a 10 Hz")
            check(bar?.content == .watts && self.barLength == MenuBarIcon.itemLength(for: .watts),
                  "Definições: «Só watts» mostra só os watts (\(self.barLength) pt)")
            defaults.set("low", forKey: AppSettings.sampleRateKey)
            defaults.set("icon", forKey: AppSettings.barModeKey)
        }
        after(navigated + 5.0) {
            let bar = self.shownBar
            let hasBattery = self.monitor?.snapshot.battery.isPresent == true
            check(self.monitor?.isSamplingFast == false, "Definições: «Baixa» deixa o painel aberto a 1 Hz")
            // «Só ícone», da 2.0, passa a «Só bateria» e fica escrito assim.
            check(defaults.string(forKey: AppSettings.barModeKey) == "battery",
                  "Definições: «icon» da 2.0 fica «battery»")
            check(bar?.content == (hasBattery ? .battery : .watts),
                  "Definições: «Só bateria» mostra a bateria sozinha (\(self.barLength) pt)")
            defaults.set("normal", forKey: AppSettings.sampleRateKey)
            defaults.set("batteryWatts", forKey: AppSettings.barModeKey)
        }
        after(navigated + 5.4) {
            let bar = self.shownBar
            let hasBattery = self.monitor?.snapshot.battery.isPresent == true
            check(self.monitor?.fastHz == 2, "Definições: «Normal» põe o painel aberto a 2 Hz")
            check(bar?.content == (hasBattery ? .batteryWatts : .watts)
                  && self.barLength == MenuBarIcon.itemLength(for: bar?.content ?? .watts) && self.barLength <= 72,
                  "Definições: «Bateria e watts» mostra «\(bar?.wattsText() ?? "")» ao lado da bateria (\(self.barLength) pt)")
            defaults.set("flowWatts", forKey: AppSettings.barModeKey)
        }
        after(navigated + 5.6) {
            let bar = self.shownBar
            check(bar?.content == .flowWatts && self.barLength == MenuBarIcon.itemLength(for: .flowWatts),
                  "Definições: «Ícone e watts» mostra o ícone da app e «\(bar?.wattsText() ?? "")» (\(self.barLength) pt)")
            if let savedRate { defaults.set(savedRate, forKey: AppSettings.sampleRateKey) } else { defaults.removeObject(forKey: AppSettings.sampleRateKey) }
            if let savedMode { defaults.set(savedMode, forKey: AppSettings.barModeKey) } else { defaults.removeObject(forKey: AppSettings.barModeKey) }
        }
        // Primeiro arranque: o cartão aparece, «Percebi» (Return) grava
        // `pf.firstRunDone`, e reaberto o painel já não o tem.
        // A mudança da preferência chega à vista pelo `@AppStorage`, às vezes
        // mais de 0,6 s depois (medido na Fase 10): o cartão tem 2 s para aparecer.
        after(navigated + 5.8) {
            act("volta ao nível 1; pf.firstRunDone = falso")
            self.navigation?.pop(animated: false, reduceMotion: true)
            defaults.set(false, forKey: AppSettings.firstRunDoneKey)
        }
        after(navigated + 7.8) {
            check(FirstRunCard.shownCount == 1, "primeiro arranque: o cartão aparece (\(FirstRunCard.shownCount) à vista)")
            act("tecla Return")
            self.sendKey("\r", code: 36)
        }
        after(navigated + 8.4) {
            check(AppSettings.firstRunDone(), "«Percebi» (Return) grava pf.firstRunDone")
            check(FirstRunCard.lastDismissal == false,
                  "«Percebi» pelo Return fecha o cartão sem animar (D7b; \(FirstRunCard.lastDismissal.map { $0 ? "animou" : "não animou" } ?? "não fechou"))")
            check(FirstRunCard.shownCount == 0, "depois de «Percebi» o cartão sai")
            self.closePanel()
        }
        after(navigated + 8.8) { self.holdPanel() }
        after(navigated + 9.4) {
            check(self.popover?.isShown == true && FirstRunCard.shownCount == 0,
                  "reaberto, o cartão não volta")
            // Abrir com o rato não acende o anel de foco em nenhum botão: o
            // primeiro Tab é que o leva ao primeiro controlo.
            let responder = self.popover?.contentViewController?.view.window?.firstResponder
            check(!PanelFocus.isVisibleStop(responder),
                  "ao abrir, nenhum controlo com o anel de foco (\(PanelFocus.describe(responder)))")
        }

        // Teclado (Fase 10): cada paragem do Tab é uma vista que se vê, no
        // nível 1 e no nível 2. Um botão escondido de atalho (⌘1, Esc…) que
        // apanhe o foco deixa o anel sem sítio onde se desenhar.
        var stops: [String] = []
        func walk(_ label: String, tabs: Int, at start: TimeInterval) {
            for step in 0..<tabs {
                after(start + Double(step) * 0.2) { self.sendKey("\t", code: 48) }
                after(start + Double(step) * 0.2 + 0.15) {
                    stops.append(PanelFocus.describe(self.popover?.contentViewController?.view.window?.firstResponder))
                }
            }
            after(start + Double(tabs) * 0.2 + 0.05) {
                let hidden = stops.filter { $0.contains("INVISÍVEL") || $0 == "nenhum" }
                check(hidden.isEmpty, "teclado, \(label): \(tabs) Tab sem paragens invisíveis (\(hidden.count) de \(tabs))")
                print("          " + stops.joined(separator: " → "))
                stops = []
            }
        }
        if let path = panelPNG {
            after(navigated + 9.5) {
                print("  Aparência: \(NSApp.effectiveAppearance.name.rawValue); aumentar contraste \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast), reduzir transparência \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)")
                self.renderPanel(to: path)
            }
        }
        // ⌘2 e ⌘1 escolhem o período sem foco nenhum (os botões deles saíram do Tab).
        let savedPeriod = defaults.object(forKey: "pf.historyPeriod")
        after(navigated + 9.55) { self.sendKey("2", code: 19, modifiers: .command) }
        after(navigated + 9.58) {
            check(defaults.string(forKey: "pf.historyPeriod") == HistoryPeriod.oneHour.rawValue,
                  "⌘2 escolhe «1 h» no histórico")
            self.sendKey("1", code: 18, modifiers: .command)
        }
        after(navigated + 9.59) {
            check(defaults.string(forKey: "pf.historyPeriod") == HistoryPeriod.twoMinutes.rawValue,
                  "⌘1 escolhe «2 min» no histórico")
            if let savedPeriod { defaults.set(savedPeriod, forKey: "pf.historyPeriod") } else { defaults.removeObject(forKey: "pf.historyPeriod") }
        }
        walk("nível 1", tabs: 8, at: navigated + 9.6)
        after(navigated + 11.4) { self.navigation?.push(.battery, reduceMotion: true) }
        walk("bateria", tabs: 4, at: navigated + 11.9)
        after(navigated + 13.0) { self.navigation?.pop(animated: false, reduceMotion: true) }

        after(navigated + 13.2) {
            self.closePanel()
        }
        let closed = navigated + 13.9
        after(closed) {
            wakeups = 0
            cpuAtStart = Self.cpuSeconds()
            windowStart = Date()
        }
        after(closed + Self.closedWindow) {
            let elapsed = Date().timeIntervalSince(windowStart)
            let cpu = (Self.cpuSeconds() - cpuAtStart) / elapsed * 100

            check(self.popover?.isShown == false, "o painel fecha por código")
            check(self.popover?.contentViewController == nil,
                  "fechado: o conteúdo do painel deixou de existir")
            check(self.monitor?.isSamplingFast == false, "fechado: leituras rápidas paradas (1 Hz)")
            check(!self.apps.isSampling, "fechado: o amostrador por app parado")
            check(cpu <= Self.closedBudget,
                  String(format: "fechado: %.2f %% de CPU (máximo %.0f %%), %.0f despertares/s",
                         cpu, Self.closedBudget, Double(wakeups) / elapsed))

            if let savedFirstRun { defaults.set(savedFirstRun, forKey: AppSettings.firstRunDoneKey) } else { defaults.removeObject(forKey: AppSettings.firstRunDoneKey) }
            print(failures == 0 ? "Painel: tudo certo." : "Painel: \(failures) falha(s).")
            exit(failures == 0 ? 0 : 1)
        }
        Self.runInOrder(steps)
    }

    /// Corre os passos por ordem de tempo (os do mesmo instante pela ordem em
    /// que entraram). Cada um espera, a partir do fim do anterior, a diferença
    /// entre os dois tempos, num temporizador sem tolerância.
    private static func runInOrder(_ steps: [(at: TimeInterval, work: @MainActor () -> Void)]) {
        let ordered = steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
        func run(_ index: Int, after previous: TimeInterval) {
            guard index < ordered.count else { return }
            let step = ordered[index]
            let timer = Timer(timeInterval: max(0, step.at - previous), repeats: false) { _ in
                MainActor.assumeIsolated {
                    step.work()
                    run(index + 1, after: step.at)
                }
            }
            timer.tolerance = 0
            RunLoop.main.add(timer, forMode: .common)
        }
        run(0, after: 0)
    }

    /// Desenha o painel aberto a partir da árvore de camadas da janela do
    /// popover (com o material de fundo), sem capturar o ecrã.
    private func renderPanel(to path: String) {
        guard let window = popover?.contentViewController?.view.window,
              let frameView = window.contentView?.superview, let layer = frameView.layer else { return }
        let scale = window.backingScaleFactor, size = frameView.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        context.cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: context.cgContext)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("  Painel desenhado em \(path)")
    }

    /// Uma tecla premida na janela do painel, como se viesse do teclado.
    ///
    /// Entra na fila de eventos (`postEvent`), como na sonda: só assim a app a
    /// recebe como `NSApp.currentEvent` e a reconhece como tecla. Por
    /// `sendEvent`, o Return fechava o cartão pelo caminho animado do clique.
    private func sendKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        guard let window = popover?.contentViewController?.view.window else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil,
                                            characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    /// O que os passos do `--panel-check` leem, numa linha.
    var traceState: String {
        let report = apps.report
        let dismissal = FirstRunCard.lastDismissal.map { $0 ? "animado" : "sem animação" } ?? "—"
        return "rota \(navigation.map { "\($0.route)" } ?? "—") · painel \(popover?.isShown == true ? "aberto" : "fechado")"
            + " · amostrador \(apps.isSampling ? "ligado" : "parado")"
            + " · média \(report.measuredAt == nil ? "nenhuma" : "\(report.apps.count) apps")"
            + " · cartões \(FirstRunCard.shownCount) · firstRunDone \(AppSettings.firstRunDone())"
            + " · último «Percebi» \(dismissal)"
    }

    /// Em que ponto vai o tracejado de cada aresta neste instante, lido da
    /// camada que o Core Animation está a apresentar.
    private func particlePhases() -> [CGFloat] {
        guard let root = popover?.contentViewController?.view else { return [] }
        return Self.particleHosts(in: root).flatMap(\.particlePhases)
    }

    private static func particleHosts(in view: NSView) -> [FlowLayerHost] {
        var found = view.subviews.flatMap { particleHosts(in: $0) }
        if let host = view as? FlowLayerHost { found.append(host) }
        return found
    }
}

/// O registo do `--panel-trace`: uma linha por ação, por verificação e por
/// mudança do que os passos leem, com os segundos desde o início do registo.
@MainActor
final class PanelTrace {
    private let handle: FileHandle?
    private let start = Date()
    private var timer: Timer?
    private var last = ""

    init(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func write(_ line: String) {
        let text = String(format: "%7.3f  ", Date().timeIntervalSince(start)) + line + "\n"
        handle?.write(Data(text.utf8))
    }

    /// Lê o estado de 25 em 25 ms e escreve-o quando muda.
    func watch(_ controller: StatusItemController) {
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self, weak controller] _ in
            MainActor.assumeIsolated {
                guard let self, let controller else { return }
                let state = controller.traceState
                if state != self.last {
                    self.last = state
                    self.write("vê: " + state)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
