import Foundation
import KanaKanjiConverterModule
import Testing
@testable import azookey_server

@Test func dateConversionSettingsDefaultsCustomAndInvalidFallback() throws {
    let decoder = JSONDecoder()
    let defaults = try decoder.decode(GeneralSettings.self, from: Data("{}".utf8)).dateConversion
    #expect(defaults.enabled)
    #expect(defaults.formats == ["yyyyMMdd", "yyyy/MM/dd", "yyyy年MM月dd日"])
    let custom = try decoder.decode(GeneralSettings.self,
        from: Data(#"{"date_conversion":false,"date_formats":["yy/M/d","yyyy年M月d日"]}"#.utf8)).dateConversion
    #expect(!custom.enabled)
    #expect(custom.formats == ["yy/M/d", "yyyy年M月d日"])

    let invalid: [[String]] = [
        [], [""], ["   "], ["年月日"], ["yyyy-MM-dd HH:mm"], ["YYYYMMdd"], ["yyy/M/d"],
        ["yyyy\nMM"], ["yyyy\tMM"], ["yyyy\u{0}MM"], ["yyyy\u{85}MM"],
        ["yyyy\u{2028}MM"], ["yyyy\u{2029}MM"],
        [String(repeating: "日", count: 64) + "d"],
        [String(repeating: "👩‍💻", count: 22) + "d"],
        Array(repeating: "yyyyMMdd", count: 11), ["yyyyMMdd", "unsupported"],
    ]
    for formats in invalid {
        #expect(!DateConversionSettings.areValid(formats: formats), "formats=\(formats)")
        let json = try JSONSerialization.data(withJSONObject: ["date_formats": formats])
        let loaded = try decoder.decode(GeneralSettings.self, from: json).dateConversion
        #expect(loaded.formats == defaults.formats)
    }
    for formats in [
        ["yy/M/d"], ["yyyy年M月d日"], [" yyyy.MM.dd "],
        [String(repeating: "日", count: 63) + "d"],
        [String(repeating: "👩‍💻", count: 21) + "d"],
        Array(repeating: "yyyyMMdd", count: 10),
    ] {
        #expect(DateConversionSettings.areValid(formats: formats), "formats=\(formats)")
        #expect(DateConversionSettings(formats: formats).formats == formats)
    }
}

private func dateConversionInstant(_ iso8601: String) -> Date {
    // Tests use a fixed instant; production never constructs a date formatter.
    ISO8601DateFormatter().date(from: iso8601)!
}

@Test func dateConversionGregorianDatesTimezonesLeapDayAndYearRollover() throws {
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let defaults = DateConversionSettings()
    #expect(defaults.candidates(for: "きょう", on: dateConversionInstant("2026-11-13T03:00:00Z"), in: tokyo)
        == ["20261113", "2026/11/13", "2026年11月13日"])
    let newYear = dateConversionInstant("2026-12-31T15:30:00Z")
    #expect(defaults.candidates(for: "きょう", on: newYear, in: utc).first == "20261231")
    #expect(defaults.candidates(for: "きょう", on: newYear, in: tokyo).first == "20270101")
    #expect(defaults.candidates(for: "きょう", on: newYear, in: losAngeles).first == "20261231")
    let leapDay = dateConversionInstant("2024-02-28T15:30:00Z")
    #expect(defaults.candidates(for: "きょう", on: leapDay, in: utc).first == "20240228")
    #expect(defaults.candidates(for: "きょう", on: leapDay, in: tokyo).first == "20240229")
    #expect(defaults.candidates(for: "きょう", on: dateConversionInstant("2024-02-29T15:00:00Z"), in: tokyo).first == "20240301")
    let custom = DateConversionSettings(formats: ["yy/M/d", "yyyy年M月d日", "yy/M/d"])
    #expect(custom.candidates(for: "きょう", on: newYear, in: tokyo) == ["27/1/1", "2027年1月1日"])
    #expect(custom.candidates(for: "きょう", on: dateConversionInstant("2000-01-02T00:00:00Z"), in: utc)
        == ["00/1/2", "2000年1月2日"])
}

