import SwiftUI

/// As durações e curvas da tabela «Movimento» do handoff, num só sítio.
///
/// Cada animação está presa a um valor que só muda na transição (o aviso, a
/// estabilização, a rota). Nenhuma corre a cada leitura no SwiftUI: animar o
/// que muda a cada leitura foi a causa de E1, e voltou a medir-se na Fase 11
/// (os números com `.numericText()` levavam o painel aberto a 33 % de CPU, a
/// largura das fatias a +10 pontos). O que muda a cada leitura e anima — a
/// espessura das arestas — anima no Core Animation (`FlowLayers`).
enum PFMotion {
    /// Fim da estabilização: `fg2` → `fg`.
    static let settleInk = Animation.easeOut(duration: 0.3)
    /// O aviso e a barra de estabilização a entrar ou a sair: altura e opacidade.
    static let layout = Animation.easeInOut(duration: PanelHeight.duration)
    /// O aviso com Reduzir Movimento: só a opacidade.
    static let reducedFade = Animation.easeOut(duration: 0.15)
    /// A troca de período no gráfico: só as séries; os eixos não animam.
    static let periodFade = Animation.easeInOut(duration: 0.2)
}
