import AppKit
import Combine
import PowerFlowCore
import SwiftUI

/// `--window --motion-probe <pasta>`: mede o movimento do painel sem capturar o ecrã.
///
/// Carrega os estados do protótipo numa janela, faz uma mudança de cada vez
/// (push, voltar, período, aviso, fim da estabilização…) e desenha a árvore de
/// camadas da janela a cada 1/60 s. De cada mudança diz quanto tempo os
/// píxeis levam a assentar, a que altura do tempo vai a meio e como a altura
/// da janela evolui. No fim conta, ao vivo, quantas vezes por segundo o número
/// de destaque muda nos ritmos «Normal» e «Alta».
@MainActor
final class MotionProbe {
    /// Os dados que a sonda dá ao painel e muda a meio.
    @MainActor
    final class Feed: ObservableObject {
        /// O que se mostra: o instantâneo com as arestas à espera (`EdgeHold`),
        /// republicado a 1 Hz como faz o monitor.
        @Published private(set) var snapshot: PowerSnapshot
        @Published var sensorsAvailable: Bool
        @Published var history: HistoryStore
        @Published var apps: AppsInput
        @Published var firstRun = false

        private var raw: PowerSnapshot
        private var hold = EdgeHold()
        private var ticker: Timer?

        init(_ state: PanelFixture) {
            (raw, sensorsAvailable, history, apps) = Snapshotter.fixture(state)
            snapshot = raw
            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            }
            RunLoop.main.add(ticker, forMode: .common)
            self.ticker = ticker
        }

        func load(_ state: PanelFixture, keepApps: Bool = false) {
            let fresh = Snapshotter.fixture(state)
            sensorsAvailable = fresh.1
            history = fresh.2
            if !keepApps { apps = fresh.3 }
            set(fresh.0)
        }

        /// Um instantâneo novo, publicado já (como um aviso do sistema).
        func set(_ snapshot: PowerSnapshot) {
            raw = snapshot
            publish()
        }

        var current: PowerSnapshot { raw }

