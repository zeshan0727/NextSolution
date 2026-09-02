import CloudKit
import Foundation

// MARK: - Privacy-safe employee visit sync
//
// Important: only the fields defined below are written to CloudKit. Customer
// names, phone numbers, email addresses, billing information, full addresses,
// notes and invoices remain inside the Aspire Maintenance admin app.

enum AspireVisitCloudSchema {
    static let containerIdentifier = "iCloud.com.nextsolution.aspirevisits"
    static let assignmentRecordType = "AspireVisitAssignment"
    static let completionRecordType = "AspireVisitCompletion"
}

struct AspireCloudVisitCompletion: Identifiable, Hashable {
    let id: UUID
    let customerID: UUID
    let completedAt: Date
    let employeeName: String
    let source: String
}

actor AspireVisitCloudService {
    static let shared = AspireVisitCloudService()

    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: AspireVisitCloudSchema.containerIdentifier)) {
        database = container.publicCloudDatabase
    }

    func syncAssignments(customers: [Customer]) async throws {
        let existingRecords: [CKRecord]
        do {
            existingRecords = try await fetchAll(recordType: AspireVisitCloudSchema.assignmentRecordType)
        } catch {
            if Self.isMissingRecordType(error) {
                existingRecords = []
            } else {
                throw error
            }
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.recordID.recordName.lowercased(), $0) })
        let localIDs = Set(customers.map { $0.id.uuidString.lowercased() })

        for customer in customers {
            let recordName = customer.id.uuidString.lowercased()
            let recordID = CKRecord.ID(recordName: recordName)
            let record = existingByID[recordName] ?? CKRecord(recordType: AspireVisitCloudSchema.assignmentRecordType, recordID: recordID)

            record["customerID"] = customer.id.uuidString as CKRecordValue
            record["villaNumber"] = (customer.villaNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
            record["area"] = (customer.area ?? "").trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
            record["plannedVisits"] = NSNumber(value: max(0, customer.plannedVisitsPerMonth))
            record["active"] = NSNumber(value: customer.isActive)
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await database.save(record)
        }

        // If a customer is removed from the admin app, remove its employee-safe
        // assignment too so it does not remain visible to staff.
        for record in existingRecords where !localIDs.contains(record.recordID.recordName.lowercased()) {
            _ = try? await database.deleteRecord(withID: record.recordID)
        }
    }

    func uploadAdminVisits(_ visits: [MaintenanceVisit]) async throws {
        let existingRecords: [CKRecord]
        do {
            existingRecords = try await fetchAll(recordType: AspireVisitCloudSchema.completionRecordType)
        } catch {
            if Self.isMissingRecordType(error) {
                existingRecords = []
            } else {
                throw error
            }
        }

        let existingIDs = Set(existingRecords.map { $0.recordID.recordName.lowercased() })
        for visit in visits {
            let recordName = visit.id.uuidString.lowercased()
            guard !existingIDs.contains(recordName) else { continue }

            let record = CKRecord(
                recordType: AspireVisitCloudSchema.completionRecordType,
                recordID: CKRecord.ID(recordName: recordName)
            )
            record["visitID"] = visit.id.uuidString as CKRecordValue
            record["customerID"] = visit.customerID.uuidString as CKRecordValue
            record["completedAt"] = visit.date as CKRecordValue
            // Do not expose admin-side staff notes. The employee-facing cloud
            // record only needs a generic source label for visit counting.
            record["employeeName"] = "" as CKRecordValue
            record["source"] = "admin" as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            _ = try await database.save(record)
        }
    }

    func fetchCompletions() async throws -> [AspireCloudVisitCompletion] {
        let records: [CKRecord]
        do {
            records = try await fetchAll(recordType: AspireVisitCloudSchema.completionRecordType)
        } catch {
            if Self.isMissingRecordType(error) { return [] }
            throw error
        }

        return records.compactMap { record in
            let rawVisitID = (record["visitID"] as? String) ?? record.recordID.recordName
            guard let visitID = UUID(uuidString: rawVisitID),
                  let rawCustomerID = record["customerID"] as? String,
                  let customerID = UUID(uuidString: rawCustomerID),
                  let completedAt = record["completedAt"] as? Date else {
                return nil
            }
            return AspireCloudVisitCompletion(
                id: visitID,
                customerID: customerID,
                completedAt: completedAt,
                employeeName: (record["employeeName"] as? String) ?? "",
                source: (record["source"] as? String) ?? "employee"
            )
        }
        .sorted { $0.completedAt > $1.completedAt }
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
                operation = CKQueryOperation(
                    query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                )
            }

            operation.resultsLimit = CKQueryOperation.maximumResults
            var records: [CKRecord] = []
            let lock = NSLock()
            var firstRecordError: Error?

            operation.recordMatchedBlock = { _, result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    if firstRecordError == nil { firstRecordError = error }
                }
            }

            operation.queryResultBlock = { result in
                lock.lock()
                let collected = records
                let recordError = firstRecordError
                lock.unlock()

                if let recordError {
                    continuation.resume(throwing: recordError)
                    return
                }

                switch result {
                case .success(let nextCursor):
                    continuation.resume(returning: (collected, nextCursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private static func isMissingRecordType(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem
    }
}

@MainActor
extension AspireStore {
    /// Pushes a privacy-safe assignment snapshot, mirrors admin-entered visits
    /// for employee visit counting, and imports visit completions created by the
    /// Aspire Employee app. This is safe to call repeatedly.
    func syncEmployeeVisitCloud() async {
        do {
            let customerSnapshot = customers
            let visitSnapshot = visits

            try await AspireVisitCloudService.shared.syncAssignments(customers: customerSnapshot)
            try await AspireVisitCloudService.shared.uploadAdminVisits(visitSnapshot)

            let cloudCompletions = try await AspireVisitCloudService.shared.fetchCompletions()
            var knownVisitIDs = Set(visits.map(\.id))

            for completion in cloudCompletions {
                guard !knownVisitIDs.contains(completion.id), customer(id: completion.customerID) != nil else { continue }
                let employee = completion.employeeName.trimmingCharacters(in: .whitespacesAndNewlines)
                addVisit(
                    MaintenanceVisit(
                        id: completion.id,
                        customerID: completion.customerID,
                        date: completion.completedAt,
                        staffName: employee.isEmpty ? "Aspire Employee" : employee,
                        workDone: "Garden maintenance visit",
                        notes: completion.source == "employee" ? "Completed from Aspire Employee app" : ""
                    )
                )
                knownVisitIDs.insert(completion.id)
            }
        } catch {
            // Cloud sync should never block the accounting/admin app. A later
            // foreground refresh retries automatically.
            print("Aspire employee visit sync: \(error.localizedDescription)")
        }
    }
}
