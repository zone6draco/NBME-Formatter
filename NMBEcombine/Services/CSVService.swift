import Foundation

enum CSVError: LocalizedError {
    case missingColumn(String)
    case invalidRow(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let name):
            return "CSV is missing required column: \(name)"
        case .invalidRow(let line, let reason):
            return "Invalid row at line \(line): \(reason)"
        }
    }
}

struct CSVService {

    // Required CSV columns
    static let requiredColumns = [
        "Seq",
        "Answer Explanation",
        "Answer Selected",
        "Content Topic",
        "Content Description",
        "Time (sec)",
        "Correct / Incorrect"
    ]

    /// Load and validate questions from CSV
    static func loadQuestions(from url: URL) throws -> [Question] {

        let text = try String(contentsOf: url, encoding: .utf8)

        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else {
            throw CSVError.invalidRow(1, "CSV is empty")
        }

        let headers = parseCSVLine(headerLine)
        var indexMap: [String: Int] = [:]

        // Verify required columns
        for column in requiredColumns {
            guard let idx = headers.firstIndex(of: column) else {
                throw CSVError.missingColumn(column)
            }
            indexMap[column] = idx
        }

        var questions: [Question] = []

        for (lineIndex, line) in lines.dropFirst().enumerated() {
            let rowNumber = lineIndex + 2
            let values = parseCSVLine(line)

            func value(_ column: String) throws -> String {
                guard let idx = indexMap[column], idx < values.count else {
                    throw CSVError.invalidRow(rowNumber, "Missing value for \(column)")
                }
                return clean(values[idx])
            }

            // Parse Seq
            let seqString = try value("Seq")
            guard let seq = Int(seqString) else {
                throw CSVError.invalidRow(rowNumber, "Invalid Seq value: \(seqString)")
            }

            // Parse URL (NO encoding — trust CSV)
            let urlString = try value("Answer Explanation")
            guard let url = URL(string: urlString) else {
                throw CSVError.invalidRow(rowNumber, "Invalid URL: \(urlString)")
            }

            // Parse time (decimal seconds)
            let timeString = try value("Time (sec)")
            guard let time = Double(timeString) else {
                throw CSVError.invalidRow(rowNumber, "Invalid Time (sec): \(timeString)")
            }

            let q = Question(
                seq: seq,
                explanationURL: url,
                selectedAnswer: try value("Answer Selected"),
                topic: try value("Content Topic"),
                description: try value("Content Description"),
                timeSeconds: time,
                correctness: try value("Correct / Incorrect")
            )

            questions.append(q)
        }

        // Always sort by Seq
        return questions.sorted { $0.seq < $1.seq }
    }

    // MARK: - Helpers

    /// Removes whitespace and wrapping quotes
    private static func clean(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove wrapping quotes only
        if v.hasPrefix("\"") && v.hasSuffix("\"") {
            v.removeFirst()
            v.removeLast()
        }

        return v
    }

    /// Minimal CSV parser that respects quoted commas
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        result.append(current)
        return result
    }
}
