import SwiftUI
import UIKit

struct ReportDownloadButton: View {
    @EnvironmentObject private var store: LedgerStore

    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date

    @State private var isGenerating = false
    @State private var shareFile: QuickReportShareFile?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            Button {
                generate(.pdf)
            } label: {
                Label("PDF", systemImage: "doc.richtext.fill")
            }

            Button {
                generate(.excel)
            } label: {
                Label("Excel", systemImage: "tablecells.fill")
            }
        } label: {
            Group {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.purple)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating)
        .accessibilityLabel("Download \(type.rawValue)")
        .sheet(item: $shareFile) { file in
            QuickReportActivityView(items: [file.url])
                .ignoresSafeArea()
        }
        .alert("Report Export", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The report could not be generated.")
        }
    }

    private func generate(_ format: ProfessionalExportFormat) {
        isGenerating = true
        defer { isGenerating = false }

        let document = ProfessionalReportBuilder.build(
            type: type,
            startDate: startDate,
            endDate: endDate,
            store: store
        )

        do {
            let url = try ProfessionalReportExporter.export(document, format: format)
            shareFile = QuickReportShareFile(url: url)
        } catch {
            errorMessage = "The \(format.rawValue) report could not be generated. \(error.localizedDescription)"
        }
    }
}

struct ProfessionalReportTypeView: View {
    let type: ProfessionalReportType

    @AppStorage("ProfessionalReportStartDateV1") private var storedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("ProfessionalReportEndDateV1") private var storedEndDate = Date().timeIntervalSince1970

    private var startDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStartDate) },
            set: { value in
                storedStartDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedStartDate > storedEndDate { storedEndDate = storedStartDate }
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEndDate) },
            set: { value in
                storedEndDate = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                if storedEndDate < storedStartDate { storedStartDate = storedEndDate }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: type.icon)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.rawValue)
                            .font(.headline)
                        Text(type.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 5)
            }

            Section(type.usesAsOfDateOnly ? "Report Date" : "Period") {
                if type.usesAsOfDateOnly {
                    DatePicker("As of", selection: endDate, displayedComponents: .date)
                } else {
                    DatePicker("From", selection: startDate, displayedComponents: .date)
                    DatePicker("To", selection: endDate, in: startDate.wrappedValue..., displayedComponents: .date)
                }
            }

            Section {
                Label("Tap the download button above and choose PDF or Excel.", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ReportDownloadButton(
                    type: type,
                    startDate: startDate.wrappedValue,
                    endDate: endDate.wrappedValue
                )
            }
        }
    }
}

private struct QuickReportShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QuickReportActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
