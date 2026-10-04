import Foundation

/// Uma fatia da repartição do consumo.
///
/// A identidade é o tipo de fatia, que é o mesmo de uma leitura para a
/// seguinte. Com um `UUID` novo a cada leitura, o SwiftUI via três fatias a
/// sair e três a entrar todos os segundos, em vez de três fatias a mudar.
public struct BreakdownSlice: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case soc
        case mainRail
        case other
    }

    public let kind: Kind
    public let watts: Double

    public var id: Kind { kind }

    public init(kind: Kind, watts: Double) {
        self.kind = kind
        self.watts = watts
    }
}

extension PowerSnapshot {
    /// Abaixo disto a fatia «Outros» é ruído da subtração e não se mostra.
    private static let otherThreshold: Double = 0.1

    /// Para onde vão os watts dentro do sistema, pela ordem em que se desenham.
    public var breakdown: [BreakdownSlice] {
        var slices: [BreakdownSlice] = []
        if let soc = socPower {
            slices.append(BreakdownSlice(kind: .soc, watts: soc))
        }
        if let main = mainRailPower {
            slices.append(BreakdownSlice(kind: .mainRail, watts: main))
        }
        if let other = otherPower, other > Self.otherThreshold {
            slices.append(BreakdownSlice(kind: .other, watts: other))
        }
        return slices
    }
}
