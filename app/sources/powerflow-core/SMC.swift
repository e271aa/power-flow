import CSMC
import Foundation

/// Ligação de leitura ao System Management Controller.
///
/// Só lê. Escrever no SMC (o que o AlDente faz para limitar a carga) exigiria
/// um helper privilegiado; ler não exige privilégio nenhum.
public final class SMC {
    public static let shared = SMC()

    private let lock = NSLock()
    private var isOpen = false

    private init() {}

    @discardableResult
    public func open() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isOpen { return true }
        isOpen = csmc_open()
        return isOpen
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        if isOpen { csmc_close(); isOpen = false }
    }

    /// Lê uma chave. `nil` quando a chave não existe neste modelo de Mac —
    /// é assim que a app sobrevive em hardware que não foi testado.
    public func read(_ key: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return nil }
        var value: Double = 0
        var type = [CChar](repeating: 0, count: 8)
        guard csmc_read(key, &value, &type) else { return nil }
        return value
    }

    /// Tipo SMC declarado para uma chave ("flt ", "ui16", ...), para diagnóstico.
    public func type(of key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return nil }
        var value: Double = 0
        var type = [CChar](repeating: 0, count: 8)
        guard csmc_read(key, &value, &type) else { return nil }
        return String(cString: type)
    }

    /// Todas as chaves expostas pelo SMC. Usado pelo modo `--dump`.
    public func allKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard isOpen else { return [] }
        let count = csmc_key_count()
        guard count > 0, count < 100_000 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        var buffer = [CChar](repeating: 0, count: 8)
        for index in 0..<count where csmc_key_at(index, &buffer) {
            keys.append(String(cString: buffer))
        }
        return keys
    }
}
