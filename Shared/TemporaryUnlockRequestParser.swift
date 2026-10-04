import Foundation

struct TemporaryUnlockRequest: Equatable {
    let applicationNames: [String]
    let duration: TimeInterval
}

enum TemporaryUnlockRequestParserError: LocalizedError, Equatable {
    case missingApplication
    case missingDuration

    var errorDescription: String? {
        switch self {
        case .missingApplication:
            "I couldn't find an installed app in that request. Try saying, ‘Monk, WhatsApp for five minutes.’"
        case .missingDuration:
            "I didn't hear a duration. Try saying, ‘Monk, WhatsApp for five minutes.’"
        }
    }
}

enum TemporaryUnlockRequestParser {
    static func parse(
        _ request: String,
        installedApplicationNames: [String]
    ) throws -> TemporaryUnlockRequest {
        guard let duration = parsedDuration(from: request), duration >= 60 else {
            throw TemporaryUnlockRequestParserError.missingDuration
        }

        let applicationNames = matchedApplicationNames(
            in: request,
            installedApplicationNames: installedApplicationNames
        )
        guard !applicationNames.isEmpty else {
            throw TemporaryUnlockRequestParserError.missingApplication
        }

        return TemporaryUnlockRequest(
            applicationNames: applicationNames,
            duration: duration
        )
    }

    private static func parsedDuration(from request: String) -> TimeInterval? {
        let tokens = durationTokens(from: request)
        var totalSeconds: TimeInterval = 0
        var foundUnit = false

        for (index, token) in tokens.enumerated() {
            guard let multiplier = unitMultiplier(for: token),
                  let value = numberImmediatelyBeforeUnit(at: index, in: tokens) else {
                continue
            }
            totalSeconds += TimeInterval(value) * multiplier
            foundUnit = true
        }

        if foundUnit {
            return totalSeconds > 0 ? totalSeconds : nil
        }

        if let finalToken = tokens.last,
           let minutes = Int(finalToken),
           minutes > 0 {
            return TimeInterval(minutes * 60)
        }
        return nil
    }

    private static func durationTokens(from value: String) -> [String] {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        var result = ""
        var previousWasDigit: Bool?
        for character in folded {
            let isDigit = character.isNumber
            let isLetter = character.isLetter
            guard isDigit || isLetter else {
                result.append(" ")
                previousWasDigit = nil
                continue
            }

            if let previousWasDigit, previousWasDigit != isDigit {
                result.append(" ")
            }
            result.append(character)
            previousWasDigit = isDigit
        }
        return result.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func unitMultiplier(for token: String) -> TimeInterval? {
        switch token {
        case "second", "seconds", "sec", "secs", "s": 1
        case "minute", "minutes", "min", "mins", "m": 60
        case "hour", "hours", "hr", "hrs", "h": 3_600
        case "day", "days", "d": 86_400
        default: nil
        }
    }

    private static func numberImmediatelyBeforeUnit(
        at unitIndex: Int,
        in tokens: [String]
    ) -> Int? {
        guard unitIndex > 0 else { return nil }
        var startIndex = unitIndex - 1
        while startIndex >= 0, isNumberToken(tokens[startIndex]) {
            startIndex -= 1
        }
        let numberTokens = Array(tokens[(startIndex + 1)..<unitIndex])
        return parseNumber(numberTokens)
    }

    private static func isNumberToken(_ token: String) -> Bool {
        Int(token) != nil
            || token == "and"
            || token == "a"
            || token == "an"
            || numberWordValues[token] != nil
            || token == "hundred"
            || token == "thousand"
    }

    private static func parseNumber(_ tokens: [String]) -> Int? {
        guard !tokens.isEmpty else { return nil }
        if tokens.count == 1, let number = Int(tokens[0]) {
            return number
        }

        var total = 0
        var current = 0
        var foundNumber = false
        for token in tokens {
            if token == "and" {
                continue
            }
            if token == "a" || token == "an" {
                current += 1
                foundNumber = true
            } else if let number = Int(token) {
                current += number
                foundNumber = true
            } else if let number = numberWordValues[token] {
                current += number
                foundNumber = true
            } else if token == "hundred" {
                current = max(1, current) * 100
                foundNumber = true
            } else if token == "thousand" {
                total += max(1, current) * 1_000
                current = 0
                foundNumber = true
            }
        }
        let value = total + current
        return foundNumber && value > 0 ? value : nil
    }

    private static func matchedApplicationNames(
        in request: String,
        installedApplicationNames: [String]
    ) -> [String] {
        let compactRequest = compact(request)
        let requestWords = words(request)
        var seen = Set<String>()
        let candidates = installedApplicationNames
            .filter { seen.insert(compact($0)).inserted }
            .sorted { compact($0).count > compact($1).count }

        var occupiedRanges: [NSRange] = []
        var matches: [(name: String, location: Int)] = []
        for name in candidates {
            let compactName = compact(name)
            guard !compactName.isEmpty else { continue }

            let range: NSRange
            if compactName.count <= 2 {
                guard let wordIndex = requestWords.firstIndex(of: compactName) else { continue }
                let compactLocation = requestWords[..<wordIndex].reduce(0) { partialResult, word in
                    partialResult + word.count
                }
                range = NSRange(location: compactLocation, length: compactName.count)
            } else {
                range = (compactRequest as NSString).range(of: compactName)
                guard range.location != NSNotFound else { continue }
            }
            guard occupiedRanges.allSatisfy({ NSIntersectionRange($0, range).length == 0 }) else {
                continue
            }
            occupiedRanges.append(range)
            matches.append((name, range.location))
        }

        return matches.sorted { $0.location < $1.location }.map(\.name)
    }

    private static func compact(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func words(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static let numberWordValues: [String: Int] = [
        "zero": 0,
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "thirteen": 13,
        "fourteen": 14,
        "fifteen": 15,
        "sixteen": 16,
        "seventeen": 17,
        "eighteen": 18,
        "nineteen": 19,
        "twenty": 20,
        "thirty": 30,
        "forty": 40,
        "fifty": 50,
        "sixty": 60,
        "seventy": 70,
        "eighty": 80,
        "ninety": 90
    ]
}
