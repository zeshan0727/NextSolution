// MARK: - Sources/Requests/RequestFormView.swift
import SwiftUI

struct RequestFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let service: KBAService

    @State private var jurisdiction: Jurisdiction
    @State private var companyName = ""
    @State private var details = ""
    @State private var priority = RequestPriority.normal
    @State private var contactMethod = ContactMethod.whatsapp
    @State private var submittedRequest: ClientRequest?

    init(service: KBAService) {
        self.service = service
        _jurisdiction = State(initialValue: service.jurisdictions.first(where: { $0 != .crossBorder }) ?? .crossBorder)
    }

    private var canSubmit: Bool {
        details.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    var body: some View {
        Form {
            if AppConfiguration.isLocalTestMode {
                Section { LocalTestBanner() }
            }

            Section("Service") {
                Label(service.title, systemImage: service.systemImage)
                Picker("Market", selection: $jurisdiction) {
                    ForEach(service.jurisdictions) { item in
                        Text("\(item.flag) \(item.rawValue)").tag(item)
                    }
                }
            }

            Section("Request details") {
                TextField("Company name", text: $companyName)
                ZStack(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Describe what you need, relevant dates, company details and the result you expect.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $details)
                        .frame(minHeight: 130)
                }
                Picker("Priority", selection: $priority) {
                    ForEach(RequestPriority.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("Preferred contact", selection: $contactMethod) {
                    ForEach(ContactMethod.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            }

            Section {
                Button {
                    submittedRequest = store.addRequest(
                        service: service,
                        jurisdiction: jurisdiction,
                        companyName: companyName.isEmpty ? (store.profile?.companyName ?? "") : companyName,
                        details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                        priority: priority,
                        preferredContact: contactMethod
                    )
                } label: {
                    Text(AppConfiguration.isLocalTestMode ? "Save Test Request" : "Submit Request")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit)
            } footer: {
                Text("Enter at least 10 characters so the team has useful context.")
            }
        }
        .navigationTitle("New Request")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            companyName = store.profile?.companyName ?? ""
        }
        .alert("Request saved", isPresented: Binding(
            get: { submittedRequest != nil },
            set: { if !$0 { submittedRequest = nil } }
        )) {
            Button("Done") { dismiss() }
        } message: {
            Text("Reference \(submittedRequest?.reference ?? ""). This is local test data and has not been transmitted.")
        }
    }
}

// MARK: - Sources/Requests/RequestsView.swift
import SwiftUI

struct RequestsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var statusFilter: RequestStatus?

    private var visibleRequests: [ClientRequest] {
        guard let statusFilter else { return store.requests }
        return store.requests.filter { $0.status == statusFilter }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.requests.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "No requests yet",
                        message: "Open Services and save your first test request."
                    )
                } else {
                    List {
                        if AppConfiguration.isLocalTestMode {
                            LocalTestBanner()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        ForEach(visibleRequests) { request in
                            NavigationLink {
                                RequestDetailView(request: request)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(request.serviceName)
                                        .font(.headline)
                                    HStack {
                                        Text(request.reference)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        StatusBadge(status: request.status)
                                    }
                                    Text(request.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Requests")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("All statuses") { statusFilter = nil }
                        ForEach(RequestStatus.allCases) { status in
                            Button(status.rawValue) { statusFilter = status }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Sources/Requests/RequestDetailView.swift
import SwiftUI

struct RequestDetailView: View {
    let request: ClientRequest

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(request.serviceName)
                        .font(.title2.bold())
                    StatusBadge(status: request.status)
                    Text(request.reference)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Details") {
                LabeledContent("Market", value: "\(request.jurisdiction.flag) \(request.jurisdiction.rawValue)")
                LabeledContent("Priority", value: request.priority.rawValue)
                LabeledContent("Contact", value: request.preferredContact.rawValue)
                LabeledContent("Created") {
                    Text(request.createdAt, format: .dateTime.day().month().year().hour().minute())
                }
                if !request.companyName.isEmpty {
                    LabeledContent("Company", value: request.companyName)
                }
                Text(request.details)
            }

            Section("Status timeline") {
                ForEach(request.timeline) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.status.systemImage)
                            .foregroundStyle(BrandColor.blue)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.status.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Text(event.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
    }
}
