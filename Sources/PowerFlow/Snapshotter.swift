import AppKit
import SwiftUI

/// Renderiza a interface para um PNG, sem abrir janela nem capturar o ecrã.
///
/// Serve para verificar o aspeto do diagrama durante o desenvolvimento e para
/// juntar uma imagem a um relatório de problema: `PowerFlow --snapshot out.png`.
@MainActor
enum Snapshotter {
    static func render(to path: String, warmUpSeconds: Double) {
        let monitor = PowerMonitor()

        // Deixar o histórico encher, senão o gráfico sai vazio.
        let deadline = Date().addingTimeInterval(warmUpSeconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        let renderer = ImageRenderer(content: ContentView(monitor: monitor))
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("Falhou a renderização.")
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("Imagem escrita: \(path)")
        } catch {
            print("Falhou a escrita: \(error.localizedDescription)")
        }
    }
}
