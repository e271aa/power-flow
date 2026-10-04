import Foundation
import ServiceManagement

/// «Abrir ao iniciar sessão», pelo `SMAppService`. Não há preferência nossa:
/// quem sabe se está ligado é o sistema, e o utilizador pode desligá-lo em
/// Definições do Sistema sem a app saber.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Ligado de facto. `requiresApproval` não conta: o sistema registou o
    /// pedido, mas o utilizador ainda não o aprovou.
    static var isEnabled: Bool { status == .enabled }

    static var needsApproval: Bool { status == .requiresApproval }

    static func set(_ on: Bool) throws {
        let service = SMAppService.mainApp
        if on {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// O estado por extenso, para o `--login-item`.
    static var statusName: String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "desconhecido"
        }
    }
}
