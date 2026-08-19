import SwiftUI
import AppTrackingTransparency
import AdSupport
import UIKit

@MainActor
final class AdTestDeviceHelper: ObservableObject {
    @Published private(set) var advertisingID = ""
    @Published private(set) var statusText = "Tap below to get this iPhone's Advertising ID for LevelPlay test-device setup."
    @Published private(set) var authorizationStatus = ATTrackingManager.trackingAuthorizationStatus

    var hasUsableAdvertisingID: Bool {
        !advertisingID.isEmpty && advertisingID != "00000000-0000-0000-0000-000000000000"
    }

    func requestAndReadAdvertisingID() {
        Task { @MainActor in
            let status: ATTrackingManager.AuthorizationStatus
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                status = await withCheckedContinuation { continuation in
                    ATTrackingManager.requestTrackingAuthorization { result in
                        continuation.resume(returning: result)
                    }
                }
            } else {
                status = ATTrackingManager.trackingAuthorizationStatus
            }

            authorizationStatus = status
            updateAdvertisingID(for: status)
        }
    }

    func copyAdvertisingID() {
        guard hasUsableAdvertisingID else { return }
        UIPasteboard.general.string = advertisingID
        statusText = "Advertising ID copied. Paste it into LevelPlay → Test devices."
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func updateAdvertisingID(for status: ATTrackingManager.AuthorizationStatus) {
        switch status {
        case .authorized:
            advertisingID = ASIdentifierManager.shared().advertisingIdentifier.uuidString.lowercased()
            if hasUsableAdvertisingID {
                statusText = "Ready. Copy this ID into the LevelPlay Advertising ID field."
            } else {
                statusText = "Tracking is allowed, but iOS returned an all-zero Advertising ID. Reopen the app and try again."
            }
        case .denied:
            advertisingID = ""
            statusText = "Tracking is denied. Open Settings and allow tracking for Next Post, then return and try again."
        case .restricted:
            advertisingID = ""
            statusText = "Tracking is restricted on this device, so iOS cannot provide an Advertising ID."
        case .notDetermined:
            advertisingID = ""
            statusText = "Tracking permission has not been decided yet. Tap Get Advertising ID."
        @unknown default:
            advertisingID = ""
            statusText = "Unable to determine tracking permission status."
        }
    }
}

struct AdTestDeviceSetupView: View {
    @StateObject private var helper = AdTestDeviceHelper()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LevelPlay Test Device", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)
                Spacer()
                Text("TEST")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }

            Text(helper.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if helper.hasUsableAdvertisingID {
                Text(helper.advertisingID)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    helper.copyAdvertisingID()
                } label: {
                    Label("Copy Advertising ID", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    helper.requestAndReadAdvertisingID()
                } label: {
                    Label("Get Advertising ID", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
            }

            if helper.authorizationStatus == .denied || helper.authorizationStatus == .restricted {
                Button("Open Next Post Settings") {
                    helper.openAppSettings()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

struct AdTestDeviceButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Test ID", systemImage: "testtube.2")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    AdTestDeviceSetupView()
                        .padding(18)
                }
                .navigationTitle("Ad Test Device")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
