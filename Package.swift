// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerFlow",
    platforms: [.macOS(.v13)],
    targets: [
        // Camada C: fala com o AppleSMC. É C porque o layout da struct do
        // userclient depende de regras de alinhamento que o compilador C
        // resolve e que seria frágil replicar à mão em Swift.
        .target(
            name: "CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Núcleo sem UI: leitura de hardware, modelo e histórico. Testável.
        .target(
            name: "PowerFlowCore",
            dependencies: ["CSMC"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Executável + UI SwiftUI.
        .executableTarget(
            name: "PowerFlow",
            dependencies: ["PowerFlowCore"]
        ),
    ]
)
