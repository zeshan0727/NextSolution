import Foundation

struct EmployeeVisitAssignment: Identifiable, Hashable {
    let id: UUID
    let villaNumber: String
    let area: String
    let plannedVisits: Int
    let active: Bool
    let updatedAt: Date?

    var villaTitle: String {
        let trimmed = villaNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Villa not set" : "Villa \(trimmed)"
    }

    var areaTitle: String {
        let trimmed = area.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Area not set" : trimmed
    }
}

struct EmployeeVisitCompletion: Identifiable, Hashable {
    let id: UUID
    let customerID: UUID
    let completedAt: Date
    let employeeName: String
    let source: String
}

extension DateFormatter {
    static let employeeVisitDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
