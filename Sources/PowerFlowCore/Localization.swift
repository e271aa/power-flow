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
    public nonisolated(unsafe) static var languageOverride: [String]?

    private static var resources: Bundle {
        Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
    }

    /// Línguas que a app traz.
    public static var availableLanguages: [String] { resources.localizations.filter { $0 != "Base" } }

    /// A língua em uso, como nome de `.lproj` («pt-PT», «en»).
    public static var language: String {
        let preferences = languageOverride ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: availableLanguages, forPreferences: preferences).first
            ?? "pt-PT"
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
        guard let path = resources.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return resources }
        return bundle
    }

    /// A pasta dos `.lproj` (para o teste de paridade os ler diretamente).
    public static func tableURL(language: String) -> URL? {
        resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language)
    }
}
