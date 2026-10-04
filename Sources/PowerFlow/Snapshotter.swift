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
        /// A vista a desenhar: o nível 1, ou uma das do nível 2.
        var route: PanelRoute = .main
        /// Tira uma leitura ao estado, para ver o painel num Mac que não a dá.
        var missing: Missing?
        /// O período do histórico. `nil`: o que estiver guardado nas preferências.
        var period: HistoryPeriod?
        /// Histórico de 18 min, como nos primeiros minutos depois de instalar.
        var isFresh = false
        /// Desenha só a secção do histórico.
        var onlyHistory = false
        /// Desenha a janela de Definições, com as preferências guardadas.
        var onlySettings = false
        /// Desenha o painel como no primeiro arranque, com o cartão.
        var firstRun = false
        /// Onde pôr a leitura por ponteiro do histórico, de 0 (esquerda) a 1.
        var pointer: Double?
    }

    enum Missing: String, CaseIterable {
        case soc, mainrail
    }

    static let routes: [String: PanelRoute] = ["main": .main, "battery": .battery, "apps": .apps]

    static let appearances: [String: NSAppearance.Name] = [
        "light": .aqua,
        "dark": .darkAqua,
        "hc-light": .accessibilityHighContrastAqua,
        "hc-dark": .accessibilityHighContrastDarkAqua,
    ]

    /// Os dados de um estado do protótipo, os mesmos na imagem e no `--window --state`.
    static func fixture(_ state: PanelFixture, fresh: Bool = false)
        -> (PowerSnapshot, Bool, HistoryStore, AppsInput) {
        var snapshot = state.snapshot
        // Os números de bateria do protótipo, que o estado não traz.
        if snapshot.battery.isPresent {
            snapshot.battery.fullChargeCapacity = 4860
            snapshot.battery.designCapacity = 6075
            snapshot.battery.cycleCount = 649
        }
        return (snapshot, state.sensorsAvailable, state.history(fresh: fresh, now: snapshot.timestamp),
                AppsInput(report: state.apps(at: snapshot.timestamp), systemAverage: snapshot.systemTotal))
    }

    static func render(to path: String, options: Options) {
        var snapshot: PowerSnapshot
        let sensorsAvailable: Bool
        let history: HistoryStore
        var apps = AppsInput()
        if let state = options.state {
            (snapshot, sensorsAvailable, history, apps) = fixture(state, fresh: options.isFresh)
        } else {
            let monitor = PowerMonitor()
            monitor.setFastSampling(true)
            let model = AppEnergyModel()
            if options.route == .apps { model.start(monitor: monitor) }

            // Deixar o histórico encher, senão o gráfico sai vazio.
            let deadline = Date().addingTimeInterval(options.warmUpSeconds)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            snapshot = monitor.snapshot
            sensorsAvailable = monitor.isAvailable
            history = monitor.history
            model.stop()
            apps = model.input
        }
        switch options.missing {
        case .soc:      snapshot.socPower = nil
        case .mainrail: snapshot.mainRailPower = nil
        case nil:       break
        }
        let content: AnyView
        if options.onlySettings {
            content = AnyView(SettingsView(hasBattery: snapshot.battery.isPresent))
        } else if options.onlyHistory {
            content = AnyView(HistorySection(store: history, now: snapshot.timestamp,
                                             forcedPeriod: options.period ?? .twoMinutes,
                                             pointerPosition: options.pointer)
                .padding(EdgeInsets(top: 10, leading: PFSpace.popoverMargin,
                                    bottom: PFSpace.m, trailing: PFSpace.popoverMargin))
                .frame(width: PanelContent.width))
        } else {
            content = AnyView(PanelScreen(
                route: options.route, snapshot: snapshot,
                panel: PanelState(snapshot: snapshot, sensorsAvailable: sensorsAvailable),
                history: history, apps: apps, open: { _ in }, back: {}, historyPeriod: options.period,
                firstRun: options.firstRun))
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
