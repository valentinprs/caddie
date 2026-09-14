import CloudKit
import Foundation

enum CloudMappingError: LocalizedError {
    case missingEntity
    case digestCollision

    var errorDescription: String? {
        switch self {
        case .missingEntity: "Un changement local ne correspond plus à aucune donnée."
        case .digestCollision: "Deux produits distincts utilisent exceptionnellement le même identifiant iCloud."
        }
    }
}

enum CloudRecordMapper {
    static func record(for mutation: RecordMutation, in snapshot: LocalStoreSnapshot) throws -> CKRecord {
        guard let entry = snapshot.library.lists.first(where: { $0.id == mutation.listID }) else { throw CloudMappingError.missingEntity }
        let zoneID = CloudSchema.zoneID(for: entry.id, ownerName: entry.cloudLocation?.ownerName)
        let recordID = CloudSchema.recordID(name: mutation.recordID, zoneID: zoneID)
        let record = decodeSystemFields(snapshot.cloud.systemFields[CloudSchema.cacheKey(recordID)])
            ?? CKRecord(recordType: recordType(for: mutation.recordKind), recordID: recordID)
        let fields = CloudSchema.fields(for: mutation.changedFields)

        switch mutation.recordKind {
        case .list:
            set("id", entry.id.uuidString, on: record, ifIncludedIn: fields)
            set("name", entry.metadata.name, on: record, ifIncludedIn: fields)
            set("createdAt", entry.metadata.createdAt, on: record, ifIncludedIn: fields)
            set("updatedAt", entry.metadata.updatedAt, on: record, ifIncludedIn: fields)
            record["schemaVersion"] = NSNumber(value: CloudSchema.schemaVersion)
        case .aisle:
            guard let (index, aisle) = entry.shoppingList.aisles.enumerated().first(where: {
                MutationJournal.recordName(for: .aisle, entityID: $0.element.id, in: entry.shoppingList) == mutation.recordID
            }) else { throw CloudMappingError.missingEntity }
            set("id", aisle.id.uuidString, on: record, ifIncludedIn: fields)
            set("name", aisle.name, on: record, ifIncludedIn: fields)
            set("icon", aisle.icon.rawValue, on: record, ifIncludedIn: fields)
            set("iconColor", aisle.iconColor.rawValue, on: record, ifIncludedIn: fields)
            if fields.contains("orderKey") { record["orderKey"] = NSNumber(value: Int64(index)) }
        case .product:
            guard let product = entry.shoppingList.products.first(where: {
                MutationJournal.recordName(for: .product, entityID: $0.id, in: entry.shoppingList) == mutation.recordID
            }) else { throw CloudMappingError.missingEntity }
            let identityKey = ShoppingList.key(product.name)
            guard mutation.recordID == "product-\(MutationJournal.digest(identityKey))" else { throw CloudMappingError.digestCollision }
            set("id", product.id.uuidString, on: record, ifIncludedIn: fields)
            set("name", product.name, on: record, ifIncludedIn: fields)
            if fields.contains("aliases") { record["aliases"] = product.aliases as CKRecordValue }
            if fields.contains("uses") { record["uses"] = NSNumber(value: product.uses) }
            record["identityKey"] = identityKey as CKRecordValue
            if fields.contains("hasPreference") { record["hasPreference"] = NSNumber(value: product.hasPreference) }
            setOptionalUUID("preferredAisleID", product.preferredAisle, on: record, ifIncludedIn: fields)
            if fields.contains("hasClassification") { record["hasClassification"] = NSNumber(value: product.hasClassification) }
            setOptional("classificationSuggestion", product.classificationSuggestion, on: record, ifIncludedIn: fields)
        case .item:
            guard let item = entry.shoppingList.items.first(where: {
                MutationJournal.recordName(for: .item, entityID: $0.id, in: entry.shoppingList) == mutation.recordID
            }) else { throw CloudMappingError.missingEntity }
            set("id", item.id.uuidString, on: record, ifIncludedIn: fields)
            set("productID", item.productID.uuidString, on: record, ifIncludedIn: fields)
            set("note", item.note, on: record, ifIncludedIn: fields)
            setOptionalUUID("aisleID", item.aisleID, on: record, ifIncludedIn: fields)
            if fields.contains("purchased") { record["purchased"] = NSNumber(value: item.purchased) }
            setOptional("suggestion", item.suggestion, on: record, ifIncludedIn: fields)
            set("classificationRevision", item.revision.uuidString, on: record, ifIncludedIn: fields)
            set("createdAt", item.createdAt, on: record, ifIncludedIn: fields)
            if fields.contains("orderKey") { record["orderKey"] = NSNumber(value: item.orderKey) }
        }
        return record
    }

