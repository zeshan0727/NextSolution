import SwiftUI

struct PaymentInvoiceView: View {
    @EnvironmentObject private var store: JobStore
    let jobID: UUID

    @State private var sharePayload: SharePayload?
    @State private var isCreatingInvoice = false
    @State private var noticeTitle = ""
    @State private var noticeMessage = ""
    @State private var showingNotice = false

    private var job: JobRecord? { store.job(id: jobID) }

    var body: some View {
        Group {
            if let job {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionTitle(title: "Payment & Invoice", systemImage: "banknote.fill")
                        Spacer()
                        if let status = job.effectivePaymentStatus {
                            Label(status.shortTitle, systemImage: status.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(status.tint)
                        }
                    }

                    detailRow("Job price", "\(store.settings.currency) \(String(format: "%.2f", job.price))")
                    if let receivedDate = job.paymentReceivedDate {
                        detailRow("Payment received", receivedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let invoiceNumber = job.invoiceNumber {
                        detailRow("Invoice", invoiceNumber)
                    }
                    if let dueDate = job.invoiceDueDate, job.effectivePaymentStatus == .pending {
                        detailRow("Invoice due", dueDate.formatted(date: .abbreviated, time: .omitted))
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.setPaymentStatus(.pending, jobID: job.id)
                        } label: {
                            Label("Pending", systemImage: "clock.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)

                        Button {
                            store.setPaymentStatus(.received, jobID: job.id)
                        } label: {
                            Label("Received", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    Button {
                        createInvoice(job)
                    } label: {
                        Label(
                            job.invoiceNumber == nil ? "Create & Share Invoice PDF" : "Recreate & Share Invoice PDF",
                            systemImage: "doc.richtext.fill"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingInvoice || job.status != .completed || job.price <= 0 || job.effectivePaymentStatus == .received)

                    if job.status != .completed {
                        Text("Complete the job before creating an invoice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if job.price <= 0 {
                        Text("Add a job price before creating an invoice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if job.effectivePaymentStatus == .received {
                        Text("The invoice button is disabled because payment is marked as received.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassCard()
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .alert(noticeTitle, isPresented: $showingNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func createInvoice(_ job: JobRecord) {
        isCreatingInvoice = true
        let settings = store.settings
        Task {
            defer { isCreatingInvoice = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try InvoiceService.shared.createInvoice(job: job, settings: settings)
                }.value
                store.recordInvoice(
                    number: result.number,
                    issuedDate: result.issuedDate,
                    dueDate: result.dueDate,
                    jobID: job.id
                )
                sharePayload = SharePayload(items: [result.url])
            } catch {
                showNotice("Invoice Not Created", error.localizedDescription)
            }
        }
    }

    private func showNotice(_ title: String, _ message: String) {
        noticeTitle = title
        noticeMessage = message
        showingNotice = true
    }
}
