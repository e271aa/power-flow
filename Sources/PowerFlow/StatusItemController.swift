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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = PowerMonitor()
        self.monitor = monitor

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.imagePosition = .imageLeading
        statusItem = item

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
        center.addObserver(self, selector: #selector(closePanel),
                           name: RemoteCommand.closePanel.name, object: nil,
                           suspensionBehavior: .deliverImmediately)

        cancellable = monitor.$snapshot.sink { [weak self] snapshot in
            self?.refresh(with: snapshot)
        }
        refresh(with: monitor.snapshot)

        if let openPanelAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + openPanelAfter) {
                MainActor.assumeIsolated {
                    self.holdPanel()
                    print("painel aberto: \(self.popover?.isShown ?? false)")
                }
            }
        }
        if checkPanelAndExit {
            runPanelCheck()
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

    private func refresh(with snapshot: PowerSnapshot) {
        guard let button = statusItem?.button else { return }

        // Só se mexe no botão quando o que ele mostra muda. Atribuir o mesmo
        // título ou a mesma imagem obriga a barra a redesenhar-se na mesma.
        let pluggedIn = snapshot.source == .adapter
        if pluggedIn != shownPluggedIn {
            button.image = MenuBarIcon.image(pluggedIn: pluggedIn)
            shownPluggedIn = pluggedIn
        }

        // Sem espaço entre o número e a unidade, e sem casas decimais: numa
        // barra de menus disputada, cada ponto de largura conta.
        let watts = snapshot.systemTotal ?? 0
        let title = PFFormat().wattsValue(watts, decimals: 0) + "W"
        if button.title != title { button.title = title }

        let toolTip = L10n.string("tt_status", PFFormat().watts(watts))
        if button.toolTip != toolTip { button.toolTip = toolTip }
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

    private func openPanel(pinned: Bool) {
        guard let popover, let monitor, let button = statusItem?.button else { return }
        popover.behavior = pinned ? .applicationDefined : .transient
        guard !popover.isShown else { return }

        monitor.setFastSampling(true)
        let hosting = NSHostingController(rootView: PanelView(monitor: monitor)
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
