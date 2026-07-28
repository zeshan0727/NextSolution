import Foundation
import SwiftUI
import UIKit

private enum EmailTextFormat {
    case bold
    case italic
    case bullet
}

struct EmailFormattingEditor: View {
    @Binding var text: String
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                formattingButton("Bold", systemImage: "bold", format: .bold)
                formattingButton("Italic", systemImage: "italic", format: .italic)
                formattingButton("Bullets", systemImage: "list.bullet", format: .bullet)
                Spacer()
            }

            EmailBodyTextView(text: $text, selection: $selection)
                .frame(minHeight: 190)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }

            Text("Select text, or place the cursor in a line, then choose Bold, Italic or Bullets. Formatting remains visible in Gmail and Apple Mail.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formattingButton(_ title: String, systemImage: String, format: EmailTextFormat) -> some View {
        Button {
            apply(format)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func apply(_ format: EmailTextFormat) {
        let source = text as NSString
        let target = targetRange(in: source, format: format)
        let selectedText = target.length > 0 ? source.substring(with: target) : ""

        let replacement: String
        switch format {
        case .bold:
            replacement = selectedText.isEmpty
                ? Self.styled("Bold text", using: Self.boldCharacters)
                : Self.styled(selectedText, using: Self.boldCharacters)
        case .italic:
            replacement = selectedText.isEmpty
                ? Self.styled("Italic text", using: Self.italicCharacters)
                : Self.styled(selectedText, using: Self.italicCharacters)
        case .bullet:
            replacement = Self.bulleted(selectedText)
        }

        text = source.replacingCharacters(in: target, with: replacement)
        selection = NSRange(location: target.location, length: (replacement as NSString).length)
    }

    private func targetRange(in source: NSString, format: EmailTextFormat) -> NSRange {
        let fullRange = NSRange(location: 0, length: source.length)
        let safeLocation = min(max(selection.location, 0), source.length)
        let safeLength = min(max(selection.length, 0), source.length - safeLocation)
        let safeSelection = NSRange(location: safeLocation, length: safeLength)

        if safeSelection.length > 0 {
            return NSIntersectionRange(safeSelection, fullRange)
        }

        let lineRange = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty || format == .bullet {
            return lineRange
        }
        return safeSelection
    }

    private static func styled(_ value: String, using map: [Character: Character]) -> String {
        String(value.map { map[$0] ?? $0 })
    }

    private static func bulleted(_ value: String) -> String {
        guard !value.isEmpty else { return "• " }
        return value
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return line }
                if trimmed.hasPrefix("• ") { return line }
                return "• \(line)"
            }
            .joined(separator: "\n")
    }

    private static let plainCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private static let boldCharacters: [Character: Character] = Dictionary(
        uniqueKeysWithValues: zip(
            plainCharacters,
            Array("𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗")
        )
    )
    private static let italicCharacters: [Character: Character] = Dictionary(
        uniqueKeysWithValues: zip(
            plainCharacters,
            Array("𝐴𝐵𝐶𝐷𝐸𝐹𝐺𝐻𝐼𝐽𝐾𝐿𝑀𝑁𝑂𝑃𝑄𝑅𝑆𝑇𝑈𝑉𝑊𝑋𝑌𝑍𝑎𝑏𝑐𝑑𝑒𝑓𝑔ℎ𝑖𝑗𝑘𝑙𝑚𝑛𝑜𝑝𝑞𝑟𝑠𝑡𝑢𝑣𝑤𝑥𝑦𝑧0123456789")
        )
    )
}

private struct EmailBodyTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .yes
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.text = text
        controller.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: controller.view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        context.coordinator.textView = textView
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.text != text {
            textView.text = text
        }
        let length = (textView.text as NSString).length
        let location = min(max(selection.location, 0), length)
        let rangeLength = min(max(selection.length, 0), length - location)
        let safeRange = NSRange(location: location, length: rangeLength)
        if textView.selectedRange != safeRange {
            textView.selectedRange = safeRange
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EmailBodyTextView
        weak var textView: UITextView?

        init(parent: EmailBodyTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selection = textView.selectedRange
        }
    }
}
