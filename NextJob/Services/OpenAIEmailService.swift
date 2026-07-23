import Foundation

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
        case .completion: return "Completed – \(job.title)"
        case .paymentFollowUp: return "Payment Follow-Up – \(job.title)"
        case .custom: return job.title
        }
    }

    func defaultBody(for job: JobRecord, signature: String) -> String {
        let dueText = job.dueDate.formatted(date: .long, time: .shortened)
        let completionText = (job.completedDate ?? Date()).formatted(date: .long, time: .shortened)
        let requested = job.requestedDocuments.trimmingCharacters(in: .whitespacesAndNewlines)

        let message: String
        switch self {
        case .documentRequest:
            message = """
            Hello,

            I am working on the following job:
            \(job.title)

            Please provide the following documents or information:
            \(requested.isEmpty ? "Please send the documents and information required to complete this job." : requested)

            Target completion date: \(dueText)
            """
        case .progressUpdate:
            message = """
            Hello,

            Here is an update regarding \(job.title).

            Current status: \(job.status.title)
            Target completion date: \(dueText)
            """
        case .completion:
            message = """
            Hello,

            The following job has been completed:
            \(job.title)

            Job type: \(job.jobType)
            Completed: \(completionText)

            The completion documents are attached.
            """
        case .paymentFollowUp:
            message = """
            Hello,

            I am following up regarding payment for the completed job below:
            \(job.title)

            Job price: \(String(format: "%.2f", job.price))
            """
        case .custom:
            message = """
            Hello,

            Regarding \(job.title):
            """
        }

        let cleanedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedSignature.isEmpty ? message : message + "\n\n" + cleanedSignature
    }
}

struct OpenAIEmailDraft: Codable, Equatable {
    var subject: String
    var body: String
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

@MainActor
final class OpenAIConfigurationStore: ObservableObject {
    static let shared = OpenAIConfigurationStore()

    @Published private(set) var model: String

    private let modelKey = "NextJob.OpenAIModel"
    private let apiKeyAccount = "openai-api-key"

    private init() {
        model = UserDefaults.standard.string(forKey: modelKey) ?? "gpt-5-mini"
    }

    var apiKey: String { SecureStore.load(account: apiKeyAccount) }
    var isConfigured: Bool { !apiKey.isEmpty && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func save(apiKey: String, model: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            SecureStore.delete(account: apiKeyAccount)
        } else {
            try SecureStore.save(trimmedKey, account: apiKeyAccount)
        }
        self.model = trimmedModel.isEmpty ? "gpt-5-mini" : trimmedModel
        UserDefaults.standard.set(self.model, forKey: modelKey)
        objectWillChange.send()
    }
}

enum OpenAIEmailError: LocalizedError {
    case notConfigured
    case invalidResponse
    case emptyOutput
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an OpenAI API key in Settings before crafting an email."
        case .invalidResponse:
            return "OpenAI returned an invalid email response."
        case .emptyOutput:
            return "OpenAI did not return an email draft."
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
        }
        var content: [ContentItem]?
    }
    struct APIError: Decodable {
        var message: String
    }
    var output: [OutputItem]?
    var error: APIError?
}

struct OpenAIEmailService {
    func craft(
        job: JobRecord,
        purpose: JobEmailPurpose,
        tone: String,
        additionalInstruction: String,
        configuration: OpenAIConfigurationStore,
        signature: String
    ) async throws -> OpenAIEmailDraft {
        guard configuration.isConfigured else { throw OpenAIEmailError.notConfigured }

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
        let payload: [String: Any] = [
            "model": configuration.model,
            "store": false,
            "input": prompt,
            "max_output_tokens": 900,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "job_email_draft",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIEmailError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data),
               let message = decoded.error?.message {
                throw OpenAIEmailError.server(message)
            }
            throw OpenAIEmailError.server("OpenAI request failed (\(http.statusCode)).")
        }

        let envelope = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        if let message = envelope.error?.message { throw OpenAIEmailError.server(message) }
        let text = envelope.output?
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw OpenAIEmailError.emptyOutput }
        guard let draftData = text.data(using: .utf8),
              let draft = try? JSONDecoder().decode(OpenAIEmailDraft.self, from: draftData) else {
            throw OpenAIEmailError.invalidResponse
        }
        return draft
    }

    private func makePrompt(
        job: JobRecord,
        purpose: JobEmailPurpose,
        tone: String,
        additionalInstruction: String,
        signature: String
    ) -> String {
        let completed = job.completedDate?.formatted(date: .long, time: .shortened) ?? "Not completed"
        return """
        Draft a professional accounting-work email. Use only the facts below. Do not invent documents, dates, completion status, prices, or promises. The email must be clear, natural, concise, and ready to send. Return a subject and plain-text body.

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
        Documents requested: \(job.requestedDocuments.isEmpty ? "None recorded" : job.requestedDocuments)
        Job notes: \(job.notes.isEmpty ? "None recorded" : job.notes)
        Completion notes: \(job.completionNotes.isEmpty ? "None recorded" : job.completionNotes)
        Signature: \(signature)
        """
    }
}
