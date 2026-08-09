from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read(p): return (ROOT / p).read_text(encoding='utf-8')
def write(p, s): (ROOT / p).write_text(s, encoding='utf-8')
def replace_once(p, old, new):
    s = read(p)
    if s.count(old) != 1:
        raise RuntimeError(f'{p}: expected one match, got {s.count(old)} for {old[:100]!r}')
    write(p, s.replace(old, new, 1))

replace_once('project.yml', 'MARKETING_VERSION: "1.3.62"', 'MARKETING_VERSION: "1.3.63"')
replace_once('project.yml', 'CURRENT_PROJECT_VERSION: "70"', 'CURRENT_PROJECT_VERSION: "71"')

p = 'DailyLedger/Views/SMSLatest15ReviewView.swift'
s = read(p)

old_decode = '''                guard let start = raw.firstIndex(of: "{"),
                      let end = raw.lastIndex(of: "}"), start <= end,
                      let data = String(raw[start...end]).data(using: .utf8),
                      var result = try? JSONDecoder().decode(SMSLatestReviewAIResult.self, from: data) else {
                    throw SMSLatestReviewError.invalidResponse
                }
                let allowed = ["income", "expense", "transfer", "not_transaction", "unknown"]
                result.transactionType = result.transactionType.lowercased()
                guard allowed.contains(result.transactionType) else { throw SMSLatestReviewError.invalidResponse }
                result.confidence = min(max(result.confidence, 0), 1)
                result.model = model
'''
new_decode = '''                guard let start = raw.firstIndex(of: "{"),
                      let end = raw.lastIndex(of: "}"), start <= end,
                      let data = String(raw[start...end]).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let json = object as? [String: Any] else {
                    throw SMSLatestReviewError.invalidResponse
                }
                let type = (json["transactionType"] as? String)?.lowercased() ?? ""
                let allowed = ["income", "expense", "transfer", "not_transaction", "unknown"]
                guard allowed.contains(type) else { throw SMSLatestReviewError.invalidResponse }
                func textValue(_ key: String) -> String? {
                    if let value = json[key] as? String, !value.isEmpty { return value }
                    if let value = json[key] as? NSNumber { return value.stringValue }
                    return nil
                }
                let confidence: Double = {
                    if let value = json["confidence"] as? NSNumber { return value.doubleValue }
                    if let value = json["confidence"] as? String { return Double(value) ?? 0 }
                    return 0
                }()
                var result = SMSLatestReviewAIResult(
                    transactionType: type,
                    amount: textValue("amount"),
                    currency: textValue("currency"),
                    accountAlias: textValue("accountAlias"),
                    vendor: textValue("vendor"),
                    category: textValue("category"),
                    confidence: min(max(confidence, 0), 1),
                    reason: textValue("reason"),
                    model: model
                )
'''
if s.count(old_decode) != 1:
    raise RuntimeError('AI decode block not found')
s = s.replace(old_decode, new_decode, 1)

old_buttons = '''                        HStack {
                            Button {
                                Task { await analyzeOne(item) }
                            } label: {
                                Label("Ask AI", systemImage: "sparkles")
                            }
                            .disabled(aiRunning || !OpenAIService.shared.hasAPIKey)

                            if let result = results[item.id], canCreateDraft(result) {
                                Button {
                                    createDraft(item: item, result: result)
                                } label: {
                                    Label("Send to Drafts", systemImage: "tray.and.arrow.down.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button(role: .destructive) {
                                SMSLatest15ReviewService.setDisposition("rejected", for: item.id)
                                results.removeValue(forKey: item.id)
                                reload()
                            } label: {
                                Label("Reject", systemImage: "xmark.circle")
                            }
                        }
                        .font(.caption)
'''
new_buttons = '''                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button {
                                    SMSLatest15ReviewService.setDisposition(nil, for: item.id)
                                    Task { await analyzeOne(item) }
                                } label: {
                                    Label("Ask AI", systemImage: "sparkles")
                                }
                                .disabled(aiRunning || !OpenAIService.shared.hasAPIKey)

                                Menu {
                                    Button("Income") { createManualDraft(item: item, type: "income") }
                                    Button("Expense") { createManualDraft(item: item, type: "expense") }
                                    Button("Transfer") { createManualDraft(item: item, type: "transfer") }
                                    Button("Refund") { createManualDraft(item: item, type: "refund") }
                                } label: {
                                    Label("Book As", systemImage: "square.and.pencil")
                                }
                                .buttonStyle(.borderedProminent)

                                if let result = results[item.id], canCreateDraft(result) {
                                    Button {
                                        createDraft(item: item, result: result)
                                    } label: {
                                        Label("Use AI", systemImage: "tray.and.arrow.down.fill")
                                    }
                                }
                            }

                            HStack {
                                if SMSLatest15ReviewService.disposition(for: item.id) != nil {
                                    Button {
                                        SMSLatest15ReviewService.setDisposition(nil, for: item.id)
                                        results.removeValue(forKey: item.id)
                                        reload()
                                    } label: {
                                        Label("Restore Pending", systemImage: "arrow.uturn.backward.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    SMSLatest15ReviewService.setDisposition("rejected", for: item.id)
                                    results.removeValue(forKey: item.id)
                                    reload()
                                } label: {
                                    Label("Reject", systemImage: "xmark.circle")
                                }
                            }
                        }
                        .font(.caption)
'''
if s.count(old_buttons) != 1:
    raise RuntimeError('Review action block not found')
