import AppKit
import PowerFlowCore
import SwiftUI

/// Abre a interface numa janela normal, com `--window`.
///
/// É a rede de segurança: se o item da barra de menus não aparecer — barra
/// cheia, item empurrado para fora pelo notch, ou outro conflito — a app
/// continua a ser alcançável por aqui.
///
/// Com `--state`, a janela mostra um dos nove estados do protótipo, viva (os
/// botões funcionam), para ler a árvore de acessibilidade e andar por Tab
/// estado a estado. `--view battery|apps` começa no nível 2, `--view settings`
/// abre só as Definições, `--first-run` mostra o cartão de primeiro arranque.
@MainActor
final class WindowModeDelegate: NSObject, NSApplicationDelegate {
    struct Options {
        var state: PanelFixture?
        var route: PanelRoute = .main
        var firstRun = false
        var settings = false
        /// `--focus-walk <pasta> <n>`: avança n vezes por Tab e desenha a janela
        /// num PNG antes de cada passo, para ver o anel de foco sem capturar o ecrã.
        var focusWalk: (folder: String, steps: Int)?
        /// `--motion-probe <pasta>`: mede o movimento do painel (`MotionProbe`).
        var motionProbe: String?
        /// `--growth-probe [s]`: confere que nada se acumula com o painel a receber leituras (`GrowthProbe`).
        var growthProbe: Double?
        var reduceMotion = false
    }

    var options = Options()
    private var window: NSWindow?
    private var monitor: PowerMonitor?
    private var probe: MotionProbe?
    private var growthProbe: GrowthProbe?

    func applicationDidFinishLaunching(_ notification: Notification) {
        defer {
            NSApp.activate(ignoringOtherApps: true)
            if let walk = options.focusWalk {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.walkFocus(walk, step: 0) }
            }
        }

        if options.settings {
            SettingsWindow.shared.hasBatteryOverride = options.state.map { Snapshotter.fixture($0).0.battery.isPresent }
            SettingsWindow.shared.show()
            return
        }

        if let folder = options.motionProbe {
            startProbe(folder)
            return
        }

        if let seconds = options.growthProbe {
            startGrowthProbe(seconds)
            return
        }

        let root: AnyView
        if let state = options.state {
            let (snapshot, sensorsAvailable, history, apps) = Snapshotter.fixture(state)
            root = AnyView(FixturePanel(snapshot: snapshot, sensorsAvailable: sensorsAvailable,
                                        history: history, apps: apps, route: options.route,
                                        firstRun: options.firstRun))
        } else {
            let monitor = PowerMonitor()
            // A janela é o painel, e está sempre à vista.
            monitor.setFastSampling(true)
            self.monitor = monitor
            root = AnyView(PanelView(monitor: monitor, navigation: PanelNavigation(), apps: AppEnergyModel()))
        }

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = .preferredContentSize

