import SwiftUI
import UIKit
import PDFKit
import PencilKit

// MARK: - Text editing

struct AddTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fonts: [String]
    let onInsert: (String, PDFTextStyle) -> Void

    @State private var text = ""
    @State private var fontName = UIFont.systemFont(ofSize: 18).fontName
    @State private var fontSize: Double = 18
    @State private var textColor = Color.primary
    @State private var alignment: TextAlignmentChoice = .left

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                }

                TextStyleControls(
                    fonts: fonts,
                    fontName: $fontName,
                    fontSize: $fontSize,
                    textColor: $textColor,
                    alignment: $alignment,
                    showCoverColor: false,
                    coverColor: .constant(.white)
                )
            }
            .navigationTitle("Add Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        onInsert(text, makeStyle())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func makeStyle() -> PDFTextStyle {
        PDFTextStyle(
            fontName: fontName,
            fontSize: CGFloat(fontSize),
            textColor: UIColor(textColor),
            coverColor: .white,
            alignment: alignment.nsAlignment
        )
    }
}

struct ExistingTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TextEditDraft
    let fonts: [String]
    let onApply: (String, PDFTextStyle) -> Void

    @State private var text: String
    @State private var fontName: String
    @State private var fontSize: Double
    @State private var textColor: Color
    @State private var coverColor = Color.white
    @State private var alignment: TextAlignmentChoice

    init(draft: TextEditDraft, fonts: [String], onApply: @escaping (String, PDFTextStyle) -> Void) {
        self.draft = draft
        self.fonts = fonts
        self.onApply = onApply
        _text = State(initialValue: draft.originalText)
        _fontName = State(initialValue: draft.detectedFontName)
        _fontSize = State(initialValue: Double(draft.detectedFontSize))
        _textColor = State(initialValue: Color(uiColor: draft.detectedTextColor))
        _alignment = State(initialValue: TextAlignmentChoice(draft.detectedAlignment))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Font, size and colour were detected from the selected PDF text when available.", systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Replace selected text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                    Button("Clear Text / Remove", role: .destructive) {
                        text = ""
                    }
                }

                TextStyleControls(
                    fonts: fonts,
                    fontName: $fontName,
                    fontSize: $fontSize,
                    textColor: $textColor,
                    alignment: $alignment,
                    showCoverColor: true,
                    coverColor: $coverColor
                )

                Section("Original") {
                    Text(draft.originalText)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Edit Existing Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(text, makeStyle())
                    }
                }
            }
        }
    }

    private func makeStyle() -> PDFTextStyle {
        PDFTextStyle(
            fontName: fontName,
            fontSize: CGFloat(fontSize),
            textColor: UIColor(textColor),
            coverColor: UIColor(coverColor),
            alignment: alignment.nsAlignment
        )
    }
}

private struct TextStyleControls: View {
    let fonts: [String]
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var textColor: Color
    @Binding var alignment: TextAlignmentChoice
    let showCoverColor: Bool
    @Binding var coverColor: Color

    var body: some View {
        Section("Formatting") {
            Picker("Font", selection: $fontName) {
                ForEach(fonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $fontSize, in: 6...96, step: 1)
            }

            ColorPicker("Text Colour", selection: $textColor, supportsOpacity: true)

            if showCoverColor {
                ColorPicker("Original Text Cover", selection: $coverColor, supportsOpacity: true)
                Text("Use white for normal documents. Change this colour when the original text is on a coloured background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Alignment", selection: $alignment) {
                ForEach(TextAlignmentChoice.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

enum TextAlignmentChoice: String, CaseIterable, Identifiable {
    case left
    case centre
    case right

    var id: String { rawValue }

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center: self = .centre
        case .right: self = .right
        default: self = .left
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .centre: return .center
        case .right: return .right
        }
    }

    var title: String {
        switch self {
        case .left: return "Left"
        case .centre: return "Centre"
        case .right: return "Right"
        }
    }

    var systemImage: String {
        switch self {
        case .left: return "text.alignleft"
        case .centre: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

// MARK: - Date replacement

struct DateReplacementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    let onApply: (String, PDFTextStyle) -> Void

    @State private var date: Date
    @State private var format: DateFormatChoice = .dayMonthYearSlash
    @State private var customText = ""

    init(initialDate: Date, onApply: @escaping (String, PDFTextStyle) -> Void) {
        self.initialDate = initialDate
        self.onApply = onApply
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("Format") {
                    Picker("Date Format", selection: $format) {
                        ForEach(DateFormatChoice.allCases) { option in
                            Text(option.example).tag(option)
                        }
                    }

                    if format == .custom {
                        TextField("Enter date exactly", text: $customText)
                    }

                    LabeledContent("Result", value: replacementText)
                }
            }
            .navigationTitle("Change Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") {
                        onApply(replacementText, .standard)
                    }
                    .disabled(replacementText.isEmpty)
                }
            }
        }
    }

    private var replacementText: String {
        if format == .custom {
            return customText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return format.string(from: date)
    }
}

private enum DateFormatChoice: String, CaseIterable, Identifiable {
    case dayMonthYearSlash
    case dayMonthYearDash
    case yearMonthDay
    case writtenShort
    case writtenLong
    case custom

    var id: String { rawValue }

    var example: String {
        switch self {
        case .dayMonthYearSlash: return "29/07/2026"
        case .dayMonthYearDash: return "29-07-2026"
        case .yearMonthDay: return "2026-07-29"
        case .writtenShort: return "29 Jul 2026"
        case .writtenLong: return "29 July 2026"
        case .custom: return "Custom"
        }
    }

    func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        switch self {
        case .dayMonthYearSlash: formatter.dateFormat = "dd/MM/yyyy"
        case .dayMonthYearDash: formatter.dateFormat = "dd-MM-yyyy"
        case .yearMonthDay: formatter.dateFormat = "yyyy-MM-dd"
        case .writtenShort: formatter.dateFormat = "dd MMM yyyy"
        case .writtenLong: formatter.dateFormat = "dd MMMM yyyy"
        case .custom: return ""
        }
        return formatter.string(from: date)
    }
}

// MARK: - Signature and drawing

struct InkDrawingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let mode: InkMode
    let onApply: (PKDrawing, UIColor, CGFloat) -> Void

    @State private var drawing = PKDrawing()
    @State private var inkColor = Color.primary
    @State private var width: Double = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    ColorPicker("Ink", selection: $inkColor, supportsOpacity: false)
                        .labelsHidden()
                    Image(systemName: "pencil.tip")
                    Slider(value: $width, in: 1...14, step: 1)
                    Text("\(Int(width))")
                        .monospacedDigit()
                        .frame(width: 24)
                    Button("Clear", role: .destructive) {
                        drawing = PKDrawing()
                    }
                }
                .padding()

