import Foundation

struct ShoppingListMetadata: Identifiable, Codable, Equatable {
    var id: ShoppingList.ID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date
}

enum ListProvenance: String, Codable, Equatable {
    case local
    case privateCloud
    case shared
}

struct CloudListLocation: Codable, Equatable {
    var zoneName: String
    var ownerName: String?
}

struct LibraryList: Identifiable, Codable, Equatable {
    var metadata: ShoppingListMetadata
    var shoppingList: ShoppingList
    var provenance: ListProvenance
    var cloudLocation: CloudListLocation?

    var id: ShoppingList.ID { metadata.id }
    var isOwner: Bool { provenance != .shared }
}

enum LibraryError: LocalizedError {
    case emptyName
    case missing
    case lastList

    var errorDescription: String? {
        switch self {
        case .emptyName: "Saisissez un nom pour la liste."
        case .missing: "Cette liste n’est plus accessible."
        case .lastList: "Créez une autre liste avant de supprimer celle-ci."
        }
    }
}

struct ListLibrary: Codable, Equatable {
    var currentListID: ShoppingList.ID?
    var lists: [LibraryList]

    var currentList: LibraryList? {
        guard let currentListID else { return fallbackList }
        return lists.first(where: { $0.id == currentListID }) ?? fallbackList
    }

    var fallbackList: LibraryList? {
        lists.max { lhs, rhs in lhs.metadata.lastOpenedAt < rhs.metadata.lastOpenedAt }
    }

    init(currentListID: ShoppingList.ID? = nil, lists: [LibraryList] = []) {
        self.currentListID = currentListID
        self.lists = lists
        repairSelection()
    }

    static func initial(name: String = "Ma liste", now: Date = Date()) -> Self {
        let id = ShoppingList.ID()
        let entry = LibraryList(
            metadata: ShoppingListMetadata(id: id, name: name, createdAt: now, updatedAt: now, lastOpenedAt: now),
            shoppingList: .initial(),
            provenance: .local,
            cloudLocation: nil
        )
        return Self(currentListID: id, lists: [entry])
    }

    mutating func repairSelection() {
        if let currentListID, lists.contains(where: { $0.id == currentListID }) { return }
        currentListID = fallbackList?.id
    }

    @discardableResult mutating func createList(name: String, now: Date = Date()) throws -> ShoppingList.ID {
        let name = ShoppingList.clean(name)
        guard !name.isEmpty else { throw LibraryError.emptyName }
        let id = ShoppingList.ID()
        lists.append(LibraryList(
            metadata: ShoppingListMetadata(id: id, name: name, createdAt: now, updatedAt: now, lastOpenedAt: now),
            shoppingList: .initial(),
            provenance: .local,
            cloudLocation: nil
        ))
        currentListID = id
        return id
    }

    mutating func select(_ id: ShoppingList.ID, now: Date = Date()) throws {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { throw LibraryError.missing }
        currentListID = id
        lists[index].metadata.lastOpenedAt = now
    }

    mutating func rename(_ id: ShoppingList.ID, name: String, now: Date = Date()) throws {
        let name = ShoppingList.clean(name)
        guard !name.isEmpty else { throw LibraryError.emptyName }
        guard let index = lists.firstIndex(where: { $0.id == id }) else { throw LibraryError.missing }
        lists[index].metadata.name = name
        lists[index].metadata.updatedAt = now
    }

    @discardableResult mutating func remove(_ id: ShoppingList.ID) throws -> LibraryList {
        guard lists.count > 1 else { throw LibraryError.lastList }
        guard let index = lists.firstIndex(where: { $0.id == id }) else { throw LibraryError.missing }
        let removed = lists.remove(at: index)
        repairSelection()
        return removed
    }

    mutating func removeInaccessible(_ id: ShoppingList.ID) {
        lists.removeAll { $0.id == id }
        repairSelection()
    }
}
