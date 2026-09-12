import XCTest
@testable import CoursesCore

final class ShoppingListTests: XCTestCase {
    func testDuplicateIncludesPurchasedAndKnownPlural() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "  BAVETTE ", note: "2 pièces")
        list.toggle(id)
        XCTAssertThrowsError(try list.add(name: "bavettes", note: ""))
        XCTAssertEqual(list.items.count, 1)
        list.items.removeAll()
        XCTAssertNotNil(list.matching("Bavette"))
        XCTAssertNoThrow(try list.add(name: "bavettes", note: ""))
    }
    func testManualPreferenceSurvivesReadditionIncludingUnclassified() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Bavette", note: "")
        let aisle = list.aisles[1].id
        list.assign(id, aisle: aisle)
        list.items.removeAll()
        let next = try list.add(name: "bavettes", note: "")
        XCTAssertEqual(list.items.first?.aisleID, aisle)
        list.assign(next, aisle: nil)
        list.items.removeAll()
        _ = try list.add(name: "Bavette", note: "")
        XCTAssertTrue(try XCTUnwrap(list.matching("Bavette")).hasPreference)
        XCTAssertNil(list.items.first?.aisleID)
    }
    func testDeletingAisleClearsPreferencesAndKeepsProducts() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Bavette", note: "2 pièces")
        let aisle = list.aisles[1].id
        list.assign(id, aisle: aisle)
        list.deleteAisle(aisle)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertNil(list.items.first?.aisleID)
        XCTAssertFalse(try XCTUnwrap(list.matching("Bavette")).hasPreference)
        XCTAssertEqual(list.items.first?.note, "2 pièces")
    }
    func testLateClassificationCannotOverwriteManualChoiceOrAisleChange() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Bavette", note: "")
        let item = try XCTUnwrap(list.items.first)
        let snapshot = list.aisles
        list.assign(id, aisle: nil)
        list.applyClassification(id, revision: item.revision, aisles: snapshot, aisle: snapshot[1].id, suggestion: nil)
        XCTAssertNil(list.items.first?.aisleID)
        let other = try list.add(name: "Comté", note: "")
        let revision = try XCTUnwrap(list.items.last).revision
        try list.renameAisle(snapshot[4].id, name: "Crémerie")
        list.applyClassification(other, revision: revision, aisles: snapshot, aisle: snapshot[4].id, suggestion: nil)
        XCTAssertNil(list.items.last?.aisleID)
    }
    func testRenamingReplacesProductPreservesNoteAndRejectsCollision() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Tomates", note: "2 boîtes")
        list.assign(id, aisle: list.aisles[0].id)
        XCTAssertTrue(try list.edit(id, name: "Tomates en conserve", note: "2 boîtes"))
        XCTAssertNil(list.items.first?.aisleID)
        XCTAssertEqual(list.items.first?.note, "2 boîtes")
        XCTAssertTrue(try XCTUnwrap(list.matching("Tomates")).hasPreference)
        _ = try list.add(name: "Bavette", note: "")
        let before = list
        XCTAssertThrowsError(try list.edit(id, name: "bavettes", note: "different"))
        XCTAssertEqual(list, before)
    }
    func testSuggestionDoesNotCreateAisleAndManualChoiceDismissesIt() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Croquettes", note: "")
        let item = try XCTUnwrap(list.items.first)
        list.applyClassification(id, revision: item.revision, aisles: list.aisles, aisle: nil, suggestion: "Animalerie")
        XCTAssertEqual(list.aisles.count, 10)
        XCTAssertEqual(list.items.first?.suggestion, "Animalerie")
        list.assign(id, aisle: nil)
        XCTAssertNil(list.items.first?.suggestion)
    }
    func testAisleRenamePreservesIdentityAndRejectsDuplicates() throws {
        var list = ShoppingList.initial()
        let aisle = list.aisles[1].id
        let id = try list.add(name: "Bavette", note: "")
        list.assign(id, aisle: aisle)
        try list.renameAisle(aisle, name: "Viandes")
        XCTAssertEqual(list.items.first?.aisleID, aisle)
        XCTAssertEqual(list.matching("Bavette")?.preferredAisle, aisle)
        XCTAssertThrowsError(try list.addAisle(" viandes "))
        XCTAssertThrowsError(try list.addAisle("À classer"))
    }
    func testPersistenceRoundTripAndCorruptionIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(url: directory.appendingPathComponent("list.json"))
        var list = try repository.load()
        let id = try list.add(name: "Bavette", note: "2 pièces")
        list.assign(id, aisle: list.aisles[1].id)
        list.onboarded = true
        try repository.save(list)
        XCTAssertEqual(try repository.load(), list)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
}
