import Darwin
import Foundation

/// De onde vem a energia de cada processo.
public enum AppEnergyMethod: String, Sendable {
    /// `ri_energy_nj` do `RUSAGE_INFO_V6`: a energia de CPU que o kernel atribui
    /// ao processo. Não inclui a GPU: uma carga só de GPU que sobe o SoC em
    /// 10 W dá 0,004 W ao processo (medido na Fase 7).
    case energy
    /// Sem v6: o tempo de CPU de cada processo, repartindo a potência do SoC
    /// medida no mesmo intervalo. Mais grosseiro: não distingue núcleos de
    /// eficiência de núcleos de desempenho.
    case cpuTime
}

/// O contador acumulado de um processo desde que arrancou.
public struct ProcessCounter: Equatable, Sendable {
    /// nJ no método `.energy`; ns de CPU no método `.cpuTime`.
    public var value: UInt64
    /// Quando o processo arrancou, em tempo absoluto da máquina. Separa um
    /// processo de outro que tenha herdado o mesmo pid.
    public var start: UInt64

    public init(value: UInt64, start: UInt64) {
        self.value = value
        self.start = start
    }
}

/// O que o amostrador precisa do sistema. Os testes dão um falso.
public protocol ProcessEnergyReading: AnyObject {
    var method: AppEnergyMethod { get }
    /// O relógio em que vêm os `start` dos contadores.
    func absoluteTime() -> UInt64
    /// Os contadores de todos os processos que se deixam ler sem root.
    func readAll() -> [pid_t: ProcessCounter]
    /// O processo que o sistema dá como responsável por este (a app, para os
    /// serviços XPC que ela pediu ao launchd). `nil`: não se sabe.
    func responsible(for pid: pid_t) -> pid_t?
    func parent(of pid: pid_t) -> pid_t?
}

/// Uma app do utilizador (`activationPolicy == .regular`) a correr agora.
public struct RunningApp: Equatable, Sendable {
    public var pid: pid_t
    /// O que identifica a app entre arranques: o identificador do bundle ou,
    /// sem ele, o caminho do executável.
    public var key: String
    public var name: String
    public var bundleIdentifier: String?

    public init(pid: pid_t, key: String, name: String, bundleIdentifier: String?) {
        self.pid = pid
        self.key = key
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// O consumo médio de uma app na janela.
public struct AppUsage: Equatable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var bundleIdentifier: String?
    public var watts: Double
    /// Falso para uma app que terminou dentro da janela.
    public var isRunning: Bool
    /// O pid da app, enquanto corre. Serve para a ativar com um clique.
    public var pid: pid_t?

    public var id: String { key }

    public init(key: String, name: String, bundleIdentifier: String? = nil, watts: Double,
                isRunning: Bool = true, pid: pid_t? = nil) {
        self.key = key
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.watts = watts
        self.isRunning = isRunning
        self.pid = pid
    }
}

/// O resultado do amostrador num instante.
public struct AppEnergyReport: Equatable, Sendable {
    /// Todas as apps com energia na janela, da que gasta mais para a que gasta menos.
    public var apps: [AppUsage]
    /// Segundos que a média cobre: chega a `window` ao fim de 5 min com a vista aberta.
    public var span: TimeInterval
    public var window: TimeInterval
    public var method: AppEnergyMethod
    /// Até onde vão as leituras. `nil`: ainda não há média nenhuma.
    public var measuredAt: Date?

    public init(apps: [AppUsage], span: TimeInterval, window: TimeInterval = AppEnergySampler.window,
                method: AppEnergyMethod = .energy, measuredAt: Date?) {
        self.apps = apps
        self.span = span
        self.window = window
        self.method = method
        self.measuredAt = measuredAt
    }

    public static func empty(method: AppEnergyMethod = .energy) -> AppEnergyReport {
        AppEnergyReport(apps: [], span: 0, method: method, measuredAt: nil)
    }
}

/// Energia por app, numa média deslizante de 5 min.
///
/// Os contadores do kernel são acumulados desde que cada processo arrancou,
/// por isso basta ler de vez em quando: a diferença entre duas leituras é a
/// energia gasta no meio, por longo que seja o intervalo. É o que deixa o
/// amostrador parado com a vista fechada e, ao reabrir dentro de 5 min, dar
/// logo a média certa.
///
/// Os processos auxiliares contam para a app que os lançou, pelo processo
/// responsável que o sistema regista. Pelo pai não chegava: os processos do
/// WebKit do Safari são filhos do launchd e ficavam com 84 % da energia do
/// Safari (2,6 de 3,07 W, medido na Fase 7). O que não pertence a nenhuma app
/// do utilizador fica em «Sistema e outros».
public final class AppEnergySampler {
    public static let window: TimeInterval = 300

