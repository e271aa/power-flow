import PowerFlowCore
import SwiftUI

/// As vistas do painel. `main` é o nível 1; as outras entram por push.
enum PanelRoute: Equatable {
    case main, apps, battery
}

/// Onde o painel está e como lá chegou.
///
/// Vive fora da vista para o `--panel-check` o poder ler, e para cada
/// abertura do painel começar no nível 1.
@MainActor
final class PanelNavigation: ObservableObject {
    @Published private(set) var route: PanelRoute = .main
    /// Verdadeiro quando a última mudança foi um voltar: a vista sai pela borda oposta.
    private(set) var isGoingBack = false

    /// Entra numa vista do nível 2. Vem sempre de um clique, por isso anima.
    func push(_ route: PanelRoute, reduceMotion: Bool) {
        isGoingBack = false
        withAnimation(Self.animation(reduceMotion: reduceMotion)) { self.route = route }
    }

    /// Volta ao nível 1. O teclado (Esc, ⌘[) não anima: quem o usa repete o
    /// gesto muitas vezes e a animação só o faria esperar.
    func pop(animated: Bool, reduceMotion: Bool) {
        guard route != .main else { return }
        isGoingBack = true
        if animated {
            withAnimation(Self.animation(reduceMotion: reduceMotion)) { route = .main }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { route = .main }
        }
    }

    private static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 1)
    }

    /// Com Reduzir Movimento a vista nova aparece no lugar, sem deslizar.
    func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return isGoingBack
            ? .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }
}

/// Fundo `fill` com o ponteiro por cima ou premido, para linhas e botões sem moldura.
struct PFHoverButtonStyle: ButtonStyle {
    var radius: CGFloat = PFRadius.button
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PFColor.fill)
                    .opacity(isHovering || configuration.isPressed ? 1 : 0)
            }
            // O anel de foco segue esta forma, com os cantos do fundo do hover.
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { isHovering = $0 }
    }
}

/// O «›» das linhas e botões que levam a outra vista.
struct PFDisclosure: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PFColor.fg2)
            .frame(width: 10, height: 14)
            .accessibilityHidden(true)
    }
}

/// O cabeçalho das vistas do nível 2: voltar, título e subtítulo.
struct PanelSubHeader: View {
    let title: String
    let subtitle: String
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PFColor.fg)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(PFHoverButtonStyle())
                .accessibilityLabel(L10n.string("back"))

                VStack(alignment: .leading, spacing: 0) {
                    Text(title).pfType(.title).foregroundStyle(PFColor.fg)
                    Text(subtitle).pfType(.secondary).foregroundStyle(PFColor.fg2)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 10, leading: PFSpace.s, bottom: 10, trailing: PFSpace.popoverMargin))

            Rectangle().fill(PFColor.sep).frame(height: 1)
        }
    }
}

/// Uma linha de 32 pt que leva a outra vista.
struct PanelNavRow: View {
    let symbol: String
    let title: String
    let summary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(PFColor.fg2)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(PFFont.body)
                    .foregroundStyle(PFColor.fg)
                    .fixedSize()
                Text(summary)
                    .font(PFFont.secondary)
                    .monospacedDigit()
                    .foregroundStyle(PFColor.fg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                PFDisclosure()
            }
            .padding(.horizontal, PFSpace.s)
            .frame(height: PFSpace.rowPopover)
        }
        .buttonStyle(PFHoverButtonStyle())
    }
}
