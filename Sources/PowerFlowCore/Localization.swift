import Foundation

/// Ponto único de acesso aos textos.
///
/// Os `.lproj` moram em `Sources/PowerFlowCore/Resources/`. Dentro do
/// `PowerFlow.app` o `build.sh` copia-os para `Contents/Resources/` e lêem-se
/// do bundle principal; em `swift run` e nos testes lêem-se do bundle de
/// recursos do SwiftPM. A língua é a do sistema (`-AppleLanguages "(en)"`
/// força-a na linha de comandos).
public enum L10n {
    /// Para os testes e para forçar uma língua. `nil`: a do sistema.
    public nonisolated(unsafe) static var languageOverride: [String]? {
        didSet { cache.reset() }
    }

    /// A língua e as tabelas, guardadas. Procurá-las a cada texto custava
    /// 0,4 pontos de CPU com o painel aberto (Fase 11, `sample` de 10 s).
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var language: String?
        private var tables: [String: Bundle] = [:]
        private var observer: NSObjectProtocol?

        init() {
            // A língua do sistema pode mudar com a app aberta.
            observer = NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.reset() }
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            language = nil
        }

        func language(_ make: () -> String) -> String {
            lock.lock(); defer { lock.unlock() }
            if let language { return language }
            let fresh = make()
            language = fresh
            return fresh
        }

        func table(for language: String, _ make: () -> Bundle) -> Bundle {
            lock.lock(); defer { lock.unlock() }
            if let table = tables[language] { return table }
            let fresh = make()
            tables[language] = fresh
            return fresh
        }
    }

    private static let cache = Cache()

    private static var resources: Bundle {
        Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
    }

    /// Línguas que a app traz, com o nome canónico («pt-PT»). O SwiftPM 5.10
    /// copia `pt-PT.lproj` para o bundle de recursos como `pt-pt.lproj`.
    public static var availableLanguages: [String] {
        resources.localizations.filter { $0 != "Base" }.map { Locale.canonicalLanguageIdentifier(from: $0) }
    }

    /// A pasta `.lproj` de uma língua, com o nome que tem no bundle. O
    /// `path(forResource:ofType:)` distingue maiúsculas: «pt-PT» não encontra
    /// `pt-pt.lproj`, e os textos cairiam para a língua do sistema.
    static func folder(for language: String, among folders: [String]) -> String {
        folders.first { $0.caseInsensitiveCompare(language) == .orderedSame } ?? language
    }

    /// A língua em uso, como nome de `.lproj` («pt-PT», «en»).
    public static var language: String {
        cache.language {
            let preferences = languageOverride ?? Locale.preferredLanguages
            return Bundle.preferredLocalizations(from: availableLanguages, forPreferences: preferences).first
                ?? "pt-PT"
        }
    }

    public static var locale: Locale { Locale(identifier: language) }

    /// Um texto, com argumentos `%@` por ordem (`%1$@`, `%2$@`… quando a ordem muda).
    /// Uma chave que não existe devolve a própria chave, para se ver e para os testes a apanharem.
    public static func string(_ key: String, _ args: CVarArg...) -> String {
        string(key, language: language, args: args)
    }

    public static func string(_ key: String, language: String, args: [CVarArg] = []) -> String {
        let format = table(for: language).localizedString(forKey: key, value: key, table: nil)
        let text = args.isEmpty ? format : String(format: format, locale: Locale(identifier: language), arguments: args)
        return pseudoLocalizes ? pseudo(text) : text
    }

    /// Pseudo-localização (`--pseudo`): cada texto sai 30 % mais comprido e
    /// entre «⟦ ⟧». Um texto cortado perde o «⟧», e vê-se numa captura.
    public nonisolated(unsafe) static var pseudoLocalizes = false

    /// O texto com 30 % mais carateres, contando os parênteses, arredondado para cima.
    public static func pseudo(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let extra = Int((Double(text.count) * 0.3).rounded(.up))
        let padding = String(repeating: "ü", count: max(extra - 2, 0))
        return "⟦" + text + padding + "⟧"
    }

    /// O texto por aplicar, sem argumentos (para os testes de paridade).
    public static func rawString(_ key: String, language: String) -> String? {
        let missing = "\u{0}missing"
        let value = table(for: language).localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    /// O nome da língua em uso, escrito nela própria («Português», «English»).
    public static var languageName: String {
        let locale = self.locale
        guard let code = locale.language.languageCode?.identifier,
              let name = locale.localizedString(forLanguageCode: code), let first = name.first
        else { return language }
        return first.uppercased() + name.dropFirst()
    }

    private static func table(for language: String) -> Bundle {
        cache.table(for: language) {
            let name = folder(for: language, among: resources.localizations)
            guard let path = resources.path(forResource: name, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return resources }
            return bundle
        }
    }

    /// A pasta dos `.lproj` (para o teste de paridade os ler diretamente).
    public static func tableURL(language: String) -> URL? {
        resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil,
                      localization: folder(for: language, among: resources.localizations))
    }
}