    static func apply(_ records: [CKRecord], scope: ListProvenance, to snapshot: inout LocalStoreSnapshot) throws {
        let ordered = records.sorted { recordRank($0.recordType) < recordRank($1.recordType) }
        for record in ordered {
            try apply(record, scope: scope, to: &snapshot)
            snapshot.cloud.systemFields[CloudSchema.cacheKey(record.recordID)] = try encodeSystemFields(record)
        }
        for index in snapshot.library.lists.indices {
            reconcileItemProductIDs(in: &snapshot.library.lists[index], systemFields: snapshot.cloud.systemFields)
            snapshot.library.lists[index].shoppingList.repairReferences()
        }
        snapshot.library.repairSelection()
    }

    static func applyDeletion(_ recordID: CKRecord.ID, recordType: String, to snapshot: inout LocalStoreSnapshot) {
        guard let listIndex = snapshot.library.lists.firstIndex(where: {
            $0.cloudLocation?.zoneName == recordID.zoneID.zoneName || CloudSchema.zoneID(for: $0.id).zoneName == recordID.zoneID.zoneName
        }) else { return }
        let list = snapshot.library.lists[listIndex].shoppingList
        switch recordType {
        case CloudSchema.RecordType.list:
            snapshot.library.removeInaccessible(snapshot.library.lists[listIndex].id)
        case CloudSchema.RecordType.aisle:
            if let aisle = list.aisles.first(where: {
                MutationJournal.recordName(for: .aisle, entityID: $0.id, in: list) == recordID.recordName
            }) { snapshot.library.lists[listIndex].shoppingList.deleteAisle(aisle.id) }
        case CloudSchema.RecordType.product:
            if let product = list.products.first(where: {
                MutationJournal.recordName(for: .product, entityID: $0.id, in: list) == recordID.recordName
            }) {
                snapshot.library.lists[listIndex].shoppingList.products.removeAll { $0.id == product.id }
                snapshot.library.lists[listIndex].shoppingList.items.removeAll { $0.productID == product.id }
            }
        case CloudSchema.RecordType.item:
            snapshot.library.lists[listIndex].shoppingList.items.removeAll {
                MutationJournal.recordName(for: .item, entityID: $0.id, in: list) == recordID.recordName
            }
        default: break
        }
        snapshot.cloud.systemFields.removeValue(forKey: CloudSchema.cacheKey(recordID))
        snapshot.library.repairSelection()
    }

