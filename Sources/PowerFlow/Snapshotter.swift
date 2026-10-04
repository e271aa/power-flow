import AppKit
import PowerFlowCore
import SwiftUI

/// Renderiza a interface para um PNG, sem abrir janela nem capturar o ecrã.
///
/// Serve para verificar o aspeto do painel durante o desenvolvimento e para
/// juntar uma imagem a um relatório de problema: `PowerFlow --snapshot out.png`.
/// Com `--state` desenha um dos nove estados do protótipo em vez das leituras
/// deste Mac; com `--appearance`, noutra aparência que não a do sistema.
@MainActor
enum Snapshotter {
    struct Options {
        /// `nil`: as leituras verdadeiras, depois de `warmUpSeconds`.
        var state: PanelFixture?
        /// `nil`: a aparência do sistema.
        var appearance: NSAppearance.Name?
        var reduceMotion = false
        var warmUpSeconds: Double = 6
    }

    static let appearances: [String: NSAppearance.Name] = [
        "light": .aqua,
        "dark": .darkAqua,
        "hc-light": .accessibilityHighContrastAqua,
        "hc-dark": .accessibilityHighContrastDarkAqua,
    ]

    static func render(to path: String, options: Options) {
        let content: PanelContent
        if let state = options.state {
            content = PanelContent(snapshot: state.snapshot, panel: state.panel,
                                   samples: state.history)
        } else {
            let monitor = PowerMonitor()
            monitor.setFastSampling(true)

            // Deixar o histórico encher, senão o gráfico sai vazio.
            let deadline = Date().addingTimeInterval(options.warmUpSeconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            content = PanelContent(snapshot: monitor.snapshot, panel: monitor.panel,
                                   samples: monitor.history.recent(seconds: 120))
        }

        let appearance = options.appearance.flatMap { NSAppearance(named: $0) }
            ?? NSApplication.shared.effectiveAppearance

        PFColor.forcesIncreasedContrast = options.appearance == .accessibilityHighContrastAqua
            || options.appearance == .accessibilityHighContrastDarkAqua

        // O popover dá o material de fundo; numa imagem não há popover.
        let root = content
            .background(PFColor.bg)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.isStaticRender, true)
            .environment(\.forceReduceMotion, options.reduceMotion)

        // Uma vista do AppKit fora do ecrã, e não o `ImageRenderer`: só assim
        // as cores seguem a aparência pedida, alto contraste incluído, e os
        // controlos do sistema se desenham.
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.appearance = appearance
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        let scale = 2
        let size = hosting.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else {
            print("Falhou a renderização.")
            return
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("Falhou a renderização.")
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Imagem escrita: \(path) (\(Int(size.width)) × \(Int(size.height)) pt)")
        } catch {
            print("Falhou a escrita: \(error.localizedDescription)")
        }
    }
}
