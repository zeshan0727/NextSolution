import SwiftUI
import UniformTypeIdentifiers

struct IPAFileImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void
    let onError: (Error) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                onPick(url)
            case let .failure(error):
                onError(error)
            }
        }
    }
}

extension View {
    func ipaFileImporter(
        isPresented: Binding<Bool>,
        onPick: @escaping (URL) -> Void,
        onError: @escaping (Error) -> Void
    ) -> some View {
        modifier(IPAFileImporterModifier(isPresented: isPresented, onPick: onPick, onError: onError))
    }
}
