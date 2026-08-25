import UIKit

struct BrowserGridLayoutMetrics: Equatable {
    let columns: Int
    let rowHeight: CGFloat
    let contentInset: CGFloat
    let spacing: CGFloat
}

enum BrowserGridLayout {
    static let iPadPro129Portrait = CGSize(width: 1_024, height: 1_366)
    static let iPadPro129Landscape = CGSize(width: 1_366, height: 1_024)

    static func metrics(
        for size: CGSize,
        horizontalSizeClass: UIUserInterfaceSizeClass?,
        interfaceIdiom: UIUserInterfaceIdiom,
        browserCount: Int
    ) -> BrowserGridLayoutMetrics {
        let safeCount = max(1, browserCount)
        guard safeCount > 1 else {
            return BrowserGridLayoutMetrics(
                columns: 1,
                rowHeight: interfaceIdiom == .pad ? max(520, size.height - 150) : max(420, size.height - 130),
                contentInset: interfaceIdiom == .pad ? 14 : 8,
                spacing: interfaceIdiom == .pad ? 12 : 8
            )
        }

        if interfaceIdiom == .pad {
            let columns: Int
            switch size.width {
            case 1_180...:
                columns = 4
            case 850...:
                columns = 3
            case 560...:
                columns = 2
            default:
                columns = 1
            }

            let isLandscape = size.width > size.height
            let rowHeight: CGFloat
            if columns == 1 {
                rowHeight = max(520, min(760, size.height - 150))
            } else if columns == 2 {
                rowHeight = isLandscape ? 380 : 440
            } else if columns == 3 {
                rowHeight = isLandscape ? 350 : 400
            } else {
                rowHeight = 330
            }

            return BrowserGridLayoutMetrics(
                columns: min(columns, safeCount),
                rowHeight: rowHeight,
                contentInset: 14,
                spacing: 12
            )
        }

        let isLandscape = size.width > size.height
        let regular = horizontalSizeClass == .regular
        let columns = regular ? (isLandscape ? 4 : 3) : (isLandscape ? 3 : 2)
        return BrowserGridLayoutMetrics(
            columns: min(columns, safeCount),
            rowHeight: regular ? 360 : 300,
            contentInset: 8,
            spacing: 8
        )
    }
}
