// Services/DownloadService.swift
import Foundation
import PDFKit

enum DownloadError: LocalizedError {
    case expired
    case network(String)

    var errorDescription: String? {
        switch self {
        case .expired:
            return """
Please redownload CSV and re-drag it into the app,
the links to the questions have expired
"""
        case .network(let msg):
            return msg
        }
    }
}

struct DownloadService {

    /// Preflight: verify the first link resolves to a real PDF
    static func preflightCheck(resolverURL: URL) async throws {
        var request = URLRequest(url: resolverURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw DownloadError.expired
        }

        guard
            let pdf = PDFDocument(data: data),
            pdf.pageCount > 0
        else {
            throw DownloadError.expired
        }
    }

    /// Download ALL PDFs in chunks of 100, with limited concurrency
    static func downloadAll(
        questions: [Question],
        to directory: URL,
        maxConcurrent: Int,
        onProgress: @escaping (Int, Int) -> Void,
        log: @escaping (String) -> Void
    ) async throws -> [URL] {

        let chunkSize = 100
        var downloadedURLs: [URL] = []
        let total = questions.count
        var completed = 0

        for chunkStart in stride(from: 0, to: total, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, total)
            let chunk = questions[chunkStart..<chunkEnd]

            log("Downloading questions \(chunkStart + 1)–\(chunkEnd)")

            try await withThrowingTaskGroup(of: URL.self) { group in
                var iterator = chunk.makeIterator()

                // Start initial batch
                for _ in 0..<maxConcurrent {
                    if let q = iterator.next() {
                        group.addTask {
                            try await downloadOne(question: q, to: directory)
                        }
                    }
                }

                while let result = try await group.next() {
                    downloadedURLs.append(result)
                    completed += 1
                    onProgress(completed, total)

                    if let next = iterator.next() {
                        group.addTask {
                            try await downloadOne(question: next, to: directory)
                        }
                    }
                }
            }
        }

        return downloadedURLs
    }

    /// Download a single PDF
    private static func downloadOne(
        question: Question,
        to directory: URL
    ) async throws -> URL {

        let filename = "question_\(question.seq).pdf"
        let destination = directory.appendingPathComponent(filename)

        var request = URLRequest(url: question.explanationURL)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw DownloadError.expired
        }

        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw DownloadError.expired
        }

        try data.write(to: destination, options: .atomic)
        return destination
    }
}
