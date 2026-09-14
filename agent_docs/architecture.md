# Architecture

- `Caddie/Core/ShoppingList.swift` remains the per-list domain model: products, aisles, items, remembered corrections, classification state, and deterministic list rules.
- `Caddie/Core/ListLibrary.swift` owns the collection of lists, metadata, selection, last-opened timestamps, and provenance (`local`, `privateCloud`, or `shared`). Each list keeps its own aisles, product catalog, corrections, and items.
- `Caddie/Core/LocalStore.swift` persists a version-2 `LocalStoreSnapshot` at `Application Support/Courses/store-v2/snapshot.json`. It imports the legacy `Application Support/Courses/list.json`, keeps atomic writes, and stores migration state, CloudKit engine state/system fields, account identity, and pending mutations. Account changes can quarantine and restore account-scoped snapshots.
- `Caddie/Core/SyncModel.swift` provides stable record names and a coalescing mutation journal. It computes field-level changes for lists, aisles, products, and items so local edits can be sent independently.
- `Caddie/App/Store.swift` is the `@MainActor` coordinator for persistence, list operations, classification, offline/error status, account changes, and synchronization callbacks. `Caddie/App/ShoppingView.swift` and its list-management views provide the SwiftUI UI.
- `Caddie/App/Cloud/` maps the local model to the CloudKit schema and resolves field-level server conflicts. `CloudSyncCoordinator` owns separate `CKSyncEngine` drivers for the private and shared databases; private custom zones carry owned/local lists, while shared zones are consumed from the shared database.
- `Caddie/App/Sharing/` creates or loads zone-wide `CKShare` records, presents `UICloudSharingController`, and accepts incoming share metadata through the scene delegate. CloudKit configuration is declared in `Caddie/Caddie.entitlements` and `Caddie/Info.plist` (sharing support and remote notifications).
- `Tests/CaddieCoreTests/` covers deterministic core behavior, persistence, and list-library behavior. `Tests/ClassificationChecks.swift` remains device/model-dependent.

Keep deterministic domain rules in Core, application coordination in `Store`, CloudKit mapping/sync in `Cloud`, sharing/invitation plumbing in `Sharing`, and presentation in SwiftUI. Offline use and manual classification remain supported when iCloud or the local model is unavailable.
