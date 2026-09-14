import XCTest
@testable import CaddieCore

final class ListLibraryTests: XCTestCase {
    func testListsKeepItemsAislesAndCorrectionsIndependent() throws {
        var library = ListLibrary.initial(name: "Maison", now: Date(timeIntervalSince1970: 1))
        let homeID = try XCTUnwrap(library.currentListID)
        let workID = try library.createList(name: "Bureau", now: Date(timeIntervalSince1970: 2))

        let homeIndex = try XCTUnwrap(library.lists.firstIndex(where: { $0.id == homeID }))
        let homeItem = try library.lists[homeIndex].shoppingList.add(name: "Croquettes", note: "2 kg")
        library.lists[homeIndex].shoppingList.assign(homeItem, aisle: nil)

        let workIndex = try XCTUnwrap(library.lists.firstIndex(where: { $0.id == workID }))
        XCTAssertNil(library.lists[workIndex].shoppingList.matching("Croquettes"))
        XCTAssertTrue(library.lists[workIndex].shoppingList.items.isEmpty)
        XCTAssertFalse(try XCTUnwrap(library.lists[workIndex].shoppingList.matching("Bavette")).hasPreference)
    }

    func testSelectionReopensLastAvailableListAndRejectsDeletingOnlyList() throws {
        var library = ListLibrary.initial(name: "Une", now: Date(timeIntervalSince1970: 1))
        let first = try XCTUnwrap(library.currentListID)
        let second = try library.createList(name: "Deux", now: Date(timeIntervalSince1970: 2))
        try library.select(first, now: Date(timeIntervalSince1970: 3))
        _ = try library.remove(first)
        XCTAssertEqual(library.currentListID, second)
        XCTAssertThrowsError(try library.remove(second))
    }

    func testLegacyMigrationIsIdempotentAndLeavesSourceUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appendingPathComponent("list.json")
        var legacy = ShoppingList.initial()
        _ = try legacy.add(name: "Bavette", note: "2 pièces")
        legacy.onboarded = true
        let source = try JSONEncoder().encode(legacy)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try source.write(to: legacyURL)

        let store = LocalStore(directory: root.appendingPathComponent("store-v2"))
        let migrated = try store.load(legacyURL: legacyURL)
        let reloaded = try store.load(legacyURL: legacyURL)

        XCTAssertEqual(migrated, reloaded)
        XCTAssertEqual(migrated.migrationState, .legacyVerified)
        XCTAssertEqual(migrated.library.currentList?.metadata.name, "Ma liste")
        XCTAssertEqual(migrated.library.currentList?.shoppingList.items.first?.note, "2 pièces")
        XCTAssertTrue(migrated.onboarded)
        XCTAssertFalse(migrated.pendingMutations.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacyURL), source)
    }

    func testCorruptV2IsNotReplacedFromLegacy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(directory: root.appendingPathComponent("store-v2"))
        let legacyURL = root.appendingPathComponent("list.json")
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let corrupt = Data("broken-v2".utf8)
        try corrupt.write(to: store.snapshotURL)
        try JSONEncoder().encode(ShoppingList.initial()).write(to: legacyURL)

        XCTAssertThrowsError(try store.load(legacyURL: legacyURL))
        XCTAssertEqual(try Data(contentsOf: store.snapshotURL), corrupt)
    }

    func testSnapshotPersistsBusinessStateAndMutationTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(directory: root.appendingPathComponent("store-v2"))
        let legacyURL = root.appendingPathComponent("list.json")
        var snapshot = try store.load(legacyURL: legacyURL)
        snapshot.pendingMutations.removeAll()
        let index = 0
        let before = snapshot.library.lists[index]
        _ = try snapshot.library.lists[index].shoppingList.add(name: "Croquettes", note: "")
        MutationJournal.enqueue(MutationJournal.changes(from: before, to: snapshot.library.lists[index]), into: &snapshot.pendingMutations)
        try store.save(snapshot)

        let reloaded = try store.load(legacyURL: legacyURL)
        XCTAssertNotNil(reloaded.library.currentList?.shoppingList.matching("Croquettes"))
        XCTAssertTrue(reloaded.pendingMutations.contains { $0.recordKind == .product && $0.action == .save })
        XCTAssertTrue(reloaded.pendingMutations.contains { $0.recordKind == .item && $0.action == .save })
    }

    func testRecordNamesDeduplicateEquivalentConcurrentProducts() throws {
        var first = ShoppingList.initial()
        var second = ShoppingList.initial()
        let firstItem = try first.add(name: "  Croquettes ", note: "")
        let secondItem = try second.add(name: "croquettes", note: "")
        let firstProduct = try XCTUnwrap(first.matching("croquettes"))
        let secondProduct = try XCTUnwrap(second.matching("croquettes"))

        XCTAssertEqual(
            MutationJournal.recordName(for: .product, entityID: firstProduct.id, in: first),
            MutationJournal.recordName(for: .product, entityID: secondProduct.id, in: second)
        )
        XCTAssertEqual(
            MutationJournal.recordName(for: .item, entityID: firstItem, in: first),
            MutationJournal.recordName(for: .item, entityID: secondItem, in: second)
        )
    }

    func testDeletionWinsWhenMutationsCoalesce() {
        let listID = UUID()
        var pending = [RecordMutation(listID: listID, recordKind: .item, recordID: "item-x", action: .save, changedFields: ["note"])]
        MutationJournal.enqueue([
            RecordMutation(listID: listID, recordKind: .item, recordID: "item-x", action: .delete)
        ], into: &pending)
        MutationJournal.enqueue([
            RecordMutation(listID: listID, recordKind: .item, recordID: "item-x", action: .save, changedFields: ["purchased"])
        ], into: &pending)

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].action, .delete)
    }

    func testRenamingProductReplacesDeterministicProductAndItemRecords() throws {
        let id = UUID()
        var before = LibraryList(
            metadata: ShoppingListMetadata(id: id, name: "Test", createdAt: .distantPast, updatedAt: .distantPast, lastOpenedAt: .distantPast),
            shoppingList: .initial(), provenance: .local, cloudLocation: nil
        )
        let itemID = try before.shoppingList.add(name: "Croquettes", note: "")
        var after = before
        _ = try after.shoppingList.edit(itemID, name: "Pâtée pour chat", note: "")

        let changes = MutationJournal.changes(from: before, to: after)
        XCTAssertEqual(changes.filter { $0.recordKind == .product && $0.action == .delete }.count, 0)
        XCTAssertEqual(changes.filter { $0.recordKind == .product && $0.action == .save }.count, 1)
        XCTAssertEqual(changes.filter { $0.recordKind == .item && $0.action == .delete }.count, 1)
        XCTAssertEqual(changes.filter { $0.recordKind == .item && $0.action == .save }.count, 1)
    }

    func testRemoteInvalidationRejectsLateClassification() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Croquettes", note: "")
        let item = try XCTUnwrap(list.items.first)
        list.invalidateClassification(id)
        list.applyClassification(id, revision: item.revision, aisles: list.aisles, aisle: list.aisles[0].id, suggestion: nil)
        XCTAssertNil(list.items.first?.aisleID)
    }
}
