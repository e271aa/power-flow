import AppKit
import Foundation
import PowerFlowCore

/// Ponto de entrada.
///
/// Tem de ser um `@main` verdadeiro e este ficheiro não se pode chamar
/// `main.swift`, senão o compilador trata o conteúdo como código de topo e
/// recusa o atributo.
@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        if arguments.contains("--dump-keys") {
            Diagnostics.dumpAllPowerKeys()
            exit(0)
        }
        if arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        if let index = arguments.firstIndex(of: "--icon-preview") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : "icone.png"
            MainActor.assumeIsolated { IconPreview.render(to: path) }
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--snapshot") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : "powerflow.png"
            let warmUp = index + 2 < arguments.count ? Double(arguments[index + 2]) ?? 6 : 6
            MainActor.assumeIsolated { Snapshotter.render(to: path, warmUpSeconds: warmUp) }
            exit(0)
        }

        if let index = arguments.firstIndex(of: "--watch") {
            let seconds = index + 1 < arguments.count ? Int(arguments[index + 1]) ?? 20 : 20
            MainActor.assumeIsolated { Watch.run(seconds: seconds) }
            exit(0)
        }

        let app = NSApplication.shared

        // Janela normal: recurso para quando o item da barra não aparece.
        if arguments.contains("--window") {
            MainActor.assumeIsolated {
                let delegate = WindowModeDelegate()
                app.delegate = delegate
                app.setActivationPolicy(.regular)
                app.run()
            }
            return
        }

        MainActor.assumeIsolated {
            let delegate = StatusItemController()
            delegate.diagnoseAndExit = arguments.contains("--diagnose")
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