    static func encodeSystemFields(_ record: CKRecord) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }

    static func decodeSystemFields(_ data: Data?) -> CKRecord? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data)
    }

    private static func apply(_ record: CKRecord, scope: ListProvenance, to snapshot: inout LocalStoreSnapshot) throws {
        let idString = record["id"] as? String
        let inferredID = UUID(uuidString: record.recordID.zoneID.zoneName.replacingOccurrences(of: "list-", with: ""))
        guard let listID = record.recordType == CloudSchema.RecordType.list ? idString.flatMap(UUID.init(uuidString:)) : inferredID else { return }
        if snapshot.library.lists.firstIndex(where: { $0.id == listID }) == nil {
            let now = Date()
            snapshot.library.lists.append(LibraryList(
                metadata: ShoppingListMetadata(id: listID, name: "Liste partagée", createdAt: now, updatedAt: now, lastOpenedAt: .distantPast),
                shoppingList: ShoppingList(), provenance: scope,
                cloudLocation: CloudListLocation(zoneName: record.recordID.zoneID.zoneName, ownerName: record.recordID.zoneID.ownerName)
            ))
        }
        guard let listIndex = snapshot.library.lists.firstIndex(where: { $0.id == listID }) else { return }
        snapshot.library.lists[listIndex].provenance = scope
        snapshot.library.lists[listIndex].cloudLocation = CloudListLocation(
            zoneName: record.recordID.zoneID.zoneName, ownerName: record.recordID.zoneID.ownerName
        )
        switch record.recordType {
        case CloudSchema.RecordType.list:
            if let name = record["name"] as? String { snapshot.library.lists[listIndex].metadata.name = name }
            if let createdAt = record["createdAt"] as? Date { snapshot.library.lists[listIndex].metadata.createdAt = createdAt }
            if let updatedAt = record["updatedAt"] as? Date { snapshot.library.lists[listIndex].metadata.updatedAt = updatedAt }
        case CloudSchema.RecordType.aisle:
            guard let id = idString.flatMap(UUID.init(uuidString:)), let name = record["name"] as? String else { return }
            let aisle = Aisle(id: id, name: name,
                              icon: (record["icon"] as? String).flatMap(AisleIcon.init(rawValue:)) ?? .wheat,
                              iconColor: (record["iconColor"] as? String).flatMap(AisleIconColor.init(rawValue:)) ?? .monochrome,
                              orderKey: (record["orderKey"] as? NSNumber)?.int64Value ?? 0)
            upsert(aisle, in: &snapshot.library.lists[listIndex].shoppingList.aisles)
            snapshot.library.lists[listIndex].shoppingList.aisles.sort { $0.orderKey < $1.orderKey }
        case CloudSchema.RecordType.product:
            guard let id = idString.flatMap(UUID.init(uuidString:)), let name = record["name"] as? String else { return }
            let identity = record["identityKey"] as? String ?? ShoppingList.key(name)
            guard record.recordID.recordName == "product-\(MutationJournal.digest(identity))" else { throw CloudMappingError.digestCollision }
            let product = Product(
                id: id, name: name, aliases: record["aliases"] as? [String] ?? [],
                uses: (record["uses"] as? NSNumber)?.intValue ?? 0,
                hasPreference: (record["hasPreference"] as? NSNumber)?.boolValue ?? false,
                preferredAisle: (record["preferredAisleID"] as? String).flatMap(UUID.init(uuidString:)),
                hasClassification: (record["hasClassification"] as? NSNumber)?.boolValue ?? false,
                classificationSuggestion: record["classificationSuggestion"] as? String
            )
            if let duplicate = snapshot.library.lists[listIndex].shoppingList.products.first(where: {
                $0.id != product.id && MutationJournal.recordName(for: .product, entityID: $0.id, in: snapshot.library.lists[listIndex].shoppingList) == record.recordID.recordName
            }) {
                for itemIndex in snapshot.library.lists[listIndex].shoppingList.items.indices where
                    snapshot.library.lists[listIndex].shoppingList.items[itemIndex].productID == duplicate.id {
                    snapshot.library.lists[listIndex].shoppingList.items[itemIndex].productID = product.id
                }
                snapshot.library.lists[listIndex].shoppingList.products.removeAll { $0.id == duplicate.id }
            }
            upsert(product, in: &snapshot.library.lists[listIndex].shoppingList.products)
        case CloudSchema.RecordType.item:
            guard let id = idString.flatMap(UUID.init(uuidString:)),
                  let productID = (record["productID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
            let canonicalProductID = snapshot.library.lists[listIndex].shoppingList.products.first(where: {
                "item-\(MutationJournal.digest(ShoppingList.key($0.name)))" == record.recordID.recordName
            })?.id ?? productID
            let item = ListItem(
                id: id, productID: canonicalProductID, note: record["note"] as? String ?? "",
                aisleID: (record["aisleID"] as? String).flatMap(UUID.init(uuidString:)),
                purchased: (record["purchased"] as? NSNumber)?.boolValue ?? false,
                suggestion: record["suggestion"] as? String,
                revision: UUID(),
                createdAt: record["createdAt"] as? Date ?? .distantPast,
                orderKey: (record["orderKey"] as? NSNumber)?.int64Value ?? 0
            )
            upsert(item, in: &snapshot.library.lists[listIndex].shoppingList.items)
            snapshot.library.lists[listIndex].shoppingList.items.sort { $0.orderKey < $1.orderKey }
        default: break
        }
    }

    private static func recordType(for kind: SyncRecordKind) -> String {
        switch kind {
        case .list: CloudSchema.RecordType.list
        case .aisle: CloudSchema.RecordType.aisle
        case .product: CloudSchema.RecordType.product
        case .item: CloudSchema.RecordType.item
        }
    }

    private static func recordRank(_ type: String) -> Int {
        switch type {
        case CloudSchema.RecordType.list: 0
        case CloudSchema.RecordType.aisle: 1
        case CloudSchema.RecordType.product: 2
        case CloudSchema.RecordType.item: 3
        default: 4
        }
    }

    private static func reconcileItemProductIDs(in entry: inout LibraryList, systemFields: [String: Data]) {
        let zoneName = entry.cloudLocation?.zoneName ?? CloudSchema.zoneID(for: entry.id).zoneName
        let canonicalProducts = entry.shoppingList.products.reduce(into: [String: UUID]()) { result, product in
            result["item-\(MutationJournal.digest(ShoppingList.key(product.name)))", default: product.id] = product.id
        }
        for data in systemFields.values {
            guard let record = decodeSystemFields(data),
                  record.recordType == CloudSchema.RecordType.item,
                  record.recordID.zoneID.zoneName == zoneName,
                  let productID = canonicalProducts[record.recordID.recordName],
                  let itemID = (record["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let itemIndex = entry.shoppingList.items.firstIndex(where: { $0.id == itemID }) else { continue }
            entry.shoppingList.items[itemIndex].productID = productID
        }
    }

    private static func set(_ key: String, _ value: String, on record: CKRecord, ifIncludedIn fields: Set<String>) {
        if fields.contains(key) { record[key] = value as CKRecordValue }
    }

    private static func set(_ key: String, _ value: Date, on record: CKRecord, ifIncludedIn fields: Set<String>) {
        if fields.contains(key) { record[key] = value as CKRecordValue }
    }

    private static func setOptional(_ key: String, _ value: String?, on record: CKRecord, ifIncludedIn fields: Set<String>) {
        if fields.contains(key) { record[key] = value as CKRecordValue? }
    }

    private static func setOptionalUUID(_ key: String, _ value: UUID?, on record: CKRecord, ifIncludedIn fields: Set<String>) {
        if fields.contains(key) { record[key] = value?.uuidString as CKRecordValue? }
    }

    private static func upsert<Value: Identifiable>(_ value: Value, in values: inout [Value]) where Value.ID: Equatable {
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value }
        else { values.append(value) }
    }

}