@Test func dateConversionOnlyReadsClockForExactEnabledReading() {
    var clockReads = 0
    func now() -> Date { clockReads += 1; return Date(timeIntervalSince1970: 0) }
    for reading in ["", "きょ", "きょうと", "きょうは", "とうきょう", "キョウ", "kyou"] {
        #expect(DateConversionSettings().candidates(for: reading, on: now()).isEmpty)
    }
    #expect(DateConversionSettings(enabled: false).candidates(for: "きょう", on: now()).isEmpty)
    #expect(clockReads == 0)
    #expect(!DateConversionSettings().candidates(for: "きょう", on: now()).isEmpty)
    #expect(clockReads == 1)
}

@MainActor private func withDateConversionServer(_ body: () throws -> Void) throws {
    let saved = (converter, normalNBestSupplementConverter, composingText, composingTextSnapshots,
        config, currentInputStyle, currentRomajiInputTable, currentLearningType,
        currentLearningMemoryDirectoryURL, learningCandidateCache, learningSelectionOverrides,
        currentDateConversionSettings, execURL, pendingBundledDictionaryConfiguration)
    defer {
        (converter, normalNBestSupplementConverter, composingText, composingTextSnapshots,
         config, currentInputStyle, currentRomajiInputTable, currentLearningType,
         currentLearningMemoryDirectoryURL, learningCandidateCache, learningSelectionOverrides,
         currentDateConversionSettings, execURL, pendingBundledDictionaryConfiguration) = saved
    }
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let dictionary = root.appending(path: "azooKey_dictionary_storage/Dictionary")
    let table = try mixedInputWindowsTable()
    converter = KanaKanjiConverter(dictionaryURL: dictionary, preloadDictionary: true)
    normalNBestSupplementConverter = KanaKanjiConverter(dictionaryURL: dictionary, preloadDictionary: false)
    composingText = ComposingText()
    composingTextSnapshots = []
    config["enable"] = false
    config["context"] = ""
    config["experimentalTypoCorrection"] = false
    config["experimentalMixedInput"] = false
    currentInputStyle = table.style
    currentRomajiInputTable = table.table
    currentLearningType = .inputAndOutput
    let memory = FileManager.default.temporaryDirectory.appending(path: "date-conversion-\(UUID().uuidString)")
    currentLearningMemoryDirectoryURL = memory
    defer { try? FileManager.default.removeItem(at: memory) }
    learningCandidateCache = LearningCandidateCache()
    learningSelectionOverrides = [:]
    currentDateConversionSettings = .init()
    execURL = root
    pendingBundledDictionaryConfiguration = nil
    try body()
}

private struct DateConversionCandidate {
    let text: String
    let suffix: String
    let hiragana: String?
    let inputCount: Int
    let id: UInt64
}

@MainActor private func dateConversionCandidates(boundary: Int? = nil, reconversion: Bool = false) -> [DateConversionCandidate] {
    var count: CInt = 0
    let list = if reconversion {
        get_composed_text_for_reconversion(lengthPtr: &count)
    } else if let boundary {
        get_composed_text_for_cursor_prefix(requiredInputCount: CInt(boundary), lengthPtr: &count)
    } else {
        get_composed_text(lengthPtr: &count)
    }
    defer { free_candidate_list(list, count) }
    return (0..<Int(count)).compactMap { index in
        guard let value = list.advanced(by: index).pointee?.pointee else { return nil }
        return DateConversionCandidate(text: String(cString: value.text), suffix: String(cString: value.subtext),
            hiragana: value.hiragana.map { String(cString: $0) }, inputCount: Int(value.correspondingCount), id: value.candidateId)
    }
}

@MainActor private func dateConversionRawInput() -> String? {
    let raw = get_raw_input()
    defer { free_c_string(raw) }
    return raw.map { String(cString: $0) }
}

@MainActor private func dateConversionOrdinaryCandidates(boundary: Int? = nil) -> [DateConversionCandidate] {
    let settings = currentDateConversionSettings
    defer { currentDateConversionSettings = settings }
    currentDateConversionSettings = .init(enabled: false)
    return dateConversionCandidates(boundary: boundary)
}

@MainActor private func dateConversionType(_ keys: String) {
    var cursor: CInt = 0
    for key in keys {
        String(key).withCString { free_c_string(append_text(input: $0, cursorPtr: &cursor)) }
        #expect(cursor == composingText.convertTargetCursorPosition)
    }
}

