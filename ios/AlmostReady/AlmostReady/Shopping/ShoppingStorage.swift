import CryptoKit
import Foundation

struct ShoppingStorage {
    private let file: URL

    init(serverIdentity: String, userID: String, directory: URL = .applicationSupportDirectory) {
        let identity = SHA256.hash(data: Data("\(serverIdentity)\n\(userID)".utf8))
        let filename = identity.map { String(format: "%02x", $0) }.joined()
        file = directory.appending(path: "Shopping.v1", directoryHint: .isDirectory)
            .appending(path: filename).appendingPathExtension("json")
    }

    func load() throws -> ShoppingListSnapshot {
        do {
            return try JSONDecoder().decode(ShoppingListSnapshot.self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
            return ShoppingListSnapshot()
        }
    }

    func save(_ snapshot: ShoppingListSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

struct ShoppingListSnapshot: Codable {
    struct Row: Codable, Identifiable {
        let package: ShoppingPackage
        let revision: AccountRevision
        var isPurchased = false
        var editID = UUID()

        var id: String { package.key }

        var item: ShoppingItem {
            ShoppingItem(
                id: id, name: package.name, quantity: package.quantityLabel,
                estimatedPrice: package.totalPrice?.rubles, isPurchased: isPurchased
            )
        }
    }

    struct Transfer: Codable {
        enum Stage: Codable {
            case submitted(revision: AccountRevision, firstAttempt: Date)
            case reloadRevision
            case awaitingConfirmation(AccountRevision)
        }

        let rowIDs: Set<String>
        let batch: ShoppingPurchasedBatch
        let key: UUID
        var stage: Stage
        var retryAfter: Date?

        init(rowIDs: Set<String>, batch: ShoppingPurchasedBatch, stage: Stage) {
            self.rowIDs = rowIDs
            self.batch = batch
            self.key = UUID()
            self.stage = stage
        }

        // The server keeps a successful replay for 30 days.
        var hasExpired: Bool {
            guard case .submitted(_, let firstAttempt) = stage else { return false }
            return Date.now >= firstAttempt.addingTimeInterval(30 * 24 * 60 * 60)
        }
    }

    var rows: [Row] = []
    var transfer: Transfer?
}
