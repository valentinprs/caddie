# Architecture

- `Caddie/Core/ShoppingList.swift` owns product identity, list rules, remembered corrections, and JSON persistence through the `CaddieCore` Swift package.
- `Caddie/App/Store.swift` coordinates application state on the main actor.
- `Caddie/App/Intelligence.swift` integrates local classification through Apple Foundation Models.
- `Caddie/App/ShoppingView.swift` implements the SwiftUI interface.
- `Tests/CaddieCoreTests/` verifies deterministic business rules and persistence.
- `Tests/ClassificationChecks.swift` contains checks that require the real local model.

Preserve the boundary between deterministic core behavior, application coordination, model-backed classification, and presentation. Consult `docs/design.md` for product and classification behavior.
