import XCTest
@testable import PowerFlowCore

/// O URL do repositório que o «Código-fonte» e o «Reportar no GitHub» abrem.
final class RepositoryTests: XCTestCase {
    func testCodigoFonteAbreORepositorio() {
        XCTAssertEqual(Repository.url.absoluteString, "https://github.com/e271aa/power-flow")
    }

    func testReportarAbreUmProblemaNovo() {
        XCTAssertEqual(Repository.newIssueURL.absoluteString,
                       "https://github.com/e271aa/power-flow/issues/new")
    }
}
