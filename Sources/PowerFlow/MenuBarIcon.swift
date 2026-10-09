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
/// Geometria do handoff do ícone da barra (versão base), em pt e em
/// coordenadas AppKit, com origem em baixo e 22 pt de altura. Alfas: 1 cheio,
/// 0,35 a parte vazia, 0 os recortes (os algarismos e o raio, abertos no
/// enchimento com `.destinationOut`, dentro da própria imagem).
enum MenuBarIcon {
    static let height: CGFloat = 22
    /// O espaço de cada lado da imagem, dentro do item.
    static let itemPadding: CGFloat = 4

    private static let body = NSRect(x: 0, y: 5, width: 22, height: 11)
    private static let bodyRadius: CGFloat = 3.5
    /// Centro do corpo: os algarismos centram-se aqui.
    private static let center = NSPoint(x: 11, y: 10.5)
    private static let emptyAlpha: CGFloat = 0.35

    /// Os watts ao lado da bateria: o mesmo tipo de letra dos algarismos dela
    /// (SF Pro Bold, algarismos tabulares), um pouco maior.
    static let wattsFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    private static let wattsX: CGFloat = 28
    /// «Só watts», sem bateria ao lado: o tamanho do texto da barra.
    static let wattsOnlyFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    static func percentFont(_ percent: Int) -> NSFont {
        // «100» com o raio não cabe a 8 pt: é a única exceção.
        .monospacedDigitSystemFont(ofSize: percent >= 100 ? 7 : 8, weight: .bold)
    }

    // MARK: - Larguras

    /// Algarismos e raio juntos, centrados no corpo. Têm de caber nos 20 pt
    /// de dentro (1 pt de margem de cada lado).
    static func digitsGroupWidth(percent: Int, charging: Bool) -> CGFloat {
        let digits = (String(percent) as NSString).size(withAttributes: [.font: percentFont(percent)]).width
        return digits + (charging ? 4.5 : 0)
    }

    /// O espaço dentro do corpo onde os algarismos e o raio podem ir.
    static let digitsRoom: CGFloat = 20

    /// A largura que os watts reservam: a do texto mais largo, medida na fonte.
    static func slot(_ font: NSFont) -> CGFloat {
        (BarItem.widestWatts as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// A largura da imagem. Só depende do que o item mostra, nunca dos valores.
    static func width(for content: BarItem.Content) -> CGFloat {
        switch content {
        case .battery: 25
        case .batteryWatts: wattsX + slot(wattsFont)
        case .watts: slot(wattsOnlyFont)
        }
    }

    /// O comprimento do item na barra.
    static func itemLength(for content: BarItem.Content) -> CGFloat {
        width(for: content) + itemPadding * 2
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
            drawBattery(item, color: color)
            drawText(watts, font: wattsFont, x: wattsX, centerY: center.y, color: color)
        case .watts:
            drawText(watts, font: wattsOnlyFont, x: 0, centerY: height / 2, color: color)
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

        // Os algarismos e o raio abrem-se no corpo, cheio ou vazio.
        let font = percentFont(item.percent)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let digits = String(item.percent) as NSString
        let digitsWidth = digits.size(withAttributes: attributes).width
        let group = digitsGroupWidth(percent: item.percent, charging: item.isCharging)
        let x = ((center.x - group / 2) * 2).rounded() / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        digits.draw(with: NSRect(x: x, y: center.y - font.capHeight / 2, width: 0, height: 0),
                    options: [], attributes: attributes)
        if item.isCharging {
            NSColor.black.setFill()
            bolt(in: NSRect(x: x + digitsWidth + 0.5, y: 6.75, width: 4, height: 7.5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// O polo: a metade direita de uma cápsula, a 1 pt do corpo.
    private static func drawCap(alpha: CGFloat, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 23, y: 0, width: 10, height: height).clip()
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: 21.5, y: 8, width: 3, height: 5), xRadius: 1.5, yRadius: 1.5).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// O raio, com as proporções do `bolt.fill` do sistema, numa caixa.
    private static func bolt(in box: NSRect) -> NSBezierPath {
        let points: [(CGFloat, CGFloat)] = [(0.611, 1), (0, 0.4375), (0.444, 0.4375),
                                            (0.389, 0), (1, 0.594), (0.556, 0.594)]
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: box.minX + point.0 * box.width, y: box.minY + point.1 * box.height)
            if index == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    // MARK: - Watts

    /// Os algarismos centram-se pelas maiúsculas: ao lado da bateria, na altura
    /// do corpo dela; sozinhos, na da barra.
    private static func drawText(_ text: String, font: NSFont, x: CGFloat, centerY: CGFloat, color: NSColor) {
        (text as NSString).draw(with: NSRect(x: x, y: centerY - font.capHeight / 2, width: 0, height: 0),
                                options: [], attributes: [.font: font, .foregroundColor: color])
    }
}
