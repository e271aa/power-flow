import AppKit
import PowerFlowCore
@preconcurrency import UserNotifications

/// As notificações do sistema para os alertas.
///
/// O `UNUserNotificationCenter` só funciona dentro de um bundle: fora dele
/// (`swift run`, `.build/debug/PowerFlow`) o `current()` termina o processo
/// com uma exceção. Tudo passa por `center`, que fica `nil` fora do `.app`.
///
/// A autorização não se pede ao arrancar: pede-se quando o utilizador liga um
/// alerta nas Definições e, se nunca o fez (dois vêm ligados por omissão),
/// quando o primeiro alerta dispara.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotifier()

    /// Clicar numa notificação chama isto: abre o painel.
    var onOpen: (() -> Void)?

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private var center: UNUserNotificationCenter? {
        Self.isAvailable ? UNUserNotificationCenter.current() : nil
    }

    /// Tem de correr antes de o arranque acabar, para um clique numa
    /// notificação que lançou a app chegar ao delegado.
    func install(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        center?.delegate = self
    }

    /// Pede autorização se ainda não foi pedida. `completion` diz se pode notificar.
    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard let center else { completion?(false); return }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            guard status == .notDetermined else {
                DispatchQueue.main.async { completion?(status == .authorized || status == .provisional) }
                return
            }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error { NSLog("PowerFlow: autorização de notificações: \(error.localizedDescription)") }
                DispatchQueue.main.async { completion?(granted) }
            }
        }
    }

    /// Mostra o alerta. Um identificador por tipo: um aviso novo do mesmo
    /// alerta substitui o anterior no Centro de Notificações.
    func post(_ event: AlertEvent, completion: ((Error?) -> Void)? = nil) {
        requestAuthorizationIfNeeded { [weak self] allowed in
            guard allowed, let center = self?.center else {
                NSLog("PowerFlow: alerta \(event.kind.rawValue) sem notificação (não autorizada)")
                completion?(NotifierError.notAuthorized)
                return
            }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: Self.identifier(event.kind),
                                                content: content, trigger: nil)
            center.add(request) { error in
                if let error { NSLog("PowerFlow: notificação: \(error.localizedDescription)") }
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    static func identifier(_ kind: AlertKind) -> String { "pf.alert.\(kind.rawValue)" }

    /// O estado da autorização e as notificações ainda no Centro, para o `--notify-test`.
    func status(_ completion: @escaping (String, [String]) -> Void) {
        guard let center else { completion("sem bundle", []); return }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            center.getDeliveredNotifications { delivered in
                let ids = delivered.map(\.request.identifier)
                DispatchQueue.main.async { completion(Self.describe(status), ids) }
            }
        }
    }

    private nonisolated static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "por pedir"
        case .denied: "recusada"
        case .authorized: "autorizada"
        case .provisional: "provisória"
        @unknown default: "desconhecida (\(status.rawValue))"
        }
    }

    /// Abre Definições do Sistema › Notificações › PowerFlow.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "local.powerflow.PowerFlow"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    enum NotifierError: Error { case notAuthorized }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { AlertNotifier.shared.onOpen?() }
            completionHandler()
        }
    }

    /// Com a app à frente (as Definições abertas), a notificação aparece na mesma.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// `PowerFlow --notify-test assist|temperature|weakAdapter`: manda uma
/// notificação real, com os números deste momento, pelo mesmo caminho dos
/// alertas, e diz se o sistema a aceitou e se ficou no Centro de Notificações.
/// Na primeira vez o macOS pergunta se a app pode notificar; espera-se pela
/// resposta até `answerWithin` segundos.
@MainActor
enum NotifyTest {
    static func run(_ kind: AlertKind, answerWithin: TimeInterval = 120) -> Never {
        guard AlertNotifier.isAvailable else {
            print("Fora do bundle não há notificações. Corre o binário de dentro do PowerFlow.app.")
            exit(2)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        // A temperatura vem do SMC; sem isto o título sairia com «—».
        _ = SMCCatalog.shared.prepare()
        let notifier = AlertNotifier.shared
        notifier.install {}
        func wait(_ done: () -> Bool, seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        }

        var ready = false
        notifier.status { status, _ in print("autorização antes : \(status)"); ready = true }
        wait({ ready }, seconds: 5)

        let event = AlertMonitor.event(kind, snapshot: PowerSampler.sample())
        print("a enviar          : «\(event.title)» «\(event.body)»")
        var sent = false
        notifier.post(event) { error in
            print("resposta          : \(error.map { "erro, \($0)" } ?? "aceite pelo sistema")")
            sent = true
        }
        wait({ sent }, seconds: answerWithin)
        if !sent { print("resposta          : nenhuma em \(Int(answerWithin)) s (a pergunta de autorização ficou por responder?)") }

        RunLoop.main.run(until: Date().addingTimeInterval(2))
        var checked = false
        notifier.status { status, delivered in
            print("autorização depois: \(status)")
            print("no Centro         : \(delivered.contains(AlertNotifier.identifier(kind)) ? "sim" : "não") \(delivered)")
            checked = true
        }
        wait({ checked }, seconds: 5)
        exit(0)
    }
}