                PencilCanvas(
                    drawing: $drawing,
                    color: UIColor(inkColor),
                    width: CGFloat(width),
                    mode: mode
                )
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()

                Text(mode == .signature
                    ? "Sign in the box. The signature will be placed near the last point you tapped on the PDF and can be dragged afterward."
                    : "Draw in the box. The drawing will be inserted on the current page and can be moved afterward.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onApply(drawing, UIColor(inkColor), CGFloat(width))
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
        }
    }
}

private struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let color: UIColor
    let width: CGFloat
    let mode: InkMode

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.drawing = drawing
        canvas.tool = PKInkingTool(mode == .signature ? .fountainPen : .pen, color: color, width: width)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.tool = PKInkingTool(mode == .signature ? .fountainPen : .pen, color: color, width: width)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}

// MARK: - Page organiser

struct PageOrganizerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PDFEditorModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<model.pageCount, id: \.self) { index in
                            Button {
                                model.goToPage(index)
                            } label: {
                                VStack(spacing: 6) {
                                    if let image = model.pageThumbnail(at: index) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 110, height: 150)
                                            .background(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .shadow(radius: model.currentPageNumber == index + 1 ? 5 : 1)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(model.currentPageNumber == index + 1 ? Color.blue : Color.clear, lineWidth: 3)
                                            }
                                    }
                                    Text("Page \(index + 1)")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }

                Divider()

                ScrollView {
                    VStack(spacing: 12) {
                        actionRow("Rotate Left", "rotate.left") { model.rotateCurrentPage(clockwise: false) }
                        actionRow("Rotate Right", "rotate.right") { model.rotateCurrentPage(clockwise: true) }
                        actionRow("Move Page Earlier", "arrow.left") { model.moveCurrentPage(by: -1) }
                        actionRow("Move Page Later", "arrow.right") { model.moveCurrentPage(by: 1) }
                        actionRow("Duplicate Page", "plus.square.on.square") { model.duplicateCurrentPage() }
                        actionRow("Add Blank Page", "doc.badge.plus") { model.addBlankPage() }
                        actionRow("Crop Page 5%", "crop") { model.cropCurrentPage() }
                        actionRow("Reset Crop", "arrow.counterclockwise") { model.resetCurrentPageCrop() }

                        Button(role: .destructive) {
                            model.deleteCurrentPage()
                        } label: {
                            Label("Delete Current Page", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
            .navigationTitle("Organise Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

struct PDFSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PDFEditorModel
    @State private var query = ""
    @State private var hits: [PDFSearchHit] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search text in PDF", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { runSearch() }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            hits = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .padding()

                if hits.isEmpty {
                    ContentUnavailableSearchView(hasQuery: !query.isEmpty)
                } else {
                    List(hits) { hit in
                        Button {
                            model.goToSearchHit(hit)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.preview)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("Page \(hit.pageNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { runSearch() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func runSearch() {
        hits = model.search(query)
    }
}

private struct ContentUnavailableSearchView: View {
    let hasQuery: Bool

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: hasQuery ? "text.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(hasQuery ? "No matches found" : "Enter text to search")
                .font(.headline)
            Text(hasQuery ? "Scanned image-only pages require OCR before their text can be searched." : "Search works with selectable text inside the PDF.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
    }
}
