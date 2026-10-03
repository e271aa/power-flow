import Foundation

/// Buffer circular com o histórico recente de potência.
///
/// Uma hora a 1 Hz são 3600 amostras. Não persiste em disco: o histórico
/// recomeça a cada arranque, o que é aceitável para uma app de barra de menus.
public final class PowerHistory {
    public struct Sample: Sendable {
        public let timestamp: Date
        public let systemTotal: Double
        public let adapterInput: Double
        public let batteryFlow: Double   // positivo a carregar, negativo a descarregar
    }

    public let capacity: Int
    private var storage: [Sample] = []
    private var writeIndex = 0

    public init(capacity: Int = 3600) {
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public func append(_ snapshot: PowerSnapshot) {
        let flow = snapshot.adapterToBattery - snapshot.batteryToSystem
        let sample = Sample(
            timestamp: snapshot.timestamp,
            systemTotal: snapshot.systemTotal ?? 0,
            adapterInput: snapshot.adapterInput ?? 0,
            batteryFlow: flow
        )
        if storage.count < capacity {
            storage.append(sample)
        } else {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// Amostras por ordem cronológica.
    public var samples: [Sample] {
        guard storage.count == capacity else { return storage }
        return Array(storage[writeIndex...] + storage[..<writeIndex])
    }

    /// As últimas `seconds` amostras, para o gráfico.
    public func recent(seconds: Int) -> [Sample] {
        let all = samples
        return Array(all.suffix(seconds))
    }

    public var peakSystemTotal: Double {
        samples.map(\.systemTotal).max() ?? 0
    }
}
