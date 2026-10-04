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
    /// O trinco de instância única, guardado enquanto a app correr.
    private static var instanceLock: InstanceLock?

    static func main() {
        let arguments = CommandLine.arguments

        if arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        if arguments.contains("--dump-history") {
            // O que está guardado das últimas 24 h, sem abrir a app.
            let url = HistoryStore.defaultFileURL
            let store = HistoryStore(fileURL: url)
            let series = store.series(for: .day)
            let format = PFFormat()
            print("ficheiro   : \(url.path)\(FileManager.default.fileExists(atPath: url.path) ? "" : " (não existe)")")
            print("pontos     : \(store.points(.day).count) fechados, \(series.samples.count) à vista em 24 h")
            print("cobertura  : \(format.duration(minutes: Int(store.coverage() / 60)))")
            print("lacunas    : \(series.gaps.count)")
            if let first = series.samples.first, let last = series.samples.last {
                print("primeiro   : \(format.clock(first.time)) · \(format.watts(first.system))")
                print("último     : \(format.clock(last.time)) · \(format.watts(last.system))")
            }
            print("24 h       : \(store.isAvailable(.day) ? "disponível" : "ainda não (pede 1 h de dados)")")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--dump-apps") {
            let seconds = index + 1 < arguments.count ? Double(arguments[index + 1]) ?? 16 : 16
            let forced: AppEnergyMethod? = arguments.contains("--rusage") && arguments.contains("v4") ? .cpuTime : nil
            MainActor.assumeIsolated { DumpApps.run(seconds: seconds, forcing: forced) }
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
            func value(after flag: String) -> String? {
                guard let at = arguments.firstIndex(of: flag), at + 1 < arguments.count else { return nil }
                return arguments[at + 1]
            }

            var options = Snapshotter.Options()
            options.warmUpSeconds = index + 2 < arguments.count ? Double(arguments[index + 2]) ?? 6 : 6
            options.reduceMotion = arguments.contains("--reduce-motion")
            if let name = value(after: "--state") {
                guard let state = PanelFixture(rawValue: name) else {
                    print("Estado desconhecido: \(name). Estados: "
                        + PanelFixture.allCases.map(\.rawValue).joined(separator: ", "))
                    exit(2)
                }
                options.state = state
            }
            if let name = value(after: "--appearance") {
                guard let appearance = Snapshotter.appearances[name] else {
                    print("Aparência desconhecida: \(name). Aparências: "
                        + Snapshotter.appearances.keys.sorted().joined(separator: ", "))
                    exit(2)
                }
                options.appearance = appearance
            }
            if value(after: "--view") == "history" {
                options.onlyHistory = true
            } else if let name = value(after: "--view") {
                guard let route = Snapshotter.routes[name] else {
                    print("Vista desconhecida: \(name). Vistas: "
                        + (Snapshotter.routes.keys + ["history"]).sorted().joined(separator: ", "))
                    exit(2)
                }
                options.route = route
            }
            options.isFresh = arguments.contains("--fresh")
            options.pointer = value(after: "--pointer").flatMap(Double.init)
            if let name = value(after: "--period") {
                guard let period = HistoryPeriod(rawValue: name) else {
                    print("Período desconhecido: \(name). Períodos: "
                        + HistoryPeriod.allCases.map(\.rawValue).joined(separator: ", "))
                    exit(2)
                }
                options.period = period
            }
            if let name = value(after: "--without") {
                guard let missing = Snapshotter.Missing(rawValue: name) else {
                    print("Leitura desconhecida: \(name). Leituras: "
                        + Snapshotter.Missing.allCases.map(\.rawValue).joined(separator: ", "))
                    exit(2)
                }
                options.missing = missing
            }
            MainActor.assumeIsolated { Snapshotter.render(to: path, options: options) }
            exit(0)
        }

        if let index = arguments.firstIndex(of: "--watch") {
            let seconds = index + 1 < arguments.count ? Int(arguments[index + 1]) ?? 20 : 20
            let fast = !arguments.contains("--closed")
            MainActor.assumeIsolated { Watch.run(seconds: seconds, fast: fast) }
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

        let isDiagnose = arguments.contains("--diagnose")
        let isPanelCheck = arguments.contains("--panel-check")
        let wantsClose = arguments.contains("--close-panel")

        // Daqui para baixo é a app da barra de menus, e só pode haver uma.
        // O `--diagnose` fica de fora: cria um item durante 2 s e sai.
        if !isDiagnose {
            switch InstanceLock.acquire(at: InstanceLock.defaultURL) {
            case .acquired(let lock):
                instanceLock = lock
            case .heldByAnother:
                if isPanelCheck {
                    print("Já há uma instância a correr. Fecha-a antes do --panel-check.")
                    exit(2)
                }
                // A segunda abertura ativa a primeira e termina.
                if wantsClose {
                    RemoteCommand.closePanel.post()
                } else if arguments.contains("--open-panel") {
                    (arguments.contains("apps") ? RemoteCommand.holdApps : RemoteCommand.holdPanel).post()
                } else {
                    RemoteCommand.showPanel.post()
                }
                exit(0)
            case .unavailable:
                break
            }
        }
        if wantsClose {
            print("Não há nenhuma instância a correr.")
            exit(1)
        }

        var openPanelAfter: TimeInterval?
        if let index = arguments.firstIndex(of: "--open-panel") {
            // Aos 2 s o item ainda não está na barra e o painel não abre.
            openPanelAfter = index + 1 < arguments.count
                ? Double(arguments[index + 1]) ?? 5 : 5
        }

        MainActor.assumeIsolated {
            let delegate = StatusItemController()
            delegate.diagnoseAndExit = isDiagnose
            delegate.checkPanelAndExit = isPanelCheck
            delegate.openPanelAfter = openPanelAfter
            delegate.openAppsOnOpen = arguments.contains("--view") && arguments.contains("apps")
            delegate.forceReduceMotion = arguments.contains("--reduce-motion")
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
