from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''    static func loadSnapshot() -> SMSImportConsoleSnapshot {
        guard let data = try? Data(contentsOf: consoleURL),
              let value = try? decoder.decode(SMSImportConsoleSnapshot.self, from: data) else {
            return SMSImportConsoleSnapshot()
        }
        return value
    }

    static var directoryURL: URL {
''',
    '''    static func loadSnapshot() -> SMSImportConsoleSnapshot {
        guard let data = try? Data(contentsOf: consoleURL),
              let value = try? decoder.decode(SMSImportConsoleSnapshot.self, from: data) else {
            return SMSImportConsoleSnapshot()
        }
        return value
    }

    static func loadInstallerDiagnostic() -> String {
        (try? String(contentsOf: installerDiagnosticURL, encoding: .utf8)) ?? ""
    }

    static var directoryURL: URL {
''',
)
replace_once(
    service,
    '''    static var consoleURL: URL {
        directoryURL.appendingPathComponent("sms-import-console.json")
    }
''',
    '''    static var consoleURL: URL {
        directoryURL.appendingPathComponent("sms-import-console.json")
    }

    static var installerDiagnosticURL: URL {
        directoryURL.appendingPathComponent("sms-import-install.log")
    }
''',
)

view = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    view,
    '''    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?
''',
    '''    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var installerDiagnostic = ""
    @State private var notice: String?
''',
)
replace_once(
    view,
    '''            Section("Live Status") {
''',
    '''            if !installerDiagnostic.isEmpty {
                Section("Installer Diagnostic") {
                    Text(installerDiagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Live Status") {
''',
)
replace_once(
    view,
    '''    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
    }
''',
    '''    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
    }
''',
)

print("Added installer launch diagnostics to the temporary SMS console.")