@Test func dateConversionKeyHistoryDeletionReinputAndCommitMetadata() async throws {
    try await MainActor.run {
        try withDateConversionServer {
            for (key, reading, raw) in [("k", "k", "k"), ("y", "ky", "ky"), ("o", "きょ", "kyo"), ("u", "きょう", "kyou")] {
                dateConversionType(key)
                #expect(composingText.convertTarget == reading)
                #expect(dateConversionRawInput() == raw)
                #expect(composingText.input.count == raw.count)
                let candidates = dateConversionCandidates()
                #expect(candidates.filter { $0.id == 0 }.count == (raw == "kyou" ? 3 : 0))
            }
            let ordinary = dateConversionOrdinaryCandidates()
            let ordinaryFirst = try #require(ordinary.first?.text)
            let candidates = dateConversionCandidates()
            #expect(candidates.first?.text == ordinaryFirst)
            #expect(candidates.filter { $0.id != 0 }.map(\.text) == ordinary.map(\.text))
            #expect(candidates.first?.hiragana == "きょう")
            let dates = Array(candidates.dropFirst().prefix(3))
            #expect(dates.map(\.text) == currentDateConversionSettings.candidates(for: "きょう"))
            #expect(dates.allSatisfy { $0.inputCount == 4 && $0.suffix.isEmpty && $0.id == 0 && $0.hiragana == nil })
            #expect(!pin_learning_candidate(candidateId: 0))
            #expect(consumeLearningCandidate(0) == nil)
            #expect(!commit_learning_candidate(candidateId: 0, commitKind: 0))
            #expect(learningSelectionOverrides.isEmpty)

            var cursor: CInt = 0
            free_c_string(remove_text(cursorPtr: &cursor))
            #expect(composingText.convertTarget == "きょ")
            #expect(dateConversionRawInput() == "kyo")
            #expect(composingText.input.count == 3)
            #expect(dateConversionCandidates().allSatisfy { $0.id != 0 })
            dateConversionType("u")
            #expect(dateConversionRawInput() == "kyou")
            #expect(dateConversionCandidates().filter { $0.id == 0 }.count == 3)
            let selected = try #require(dateConversionCandidates().first { $0.id == 0 })
            free_c_string(shrink_text(offset: CInt(selected.inputCount)))
            #expect(composingText.convertTarget.isEmpty)
            #expect(composingText.input.isEmpty)
            #expect(dateConversionRawInput() == "")
            #expect(learningSelectionOverrides.isEmpty)
        }
    }
}

@Test func dateConversionDisabledCustomAndReconversionCandidates() async throws {
    try await MainActor.run {
        try withDateConversionServer {
            dateConversionType("kyou")
            currentDateConversionSettings = .init(enabled: false)
            let ordinary = dateConversionCandidates()
            let ordinaryFirst = try #require(ordinary.first?.text)
            #expect(ordinary.allSatisfy { $0.id != 0 })
            currentDateConversionSettings = .init(formats: ["yy/M/d", "yyyy年M月d日"])
            let candidates = dateConversionCandidates()
            #expect(candidates.first?.text == ordinaryFirst)
            #expect(candidates.filter { $0.id != 0 }.map(\.text) == ordinary.map(\.text))
            #expect(Array(candidates.dropFirst().prefix(2)).map(\.text) == currentDateConversionSettings.candidates(for: "きょう"))
            #expect(candidates.filter { $0.id == 0 }.count == 2)
            #expect(dateConversionCandidates(reconversion: true).allSatisfy { $0.id != 0 })
            #expect(dateConversionRawInput() == "kyou")
            for keys in ["kyouto", "kyouha", "toukyou"] {
                clear_text()
                dateConversionType(keys)
                #expect(dateConversionCandidates().allSatisfy { $0.id != 0 }, "keys=\(keys)")
            }
        }
    }
}

