import Foundation
import PDFKit
import AppKit

enum PDFService {

    // MARK: - Public entry point

    /// Builds final merged PDF:
    /// 1) For each question PDF: optionally hides "Correct Answer:" line + "Incorrect Answers:" line
    /// 2) Stamps Question # on EVERY page
    /// 3) Appends an Answer Summary page
    /// 4) Merges all PDFs
    /// 5) Prepends Exam Summary page
    static func buildFinalReport(
        questions: [Question],
        downloadedPDFs: [URL],
        hideAnswersOnQuestionPages: Bool,
        outputURL: URL,
        log: (String) -> Void,
        onMergeProgress: ((Double) -> Void)? = nil
    ) throws {

        // ---------------- Match PDFs to questions ----------------
        let pairs = matchDownloadedPDFsToQuestions(
            questions: questions,
            downloadedPDFs: downloadedPDFs
        )

        guard !pairs.isEmpty else {
            throw NSError(
                domain: "PDFService",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "No PDFs matched to questions"]
            )
        }

        let ordered = pairs.sorted { $0.question.seq < $1.question.seq }

        // ---------------- Temp processed directory ----------------
        let processedDir = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".processed", isDirectory: true)

        try? FileManager.default.removeItem(at: processedDir)
        try FileManager.default.createDirectory(
            at: processedDir,
            withIntermediateDirectories: true
        )

        // ---------------- Process each question PDF ----------------
        var processedPDFs: [(question: Question, url: URL, pageCount: Int)] = []
        for item in ordered {
            
            let q = item.question
            let inputURL = item.pdfURL
            let outURL = processedDir.appendingPathComponent("question_\(q.seq).pdf")

            let pageCount = try processSingleQuestionPDF(
                question: q,
                inputURL: inputURL,
                outputURL: outURL,
                hideAnswersOnQuestionPages: hideAnswersOnQuestionPages
            )

            processedPDFs.append((q, outURL, pageCount))
        }

        // ---------------- Merge PDFs WITH progress ----------------
        let merged = PDFDocument()
        var questionStartPageIndex: [Int: Int] = [:]

        let total = processedPDFs.count
        var completed = 0
        var currentIndex = 0

        for item in processedPDFs {
            try autoreleasepool {

                questionStartPageIndex[item.question.seq] = currentIndex

                guard let doc = PDFDocument(url: item.url) else {
                    throw NSError(
                        domain: "PDFService",
                        code: -20,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Failed to open processed PDF: \(item.url.lastPathComponent)"]
                    )
                }

                for pageIndex in 0..<doc.pageCount {
                    if let page = doc.page(at: pageIndex) {
                        merged.insert(page, at: merged.pageCount)
                    }
                }

                currentIndex += doc.pageCount
                completed += 1

                if let onMergeProgress, completed % 5 == 0 || completed == total {
                    onMergeProgress(Double(completed) / Double(total))
                }
            }
        }

        // ---------------- Prepend exam summary ----------------
        let summaryPage = try makeExamSummaryPage(questions: questions)
        merged.insert(summaryPage, at: 0)
        
        // ---------------- Add Table of Contents ----------------
        addTOC(
            to: merged,
            questions: processedPDFs.map { $0.question },
            questionStartPageIndex: questionStartPageIndex,
            summaryInsertedAtFront: true
        )

        // ---------------- Write final PDF ----------------
        if !merged.write(to: outputURL) {
            throw NSError(
                domain: "PDFService",
                code: -30,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write merged PDF"]
            )
        }

        log("PDF created ✔")
        
    }
    // MARK: - Table of Contents (Outline)

    private static func addTOC(
        to document: PDFDocument,
        questions: [Question],
        questionStartPageIndex: [Int: Int],
        summaryInsertedAtFront: Bool
    ) {
        let root = PDFOutline()
        root.label = "Questions"

        for q in questions.sorted(by: { $0.seq < $1.seq }) {

            guard let startIndex = questionStartPageIndex[q.seq] else { continue }

            // If summary page was inserted at front, shift by +1
            let pageIndex = summaryInsertedAtFront
                ? startIndex + 1
                : startIndex

            guard let page = document.page(at: pageIndex) else { continue }

            let dest = PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))

            let item = PDFOutline()
            item.label = "Question \(q.seq)"
            item.destination = dest

            root.insertChild(item, at: root.numberOfChildren)
        }

        document.outlineRoot = root
    }
    // MARK: - Per-question processing

    private static func processSingleQuestionPDF(
        question: Question,
        inputURL: URL,
        outputURL: URL,
        hideAnswersOnQuestionPages: Bool
    ) throws -> Int {

        guard let doc = PDFDocument(url: inputURL) else {
            throw NSError(
                domain: "PDFService",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey:
                    "Failed to open PDF: \(inputURL.lastPathComponent)"]
            )
        }

        // Stamp question number
        stampQuestionNumber(question.seq, in: doc)

        // Hide answer lines
        if hideAnswersOnQuestionPages {
            hideLine(prefix: "Correct Answer:", in: doc)
            hideLine(prefix: "Incorrect Answers:", in: doc)
        }

        // Append answer summary
        let summaryPage = try makeAnswerSummaryPage(
            question: question,
            correctAnswerText: extractCorrectAnswer(from: doc)
        )
        doc.insert(summaryPage, at: doc.pageCount)

        if !doc.write(to: outputURL) {
            throw NSError(
                domain: "PDFService",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey:
                    "Failed to write processed PDF"]
            )
        }

        return doc.pageCount
    }

    // MARK: - Stamp question number

    private static func stampQuestionNumber(_ seq: Int, in doc: PDFDocument) {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }

            let bounds = page.bounds(for: .mediaBox)

            let header = PDFAnnotation(
                bounds: CGRect(
                    x: bounds.width - 160,
                    y: bounds.height - 30,
                    width: 150,
                    height: 20
                ),
                forType: .freeText,
                withProperties: nil
            )

            header.contents = "Question \(seq)"
            header.font = .systemFont(ofSize: 10)
            header.fontColor = .black
            header.color = .clear
            header.alignment = .right

            page.addAnnotation(header)
        }
    }

    // MARK: - Hide answer lines

    private static func hideLine(prefix: String, in doc: PDFDocument) {
        let selections = doc.findString(prefix, withOptions: [.caseInsensitive])

        for sel in selections {
            guard let page = sel.pages.first else { continue }

            let bounds = sel.bounds(for: page)
            let pageBounds = page.bounds(for: .mediaBox)

            let cover = PDFAnnotation(
                bounds: CGRect(
                    x: pageBounds.minX,
                    y: bounds.minY - 2,
                    width: pageBounds.width,
                    height: max(bounds.height + 4, 14)
                ),
                forType: .square,
                withProperties: nil
            )

            cover.color = .clear
            cover.interiorColor = .white
            cover.border = PDFBorder()
            cover.border?.lineWidth = 0

            page.addAnnotation(cover)
        }
    }

    // MARK: - Correct answer extraction

    private static func extractCorrectAnswer(from doc: PDFDocument) -> String? {
        let hits = doc.findString("Correct Answer:", withOptions: [.caseInsensitive])
        guard let hit = hits.first, let page = hit.pages.first else { return nil }
        return page.string?
            .components(separatedBy: "\n")
            .first { $0.lowercased().contains("correct answer") }
    }

    // MARK: - Answer summary page

    private static func makeAnswerSummaryPage(
        question: Question,
        correctAnswerText: String?
    ) throws -> PDFPage {

        var lines: [PDFPageFactory.TextLine] = [
            .init(text: "Question \(question.seq)",
                  font: .systemFont(ofSize: 14),
                  color: .black),
            .init(text: (correctAnswerText ?? "ERROR"),
                  font: .systemFont(ofSize: 14),
                  color: .green),
            .init(text: "Your Answer: \(question.selectedAnswer)",
                  font: .systemFont(ofSize: 14),
                  color: .black),
            .init(text: "Time (sec): \(Int(question.timeSeconds))",
                  font: .systemFont(ofSize: 13),
                  color: .black),
            .init(text: "Topic: \(question.topic)",
                  font: .systemFont(ofSize: 14),
                  color: .black),
            .init(text: "Description: \(question.description)",
                  font: .systemFont(ofSize: 14),
                  color: .black),
            .init(text: "ID: \(question.id)",
                  font: .systemFont(ofSize: 14),
                  color: .black)
        ]

//        if let correctAnswerText {
//            lines.append(.init(
//                text: correctAnswerText,
//                font: .systemFont(ofSize: 14),
//                color: .black
//            ))
//        }

        return try PDFPageFactory.makeTextPage(
            title: "Answer Summary",
            lines: lines
        )
    }

    // MARK: - Exam summary page

    private static func makeExamSummaryPage(questions: [Question]) throws -> PDFPage {

        let ordered = questions.sorted { $0.seq < $1.seq }
        let correctFlags = ordered.map {
            $0.correctness.lowercased() == "correct"
        }

        let total = correctFlags.count
        let correct = correctFlags.filter { $0 }.count

        var lines: [PDFPageFactory.TextLine] = [
            .init(text: "Total Score: \(correct) / \(total)",
                  font: .systemFont(ofSize: 18, weight: .bold),
                  color: .black)
        ]

        let blockSize = 50
        var index = 0
        var block = 1

        while index < total {
            let end = min(index + blockSize, total)
            let slice = correctFlags[index..<end]
            let blockCorrect = slice.filter { $0 }.count

            lines.append(.init(
                text: "Block \(block) (Q\(index + 1)–Q\(end)): \(blockCorrect) / \(end - index)",
                font: .systemFont(ofSize: 14),
                color: .black
            ))

            index += blockSize
            block += 1
        }

        return try PDFPageFactory.makeTextPage(
            title: "Exam Summary",
            lines: lines
        )
    }

    // MARK: - Matching logic

    private static func matchDownloadedPDFsToQuestions(
        questions: [Question],
        downloadedPDFs: [URL]
    ) -> [(question: Question, pdfURL: URL)] {

        func extractInt(_ url: URL) -> Int? {
            let name = url.deletingPathExtension().lastPathComponent
            return Int(name.components(separatedBy: "_").last ?? "")
        }

        var map: [Int: URL] = [:]
        for u in downloadedPDFs {
            if let n = extractInt(u) {
                map[n] = u
            }
        }

        return questions.compactMap { q in
            map[q.seq].map { (q, $0) }
        }
    }
}
