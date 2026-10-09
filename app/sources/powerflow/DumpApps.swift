import AppKit
import PowerFlowCore

/// `PowerFlow --dump-apps [segundos] [--rusage v4]`: o amostrador por app sem
/// abrir o painel. Lê de 5 em 5 s, como a vista, e no fim escreve as linhas,
/// a conta com o total e quanto custou cada leitura.
@MainActor
enum DumpApps {
    static func run(seconds: Double, forcing method: AppEnergyMethod?) {
        setvbuf(stdout, nil, _IOLBF, 0)
        let reader = SystemProcessReader(forcing: method)
        let monitor = PowerMonitor()
        let sampler = AppEnergySampler(reader: reader)
        let format = PFFormat()

        print("método        : \(reader.method == .energy ? "ri_energy_nj (RUSAGE_INFO_V6)" : "tempo de CPU × SoC (RUSAGE_INFO_V4)")"
            + (method != nil ? " — forçado" : ""))
        print("v6 no sistema : \(SystemProcessReader.detectMethod() == .energy ? "sim" : "não")")
        print("responsável   : \(reader.hasResponsibility ? "sim" : "não (só a cadeia de pais)")")

        var costs: [Double] = []
        func sample() {
            let start = DispatchTime.now().uptimeNanoseconds
            sampler.sample(at: Date(), apps: AppEnergyModel.runningApps(), socPower: monitor.snapshot.socPower)
            costs.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        func wait(_ seconds: Double) {
            let until = Date().addingTimeInterval(seconds)
            while Date() < until { RunLoop.main.run(until: min(until, Date().addingTimeInterval(0.1))) }
        }

        sample()
        var elapsed = 0.0
        while elapsed + AppEnergyModel.interval <= seconds {
            wait(AppEnergyModel.interval)
            elapsed += AppEnergyModel.interval
            sample()
        }

        let total = proc_listallpids(nil, 0)
        print("processos     : \(sampler.readableCount) legíveis de \(total)")
        print(String(format: "custo/leitura : %.2f ms em média, %.2f ms no máximo (%d leituras)",
                     costs.reduce(0, +) / Double(costs.count), costs.max() ?? 0, costs.count))

        let report = sampler.report(at: Date())
        let average = report.measuredAt.flatMap { monitor.history.average(over: report.span, now: $0) }
        let copy = AppsCopy(report: report, systemAverage: average)
        print("janela        : \(format.seconds(Int(report.span.rounded()))) · SoC agora \(monitor.snapshot.socPower.map { format.watts($0) } ?? "—")")
        print("")
        for app in report.apps.prefix(10) {
            print(String(format: "  %8.3f W  %@%@", app.watts, app.name, app.isRunning ? "" : " (terminou)"))
        }
        print("")
        for row in copy.rows { print("  \(row.value.padding(toLength: 9, withPad: " ", startingAt: 0)) \(row.name)") }
        print("  \(copy.otherValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(copy.otherName)")
        print("  \(copy.total.padding(toLength: 9, withPad: " ", startingAt: 0)) \(copy.totalLabel)")

        let shown = report.apps.filter { copy.order.contains($0.key) }.reduce(0) { $0 + $1.watts }
        let allApps = report.apps.reduce(0) { $0 + $1.watts }
        if let average {
            let scale = shown > average ? average / shown : 1
            let other = max(0, average - shown * scale)
            print(String(format: "\nconta         : %.3f (apps) + %.3f (resto) = %.3f W; total %.3f W; todas as apps %.3f W",
                         shown * scale, other, shown * scale + other, average, allApps))
        }
    }
}
