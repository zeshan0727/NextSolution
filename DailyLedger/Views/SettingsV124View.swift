import SwiftUI

struct SettingsV124View: View {
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = LedgerVisualTheme.glass.rawValue

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("App Theme", systemImage: "paintbrush.fill")
                        .font(.headline)
                    Spacer()
                    Text("v1.3.24")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Picker("App Theme", selection: $visualTheme) {
                    ForEach(LedgerVisualTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedTheme.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(AppTheme.page)

            Divider()
            SettingsView()
        }
    }

    private var selectedTheme: LedgerVisualTheme {
        LedgerVisualTheme(rawValue: visualTheme) ?? .glass
    }
}
