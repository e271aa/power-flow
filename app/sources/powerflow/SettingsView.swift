import AppKit
import PowerFlowCore
import SwiftUI

/// As duas abas da janela de Definições.
enum SettingsTab: String, CaseIterable {
    case general, alerts

    var titleKey: String {
        switch self {
        case .general: "s_general"
        case .alerts: "s_alerts"
        }
    }
}

/// A janela de Definições: duas abas («Geral» e «Alertas»), cada uma um `Form`
/// agrupado, 540 pt de largura.
///
/// A janela tem a altura da aba mais alta e não muda ao trocar de aba: as duas
/// páginas ficam empilhadas, só uma à vista. Com um `Form` único a janela media
/// 1004 pt e não cabia num ecrã de 13".
///
/// O arranque com a sessão não tem chave `pf.*`: lê-se e escreve-se no
/// `SMAppService`. As outras (`pf.barMode`, `pf.sampleRate`, `pf.alert.*`)
/// são preferências, e o `StatusItemController` reage a elas.
struct SettingsView: View {
    static let width: CGFloat = 540

    let hasBattery: Bool

    @State private var tab: SettingsTab
    @AppStorage(AppSettings.barModeKey) private var barMode = BarMode.default.rawValue
    @AppStorage(AppSettings.sampleRateKey) private var sampleRate = SampleRate.default.rawValue

    init(hasBattery: Bool, tab: SettingsTab = .general) {
        self.hasBattery = hasBattery
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("s_sections"), selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(L10n.string(tab.titleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, PFSpace.m)

            ZStack(alignment: .top) {
                page(.general) {
                    GeneralSection()
                    BarModeSection(selection: $barMode, hasBattery: hasBattery)
                    MeasureSection(selection: $sampleRate)
                }
                page(.alerts) {
                    AlertsSection()
                    AboutSection()
                }
            }
        }
        .background(PFColor.win)
        .frame(width: Self.width)
    }

    /// Uma página. A que não está à vista fica no sítio, para dar a altura à
    /// janela, mas sem foco, sem cliques e fora do VoiceOver.
    private func page<Content: View>(_ page: SettingsTab,
                                     @ViewBuilder content: () -> Content) -> some View {
        let isVisible = tab == page
        return Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .opacity(isVisible ? 1 : 0)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
    }
}

private func sectionTitle(_ key: String) -> some View {
    Text(L10n.string(key)).font(PFFont.title).foregroundStyle(PFColor.fg)
}

// MARK: - Geral

private struct GeneralSection: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var failed = false

    var body: some View {
        Section {
            Toggle(L10n.string("s_login"), isOn: Binding(get: { launchAtLogin }, set: change))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(PFFont.body)
                .frame(minHeight: PFSpace.rowSettings)

            if needsApproval || failed {
                HStack {
                    Text(L10n.string(failed ? "s_login_error" : "s_login_pending"))
                        .font(PFFont.secondary)
                        .foregroundStyle(PFColor.fg2)
                    Spacer(minLength: PFSpace.m)
                    if needsApproval {
                        Button(L10n.string("s_login_open")) { LoginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string("s_lang")).font(PFFont.body)
                    Text(L10n.string("s_lang_val", L10n.languageName))
                        .font(PFFont.secondary)
                        .foregroundStyle(PFColor.fg2)
                }
                Spacer(minLength: PFSpace.m)
                Button(L10n.string("s_lang_btn")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            .frame(minHeight: PFSpace.rowSettings)
        } header: {
            sectionTitle("s_general")
        }
        // O utilizador pode ter mexido nos Itens de início de sessão enquanto
        // a janela estava aberta.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func change(_ on: Bool) {
        do {
            try LoginItem.set(on)
            failed = false
        } catch {
            NSLog("PowerFlow: arranque com a sessão: \(error.localizedDescription)")
            failed = true
        }
        refresh()
    }

    private func refresh() {
        launchAtLogin = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}

// MARK: - Barra de menus

private struct BarModeSection: View {
    @Binding var selection: String
    let hasBattery: Bool

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: PFSpace.s) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(BarMode.allCases, id: \.self) { mode in
                        BarModeTile(mode: mode, isSelected: selection == mode.rawValue,
                                    isAvailable: hasBattery || !mode.showsBattery) {
                            selection = mode.rawValue
                        }
                    }
                }
                // Num Mac sem bateria a barra mostra os watts, seja qual for o modo.
                if !hasBattery {
                    Text(L10n.string("s_bar_nobattery"))
                        .font(PFFont.secondary)
                        .foregroundStyle(PFColor.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, PFSpace.xs)
        } header: {
            sectionTitle("s_bar")
        }
    }
}