    private struct Bucket {
        var start: Date
        var end: Date
        var joules: [String: Double]
    }

    private struct Owner {
        var start: UInt64
        var key: String?
    }

    private let reader: ProcessEnergyReading
    public let window: TimeInterval

    private var counters: [pid_t: ProcessCounter] = [:]
    private var lastDate: Date?
    private var lastAbsolute: UInt64 = 0
    private var buckets: [Bucket] = []
    private var owners: [pid_t: Owner] = [:]
    private var ownersAppPids: Set<pid_t> = []
    /// Nome e bundle de cada app que passou pela janela, para as que já terminaram.
    private var known: [String: (name: String, bundle: String?)] = [:]
    private var running: [String: pid_t] = [:]

    public var method: AppEnergyMethod { reader.method }

    /// Quantos processos se leram na última amostra.
    public private(set) var readableCount = 0

    public init(reader: ProcessEnergyReading, window: TimeInterval = AppEnergySampler.window) {
        self.reader = reader
        self.window = window
    }

    /// Uma leitura. A primeira (ou a primeira depois de mais de `window`
    /// parado) só marca o ponto de partida.
    ///
    /// `socPower`: a potência do SoC agora, em W. Só o método `.cpuTime` a usa.
    public func sample(at date: Date, apps: [RunningApp], socPower: Double?) {
        let now = reader.readAll()
        let absolute = reader.absoluteTime()
        readableCount = now.count

        running = Dictionary(apps.map { ($0.key, $0.pid) }, uniquingKeysWith: { first, _ in first })
        for app in apps { known[app.key] = (app.name, app.bundleIdentifier) }

        defer {
            counters = now
            lastDate = date
            lastAbsolute = absolute
            buckets.removeAll { $0.end <= date.addingTimeInterval(-window) }
        }
        guard let lastDate, date > lastDate, date.timeIntervalSince(lastDate) <= window else {
            buckets.removeAll()
            return
        }

        let appPids = Dictionary(apps.map { ($0.pid, $0.key) }, uniquingKeysWith: { first, _ in first })
        if Set(appPids.keys) != ownersAppPids {
            owners.removeAll()
            ownersAppPids = Set(appPids.keys)
        }

        var byKey: [String: Double] = [:]
        var all = 0.0
        for (pid, counter) in now {
            let delta: UInt64
            if let before = counters[pid], before.start == counter.start {
                delta = counter.value >= before.value ? counter.value - before.value : 0
            } else if counter.start > lastAbsolute {
                // Nasceu depois da última leitura: tudo o que gastou é deste intervalo.
                delta = counter.value
            } else {
                continue
            }
            guard delta > 0 else { continue }
            let amount = Double(delta) / 1e9
            all += amount
            if let key = owner(of: pid, start: counter.start, appPids: appPids) {
                byKey[key, default: 0] += amount
            }
        }

        if reader.method == .cpuTime {
            // Segundos de CPU → joules: a fatia de cada app no tempo de CPU
            // de todos os processos legíveis, vezes a energia do SoC.
            let energy = (socPower ?? 0) * date.timeIntervalSince(lastDate)
            byKey = all > 0 ? byKey.mapValues { $0 / all * energy } : [:]
        }
        buckets.append(Bucket(start: lastDate, end: date, joules: byKey))
    }

    /// A média de cada app na janela que acaba na última leitura.
    public func report(at date: Date) -> AppEnergyReport {
        guard let end = buckets.last?.end, let first = buckets.first?.start else {
            return .empty(method: reader.method)
        }
        let windowStart = end.addingTimeInterval(-window)
        let from = max(windowStart, first)
        let span = end.timeIntervalSince(from)
        guard span > 0 else { return .empty(method: reader.method) }

        var joules: [String: Double] = [:]
        for bucket in buckets {
            let length = bucket.end.timeIntervalSince(bucket.start)
            let inside = bucket.end.timeIntervalSince(max(bucket.start, from))
            guard length > 0, inside > 0 else { continue }
            let share = min(1, inside / length)
            for (key, value) in bucket.joules { joules[key, default: 0] += value * share }
        }

        let apps = joules.map { key, value in
            AppUsage(key: key, name: known[key]?.name ?? key, bundleIdentifier: known[key]?.bundle,
                     watts: value / span, isRunning: running[key] != nil, pid: running[key])
        }
        .sorted { $0.watts != $1.watts ? $0.watts > $1.watts : $0.name < $1.name }
        return AppEnergyReport(apps: apps, span: span, window: window, method: reader.method,
                               measuredAt: end)
    }