        let window = NSWindow(contentViewController: hosting)
        window.title = "PowerFlow"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func startProbe(_ folder: String) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let probe = MotionProbe(folder: folder, window: window)
        probe.forceReduceMotion = options.reduceMotion
        let hosting = NSHostingController(rootView: ProbePanel(feed: probe.feed, navigation: probe.navigation)
            .environment(\.forceReduceMotion, options.reduceMotion))
        hosting.sizingOptions = .preferredContentSize
        window.contentViewController = hosting
        window.title = "PowerFlow · sonda"
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.probe = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { probe.run() }
    }

    private func startGrowthProbe(_ seconds: Double) {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let probe = GrowthProbe(seconds: seconds, window: window)
        let hosting = NSHostingController(rootView: ProbePanel(feed: probe.feed, navigation: probe.navigation))
        hosting.sizingOptions = .preferredContentSize
        window.contentViewController = hosting
        window.title = "PowerFlow · sonda"
        // Por cima das outras janelas e em todos os Espaços, também sobre uma
        // app em ecrã inteiro: tapada, não se redesenhava.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        growthProbe = probe
        probe.run()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func walkFocus(_ walk: (folder: String, steps: Int), step: Int) {
        guard let window = window ?? NSApp.windows.first(where: \.isVisible),
              let view = window.contentView else { return }
        window.makeKey()
        // O anel de foco é uma camada à parte: o `cacheDisplay` não o desenha.
        // Desenha-se a árvore de camadas da moldura da janela.
        let frameView = view.superview ?? view
        if let layer = frameView.layer {
            let scale = window.backingScaleFactor
            let size = frameView.bounds.size
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                          pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
               let context = NSGraphicsContext(bitmapImageRep: rep) {
                context.cgContext.scaleBy(x: scale, y: scale)
                layer.render(in: context.cgContext)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(walk.folder)/foco-\(step).png"))
            }
        }
        print("\(step): \(PanelFocus.describe(window.firstResponder))")
        fflush(stdout)
        guard step < walk.steps else { NSApp.terminate(nil); return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let tab = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          characters: "\t", charactersIgnoringModifiers: "\t",
                                          isARepeat: false, keyCode: 48) {
                NSApp.postEvent(tab, atStart: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.walkFocus(walk, step: step + 1) }
    }
}

/// O painel com os dados de um estado do protótipo. Navega como o verdadeiro.
private struct FixturePanel: View {
    let snapshot: PowerSnapshot
    let sensorsAvailable: Bool
    let history: HistoryStore
    let apps: AppsInput
    let route: PanelRoute
    let firstRun: Bool

    @StateObject private var navigation = PanelNavigation()
    @State private var dismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PanelStack(navigation: navigation, reduceMotion: reduceMotion) { route in
            PanelScreen(route: route, snapshot: snapshot,
                        panel: PanelState(snapshot: snapshot, sensorsAvailable: sensorsAvailable),
                        history: history, apps: apps,
                        open: { navigation.push($0, reduceMotion: reduceMotion) },
                        back: { navigation.pop(animated: true, reduceMotion: reduceMotion) },
                        firstRun: firstRun && !dismissed,
                        dismissFirstRun: {
                            FirstRunCard.dismiss(navigation: navigation, reduceMotion: reduceMotion) {
                                dismissed = true
                            }
                        })
        }
        .background(PFColor.bg)
        .onAppear {
            if route != .main { navigation.push(route, reduceMotion: true) }
        }
    }
}

/// O que tem o foco do teclado, e se se vê.
@MainActor
enum PanelFocus {
    /// A moldura do respondedor, na janela. `nil` se não for uma vista.
    static func frame(of responder: NSResponder?) -> CGRect? {
        guard let view = responder as? NSView, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    /// Uma paragem do Tab tem de ser uma vista que se vê: com uma moldura de
    /// tamanho zero o anel de foco não tem onde se desenhar.
    static func isVisibleStop(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView, let frame = frame(of: responder) else { return false }
        return frame.width >= 4 && frame.height >= 4 && !view.isHiddenOrHasHiddenAncestor
            && opacity(of: view) > 0.05
    }

    /// A opacidade com que a vista chega ao ecrã: a dela e a de todas as camadas por cima.
    static func opacity(of view: NSView) -> Float {
        var value: Float = Float(view.alphaValue)
        var layer = view.layer
        while let current = layer {
            value *= current.opacity
            layer = current.superlayer
        }
        var ancestor = view.superview
        while let current = ancestor {
            value *= Float(current.alphaValue)
            ancestor = current.superview
        }
        return value
    }

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nenhum" }
        let name = String(describing: type(of: responder))
        guard let f = frame(of: responder) else { return name }
        let alpha = (responder as? NSView).map(opacity(of:)) ?? 1
        return String(format: "%@ %.0f×%.0f α%.2f%@", name, f.width, f.height, alpha,
                      isVisibleStop(responder) ? "" : " INVISÍVEL")
    }
}
