import AppKit
import PowerFlowCore
import SwiftUI

/// Abre a interface numa janela normal, com `--window`.
///
/// É a rede de segurança: se o item da barra de menus não aparecer — barra
/// cheia, item empurrado para fora pelo notch, ou outro conflito — a app
/// continua a ser alcançável por aqui.
@MainActor
final class WindowModeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var monitor: PowerMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = PowerMonitor()
        // A janela é o painel, e está sempre à vista.
        monitor.setFastSampling(true)
        self.monitor = monitor

        let hosting = NSHostingController(rootView: PanelView(monitor: monitor, navigation: PanelNavigation()))
        hosting.sizingOptions = .preferredContentSize

        let window = NSWindow(contentViewController: hosting)
        window.title = "PowerFlow"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
