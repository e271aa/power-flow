import Foundation

/// O que uma segunda abertura da app pede à instância que já está a correr.
///
/// Quem chega em segundo lugar não arranca: manda um destes pedidos e sai.
enum RemoteCommand: String {
    case showPanel = "local.powerflow.PowerFlow.showPanel"
    /// Abre o painel e deixa-o aberto até ordem em contrário. Serve o
    /// `--open-panel`: uma medição de 60 s não pode acabar ao primeiro
    /// clique noutra janela.
    case holdPanel = "local.powerflow.PowerFlow.holdPanel"
    case closePanel = "local.powerflow.PowerFlow.closePanel"

    var name: Notification.Name { Notification.Name(rawValue) }

    func post() {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
