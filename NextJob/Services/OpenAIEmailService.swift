import Foundation
import Combine

enum JobEmailPurpose: String, CaseIterable, Identifiable {
    case documentRequest
    case progressUpdate
    case completion
    case paymentFollowUp
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documentRequest: return "Request Documents"
        case .progressUpdate: return "Progress Update"
        case .completion: return "Job Completion"
        case .paymentFollowUp: return "Payment Follow-Up"
        case .custom: return "Custom Email"
        }
    }

    var recordKind: JobEmailRecord.Kind {
        switch self {
        case .documentRequest: return .documentRequest
        case .progressUpdate: return .progress
        case .completion: return .completion
        case .paymentFollowUp: return .paymentFollowUp
        case .custom: return .custom
        }
    }

    func defaultSubject(for job: JobRecord) -> String {
        switch self {
        case .documentRequest: return "Documents Required – \(job.title)"
        case .progressUpdate: return "Progress Update – \(job.title)"
        case .completion: return "Completion Documents – \(job.title)"
        case .paymentFollowUp: return "Payment Follow-Up – \(job.title)"
        case .custom: return job.title
        }
    }

    func defaultBody(for job: JobRecord, signature: String) -> String {
        let dueText = job.dueDate.formatted(date: .long, time: .shortened)
        let completionText = job.completedDate?.formatted(date: .long, time: .shortened) ?? "Not recorded"
        let requested = job.requestedDocuments.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = job.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let completionNotes = job.completionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let jobNotes = notes.isEmpty ? "No additional job notes were recorded." : notes

        let message: String
        switch self {
        case .documentRequest:
            message = """
            Dear Team,

            I am currently working on the following assignment:

            Job: \(job.title)
            Job type: \(job.jobType)
            Target completion: \(dueText)

            Please provide the following documents or information:
            \(requested.isEmpty ? "Please send the documents and information required to complete this job." : requested)

            Your timely assistance will help me complete the work within the agreed timeframe.

            Kind regards,
            """
        case .progressUpdate:
            message = """
            Dear Team,

            Please find below the current progress update for the following assignment:

            Job: \(job.title)
            Job type: \(job.jobType)
            Current status: \(job.status.title)
            Target completion: \(dueText)

            Job notes:
            \(jobNotes)

            I will continue to keep you informed of any material update or outstanding requirement.

            Kind regards,
            """
        case .completion:
            let finalNotes = completionNotes.isEmpty ? jobNotes : completionNotes
            message = """
            Dear Team,

            I am pleased to confirm that the following assignment has been completed:

            Job: \(job.title)
            Job type: \(job.jobType)
            Completion date and time: \(completionText)
            Actual time recorded: \(job.actualTimeText)

            Job notes:
            \(jobNotes)

            Completion notes:
            \(finalNotes)

            The completion documents and relevant supporting files are included in the attached ZIP package. Please review them and let me know if any clarification or additional work is required.

            Kind regards,
            """
        case .paymentFollowUp:
            let invoice = job.invoiceNumber.map { "Invoice number: \($0)\n" } ?? ""
            let payment = job.effectivePaymentStatus?.title ?? "Payment status not recorded"
            message = """
            Dear Team,

            I am following up regarding payment for the completed assignment below:

            Job: \(job.title)
            Job type: \(job.jobType)
            Completed: \(completionText)
            \(invoice)Amount: \(String(format: "%.2f", job.price))
            Payment status: \(payment)

            I would appreciate your confirmation of the expected payment date. Please let me know if you require the invoice or any supporting document again.

            Kind regards,
            """
        case .custom:
            message = """
            Dear Team,

            I am writing regarding the following assignment:

            Job: \(job.title)
            Job type: \(job.jobType)
            Current status: \(job.status.title)

            Job notes:
            \(jobNotes)

            Kind regards,
            """
        }

        let cleanedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedSignature.isEmpty ? message : message + "\n" + cleanedSignature
    }
}

struct OpenAIEmailDraft: Codable, Equatable {
    var subject: String
    var body: String
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?

