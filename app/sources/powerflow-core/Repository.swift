import Foundation

/// O repositório público da app. É o único sítio com o URL: o
/// «Código-fonte» das Definições e o «Reportar no GitHub» do painel lêem-no daqui.
public enum Repository {
    public static let url = URL(string: "https://github.com/e271aa/power-flow")!

    /// A página de um problema novo, para o «Reportar no GitHub».
    public static let newIssueURL = url.appendingPathComponent("issues/new")
}
