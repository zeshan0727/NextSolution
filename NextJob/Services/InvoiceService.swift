import Foundation
import UIKit

struct InvoiceResult {
    let url: URL
    let number: String
    let issuedDate: Date
    let dueDate: Date
}

enum InvoiceError: LocalizedError {
    case jobNotCompleted
    case paymentAlreadyReceived
    case missingPrice
    case couldNotCreate

    var errorDescription: String? {
        switch self {
        case .jobNotCompleted:
            return "Complete the job before creating its invoice."
        case .paymentAlreadyReceived:
            return "This job is already marked as paid. Change it to Payment Pending to create an invoice."
        case .missingPrice:
            return "Add a job price before creating an invoice."
        case .couldNotCreate:
            return "The invoice PDF could not be created."
        }
    }
}

@MainActor
extension JobStore {
    func setPaymentStatus(_ status: PaymentStatus, jobID: UUID) {
        guard var job = job(id: jobID) else { return }
        job.paymentStatus = status
        job.paymentReceivedDate = status == .received ? Date() : nil
        save(job)
    }

    func recordInvoice(
        number: String,
        issuedDate: Date,
        dueDate: Date,
        jobID: UUID
    ) {
        guard var job = job(id: jobID) else { return }
        job.paymentStatus = .pending
        job.paymentReceivedDate = nil
        job.invoiceNumber = number
        job.invoiceIssuedDate = issuedDate
        job.invoiceDueDate = dueDate
        save(job)
    }
}

final class InvoiceService {
    static let shared = InvoiceService()

    private let fileManager = FileManager.default

    private init() {}

