import AppKit
import PowerFlowCore
import SwiftUI

/// A pilha do painel: a vista da rota, o push e a altura.
///
/// A altura acompanha a vista em 0,25 s easeInOut (handoff, «Push»), também
/// quando muda sem navegar: o aviso que entra, «A medir…» que dá lugar à
/// lista. Muda de uma vez na primeira medição, com Reduzir Movimento e logo a
/// seguir a uma ação do teclado (D7b). O conteúdo fica encostado em cima e a
/// parte de baixo é cortada ou revelada.
struct PanelStack<Screen: View>: View {
    @ObservedObject var navigation: PanelNavigation
    let reduceMotion: Bool
    let screen: (PanelRoute) -> Screen

    @StateObject private var height = PanelHeight()

    init(navigation: PanelNavigation, reduceMotion: Bool, @ViewBuilder screen: @escaping (PanelRoute) -> Screen) {
        self.navigation = navigation
        self.reduceMotion = reduceMotion
        self.screen = screen
    }

    var body: some View {
        let route = navigation.route
        ZStack(alignment: .top) {
            screen(route)
                // A altura natural da vista, seja qual for a da janela neste instante.
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelHeightKey.self, value: [route: proxy.size.height])
                    }
                }
                .id(route)
                .transition(navigation.transition(reduceMotion: reduceMotion))
        }
        .frame(width: PanelContent.width, height: height.shown, alignment: .top)
        .clipped()
        .onPreferenceChange(PanelHeightKey.self) { heights in
            MainActor.assumeIsolated {
                // Durante o push estão as duas vistas; conta a da rota de agora.
                // Durante o push estão as duas vistas; conta a da rota de agora.
                guard let target = heights[navigation.route] else { return }
                height.move(to: target, animated: !reduceMotion && navigation.resizeAnimates)
            }
        }
        .background { PanelBackShortcuts(navigation: navigation) }
    }
}

/// A altura de cada vista da pilha, pela rota: na transição há duas.
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: [PanelRoute: CGFloat] = [:]

    static func reduce(value: inout [PanelRoute: CGFloat], nextValue: () -> [PanelRoute: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A altura que o painel mostra, a caminho da da vista.
///
/// A janela do popover segue o tamanho que o SwiftUI pede, por isso a
/// animação é deste valor, passo a passo, e não do `NSPopover`: o dele não
/// deixa escolher a duração nem a curva, e anima também o abrir e o fechar.
@MainActor
final class PanelHeight: ObservableObject {
    @Published private(set) var shown: CGFloat?

    nonisolated static let duration: Double = 0.25
    private var timer: Timer?

    func move(to target: CGFloat, animated: Bool) {
        timer?.invalidate()
        timer = nil
        guard let from = shown, animated, abs(from - target) > 0.5 else {
            if shown != target { shown = target }
            return
        }
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min((CACurrentMediaTime() - start) / Self.duration, 1)
                self.shown = from + (target - from) * CGFloat(Self.easeInOut(progress))
                if progress >= 1 {
                    timer.invalidate()
                    self.timer = nil
                }
            }
        }
        // .common: continua com o rato a segurar um botão ou um menu aberto.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A curva easeInOut do Core Animation, (0,42, 0, 0,58, 1).
    nonisolated static func easeInOut(_ x: Double) -> Double {
        // Resolve x(t) = x pelo método de Newton e devolve y(t).
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
        }
        var t = x
        for _ in 0..<8 {
            let slope = 3 * 0.42 * (1 - t) * (1 - t) + 6 * (0.58 - 0.42) * t * (1 - t) + 3 * (1 - 0.58) * t * t
            guard slope > 1e-6 else { break }
            t -= (bezier(t, 0.42, 0.58) - x) / slope
            t = min(max(t, 0), 1)
        }
        return bezier(t, 0, 1)
    }
}
