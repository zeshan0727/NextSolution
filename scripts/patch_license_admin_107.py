from pathlib import Path

source_path = Path("NextSolutionLicenseAdmin/Sources/NextSolutionLicenseAdminApp.swift")
text = source_path.read_text()

# Use the renamed/current repository directly. Avoid auth-sensitive redirects from NextSolution -> NextJailbreak.
text = text.replace('let repo = "NextSolution"', 'let repo = "NextJailbreak"', 1)
text = text.replace('NextSolutionLicenseAdmin/1.0.0', 'NSAdmin/1.0.7', 1)
text = text.replace('NSAdmin/1.0.6', 'NSAdmin/1.0.7')
text = text.replace('LabeledContent("Version", value: "1.0.6")', 'LabeledContent("Version", value: "1.0.7")')

# Give a useful error for the exact failure the user is seeing.
old_load_error = '''        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
        }
'''
new_load_error = '''        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw LicenseAdminError.api(401, "The saved GitHub token is invalid or expired. Replace it in Settings with a token that can read/write Contents in zeshan0727/NextJailbreak.")
            }
            let text = String(data: data, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
        }
'''
if old_load_error not in text:
    raise SystemExit("loadRegistry HTTP error anchor not found")
text = text.replace(old_load_error, new_load_error, 1)

old_put_error = '''            if (200...299).contains(http.statusCode) { return shouldActivate }
            if http.statusCode == 409 && attempt == 0 { continue }
            let text = String(data: responseData, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
'''
new_put_error = '''            if (200...299).contains(http.statusCode) { return shouldActivate }
            if http.statusCode == 409 && attempt == 0 { continue }
            if http.statusCode == 401 {
                throw LicenseAdminError.api(401, "The saved GitHub token is invalid or expired. Replace it in Settings with a token that can read/write Contents in zeshan0727/NextJailbreak.")
            }
            let text = String(data: responseData, encoding: .utf8) ?? "Unknown response"
            throw LicenseAdminError.api(http.statusCode, String(text.prefix(600)))
'''
if old_put_error not in text:
    raise SystemExit("setActive HTTP error anchor not found")
text = text.replace(old_put_error, new_put_error, 1)

# Include invoice_id in PayPal matching; future checkout also sends it.
old_info = '''struct PayPalTransactionInfo: Decodable {
    let transactionId: String
    let transactionStatus: String?
    let customField: String?
    let transactionSubject: String?
    let transactionNote: String?
}
'''
new_info = '''struct PayPalTransactionInfo: Decodable {
    let transactionId: String
    let transactionStatus: String?
    let customField: String?
    let invoiceId: String?
    let transactionSubject: String?
    let transactionNote: String?
}
'''
if old_info not in text:
    raise SystemExit("PayPalTransactionInfo anchor not found")
text = text.replace(old_info, new_info, 1)

# Do not ask PayPal to pre-filter status. Some Payments Standard rows can be omitted by that filter.
text = text.replace('            URLQueryItem(name: "transaction_status", value: "S"),\n', '', 1)

old_haystack = '''            let haystack = ([custom, info.transactionSubject ?? "", info.transactionNote ?? ""] + itemNames)
                .joined(separator: " | ")
'''
new_haystack = '''            let haystack = ([custom, info.invoiceId ?? "", info.transactionSubject ?? "", info.transactionNote ?? ""] + itemNames)
                .joined(separator: " | ")
'''
if old_haystack not in text:
    raise SystemExit("PayPal haystack anchor not found")
text = text.replace(old_haystack, new_haystack, 1)

old_looks = '''            var looksLikeNextLock = upper.contains("NEXTLOCK") || upper.contains("NS LOCK") || upper.contains("NSLOCK")

            if customParts.count >= 2 {
'''
new_looks = '''            var looksLikeNextLock = upper.contains("NEXTLOCK") || upper.contains("NS LOCK") || upper.contains("NSLOCK")
            if upper.range(of: devicePattern, options: .regularExpression) != nil {
                looksLikeNextLock = true
            }

            if customParts.count >= 2 {
'''
if old_looks not in text:
    raise SystemExit("PayPal detection anchor not found")
text = text.replace(old_looks, new_looks, 1)

# Better visible sync result so an empty Requests screen is diagnosable.
text = text.replace(
    '"PayPal synced. No new paid NextLock requests."',
    '"PayPal synced successfully, but no new paid NextLock request with a valid NS Device ID was found. Payments can take up to about three hours to appear in Transaction Search."',
    1
)

# Update setup copy to make the dependency explicit.
text = text.replace(
    'Text("Paid NextLock requests can sync directly from PayPal after credentials are configured. Deep links remain supported as a fallback: nextsolutionlicense://request.")',
    'Text("Paid NextLock requests sync from PayPal only after LIVE PayPal API credentials are saved above. Deep links remain supported as a fallback: nextsolutionlicense://request.")',
    1
)

source_path.write_text(text)

project_path = Path("NextSolutionLicenseAdmin/project.yml")
project = project_path.read_text()
project = project.replace('MARKETING_VERSION: "1.0.6"', 'MARKETING_VERSION: "1.0.7"')
project = project.replace('CURRENT_PROJECT_VERSION: "106"', 'CURRENT_PROJECT_VERSION: "107"')
project_path.write_text(project)

plist_path = Path("NextSolutionLicenseAdmin/Info.plist")
plist = plist_path.read_text()
plist = plist.replace('<key>CFBundleShortVersionString</key><string>1.0.6</string>', '<key>CFBundleShortVersionString</key><string>1.0.7</string>')
plist = plist.replace('<key>CFBundleVersion</key><string>106</string>', '<key>CFBundleVersion</key><string>107</string>')
plist_path.write_text(plist)

print("Patched NS Admin 1.0.7: current GitHub repo, clearer 401, broader PayPal request matching")
