import Foundation

/// Formats are compiled when settings are loaded, so typing only renders a
/// bounded number of tokens after the exact reading has matched.
struct DateConversionSettings: Equatable {
    static let defaultFormats = ["yyyyMMdd", "yyyy/MM/dd", "yyyy年MM月dd日"]
    static let maxFormatCount = 10
    static let maxFormatCharacterCount = 64

    private enum Part: Equatable {
        case year, shortYear, month, paddedMonth, day, paddedDay
        case literal(String)
    }

    let enabled: Bool
    let formats: [String]
    private let compiledFormats: [[Part]]

    init(enabled: Bool = true, formats: [String]? = nil) {
        self.enabled = enabled
        if let formats, let compiled = Self.compile(formats) {
            self.formats = formats
            self.compiledFormats = compiled
        } else {
            self.formats = Self.defaultFormats
            self.compiledFormats = Self.compile(Self.defaultFormats)!
        }
    }

    static func areValid(formats: [String]) -> Bool {
        compile(formats) != nil
    }

    private static func compile(_ formats: [String]) -> [[Part]]? {
        guard !formats.isEmpty, formats.count <= maxFormatCount else { return nil }
        var compiled: [[Part]] = []
        for format in formats {
            // Count Unicode scalars, matching Rust's chars() and JS Array.from().
            let scalars = Array(format.unicodeScalars.prefix(maxFormatCharacterCount + 1))
            guard !scalars.isEmpty, scalars.count <= maxFormatCharacterCount else { return nil }
            var parts: [Part] = []
            var index = 0
            var hasToken = false
            while index < scalars.count {
                let scalar = scalars[index].value
                let width: Int
                let part: Part
                switch scalar {
                case 0x79: // yyyy or yy
                    let run = scalars[index...].prefix(4).prefix { $0.value == 0x79 }.count
                    guard run >= 2 else { return nil }
                    width = run == 4 ? 4 : 2
                    part = width == 4 ? .year : .shortYear
                case 0x4D: // MM or M
                    width = index + 1 < scalars.count && scalars[index + 1].value == scalar ? 2 : 1
                    part = width == 2 ? .paddedMonth : .month
                case 0x64: // dd or d
                    width = index + 1 < scalars.count && scalars[index + 1].value == scalar ? 2 : 1
                    part = width == 2 ? .paddedDay : .day
                default:
                    guard !(0x41...0x5A).contains(scalar), !(0x61...0x7A).contains(scalar),
                          !(0...0x1F).contains(scalar), !(0x7F...0x9F).contains(scalar),
                          scalar != 0x2028, scalar != 0x2029 else { return nil }
                    parts.append(.literal(String(scalars[index])))
                    index += 1
                    continue
                }
                hasToken = true
                parts.append(part)
                index += width
            }
            guard hasToken else { return nil }
            compiled.append(parts)
        }
        return compiled
    }

    func candidates(
        for reading: String,
        on date: @autoclosure () -> Date = Date(),
        in timeZone: TimeZone = .autoupdatingCurrent
    ) -> [String] {
        guard enabled, reading == "きょう" else { return [] }
        // Never inherit the user's preferred calendar (for example Japanese
        // era years or Buddhist years) for these explicitly Gregorian tokens.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date())
        guard let year = components.year, let month = components.month, let day = components.day else { return [] }
        let yearText = String(year)
        let fullYear = String(repeating: "0", count: max(0, 4 - yearText.count)) + yearText
        let shortYearValue = year % 100
        let shortYear = (shortYearValue < 10 ? "0" : "") + String(shortYearValue)
        let monthText = String(month)
        let paddedMonth = month < 10 ? "0" + monthText : monthText
        let dayText = String(day)
        let paddedDay = day < 10 ? "0" + dayText : dayText
        var results: [String] = []
        for parts in compiledFormats {
            var text = ""
            for part in parts {
                switch part {
                case .year: text += fullYear
                case .shortYear: text += shortYear
                case .month: text += monthText
                case .paddedMonth: text += paddedMonth
                case .day: text += dayText
                case .paddedDay: text += paddedDay
                case .literal(let literal): text += literal
                }
            }
            if !results.contains(text) { results.append(text) }
        }
        return results
    }
}
