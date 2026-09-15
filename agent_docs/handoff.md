# Latest Handoff

The multiple-list and iCloud foundation is implemented. Core changes add `ListLibrary`, the version-2 `LocalStoreSnapshot`, legacy migration/quarantine handling, and the mutation journal. App changes add private/shared `CKSyncEngine` drivers, CloudKit record mapping/conflict handling, sharing UI, and invitation intake; project configuration adds CloudKit entitlements, sharing metadata, and remote-notification background delivery.

Validation completed: `swift test` 28/28; unsigned simulator build with Xcode 26.6/iOS SDK 26.5; ad hoc signed iPhone 17 Pro smoke test without an iCloud account; and an end-to-end TestFlight sharing test between the owner and a participant. The iPhone smoke test confirmed local operation and the unavailable-iCloud UI state. The TestFlight test confirmed that a shared list can be created and opened after the Production CloudKit schema was promoted.

CloudKit deployment is complete for the current container: `iCloud.com.valentin.caddie` is used throughout, `Caddie/CloudKitSchema.ckdb` is the checked-in schema source, and the Production environment includes the system `cloudkit.share` record type required for sharing. Earlier sharing failures came from that system type not yet existing in Production; they are resolved.

The list screen also contains a small orange “Développement” marker above the compact add drawer in Debug builds only. It is intentionally compiled out of TestFlight/Release builds, making it easy to tell an Xcode install from the TestFlight build.

For the next app change: run the Debug build on a device for Development-environment checks, then increment the build number, archive, upload it to App Store Connect, and distribute the processed build through the existing TestFlight tester group. Continue using `docs/icloud.md` for any schema or device/account troubleshooting. Background delivery and conflict handling remain sensible areas for broader real-device testing, but are not blockers for the already working sharing flow.