        private func publish() {
            var shown = raw
            shown.timestamp = Date()
            shown.heldEdges = hold.held(for: shown, at: shown.timestamp)
            snapshot = shown
        }
    }

    struct Step {
        let name: String
        let prepare: () -> Void
        let trigger: () -> Void
        var seconds: Double = 1.2
        /// Medir a posição ponto a ponto contra a curva do handoff.
        var curve: Curve?
    }

    /// O que se acompanha fotograma a fotograma, e contra que curva.
    enum Curve {
        /// O ecrã que entra, na horizontal: `.spring(response: 0.3, dampingFraction: 1)`.
        case push
        /// A linha que sobe na lista, na vertical: `PFMotion.layout`, easeInOut 0,25 s.
        case reorder

        var expectedName: String {
            switch self {
            case .push: "spring(response 0,3, amortecimento 1)"
            case .reorder: "easeInOut 0,25 s"
            }
        }

        /// A fração do caminho já feita aos `t` segundos.
        func expected(_ t: Double) -> Double {
            guard t > 0 else { return 0 }
            switch self {
            case .push:
                // Mola com amortecimento crítico: ω = 2π / resposta.
                let omega = 2 * Double.pi / 0.3
                return 1 - (1 + omega * t) * exp(-omega * t)
            case .reorder:
                return Self.cubicBezier(min(t / 0.25, 1), 0.42, 0, 0.58, 1)
            }
        }

        /// A curva de Bézier cúbica do `easeInOut`: o y para um x, por bisseção.
        private static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double,
                                        _ x2: Double, _ y2: Double) -> Double {
            func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
            }
            var low = 0.0, high = 1.0
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
            }
            return bezier((low + high) / 2, y1, y2)
        }
    }

    private struct Frame {
        let time: Double
        let pixels: [UInt8]
        let height: CGFloat
        let edges: [String: [Double]]
    }

    let folder: String
    let feed = Feed(.charging)
    let navigation = PanelNavigation()
    private let window: NSWindow
    private var report = ""
    private static let canvas = CGSize(width: 360, height: 720)

    init(folder: String, window: NSWindow) {
        self.folder = folder
        self.window = window
    }

    // MARK: - Os passos

    private var steps: [Step] {
        let nav = navigation, feed = feed
        return [
            Step(name: "push-clique (Bateria)", prepare: { feed.load(.charging) },
                 trigger: { nav.push(.battery, reduceMotion: self.reduceMotion) }, curve: .push),
            Step(name: "voltar-clique", prepare: { nav.push(.battery, reduceMotion: true) },
                 trigger: { nav.pop(animated: true, reduceMotion: self.reduceMotion) }),
            Step(name: "voltar-Esc (teclado)", prepare: { nav.push(.battery, reduceMotion: true) },
                 trigger: { self.key(53, "\u{1b}") }),
            Step(name: "voltar-⌘[ (teclado)", prepare: { nav.push(.apps, reduceMotion: true) },
                 trigger: { self.key(33, "[", .command) }),
            Step(name: "período-clique (2 min → 1 h)", prepare: { self.setPeriod(.twoMinutes) },
                 trigger: { self.clickPeriod(1) }),
            Step(name: "período-⌘2 (teclado)", prepare: { self.setPeriod(.twoMinutes) },
                 trigger: { self.key(19, "2", .command) }),
            Step(name: "período-⌘1 (teclado)", prepare: { self.setPeriod(.oneHour) },
                 trigger: { self.key(18, "1", .command) }),
            Step(name: "aviso a entrar (a carregar → assistência)", prepare: { feed.load(.charging) },
                 trigger: { feed.load(.assist) }, seconds: 2.4),
            Step(name: "aviso a sair (assistência → a carregar)", prepare: { feed.load(.assist) },
                 trigger: { feed.load(.charging) }, seconds: 2.4),
            Step(name: "fim da estabilização (a estabilizar → em pausa)", prepare: { feed.load(.warming) },
                 trigger: {
                     var settled = feed.current
                     settled.isSettled = true
                     settled.isAligned = true
                     settled.settleRemaining = 0
                     feed.set(settled)
                 }),
            Step(name: "números (+25 % em todas as potências)", prepare: { feed.load(.charging) },
                 trigger: {
                     var more = feed.current
                     more.adapterInput = more.adapterInput.map { $0 * 1.25 }
                     more.systemTotal = more.systemTotal.map { $0 * 1.25 }
                     more.socPower = more.socPower.map { $0 * 1.25 }
                     more.mainRailPower = more.mainRailPower.map { $0 * 1.25 }
                     feed.set(more)
                 }),
            Step(name: "Percebi-Return (teclado)", prepare: { feed.load(.charging); feed.firstRun = true },
                 trigger: { self.key(36, "\r") }),
            Step(name: "Percebi-clique", prepare: { feed.load(.charging); feed.firstRun = true },
                 // O SwiftUI só cria a árvore de acessibilidade com um cliente
                 // ligado; chama-se o que o botão chama, fora de um evento de teclado.
                 trigger: {
                     FirstRunCard.dismiss(navigation: nav, reduceMotion: self.reduceMotion) {
                         feed.firstRun = false
                     }
                 }),
            Step(name: "push-clique (Por app)", prepare: { feed.load(.charging) },
                 trigger: { nav.push(.apps, reduceMotion: self.reduceMotion) }, curve: .push),
            Step(name: "troca de ordem das apps (1.ª ↔ 2.ª)", prepare: {
                     feed.load(.charging)
                     nav.push(.apps, reduceMotion: true)
                 },
                 trigger: {
                     // A segunda passa a gastar mais do que a primeira: trocam de lugar.
                     var apps = feed.apps
                     guard apps.report.apps.count >= 2 else { return }
                     let first = apps.report.apps[0].watts
                     apps.report.apps[0].watts = apps.report.apps[1].watts
                     apps.report.apps[1].watts = first
                     apps.report.apps.swapAt(0, 1)
                     feed.apps = apps
                 }, curve: .reorder),
            Step(name: "Por app: «A medir…» → lista", prepare: {
                     feed.load(.charging)
                     feed.apps = AppsInput()
                     nav.push(.apps, reduceMotion: true)
                 },
                 trigger: { feed.load(.charging) }),
        ]
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || forceReduceMotion
    }
    var forceReduceMotion = false

    // MARK: - Correr

    /// Sem isto, ao fim de ~30 s o App Nap espaçava os temporizadores de uma
    /// janela que não está à frente e a sonda ficava com 5 fotogramas por passo.
    private var activity: NSObjectProtocol?

    func run() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "sonda de movimento")
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        log(String(format: "== Sonda de movimento · Reduzir Movimento: %@ (sistema %@) ==",
                   reduceMotion ? "ligado" : "desligado",
                   NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "ligado" : "desligado"))
        runStep(0)
    }

    private func runStep(_ index: Int) {
        let all = steps
        guard index < all.count else {
            measureLiveRates()
            return
        }
        let step = all[index]
        // Começa sempre do nível 1, sem animar, e com os dados de partida.
        navigation.pop(animated: false, reduceMotion: true)
        feed.firstRun = false
        step.prepare()
        window.makeKey()

        after(1.6) {
            var frames: [Frame] = []
            let start = CACurrentMediaTime() + 0.05
            var triggered = false
            let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
                MainActor.assumeIsolated {
                    let now = CACurrentMediaTime()
                    if !triggered && now >= start {
                        triggered = true
                        step.trigger()
                    }
                    frames.append(self.frame(at: now - start))
                    if now - start >= step.seconds {
                        timer.invalidate()
                        self.finish(step, index: index, frames: frames)
                    }
                }
            }
            RunLoop.main.add(tick, forMode: .common)
        }
    }

    private func finish(_ step: Step, index: Int, frames: [Frame]) {
        let before = frames.filter { $0.time < 0 }.last ?? frames[0]
        let after = frames.filter { $0.time >= 0 }
        guard let last = after.last else { return }

        let total = Self.difference(before.pixels, last.pixels)
        var settled = 0.0
        var half: Double?
        var changes = 0
        var previous = before.pixels
        for frame in after {
            let left = Self.difference(frame.pixels, last.pixels)
            if left > max(total * 0.02, 0.00005) { settled = frame.time }
            if half == nil, total > 0, 1 - left / total >= 0.5 { half = frame.time }
            if Self.difference(frame.pixels, previous) > max(total * 0.01, 0.00002) { changes += 1 }
            previous = frame.pixels
        }

        // A altura: de onde a onde, quando chegou, e por quantos valores passou.
        let heights = after.map(\.height)
        let finalHeight = heights.last ?? 0
        let reached = after.last(where: { abs($0.height - finalHeight) > 0.5 })?.time
        let distinct = Set(heights.map { Int(($0 * 2).rounded()) }).count

        // Depois do primeiro passo, que mede a velocidade, as partículas param.
        FlowLayerHost.freezesParticles = true

        var line = String(format: "%2d %-48@ %3d fotogramas · píxeis: mudança %.4f · assenta %4.0f ms · metade %@ · %2d fotogramas diferentes",
                          index + 1, step.name as NSString, frames.count, total, settled * 1000,
                          half.map { String(format: "%4.0f ms", $0 * 1000) } ?? "   —   ", changes)
        line += String(format: " | altura %.0f → %.0f pt", before.height, finalHeight)
        if let reached { line += String(format: ", chega aos %.0f ms por %d valores", reached * 1000, distinct) }
        log(line)
        log(String(format: "     (sonda: %.1f ms por fotograma, %d camadas)", renderSeconds / Double(max(renderCount, 1)) * 1000,
                   Self.layerCount(window.contentView?.layer)))
        renderSeconds = 0
        renderCount = 0

        // Onde os píxeis ainda mudam depois de 0,6 s.
        if let late = after.first(where: { $0.time >= 0.6 }),
           let box = Self.changedBox(late.pixels, last.pixels) {
            log(String(format: "     ainda muda depois de 0,6 s em x %.0f–%.0f, y %.0f–%.0f",
                       box.minX, box.maxX, box.minY, box.maxY))
        }

        // As camadas do Core Animation (o `render(in:)` não as desenha): o que
        // está a ser apresentado nas arestas que mudaram, de 50 em 50 ms, até
        // deixarem de mudar. A fase das partículas fica de fora: muda sempre.
        let edgeNames = Set(after.flatMap { $0.edges.keys }).sorted()
        for name in edgeNames {
            let samples = after.enumerated().filter { $0.offset % 3 == 0 }.map { frame -> String in
                guard let values = frame.element.edges[name] else { return "·" }
                return values.prefix(2).map { String(format: "%.2f", $0) }.joined(separator: "/")
            }
            guard Set(samples).count > 1 else { continue }
            let end = (samples.lastIndex { $0 != samples.last } ?? 0) + 2
            log("     \(name) [opacidade/\(name.hasSuffix("chevron") ? "escala" : "tubo"), de 50 em 50 ms]: "
                + samples.prefix(end).joined(separator: " "))
        }
        // A velocidade das partículas, da fase do tracejado: pontos por segundo.
        if index == 0 {
            for name in edgeNames where !name.hasSuffix("chevron") {
                let phases = after.compactMap { frame in frame.edges[name].map { (frame.time, $0[2]) } }
                var travelled = 0.0
                for (a, b) in zip(phases, phases.dropFirst()) {
                    var step = a.1 - b.1
                    if step < 0 { step += EdgeFlow.particleSpacing }
                    travelled += step
                }
                if let first = phases.first, let last = phases.last, last.0 > first.0, travelled > 0 {
                    log(String(format: "     partículas em %@: %.1f pt/s", name, travelled / (last.0 - first.0)))
                }
            }
        }

        if let curve = step.curve {
            logCurve(curve, before: before, after: after, last: last)
        }

        // Quatro fotogramas para ver a olho.
        let slug = String(format: "%02d", index + 1)
        for wanted in [0.05, 0.125, 0.25, 0.5] {
            if let frame = after.min(by: { abs($0.time - wanted) < abs($1.time - wanted) }) {
                Self.writePNG(frame.pixels, to: "\(folder)/\(slug)-\(Int(wanted * 1000))ms.png")
            }
        }
        Self.writePNG(last.pixels, to: "\(folder)/\(slug)-fim.png")
        runStep(index + 1)
    }

    // MARK: - Curvas, ponto a ponto

    /// Em cada fotograma, onde está um pedaço do fim que só existe uma vez (o
    /// título do ecrã que entra; o ícone da app que sobe): a fração do caminho
    /// feita, contra a curva do handoff, com o atraso de arranque que melhor a explica.
    private func logCurve(_ curve: Curve, before: Frame, after: [Frame], last: Frame) {
        let patch: CGRect
        let range: ClosedRange<Int>
        let path: Double
        switch curve {
        case .push:
            // O cabeçalho do ecrã que entra (voltar e título), que vem da direita.
            patch = CGRect(x: 8, y: 8, width: 150, height: 30)
            range = 0...Int(Self.canvas.width)
            path = Double(Self.canvas.width)
        case .reorder:
            guard let box = Self.changedBox(before.pixels, last.pixels) else {
                log("     curva: nada mudou (a lista não trocou de ordem)")
                return
            }
            // O ícone (e o início do nome) da linha que ficou em cima, que vem de baixo.
            patch = CGRect(x: box.minX, y: box.minY + 4, width: min(60, box.width), height: 34)
            range = -60...60
            path = 42
        }
        let points: [(Double, Double?)] = after.map { frame in
            (frame.time, Self.locate(patch, of: last.pixels, in: frame.pixels, curve: curve, range: range)
                .map { 1 - $0 / path })
        }
        // O atraso de arranque (0 a 6 fotogramas) que melhor explica a curva.
        func error(_ lag: Double) -> (rms: Double, worst: Double) {
            var sum = 0.0, worst = 0.0, count = 0
            for case let (t, measured?) in points where t <= 0.7 {
                let difference = measured - curve.expected(t - lag)
                sum += difference * difference
                worst = max(worst, abs(difference))
                count += 1
            }
            return (count > 0 ? (sum / Double(count)).squareRoot() : .infinity, worst)
        }
        let lag = (0...6).map { Double($0) / 60 }.min { error($0).rms < error($1).rms } ?? 0
        let (rms, worst) = error(lag)
        let reached90 = points.first { ($0.1 ?? 0) >= 0.9 }.map { String(format: "%.0f ms", ($0.0 - lag) * 1000) } ?? "—"
        log(String(format: "     curva contra %@: caminho %.0f pt; atraso de arranque %.0f ms; 90 %% aos %@ depois dele; diferença média %.3f, maior %.3f",
                   curve.expectedName, path, lag * 1000, reached90, rms, worst))
        var table: [String] = []
        for (index, point) in points.enumerated() where index % 2 == 0 && point.0 <= 0.6 {
            let measured = point.1.map { String(format: "%.2f", $0) } ?? "fora"
            table.append(String(format: "%3.0f ms %@/%.2f", point.0 * 1000, measured, curve.expected(point.0 - lag)))
        }
        log("     [medido/esperado] " + table.joined(separator: " · "))
    }

    /// Quanto (em pt) o pedaço do fotograma do fim está deslocado no fotograma
    /// dado: na horizontal para o push, na vertical para a lista. `nil`: não está
    /// à vista (ainda fora do painel), ou nada coincide.
    private static func locate(_ patch: CGRect, of final: [UInt8], in pixels: [UInt8],
                               curve: Curve, range: ClosedRange<Int>) -> Double? {
        let width = Int(canvas.width), height = Int(canvas.height)
        var best: Int?, bestScore = Double.infinity
        for shift in range {
            let (dx, dy) = curve == .push ? (shift, 0) : (0, shift)
            guard Int(patch.minX) + dx >= 0, Int(patch.maxX) + dx <= width,
                  Int(patch.minY) + dy >= 0, Int(patch.maxY) + dy <= height else { continue }
            var sum = 0, count = 0
            for y in stride(from: Int(patch.minY), to: Int(patch.maxY), by: 1) {
                for x in stride(from: Int(patch.minX), to: Int(patch.maxX), by: 1) {
                    let a = ((y + dy) * width + x + dx) * 4, b = (y * width + x) * 4
                    sum += abs(Int(pixels[a]) - Int(final[b])) + abs(Int(pixels[a + 1]) - Int(final[b + 1]))
                        + abs(Int(pixels[a + 2]) - Int(final[b + 2]))
                    count += 1
                }
            }
            let score = Double(sum) / Double(count)
            if score < bestScore { bestScore = score; best = shift }
        }
        // Acima disto o pedaço não está lá: o que coincide menos mal é outra coisa.
        guard let best, bestScore < 18 else { return nil }
        return Double(best)
    }

    // MARK: - Ritmo dos números, ao vivo

    private var liveMonitor: PowerMonitor?
    private var subscription: AnyCancellable?

    private func measureLiveRates() {
        let plan: [SampleRate] = [.normal, .high]
        func measure(_ index: Int) {
            guard index < plan.count else {
                log("== fim ==")
                try? report.write(toFile: "\(folder)/sonda.txt", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            let rate = plan[index]
            let monitor = PowerMonitor(sampleRate: rate)
            monitor.setFastSampling(true)
            liveMonitor = monitor
            var publishes: [Double] = []
            var heroChanges: [Double] = []
            var lastHero = ""
            let begin = CACurrentMediaTime()
            subscription = monitor.$snapshot.sink { snapshot in
                let now = CACurrentMediaTime() - begin
                publishes.append(now)
                let hero = PanelCopy(snapshot: snapshot,
                                     panel: PanelState(snapshot: snapshot, sensorsAvailable: true)).hero
                if hero != lastHero { heroChanges.append(now); lastHero = hero }
            }
            after(20) {
                self.subscription = nil
                monitor.setFastSampling(false)
                func gaps(_ times: [Double]) -> String {
                    let deltas = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }
                    guard let shortest = deltas.min() else { return "—" }
                    return String(format: "%d em 20 s, intervalo mínimo %.2f s, mais de 2 no mesmo segundo: %d",
                                  times.count, shortest,
                                  Self.overTwoPerSecond(times))
                }
                self.log("ao vivo, ritmo \(rate.rawValue): publicações \(gaps(publishes)) · número de destaque mudou \(gaps(heroChanges))")
                measure(index + 1)
            }
        }
        measure(0)
    }

    /// Quantas janelas de 1 s têm mais de duas mudanças.
    nonisolated private static func overTwoPerSecond(_ times: [Double]) -> Int {
        var count = 0
        for (index, start) in times.enumerated() {
            let inside = times[index...].prefix { $0 < start + 1 }.count
            if inside > 2 { count += 1 }
        }
        return count
    }

    // MARK: - Fotogramas

    private var renderSeconds = 0.0
    private var renderCount = 0

    private static func layerCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return 1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount($1) } + layerCount(layer.mask)
    }

    private func frame(at time: Double) -> Frame {
        let began = CACurrentMediaTime()
        defer { renderSeconds += CACurrentMediaTime() - began; renderCount += 1 }
        let view = window.contentView!
        var pixels = [UInt8](repeating: 0, count: Int(Self.canvas.width * Self.canvas.height) * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: Int(Self.canvas.width),
                                          height: Int(Self.canvas.height), bitsPerComponent: 8,
                                          bytesPerRow: Int(Self.canvas.width) * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // A árvore de camadas da janela conta o y de cima para baixo.
            context.translateBy(x: 0, y: Self.canvas.height)
            context.scaleBy(x: 1, y: -1)
            if let layer = view.layer {
                (layer.presentation() ?? layer).render(in: context)
            }
        }
        return Frame(time: time, pixels: pixels, height: view.bounds.height,
                     edges: FlowProbe.sample(in: view))
    }

    /// O retângulo (em pontos, de cima) onde dois fotogramas diferem.
    private static func changedBox(_ a: [UInt8], _ b: [UInt8]) -> CGRect? {
        let width = Int(canvas.width), height = Int(canvas.height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 24 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                for index in stride(from: 0, to: min(a.count, b.count), by: 1) {
                    sum += abs(Int(a[index]) - Int(b[index]))
                }
            }
        }
        return Double(sum) / Double(a.count) / 255
    }

    private static func writePNG(_ pixels: [UInt8], to path: String) {
        var copy = pixels
        copy.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: Int(canvas.width),
                                          height: Int(canvas.height), bitsPerComponent: 8,
                                          bytesPerRow: Int(canvas.width) * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage() else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Ações

    private func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(body) }
    }

    /// Uma tecla, só para esta janela.
    private func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil,
                                            characters: characters, charactersIgnoringModifiers: characters,
                                            isARepeat: false, keyCode: code) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private func setPeriod(_ period: HistoryPeriod) {
        UserDefaults.standard.set(period.rawValue, forKey: "pf.historyPeriod")
    }

    private func clickPeriod(_ segment: Int) {
        guard let control = Self.find(NSSegmentedControl.self, in: window.contentView) else {
            log("   (controlo de período não encontrado)")
            return
        }
        control.selectedSegment = segment
        control.sendAction(control.action, to: control.target)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }

    private func log(_ line: String) {
        print(line)
        fflush(stdout)
        report += line + "\n"
    }
}

