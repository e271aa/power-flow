import XCTest

/// Guarda as cores da paleta. Lê os temas de `fixtures/powerflow-data.json`,
/// que é a fonte de verdade (OKLCH), e mede-os com as mesmas fórmulas do validador de paleta
/// (`validate_palette.js`): ΔE em OKLab ×100, daltonismo simulado com Machado et al. (2009) a 100 %, contraste WCAG.
final class PaletteTests: XCTestCase {
    private static let themes = ["light", "dark", "hcLight", "hcDark"]
    /// A pasta `app/`.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private struct OKLCH { let l, c, h, alpha: Double }
    private typealias RGB = [Double]

    private func loadThemes() throws -> [String: [String: String]] {
        let url = Self.root.appendingPathComponent("tests/fixtures/powerflow-data.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["themes"] as? [String: [String: String]])
    }

    private func parse(_ value: String) throws -> OKLCH {
        let regex = try NSRegularExpression(pattern: #"^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*/\s*([\d.]+))?\s*\)$"#)
        let match = try XCTUnwrap(regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                                  "não é oklch(): \(value)")
        func number(_ i: Int) -> Double? { Range(match.range(at: i), in: value).flatMap { Double(value[$0]) } }
        return OKLCH(l: number(1)!, c: number(2)!, h: number(3)!, alpha: number(4) ?? 1)
    }

    private func color(_ themes: [String: [String: String]], _ theme: String, _ token: String) throws -> OKLCH {
        try parse(try XCTUnwrap(themes[theme]?[token], "falta \(theme).\(token)"))
    }

    // MARK: Conversões

    private func linearSRGB(_ c: OKLCH) -> RGB {
        let a = c.c * cos(c.h * .pi / 180), b = c.c * sin(c.h * .pi / 180)
        let l = pow(c.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(c.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(c.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
    }

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
    private func encode(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }
    private func decode(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

    /// sRGB linear da cor tal como o validador a recebe: em hex de 8 bits, cortada ao gamut.
    private func screen(_ c: OKLCH) -> RGB {
        linearSRGB(c).map { decode((encode(clamp($0)) * 255).rounded() / 255) }
    }

    private func displayP3(_ c: OKLCH) -> RGB {
        let rgb = linearSRGB(c)
        let x = 0.4123907993 * rgb[0] + 0.3575843394 * rgb[1] + 0.1804807884 * rgb[2]
        let y = 0.2126390059 * rgb[0] + 0.7151686788 * rgb[1] + 0.0721923154 * rgb[2]
        let z = 0.0193308187 * rgb[0] + 0.1191947798 * rgb[1] + 0.9505321522 * rgb[2]
        return [2.4934969119 * x - 0.9313836179 * y - 0.4027107845 * z,
                -0.8294889696 * x + 1.7626640603 * y + 0.0236246858 * z,
                0.0358458302 * x - 0.0761723893 * y + 0.9568845240 * z].map { encode(clamp($0)) }
    }

    private func oklab(_ rgb: RGB) -> [Double] {
        let l = cbrt(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1] + 0.0514459929 * rgb[2])
        let m = cbrt(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1] + 0.1073969566 * rgb[2])
        let s = cbrt(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1] + 0.6299787005 * rgb[2])
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }

    // MARK: Medidas

    private enum Vision: String, CaseIterable {
        case protan, deutan, tritan
        var matrix: [[Double]] {
            switch self {
            case .protan: return [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
            case .deutan: return [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
            case .tritan: return [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
            }
        }
    }

    private func deltaE(_ a: OKLCH, _ b: OKLCH, _ vision: Vision? = nil) -> Double {
        func seen(_ c: OKLCH) -> [Double] {
            let rgb = screen(c)
            guard let m = vision?.matrix else { return oklab(rgb) }
            return oklab(m.map { clamp($0[0] * rgb[0] + $0[1] * rgb[1] + $0[2] * rgb[2]) })
        }
        let p = seen(a), q = seen(b)
        return 100 * sqrt(pow(p[0] - q[0], 2) + pow(p[1] - q[1], 2) + pow(p[2] - q[2], 2))
    }

    private func luminance(_ rgb: RGB) -> Double { 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] }

    private func contrast(_ a: OKLCH, on b: OKLCH) -> Double {
        let la = luminance(screen(a)), lb = luminance(screen(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: Testes

    /// E8: verde, âmbar e azul do diagrama distinguem-se dois a dois em protanopia, deuteranopia
    /// e tritanopia (ΔE ≥ 8) e com visão normal (ΔE ≥ 15).
    func testCoresDoFluxoDistinguemSeComDaltonismo() throws {
        let themes = try loadThemes()
        for theme in Self.themes {
            for (a, b) in [("green", "amber"), ("green", "blue"), ("amber", "blue")] {
                let ca = try color(themes, theme, a), cb = try color(themes, theme, b)
                for vision in Vision.allCases {
                    let d = deltaE(ca, cb, vision)
                    XCTAssertGreaterThanOrEqual(d, 8, "\(theme): \(a)↔\(b) em \(vision.rawValue) com ΔE \(oneDecimal(d))")
                }
                XCTAssertGreaterThanOrEqual(deltaE(ca, cb), 15, "\(theme): \(a)↔\(b) com visão normal")
            }
        }
    }

    /// E9 e E10: as cores de grandeza são marcas gráficas e têm 3:1 contra o fundo do painel.
    func testMarcasGraficasTemContrasteDe3() throws {
        let themes = try loadThemes()
        for theme in Self.themes {
            let bg = try color(themes, theme, "bg")
            for token in ["green", "amber", "blue", "blue2", "rest"] {
                let ratio = contrast(try color(themes, theme, token), on: bg)
                XCTAssertGreaterThanOrEqual(ratio, 3, "\(theme).\(token) com \(oneDecimal(ratio)):1 contra bg")
            }
        }
    }

    /// E10: os segmentos vizinhos da barra de repartição distinguem-se com visão normal (ΔE ≥ 15)
    /// e com daltonismo vermelho-verde (ΔE ≥ 8). `blue`↔`rest` são vizinhos quando falta o Ecrã e I/O.
    func testSegmentosDaReparticaoDistinguemSe() throws {
        let themes = try loadThemes()
        for theme in Self.themes {
            for (a, b) in [("blue", "blue2"), ("blue2", "rest"), ("blue", "rest")] {
                let ca = try color(themes, theme, a), cb = try color(themes, theme, b)
                XCTAssertGreaterThanOrEqual(deltaE(ca, cb), 15, "\(theme): \(a)↔\(b) com visão normal")
                for vision in [Vision.protan, .deutan] {
                    let d = deltaE(ca, cb, vision)
                    XCTAssertGreaterThanOrEqual(d, 8, "\(theme): \(a)↔\(b) em \(vision.rawValue) com ΔE \(oneDecimal(d))")
                }
            }
        }
    }

    /// O texto usa `fg`, `fg2` e as versões `*Ink`, todas com 4,5:1 contra o fundo do painel.
    func testTextoTemContrasteDe4e5() throws {
        let themes = try loadThemes()
        for theme in Self.themes {
            let bg = try color(themes, theme, "bg")
            for token in ["fg", "fg2", "greenInk", "amberInk", "blueInk"] {
                let ratio = contrast(try color(themes, theme, token), on: bg)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme).\(token) com \(oneDecimal(ratio)):1 contra bg")
            }
        }
    }

    /// O `PFColor.swift` corresponde ao JSON, em Display P3. Se alguém mudar um e não o outro, falha aqui.
    func testPFColorCorrespondeAoJSON() throws {
        let themes = try loadThemes()
        let swift = try String(contentsOf: Self.root.appendingPathComponent("sources/powerflow/PFColor.swift"), encoding: .utf8)
        let tuple = #"\(([^)]*)\)"#
        let tokens = try XCTUnwrap(themes["light"]).keys.filter { $0 != "shadow" && $0 != "desk" }
        XCTAssertFalse(tokens.isEmpty)
        for token in tokens {
            let pattern = #"static let \#(token) = dynamic\("pf\.\#(token)",\s*light: \#(tuple), dark: \#(tuple),\s*hcLight: \#(tuple), hcDark: \#(tuple)\)"#
            let regex = try NSRegularExpression(pattern: pattern)
            let match = try XCTUnwrap(regex.firstMatch(in: swift, range: NSRange(swift.startIndex..., in: swift)),
                                      "PFColor.swift não tem o token \(token)")
            for (index, theme) in Self.themes.enumerated() {
                let c = try color(themes, theme, token)
                let expected = (displayP3(c) + [c.alpha]).map { String(format: "%.4f", $0) }.joined(separator: ", ")
                let found = String(swift[try XCTUnwrap(Range(match.range(at: index + 1), in: swift))])
                XCTAssertEqual(found, expected, "\(theme).\(token) difere do JSON")
            }
        }
    }
}
