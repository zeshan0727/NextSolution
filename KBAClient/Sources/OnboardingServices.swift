// MARK: - Sources/Onboarding/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var companyName = ""
    @State private var jurisdiction = Jurisdiction.qatar
    @State private var customerType = CustomerType.smallBusiness

    private var isValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        BrandMark(size: 76)
                        Text("Welcome to KBA Client")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Explore services, prepare requests and keep your customer documents organised.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    LocalTestBanner()

                    VStack(spacing: 14) {
                        TextField("Full name", text: $fullName)
                            .textContentType(.name)
                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        TextField("Phone number", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Company name (optional)", text: $companyName)
                            .textContentType(.organizationName)

                        Picker("Primary market", selection: $jurisdiction) {
                            ForEach(Jurisdiction.allCases.filter { $0 != .crossBorder }) { country in
                                Text("\(country.flag) \(country.rawValue)").tag(country)
                            }
                        }

                        Picker("Customer type", selection: $customerType) {
                            ForEach(CustomerType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.08))
                    }

                    Button {
                        store.completeOnboarding(
                            UserProfile(
                                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                                companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
                                jurisdiction: jurisdiction,
                                customerType: customerType
                            )
                        )
                    } label: {
                        Text("Start Testing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)

                    Text("Version \(AppConfiguration.version) • Test data remains on this iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(BrandColor.paleBlue.opacity(0.38))
        }
    }
}

// MARK: - Sources/ServicesUI/ServicesView.swift
import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var store: AppStore
    var embedded = false
    @State private var searchText = ""
    @State private var jurisdiction: Jurisdiction?

    private var filteredServices: [KBAService] {
        let byJurisdiction = ServiceCatalog.services(for: jurisdiction)
        guard !searchText.isEmpty else { return byJurisdiction }
        return byJurisdiction.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Market", selection: $jurisdiction) {
                    Text("All markets").tag(Jurisdiction?.none)
                    ForEach(Jurisdiction.allCases) { item in
                        Text("\(item.flag) \(item.shortName)").tag(Jurisdiction?.some(item))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(filteredServices) { service in
                    NavigationLink {
                        ServiceDetailView(service: service)
                    } label: {
                        ServiceCard(service: service)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Services")
        .searchable(text: $searchText, prompt: "Search KBA services")
        .onAppear {
            if jurisdiction == nil {
                jurisdiction = store.profile?.jurisdiction
            }
        }
    }
}

// MARK: - Sources/ServicesUI/ServiceDetailView.swift
import SwiftUI

struct ServiceDetailView: View {
    let service: KBAService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: service.systemImage)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(BrandColor.blue.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text(service.title)
                        .font(.largeTitle.bold())
                    Text(service.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(service.details)
                    .font(.body)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Included support")
                        .font(.headline)
                    ForEach(service.highlights, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(BrandColor.navy)
                    }
                }
                .padding(17)
                .background(BrandColor.paleBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Available markets")
                        .font(.headline)
                    Text(service.jurisdictions.map { "\($0.flag) \($0.shortName)" }.joined(separator: "  "))
                        .font(.subheadline)
                }

                if AppConfiguration.isLocalTestMode {
                    LocalTestBanner()
                }

                NavigationLink {
                    RequestFormView(service: service)
                } label: {
                    Label("Request this service", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
        }
        .navigationTitle("Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}
