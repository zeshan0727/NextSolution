#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "NextReminder" / "Sources" / "FileSharing.swift"
text = source.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"Expected FileSharing.swift anchor not found: {old[:180]!r}")
    text = text.replace(old, new, 1)


replace_once(
    '''    case attachmentTooLarge
    case totalTooLarge''',
    '''    case attachmentTooLarge
    case scanCompressionFailed
    case totalTooLarge'''
)
replace_once(
    '''        case .attachmentTooLarge:
            return "Each attachment must be smaller than 10 MB."
        case .totalTooLarge:''',
    '''        case .attachmentTooLarge:
            return "Each attachment must be smaller than 8 MB."
        case .scanCompressionFailed:
            return "The scan could not be compressed below 8 MB while keeping it readable. Scan fewer pages and try again."
        case .totalTooLarge:'''
)
replace_once(
    '''    private let maximumSingleAttachment = 10_000_000''',
    '''    private let maximumSingleAttachment = 8_000_000'''
)
replace_once(
    '''    @State private var isShowingScanner = false
    @State private var isSending = false''',
    '''    @State private var isShowingScanner = false
    @State private var isPreparingScan = false
    @State private var scanStatusMessage: String?
    @State private var isSending = false'''
)
replace_once(
    '''        !isSending
            && !recipients.isEmpty''',
    '''        !isSending
            && !isPreparingScan
            && !recipients.isEmpty'''
)
replace_once(
    '''            SectionHeader(title: "Attach Things", trailing: "Maximum total 18 MB")''',
    '''            SectionHeader(title: "Attach Things", trailing: "Scans stay below 8 MB")'''
)
replace_once(
    '''            if attachments.isEmpty {
                Text("No attachments selected.")''',
    '''            if isPreparingScan {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Compressing scanned document below 8 MB…")
                        .font(.caption.weight(.medium))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nextCard()
            } else if let scanStatusMessage {
                Label(scanStatusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            if attachments.isEmpty {
                Text("No attachments selected.")'''
)
replace_once(
    '''        guard attachment.data.count <= 10_000_000 else {
            errorMessage = "\\(attachment.fileName) is larger than 10 MB."''',
    '''        guard attachment.data.count <= 8_000_000 else {
            errorMessage = "\\(attachment.fileName) is larger than 8 MB."'''
)
replace_once(
    '''                    if let fileSize = values.fileSize, fileSize > 10_000_000 {
                        errorMessage = "\\(url.lastPathComponent) is larger than 10 MB."''',
    '''                    if let fileSize = values.fileSize, fileSize > 8_000_000 {
                        errorMessage = "\\(url.lastPathComponent) is larger than 8 MB."'''
)

old_scan = '''    private func addScannedDocument(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let pdf = renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let inset = pageBounds.insetBy(dx: 24, dy: 24)
                let imageRatio = image.size.width / max(image.size.height, 1)
                let targetRatio = inset.width / inset.height
                let drawRect: CGRect
                if imageRatio > targetRatio {
                    let height = inset.width / imageRatio
                    drawRect = CGRect(
                        x: inset.minX,
                        y: inset.midY - height / 2,
                        width: inset.width,
                        height: height
                    )
                } else {
                    let width = inset.height * imageRatio
                    drawRect = CGRect(
                        x: inset.midX - width / 2,
                        y: inset.minY,
                        width: width,
                        height: inset.height
                    )
                }
                image.draw(in: drawRect)
            }
        }
        addAttachment(
            FileShareAttachment(
                fileName: "Scanned-Document-\\(Int(Date().timeIntervalSince1970)).pdf",
                mimeType: "application/pdf",
                data: pdf
            )
        )
    }
'''
new_scan = '''    private func addScannedDocument(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isPreparingScan = true
        scanStatusMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let pdf = ScannedDocumentCompressor.makePDF(from: images)
            DispatchQueue.main.async {
                isPreparingScan = false
                guard let pdf else {
                    errorMessage = FileShareError.scanCompressionFailed.localizedDescription
                    return
                }

                addAttachment(
                    FileShareAttachment(
                        fileName: "Scanned-Document-\\(Int(Date().timeIntervalSince1970)).pdf",
                        mimeType: "application/pdf",
                        data: pdf
                    )
                )
                scanStatusMessage = "Scan compressed to \\(ByteCountFormatter.string(fromByteCount: Int64(pdf.count), countStyle: .file))."
            }
        }
    }
'''
replace_once(old_scan, new_scan)
replace_once(
    '''        attachments = []
        selectedPhotos = []''',
    '''        attachments = []
        selectedPhotos = []
        scanStatusMessage = nil'''
)

