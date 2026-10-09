import AppKit
import PowerFlowCore

/// Folha de contacto do item da barra de menus (`--icon-preview`).
///
/// A barra é o pior sítio para avaliar o item a olho: tem 22 pt de altura e
/// fica encostado a outros. Isto desenha-o ao tamanho real (1× e 2×) e
/// ampliado (8×, com a grelha de 1 pt), sobre fundo claro e escuro, e confere
/// as larguras: a do item não pode mudar com os valores nem passar de 72 pt.
enum IconPreview {
    private struct Case {
        let label: String
        let item: BarItem
    }

    private static let maximumItem: CGFloat = 72

    private static var cases: [Case] {
        func battery(_ percent: Int, charging: Bool = false, watts: BarItem.Reading = .watts(15)) -> Case {
            // «a carregar» aqui é o raio: o cabo ligado.
            let reading: String = switch watts {
            case .watts(let value): "\(value) W"
            case .settling: "a medir"
            case .unavailable: "sem leitura"
            }
            return Case(label: "\(percent) %\(charging ? " com cabo" : "") · \(reading)",
                        item: BarItem(content: .batteryWatts, percent: percent, isCharging: charging, reading: watts))
        }
        var all: [Case] = []
        for percent in [100, 80, 50, 20, 5] { all.append(battery(percent)) }
        for percent in [100, 80, 50, 20, 5] { all.append(battery(percent, charging: true)) }
        for watts in [5, 120] { all.append(battery(80, watts: .watts(watts))) }
        all.append(battery(80, watts: .unavailable))
        all.append(Case(label: "Só bateria · 80 % com cabo",
                        item: BarItem(content: .battery, percent: 80, isCharging: true, reading: .watts(15))))
        all.append(Case(label: "Bateria sem % · 80 %",
                        item: BarItem(content: .battery, percent: 80, isCharging: false, showsPercent: false,
                                      reading: .watts(15))))
        all.append(Case(label: "Bateria sem % e watts · 20 % com cabo",
                        item: BarItem(content: .batteryWatts, percent: 20, isCharging: true, showsPercent: false,
                                      reading: .watts(15))))
        all.append(Case(label: "Ícone e watts · com cabo",
                        item: BarItem(content: .flowWatts, percent: 80, isCharging: false, reading: .watts(15))))
        all.append(Case(label: "Ícone e watts · em bateria",
                        item: BarItem(content: .flowWatts, percent: 80, isCharging: false, isOnBattery: true,
                                      reading: .watts(15))))
        all.append(Case(label: "Ícone e watts · sem leitura",
                        item: BarItem(content: .flowWatts, percent: 80, isCharging: false, reading: .unavailable)))
        all.append(Case(label: "Só watts · 15 W",
                        item: BarItem(content: .watts, percent: 80, isCharging: false, reading: .watts(15))))
        all.append(Case(label: "Mac sem bateria · 120 W",
                        item: BarItem(content: .watts, percent: 0, isCharging: false, hasBattery: false,
                                      reading: .watts(120))))
        return all
    }

    /// Os quatro casos ampliados.
    private static var zoomed: [Case] {
        [0, 4, 5, 9].map { cases[$0] }
    }