/// Um mosaico: o item da barra como fica, a 1:1, com o rótulo por baixo.
/// O selecionado leva anel de 2 pt e o rótulo a semibold: a cor não está sozinha.
private struct BarModeTile: View {
    let mode: BarMode
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    private var label: String {
        let key: String = switch mode {
        case .battery: "s_bar_battery"
        case .batteryWatts: "s_bar_bw"
        case .batteryPlain: "s_bar_plain"
        case .batteryPlainWatts: "s_bar_plain_w"
        case .flowWatts: "s_bar_flow_w"
        case .watts: "s_bar_w"
        }
        return L10n.string(key)
    }

    /// O item com os valores do exemplo: 80 %, 15 W, sem carregar.
    private var sample: NSImage {
        MenuBarIcon.image(BarItem(content: BarItem.content(mode: mode, hasBattery: true),
                                  percent: 80, isCharging: false, showsPercent: mode.showsPercent,
                                  reading: .watts(15)))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: sample)
                    .renderingMode(.template)
                    .foregroundStyle(PFColor.fg)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    .background(PFColor.bar, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(PFColor.accent, lineWidth: 2)
                        }
                    }
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isAvailable ? PFColor.fg : PFColor.fg2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .opacity(isAvailable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isAvailable ? "" : L10n.string("s_bar_nobattery"))
        .accessibilityLabel(label)
        .accessibilityHint(isAvailable ? "" : L10n.string("s_bar_nobattery"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Medição

private struct MeasureSection: View {
    @Binding var selection: String

    var body: some View {
        Section {
            LabeledContent {
                Picker(L10n.string("s_rate"), selection: $selection) {
                    Text(L10n.string("s_rate_low")).tag(SampleRate.low.rawValue)
                    Text(L10n.string("s_rate_norm")).tag(SampleRate.normal.rawValue)
                    Text(L10n.string("s_rate_high")).tag(SampleRate.high.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 220)
            } label: {
                Text(L10n.string("s_rate")).font(PFFont.body)
            }
            .frame(minHeight: PFSpace.rowSettings)
        } header: {
            sectionTitle("s_measure")
        } footer: {
            Text(L10n.string("s_rate_note"))
                .font(PFFont.secondary)
                .foregroundStyle(PFColor.fg2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Alertas

private struct AlertsSection: View {
    private static let defaults = AlertSettings()

    @AppStorage(AppSettings.alertAssistKey) private var assist = defaults.assist
    @AppStorage(AppSettings.alertAssistDelayKey) private var assistDelay = defaults.assistDelay
    @AppStorage(AppSettings.alertTempKey) private var temperature = defaults.temperature
    @AppStorage(AppSettings.alertTempLimitKey) private var temperatureLimit = defaults.temperatureLimit
    @AppStorage(AppSettings.alertWeakKey) private var weakAdapter = defaults.weakAdapter

    var body: some View {
        Section {
            toggle("s_al_assist", isOn: $assist)
            dependent("s_al_after", enabled: assist) {
                Picker(L10n.string("s_al_after"), selection: $assistDelay) {
                    ForEach(AlertSettings.assistDelays, id: \.self) { seconds in
                        Text(AlertSettings.delayLabel(seconds, format: PFFormat(locale: L10n.locale)))
                            .monospacedDigit()
                            .tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            toggle("s_al_temp", isOn: $temperature)
            dependent("s_al_above", enabled: temperature) {
                temperatureStepper
            }

            Toggle(isOn: $weakAdapter) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.string("s_al_weak")).font(PFFont.body)
                    Text(L10n.string("s_al_weak_sub"))
                        .font(PFFont.secondary)
                        .foregroundStyle(PFColor.fg2)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .frame(minHeight: 44)
        } header: {
            sectionTitle("s_alerts")
        } footer: {
            HStack(alignment: .center, spacing: PFSpace.m) {
                Text(L10n.string("s_al_note"))
                    .font(PFFont.secondary)
                    .foregroundStyle(PFColor.fg2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(L10n.string("s_al_btn")) { AlertNotifier.openSystemSettings() }
                    .controlSize(.small)
            }
        }
    }

    /// O passo de 1 °C: dois botões de 24 × 24 pt à volta do valor. As setas do
    /// `Stepper` do sistema medem 11 × 8 pt e não há maneira de as aumentar.
    private var temperatureStepper: some View {
        HStack(spacing: PFSpace.s) {
            stepButton("minus", label: "s_al_above_dec", delta: -1)
            // Com o alerta desligado o valor esbate-se com os botões ao lado.
            Text(PFFormat(locale: L10n.locale).celsius(Double(temperatureLimit), decimals: 0))
                .font(PFFont.body)
                .monospacedDigit()
                .foregroundStyle(temperature ? PFColor.fg : PFColor.fg2)
                .frame(minWidth: 52)
            stepButton("plus", label: "s_al_above_inc", delta: 1)
        }
        .fixedSize()
    }

    private func stepButton(_ symbol: String, label: String, delta: Int) -> some View {
        let next = AlertSettings.steppedTemperatureLimit(temperatureLimit, by: delta)
        return Button { temperatureLimit = next } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PFColor.fg)
                .frame(width: Self.stepSize, height: Self.stepSize)
                .background(PFColor.control, in: RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous)
                    .strokeBorder(PFColor.nodeBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(next == temperatureLimit)
        .accessibilityLabel(L10n.string(label))
    }

    /// O lado dos botões do passo: o mínimo de 24 pt da área de clique (D7d).
    private static let stepSize: CGFloat = 24

    private func toggle(_ key: String, isOn: Binding<Bool>) -> some View {
        Toggle(L10n.string(key), isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(PFFont.body)
            .frame(minHeight: PFSpace.rowSettings)
    }

    /// Uma linha que depende do interruptor de cima: 36 pt, recuo de 28 e
    /// rótulo em `fg2`. Com o interruptor desligado fica à vista, desativada:
    /// a janela não muda de altura.
    private func dependent<Control: View>(_ key: String, enabled: Bool,
                                          @ViewBuilder control: () -> Control) -> some View {
        LabeledContent {
            control()
        } label: {
            Text(L10n.string(key)).font(PFFont.body).foregroundStyle(PFColor.fg2)
        }
        .padding(.leading, 16)
        .frame(minHeight: 36)
        .disabled(!enabled)
    }
}

// MARK: - Sobre

private struct AboutSection: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Section {
            LabeledContent {
                Text(version).font(PFFont.body).monospacedDigit()
            } label: {
                Text(L10n.string("s_version")).font(PFFont.body)
            }
            .frame(minHeight: PFSpace.rowSettings)
            LabeledContent {
                Link(destination: Repository.url) {
                    Text(L10n.string("s_source_link"))
                        .font(PFFont.body)
                        .foregroundStyle(PFColor.blueInk)
                }
                .accessibilityLabel(L10n.string("s_source"))
            } label: {
                Text(L10n.string("s_source")).font(PFFont.body)
            }
            .frame(minHeight: PFSpace.rowSettings)
        } header: {
            sectionTitle("s_about")
        }
    }
}

// MARK: - Janela

/// A janela de Definições. Uma só; abrir outra vez traz a que existe para a frente.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    /// Diz se o Mac tem bateria, para os mosaicos da barra.
    weak var monitor: PowerMonitor?
    /// Fixa se o Mac tem bateria, sem monitor (`--window --view settings --state`).
    var hasBatteryOverride: Bool?
    /// A aba com que a janela abre (`--settings-tab`).
    var initialTab: SettingsTab = .general

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // O `Form` não tem altura própria que o controlador de vista leve à
        // janela (saía só com a barra de título): mede-se na vista e fixa-se.
        let hosting = NSHostingView(rootView: SettingsView(hasBattery: hasBatteryOverride
                                                           ?? monitor?.snapshot.battery.isPresent ?? true,
                                                           tab: initialTab))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.title = L10n.string("s_title")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Fechada, a janela deixa de existir: nada a avaliar enquanto ninguém a vê.
    func windowWillClose(_ notification: Notification) {
        let closing = window
        window = nil
        DispatchQueue.main.async { closing?.contentView = nil }
    }
}
