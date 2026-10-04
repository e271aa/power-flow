import XCTest
@testable import PowerFlowCore

final class LocalizationTests: XCTestCase {
    private func table(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(L10n.tableURL(language: language), "sem Localizable.strings em \(language)")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Os especificadores de formato por ordem de argumento: «%1$@ … %2$@» e «%@ … %@» dão [1, 2].
    private func arguments(_ format: String) -> [Int] {
        let regex = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?[@dfs]")
        var next = 1
        var result: [Int] = []
        for m in regex.matches(in: format, range: NSRange(format.startIndex..., in: format)) {
            if let r = Range(m.range(at: 1), in: format), let n = Int(format[r]) { result.append(n) }
            else { result.append(next); next += 1 }
        }
        return result.sorted()
    }

    func testPTeENTemAsMesmasChaves() throws {
        let pt = try table("pt-PT"), en = try table("en")
        XCTAssertEqual(Set(pt.keys).subtracting(en.keys).sorted(), [], "chaves só em PT")
        XCTAssertEqual(Set(en.keys).subtracting(pt.keys).sorted(), [], "chaves só em EN")
    }

    func testPTeENTemOMesmoNumeroDeArgumentos() throws {
        let pt = try table("pt-PT"), en = try table("en")
        for (key, ptText) in pt {
            guard let enText = en[key] else { continue }
            XCTAssertEqual(arguments(ptText), arguments(enText), "argumentos diferentes em «\(key)»")
        }
    }

    /// Nenhum texto fica com número de exemplo escrito (as notificações levam argumentos).
    func testNotificacoesNaoTemNumerosEscritos() throws {
        for lang in ["pt-PT", "en"] {
            let t = try table(lang)
            for key in t.keys where key.hasPrefix("n_assist") || key.hasPrefix("n_temp") || key.hasPrefix("n_weak") {
                let semArgumentos = t[key]!.replacingOccurrences(of: "%(\\d+\\$)?@", with: "", options: .regularExpression)
                XCTAssertFalse(semArgumentos.contains(where: \.isNumber), "«\(key)» em \(lang) tem um número escrito")
            }
            XCTAssertFalse(t["s_lang_val"]!.contains("Portugu") || t["s_lang_val"]!.contains("English"))
            XCTAssertNil(t["vo_flow"], "vo_flow foi dividido em três (D7c)")
        }
    }

    /// Toda a chave usada em `L10n.string("…")` no código existe na tabela.
    func testChavesUsadasNoCodigoExistem() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let regex = try NSRegularExpression(pattern: "L10n\\.string\\(\"([A-Za-z0-9_]+)\"")
        let pt = try table("pt-PT")
        var used = 0
        for dir in ["Sources/PowerFlow", "Sources/PowerFlowCore"] {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)
            for file in files where file.hasSuffix(".swift") {
                let text = try String(contentsOf: root.appendingPathComponent(dir).appendingPathComponent(file), encoding: .utf8)
                for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let key = String(text[Range(m.range(at: 1), in: text)!])
                    used += 1
                    XCTAssertNotNil(pt[key], "«\(key)» usada em \(file) não existe")
                }
            }
        }
        XCTAssertGreaterThan(used, 10)
    }

    func testEscolhaDaLinguaEArgumentos() {
        defer { L10n.languageOverride = nil }
        L10n.languageOverride = ["en-US"]
        XCTAssertEqual(L10n.language, "en")
        XCTAssertEqual(L10n.languageName, "English")
        XCTAssertEqual(L10n.string("n_temp_t", "42 °C"), "Battery hot: 42 °C")
        XCTAssertEqual(L10n.string("s_lang_val", L10n.languageName), "Same as system (English)")
        L10n.languageOverride = ["pt-PT"]
        XCTAssertEqual(L10n.languageName, "Português")
        XCTAssertEqual(L10n.string("n_weak_b", "20 W", "18 W"),
                       "O adaptador de 20 W não chega para carregar enquanto o Mac gasta 18 W.")
        XCTAssertEqual(L10n.string("chave_inexistente"), "chave_inexistente")
    }
}

final class FormattersTests: XCTestCase {
    private let pt = PFFormat(locale: Locale(identifier: "pt-PT"))
    private let en = PFFormat(locale: Locale(identifier: "en"))
    private let nb = "\u{00A0}"

    func testUnidadesComEspacoNaoSeparavel() {
        XCTAssertEqual(pt.watts(12.34), "12,3\(nb)W")
        XCTAssertEqual(en.watts(12.34), "12.3\(nb)W")
        XCTAssertEqual(pt.percent(80), "80\(nb)%")
        XCTAssertEqual(pt.celsius(42.46), "42,5\(nb)°C")
        XCTAssertEqual(en.celsius(42.46), "42.5\(nb)°C")
        XCTAssertEqual(en.mAh(4500), "4,500\(nb)mAh")
        XCTAssertFalse(pt.watts(1).contains(" "), "sem espaço normal")
    }

    func testDuracoes() {
        XCTAssertEqual(pt.duration(minutes: 80), "1\(nb)h\(nb)20\(nb)min")
        XCTAssertEqual(pt.duration(minutes: 45), "45\(nb)min")
        XCTAssertEqual(pt.duration(minutes: 120), "2\(nb)h\(nb)0\(nb)min")
        XCTAssertEqual(pt.duration(minutes: -5), "0\(nb)min")
    }
}
