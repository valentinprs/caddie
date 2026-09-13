# Repository Guidelines

## Project Structure & Module Organization

Caddie is a local-only iPhone shopping-list app built with SwiftUI and Apple Foundation Models.

- `Caddie/Core/ShoppingList.swift`: product identity, list rules, and JSON persistence; exposed through the `CaddieCore` Swift package.
- `Caddie/App/`: app entry point, `Store.swift` for state coordination, `Intelligence.swift` for classification, and `ShoppingView.swift` for UI.
- `Caddie/Assets.xcassets/`: app icons and branding.
- `Tests/CaddieCoreTests/`: automated business-rule and persistence tests.
- `Tests/ClassificationChecks.swift`: standalone checks against the real local model.

Read `CONTEXT.md` when changing terminology and `docs/design.md` before changing product behavior or classification rules.

## Build, Test, and Development Commands

Use Xcode 26 or later and an iOS 26+ simulator or device.

- `open Caddie.xcodeproj`: open Xcode; select the `Caddie` scheme and an iPhone simulator, then press Command-R.
- `swift test`: run the core package's XCTest suite on macOS.
- Build the simulator app without signing:

```sh
xcodebuild -project Caddie.xcodeproj -scheme Caddie \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` methods and properties. Keep business logic in Core and UI coordination in the `@MainActor` store. Use French user-facing text and “rayon” for aisle terminology. No formatter or linter configuration is currently checked in; match surrounding code.

## Testing Guidelines

Add XCTest methods named `test<Behavior>` in `Tests/CaddieCoreTests/` for changed core behavior. Cover duplicate identity, remembered corrections, stale classification responses, and persistence compatibility where relevant. No numeric coverage threshold is configured.

Run `swift test` and the simulator build for code changes. For UI changes, exercise affected flows in the simulator. For classification changes, follow `docs/validation.md` and validate on a compatible iPhone with Apple Intelligence enabled in French; core tests do not measure model accuracy.

## Commit & Pull Request Guidelines

History uses short imperative subjects, such as “Refactor classifier to use aisle names and add checks.” Follow that style. In PRs, describe the behavior change, link relevant issues, report validation and device/model limitations, and include screenshots for UI changes.

## Persistence & Configuration

Preserve the legacy `Application Support/Courses/list.json` location, atomic saves, and write blocking after load failures. Keep manual classification available when the local model is unavailable. Configure personal signing in Xcode for device installation.

## Agent Orchestration

The main agent remains responsible for analysis, diagnosis, architecture, planning, production changes, repairs, verification, final acceptance, and user communication.

For substantive tasks, read the relevant files in `agent_docs/`, then separate the working context into:

- decision-critical code and evidence that the main agent must inspect directly;
- bulky supporting context that a Companion can summarize;
- one bounded unknown that an Investigator can research independently.

Use subagents only when they materially reduce context pressure or uncertainty. Group independent investigations into one wave, give each worker a compact self-contained assignment, wait for the relevant results, and synthesize them once. Avoid status-only follow-ups and repeated requests for evidence already returned.

### Supporting Roles

- **Companion**: a persistent read-only context assistant for repository structure, configuration, logs, documentation, and large syntheses.
- **Investigator**: a disposable read-only researcher for one precise repository or external-documentation question. It returns facts, references, limitations, and implications; the main agent decides the solution.
- **Archivist**: a closure and handoff assistant used after substantive work. It updates `agent_docs/` from verified results without changing production code.

Subagent assignments must state the context, precise question, intended result, allowed files or sources, ownership boundary, and response format. Send the smallest sufficient context instead of the complete conversation history.

The main agent implements and tests changes itself. Subagents inspect, research, synthesize, and document; they do not own production implementation or acceptance. Handle lightweight tasks directly without creating subagents.

### Durable Project Memory

For work that changes project knowledge or spans sessions, maintain the concise documents in `agent_docs/`:

- `overview.md`: stable product purpose and scope;
- `architecture.md`: important components, boundaries, and relationships;
- `decisions.md`: durable decisions and their rationale;
- `progress.md`: verified current state and outstanding work;
- `handoff.md`: latest completed work, validation, limitations, and next entry point.

Update only the documents affected by the work. Keep verified current state in these files and remove stale details rather than accumulating a chronological transcript.