    static func render(to path: String) {
        let padding: CGFloat = 16
        let labelWidth: CGFloat = 190
        let widest = MenuBarIcon.width(for: .batteryWatts)
        let rowHeight: CGFloat = 22 * 2 + 10
        let zoomHeight: CGFloat = 22 * 8 + padding
        let width = max(padding + labelWidth + widest * 3 + padding * 3, padding * 2 + widest * 8 * 2 + padding)
        let height = rowHeight * CGFloat(cases.count) * 2 + zoomHeight * CGFloat(zoomed.count / 2) * 2 + padding

        // Um píxel por ponto: o «1×» é mesmo 1×.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else { print("Falhou a renderização."); return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        var y = height
        for isDark in [false, true] {
            let background = isDark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)
            let foreground: NSColor = isDark ? .white : .black

            for entry in cases {
                y -= rowHeight
                background.setFill()
                NSRect(x: 0, y: y, width: width, height: rowHeight).fill()
                var attributes = label
                attributes[.foregroundColor] = foreground.withAlphaComponent(0.6)
                (entry.label as NSString).draw(at: NSPoint(x: padding, y: y + rowHeight / 2 - 7), withAttributes: attributes)

                var x = padding + labelWidth
                for scale: CGFloat in [1, 2] {
                    let size = NSSize(width: MenuBarIcon.width(for: entry.item.content) * scale, height: 22 * scale)
                    MenuBarIcon.rendered(entry.item, size: size, color: foreground)
                        .draw(at: NSPoint(x: x, y: y + (rowHeight - size.height) / 2), from: .zero,
                              operation: .sourceOver, fraction: 1)
                    x += widest * scale + padding
                }
            }

            // Ampliado, dois por linha, com a grelha de 1 pt.
            for (index, entry) in zoomed.enumerated() {
                if index % 2 == 0 {
                    y -= zoomHeight
                    background.setFill()
                    NSRect(x: 0, y: y, width: width, height: zoomHeight).fill()
                }
                let x = padding + CGFloat(index % 2) * (widest * 8 + padding)
                let size = NSSize(width: MenuBarIcon.width(for: entry.item.content) * 8, height: 22 * 8)
                let origin = NSPoint(x: x, y: y + padding / 2)
                foreground.withAlphaComponent(0.08).setFill()
                for column in 0...Int(size.width / 8) {
                    NSRect(x: origin.x + CGFloat(column) * 8, y: origin.y, width: 1, height: size.height).fill()
                }
                for row in 0...22 {
                    NSRect(x: origin.x, y: origin.y + CGFloat(row) * 8, width: size.width, height: 1).fill()
                }
                MenuBarIcon.rendered(entry.item, size: size, color: foreground)
                    .draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { print("Falhou o PNG."); return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("Pré-visualização escrita: \(path)")
        print("Linhas: \(cases.map(\.label).joined(separator: "; ")), em claro e em escuro; 1× e 2×; depois 8×")
        print(widthReport())
    }

    /// As larguras, conferidas: o item não muda com os valores, não passa de 72 pt
    /// e os algarismos cabem no corpo.
    static func widthReport() -> String {
        var lines = ["Larguras (pt):"]
        var ok = true
        for content in [BarItem.Content.battery, .batteryWatts, .flowWatts, .watts] {
            let item = MenuBarIcon.itemLength(for: content)
            lines.append(String(format: "  %@: imagem %.1f, item %.1f", "\(content)",
                                MenuBarIcon.width(for: content), item))
            if item > maximumItem { ok = false; lines.append("  FALHOU: passa de 72 pt") }
        }
        let wattsFont = MenuBarIcon.wattsFont
        let slot = MenuBarIcon.slot(wattsFont)
        for text in ["5\u{202F}W", "15\u{202F}W", "120\u{202F}W", "—", BarItem.widestWatts] {
            let width = (text as NSString).size(withAttributes: [.font: wattsFont]).width
            lines.append(String(format: "  «%@» a %.1f pt: %.1f de %.1f", text, wattsFont.pointSize, width, slot))
            if width > slot { ok = false; lines.append("  FALHOU: não cabe") }
        }
        for percent in [100, 80, 50, 20, 5] {
            for charging in [false, true] {
                let group = MenuBarIcon.digitsGroupWidth(percent: percent, bolt: charging)
                if group > MenuBarIcon.digitsRoom {
                    ok = false
                    lines.append(String(format: "  FALHOU: %d %%%@ ocupa %.1f de %.0f", percent,
                                        charging ? " com raio" : "", group, MenuBarIcon.digitsRoom))
                }
            }
        }
        lines.append(String(format: "  a percentagem e os watts: %.1f e %.1f pt", MenuBarIcon.percentFont(80, bolt: true).pointSize,
                            wattsFont.pointSize))
        let tightest = MenuBarIcon.digitsGroupWidth(percent: 100, bolt: true)
        let tightestSize = MenuBarIcon.percentFont(100, bolt: true).pointSize
        lines.append(String(format: "  «100» com o raio: %.1f de %.0f pt dentro do corpo, a %.1f pt", tightest,
                            MenuBarIcon.digitsRoom, tightestSize))
        lines.append(ok ? "  certo" : "  FALHOU")
        return lines.joined(separator: "\n")
    }
}