    init(
        subject: String,
        body: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.subject = subject
        self.body = body
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

@MainActor
final class EmailDraftStore: ObservableObject {
    @Published var selectedJobID: UUID?
    @Published var recipient = ""
    @Published var purpose: JobEmailPurpose = .completion
    @Published var subject = ""
    @Published var body = ""
    @Published var attachCompletionPackage = true
    @Published var hasAIDraft = false

    func load(
        job: JobRecord,
        purpose: JobEmailPurpose,
        recipient: String,
        signature: String,
        force: Bool = false
    ) {
        let jobChanged = selectedJobID != job.id
        let purposeChanged = self.purpose != purpose
        selectedJobID = job.id
        self.purpose = purpose
        self.recipient = recipient
        attachCompletionPackage = purpose == .completion
        if force || jobChanged || purposeChanged || subject.isEmpty || body.isEmpty {
            subject = purpose.defaultSubject(for: job)
            body = purpose.defaultBody(for: job, signature: signature)
            hasAIDraft = false
        }
    }

    func applyAI(
        draft: OpenAIEmailDraft,
        jobID: UUID,
        purpose: JobEmailPurpose,
        recipient: String
    ) {
        selectedJobID = jobID
        self.purpose = purpose
        self.recipient = recipient
        subject = draft.subject
        body = draft.body
        attachCompletionPackage = purpose == .completion
        hasAIDraft = true
    }
}

struct OpenAIModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let tokenGroup: String

    static let recommended: [OpenAIModelOption] = [
        OpenAIModelOption(id: "gpt-5-mini-2025-08-07", title: "GPT-5 Mini", tokenGroup: "Complimentary mini group – up to 2.5M/day for eligible Tiers 1–2"),
        OpenAIModelOption(id: "gpt-5-nano-2025-08-07", title: "GPT-5 Nano", tokenGroup: "Complimentary mini group – fastest and lowest cost"),
        OpenAIModelOption(id: "gpt-4.1-mini-2025-04-14", title: "GPT-4.1 Mini", tokenGroup: "Complimentary mini group"),
        OpenAIModelOption(id: "gpt-4.1-nano-2025-04-14", title: "GPT-4.1 Nano", tokenGroup: "Complimentary mini group"),
        OpenAIModelOption(id: "gpt-5-2025-08-07", title: "GPT-5", tokenGroup: "Complimentary full group – up to 250K/day for eligible Tiers 1–2"),
        OpenAIModelOption(id: "gpt-4.1-2025-04-14", title: "GPT-4.1", tokenGroup: "Complimentary full group – up to 250K/day for eligible Tiers 1–2")
    ]
}

@MainActor
final class OpenAIConfigurationStore: ObservableObject {
    static let shared = OpenAIConfigurationStore()

    @Published private(set) var model: String

    private let modelKey = "NextJob.OpenAIModel"
    private let apiKeyAccount = "openai-api-key"

    private init() {
        let saved = UserDefaults.standard.string(forKey: modelKey)
        model = saved == "gpt-5-mini" || saved == nil ? "gpt-5-mini-2025-08-07" : saved!
    }

    var apiKey: String { SecureStore.load(account: apiKeyAccount) }
    var isConfigured: Bool {
        !apiKey.isEmpty && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(apiKey: String, model: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            SecureStore.delete(account: apiKeyAccount)
        } else {
            try SecureStore.save(trimmedKey, account: apiKeyAccount)
        }
        self.model = trimmedModel.isEmpty ? "gpt-5-mini-2025-08-07" : trimmedModel
        UserDefaults.standard.set(self.model, forKey: modelKey)
        objectWillChange.send()
    }
}

enum OpenAIEmailError: LocalizedError {
    case notConfigured
    case invalidResponse(String)
    case emptyOutput(String)
    case incomplete(String)
    case refusal(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an OpenAI API key in Settings before crafting an email."
        case .invalidResponse(let detail):
            return "OpenAI returned a response that could not be read. \(detail)"
        case .emptyOutput(let detail):
            return "OpenAI completed the request but did not return an email draft. \(detail)"
        case .incomplete(let detail):
            return "OpenAI could not finish the draft. \(detail)"
        case .refusal(let message):
            return "OpenAI declined the request: \(message)"
        case .server(let message):
            return message
        }
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            var type: String
            var text: String?
            var refusal: String?
        }
        var type: String?
        var content: [ContentItem]?
    }

    struct APIError: Decodable {
        var message: String
    }

    struct IncompleteDetails: Decodable {
        var reason: String?
    }

    struct Usage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var total_tokens: Int?
    }

    var status: String?
    var output: [OutputItem]?
    var error: APIError?
    var incomplete_details: IncompleteDetails?
    var usage: Usage?
}