s = s.replace(old_buttons, new_buttons, 1)

# AI failure must never retain/reapply a rejected state.
s = s.replace('''        } catch {
            connectionStatus = "Error"
            aiLog.append("Row \\(item.rowID) ERROR: \\(error.localizedDescription)")
            notice = "AI error: \\(error.localizedDescription)"
        }
    }
''', '''        } catch {
            connectionStatus = "Error"
            SMSLatest15ReviewService.setDisposition(nil, for: item.id)
            aiLog.append("Row \\(item.rowID) ERROR: \\(error.localizedDescription) · kept Pending")
            notice = "AI error: \\(error.localizedDescription) The SMS remains Pending; use Book As to enter it manually."
            reload()
        }
    }
''', 1)

insert_anchor = '''    private func canCreateDraft(_ result: SMSLatestReviewAIResult) -> Bool {
'''
manual_helpers = r'''    private func extractedAmountCurrency(from text: String) -> (String, String)? {
        let patterns = [
            #"(?i)\b(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
            #"(?i)\b([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\b"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let currencyRange = match.range(at: index == 0 ? 1 : 2)
            let amountRange = match.range(at: index == 0 ? 2 : 1)
            guard let cr = Range(currencyRange, in: text), let ar = Range(amountRange, in: text) else { continue }
            var currency = String(text[cr]).uppercased()
            if currency == "QR" { currency = "QAR" }
            let amount = String(text[ar]).replacingOccurrences(of: ",", with: "")
            if Decimal(string: amount) != nil { return (amount, currency) }
        }
        return nil
    }

    private func manualVendor(from item: SMSLatestReviewMessage) -> String? {
        let text = item.details
        let patterns = [
            #"(?i)\bat\s+(.+?)(?=\s+at\s+\d{1,2}:\d{2}|\s+for\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)|\s+Available Limit|$)"#,
            #"(?i)\bfor\s+(ATM Cash Deposit)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func createManualDraft(item: SMSLatestReviewMessage, type: String) {
        guard let (amount, currency) = extractedAmountCurrency(from: item.details) else {
            notice = "Could not read an amount/currency from this SMS. Keep it Pending and enter it manually from Transactions."
            SMSLatest15ReviewService.setDisposition(nil, for: item.id)
            return
        }
        let isRefund = type == "refund"
        let result = SMSLatestReviewAIResult(
            transactionType: isRefund ? "income" : type,
            amount: amount,
            currency: currency,
            accountAlias: nil,
            vendor: manualVendor(from: item),
            category: isRefund ? "Refund" : nil,
            confidence: 1.0,
            reason: "User selected transaction nature manually.",
            model: "Manual Review"
        )
        createDraft(item: item, result: result)
    }

'''
if s.count(insert_anchor) != 1:
    raise RuntimeError('canCreateDraft anchor missing')
s = s.replace(insert_anchor, manual_helpers + insert_anchor, 1)

# Better local pre-suggestion for obvious formats without API dependency.
local_anchor = '''    private func historyContext(for item: SMSLatestReviewMessage) -> String {
'''
# leave history helper intact; only UI/manual fallback is required.

write(p, s)

settings = 'DailyLedger/Views/SettingsView.swift'
st = read(settings)
st = re.sub(r'LabeledContent\("Version", value: "[^"]+"\)', 'LabeledContent("Version", value: "1.3.63")', st, count=1)
write(settings, st)
print('Prepared Next Ledger 1.3.63: tolerant OpenAI SMS JSON parser, AI errors stay Pending, and manual Book As Income/Expense/Transfer/Refund fallback.')