/// O painel da sonda: como o do protótipo no `--window`, mas com dados que mudam.
struct ProbePanel: View {
    @ObservedObject var feed: MotionProbe.Feed
    @ObservedObject var navigation: PanelNavigation

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReduceMotion) private var forceReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        PanelStack(navigation: navigation, reduceMotion: reduceMotion) { route in
            PanelScreen(route: route, snapshot: feed.snapshot,
                        panel: PanelState(snapshot: feed.snapshot, sensorsAvailable: feed.sensorsAvailable),
                        history: feed.history, apps: feed.apps,
                        open: { navigation.push($0, reduceMotion: reduceMotion) },
                        back: { navigation.pop(animated: true, reduceMotion: reduceMotion) },
                        firstRun: feed.firstRun,
                        dismissFirstRun: {
                            FirstRunCard.dismiss(navigation: navigation, reduceMotion: reduceMotion) {
                                feed.firstRun = false
                            }
                        })
        }
        .background(PFColor.bg)
    }
}

/// O que as camadas das arestas estão a apresentar (`FlowLayerHost`). O
/// `render(in:)` não desenha camadas com máscara, por isso lêem-se os valores.
@MainActor
enum FlowProbe {
    static func sample(in view: NSView) -> [String: [Double]] {
        var found: [String: [Double]] = [:]
        func walk(_ view: NSView) {
            if let host = view as? FlowLayerHost {
                for (edge, values) in host.presented {
                    let name = "\(edge)".replacingOccurrences(of: "To", with: "→") + (host.part == .edges ? "" : " chevron")
                    found[name] = values
                }
            }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found
    }
}
