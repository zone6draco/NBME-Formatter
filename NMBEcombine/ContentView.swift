import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {

    @StateObject private var viewModel = ProcessorViewModel()

    @State private var csvURL: URL?
    @State private var hideCorrectAnswer: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: - Output Folder Picker
            VStack(alignment: .leading, spacing: 6) {
                Button("Choose Output Folder") {
                    pickOutputFolder()
                }
                .disabled(viewModel.isRunning)

                if let dir = viewModel.outputDirectory {
                    Text("Output: \(dir.path)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Output: ~/Downloads (default)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // MARK: - CSV Picker
            Button {
                pickCSV()
            } label: {
                Text(csvURL == nil ? "Choose CSV File" : csvURL!.lastPathComponent)
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isRunning)

            // MARK: - Options
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Hide correct answer under the question",
                    isOn: $hideCorrectAnswer
                )
                .disabled(viewModel.isRunning)

                Text("If checked, correct answers will still be available on question summary page after each question. Enabling will only hide the correct answer line that is directly under the answer choices")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20) // aligns with toggle label
            }

            // MARK: - Progress
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)

            // MARK: - Run Button
            Button {
                if let csvURL {
                    viewModel.hideCorrectAnswer = hideCorrectAnswer
                    print(hideCorrectAnswer)
                    viewModel.runPipeline(csvURL: csvURL)
                }
            } label: {
                Text(viewModel.isRunning ? "Processing…" : "Convert & Merge PDFs")
                    .frame(maxWidth: .infinity)
            }
            .disabled(csvURL == nil || viewModel.isRunning)

            // MARK: - Log Output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("BOTTOM")
                }
                .onChange(of: viewModel.logText) { _ in
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 220)
            .border(Color.gray.opacity(0.3))

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 520)
        .onDisappear {
            // Safety: release security scope if still held
            viewModel.outputDirectory?.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Pick Output Folder

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // ✅ FAST — single state change
            DispatchQueue.main.async {
                self.viewModel.outputDirectory = url
            }
        }
    }

    // MARK: - Pick CSV

    private func pickCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            csvURL = panel.url
        }
    }
}
