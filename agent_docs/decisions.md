# Decisions

- The application is local-only.
- User-facing copy is French and uses “rayon” rather than “catégorie” for aisle terminology.
- Manual classification remains available when the local model is unavailable.
- The legacy `Application Support/Courses/list.json` location remains compatible.
- Persistence uses atomic saves and blocks writes after a load failure.

Record only durable decisions whose rationale would otherwise need to be rediscovered. Keep temporary implementation notes in `handoff.md`.
