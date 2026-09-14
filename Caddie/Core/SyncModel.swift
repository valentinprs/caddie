import Foundation
import CryptoKit

enum SyncRecordKind: String, Codable, CaseIterable {
    case list
    case aisle
    case product
    case item
}

enum MutationAction: String, Codable {
    case save
    case delete
}

struct RecordMutation: Identifiable, Codable, Equatable {
    var id: UUID
    var listID: ShoppingList.ID
    var recordKind: SyncRecordKind
    var recordID: String
    var action: MutationAction
    var changedFields: Set<String>

    init(id: UUID = UUID(), listID: ShoppingList.ID, recordKind: SyncRecordKind,
         recordID: String, action: MutationAction, changedFields: Set<String> = []) {
        self.id = id
        self.listID = listID
        self.recordKind = recordKind
        self.recordID = recordID
        self.action = action
        self.changedFields = changedFields
    }
}

enum MutationJournal {
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func recordName(for kind: SyncRecordKind, entityID: UUID, in list: ShoppingList) -> String {
        switch kind {
        case .list: return "list-\(entityID.uuidString.lowercased())"
        case .aisle: return "aisle-\(entityID.uuidString.lowercased())"
        case .product:
            guard let product = list.products.first(where: { $0.id == entityID }) else {
                return "product-id-\(entityID.uuidString.lowercased())"
            }
            return "product-\(digest(ShoppingList.key(product.name)))"
        case .item:
            guard let item = list.items.first(where: { $0.id == entityID }),
                  let product = list.product(item.productID) else {
                return "item-id-\(entityID.uuidString.lowercased())"
            }
            return "item-\(digest(ShoppingList.key(product.name)))"
        }
    }

    static func enqueue(_ additions: [RecordMutation], into pending: inout [RecordMutation]) {
        for addition in additions {
            if let index = pending.firstIndex(where: {
                $0.listID == addition.listID && $0.recordKind == addition.recordKind && $0.recordID == addition.recordID
            }) {
                if addition.action == .delete {
                    pending[index] = addition
                } else if pending[index].action != .delete {
                    pending[index].changedFields.formUnion(addition.changedFields)
                }
            } else {
                pending.append(addition)
            }
        }
    }

    static func bootstrap(_ entry: LibraryList) -> [RecordMutation] {
        var result = [RecordMutation(
            listID: entry.id, recordKind: .list, recordID: recordName(for: .list, entityID: entry.id, in: entry.shoppingList),
            action: .save, changedFields: ["id", "name", "createdAt", "updatedAt"]
        )]
        result += entry.shoppingList.aisles.map {
            RecordMutation(listID: entry.id, recordKind: .aisle, recordID: recordName(for: .aisle, entityID: $0.id, in: entry.shoppingList),
                           action: .save, changedFields: ["id", "name", "icon", "iconColor", "orderKey"])
        }
        result += entry.shoppingList.products.map {
            RecordMutation(listID: entry.id, recordKind: .product, recordID: recordName(for: .product, entityID: $0.id, in: entry.shoppingList),
                           action: .save, changedFields: ["id", "name", "aliases", "uses", "preference", "classification"])
        }
        result += entry.shoppingList.items.map {
            RecordMutation(listID: entry.id, recordKind: .item, recordID: recordName(for: .item, entityID: $0.id, in: entry.shoppingList),
                           action: .save, changedFields: ["id", "productID", "note", "aisleID", "purchased", "suggestion", "revision", "createdAt", "orderKey"])
        }
        return result
    }

    static func changes(from old: LibraryList, to new: LibraryList) -> [RecordMutation] {
        var mutations: [RecordMutation] = []
        var metadataFields: Set<String> = []
        if old.metadata.name != new.metadata.name { metadataFields.insert("name") }
        if old.metadata.updatedAt != new.metadata.updatedAt { metadataFields.insert("updatedAt") }
        if !metadataFields.isEmpty {
            mutations.append(RecordMutation(listID: new.id, recordKind: .list, recordID: recordName(for: .list, entityID: new.id, in: new.shoppingList),
                                            action: .save, changedFields: metadataFields))
        }
        diff(old.shoppingList.aisles, new.shoppingList.aisles, kind: .aisle, listID: new.id, oldList: old.shoppingList, newList: new.shoppingList, fields: aisleFields, into: &mutations)
        diff(old.shoppingList.products, new.shoppingList.products, kind: .product, listID: new.id, oldList: old.shoppingList, newList: new.shoppingList, fields: productFields, into: &mutations)
        diff(old.shoppingList.items, new.shoppingList.items, kind: .item, listID: new.id, oldList: old.shoppingList, newList: new.shoppingList, fields: itemFields, into: &mutations)
        if old.shoppingList.aisles.map(\.id) != new.shoppingList.aisles.map(\.id) {
            for aisle in new.shoppingList.aisles {
                mutations.append(RecordMutation(listID: new.id, recordKind: .aisle, recordID: recordName(for: .aisle, entityID: aisle.id, in: new.shoppingList),
                                                action: .save, changedFields: ["orderKey"]))
            }
        }
        return mutations
    }

