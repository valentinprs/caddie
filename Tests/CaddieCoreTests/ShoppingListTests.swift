import XCTest
@testable import CaddieCore

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
    func testDefaultSuggestionsArePreclassifiedInRegistry() throws {
        let list = ShoppingList.initial()
        XCTAssertFalse(list.products.isEmpty)
        XCTAssertTrue(list.products.allSatisfy(\.hasClassification))
        XCTAssertEqual(list.matching("Tomates")?.preferredAisle, list.aisles.first { $0.name == "Fruits et légumes" }?.id)
        XCTAssertEqual(list.matching("Tomates en conserve")?.preferredAisle, list.aisles.first { $0.name == "Épicerie" }?.id)
    }
    func testDefaultAislesUseTheLucideCatalog() {
        XCTAssertEqual(
            ShoppingList.initial().aisles.map(\.icon),
            [.carrot, .beef, .fish, .ham, .eggFried, .croissant, .wheat, .snowflake, .milk, .soapDispenserDroplet]
        )
        XCTAssertEqual(AisleIcon.allCases.count, 10)
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
    func testModelClassificationIsRegisteredAndReusedAfterReaddition() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Croquettes", note: "")
        let item = try XCTUnwrap(list.items.first)
        let aisle = list.aisles[6].id
        list.applyClassification(id, revision: item.revision, aisles: list.aisles, aisle: aisle, suggestion: nil)

        let product = try XCTUnwrap(list.matching("Croquettes"))
        XCTAssertTrue(product.hasClassification)
        XCTAssertFalse(product.hasPreference)
        XCTAssertEqual(product.preferredAisle, aisle)

        list.items.removeAll()
        _ = try list.add(name: "croquettes", note: "")
        XCTAssertEqual(list.items.first?.aisleID, aisle)
        XCTAssertNil(list.items.first?.suggestion)
    }
    func testUnclassifiedModelResultAndSuggestionAreRegistered() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Croquettes", note: "")
        let item = try XCTUnwrap(list.items.first)
        list.applyClassification(id, revision: item.revision, aisles: list.aisles, aisle: nil, suggestion: "Animalerie")

        list.items.removeAll()
        _ = try list.add(name: "Croquettes", note: "")
        XCTAssertTrue(try XCTUnwrap(list.matching("Croquettes")).hasClassification)
        XCTAssertNil(list.items.first?.aisleID)
        XCTAssertEqual(list.items.first?.suggestion, "Animalerie")
    }
    func testManualChoiceReplacesRegisteredModelClassification() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Croquettes", note: "")
        let item = try XCTUnwrap(list.items.first)
        list.applyClassification(id, revision: item.revision, aisles: list.aisles, aisle: list.aisles[6].id, suggestion: nil)
        let manualAisle = list.aisles[9].id
        list.assign(id, aisle: manualAisle)

        list.items.removeAll()
        _ = try list.add(name: "Croquettes", note: "")
        let product = try XCTUnwrap(list.matching("Croquettes"))
        XCTAssertTrue(product.hasPreference)
        XCTAssertFalse(product.hasClassification)
        XCTAssertEqual(list.items.first?.aisleID, manualAisle)
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
        XCTAssertEqual(list.items.last?.aisleID, snapshot[4].id)
    }
    func testRenamingReplacesProductPreservesNoteAndRejectsCollision() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Tomates", note: "2 boîtes")
        list.assign(id, aisle: list.aisles[0].id)
        XCTAssertTrue(try list.edit(id, name: "Tomates en conserve", note: "2 boîtes"))
        XCTAssertEqual(list.items.first?.aisleID, list.aisles[6].id)
        XCTAssertEqual(list.items.first?.note, "2 boîtes")
        XCTAssertTrue(try XCTUnwrap(list.matching("Tomates")).hasPreference)
        _ = try list.add(name: "Bavette", note: "")
        let before = list
        XCTAssertThrowsError(try list.edit(id, name: "bavettes", note: "different"))
        XCTAssertEqual(list, before)
    }
    func testUpdatingNotePreservesProductAndClassification() throws {
        var list = ShoppingList.initial()
        let id = try list.add(name: "Tomates", note: "")
        let productID = try XCTUnwrap(list.items.first?.productID)
        let aisleID = try XCTUnwrap(list.items.first?.aisleID)
        try list.updateNote(id, note: "  500 g  ")
        XCTAssertEqual(list.items.first?.note, "500 g")
        XCTAssertEqual(list.items.first?.productID, productID)
        XCTAssertEqual(list.items.first?.aisleID, aisleID)
        XCTAssertThrowsError(try list.updateNote(UUID(), note: "1 kg"))
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
        try list.editAisle(list.aisles[1].id, name: "Viandes", icon: .beef)
        try repository.save(list)
        XCTAssertEqual(try repository.load(), list)
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
    func testDecodingExistingProductDefaultsClassificationRegistryFields() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id.uuidString)","name":"Bavette","aliases":[],"uses":1,"hasPreference":false}
        """.utf8)
        let product = try JSONDecoder().decode(Product.self, from: data)
        XCTAssertFalse(product.hasClassification)
        XCTAssertNil(product.classificationSuggestion)
    }
    func testLoadingExistingListRegistersDefaultProductsWithoutOverwritingPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalRepository(url: directory.appendingPathComponent("list.json"))
        var list = ShoppingList.initial()
        for index in list.products.indices {
            list.products[index].hasClassification = false
            list.products[index].preferredAisle = nil
        }
        let bavette = try XCTUnwrap(list.matching("Bavette"))
        let item = try list.add(name: bavette.name, note: "")
        let manualAisle = list.aisles[9].id
        list.assign(item, aisle: manualAisle)
        try repository.save(list)

        let migrated = try repository.load()
        XCTAssertEqual(migrated.matching("Bavette")?.preferredAisle, manualAisle)
        XCTAssertTrue(try XCTUnwrap(migrated.matching("Tomates")).hasClassification)
        XCTAssertEqual(migrated.matching("Tomates")?.preferredAisle, migrated.aisles[0].id)
    }
    func testEditingAisleIconPreservesProductsAndPreferences() throws {
        var list = ShoppingList.initial()
        let aisle = list.aisles[1].id
        let item = try list.add(name: "Bavette", note: "2 pièces")
        list.assign(item, aisle: aisle)
        let items = list.items
        let products = list.products
        let order = list.aisles.map(\.id)
        try list.editAisle(aisle, name: "Viandes", icon: .ham)
        XCTAssertEqual(list.aisles[1].icon, .ham)
        XCTAssertEqual(list.aisles[1].name, "Viandes")
        XCTAssertEqual(list.aisles.map(\.id), order)
        XCTAssertEqual(list.items, items)
        XCTAssertEqual(list.products, products)
        let before = list
        XCTAssertThrowsError(try list.editAisle(aisle, name: "Boissons", icon: .fish))
        XCTAssertThrowsError(try list.editAisle(aisle, name: " ", icon: .fish))
        XCTAssertThrowsError(try list.editAisle(UUID(), name: "Viandes", icon: .fish))
        XCTAssertEqual(list, before)
    }
    func testLegacySFSymbolsMigrateToLucideIcons() throws {
        let data = Data("""
        {"id":"\(UUID().uuidString)","name":"Charcuterie","symbol":"fork.knife","iconColor":"yellow"}
        """.utf8)
        let aisle = try JSONDecoder().decode(Aisle.self, from: data)
        XCTAssertEqual(aisle.icon, .ham)
        XCTAssertEqual(aisle.iconColor, .yellow)
    }

    func testLegacyIconColorsMigrateToTheNewPalette() throws {
        let primary = try JSONDecoder().decode(AisleIconColor.self, from: Data("\"primary\"".utf8))
        let mint = try JSONDecoder().decode(AisleIconColor.self, from: Data("\"mint\"".utf8))
        XCTAssertEqual(primary, .monochrome)
        XCTAssertEqual(mint, .emerald)
        XCTAssertEqual(AisleIconColor.allCases.count, 18)
    }
}
