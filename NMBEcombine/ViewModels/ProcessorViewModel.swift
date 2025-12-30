import Foundation
import Combine
var progressDone = false

@MainActor
final class ProcessorViewModel: ObservableObject {

    // MARK: - Published UI State
    @Published var logText: String = ""
    @Published var progress: Double = 0.0
    @Published var isRunning: Bool = false

    // MARK: - User Options
    var hideCorrectAnswer: Bool = true
    var outputDirectory: URL?

    // MARK: - Constants
    private let appName = "ExamPDFProcessor"

    // MARK: - Logging
    func log(_ msg: String) {
        logText += msg + "\n"
    }

    // MARK: - App Support Directory
    private func appSupportDir() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Safe Output Filename
    private func uniqueOutputURL(_ url: URL) -> URL {
        let fm = FileManager.default
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()

        var candidate = url
        var counter = 1

        while fm.fileExists(atPath: candidate.path) {
            let newName = "\(baseName) (\(counter)).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        }

        return candidate
    }

    // MARK: - Main Pipeline Entry
    func runPipeline(csvURL: URL) {
        if isRunning { return }

        isRunning = true
        progress = 0
        logText = ""

        Task {
            defer {
                if let dir = outputDirectory {
                    dir.stopAccessingSecurityScopedResource()
                }
                isRunning = false
            }

            do {
                // -------------------------
                // Read CSV
                // -------------------------
                log("Reading CSV...")
                progress = 0.02

                let questions = try CSVService.loadQuestions(from: csvURL)
                log("Loaded \(questions.count) questions")

                guard let first = questions.first else {
                    log("X ERROR: CSV has no questions")
                    return
                }

                // -------------------------
                // Preflight Check
                // -------------------------
                log("Running preflight check on first question...")
                progress = 0.05

                try await DownloadService.preflightCheck(
                    resolverURL: first.explanationURL
                )
                log("Preflight check passed ✔")

                // -------------------------
                // Determine Output Directory
                // -------------------------
                let outDir: URL
                if let outputDirectory {
                    outDir = outputDirectory
                } else {
                    outDir = try FileManager.default.url(
                        for: .downloadsDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: false
                    )
                }

                try FileManager.default.createDirectory(
                    at: outDir,
                    withIntermediateDirectories: true
                )

                // -------------------------
                // Temp Download Directory
                // -------------------------
                let support = try appSupportDir()
                let downloadsDir = support.appendingPathComponent(
                    "Downloads",
                    isDirectory: true
                )

                // Clean previous run
                try? FileManager.default.removeItem(at: downloadsDir)
                try FileManager.default.createDirectory(
                    at: downloadsDir,
                    withIntermediateDirectories: true
                )

                // -------------------------
                // Download PDFs
                // -------------------------
                log("Starting downloads (100 at a time)...")

                let downloaded = try await DownloadService.downloadAll(
                    questions: questions,
                    to: downloadsDir,
                    maxConcurrent: 100,
                    onProgress: { completed, total in
                        let frac = Double(completed) / Double(max(total, 1))
                        Task { @MainActor in
                            self.progress = 0.05 + (0.5 * frac)
                            self.log("Downloaded \(completed) / \(total)")
                        }
                    },
                    log: { msg in
                        Task { @MainActor in
                            self.log(msg)
                        }
                    }
                )

                // -------------------------
                // Output PDF Path
                // -------------------------
                let outputName =
                    csvURL.deletingPathExtension().lastPathComponent
                    + "_merged.pdf"

                let baseOutput = outDir.appendingPathComponent(outputName)
                let finalOutputPDF = uniqueOutputURL(baseOutput)

                // -------------------------
                // Merge PDFs (OFF main thread)
                // -------------------------
                
                progress = 0.5
                log("Processing PDFs, this might take a minute...")

                // Capture everything needed BEFORE leaving MainActor
                let questionsCopy = questions
                let downloadedCopy = downloaded
                let hideAnswers = self.hideCorrectAnswer   // ✅ explicit self
                let outputURL = finalOutputPDF

                let finalURL = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    // Helps avoid memory bloat / stalls during PDFKit work
                    try autoreleasepool {
                        let orderedPDFs = downloadedCopy.sorted {
                            let a = Int($0.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "") ?? 0
                            let b = Int($1.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "") ?? 0
                            return a < b
                        }

                        try PDFService.buildFinalReport(
                            questions: questionsCopy,
                            downloadedPDFs: orderedPDFs,
                            hideAnswersOnQuestionPages: hideAnswers,
                            outputURL: outputURL,
                            log: { _ in },
                            onProcessProgress: { completed, total in
                                let frac = Double(completed) / Double(max(total, 1))
                                Task { @MainActor in
                                    self.progress = 0.5 + (0.4 * frac)
                                    self.log("Processed \(completed) / \(total)")
                                }
                            },
                            onSaveProgress: { completed in
                                if (completed==9){
                                    self.log("Saving PDF...")
                                    Task { @MainActor in
                                        for num1 in 1...20{
                                            if (!progressDone){
                                                self.progress = 0.9 + (0.0045 * Double(num1))
                                                try await Task.sleep(nanoseconds: 500_000_000)
                                            }

                                        }
                                        
    //                                    self.log("Merged \(completed) / \(total)")
                                    }
                                }

                            }
                            // 🚫 do not touch UI here
                        )

                        return outputURL
                    }
                }.value

                // Back on MainActor
                progress = 1.0
                
                log("✔ DONE → \(finalURL.lastPathComponent)")

            } catch {
                if let de = error as? DownloadError {
                    log(de.localizedDescription)
                } else {
                    log("X ERROR: \(error.localizedDescription)")
                }
            }
        }
    }
}
