import AppKit
import Combine
import PowerFlowCore
import SwiftUI

/// Gere o item da barra de menus e o painel que ele abre.
///
/// Usa `NSStatusItem` do AppKit em vez do `MenuBarExtra` do SwiftUI. O
/// `MenuBarExtra` não chega a produzir um item visível quando a app é
/// construída contra o SDK das Command Line Tools (14.4) e corre num macOS
/// muito mais recente: o processo arranca, não regista erro nenhum, e
/// simplesmente não aparece nada. O `NSStatusItem` é anterior ao SwiftUI,
/// não depende dessa ponte e funciona nas mesmas condições.
///
/// O conteúdo do painel só existe enquanto ele está aberto. Esconder não
/// chega: um painel escondido continua a ser avaliado a cada leitura, e as
/// animações que tiver continuam a correr.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private(set) var popover: NSPopover?
    private(set) var monitor: PowerMonitor?
    private var cancellable: AnyCancellable?
    /// O `kill` (SIGTERM) sai pelo mesmo caminho que o «Sair».
    private var terminationSignal: TerminationSignal?
    private var shownPluggedIn: Bool?
    /// Onde o painel está. Novo a cada abertura: o painel abre sempre no nível 1.
    private(set) var navigation: PanelNavigation?
    /// A energia por app. Vive tanto como a app; só amostra com a vista Apps aberta.
    let apps = AppEnergyModel()

    /// Quando ligado, relata o estado do item e sai. Serve o `--diagnose`.
    var diagnoseAndExit = false
    /// Segundos depois do arranque em que o painel se abre sozinho. Serve o
    /// `--open-panel`, para medir a app sem ter de clicar no item.
    var openPanelAfter: TimeInterval?
    /// Quando ligado, abre e fecha o painel, verifica o que fica a correr
    /// em cada estado e sai. Serve o `--panel-check`.
    var checkPanelAndExit = false
    /// Trata o painel como se Reduzir Movimento estivesse ligado, sem mexer
    /// na definição do sistema. Serve o `--reduce-motion`, para medir.
    var forceReduceMotion = false
    /// Com o `--open-panel`, abre já na vista «Consumo por app».
    var openAppsOnOpen = false
    /// Escreve cada mudança do item com a hora, para medir o intervalo. Serve o `--log-title`.
    var logTitleChanges = false

    private var barMode = AppSettings.barMode()
    /// Segura os watts para mudarem no máximo de 2 em 2 s.
    private var readingThrottle = BarTitleThrottle()
    /// O que o item mostra. A imagem só se refaz quando isto muda.
    private(set) var shownBar: BarItem?
    private var defaultsObserver: NSObjectProtocol?

    /// Os alertas correm sobre o instantâneo de 1 Hz, com o painel aberto ou fechado.
    private var alerts = AlertMonitor()
    private var alertSettings = AppSettings.alerts()
    /// Escreve cada alerta disparado. Serve para medir sem esperar pelo Centro de Notificações.
    var logAlerts = false
    /// `--panel-check --panel-png <ficheiro>`: desenha o painel aberto num PNG.
    var panelPNG: String?
    /// `--panel-check --panel-trace <ficheiro>`: o registo do que cada passo viu.
    var panelTrace: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = PowerMonitor(persistsHistory: true)
        self.monitor = monitor
        terminationSignal = TerminationSignal { NSApp.terminate(nil) }

        // Comprimento fixo: o item só muda de largura quando muda o modo.
        let content = BarItem.content(mode: barMode, hasBattery: monitor.snapshot.battery.isPresent)
        let item = NSStatusBar.system.statusItem(withLength: MenuBarIcon.itemLength(for: content))
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // O clique direito também chega à ação, para abrir o menu.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // A bateria e os watts são uma só imagem, sem título.
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel(L10n.string("ax_bar_label"))
        item.button?.setAccessibilityHelp(L10n.string("ax_bar_help"))
        statusItem = item

        SettingsWindow.shared.monitor = monitor
        installMainMenu()
        AlertNotifier.shared.install { [weak self] in self?.showPanel() }
        // As Definições mudam `UserDefaults`; o item e o monitor seguem-nas.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        self.popover = popover

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(showPanel),
                           name: RemoteCommand.showPanel.name, object: nil,
                           suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(holdPanel),
                           name: RemoteCommand.holdPanel.name, object: nil,
                           suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(holdApps),
                           name: RemoteCommand.holdApps.name, object: nil,
                           suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(closePanel),
                           name: RemoteCommand.closePanel.name, object: nil,
                           suspensionBehavior: .deliverImmediately)

        cancellable = monitor.$snapshot.sink { [weak self] snapshot in
            self?.refresh(with: snapshot)
            self?.checkAlerts(snapshot)
        }
        refresh(with: monitor.snapshot)

        if let openPanelAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + openPanelAfter) {
                MainActor.assumeIsolated {
                    if self.openAppsOnOpen { self.holdApps() } else { self.holdPanel() }
                    print("painel aberto: \(self.popover?.isShown ?? false)")
                }
            }
        }
        if checkPanelAndExit {
            runPanelCheck()
        }

        // Primeiro arranque: o painel abre sozinho, com o cartão, 0,5 s depois.
        if !AppSettings.firstRunDone() && openPanelAfter == nil && !checkPanelAndExit && !diagnoseAndExit {
            openFirstRunPanel(after: 0.5)
        }

        if diagnoseAndExit {
            // Aos 2 s o sistema ainda não pôs o item na barra, e o relatório
            // saía com a janela dele por colocar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                MainActor.assumeIsolated {
                    print("== Estado do item da barra de menus ==")
                    self.diagnose()
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Ao sair, o intervalo de 10 min que ia a meio fica guardado. Também
    /// com um SIGTERM, que chega aqui pelo `terminationSignal`.
    func applicationWillTerminate(_ notification: Notification) {
        monitor?.saveHistory()
    }

    /// Aplica as Definições que o item e o monitor leem: o modo da barra e a
    /// frequência de amostragem. O sistema avisa de qualquer mudança em
    /// `UserDefaults`, por isso só se mexe no que mudou.
    private func applySettings() {
        guard let monitor else { return }
        monitor.setSampleRate(AppSettings.sampleRate())

        // Ligar um alerta é quando se pede a autorização de notificações.
        let alerts = AppSettings.alerts()
        if AlertKind.allCases.contains(where: { alerts.isEnabled($0) && !alertSettings.isEnabled($0) }) {
            AlertNotifier.shared.requestAuthorizationIfNeeded()
        }
        alertSettings = alerts

        let mode = AppSettings.barMode()
        if mode != barMode {
            barMode = mode
            // É uma ordem do utilizador: os watts não esperam pelos 2 s.
            refresh(with: monitor.snapshot, immediately: true)
        }
    }

    private func refresh(with snapshot: PowerSnapshot, immediately: Bool = false) {
        guard let item = statusItem, let button = item.button, let monitor else { return }

        var bar = BarItem(mode: barMode, snapshot: snapshot, sensorsAvailable: monitor.isAvailable)
        // A percentagem e o raio passam logo; os watts seguram 2 s.
        bar.reading = readingThrottle.shown(for: bar.reading, at: Date(), immediately: immediately)

        // Só se mexe no botão quando o que ele mostra muda. Atribuir a mesma
        // imagem obriga a barra a redesenhar-se na mesma.
        guard bar != shownBar else { return }
        let length = MenuBarIcon.itemLength(for: bar.content)
        if item.length != length { item.length = length }
        button.image = MenuBarIcon.image(bar)
        button.toolTip = bar.toolTip()
        button.setAccessibilityValue(bar.accessibilityValue())
        shownBar = bar
        if logTitleChanges {
            print(String(format: "%.3f item «%@» %d %%%@", Date().timeIntervalSince1970,
                         bar.wattsText(), bar.percent, bar.isCharging ? " a carregar" : ""))
            fflush(stdout)
        }
    }

    private func checkAlerts(_ snapshot: PowerSnapshot) {
        guard let monitor else { return }
        for event in alerts.update(snapshot: snapshot, sensorsAvailable: monitor.isAvailable,
                                   settings: alertSettings) {
            if logAlerts {
                print(String(format: "%.3f alerta %@: «%@» «%@»", Date().timeIntervalSince1970,
                             event.kind.rawValue, event.title, event.body))
                fflush(stdout)
            }
            AlertNotifier.shared.post(event)
        }
    }

    /// No arranque o item ainda não está na barra e o painel não abre (ver
    /// `openPanel`); tenta-se de meio em meio segundo, durante 10 s.
    private func openFirstRunPanel(after delay: TimeInterval, attempts: Int = 20) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !AppSettings.firstRunDone(), self.popover?.isShown == false else { return }
                self.showPanel()
                if self.popover?.isShown == true { print("primeiro arranque: painel aberto com o cartão") }
                if self.popover?.isShown != true, attempts > 1 {
                    self.openFirstRunPanel(after: 0.5, attempts: attempts - 1)
                }
            }
        }
    }

    /// O comprimento do item na barra, para o `--panel-check`.
    var barLength: CGFloat { statusItem?.length ?? 0 }

    // MARK: - Menus

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    /// O menu de clique direito: abrir, definições, sair.
    private func showContextMenu() {
        if popover?.isShown == true { closePanel() }

        let menu = NSMenu()
        let open = menu.addItem(withTitle: L10n.string("m_open"), action: #selector(showPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L10n.string("m_settings"),
                                    action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L10n.string("m_quit"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        // Com o menu atribuído, o clique no botão abre-o (à maneira do sistema,
        // com o item realçado). Tira-se logo a seguir, para o clique esquerdo
        // voltar a abrir o painel.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    /// O menu principal da app. Uma app só da barra não o mostra, mas é ele que
    /// dá ⌘Q e ⌘, com o painel ou as Definições à frente, sem nenhum menu aberto.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)

        let menu = NSMenu()
        menu.addItem(withTitle: L10n.string("m_about"),
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            .target = NSApp
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string("m_settings"), action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.string("m_quit"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
        appItem.submenu = menu
        NSApp.mainMenu = main
    }

    @objc func showSettings() {
        SettingsWindow.shared.show()
    }

    /// Abrir a app outra vez com ela já a correr mostra o painel.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    @objc private func togglePanel() {
        if popover?.isShown == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    /// Abre o painel como um clique no item: fecha-se com um clique fora.
    @objc func showPanel() {
        openPanel(pinned: false)
    }

    /// Abre o painel e deixa-o ficar até ser fechado por código ou com um
    /// clique no item. É assim que se mede o painel aberto.
    @objc func holdPanel() {
        openPanel(pinned: true)
    }

    /// Abre o painel fixo, já na vista «Consumo por app».
    @objc func holdApps() {
        openPanel(pinned: true)
        navigation?.push(.apps, reduceMotion: true)
    }

    private func openPanel(pinned: Bool) {
        guard let popover, let monitor, let button = statusItem?.button else { return }
        popover.behavior = pinned ? .applicationDefined : .transient
        guard !popover.isShown else { return }

        monitor.setFastSampling(true)
        let navigation = PanelNavigation()
        self.navigation = navigation
        let hosting = NSHostingController(rootView: PanelView(monitor: monitor, navigation: navigation, apps: apps)
            .environment(\.forceReduceMotion, forceReduceMotion))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hosting.view.window?.makeKey()
        // A janela ativa dava o foco ao primeiro controlo, o «…», e o anel azul
        // ficava aceso a cada abertura. Sem foco nenhum, o painel continua a
        // responder ao teclado e o primeiro Tab leva o foco ao primeiro controlo.
        hosting.view.window?.makeFirstResponder(nil)

        // Se o item ainda não estiver na barra, o painel não chega a abrir
        // e o delegado não é avisado de fecho nenhum.
        if !popover.isShown { releasePanel() }
    }

    @objc func closePanel() {
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        releasePanel()
    }

    /// Deita fora o conteúdo do painel e volta ao ritmo de 1 Hz.
    private func releasePanel() {
        popover?.contentViewController = nil
        navigation = nil
        apps.stop()
        monitor?.setFastSampling(false)
    }

    /// Relatório do estado do item, para diagnosticar sem ver o ecrã.
    func diagnose() {
        guard let item = statusItem else { print("  item: NÃO CRIADO"); return }
        print("  item criado      : sim")
        print("  isVisible        : \(item.isVisible)")
        print("  largura do botão : \(item.button?.frame.width ?? -1) pt (comprimento \(item.length) pt)")
        print("  mostra           : \(shownBar.map { "\($0.content) · «\($0.wattsText())» · \($0.percent) %\($0.isCharging ? " a carregar" : "")" } ?? "nada")")
        print("  tem imagem       : \(item.button?.image != nil) (\(item.button?.image.map { "\($0.size.width) × \($0.size.height)" } ?? "—") pt)")
        // O AppKit dá o item como visível mesmo quando a barra não o mostra
        // (escondido atrás do notch ou por uma app que gere a barra). Onde
        // está a janela dele e se está tapada dizem mais.
        if let window = item.button?.window {
            let frame = window.frame
            print("  posição no ecrã  : x \(Int(frame.minX)) a \(Int(frame.maxX)), y \(Int(frame.minY))")
            print("  janela à vista   : \(window.occlusionState.contains(.visible) ? "sim" : "não")")
            print("  janela ordenada  : \(window.isVisible ? "sim" : "não") (nível \(window.level.rawValue), classe \(type(of: window)))")
            print("  no ecrã          : \(window.screen != nil ? "sim" : "não")")
        } else {
            print("  janela do item   : NÃO EXISTE")
        }
        if let screen = NSScreen.main {
            print("  ecrã             : \(Int(screen.frame.width)) x \(Int(screen.frame.height)) pt")
            if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0 {
                print("  notch            : sim (\(Int(screen.safeAreaInsets.top)) pt)")
            } else {
                print("  notch            : não")
            }
        }
    }
}
