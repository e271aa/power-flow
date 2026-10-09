// PFColor.swift — derivado de tests/fixtures/powerflow-data.json.
// Valores em Display P3, convertidos de OKLCH. Cada cor resolve claro / escuro / alto contraste
// pela aparência efetiva, por isso funciona sem Asset Catalog (a app constrói-se só com as CLT).
// Regra: green / amber / blue (e blue2, rest) NUNCA são texto — para texto usar *Ink.
import AppKit
import SwiftUI

enum PFColor {
    /// Material do popover (NSVisualEffectView .popover)
    static let bg = dynamic("pf.bg",
        light: (0.9648, 0.9674, 0.9722, 0.9500), dark: (0.1328, 0.1365, 0.1434, 0.9500),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0435, 0.0435, 0.0435, 1.0000))
    /// Texto principal (labelColor)
    static let fg = dynamic("pf.fg",
        light: (0.0918, 0.0953, 0.1019, 1.0000), dark: (0.9582, 0.9608, 0.9657, 1.0000),
        hcLight: (0.0000, 0.0000, 0.0000, 1.0000), hcDark: (1.0000, 1.0000, 1.0000, 1.0000))
    /// Texto secundário — único cinzento para texto, ≥ 4,5:1
    static let fg2 = dynamic("pf.fg2",
        light: (0.3173, 0.3236, 0.3355, 1.0000), dark: (0.6881, 0.6942, 0.7056, 1.0000),
        hcLight: (0.1599, 0.1599, 0.1599, 1.0000), hcDark: (0.8442, 0.8442, 0.8442, 1.0000))
    /// Separadores
    static let sep = dynamic("pf.sep",
        light: (0.0918, 0.0953, 0.1019, 0.1100), dark: (1.0000, 1.0000, 1.0000, 0.1200),
        hcLight: (0.0000, 0.0000, 0.0000, 0.5000), hcDark: (1.0000, 1.0000, 1.0000, 0.5000))
    /// Fundo de controlos, hover de linhas
    static let fill = dynamic("pf.fill",
        light: (0.0918, 0.0953, 0.1019, 0.0600), dark: (1.0000, 1.0000, 1.0000, 0.0800),
        hcLight: (0.0000, 0.0000, 0.0000, 0.1000), hcDark: (1.0000, 1.0000, 1.0000, 0.1400))
    /// Fundo dos nós do diagrama
    static let node = dynamic("pf.node",
        light: (1.0000, 1.0000, 1.0000, 0.8000), dark: (1.0000, 1.0000, 1.0000, 0.0600),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0435, 0.0435, 0.0435, 1.0000))
    /// Contorno de nós e cartões
    static let nodeBorder = dynamic("pf.nodeBorder",
        light: (0.0918, 0.0953, 0.1019, 0.1000), dark: (1.0000, 1.0000, 1.0000, 0.1100),
        hcLight: (0.0000, 0.0000, 0.0000, 0.7500), hcDark: (1.0000, 1.0000, 1.0000, 0.7500))
    /// Segmento selecionado
    static let segSel = dynamic("pf.segSel",
        light: (1.0000, 1.0000, 1.0000, 1.0000), dark: (0.3408, 0.3450, 0.3531, 1.0000),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.3886, 0.3886, 0.3886, 1.0000))
    static let outline = dynamic("pf.outline",
        light: (0.0000, 0.0000, 0.0000, 0.1400), dark: (0.0000, 0.0000, 0.0000, 0.5000),
        hcLight: (0.0000, 0.0000, 0.0000, 0.8000), hcDark: (1.0000, 1.0000, 1.0000, 0.7000))
    /// Adaptador — traço e preenchimento (não-texto)
    static let green = dynamic("pf.green",
        light: (0.2051, 0.4548, 0.3143, 1.0000), dark: (0.3009, 0.5684, 0.4373, 1.0000),
        hcLight: (0.1832, 0.3812, 0.2073, 1.0000), hcDark: (0.3009, 0.5684, 0.4373, 1.0000))
    /// Adaptador — texto, ícones, chevrons
    static let greenInk = dynamic("pf.greenInk",
        light: (0.1766, 0.4097, 0.2260, 1.0000), dark: (0.5261, 0.8408, 0.5782, 1.0000),
        hcLight: (0.1032, 0.2896, 0.1453, 1.0000), hcDark: (0.6431, 0.9392, 0.6881, 1.0000))
    /// Adaptador — fundo de ícone
    static let greenSoft = dynamic("pf.greenSoft",
        light: (0.2051, 0.4548, 0.3143, 0.1600), dark: (0.3009, 0.5684, 0.4373, 0.2000),
        hcLight: (0.1832, 0.3812, 0.2073, 0.1800), hcDark: (0.3009, 0.5684, 0.4373, 0.2200))
    /// Bateria — traço e preenchimento (não-texto)
    static let amber = dynamic("pf.amber",
        light: (0.7404, 0.4959, 0.1892, 1.0000), dark: (0.7596, 0.5139, 0.2096, 1.0000),
        hcLight: (0.6985, 0.4403, 0.1518, 1.0000), hcDark: (0.7596, 0.5139, 0.2096, 1.0000))
    /// Bateria — texto, ícones, avisos
    static let amberInk = dynamic("pf.amberInk",
        light: (0.5542, 0.3358, 0.1068, 1.0000), dark: (0.9544, 0.7725, 0.4507, 1.0000),
        hcLight: (0.4069, 0.2231, 0.0610, 1.0000), hcDark: (0.9969, 0.8477, 0.5414, 1.0000))
    /// Bateria — fundo de aviso e área do gráfico
    static let amberSoft = dynamic("pf.amberSoft",
        light: (0.7404, 0.4959, 0.1892, 0.2000), dark: (0.7596, 0.5139, 0.2096, 0.2000),
        hcLight: (0.6985, 0.4403, 0.1518, 0.2000), hcDark: (0.7596, 0.5139, 0.2096, 0.2200))
    /// Sistema — traço, SoC na repartição
    static let blue = dynamic("pf.blue",
        light: (0.2735, 0.4910, 0.8615, 1.0000), dark: (0.3495, 0.5713, 0.9481, 1.0000),
        hcLight: (0.1140, 0.3303, 0.7465, 1.0000), hcDark: (0.3495, 0.5713, 0.9481, 1.0000))
    /// Sistema — texto e ícones
    static let blueInk = dynamic("pf.blueInk",
        light: (0.1524, 0.3409, 0.7070, 1.0000), dark: (0.5359, 0.7334, 0.9861, 1.0000),
        hcLight: (0.0567, 0.2156, 0.5816, 1.0000), hcDark: (0.6673, 0.8347, 1.0000, 1.0000))
    /// Sistema — fundo de ícone, área do gráfico
    static let blueSoft = dynamic("pf.blueSoft",
        light: (0.2735, 0.4910, 0.8615, 0.1600), dark: (0.3495, 0.5713, 0.9481, 0.2200),
        hcLight: (0.1140, 0.3303, 0.7465, 0.1600), hcDark: (0.3495, 0.5713, 0.9481, 0.2400))
    /// Repartição: Ecrã e I/O
    static let blue2 = dynamic("pf.blue2",
        light: (0.1449, 0.3507, 0.5243, 1.0000), dark: (0.2084, 0.4581, 0.5993, 1.0000),
        hcLight: (0.3490, 0.5921, 0.7711, 1.0000), hcDark: (0.2084, 0.4581, 0.5993, 1.0000))
    /// Repartição: Resto da placa (tracejado)
    static let rest = dynamic("pf.rest",
        light: (0.5308, 0.5377, 0.5508, 1.0000), dark: (0.5709, 0.5779, 0.5912, 1.0000),
        hcLight: (0.3886, 0.3886, 0.3886, 1.0000), hcDark: (0.5774, 0.5774, 0.5774, 1.0000))
    /// Aresta sem caudal (tracejada)
    static let track = dynamic("pf.track",
        light: (0.0918, 0.0953, 0.1019, 0.2200), dark: (1.0000, 1.0000, 1.0000, 0.2200),
        hcLight: (0.0000, 0.0000, 0.0000, 0.4500), hcDark: (1.0000, 1.0000, 1.0000, 0.5000))
    /// Botão primário, seleção (controlAccentColor)
    static let accent = dynamic("pf.accent",
        light: (0.1291, 0.3771, 0.8180, 1.0000), dark: (0.1759, 0.4070, 0.8243, 1.0000),
        hcLight: (0.0601, 0.2990, 0.7401, 1.0000), hcDark: (0.3834, 0.6174, 0.9939, 1.0000))
    static let onAccent = dynamic("pf.onAccent",
        light: (1.0000, 1.0000, 1.0000, 1.0000), dark: (1.0000, 1.0000, 1.0000, 1.0000),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0000, 0.0000, 0.0000, 1.0000))
    /// Fundo da janela de Definições
    static let win = dynamic("pf.win",
        light: (0.9387, 0.9412, 0.9461, 1.0000), dark: (0.1143, 0.1179, 0.1247, 1.0000),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0223, 0.0223, 0.0223, 1.0000))
    /// Caixa de grupo (Form .grouped)
    static let group = dynamic("pf.group",
        light: (1.0000, 1.0000, 1.0000, 1.0000), dark: (1.0000, 1.0000, 1.0000, 0.0500),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0518, 0.0518, 0.0518, 1.0000))
    static let control = dynamic("pf.control",
        light: (1.0000, 1.0000, 1.0000, 1.0000), dark: (1.0000, 1.0000, 1.0000, 0.1600),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.1792, 0.1792, 0.1792, 1.0000))
    /// Menus e notificações
    static let menuBg = dynamic("pf.menuBg",
        light: (0.9648, 0.9674, 0.9722, 0.9700), dark: (0.1660, 0.1698, 0.1770, 0.9700),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0435, 0.0435, 0.0435, 1.0000))
    static let bar = dynamic("pf.bar",
        light: (0.9547, 0.9616, 0.9704, 0.8800), dark: (0.0571, 0.0604, 0.0667, 0.8800),
        hcLight: (1.0000, 1.0000, 1.0000, 1.0000), hcDark: (0.0000, 0.0000, 0.0000, 1.0000))
    static let switchOff = dynamic("pf.switchOff",
        light: (0.0918, 0.0953, 0.1019, 0.1300), dark: (1.0000, 1.0000, 1.0000, 0.1700),
        hcLight: (0.0000, 0.0000, 0.0000, 0.3200), hcDark: (1.0000, 1.0000, 1.0000, 0.3800))

    typealias RGBA = (Double, Double, Double, Double)

    /// Usa os valores de alto contraste seja qual for a definição do sistema.
    /// Serve o `--snapshot --appearance hc-light` e `hc-dark`.
    static var forcesIncreasedContrast = false

    private static func dynamic(_ name: String, light: RGBA, dark: RGBA,
                                hcLight: RGBA, hcDark: RGBA) -> Color {
        let ns = NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua,
                .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            // O SwiftUI resolve as cores com a aparência clara ou escura e não
            // passa a variante de alto contraste (medido na Fase 4: com a
            // aparência de alto contraste na vista, vinham os valores normais).
            // Por isso pergunta-se também ao sistema.
            let isHighContrast = match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
                || forcesIncreasedContrast
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

            let c: RGBA
            switch (isDark, isHighContrast) {
            case (false, false): c = light
            case (true, false):  c = dark
            case (false, true):  c = hcLight
            case (true, true):   c = hcDark
            }
            return NSColor(displayP3Red: c.0, green: c.1, blue: c.2, alpha: c.3)
        }
        return Color(nsColor: ns)
    }
}
