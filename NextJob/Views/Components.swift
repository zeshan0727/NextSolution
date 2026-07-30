import SwiftUI

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.13), Color.indigo.opacity(0.05), Color(uiColor: .systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}

struct BrandHeader: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, .green)
                    .offset(x: 15, y: 15)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text("Next Job")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct StatusBadge: View {
    let status: JobStatus
    var overdue = false

    var body: some View {
        Label(overdue ? "Overdue" : status.title, systemImage: overdue ? "exclamationmark.triangle.fill" : status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(overdue ? Color.red : status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((overdue ? Color.red : status.tint).opacity(0.12), in: Capsule())
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct JobRow: View {
    let job: JobRecord
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(job.jobType) • \(job.clientName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                StatusBadge(status: job.status, overdue: job.isOverdue)
            }
            HStack {
                Label(job.dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Spacer()
                Label("\(currency) \(job.price, specifier: "%.2f")", systemImage: "banknote")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.blue)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .glassCard()
    }
}

struct SectionTitle: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.blue)
            }
            Text(title).font(.headline)
            Spacer()
        }
    }
}
