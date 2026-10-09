import Foundation

/// Garante que só há uma instância da app, com um trinco sobre um ficheiro.
///
/// O sistema só evita lançar duas vezes o mesmo bundle pelo mesmo caminho.
/// Uma cópia noutra pasta, `open -n` ou o binário lançado à mão passam todos.
/// O `flock` não depende de como o processo foi lançado, é atómico, e o
/// núcleo liberta-o quando o processo morre, mesmo que morra mal.
public final class InstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public enum Outcome {
        /// O trinco é desta instância. Tem de guardar o objeto enquanto
        /// correr: o trinco solta-se quando o objeto é libertado.
        case acquired(InstanceLock)
        /// Outra instância já o tem.
        case heldByAnother
        /// Não foi possível abrir o ficheiro. Não prova que haja outra
        /// instância, por isso quem chama deve continuar a arrancar.
        case unavailable
    }

    public static func acquire(at url: URL) -> Outcome {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return .unavailable }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let isHeld = errno == EWOULDBLOCK
            close(descriptor)
            return isHeld ? .heldByAnother : .unavailable
        }
        return .acquired(InstanceLock(descriptor: descriptor))
    }

    /// O ficheiro do trinco desta app, igual para todas as cópias do bundle.
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PowerFlow/instance.lock")
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
