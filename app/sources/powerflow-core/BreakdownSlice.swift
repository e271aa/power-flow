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
    ///
    /// Sem leitura do SoC não há repartição: o resto não se pode calcular, e
    /// uma barra só com o rail principal não reparte nada.
    public var breakdown: [BreakdownSlice] {
        guard let soc = socPower else { return [] }
        var slices = [BreakdownSlice(kind: .soc, watts: soc)]
        if let main = mainRailPower {
            slices.append(BreakdownSlice(kind: .mainRail, watts: main))
        }
        if let other = otherPower, other > Self.otherThreshold {
            slices.append(BreakdownSlice(kind: .other, watts: other))
        }
        return slices
    }
}

/// As larguras dos segmentos da barra de repartição.
public enum BreakdownLayout {
    /// Proporcionais aos watts, com um mínimo: uma fatia de 0,2 W ao lado de
    /// uma de 30 W continua a ver-se. O que o mínimo dá a uma tira-se às outras.
    public static func widths(for watts: [Double], total: Double,
                              gap: Double = 2, minimum: Double = 4) -> [Double] {
        guard !watts.isEmpty else { return [] }
        let available = max(total - gap * Double(watts.count - 1), 0)
        var widths = [Double](repeating: 0, count: watts.count)
        var fixed = Set<Int>()

        // Cada volta fixa no mínimo as fatias que ficaram abaixo dele e
        // reparte o resto pelas outras, até nenhuma ficar abaixo.
        while true {
            let free = watts.indices.filter { !fixed.contains($0) }
            let room = available - minimum * Double(fixed.count)
            let sum = free.reduce(0) { $0 + max(watts[$1], 0) }
            var changed = false
            for index in free {
                let width = sum > 0 ? room * max(watts[index], 0) / sum : room / Double(free.count)
                if width < minimum {
                    fixed.insert(index)
                    changed = true
                } else {
                    widths[index] = width
                }
            }
            if !changed || fixed.count == watts.count { break }
        }
        for index in fixed { widths[index] = minimum }
        return widths
    }
}
