// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerFlow",
    defaultLocalization: "pt-PT",
    platforms: [.macOS(.v13)],
    targets: [
        // Camada C: fala com o AppleSMC. É C porque o layout da struct do
        // userclient depende de regras de alinhamento que o compilador C
        // resolve e que seria frágil replicar à mão em Swift.
        .target(
            name: "CSMC",
            path: "sources/csmc",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Núcleo sem UI: leitura de hardware, modelo e histórico. Testável.
        .target(
            name: "PowerFlowCore",
            dependencies: ["CSMC"],
            path: "sources/powerflow-core",
            // Os .lproj com os textos PT-PT e EN. O build.sh copia-os também para o bundle da app.
            resources: [.process("resources")],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Executável + UI SwiftUI.
        .executableTarget(
            name: "PowerFlow",
            dependencies: ["PowerFlowCore"],
            path: "sources/powerflow"
        ),
        // Testes XCTest do núcleo. Não tocam no hardware: constroem os
        // instantâneos à mão, para correrem iguais em qualquer Mac.
        .testTarget(
            name: "PowerFlowCoreTests",
            dependencies: ["PowerFlowCore"],
            path: "tests",
            // Lido pelo caminho do ficheiro, não como recurso do bundle de testes.
            exclude: ["fixtures"]
        ),
    ]
)
