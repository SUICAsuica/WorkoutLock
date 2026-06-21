import CloudKit
import Foundation

enum CloudRecordSync {
    private static let container = CKContainer(identifier: "iCloud.com.kosakanao.WorkoutLock")
    private static var database: CKDatabase { container.privateCloudDatabase }

    private static let workoutRecordType = "WorkoutRecord"
    private static let indexRecordType = "RecordIndex"
    private static let indexRecordName = "workout-record-index"
    private static let fetchBatchSize = 200

    static func available() async -> Bool {
        do {
            return try await container.accountStatus() == .available
        } catch {
            return false
        }
    }

    static func push(_ record: WorkoutRecord) async {
        guard await available() else { return }

        do {
            var temporaryAssetURL: URL?
            let cloudRecord = try makeCloudRecord(from: record, temporaryAssetURL: &temporaryAssetURL)
            defer {
                if let temporaryAssetURL {
                    try? FileManager.default.removeItem(at: temporaryAssetURL)
                }
            }

            _ = try await database.save(cloudRecord)
            try await appendToIndex(record.id.uuidString)
        } catch {
            return
        }
    }

    static func fetchAll() async -> [WorkoutRecord] {
        guard await available() else { return [] }

        do {
            let index = try await fetchIndexRecord()
            let ids = index["ids"] as? [String] ?? []
            guard !ids.isEmpty else { return [] }

            let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
            let records = try await fetchRecords(recordIDs)
            return records.compactMap(makeWorkoutRecord(from:))
        } catch {
            return []
        }
    }

    private static func makeCloudRecord(
        from record: WorkoutRecord,
        temporaryAssetURL: inout URL?
    ) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: record.id.uuidString)
        let cloudRecord = CKRecord(recordType: workoutRecordType, recordID: recordID)
        cloudRecord["completedAt"] = record.completedAt as CKRecordValue
        cloudRecord["exercise"] = record.exercise.rawValue as CKRecordValue
        cloudRecord["targetReps"] = NSNumber(value: record.targetReps)
        cloudRecord["actualReps"] = NSNumber(value: record.actualReps)
        cloudRecord["duration"] = NSNumber(value: record.duration)

        if let snapshotData = record.snapshotData {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("workout-snapshot-\(record.id.uuidString).dat")
            try snapshotData.write(to: url, options: [.atomic])
            temporaryAssetURL = url
            cloudRecord["snapshot"] = CKAsset(fileURL: url)
        }

        return cloudRecord
    }

    private static func appendToIndex(_ id: String) async throws {
        let index = try await fetchOrCreateIndexRecord()
        var ids = index["ids"] as? [String] ?? []
        guard !ids.contains(id) else { return }

        ids.append(id)
        index["ids"] = ids as CKRecordValue

        do {
            _ = try await database.save(index)
        } catch let error as CKError where error.code == .serverRecordChanged {
            guard
                let serverRecord = error.serverRecord,
                var serverIDs = serverRecord["ids"] as? [String]
            else {
                throw error
            }

            if !serverIDs.contains(id) {
                serverIDs.append(id)
                serverRecord["ids"] = serverIDs as CKRecordValue
                _ = try await database.save(serverRecord)
            }
        }
    }

    private static func fetchOrCreateIndexRecord() async throws -> CKRecord {
        do {
            return try await fetchIndexRecord()
        } catch let error as CKError where error.code == .unknownItem {
            let recordID = CKRecord.ID(recordName: indexRecordName)
            let record = CKRecord(recordType: indexRecordType, recordID: recordID)
            let ids: [String] = []
            record["ids"] = ids as CKRecordValue
            return record
        }
    }

    private static func fetchIndexRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: indexRecordName)
        return try await database.record(for: recordID)
    }

    private static func fetchRecords(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        records.reserveCapacity(recordIDs.count)

        for batch in recordIDs.chunked(into: fetchBatchSize) {
            let batchRecords = try await fetchRecordBatch(batch)
            records.append(contentsOf: batchRecords)
        }

        return records
    }

    private static func fetchRecordBatch(_ recordIDs: [CKRecord.ID]) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            let lock = NSLock()
            var records: [CKRecord] = []

            operation.perRecordResultBlock = { _, result in
                guard case .success(let record) = result else { return }
                lock.lock()
                records.append(record)
                lock.unlock()
            }

            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private static func makeWorkoutRecord(from record: CKRecord) -> WorkoutRecord? {
        guard
            let id = UUID(uuidString: record.recordID.recordName),
            let completedAt = record["completedAt"] as? Date,
            let exerciseRawValue = record["exercise"] as? String,
            let exercise = ExerciseKind(rawValue: exerciseRawValue),
            let targetReps = (record["targetReps"] as? NSNumber)?.intValue,
            let actualReps = (record["actualReps"] as? NSNumber)?.intValue,
            let duration = (record["duration"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        let snapshotData: Data?
        if
            let asset = record["snapshot"] as? CKAsset,
            let fileURL = asset.fileURL
        {
            snapshotData = try? Data(contentsOf: fileURL)
        } else {
            snapshotData = nil
        }

        return WorkoutRecord(
            id: id,
            completedAt: completedAt,
            exercise: exercise,
            targetReps: targetReps,
            actualReps: actualReps,
            duration: duration,
            snapshotData: snapshotData
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }

        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