struct OpenAIEmailService {
    @MainActor
    func craft(
        job: JobRecord,
        purpose: JobEmailPurpose,
        tone: String,
        additionalInstruction: String,
        configuration: OpenAIConfigurationStore,
        signature: String
    ) async throws -> OpenAIEmailDraft {
        guard configuration.isConfigured else { throw OpenAIEmailError.notConfigured }

        let apiKey = configuration.apiKey
        let model = configuration.model
        let prompt = makePrompt(
            job: job,
            purpose: purpose,
            tone: tone,
            additionalInstruction: additionalInstruction,
            signature: signature
        )
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "subject": ["type": "string"],
                "body": ["type": "string"]
            ],
            "required": ["subject", "body"],
            "additionalProperties": false
        ]

        var payload: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": prompt]]
                ]
            ],
            "max_output_tokens": 2200,
            "truncation": "auto",
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "job_email_draft",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]
        if model.hasPrefix("gpt-5") {
            payload["reasoning"] = ["effort": "low"]
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIEmailError.invalidResponse("No HTTP response was received.")
        }

        let envelope = try? JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        guard (200...299).contains(http.statusCode) else {
            let message = envelope?.error?.message
                ?? String(data: data, encoding: .utf8)
                ?? "OpenAI request failed (\(http.statusCode))."
            throw OpenAIEmailError.server(message)
        }
        guard let envelope else {
            throw OpenAIEmailError.invalidResponse("The returned JSON did not match the Responses API format.")
        }
        if let message = envelope.error?.message {
            throw OpenAIEmailError.server(message)
        }

        let contents = envelope.output?.flatMap { $0.content ?? [] } ?? []
        if let refusal = contents.compactMap(\.refusal).first, !refusal.isEmpty {
            throw OpenAIEmailError.refusal(refusal)
        }

        let rawText = contents
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let draft = decodeDraft(from: rawText, usage: envelope.usage) {
            return draft
        }

        let usageText = usageDescription(envelope.usage)
        if envelope.status == "incomplete" {
            let reason = envelope.incomplete_details?.reason ?? "The response was marked incomplete."
            throw OpenAIEmailError.incomplete("Reason: \(reason). \(usageText)")
        }
        guard !rawText.isEmpty else {
            throw OpenAIEmailError.emptyOutput(usageText)
        }
        throw OpenAIEmailError.invalidResponse("The model returned text, but it was not a valid structured email draft. \(usageText)")
    }

    private func decodeDraft(
        from rawText: String,
        usage: OpenAIResponseEnvelope.Usage?
    ) -> OpenAIEmailDraft? {
        guard !rawText.isEmpty else { return nil }
        var candidates = [rawText]
        let withoutFences = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutFences != rawText { candidates.append(withoutFences) }
        if let first = withoutFences.firstIndex(of: "{"),
           let last = withoutFences.lastIndex(of: "}"), first <= last {
            candidates.append(String(withoutFences[first...last]))
        }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  var draft = try? JSONDecoder().decode(OpenAIEmailDraft.self, from: data),
                  !draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            draft.inputTokens = usage?.input_tokens
            draft.outputTokens = usage?.output_tokens
            draft.totalTokens = usage?.total_tokens
            return draft
        }
        return nil
    }

    private func usageDescription(_ usage: OpenAIResponseEnvelope.Usage?) -> String {
        guard let usage else { return "No token-usage details were returned." }
        return "Tokens used: input \(usage.input_tokens ?? 0), output \(usage.output_tokens ?? 0), total \(usage.total_tokens ?? 0)."
    }

    private func makePrompt(
        job: JobRecord,
        purpose: JobEmailPurpose,
        tone: String,
        additionalInstruction: String,
        signature: String
    ) -> String {
        let completed = job.completedDate?.formatted(date: .long, time: .shortened) ?? "Not completed"
        let payment = job.effectivePaymentStatus?.title ?? "Not recorded"
        return """
        Draft a professional accounting-work email. Use only the facts below. Do not invent documents, dates, completion status, prices, payment status, or promises. The email must be natural, concise, ready to send, and appropriate for a professional accounting firm. For a completion email, clearly state the exact recorded completion date and time and include the recorded job notes. Return only the structured subject and plain-text body.

        Email purpose: \(purpose.title)
        Requested tone: \(tone)
        Additional instruction: \(additionalInstruction.isEmpty ? "None" : additionalInstruction)

        Job name: \(job.title)
        Company: \(job.clientName)
        Job type: \(job.jobType)
        Status: \(job.status.title)
        Assigned: \(job.assignedDate.formatted(date: .long, time: .shortened))
        Due: \(job.dueDate.formatted(date: .long, time: .shortened))
        Completed: \(completed)
        Target time: \(job.targetTimeText)
        Actual time: \(job.actualTimeText)
        Job price: \(String(format: "%.2f", job.price))
        Payment status: \(payment)
        Invoice number: \(job.invoiceNumber ?? "Not created")
        Documents requested: \(job.requestedDocuments.isEmpty ? "None recorded" : job.requestedDocuments)
        Job notes: \(job.notes.isEmpty ? "None recorded" : job.notes)
        Completion notes: \(job.completionNotes.isEmpty ? "None recorded" : job.completionNotes)
        Signature: \(signature)
        """
    }
}
