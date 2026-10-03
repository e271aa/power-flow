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
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var monitor: PowerMonitor?
    private var cancellable: AnyCancellable?

    /// Quando ligado, relata o estado do item e sai. Serve o `--diagnose`.
    var diagnoseAndExit = false

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
        let hosting = NSHostingController(rootView: ContentView(monitor: monitor))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        self.popover = popover

        cancellable = monitor.$snapshot.sink { [weak self] snapshot in
            self?.refresh(with: snapshot)
        }
        refresh(with: monitor.snapshot)

        if diagnoseAndExit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
        button.image = MenuBarIcon.image(pluggedIn: snapshot.source == .adapter)

        // Sem espaço entre o número e a unidade, e sem casas decimais: numa
        // barra de menus disputada, cada ponto de largura conta.
        let watts = snapshot.systemTotal ?? 0
        button.title = String(format: "%.0fW", watts)
        button.toolTip = "PowerFlow — \(String(format: "%.1f W", watts)) consumidos"
    }

    @objc private func togglePanel() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Relatório do estado do item, para diagnosticar sem ver o ecrã.
    func diagnose() {
        guard let item = statusItem else { print("  item: NÃO CRIADO"); return }
        print("  item criado      : sim")
        print("  isVisible        : \(item.isVisible)")
        print("  largura do botão : \(item.button?.frame.width ?? -1) pt")
        print("  título           : \"\(item.button?.title ?? "")\"")
        print("  tem imagem       : \(item.button?.image != nil)")
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
