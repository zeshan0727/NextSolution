// MARK: - Sources/Consultations/ConsultationsView.swift
import SwiftUI

struct ConsultationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var requestedDate = Date().addingTimeInterval(86_400)
    @State private var contactMethod = ContactMethod.videoCall
    @State private var topic = ""
    @State private var notes = ""
    @State private var remindMe = true
    @State private var showConfirmation = false

    var body: some View {
        Form {
            if AppConfiguration.isLocalTestMode {
                Section { LocalTestBanner() }
            }

            Section("Preferred appointment") {
                DatePicker(
                    "Date and time",
                    selection: $requestedDate,
                    in: Date().addingTimeInterval(3_600)...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Picker("Contact method", selection: $contactMethod) {
                    ForEach(ContactMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                TextField("Consultation topic", text: $topic)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("Remind me one hour before", isOn: $remindMe)
            }

            Section {
                Button {
                    store.addConsultation(
                        date: requestedDate,
                        contactMethod: contactMethod,
                        topic: topic,
                        notes: notes
                    )
                    if remindMe {
                        Task {
                            let allowed = await NotificationManager.shared.requestAuthorization()
                            if allowed {
                                await NotificationManager.shared.scheduleConsultationReminder(for: requestedDate, topic: topic)
                            }
                        }
                    }
                    showConfirmation = true
                } label: {
                    Text(AppConfiguration.isLocalTestMode ? "Save Test Appointment" : "Request Appointment")
                        .frame(maxWidth: .infinity)
                }
                .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !store.consultations.isEmpty {
                Section("Saved appointments") {
                    ForEach(store.consultations) { consultation in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(consultation.topic)
                                .font(.headline)
                            Text(consultation.requestedDate, format: .dateTime.day().month().year().hour().minute())
                                .font(.subheadline)
                            Text(consultation.contactMethod.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Consultation")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Appointment saved", isPresented: $showConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This appointment request is stored locally for testing and has not been sent to KBA.")
        }
    }
}

// MARK: - Sources/Contact/ContactView.swift
import SwiftUI

struct ContactView: View {
    @Environment(\.openURL) private var openURL

    private let offices: [OfficeContact] = [
        OfficeContact(jurisdiction: .unitedKingdom, phone: "+44 7377 970340", whatsappDigits: "447377970340", address: "155 Altmore Avenue, London, E6 2BT, United Kingdom"),
        OfficeContact(jurisdiction: .unitedStates, phone: "+1 302 506 9696", whatsappDigits: "13025069696", address: "8 The Grn #18311, Dover, DE 19901, United States"),
        OfficeContact(jurisdiction: .qatar, phone: "+974 3393 3119", whatsappDigits: "97433933119", address: "B138B Street 829, Zone 91, Doha, Qatar"),
        OfficeContact(jurisdiction: .unitedArabEmirates, phone: "+971 58 608 0000", whatsappDigits: "971586080000", address: "Musaffah 2, Abu Dhabi, United Arab Emirates")
    ]

    var body: some View {
        List {
            Section {
                Button {
                    openURL(URL(string: "mailto:info@kbaccountant.com")!)
                } label: {
                    Label("info@kbaccountant.com", systemImage: "envelope.fill")
                }
                Link(destination: AppConfiguration.websiteURL) {
                    Label("Visit kbaccountant.com", systemImage: "safari.fill")
                }
            } header: {
                Text("General enquiries")
            } footer: {
                Text("Operating hours shown on the website: Monday–Friday, 9:00 AM–5:00 PM.")
            }

            ForEach(offices) { office in
                Section("\(office.jurisdiction.flag) \(office.jurisdiction.rawValue)") {
                    Button {
                        let digits = office.phone.filter { $0.isNumber || $0 == "+" }
                        openURL(URL(string: "tel:\(digits)")!)
                    } label: {
                        Label(office.phone, systemImage: "phone.fill")
                    }
                    Button {
                        openURL(URL(string: "https://wa.me/\(office.whatsappDigits)")!)
                    } label: {
                        Label("Open WhatsApp", systemImage: "message.fill")
                    }
                    Label(office.address, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Contact KBA")
        .navigationBarTitleDisplayMode(.inline)
    }
}
