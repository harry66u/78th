import PhotosUI
import SwiftUI
import UIKit
import ScheduleEngine

/// Path A: paste and parse. The primary route.
struct PasteImportView: View {

    @Environment(SocialStore.self) private var social
    @State private var text = ""
    @State private var importer = ImportCoordinator()

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .font(.callout.monospaced())
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste your schedule here. A table, an email, a wall of text: all fine.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Paste your schedule")
            } footer: {
                Text("The text is sent to a parser to turn into periods. Nothing is saved until you check it on the next screen.")
            }

            Section {
                Button {
                    Task { await importer.parse(text: text, imageData: nil) }
                } label: {
                    if importer.isWorking {
                        HStack { ProgressView(); Text("Reading it") }
                    } else {
                        Text("Read my schedule")
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || importer.isWorking)
            }

            if let error = importer.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Paste")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importer.result) { result in
            ReviewImportView(result: result)
        }
        .onAppear { importer.backend = social }
    }
}

/// Path B: photo import. Same contract, same review screen.
struct PhotoImportView: View {

    @Environment(SocialStore.self) private var social
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var importer = ImportCoordinator()

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label(imageData == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo")
                }

                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } header: {
                Text("Photograph your schedule")
            } footer: {
                Text("Flat, well lit, whole page in frame. You confirm everything on the next screen before it is saved.")
            }

            Section {
                Button {
                    Task { await importer.parse(text: nil, imageData: imageData) }
                } label: {
                    if importer.isWorking {
                        HStack { ProgressView(); Text("Reading it") }
                    } else {
                        Text("Read my schedule")
                    }
                }
                .disabled(imageData == nil || importer.isWorking)
            }

            if let error = importer.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importer.result) { result in
            ReviewImportView(result: result)
        }
        .onAppear { importer.backend = social }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                imageData = try? await item.loadTransferable(type: Data.self)
            }
        }
    }
}

/// Runs a parse and hands the result to the review screen. Never writes.
@MainActor
@Observable
final class ImportCoordinator {

    var isWorking = false
    var errorMessage: String?
    var result: ParsedSchedule?

    /// Set by the view; the parse runs through the backend's edge function so no
    /// model key ships in the app.
    var backend: SocialStore?

    func parse(text: String?, imageData: Data?) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard let parser = backend else {
            errorMessage = "No parser is configured in this build. Use the grid instead."
            return
        }

        do {
            let raw = try await parser.parseSchedule(text: text, imageData: imageData)
            let payload = try ScheduleImporter.decode(raw)
            let imported = ScheduleImporter.makeConfiguration(from: payload)
            guard !imported.configuration.templates.isEmpty else {
                errorMessage = "Nothing in there looked like a schedule. Try the grid, or paste a bit more."
                return
            }
            result = ParsedSchedule(
                configuration: imported.configuration,
                issues: imported.issues,
                courseCount: imported.courseCount
            )
        } catch let error as SocialBackendError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "That did not come back as a schedule. Try the grid, or paste a bit more."
        }
    }
}

/// The parsed result, carried to the review screen. `Identifiable` so it can
/// drive a navigation destination.
struct ParsedSchedule: Identifiable, Hashable {
    let id = UUID()
    var configuration: ScheduleConfiguration
    var issues: [ImportIssue]
    var courseCount: Int
}
