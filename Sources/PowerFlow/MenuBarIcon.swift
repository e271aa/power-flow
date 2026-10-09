import AppKit
import PowerFlowCore

/// O item da barra de menus: a bateria do macOS, com a percentagem dentro e o
/// raio a carregar, e ao lado os watts que o Mac está a gastar.
///
/// É uma só imagem, sem título no botão: assim a largura não depende do texto
/// e não muda com os valores. Desenhada em código (o projeto não tem catálogo
/// de assets) e marcada como `isTemplate`, por isso só tem alfa: o macOS trata
/// do claro, do escuro, do item selecionado e das barras translúcidas.
///
/// A bateria é a do sistema, medida numa captura da barra (2 px por pt) e
/// reproduzida píxel a píxel; o handoff do ícone da barra tinha as proporções
/// do SF Symbols, mais pequenas. Em pt e em coordenadas AppKit, com origem em
/// baixo e 22 pt de altura. Alfas: 1 cheio, 0,35 a parte vazia, 0 os recortes
/// (os algarismos e o raio, abertos no corpo com `.destinationOut`, dentro da
/// própria imagem).
enum MenuBarIcon {
    static let height: CGFloat = 22

    private static let body = NSRect(x: 0, y: 5, width: 23, height: 12)
    private static let bodyRadius: CGFloat = 3.5
    /// Onde os algarismos se centram: ao meio do corpo na largura e meio ponto
    /// acima na altura, como no sistema.
    private static let center = NSPoint(x: 11.5, y: 11.5)
    private static let emptyAlpha: CGFloat = 0.35
    /// O lugar do raio, à direita dos algarismos: 4 pt de largura, a 0,5 pt deles.
    private static let boltSize = NSSize(width: 4, height: 6.5)
    private static let boltGap: CGFloat = 0.5

