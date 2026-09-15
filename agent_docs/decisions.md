# Decisions

- Model multiple autonomous lists. A list owns its aisles, product catalog, remembered corrections, and items; these data do not flow between lists.
- Preserve the legacy `Application Support/Courses/list.json` location for migration, then use the version-2 `store-v2/snapshot.json` cache with atomic saves. Block writes after a load failure, and isolate account changes with account-specific quarantine snapshots.
- Use a mutation journal plus stable CloudKit record identities to coalesce local work and support field-level merges. Concurrent edits merge independent fields; the last arriving write wins for the same field, deletion wins over modification, and stable product/item identities deduplicate simultaneous additions.
- Use CloudKit private custom zones for owned lists and the shared database for shared lists, with one `CKSyncEngine` per scope. Persist engine state, system fields, and pending mutations in the local snapshot so sync can resume offline.
- A shared list has one owner and read-write participants. Only the owner manages participation; ownership transfer is out of scope. Sharing uses a zone-wide `CKShare` and the system sharing controller; invitation acceptance enters through the scene delegate.
- Keep French user-facing copy and use “rayon” for aisle terminology. Manual classification remains available when the local model is unavailable.
- Use the app identifier `com.valentin.caddie` and CloudKit container `iCloud.com.valentin.caddie`. The previous `courses` identifiers are not a migration target: changing CloudKit containers starts a separate cloud data space and invalidates access to old shared lists.
- Show a discreet “Développement” marker above the compact add drawer only in Debug builds. It distinguishes an Xcode development install (CloudKit Development) from TestFlight (CloudKit Production) without shipping in Release.

CloudKit behavior beyond local/offline execution—server conflicts, invitations, background delivery, and schema promotion—requires the manual device/account validation procedure in `docs/icloud.md`.