helper_anchor = '''struct FlowRecipientList: View {'''
helper = r'''private enum ScannedDocumentCompressor {
    // Leave headroom below the requested 8 MB attachment limit.
    static let targetBytes = 7_500_000
    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func makePDF(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        var pageBudget = max(45_000, Int(Double(targetBytes) * 0.82 / Double(images.count)))
        var smallestPDF: Data?

        for _ in 0..<9 {
            autoreleasepool {
                let jpegPages = images.compactMap {
                    compressedJPEG(from: $0, maximumBytes: pageBudget)
                }
                guard jpegPages.count == images.count else { return }

                let pdf = renderPDF(jpegPages: jpegPages)
                if smallestPDF == nil || pdf.count < smallestPDF!.count {
                    smallestPDF = pdf
                }
                guard pdf.count > targetBytes else {
                    smallestPDF = pdf
                    return
                }

                let ratio = Double(targetBytes) / Double(max(pdf.count, 1))
                let reduction = max(0.42, min(0.78, ratio * 0.80))
                pageBudget = max(18_000, Int(Double(pageBudget) * reduction))
            }
            if let smallestPDF, smallestPDF.count <= targetBytes {
                return smallestPDF
            }
        }

        // Emergency document preset for unusually long scans.
        let emergencyBudget = max(14_000, Int(Double(targetBytes) * 0.72 / Double(images.count)))
        let emergencyPages = images.compactMap {
            compressedJPEG(
                from: $0,
                maximumBytes: emergencyBudget,
                startingDimension: 900,
                minimumDimension: 420,
                maximumQuality: 0.42,
                minimumQuality: 0.08
            )
        }
        guard emergencyPages.count == images.count else { return nil }
        let emergencyPDF = renderPDF(jpegPages: emergencyPages)
        return emergencyPDF.count <= targetBytes ? emergencyPDF : nil
    }

    private static func compressedJPEG(
        from image: UIImage,
        maximumBytes: Int,
        startingDimension: CGFloat = 2400,
        minimumDimension: CGFloat = 560,
        maximumQuality: CGFloat = 0.82,
        minimumQuality: CGFloat = 0.10
    ) -> Data? {
        var dimension = startingDimension
        var smallestData: Data?

        while dimension >= minimumDimension {
            let rendered = normalizedImage(image, maximumPixelDimension: dimension)
            var low = minimumQuality
            var high = maximumQuality
            var bestAtDimension: Data?

            for _ in 0..<8 {
                let quality = (low + high) / 2
                guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
                if smallestData == nil || data.count < smallestData!.count {
                    smallestData = data
                }
                if data.count <= maximumBytes {
                    bestAtDimension = data
                    low = quality
                } else {
                    high = quality
                }
            }

            if let bestAtDimension {
                return bestAtDimension
            }
            dimension *= 0.78
        }

        let finalImage = normalizedImage(image, maximumPixelDimension: minimumDimension)
        let finalData = finalImage.jpegData(compressionQuality: minimumQuality)
        if let finalData, finalData.count <= maximumBytes {
            return finalData
        }
        return smallestData?.count ?? Int.max <= maximumBytes ? smallestData : nil
    }

    private static func normalizedImage(
        _ image: UIImage,
        maximumPixelDimension: CGFloat
    ) -> UIImage {
        let sourceWidth = max(1, image.size.width * image.scale)
        let sourceHeight = max(1, image.size.height * image.scale)
        let longest = max(sourceWidth, sourceHeight)
        let scale = min(1, maximumPixelDimension / longest)
        let outputSize = CGSize(
            width: max(1, floor(sourceWidth * scale)),
            height: max(1, floor(sourceHeight * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    private static func renderPDF(jpegPages: [Data]) -> Data {
        UIGraphicsPDFRenderer(bounds: pageBounds).pdfData { context in
            for jpeg in jpegPages {
                guard let image = UIImage(data: jpeg) else { continue }
                context.beginPage()
                let inset = pageBounds.insetBy(dx: 24, dy: 24)
                let imageRatio = image.size.width / max(image.size.height, 1)
                let targetRatio = inset.width / inset.height
                let drawRect: CGRect

                if imageRatio > targetRatio {
                    let height = inset.width / imageRatio
                    drawRect = CGRect(
                        x: inset.minX,
                        y: inset.midY - height / 2,
                        width: inset.width,
                        height: height
                    )
                } else {
                    let width = inset.height * imageRatio
                    drawRect = CGRect(
                        x: inset.midX - width / 2,
                        y: inset.minY,
                        width: width,
                        height: inset.height
                    )
                }
                image.draw(in: drawRect)
            }
        }
    }
}

'''
if helper_anchor not in text:
    raise SystemExit("FlowRecipientList anchor not found")
text = text.replace(helper_anchor, helper + helper_anchor, 1)
source.write_text(text)

project = ROOT / "project.yml"
project_text = project.read_text()
project_text = project_text.replace('CFBundleShortVersionString: "1.3.14"', 'CFBundleShortVersionString: "1.3.15"')
project_text = project_text.replace('CFBundleVersion: "24"', 'CFBundleVersion: "25"')
project_text = project_text.replace('MARKETING_VERSION: "1.3.14"', 'MARKETING_VERSION: "1.3.15"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "24"', 'CURRENT_PROJECT_VERSION: "25"')
project.write_text(project_text)

settings = ROOT / "NextReminder" / "Sources" / "Settings.swift"
settings.write_text(settings.read_text().replace("Version 1.3.14 • iOS 16.0+", "Version 1.3.15 • iOS 16.0+"))
for swift in (ROOT / "NextReminder" / "Sources").glob("*.swift"):
    swift.write_text(swift.read_text().replace("NextReminder-iOS/1.3.14", "NextReminder-iOS/1.3.15"))

print("Next Reminder v1.3.15 scan compression patch applied successfully.")
