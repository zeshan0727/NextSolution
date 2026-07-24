// MARK: - Sources/Components/BrandComponents.swift
import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BrandColor.navy, BrandColor.blue, BrandColor.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("KBA")
                .font(.system(size: size * 0.29, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: BrandColor.navy.opacity(0.18), radius: 10, y: 5)
        .accessibilityLabel("KBA Client")
    }
}

struct LocalTestBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(BrandColor.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local test build")
                    .font(.subheadline.weight(.semibold))
                Text("Requests and documents stay on this device and are not sent to KBA yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BrandColor.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BrandColor.gold.opacity(0.35), lineWidth: 1)
        }
    }
}

struct ServiceCard: View {
    let service: KBAService

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: service.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(BrandColor.blue.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(service.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(service.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                HStack(spacing: 5) {
                    ForEach(service.jurisdictions.prefix(4)) { item in
                        Text(item.flag)
                            .font(.caption)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

struct StatusBadge: View {
    let status: RequestStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(status == .completed ? Color.green : BrandColor.blue)
            .background((status == .completed ? Color.green : BrandColor.blue).opacity(0.12), in: Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(BrandColor.blue)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