    private static func diff<Value: Identifiable & Equatable>(
        _ old: [Value], _ new: [Value], kind: SyncRecordKind, listID: ShoppingList.ID,
        oldList: ShoppingList, newList: ShoppingList,
        fields: (Value, Value) -> Set<String>, into result: inout [RecordMutation]
    ) where Value.ID == UUID {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        for id in oldByID.keys where newByID[id] == nil {
            result.append(RecordMutation(listID: listID, recordKind: kind, recordID: recordName(for: kind, entityID: id, in: oldList), action: .delete))
        }
        for (id, value) in newByID {
            guard let prior = oldByID[id] else {
                result.append(RecordMutation(listID: listID, recordKind: kind, recordID: recordName(for: kind, entityID: id, in: newList),
                                             action: .save, changedFields: allFields(for: kind)))
                continue
            }
            let oldRecordName = recordName(for: kind, entityID: id, in: oldList)
            let newRecordName = recordName(for: kind, entityID: id, in: newList)
            if oldRecordName != newRecordName {
                result.append(RecordMutation(listID: listID, recordKind: kind, recordID: oldRecordName, action: .delete))
                result.append(RecordMutation(listID: listID, recordKind: kind, recordID: newRecordName,
                                             action: .save, changedFields: allFields(for: kind)))
                continue
            }
            let changed = fields(prior, value)
            if !changed.isEmpty {
                result.append(RecordMutation(listID: listID, recordKind: kind, recordID: recordName(for: kind, entityID: id, in: newList),
                                             action: .save, changedFields: changed))
            }
        }
    }

    private static func allFields(for kind: SyncRecordKind) -> Set<String> {
        switch kind {
        case .list: ["id", "name", "createdAt", "updatedAt"]
        case .aisle: ["id", "name", "icon", "iconColor", "orderKey"]
        case .product: ["id", "name", "aliases", "uses", "preference", "classification"]
        case .item: ["id", "productID", "note", "aisleID", "purchased", "suggestion", "revision", "createdAt", "orderKey"]
        }
    }

    private static func aisleFields(_ old: Aisle, _ new: Aisle) -> Set<String> {
        if old == new { return [] }
        var fields: Set<String> = []
        if old.name != new.name { fields.insert("name") }
        if old.icon != new.icon { fields.insert("icon") }
        if old.iconColor != new.iconColor { fields.insert("iconColor") }
        if old.orderKey != new.orderKey { fields.insert("orderKey") }
        return fields.isEmpty ? ["name", "icon", "iconColor"] : fields
    }

    private static func productFields(_ old: Product, _ new: Product) -> Set<String> {
        if old == new { return [] }
        var fields: Set<String> = []
        if old.name != new.name { fields.insert("name") }
        if old.aliases != new.aliases { fields.insert("aliases") }
        if old.uses != new.uses { fields.insert("uses") }
        if old.hasPreference != new.hasPreference || old.preferredAisle != new.preferredAisle { fields.insert("preference") }
        if old.hasClassification != new.hasClassification || old.classificationSuggestion != new.classificationSuggestion { fields.insert("classification") }
        return fields.isEmpty ? ["name", "aliases", "uses", "preference", "classification"] : fields
    }

    private static func itemFields(_ old: ListItem, _ new: ListItem) -> Set<String> {
        if old == new { return [] }
        var fields: Set<String> = []
        if old.productID != new.productID { fields.insert("productID") }
        if old.note != new.note { fields.insert("note") }
        if old.aisleID != new.aisleID { fields.insert("aisleID") }
        if old.purchased != new.purchased { fields.insert("purchased") }
        if old.suggestion != new.suggestion { fields.insert("suggestion") }
        if old.revision != new.revision { fields.insert("revision") }
        if old.orderKey != new.orderKey { fields.insert("orderKey") }
        if old.createdAt != new.createdAt { fields.insert("createdAt") }
        return fields.isEmpty ? ["productID", "note", "aisleID", "purchased", "suggestion", "revision", "createdAt", "orderKey"] : fields
    }
}