    /// Os algarismos da bateria: SF Pro Medium de 10 pt, tabulares.
    private static let percentSize: CGFloat = 10
    private static let percentWeight = NSFont.Weight.medium
    /// Os watts ao lado: o mesmo tipo de letra e o mesmo tamanho dos algarismos da bateria.
    static let wattsFont = NSFont.monospacedDigitSystemFont(ofSize: percentSize, weight: percentWeight)
    /// Onde os watts começam, contado do início da bateria: 3 pt depois do polo.
    private static let wattsX: CGFloat = 28.5
    /// «Só watts», sem bateria ao lado: o tamanho do texto da barra.
    static let wattsOnlyFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    /// O tamanho dos algarismos: 10 pt, ou o maior que caiba quando não cabem
    /// (só «100» com o raio), de meio em meio ponto.
    static func percentFont(_ percent: Int, bolt: Bool) -> NSFont {
        var size = percentSize
        while size > 6 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: percentWeight)
            if groupWidth(percent, bolt: bolt, font: font) <= digitsRoom { return font }
            size -= 0.5
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: percentWeight)
    }

    private static func groupWidth(_ percent: Int, bolt: Bool, font: NSFont) -> CGFloat {
        let digits = (String(percent) as NSString).size(withAttributes: [.font: font]).width
        return digits + (bolt ? boltGap + boltSize.width : 0)
    }

    // MARK: - Larguras

    /// Algarismos e raio juntos, centrados no corpo. Têm de caber nos 21 pt
    /// de dentro (1 pt de margem de cada lado).
    static func digitsGroupWidth(percent: Int, bolt: Bool) -> CGFloat {
        groupWidth(percent, bolt: bolt, font: percentFont(percent, bolt: bolt))
    }

    /// O espaço dentro do corpo onde os algarismos e o raio podem ir.
    static let digitsRoom: CGFloat = 21

    /// A largura que os watts reservam: a do texto mais largo, medida na fonte.
    static func slot(_ font: NSFont) -> CGFloat {
        (BarItem.widestWatts as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// A largura da imagem. Só depende do que o item mostra, nunca dos valores.
    /// Em pt inteiros, para o item acabar num píxel.
    static func width(for content: BarItem.Content) -> CGFloat {
        let width: CGFloat = switch content {
        case .battery: 25.5
        case .batteryWatts: wattsX + slot(wattsFont)
        case .watts: slot(wattsOnlyFont)
        case .flowWatts: flowWattsX + slot(wattsOnlyFont)
        }
        return width.rounded(.up) - trim(content)
    }

    /// O que se tira à reserva dos watts, para a imagem acabar onde acaba a
    /// tinta do «W» com três algarismos (medido no `--icon-preview`). A reserva
    /// deixava 4 pt sem tinta de cada lado com dois algarismos, e a seleção do
    /// sistema já põe a margem dela. A 13 pt só cabe 1 pt: com 2, o «W» de
    /// «120 W» perdia 1 pt.
    private static func trim(_ content: BarItem.Content) -> CGFloat {
        switch content {
        case .battery: 0
        case .batteryWatts: 2
        case .watts, .flowWatts: 1
        }
    }

    /// O comprimento do item na barra: o da imagem. A seleção do sistema já
    /// põe a margem dela à volta; uma margem nossa somava-se à dele.
    static func itemLength(for content: BarItem.Content) -> CGFloat {
        width(for: content)
    }

    /// Os watts mais comuns têm dois algarismos. O conjunto centra-se como se
    /// tivesse pelo menos esses: com um algarismo, ou «—», não se mexe, e só
    /// acima de 100 W anda meio algarismo para a esquerda.
    private static let typicalWatts = "88" + BarItem.narrowSpace + "W"

    /// Quanto o conteúdo se afasta da esquerda para ficar ao centro da imagem,
    /// em pt inteiros (as arestas ficam no píxel a 1× e a 2×).
    private static func centeringOffset(contentStart: CGFloat, text: String, font: NSFont,
                                        imageWidth: CGFloat) -> CGFloat {
        let measured = max((text as NSString).size(withAttributes: [.font: font]).width,
                           (typicalWatts as NSString).size(withAttributes: [.font: font]).width)
        return max(0, ((imageWidth - contentStart - measured) / 2).rounded())
    }

    // MARK: - Imagem

    static func image(_ item: BarItem, language: String = L10n.language) -> NSImage {
        let size = NSSize(width: width(for: item.content), height: height)
        let image = rendered(item, size: size, color: .black, language: language)
        image.isTemplate = true
        return image
    }

    /// A imagem num tamanho qualquer, proporcional: os 22 pt da barra ou as
    /// ampliações da pré-visualização. Isolada, para os recortes só abrirem
    /// buracos nela.
    static func rendered(_ item: BarItem, size: NSSize, color: NSColor,
                         language: String = L10n.language) -> NSImage {
        let watts = item.wattsText(language: language)
        return NSImage(size: size, flipped: false) { _ in
            let unit = size.height / height
            let transform = NSAffineTransform()
            transform.scale(by: unit)
            transform.concat()
            draw(item, watts: watts, color: color)
            return true
        }
    }

    private static func draw(_ item: BarItem, watts: String, color: NSColor) {
        switch item.content {
        case .battery:
            drawBattery(item, color: color)
        case .batteryWatts:
            let offset = centeringOffset(contentStart: wattsX, text: watts, font: wattsFont,
                                         imageWidth: width(for: .batteryWatts))
            NSGraphicsContext.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: offset, yBy: 0)
            shift.concat()
            drawBattery(item, color: color)
            drawText(watts, font: wattsFont, x: wattsX, centerY: center.y, color: color)
            NSGraphicsContext.restoreGraphicsState()
        case .watts:
            let offset = centeringOffset(contentStart: 0, text: watts, font: wattsOnlyFont,
                                         imageWidth: width(for: .watts))
            drawText(watts, font: wattsOnlyFont, x: offset, centerY: height / 2, color: color)
        case .flowWatts:
            let offset = centeringOffset(contentStart: flowWattsX, text: watts, font: wattsOnlyFont,
                                         imageWidth: width(for: .flowWatts))
            NSGraphicsContext.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: offset, yBy: (height - flowSize.height) / 2)
            shift.concat()
            drawFlow(state: item.reading == .unavailable ? .unavailable : item.isOnBattery ? .onBattery : .pluggedIn,
                     color: color)
            NSGraphicsContext.restoreGraphicsState()
            drawText(watts, font: wattsOnlyFont, x: offset + flowWattsX, centerY: height / 2, color: color)
        }
    }

    // MARK: - Ícone da app

    /// O ícone da app reduzido aos três nós do diagrama, como o item da barra
    /// da 2.0: 17 × 15 pt. Com o cabo, o nó do adaptador é cheio; em bateria,
    /// vazado; sem leitura dos sensores, os três vazados.
    enum FlowState { case pluggedIn, onBattery, unavailable }

    private static let flowSize = NSSize(width: 17, height: 15)
    /// Os watts a 5 pt do ícone, no tamanho do texto da barra.
    private static let flowWattsX: CGFloat = 22

    private static func drawFlow(state: FlowState, color: NSColor) {
        let radius: CGFloat = 2.3
        let systemRadius: CGFloat = 2.6
        let lineWidth: CGFloat = 1.4
        let adapter = NSPoint(x: 3.0, y: 10.6)
        let system = NSPoint(x: 14.0, y: 10.6)
        let battery = NSPoint(x: 8.5, y: 3.6)

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

        let isUnavailable = state == .unavailable
        node(at: system, radius: systemRadius, filled: !isUnavailable, lineWidth: lineWidth)
        node(at: battery, radius: radius, filled: !isUnavailable, lineWidth: lineWidth)
        node(at: adapter, radius: radius, filled: state == .pluggedIn, lineWidth: lineWidth)
    }

    private static func node(at center: NSPoint, radius: CGFloat, filled: Bool, lineWidth: CGFloat) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // Um nó vazado abre espaço na aresta que passa por baixo, senão a linha
        // atravessa-lhe o interior e o vazio não se lê.
        if !filled {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: rect.insetBy(dx: -lineWidth * 0.3, dy: -lineWidth * 0.3)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let circle = NSBezierPath(ovalIn: filled ? rect : rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        if filled {
            circle.fill()
        } else {
            circle.lineWidth = lineWidth
            circle.stroke()
        }
    }

    // MARK: - Bateria

    private static func drawBattery(_ item: BarItem, color: NSColor) {
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius, yRadius: bodyRadius)
        color.withAlphaComponent(emptyAlpha).setFill()
        bodyPath.fill()
        drawCap(alpha: item.percent >= 100 ? 1 : emptyAlpha, color: color)

        // O enchimento acaba num píxel do ecrã: a 1× e a 2× a aresta fica nítida.
        if item.percent > 0 {
            let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 2
            let full = body.width
            let width = item.percent >= 100 ? full
                : max(1.5, (full * CGFloat(item.percent) / 100 * scale).rounded() / scale)
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            color.setFill()
            NSRect(x: body.minX, y: body.minY, width: width, height: body.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Sem algarismos, só o raio, maior, ao meio do corpo.
        guard item.showsPercent else {
            if item.showsBolt, let symbol = plainBoltSymbol {
                let size = symbol.size
                symbol.draw(in: NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2,
                                       width: size.width, height: size.height),
                            from: .zero, operation: .destinationOut, fraction: 1)
            }
            return
        }

        // Os algarismos e o raio abrem-se no corpo, cheio ou vazio.
        let font = percentFont(item.percent, bolt: item.showsBolt)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let digits = String(item.percent) as NSString
        let digitsWidth = digits.size(withAttributes: attributes).width
        let group = groupWidth(item.percent, bolt: item.showsBolt, font: font)
        let x = ((center.x - group / 2) * 2).rounded() / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        digits.draw(with: NSRect(x: x, y: center.y - font.capHeight / 2, width: 0, height: 0),
                    options: [], attributes: attributes)
        if item.showsBolt {
            // O raio centra-se ao meio do corpo; os algarismos, meio ponto acima.
            let box = NSRect(x: x + digitsWidth + boltGap, y: body.midY - boltSize.height / 2,
                             width: boltSize.width, height: boltSize.height)
            if let symbol = boltSymbol {
                let size = symbol.size
                symbol.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                                       width: size.width, height: size.height),
                            from: .zero, operation: .destinationOut, fraction: 1)
            } else {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.setFill()
                bolt(in: box).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// O polo: a metade direita de uma cápsula, 1,5 × 4 pt, a 1 pt do corpo.
    private static func drawCap(alpha: CGFloat, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 24, y: 0, width: 10, height: height).clip()
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: 22.5, y: 9, width: 3, height: 4), xRadius: 1.5, yRadius: 1.5).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// O raio do sistema: o `bolt.fill` (macOS 11 ou mais recente) a 6,5 pt,
    /// peso Medium, ajustado à captura da barra. O polígono que o imitava tinha
    /// as pontas em bico e a barra do meio fina, e parecia mais pequeno.
    private static let boltSymbol: NSImage? = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 6.5, weight: .medium))

    /// Na bateria sem número o raio está sozinho e é maior: 9 pt, perto da
    /// altura do corpo. Não medido no sistema (não há captura deste caso).
    private static let plainBoltSymbol: NSImage? = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .medium))

    /// O raio desenhado à mão, se o símbolo faltar, numa caixa.
    private static func bolt(in box: NSRect) -> NSBezierPath {
        let points: [(CGFloat, CGFloat)] = [(0.6, 1), (0.8, 1), (0.36, 0.508), (1, 0.508),
                                            (0.4, 0), (0.3, 0), (0.57, 0.385), (0.05, 0.385)]
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: box.minX + point.0 * box.width, y: box.minY + point.1 * box.height)
            if index == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    // MARK: - Watts

    /// Os algarismos centram-se pelas maiúsculas: ao lado da bateria, à altura
    /// dos dela; sozinhos, ao meio da barra.
    private static func drawText(_ text: String, font: NSFont, x: CGFloat, centerY: CGFloat, color: NSColor) {
        (text as NSString).draw(with: NSRect(x: x, y: centerY - font.capHeight / 2, width: 0, height: 0),
                                options: [], attributes: [.font: font, .foregroundColor: color])
    }
}
