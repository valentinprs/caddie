import CloudKit
import Foundation

enum CloudSchema {
    static let containerIdentifier = "iCloud.com.valentin.caddie"
    static let schemaVersion: Int64 = 1

    enum RecordType {
        static let list = "List"
        static let aisle = "Aisle"
        static let product = "Product"
        static let item = "ListItem"
    }

    static func zoneID(for listID: ShoppingList.ID, ownerName: String? = nil) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "list-\(listID.uuidString.lowercased())", ownerName: ownerName ?? CKCurrentUserDefaultName)
    }

    static func recordID(name: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    static func cacheKey(_ id: CKRecord.ID) -> String {
        "\(id.zoneID.ownerName)|\(id.zoneID.zoneName)|\(id.recordName)"
    }

    static func fields(for logicalFields: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for field in logicalFields {
            switch field {
            case "preference": result.formUnion(["hasPreference", "preferredAisleID"])
            case "classification": result.formUnion(["hasClassification", "classificationSuggestion"])
            default: result.insert(field)
            }
        }
        return result
    }
}
