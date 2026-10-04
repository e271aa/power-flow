import Accessibility
import AppKit
import PowerFlowCore
import SwiftUI

/// «Histórico»: o consumo do sistema e a entrada do adaptador num período.
struct HistorySection: View {
    let store: HistoryStore
    /// O instante a que «agora» se refere: o da última leitura.
    let now: Date
    /// Fixa o período sem mexer na preferência. Serve o `--snapshot`.
    var forcedPeriod: HistoryPeriod?
    /// Mostra a leitura por ponteiro nesta posição (0 a 1), sem ponteiro. Serve o `--snapshot`.
    var pointerPosition: Double?

    @AppStorage("pf.historyPeriod") private var storedPeriod = HistoryPeriod.twoMinutes.rawValue

    var body: some View {
        let dayAvailable = store.isAvailable(.day, now: now)
        let wanted = forcedPeriod ?? HistoryPeriod(rawValue: storedPeriod) ?? .twoMinutes
        // «24 h» guardado de outra sessão, mas ainda sem uma hora de dados.
        let period = wanted == .day && !dayAvailable ? .oneHour : wanted
        let series = store.series(for: period, now: now)
        let copy = HistoryCopy(series: series)

        VStack(alignment: .leading, spacing: PFSpace.s) {
            HStack(spacing: PFSpace.s) {
                Text(L10n.string("h_title"))
                    .pfType(.title)
                    .foregroundStyle(PFColor.fg)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                PeriodControl(selection: period, isDayEnabled: dayAvailable) { select($0) }
                    .fixedSize()
                    .padding(.vertical, -2)
            }

            HistoryChart(series: series, copy: copy, fixedPointer: pointerPosition.flatMap {
                series.nearest(to: $0 * Double(series.period.slots - 1))
            })

            Group {
                if let note = copy.note {
                    Text(note)
                        .pfType(.minimum)
                        .foregroundStyle(PFColor.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(nil, value: period)

            // Numa linha quando cabe; senão a média desce para a linha de baixo
            // e, se nem assim, cada entrada fica na sua linha. Nada se corta.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PFSpace.m) {
                    keys(series)
                    Spacer(minLength: 0)
                    averageLabel(copy)
                }
                VStack(alignment: .leading, spacing: PFSpace.xs) {
                    HStack(spacing: PFSpace.m) { keys(series) }
                    averageLabel(copy)
                }
                VStack(alignment: .leading, spacing: PFSpace.xs) {
                    keys(series)
                    averageLabel(copy)
                }
            }
            .animation(nil, value: period)
        }
        .background {
            // ⌘1, ⌘2 e ⌘3 escolhem o período. Vêm do teclado, por isso não animam.
            Group {
                shortcut("1", .twoMinutes)
                shortcut("2", .oneHour)
                if dayAvailable { shortcut("3", .day) }
            }
            // Só atalhos: fora do percurso do Tab, onde eram paragens sem anel.
            .focusable(false)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// As entradas da legenda: a amostra espelha a marca (traço para linha, caixa para área).
    @ViewBuilder private func keys(_ series: HistorySeries) -> some View {
        HistoryKey(label: L10n.string("h_sys")) {
            Capsule().fill(PFColor.blue).frame(width: 12, height: 3)
        }
        if series.hasAdapter {
            HistoryKey(label: L10n.string("h_ad")) {
                Capsule().fill(PFColor.green).frame(width: 12, height: 3)
            }
        }
        if series.hasBatteryArea {
            HistoryKey(label: L10n.string("h_bat")) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(PFColor.amberSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(PFColor.amber, lineWidth: 1)
                    }
                    .frame(width: 10, height: 9)
            }
        }
    }

    @ViewBuilder private func averageLabel(_ copy: HistoryCopy) -> some View {
        if let average = copy.average {
            (Text(L10n.string("h_avg") + " ").foregroundColor(PFColor.fg2)
                + Text(average).fontWeight(.semibold).foregroundColor(PFColor.fg))
                .font(PFFont.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func shortcut(_ key: KeyEquivalent, _ period: HistoryPeriod) -> some View {
        Button("") { change(to: period, fades: false) }
            .keyboardShortcut(key, modifiers: .command)
    }

    /// Com o rato, as séries trocam num crossfade de 0,2 s. Pelo teclado (o
    /// controlo com o foco e o espaço) trocam de uma vez (D7b).
    private func select(_ period: HistoryPeriod) {
        change(to: period, fades: !PanelNavigation.isKeyboardAction)
    }

    private func change(to period: HistoryPeriod, fades: Bool) {
        if fades {
            withAnimation(PFMotion.periodFade) { storedPeriod = period.rawValue }
        } else {
            storedPeriod = period.rawValue
        }
    }
}

/// Uma entrada da legenda: a amostra espelha a marca (traço para linha, caixa para área).
private struct HistoryKey<Swatch: View>: View {
    let label: String
    @ViewBuilder let swatch: Swatch

    var body: some View {
        HStack(spacing: 5) {
            swatch
            Text(label)
                .pfType(.minimum)
                .foregroundStyle(PFColor.fg2)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// O controlo de período. É o controlo segmentado do sistema, que deixa
/// desativar um segmento e dar-lhe uma dica.
private struct PeriodControl: NSViewRepresentable {
    let selection: HistoryPeriod
    let isDayEnabled: Bool
    let onSelect: (HistoryPeriod) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: [L10n.string("h_2m"), L10n.string("h_1h"), L10n.string("h_24h")],
            trackingMode: .selectOne, target: context.coordinator,
            action: #selector(Coordinator.changed(_:)))
        control.controlSize = .small
        control.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setAccessibilityLabel(L10n.string("h_title"))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        let index = HistoryPeriod.allCases.firstIndex(of: selection) ?? 0
        if control.selectedSegment != index { control.selectedSegment = index }
        if control.isEnabled(forSegment: 2) != isDayEnabled { control.setEnabled(isDayEnabled, forSegment: 2) }
        control.setToolTip(isDayEnabled ? nil : L10n.string("h_24h_off"), forSegment: 2)
    }

    final class Coordinator: NSObject {
        var onSelect: (HistoryPeriod) -> Void

        init(onSelect: @escaping (HistoryPeriod) -> Void) { self.onSelect = onSelect }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard HistoryPeriod.allCases.indices.contains(sender.selectedSegment) else { return }
            onSelect(HistoryPeriod.allCases[sender.selectedSegment])
        }
    }
}

/// O gráfico: 328 × 80 pt, com a área de dados em x 0–290 e y 6–60.
///
/// Um só eixo Y, em watts, para as duas séries. Tudo se desenha nas
/// coordenadas do handoff. As séries não usam o Swift Charts: medido na
/// Fase 6, custava 0,6 pontos de CPU com o painel aberto, a redesenhar 120
/// pontos por segundo. O que o Charts dava ao VoiceOver vem do descritor.
struct HistoryChart: View {
    let series: HistorySeries
    let copy: HistoryCopy
    /// Um ponto apontado sem ponteiro, para a imagem parada.
    var fixedPointer: HistorySeries.Sample?

    @State private var pointed: HistorySeries.Sample?
    private var hovered: HistorySeries.Sample? { fixedPointer ?? pointed }
    @Environment(\.isStaticRender) private var isStaticRender

    private static let size = CGSize(width: 328, height: 80)
    private static let plot = CGRect(x: 0, y: 6, width: 290, height: 54)
    private static let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)

    private func x(_ slot: Int) -> CGFloat {
        Self.plot.minX + Self.plot.width * CGFloat(slot) / CGFloat(max(series.period.slots - 1, 1))
    }

    private func y(_ watts: Double) -> CGFloat {
        Self.plot.maxY - Self.plot.height * CGFloat(min(watts / series.yMax, 1))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid
            gaps
                .animation(nil, value: series.period)
            marks
                .frame(width: Self.plot.width, height: Self.plot.height)
                .offset(x: Self.plot.minX, y: Self.plot.minY)
                .id(series.period)
                // As séries de um período novo entram num crossfade de 0,2 s
                // (só com o rato: o teclado muda sem animação).
                .transition(.opacity)
            // Os eixos, o pico e a leitura não animam com o período.
            Group {
                axisLabels
                if let peak = series.peak, let label = copy.peak, hovered == nil {
                    peakMarker(peak, label: label)
                }
                if let hovered {
                    readout(for: hovered)
                }
            }
            .animation(nil, value: series.period)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let slot = Double((point.x - Self.plot.minX) / Self.plot.width) * Double(series.period.slots - 1)
                let nearest = point.x <= Self.plot.maxX + 8 ? series.nearest(to: slot) : nil
                if nearest != pointed { pointed = nearest }
            case .ended:
                pointed = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.description)
        .accessibilityAddTraits(.isImage)
        .accessibilityChartDescriptor(HistoryDescriptor(series: series, copy: copy))
    }

    // MARK: - Grelha e eixos

    private var grid: some View {
        Canvas { context, _ in
            for (line, color) in [(Self.plot.minY, PFColor.sep), (Self.plot.midY, PFColor.sep),
                                  (Self.plot.maxY, PFColor.track)] {
                var path = Path()
                path.move(to: CGPoint(x: Self.plot.minX, y: line))
                path.addLine(to: CGPoint(x: Self.plot.maxX, y: line))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private var axisLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip([Self.plot.minY, Self.plot.midY, Self.plot.maxY], copy.yLabels)), id: \.0) { line, text in
                Text(text)
                    .font(PFFont.minimum)
                    .monospacedDigit()
                    .foregroundStyle(PFColor.fg2)
                    .fixedSize()
                    .frame(height: 14)
                    .offset(x: Self.plot.maxX + 6, y: line - 7)
            }
            ForEach(copy.xLabels) { label in
                Text(label.text)
                    .font(PFFont.minimum)
                    .monospacedDigit()
                    .foregroundStyle(PFColor.fg2)
                    .fixedSize()
                    .frame(height: 14)
                    .alignmentGuide(.leading) { size in
                        // O primeiro alinha à esquerda, o último à direita, os do meio ao centro.
                        let anchor = label.position <= 0 ? 0 : label.position >= 1 ? size.width : size.width / 2
                        return anchor - Self.plot.width * label.position
                    }
                    .offset(y: Self.size.height - 14)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// O Mac em repouso, ou a app fechada: um intervalo sem dados, não uma descida a zero.
    private var gaps: some View {
        ZStack(alignment: .topLeading) {
            ForEach(series.gaps, id: \.lowerBound) { gap in
                let left = x(gap.lowerBound), width = max(x(gap.upperBound) - left, 2)
                Rectangle()
                    .fill(PFColor.fill)
                    .overlay {
                        Text(L10n.string("h_sleep"))
                            .font(PFFont.minimum)
                            .foregroundStyle(PFColor.fg2)
                            .fixedSize()
                            // Só quando cabe, ou quase: numa lacuna estreita o
                            // texto tapava os dados dos dois lados.
                            .opacity(width >= 70 ? 1 : 0)
                    }
                    .frame(width: width, height: Self.plot.height)
                    .offset(x: left, y: Self.plot.minY)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: - Séries

    private var marks: some View {
        Canvas { context, size in
            func point(_ slot: Int, _ watts: Double) -> CGPoint {
                CGPoint(x: size.width * CGFloat(slot) / CGFloat(max(series.period.slots - 1, 1)),
                        y: size.height * (1 - CGFloat(min(watts / series.yMax, 1))))
            }
            func line(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                return path
            }
            func area(_ top: [CGPoint], _ bottom: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(top + bottom.reversed())
                path.closeSubpath()
                return path
            }

            let bySegment = Dictionary(grouping: series.samples, by: \.segment)
            let withAdapter = Dictionary(grouping: series.samples.filter { $0.adapter != nil },
                                         by: \.adapterSegment)

            // A bateria é o que fica entre as duas linhas: por cima do
            // sistema é carga, por baixo é a bateria a ajudar.
            for run in withAdapter.values {
                context.fill(area(run.map { point($0.slot, $0.adapter ?? 0) },
                                  run.map { point($0.slot, $0.system) }),
                             with: .color(PFColor.amberSoft))
            }
            for run in bySegment.values {
                context.fill(area(run.map { point($0.slot, $0.system) }, run.map { point($0.slot, 0) }),
                             with: .color(PFColor.blueSoft.opacity(series.hasAdapter ? 0.55 : 1)))
            }
            for run in bySegment.values {
                context.stroke(line(run.map { point($0.slot, $0.system) }),
                               with: .color(PFColor.blue), style: Self.line)
            }
            for run in withAdapter.values {
                context.stroke(line(run.map { point($0.slot, $0.adapter ?? 0) }),
                               with: .color(PFColor.green), style: Self.line)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Pico

    private func peakMarker(_ peak: HistorySeries.Sample, label: String) -> some View {
        let point = CGPoint(x: x(peak.slot), y: y(peak.system))
        let labelX = min(max(point.x, 36), Self.plot.maxX - 36)
        return ZStack(alignment: .topLeading) {
            dot(at: point, color: PFColor.blueInk, radius: 3)
            HaloText(text: label)
                .fixedSize()
                .frame(height: 14)
                .alignmentGuide(.leading) { $0.width / 2 - labelX }
                .offset(y: max(point.y - 7, 10) - 11)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Um ponto com anel na cor do fundo, para se destacar da linha por onde passa.
    private func dot(at point: CGPoint, color: Color, radius: CGFloat) -> some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(PFColor.bg, lineWidth: 1.5).padding(-1.5) }
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: point.x - radius, y: point.y - radius)
    }

    // MARK: - Leitura por ponteiro

    /// Uma linha no instante apontado e os valores de todas as séries nesse
    /// instante. O ponteiro só tem de acertar no tempo, não numa linha.
    private func readout(for sample: HistorySeries.Sample) -> some View {
        let format = PFFormat()
        let position = x(sample.slot)
        let onLeft = position > Self.plot.width / 2

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(PFColor.fg2)
                .frame(width: 1, height: Self.plot.height)
                .offset(x: position - 0.5, y: Self.plot.minY)
            if let adapter = sample.adapter {
                dot(at: CGPoint(x: position, y: y(adapter)), color: PFColor.greenInk, radius: 2.5)
            }
            dot(at: CGPoint(x: position, y: y(sample.system)), color: PFColor.blueInk, radius: 2.5)

            VStack(alignment: .leading, spacing: 1) {
                Text(copy.when(sample))
                    .foregroundStyle(PFColor.fg2)
                readoutRow(format.watts(sample.system), L10n.string("h_sys"), PFColor.blue)
                if let adapter = sample.adapter {
                    readoutRow(format.watts(adapter), L10n.string("h_ad"), PFColor.green)
                    let battery = adapter - sample.system
                    if abs(battery) > 0.8 {
                        readoutRow((battery > 0 ? "+" : "\u{2212}") + format.watts(abs(battery)),
                                   L10n.string("h_bat"), PFColor.amber)
                    }
                }
            }
            .font(PFFont.minimum)
            .monospacedDigit()
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background {
                RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous)
                    .fill(PFColor.menuBg)
                    .overlay {
                        RoundedRectangle(cornerRadius: PFRadius.button, style: .continuous)
                            .strokeBorder(PFColor.nodeBorder, lineWidth: 1)
                    }
            }
            .fixedSize()
            // Do lado do ponteiro que tem mais espaço.
            .alignmentGuide(.leading) { onLeft ? $0.width + 8 - position : -(position + 8) }
            // Quatro linhas de 11 pt não cabem nos 54 pt da área de dados: a
            // caixa sobe para o intervalo por cima do gráfico, e os rótulos
            // do eixo do tempo ficam à vista.
            .offset(y: Self.plot.minY - 14)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// O valor primeiro, a série depois: quem aponta já sabe a série e quer o número.
    private func readoutRow(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 8, height: 3)
            Text(value).fontWeight(.semibold).foregroundStyle(PFColor.fg)
            Text(label).foregroundStyle(PFColor.fg2)
        }
    }
}

/// Texto com um contorno na cor do fundo, para se ler por cima das linhas.
private struct HaloText: View {
    let text: String

    var body: some View {
        let label = Text(text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
        ZStack {
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) * .pi / 4
                label.foregroundStyle(PFColor.bg).offset(x: cos(angle) * 1.5, y: sin(angle) * 1.5)
            }
            label.foregroundStyle(PFColor.fg)
        }
    }
}

/// O gráfico para o VoiceOver: as séries como dados, para ouvir e para percorrer em tabela.
private struct HistoryDescriptor: AXChartDescriptorRepresentable {
    let series: HistorySeries
    let copy: HistoryCopy

    func makeChartDescriptor() -> AXChartDescriptor {
        let format = PFFormat()
        let slots = Double(max(series.period.slots - 1, 1))
        let xAxis = AXNumericDataAxisDescriptor(
            title: L10n.string("vo_hist_x"), range: 0...slots, gridlinePositions: []
        ) { slot in
            series.nearest(to: slot).map { copy.when($0) } ?? ""
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: L10n.string("vo_hist_y"), range: 0...series.yMax, gridlinePositions: [0, series.yMax / 2, series.yMax]
        ) { format.watts($0) }

        var data = [AXDataSeriesDescriptor(
            name: L10n.string("h_sys"), isContinuous: true,
            dataPoints: series.samples.map { AXDataPoint(x: Double($0.slot), y: $0.system) })]
        if series.hasAdapter {
            data.append(AXDataSeriesDescriptor(
                name: L10n.string("h_ad"), isContinuous: true,
                dataPoints: series.samples.compactMap { sample in
                    sample.adapter.map { AXDataPoint(x: Double(sample.slot), y: $0) }
                }))
        }
        return AXChartDescriptor(title: L10n.string("h_title"), summary: copy.description,
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: data)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let fresh = makeChartDescriptor()
        descriptor.summary = fresh.summary
        descriptor.xAxis = fresh.xAxis
        descriptor.yAxis = fresh.yAxis
        descriptor.series = fresh.series
    }
}
