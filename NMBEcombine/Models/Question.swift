import Foundation

struct Question: Identifiable {
    let id = UUID()

    let seq: Int
    let explanationURL: URL

    let selectedAnswer: String
    let topic: String
    let description: String
    let timeSeconds: Double
    let correctness: String
    
}
extension Question {
    var isCorrectBool: Bool {
        correctness.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "correct"
    }
}
