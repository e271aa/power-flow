import Foundation

/// Formatadores únicos de grandezas. Número pela locale, espaço não
/// separável antes da unidade. A vista nunca monta «x W» à mão.
public struct PFFormat {
    public static let nbsp = "\u{00A0}"

    public var locale: Locale

    public init(locale: Locale = L10n.locale) { self.locale = locale }

    private func number(_ value: Double, decimals: Int, grouping: Bool = false) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        f.usesGroupingSeparator = grouping
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func withUnit(_ text: String, _ unit: String) -> String { text + Self.nbsp + unit }

    /// Só o número em watts, com uma casa decimal («12,3»).
    public func wattsValue(_ watts: Double, decimals: Int = 1) -> String { number(watts, decimals: decimals) }

    /// «12,3 W».
    public func watts(_ watts: Double, decimals: Int = 1) -> String {
        withUnit(wattsValue(watts, decimals: decimals), "W")
    }

    /// «80 %».
    public func percent(_ value: Double, decimals: Int = 0) -> String {
        withUnit(number(value, decimals: decimals), "%")
    }

    public func percent(_ value: Int) -> String { percent(Double(value)) }

    /// «42,5 °C».
    public func celsius(_ value: Double, decimals: Int = 1) -> String {
        withUnit(number(value, decimals: decimals), "°C")
    }

    /// O número de mAh com separador de milhares («4 500»), sem unidade (os textos já a trazem).
    public func mAhValue(_ value: Int) -> String { number(Double(value), decimals: 0, grouping: true) }

    /// «4 500 mAh».
    public func mAh(_ value: Int) -> String { withUnit(mAhValue(value), "mAh") }

    /// Contagens sem unidade (ciclos, segundos).
    public func integer(_ value: Int) -> String { number(Double(value), decimals: 0) }

    /// «45 s».
    public func seconds(_ value: Int) -> String { withUnit(integer(value), "s") }

    /// «30 min».
    public func minutes(_ value: Int) -> String { withUnit(integer(value), "min") }

    /// «1 h».
    public func hours(_ value: Int) -> String { withUnit(integer(value), "h") }

    /// A hora do relógio como a locale a escreve: «14:02» em PT, «2:02 PM» em EN.
    public func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    /// «1 h 20 min», «45 min». Nunca negativa.
    public func duration(minutes: Int) -> String {
        let total = max(minutes, 0)
        let hours = total / 60, rest = total % 60
        let min = withUnit(integer(rest), "min")
        return hours > 0 ? withUnit(integer(hours), "h") + Self.nbsp + min : min
    }
}