    /// A app a que um processo pertence: a do processo responsável ou, sem
    /// ele, a primeira app na cadeia de pais.
    private func owner(of pid: pid_t, start: UInt64, appPids: [pid_t: String]) -> String? {
        if let cached = owners[pid], cached.start == start { return cached.key }
        var key: String?
        if let app = appPids[pid] {
            key = app
        } else if let responsible = reader.responsible(for: pid), responsible != pid,
                  let app = ancestorApp(of: responsible, appPids: appPids) {
            key = app
        } else {
            key = ancestorApp(of: pid, appPids: appPids)
        }
        owners[pid] = Owner(start: start, key: key)
        return key
    }

    private func ancestorApp(of pid: pid_t, appPids: [pid_t: String]) -> String? {
        var current = pid
        for _ in 0..<32 {
            if let app = appPids[current] { return app }
            guard current > 1, let parent = reader.parent(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }
}

/// Os contadores verdadeiros, pelo `libproc`.
public final class SystemProcessReader: ProcessEnergyReading {
    public let method: AppEnergyMethod
    /// Se o sistema dá o processo responsável. Sem ele, só a cadeia de pais.
    public let hasResponsibility: Bool

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private let responsibleFn: ResponsibleFn?
    private let timebase: (numer: UInt64, denom: UInt64)

    /// `forcing`: usa este método mesmo que o v6 exista. Serve para ver o
    /// recurso a funcionar num Mac recente (`--dump-apps --rusage v4`).
    public init(forcing forced: AppEnergyMethod? = nil) {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        timebase = (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))

        // Privado, mas é o que o Monitor de Atividade usa para juntar os
        // serviços XPC à app. Procura-se em tempo de execução: se um dia
        // faltar, a app não falha, só perde essa ligação.
        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                           "responsibility_get_pid_responsible_for_pid")
        responsibleFn = symbol.map { unsafeBitCast($0, to: ResponsibleFn.self) }
        hasResponsibility = responsibleFn != nil

        method = forced ?? Self.detectMethod()
    }

    /// O v6 existe desde o macOS 12, mas só se confia nele se a leitura de
    /// si próprio der energia: este processo já gastou CPU para chegar aqui.
    public static func detectMethod() -> AppEnergyMethod {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0)
            }
        }
        return result == 0 && info.ri_energy_nj > 0 ? .energy : .cpuTime
    }

    public func absoluteTime() -> UInt64 { mach_absolute_time() }

    public func readAll() -> [pid_t: ProcessCounter] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return [:] }

        var result: [pid_t: ProcessCounter] = [:]
        result.reserveCapacity(Int(got))
        for pid in pids.prefix(Int(got)) where pid > 0 {
            if let counter = read(pid) { result[pid] = counter }
        }
        return result
    }

    private func read(_ pid: pid_t) -> ProcessCounter? {
        switch method {
        case .energy:
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            return result == 0 ? ProcessCounter(value: info.ri_energy_nj, start: info.ri_proc_start_abstime) : nil
        case .cpuTime:
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { return nil }
            // Os tempos vêm em unidades do relógio da máquina, não em ns:
            // num M1 cada unidade são 125/3 ns.
            let ticks = info.ri_user_time &+ info.ri_system_time
            let nanoseconds = ticks.multipliedReportingOverflow(by: timebase.numer)
            let value = nanoseconds.overflow ? ticks / timebase.denom * timebase.numer
                : nanoseconds.partialValue / timebase.denom
            return ProcessCounter(value: value, start: info.ri_proc_start_abstime)
        }
    }

    public func responsible(for pid: pid_t) -> pid_t? {
        guard let responsibleFn else { return nil }
        let owner = responsibleFn(pid)
        return owner > 0 ? owner : nil
    }

    public func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }
}
