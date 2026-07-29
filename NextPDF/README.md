# Next PDF

An iOS 16+ SwiftUI PDF editor starter project built with Apple's PDFKit.

## Current test features

- Open PDFs from the Files app
- Preserve the original PDF and export an edited copy
- Add text annotations
- Choose from all fonts installed and supported by iOS
- Change text size
- Delete the selected or latest annotation
- Crop the current page
- Undo and redo editing operations
- iPhone and iPad support
- TrollStore-oriented unsigned build workflow

## Important editing behaviour

PDF files do not store text like Word documents. Text may be split into drawing commands, embedded fonts, paths, or scanned images. This first version safely adds editable PDF annotations instead of destructively rewriting the original content stream.

The next development stage will add:

1. Tap-to-detect existing text and its bounds
2. Match nearby font, size, colour, and alignment
3. Cover and replace selected text without shifting the page layout
4. Drag, resize, rotate, cut, copy, and paste controls
5. Interactive crop handles
6. OCR support for scanned PDFs
7. Embedded/imported `.ttf` and `.otf` fonts
8. Page deletion, duplication, reordering, and extraction

## Generate the Xcode project

Install XcodeGen and run:

```bash
cd NextPDF
xcodegen generate
open NextPDF.xcodeproj
```

The bundle identifier is `com.nextsolution.nextpdf` and the minimum supported version is iOS 16.0.

## Build

Select the **NextPDF** scheme and build in Xcode. The checked-in GitHub Actions workflow also creates an unsigned `.tipa`-compatible archive for testing.

## Safety

Always export to a new file while testing. Some PDFs are encrypted, digitally signed, malformed, or use custom embedded fonts that cannot be modified safely without rebuilding page content.
