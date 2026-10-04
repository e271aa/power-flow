import AppKit
import SwiftUI

// Tokens do handoff («Design tokens»: tipografia, espaçamento, raios).
// As cores estão em PFColor.swift. Uma vista usa estes nomes, nunca números soltos.

/// Os 6 papéis de tipografia (SF Pro). Os números levam `.monospacedDigit()` na vista.
enum PFFont {
    /// 28 / 34 · semibold: consumo agora, % no detalhe da bateria.
    static let display = Font.system(size: 28, weight: .semibold)
    /// 15 / 19 · semibold: nós, métricas.
    static let value = Font.system(size: 15, weight: .semibold)
    /// 13 / 17 · semibold: títulos de secção.
    static let title = Font.system(size: 13, weight: .semibold)
    /// 13 / 18 · regular: linhas, menus, definições.
    static let body = Font.system(size: 13)
    /// 12 / 16 · regular: rótulos, legendas, avisos.
    static let secondary = Font.system(size: 12)
    /// 11 / 14 · regular: eixos, notas, rótulos dos nós. O mínimo de texto.
    static let minimum = Font.system(size: 11)

    /// Altura de linha de cada papel (a vista aplica `.lineSpacing(lineHeight - tamanho)` quando precisar).
    enum LineHeight {
        static let display: CGFloat = 34
        static let value: CGFloat = 19
        static let title: CGFloat = 17
        static let body: CGFloat = 18
        static let secondary: CGFloat = 16
        static let minimum: CGFloat = 14
    }
}

/// Um papel de tipografia com a altura de linha do handoff.
///
/// O SwiftUI não tem altura de linha: tem espaço entre linhas. A diferença
/// para a altura natural da fonte reparte-se por cima e por baixo, e entre
/// linhas quando o texto quebra.
struct PFType {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat

    static let display = PFType(size: 28, weight: .semibold, lineHeight: PFFont.LineHeight.display)
    static let value = PFType(size: 15, weight: .semibold, lineHeight: PFFont.LineHeight.value)
    static let title = PFType(size: 13, weight: .semibold, lineHeight: PFFont.LineHeight.title)
    static let body = PFType(size: 13, weight: .regular, lineHeight: PFFont.LineHeight.body)
    static let secondary = PFType(size: 12, weight: .regular, lineHeight: PFFont.LineHeight.secondary)
    static let minimum = PFType(size: 11, weight: .regular, lineHeight: PFFont.LineHeight.minimum)
    /// Uma palavra no lugar de um valor («Em pausa», «Desligado»), na linha de um valor.
    static let valueWord = PFType(size: 13, weight: .medium, lineHeight: PFFont.LineHeight.value)

    var font: Font { .system(size: size, weight: weight) }

    /// O que falta à altura natural da fonte para chegar à altura de linha.
    var extraLeading: CGFloat {
        lineHeight - NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: size))
    }
}

extension View {
    func pfType(_ type: PFType) -> some View {
        let extra = type.extraLeading
        return font(type.font)
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}

/// Espaçamento, base 4.
enum PFSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24

    /// Margem do popover.
    static let popoverMargin: CGFloat = 16
    /// Altura das linhas clicáveis.
    static let rowPopover: CGFloat = 32
    static let rowSettings: CGFloat = 40
}

/// Raios (`.continuous`).
enum PFRadius {
    static let popover: CGFloat = 12
    static let card: CGFloat = 10
    static let menu: CGFloat = 9
    static let banner: CGFloat = 8
    static let tile: CGFloat = 7
    static let button: CGFloat = 6
    static let segment: CGFloat = 5
    static let breakdownBar: CGFloat = 3
    static let appBar: CGFloat = 2
}