    func createInvoice(job: JobRecord, settings: AppSettings) throws -> InvoiceResult {
        guard job.status == .completed else { throw InvoiceError.jobNotCompleted }
        guard job.effectivePaymentStatus != .received else { throw InvoiceError.paymentAlreadyReceived }
        guard job.price > 0 else { throw InvoiceError.missingPrice }

        let issuedDate = job.invoiceIssuedDate ?? Date()
        let termsDays = max(0, settings.invoiceTermsDays ?? 7)
        let dueDate = job.invoiceDueDate
            ?? Calendar.current.date(byAdding: .day, value: termsDays, to: issuedDate)
            ?? issuedDate
        let number = job.invoiceNumber ?? Self.makeInvoiceNumber(job: job, date: issuedDate)

        let safeCompany = Self.safeName(job.clientName.isEmpty ? "Client" : job.clientName)
        let safeJob = Self.safeName(job.title)
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("Invoice - \(safeCompany) - \(safeJob) - \(number).pdf")

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            drawInvoice(
                in: pageRect,
                job: job,
                settings: settings,
                number: number,
                issuedDate: issuedDate,
                dueDate: dueDate
            )
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw InvoiceError.couldNotCreate
        }
        return InvoiceResult(url: url, number: number, issuedDate: issuedDate, dueDate: dueDate)
    }

    private func drawInvoice(
        in page: CGRect,
        job: JobRecord,
        settings: AppSettings,
        number: String,
        issuedDate: Date,
        dueDate: Date
    ) {
        let margin: CGFloat = 48
        let contentWidth = page.width - (margin * 2)
        var y: CGFloat = 46

        drawText(
            "INVOICE",
            frame: CGRect(x: margin, y: y, width: contentWidth, height: 44),
            font: .systemFont(ofSize: 30, weight: .bold),
            color: .black
        )
        y += 48

        let fromName = cleaned(settings.invoiceFromName) ?? "Next Solution – Zeeshan Barvi"
        let fromEmail = cleaned(settings.invoiceFromEmail)
        let fromAddress = cleaned(settings.invoiceFromAddress) ?? "Doha, Qatar"

        drawText(
            fromName,
            frame: CGRect(x: margin, y: y, width: contentWidth * 0.58, height: 24),
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .black
        )
        drawText(
            "Invoice No: \(number)\nIssued: \(Self.dateFormatter.string(from: issuedDate))\nDue: \(Self.dateFormatter.string(from: dueDate))",
            frame: CGRect(x: margin + contentWidth * 0.60, y: y, width: contentWidth * 0.40, height: 62),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .darkGray,
            alignment: .right
        )
        y += 23
        drawText(
            [fromAddress, fromEmail].compactMap { $0 }.joined(separator: "\n"),
            frame: CGRect(x: margin, y: y, width: contentWidth * 0.58, height: 44),
            font: .systemFont(ofSize: 10),
            color: .darkGray
        )
        y += 70

        drawLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: page.width - margin, y: y), width: 1.2)
        y += 22

        drawText(
            "BILL TO",
            frame: CGRect(x: margin, y: y, width: contentWidth, height: 18),
            font: .systemFont(ofSize: 10, weight: .bold),
            color: .gray
        )
        y += 20
        drawText(
            job.clientName.isEmpty ? "Client" : job.clientName,
            frame: CGRect(x: margin, y: y, width: contentWidth, height: 24),
            font: .systemFont(ofSize: 16, weight: .semibold),
            color: .black
        )
        y += 42

        let headerHeight: CGFloat = 34
        UIColor(white: 0.94, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: headerHeight), cornerRadius: 5).fill()
        drawText("DESCRIPTION", frame: CGRect(x: margin + 12, y: y + 9, width: contentWidth - 160, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: .darkGray)
        drawText("AMOUNT", frame: CGRect(x: page.width - margin - 130, y: y + 9, width: 118, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: .darkGray, alignment: .right)
        y += headerHeight + 14

        let description = "\(job.jobType) – \(job.title)"
        drawText(description, frame: CGRect(x: margin + 12, y: y, width: contentWidth - 170, height: 42), font: .systemFont(ofSize: 12, weight: .medium), color: .black)
        drawText("\(settings.currency) \(String(format: "%.2f", job.price))", frame: CGRect(x: page.width - margin - 130, y: y, width: 118, height: 24), font: .systemFont(ofSize: 12, weight: .semibold), color: .black, alignment: .right)
        y += 54
        drawLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: page.width - margin, y: y), color: UIColor(white: 0.82, alpha: 1), width: 0.8)
        y += 18

        let completedText = job.completedDate.map { Self.dateTimeFormatter.string(from: $0) } ?? "Not recorded"
        let detailText = "Job status: \(job.status.title)\nCompleted: \(completedText)\nTarget time: \(job.targetTimeText)\nActual time: \(job.actualTimeText)"
        drawText(detailText, frame: CGRect(x: margin + 12, y: y, width: contentWidth * 0.58, height: 76), font: .systemFont(ofSize: 10), color: .darkGray)

        drawText("TOTAL", frame: CGRect(x: page.width - margin - 220, y: y + 2, width: 90, height: 20), font: .systemFont(ofSize: 12, weight: .bold), color: .black, alignment: .right)
        drawText("\(settings.currency) \(String(format: "%.2f", job.price))", frame: CGRect(x: page.width - margin - 125, y: y, width: 125, height: 24), font: .systemFont(ofSize: 15, weight: .bold), color: .black, alignment: .right)
        y += 92

        if let notes = cleaned(job.notes) {
            drawText("JOB NOTES", frame: CGRect(x: margin, y: y, width: contentWidth, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: .gray)
            y += 20
            let noteHeight = min(110, max(42, notes.boundingRect(with: CGSize(width: contentWidth, height: 180), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: 10)], context: nil).height + 8))
            drawText(notes, frame: CGRect(x: margin, y: y, width: contentWidth, height: noteHeight), font: .systemFont(ofSize: 10), color: .darkGray)
            y += noteHeight + 18
        }

        let instructions = cleaned(settings.invoicePaymentInstructions)
            ?? "Please arrange payment against this invoice and quote the invoice number."
        drawText("PAYMENT INFORMATION", frame: CGRect(x: margin, y: y, width: contentWidth, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: .gray)
        y += 20
        drawText(instructions, frame: CGRect(x: margin, y: y, width: contentWidth, height: 52), font: .systemFont(ofSize: 10), color: .darkGray)

        drawText(
            "Prepared with Next Job • Next Solution – Zeeshan Barvi",
            frame: CGRect(x: margin, y: page.height - 52, width: contentWidth, height: 18),
            font: .systemFont(ofSize: 9),
            color: .gray,
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        frame: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        text.draw(in: frame, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func drawLine(
        from: CGPoint,
        to: CGPoint,
        color: UIColor = .black,
        width: CGFloat
    ) {
        color.setStroke()
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = width
        path.stroke()
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func makeInvoiceNumber(job: JobRecord, date: Date) -> String {
        let datePart = invoiceDateFormatter.string(from: date)
        let jobPart = job.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(5).uppercased()
        return "INV-\(datePart)-\(jobPart)"
    }

    private static func safeName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Job" : String(cleaned.prefix(60))
    }

    private static let invoiceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
