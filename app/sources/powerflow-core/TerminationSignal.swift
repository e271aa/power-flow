import Foundation

/// Faz de um sinal de fim (o `kill` sem opções manda `SIGTERM`) um fecho
/// ordenado, em vez de o processo morrer onde está.
///
/// Sem isto o `SIGTERM` mata a app sem passar pelo `applicationWillTerminate`,
/// e o intervalo de 10 min do histórico que ia a meio perde-se.
public final class TerminationSignal {
    private let number: Int32
    private let source: DispatchSourceSignal

    /// `handler` corre na `queue` quando o sinal chega. Tem de guardar o
    /// objeto enquanto quiser apanhar o sinal.
    public init(_ number: Int32 = SIGTERM, queue: DispatchQueue = .main,
                handler: @escaping () -> Void) {
        self.number = number
        // A ação por omissão mata o processo antes de a fonte ver o sinal.
        signal(number, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: number, queue: queue)
        source.setEventHandler(handler: handler)
        source.resume()
    }

    deinit {
        source.cancel()
        signal(number, SIG_DFL)
    }
}
