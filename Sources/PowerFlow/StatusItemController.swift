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
    /// Escreve cada mudança do título com a hora, para medir o intervalo. Serve o `--log-title`.
    var logTitleChanges = false

    private var barMode = AppSettings.barMode()
    private var titleThrottle = BarTitleThrottle()
    private var shownIcon: MenuBarIcon.State?
    private var defaultsObserver: NSObjectProtocol?

    /// Os alertas correm sobre o instantâneo de 1 Hz, com o painel aberto ou fechado.
    private var alerts = AlertMonitor()
    private var alertSettings = AppSettings.alerts()
    /// Escreve cada alerta disparado. Serve para medir sem esperar pelo Centro de Notificações.
    var logAlerts = false
    /// `--panel-check --panel-png <ficheiro>`: desenha o painel aberto num PNG.
    var panelPNG: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = PowerMonitor(persistsHistory: true)
        self.monitor = monitor

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        // O clique direito também chega à ação, para abrir o menu.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Dígitos de largura fixa: o título não treme quando o número muda.
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        }
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

    /// Ao sair, o intervalo de 10 min que ia a meio fica guardado.
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
            // É uma ordem do utilizador: o título não espera pelos 2 s.
            refresh(with: monitor.snapshot, immediately: true)
        }
    }

    private func refresh(with snapshot: PowerSnapshot, immediately: Bool = false) {
        guard let button = statusItem?.button, let monitor else { return }

        // Só se mexe no botão quando o que ele mostra muda. Atribuir o mesmo
        // título ou a mesma imagem obriga a barra a redesenhar-se na mesma.
        let content = BarTitle.content(mode: barMode, hasBattery: snapshot.battery.isPresent)

        if barMode.showsIcon {
            let state: MenuBarIcon.State = !monitor.isAvailable ? .unavailable
                : snapshot.source == .adapter ? .pluggedIn : .onBattery
            if state != shownIcon {
                button.image = MenuBarIcon.image(state)
                shownIcon = state
            }
            let position: NSControl.ImagePosition = content == .empty ? .imageOnly : .imageLeading
            if button.imagePosition != position { button.imagePosition = position }
        } else if shownIcon != nil {
            button.image = nil
            button.imagePosition = .noImage
            shownIcon = nil
        }

        var title = ""
        if content == .empty {
            titleThrottle = BarTitleThrottle()
        } else {
            let wanted = BarTitle.text(content, snapshot: snapshot)
            title = titleThrottle.shown(for: wanted, at: Date(), immediately: immediately)
        }
        if button.title != title {
            button.title = title
            if logTitleChanges {
                print(String(format: "%.3f título «%@»", Date().timeIntervalSince1970, title))
                fflush(stdout)
            }
        }

        let toolTip = BarTitle.toolTip(snapshot: snapshot, sensorsAvailable: monitor.isAvailable)
        if button.toolTip != toolTip { button.toolTip = toolTip }
        // Sem imagem nem título o item não se anunciava a ninguém.
        button.setAccessibilityLabel("PowerFlow")
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

    /// O que o botão da barra mostra, para o `--panel-check`.
    var barButtonState: (hasImage: Bool, title: String) {
        (statusItem?.button?.image != nil, statusItem?.button?.title ?? "")
    }

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
        print("  largura do botão : \(item.button?.frame.width ?? -1) pt")
        print("  título           : \"\(item.button?.title ?? "")\"")
        print("  tem imagem       : \(item.button?.image != nil)")
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
