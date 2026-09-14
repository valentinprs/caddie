import CloudKit

enum ConflictResolver {
    static func merge(client: CKRecord, server: CKRecord, changedFields: Set<String>) -> CKRecord {
        let fields = CloudSchema.fields(for: changedFields)
        for field in fields {
            server[field] = client[field]
        }
        return server
    }

    static func serverRecord(from error: CKError) -> CKRecord? {
        error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
    }
}
