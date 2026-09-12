import Foundation

// Compile with the app's Intelligence.swift and ShoppingList.swift to exercise the real on-device model.
@main
struct ClassificationChecks {
    enum Failure: Error {
        case unavailable(String)
        case invalidArguments
        case wrongAisle(product: String, expected: String, actual: String)
        case unexpectedSuggestion(String)
        case failedChecks(Int)
    }

    @MainActor
    static func main() async {
        do {
            try await check()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor
    static func check() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst().prefix { !$0.hasPrefix("-Apple") })
        guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else {
            throw Failure.invalidArguments
        }
        let intelligence = Intelligence()
        if let status = intelligence.status { throw Failure.unavailable(status) }
        var failures = 0
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let name = arguments[index]
            let expected = arguments[index + 1]
            for reversed in [false, true] {
                var list = ShoppingList.initial()
                if reversed { list.aisles.reverse() }
                let id = try list.add(name: name, note: "")
                let item = list.items[0]
                let result = try await intelligence.classify(name: name, aisles: list.aisles)
                list.applyClassification(id, revision: item.revision, aisles: list.aisles,
                                         aisle: result.aisle, suggestion: result.suggestion)
                let actual = list.aisles.first { $0.id == list.items[0].aisleID }?.name ?? "À classer"
                guard actual == expected else {
                    print("FAIL: \(Failure.wrongAisle(product: name, expected: expected, actual: actual))")
                    failures += 1
                    continue
                }
                if actual != "À classer", let suggestion = result.suggestion {
                    throw Failure.unexpectedSuggestion(suggestion)
                }
                print("PASS: \(name) → \(actual) (reversed: \(reversed), fresh UUIDs)")
            }
        }
        guard failures == 0 else { throw Failure.failedChecks(failures) }
    }
}