@Test func dateConversionCursorPrefixCountsSuffixAndPartialCommit() async throws {
    try await MainActor.run {
        try withDateConversionServer {
            dateConversionType("kyouha")
            var cursor: CInt = 0
            free_c_string(move_cursor(offset: -1, cursorPtr: &cursor))
            #expect(cursor == 3)
            #expect(composingText.input.count == 6)
            #expect(dateConversionRawInput() == "kyouha")
            let ordinary = dateConversionOrdinaryCandidates(boundary: 4)
            let ordinaryFirst = try #require(ordinary.first?.text)
            let candidates = dateConversionCandidates(boundary: 4)
            #expect(candidates.first?.text == ordinaryFirst)
            #expect(candidates.filter { $0.id != 0 }.map(\.text) == ordinary.map(\.text))
            let dates = candidates.filter { $0.id == 0 }
            #expect(dates.count == 3)
            #expect(dates.allSatisfy { $0.inputCount == 4 && $0.suffix == "は" })
            #expect(dateConversionCandidates(boundary: 3).isEmpty)
            let selected = try #require(dates.first)
            push_composing_text_snapshot(selectedCandidateId: selected.id)
            #expect(learningCandidateCache.protectedSlotCount == 0)
            free_c_string(shrink_text(offset: CInt(selected.inputCount)))
            #expect(composingText.convertTarget == "は")
            #expect(dateConversionRawInput() == "ha")
            #expect(composingText.input.count == 2)
            pop_composing_text_snapshot(selectedCandidateId: selected.id)
            #expect(dateConversionRawInput() == "kyouha")
            #expect(dateConversionCandidates(boundary: 4).filter { $0.id == 0 }.count == 3)
            clear_text()
            "きょう".withCString { free_c_string(append_text_direct(input: $0, cursorPtr: &cursor)) }
            #expect(dateConversionRawInput() == "きょう")
            #expect(composingText.input.count == 3)
            #expect(dateConversionCandidates().filter { $0.id == 0 }.allSatisfy { $0.inputCount == 3 })
            let directPrefix = dateConversionCandidates(boundary: 3).filter { $0.id == 0 }
            #expect(directPrefix.count == 3)
            #expect(directPrefix.allSatisfy { $0.inputCount == 3 && $0.suffix.isEmpty })
        }
    }
}

@Test func dateConversionSettingsReloadPreservesActiveInputAndSnapshots() async throws {
    try await MainActor.run {
        try withDateConversionServer {
            let saved = (converterBaseDictionaryURL, converterDictionaryURL,
                activeBundledDictionaryMode, bundledDictionaryConfigurationInitialized,
                reconversionDictionary, customRomajiTableEnabled, emojiTextReplacerCache)
            defer {
                (converterBaseDictionaryURL, converterDictionaryURL,
                 activeBundledDictionaryMode, bundledDictionaryConfigurationInitialized,
                 reconversionDictionary, customRomajiTableEnabled, emojiTextReplacerCache) = saved
            }
            // Keep dictionary/backend/input-style settings stable while changing
            // only dates. The fixture converter already owns this dictionary.
            converterBaseDictionaryURL = execURL.appending(path: "azooKey_dictionary_storage/Dictionary")
            converterDictionaryURL = converterBaseDictionaryURL
            activeBundledDictionaryMode = .both
            bundledDictionaryConfigurationInitialized = true
            customRomajiTableEnabled = false
            config["backend"] = "cpu"
            config["profile"] = ""
            dateConversionType("kyou")
            let ordinaryFirst = try #require(dateConversionOrdinaryCandidates().first?.text)
            push_composing_text_snapshot(selectedCandidateId: 0)
            let original = composingText
            let snapshots = composingTextSnapshots
            let directory = FileManager.default.temporaryDirectory.appending(path: "date-settings-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let settings = directory.appending(path: "settings.json")
            for (enabled, formats) in [(false, ["yyyyMMdd"]), (true, ["yy/M/d"]), (true, ["invalid"])] {
                let data = try JSONSerialization.data(withJSONObject: ["general": ["date_conversion": enabled, "date_formats": formats]])
                try data.write(to: settings, options: .atomic)
                #expect(applyLoadedConfig(at: settings))
                #expect(composingText == original)
                #expect(composingTextSnapshots == snapshots)
                #expect(dateConversionRawInput() == "kyou")
                #expect(composingText.input.count == 4)
                #expect(currentDateConversionSettings.enabled == enabled)
                let candidates = dateConversionCandidates()
                let dates = candidates.filter { $0.id == 0 }
                #expect(dates.map(\.text) == currentDateConversionSettings.candidates(for: "きょう"))
                #expect(dates.count == (!enabled ? 0 : formats == ["invalid"] ? 3 : 1))
                #expect(candidates.first?.text == ordinaryFirst)
            }
        }
    }
}
