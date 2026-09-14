# Decisions

- The current application is local-only, but the accepted product direction adds multiple autonomous lists, private iCloud synchronization, and CloudKit sharing while preserving offline use.
- Each list owns its aisles, product catalog, remembered corrections, and items. These data do not flow between lists.
- A shared list has one owner and any number of read-write participants. Only the owner manages participation; ownership transfer is out of scope.
- Concurrent edits merge independent fields, use last-arriving-write for the same field, prefer deletion over modification, and deduplicate simultaneous additions of the same product.
- User-facing copy is French and uses “rayon” rather than “catégorie” for aisle terminology.
- Manual classification remains available when the local model is unavailable.
- The legacy `Application Support/Courses/list.json` location remains compatible.
- Persistence uses atomic saves and blocks writes after a load failure.

Record only durable decisions whose rationale would otherwise need to be rediscovered. Keep temporary implementation notes in `handoff.md`.
