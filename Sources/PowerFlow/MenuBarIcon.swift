import AppKit

/// O ícone da barra de menus: o próprio diagrama reduzido a três nós.
///
/// É desenhado em código, não carregado de um ficheiro, por duas razões: o
/// projeto não tem catálogo de assets (constrói-se sem Xcode) e o desenho
/// vetorial mantém-se nítido em qualquer densidade de ecrã.
///
/// Marcado como `isTemplate`, o que faz o macOS tratá-lo como uma máscara:
/// fica preto na barra clara, branco na escura e inverte-se quando o item
/// está selecionado, sem precisarmos de variantes.
enum MenuBarIcon {
    /// - Parameter pluggedIn: com o cabo ligado o nó do adaptador é cheio;
    ///   em bateria fica vazado, para se ver de relance de onde vem a energia.
    static func image(pluggedIn: Bool) -> NSImage {
        let image = rendered(size: NSSize(width: 17, height: 15),
                             pluggedIn: pluggedIn, color: .black)
        image.isTemplate = true
        return image
    }

    /// Desenha o ícone numa imagem própria, de fundo transparente.
    ///
    /// O isolamento é essencial: o nó vazado abre-se com uma operação de
    /// limpeza, que apagaria o que já estivesse desenhado por baixo se o
    /// desenho fosse feito diretamente sobre outra tela.
    static func rendered(size: NSSize, pluggedIn: Bool, color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            draw(in: size, pluggedIn: pluggedIn, color: color)
            return true
        }
    }

    /// Desenha proporcionalmente ao tamanho pedido, para servir tanto os
    /// 15 pt da barra de menus como as ampliações da pré-visualização.
    static func draw(in size: NSSize, pluggedIn: Bool, color: NSColor = .black) {
        let unit = size.height / 15.0
        let radius = 2.1 * unit
        let lineWidth = 1.15 * unit

        let adapter = NSPoint(x: 3.0 * unit, y: 10.6 * unit)
        let system  = NSPoint(x: 14.0 * unit, y: 10.6 * unit)
        let battery = NSPoint(x: 8.5 * unit, y: 3.4 * unit)

        color.setStroke()
        color.setFill()

        // As arestas primeiro, para os nós assentarem por cima delas.
        let edges = NSBezierPath()
        edges.move(to: adapter)
        edges.line(to: system)
        edges.move(to: adapter)
        edges.line(to: battery)
        edges.move(to: battery)
        edges.line(to: system)
        edges.lineWidth = lineWidth
        edges.lineCapStyle = .round
        edges.lineJoinStyle = .round
        edges.stroke()

        node(at: system, radius: radius, filled: true, lineWidth: lineWidth)
        node(at: battery, radius: radius, filled: true, lineWidth: lineWidth)
        node(at: adapter, radius: radius, filled: pluggedIn, lineWidth: lineWidth)
    }

    private static func node(at center: NSPoint, radius: CGFloat,
                             filled: Bool, lineWidth: CGFloat) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        // Um nó vazado tem de abrir espaço na aresta que passa por baixo,
        // senão a linha atravessa-lhe o interior e o vazio não se lê.
        if !filled {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: rect.insetBy(dx: -lineWidth * 0.3,
                                              dy: -lineWidth * 0.3)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let circle = NSBezierPath(ovalIn: filled ? rect : rect.insetBy(dx: lineWidth / 2,
                                                                      dy: lineWidth / 2))
        if filled {
            circle.fill()
        } else {
            circle.lineWidth = lineWidth
            circle.stroke()
        }
    }
}
