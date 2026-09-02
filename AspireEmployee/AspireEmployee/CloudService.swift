import CloudKit
import Foundation

private enum EmployeeCloudSchema {
    static let containerIdentifier = "iCloud.com.nextsolution.aspirevisits"
    static let assignmentRecordType = "AspireVisitAssignment"
    static let completionRecordType = "AspireVisitCompletion"
}

actor EmployeeCloudService {
    static let shared = EmployeeCloudService()

    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: EmployeeCloudSchema.containerIdentifier)) {
        database = container.publicCloudDatabase
    }

    func fetchAssignments() async throws -> [EmployeeVisitAssignment] {
        let records = try await fetchAll(recordType: EmployeeCloudSchema.assignmentRecordType)
        return records.compactMap { record in
            guard let rawID = record["customerID"] as? String,
                  let id = UUID(uuidString: rawID) else { return nil }
            return EmployeeVisitAssignment(
                id: id,
                villaNumber: (record["villaNumber"] as? String) ?? "",
                area: (record["area"] as? String) ?? "",
                plannedVisits: (record["plannedVisits"] as? NSNumber)?.intValue ?? 0,
                active: (record["active"] as? NSNumber)?.boolValue ?? true,
                updatedAt: record["updatedAt"] as? Date
            )
        }
        .filter(\.active)
        .sorted {
            let areaOrder = $0.areaTitle.localizedCaseInsensitiveCompare($1.areaTitle)
            if areaOrder != .orderedSame { return areaOrder == .orderedAscending }
            return $0.villaTitle.localizedStandardCompare($1.villaTitle) == .orderedAscending
        }
    }

    func fetchCompletions() async throws -> [EmployeeVisitCompletion] {
        let records = try await fetchAll(recordType: EmployeeCloudSchema.completionRecordType)
        return records.compactMap { record in
            let rawVisitID = (record["visitID"] as? String) ?? record.recordID.recordName
            guard let visitID = UUID(uuidString: rawVisitID),
                  let rawCustomerID = record["customerID"] as? String,
                  let customerID = UUID(uuidString: rawCustomerID),
                  let completedAt = record["completedAt"] as? Date else { return nil }
            return EmployeeVisitCompletion(
                id: visitID,
                customerID: customerID,
                completedAt: completedAt,
                employeeName: (record["employeeName"] as? String) ?? "",
                source: (record["source"] as? String) ?? "employee"
            )
        }
        .sorted { $0.completedAt > $1.completedAt }
    }

    func markVisitDone(customerID: UUID, employeeName: String, at date: Date = Date()) async throws -> EmployeeVisitCompletion {
        let visitID = UUID()
        let record = CKRecord(
            recordType: EmployeeCloudSchema.completionRecordType,
            recordID: CKRecord.ID(recordName: visitID.uuidString.lowercased())
        )
        let cleanEmployee = employeeName.trimmingCharacters(in: .whitespacesAndNewlines)
        record["visitID"] = visitID.uuidString as CKRecordValue
        record["customerID"] = customerID.uuidString as CKRecordValue
        record["completedAt"] = date as CKRecordValue
        record["employeeName"] = cleanEmployee as CKRecordValue
        record["source"] = "employee" as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        _ = try await database.save(record)
        return EmployeeVisitCompletion(
            id: visitID,
            customerID: customerID,
            completedAt: date,
            employeeName: cleanEmployee,
            source: "employee"
        )
    }

    private func fetchAll(recordType: String) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await fetchPage(recordType: recordType, cursor: cursor)
            allRecords.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        return allRecords
    }

    private func fetchPage(
        recordType: String,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                operation = CKQueryOperation(query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)))
            }
            operation.resultsLimit = CKQueryOperation.maximumResults

            var records: [CKRecord] = []
            let lock = NSLock()
            var firstError: Error?

            operation.recordMatchedBlock = { _, result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let record): records.append(record)
                case .failure(let error): if firstError == nil { firstError = error }
                }
            }

            operation.queryResultBlock = { result in
                lock.lock()
                let collected = records
                let recordError = firstError
                lock.unlock()

                if let recordError {
                    continuation.resume(throwing: recordError)
                    return
                }
                switch result {
                case .success(let nextCursor): continuation.resume(returning: (collected, nextCursor))
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}

@MainActor
final class EmployeeVisitStore: ObservableObject {
    @Published private(set) var assignments: [EmployeeVisitAssignment] = []
    @Published private(set) var completions: [EmployeeVisitCompletion] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var employeeName: String {
        didSet { UserDefaults.standard.set(employeeName, forKey: "AspireEmployee.employeeName") }
    }

    init() {
        employeeName = UserDefaults.standard.string(forKey: "AspireEmployee.employeeName") ?? ""
    }

    func completedCount(for customerID: UUID, month: Date = Date()) -> Int {
        completions.filter {
            $0.customerID == customerID && Calendar.current.isDate($0.completedAt, equalTo: month, toGranularity: .month)
        }.count
    }

    func recentCompletions(for customerID: UUID, limit: Int = 3) -> [EmployeeVisitCompletion] {
        Array(completions.filter { $0.customerID == customerID }.prefix(limit))
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let assignmentsTask = EmployeeCloudService.shared.fetchAssignments()
            async let completionsTask = EmployeeCloudService.shared.fetchCompletions()
            let (newAssignments, newCompletions) = try await (assignmentsTask, completionsTask)
            assignments = newAssignments
            completions = newCompletions
            lastError = nil
        } catch {
            lastError = Self.friendlyMessage(for: error)
        }
    }

    func markDone(_ assignment: EmployeeVisitAssignment) async -> Bool {
        let current = completedCount(for: assignment.id)
        guard current < max(0, assignment.plannedVisits) else { return false }
        do {
            let completion = try await EmployeeCloudService.shared.markVisitDone(
                customerID: assignment.id,
                employeeName: employeeName
            )
            completions.insert(completion, at: 0)
            lastError = nil
            return true
        } catch {
            lastError = Self.friendlyMessage(for: error)
            return false
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return "Sign in to iCloud on this iPhone, then try again."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return "Visit sync is temporarily unavailable. Check the internet connection and try again."
            case .unknownItem:
                return "Visit sync is not initialized yet. Ask the administrator to finish the CloudKit setup."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
