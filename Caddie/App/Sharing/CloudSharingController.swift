import CloudKit
import SwiftUI
import UIKit

@MainActor
enum ShareInvitationCenter {
    static var handler: ((CKShare.Metadata) -> Void)?

    static func receive(_ metadata: CKShare.Metadata) {
        handler?(metadata)
    }
}

enum CloudSharingController {
    static let container = CKContainer(identifier: CloudSchema.containerIdentifier)

    static func share(for entry: LibraryList) async throws -> CKShare {
        let database = entry.provenance == .shared ? container.sharedCloudDatabase : container.privateCloudDatabase
        let zoneID = CloudSchema.zoneID(for: entry.id, ownerName: entry.cloudLocation?.ownerName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if entry.provenance == .shared {
            guard let share = try await database.record(for: shareID) as? CKShare else { throw CloudMappingError.missingEntity }
            return share
        }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        if let existing = try? await database.record(for: shareID) as? CKShare {
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = entry.metadata.name as CKRecordValue
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        return try result.saveResults[share.recordID]?.get() as? CKShare ?? share
    }

    static func accept(_ metadata: CKShare.Metadata) async throws {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let result = try await container.accept([metadata])
        _ = try result[metadata]?.get()
    }
}

struct CloudSharingView: View {
    let entry: LibraryList
    let stopped: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var share: CKShare?
    @State private var error: String?

    var body: some View {
        Group {
            if let share {
                CloudSharingControllerView(share: share, title: entry.metadata.name) {
                    stopped()
                    dismiss()
                }
            } else if let error {
                ContentUnavailableView("Partage indisponible", systemImage: "icloud.slash", description: Text(error))
            } else {
                ProgressView("Préparation du partage…")
            }
        }
        .task {
            guard share == nil, error == nil else { return }
            do { share = try await CloudSharingController.share(for: entry) }
            catch { self.error = "Vérifiez votre compte iCloud et réessayez." }
        }
    }
}

private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let title: String
    let stopped: () -> Void

    func makeCoordinator() -> Delegate {
        Delegate(title: title, stopped: stopped)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CloudSharingController.container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    @MainActor
    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        let title: String
        let stopped: () -> Void

        init(title: String, stopped: @escaping () -> Void) {
            self.title = title
            self.stopped = stopped
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            stopped()
        }
    }
}
