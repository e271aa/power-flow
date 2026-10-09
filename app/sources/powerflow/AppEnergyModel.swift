import AppKit
import PowerFlowCore

/// O amostrador de energia por app, ligado só enquanto a vista Apps está à vista.
///
/// Vive tanto como a app: a janela de 5 min sobrevive a fechar o painel, e
/// ao reabrir dentro dela a média sai logo da primeira leitura (os contadores
/// do kernel são acumulados). Parado, não tem temporizador nenhum.
@MainActor
final class AppEnergyModel: ObservableObject {
    @Published private(set) var report: AppEnergyReport

    let sampler: AppEnergySampler
    private weak var monitor: PowerMonitor?
    private var timer: Timer?
    private var firstTimer: Timer?

    /// A cadência do handoff.
    static let interval: TimeInterval = 5
    /// A primeira média, quando ainda não há nenhuma. Esperar 5 s com a vista
    /// vazia seria longo; 1 s chega para ordenar as apps.
    static let firstInterval: TimeInterval = 1

    var isSampling: Bool { timer != nil }

    init(reader: ProcessEnergyReading = SystemProcessReader()) {
        sampler = AppEnergySampler(reader: reader)
        report = .empty(method: reader.method)
    }

    /// O que a vista recebe: as médias das apps e a do sistema na mesma janela.
    var input: AppsInput {
        let average = report.measuredAt.flatMap { end in
            monitor?.history.average(over: max(report.span, 1), now: end)
        } ?? monitor?.snapshot.systemTotal
        return AppsInput(report: report, systemAverage: average)
    }

    func start(monitor: PowerMonitor) {
        guard timer == nil else { return }
        self.monitor = monitor
        sample()
        if report.measuredAt == nil {
            let first = Timer(timeInterval: Self.firstInterval, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(first, forMode: .common)
            firstTimer = first
        }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstTimer?.invalidate()
        firstTimer = nil
    }

    private func sample() {
        sampler.sample(at: Date(), apps: Self.runningApps(), socPower: monitor?.snapshot.socPower)
        report = sampler.report(at: Date())
    }

    /// As apps do utilizador: as que têm ícone no Dock.
    ///
    /// Perguntar ao `NSRunningApplication` custa uma ida ao LaunchServices por
    /// processo: era 85 % de cada leitura (cerca de 11 de 13 ms). A lista
    /// guarda-se e só se refaz quando uma app abre ou fecha, ou ao fim de
    /// `listLifetime` (uma app pode passar de acessória a regular sem aviso).
    static func runningApps(now: Date = Date()) -> [RunningApp] {
        observeWorkspace()
        if let cached = cachedApps, now.timeIntervalSince(cached.at) < listLifetime {
            return cached.apps
        }
        let apps: [RunningApp] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            let key = app.bundleIdentifier ?? app.executableURL?.path ?? "pid:\(app.processIdentifier)"
            return RunningApp(pid: app.processIdentifier, key: key,
                              name: app.localizedName ?? key, bundleIdentifier: app.bundleIdentifier)
        }
        cachedApps = (apps, now)
        return apps
    }

    private static var cachedApps: (apps: [RunningApp], at: Date)?
    private static var observers: [NSObjectProtocol] = []
    private static let listLifetime: TimeInterval = 30

    private static func observeWorkspace() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { cachedApps = nil }
            }
        }
    }
}
