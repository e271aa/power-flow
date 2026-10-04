import AppKit

/// Folha de contacto do ícone da barra de menus.
///
/// A barra de menus é o pior sítio para avaliar um ícone a olho: tem 15 pt de
/// altura e fica encostado a outros. Isto desenha-o ao tamanho real e ampliado,
/// sobre fundo claro e escuro, para se ver o que se perde na redução.
enum IconPreview {
    static func render(to path: String) {
        let scales: [CGFloat] = [1, 2, 4, 8]
        let states = MenuBarIcon.State.allCases
        let padding: CGFloat = 16
        let rowHeight: CGFloat = 15 * 8 + padding

        let width = padding + scales.reduce(0) { $0 + 17 * $1 + padding }
        let height = rowHeight * CGFloat(states.count) * 2

        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()

        var y = height
        for (index, isDark) in [false, true].enumerated() {
            _ = index
            let background: NSColor = isDark ? .black : .white
            let foreground: NSColor = isDark ? .white : .black

            for state in states {
                y -= rowHeight
                background.setFill()
                NSRect(x: 0, y: y, width: width, height: rowHeight).fill()

                var x = padding
                for scale in scales {
                    let size = NSSize(width: 17 * scale, height: 15 * scale)
                    let icon = MenuBarIcon.rendered(size: size, state: state, color: foreground)
                    icon.draw(at: NSPoint(x: x, y: y + (rowHeight - size.height) / 2),
                              from: .zero, operation: .sourceOver, fraction: 1)
                    x += size.width + padding
                }
            }
        }

        sheet.unlockFocus()

        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { print("Falhou a renderização."); return }

        try? png.write(to: URL(fileURLWithPath: path))
        print("Pré-visualização escrita: \(path)")
        print("Linhas: claro: ligado, em bateria, indisponível; escuro: os mesmos três")
    }
}
