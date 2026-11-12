import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import AlmostReady

final class ServerProfileTests: XCTestCase {
    @MainActor
    func testLoadsCurrentProfileAndUsesExplicitCatalogBindings() async throws {
        let api = ProfileTestAPI()
        let (model, session) = try await makeModel(api)
        await model.loadProfile()

        XCTAssertEqual(model.profile?.value.displayName, "Имя с сервера")
        XCTAssertEqual(model.profile?.value.userID, SessionFixture.original.userID)
        XCTAssertEqual(model.profile?.value.unsupportedRestrictions, ["custom-table-option"])

        await model.openEditor()
        let catalogs = try XCTUnwrap(model.catalogs)
        let draft = try XCTUnwrap(model.draft)
        XCTAssertEqual(draft.base.revision.etag, #""state-7""#)
        XCTAssertEqual(draft.preferences.excludedAllergens, ["milk"])
        XCTAssertEqual(catalogs.allergens.first?.name, "Молочный белок")
        let lactose = try XCTUnwrap(catalogs.dietary.first { $0.id == "custom-lactose-option" })
        let table = try XCTUnwrap(catalogs.dietary.first { $0.id == "custom-table-option" })
        let information = try XCTUnwrap(catalogs.dietary.first { $0.id == "information" })
        XCTAssertEqual(lactose.support, .unsupported)
        XCTAssertFalse(lactose.binding?.isSelected(in: draft.preferences) ?? true)
        XCTAssertTrue(table.binding?.isSelected(in: draft.preferences) ?? false)
        XCTAssertNil(information.binding)
        let binding = try XCTUnwrap(lactose.binding)
        model.edit { binding.select(in: &$0) }
        XCTAssertEqual(model.draft?.preferences.lactoseFree, true)
        XCTAssertEqual(model.draft?.preferences.excludedAllergens, ["milk"])
        XCTAssertEqual(model.profile?.value.preferences.lactoseFree, false)

        model.closeEditor()
        let requests = await api.requests
        let reads = requests.filter { $0.url?.path != "/api/v1/me/state" }
        XCTAssertEqual(
            reads.compactMap { $0.url?.path }.sorted(),
            ["/api/v1/allergens", "/api/v1/dietary-options", "/api/v1/me", "/api/v1/me"]
        )
        for request in reads {
            try SessionFixture.assertRequest(request, method: "GET", token: SessionFixture.original.accessToken)
        }
        XCTAssertNil(model.draft)
        XCTAssertEqual(session.revision?.stateVersion, 7)
    }

    @MainActor
    func testSaveUsesDraftETagAndPublishesConfirmedRevision() async throws {
        let api = ProfileTestAPI()
        let (model, session) = try await makeModel(api)
        await model.openEditor()
        model.edit {
            $0.lactoseFree = true
            $0.dietTableID = nil
            $0.excludedAllergens.insert("eggs")
        }
        let originalDraft = try XCTUnwrap(model.draft?.preferences)
        await model.save()

        let writes = await api.patches
        let patch = try XCTUnwrap(writes.first)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(patch.etag, #""state-7""#)
        XCTAssertNotNil(UUID(uuidString: patch.key))
        XCTAssertEqual(patch.preferences, originalDraft)
        let patchRequest = await api.lastPatchRequest()
        let request = try XCTUnwrap(patchRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? NSDictionary)
        let expected: NSDictionary = [
            "preferences": [
                "food_type": "any",
                "excluded_allergens": ["eggs", "milk"],
                "gluten_free": false,
                "lactose_free": true,
                "diabetes": false,
                "diet_table_id": NSNull()
            ] as [String: Any]
        ]
        XCTAssertEqual(json, expected)
        XCTAssertEqual(session.revision?.stateVersion, 8)
        XCTAssertEqual(model.profile?.value.preferences, originalDraft)
        XCTAssertNil(model.editorID)
        XCTAssertNil(model.draft)

        await model.openEditor()
        XCTAssertEqual(model.draft?.preferences, originalDraft)
        XCTAssertEqual(model.draft?.base.revision.etag, #""state-8""#)
    }

    @MainActor
    func testFailureKeepsDraftAndRetryReusesTheOperation() async throws {
        let api = ProfileTestAPI(patchResults: [.timeout, .success])
        let (model, session) = try await makeModel(api)
        await model.openEditor()
        model.edit { $0.glutenFree = true }
        let input = try XCTUnwrap(model.draft?.preferences)

        await model.save()

        XCTAssertEqual(model.phase, .saveFailed)
        XCTAssertEqual(model.draft?.preferences, input)
        XCTAssertEqual(model.profile?.value.preferences.glutenFree, false)
        XCTAssertEqual(session.revision?.stateVersion, 7)

        await model.save()

        let writes = await api.patches
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.first, writes.last)
        XCTAssertEqual(model.profile?.value.preferences, input)
        XCTAssertEqual(session.revision?.stateVersion, 8)
    }

    @MainActor
    func testDuplicateLoadCannotReplaceTheDraft() async throws {
        let requestStarted = expectation(description: "First profile GET entered the transport")
        let finishRead = SessionResponseGate()
        defer { Task { await finishRead.open() } }
        let api = ProfileTestAPI(beforeFirstProfileRead: {
            requestStarted.fulfill()
            await finishRead.wait()
        })
        let (model, _) = try await makeModel(api)
        let opening = Task { await model.openEditor() }
        await fulfillment(of: [requestStarted], timeout: 5)

        await model.loadEditor()

        XCTAssertEqual(model.phase, .loading)
        XCTAssertNil(model.draft)
        await finishRead.open()
        await opening.value
        XCTAssertEqual(model.phase, .editing)
        let requests = await api.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/me" }.count, 1)
    }

    @MainActor
    func testProfileRetryAfterAlsoDefersEditorReads() async throws {
        let api = ProfileTestAPI(profileReadRetryAfter: "3600")
        let (model, _) = try await makeModel(api)

        await model.loadProfile()
        let deadline = try XCTUnwrap(model.retryAfter)
        XCTAssertTrue(model.profileLoadFailed)
        XCTAssertGreaterThan(deadline, .now)

        await model.loadProfile()
        await model.openEditor()
        await model.loadEditor()

        XCTAssertEqual(model.phase, .loadFailed)
        let requests = await api.requests
        XCTAssertEqual(requests.compactMap { $0.url?.path }, ["/api/v1/me/state", "/api/v1/me"])
    }

    @MainActor
    func testEditorRetryAfterLeavesProfileRetryAvailableOnReturn() async throws {
        let api = ProfileTestAPI(profileReadRetryAfter: "3600")
        let (model, _) = try await makeModel(api)

        await model.openEditor()
        model.closeEditor()
        await model.loadProfile()

        XCTAssertNil(model.profile)
        XCTAssertTrue(model.profileLoadFailed)
        XCTAssertNotNil(model.retryAfter)
        let requests = await api.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/me" }.count, 1)
    }

    @MainActor
    func testLostSuccessResponseReconcilesWithoutWritingAgain() async throws {
        let api = ProfileTestAPI(patchResults: [.timeoutAfterCommit])
        let (model, session) = try await makeModel(api)
        await model.openEditor()
        model.edit { $0.lactoseFree = true }
        let input = try XCTUnwrap(model.draft?.preferences)

        await model.save()
        XCTAssertEqual(model.phase, .saveFailed)
        XCTAssertEqual(session.revision?.stateVersion, 7)

        await model.save()
        XCTAssertEqual(model.phase, .conflictReady)
        XCTAssertEqual(model.draft?.preferences, input)
        XCTAssertEqual(model.conflict?.value.preferences, input)
        XCTAssertEqual(session.revision?.stateVersion, 8)

        model.reconcileConflict()

        XCTAssertNil(model.editorID)
        XCTAssertEqual(model.profile?.value.preferences, input)
        let writes = await api.patches
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.first, writes.last)
    }

    @MainActor
    func test412RefreshesAndWaitsForExplicitReconciliationAndSave() async throws {
        let api = ProfileTestAPI()
        let (model, session) = try await makeModel(api)
        await model.openEditor()
        model.edit {
            $0.excludedAllergens.remove("milk")
            $0.excludedAllergens.insert("eggs")
            $0.lactoseFree = true
        }
        let input = try XCTUnwrap(model.draft?.preferences)
        await api.applyRemoteChange()
        // Other features can advance the session revision while the draft is open.
        try await session.reloadRevision(for: model.repository.account)
        await model.save()

        XCTAssertEqual(model.phase, .conflictReady)
        XCTAssertEqual(model.draft?.preferences, input)
        XCTAssertEqual(model.draft?.base.revision.etag, #""state-7""#)
        XCTAssertEqual(model.conflict?.value.preferences.excludedAllergens, ["milk", "sesame"])
        XCTAssertEqual(model.conflict?.value.preferences.foodType, "vegetarian")
        XCTAssertEqual(session.revision?.stateVersion, 8)
        let conflictRequests = await api.requests
        XCTAssertEqual(
            conflictRequests.suffix(3).compactMap { $0.url?.path },
            ["/api/v1/me", "/api/v1/me/state", "/api/v1/me"]
        )
        await model.save()
        model.reconcileConflict()

        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.draft?.preferences.excludedAllergens, ["eggs", "sesame"])
        XCTAssertEqual(model.draft?.preferences.foodType, "vegetarian")
        XCTAssertEqual(model.draft?.preferences.lactoseFree, true)
        XCTAssertEqual(model.draft?.base.revision.etag, #""state-8""#)
        let patchCount = await api.patches.count
        XCTAssertEqual(patchCount, 1)

        await model.save()

        let writes = await api.patches
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.first?.etag, #""state-7""#)
        XCTAssertEqual(writes.last?.etag, #""state-8""#)
        XCTAssertNotEqual(writes.first?.key, writes.last?.key)
        XCTAssertEqual(model.profile?.value.preferences.excludedAllergens, ["eggs", "sesame"])
        XCTAssertEqual(session.revision?.stateVersion, 9)
    }

    @MainActor
    func test412KeepsDraftWhenConflictReloadFails() async throws {
        let api = ProfileTestAPI(patchResults: [.conflict], failConflictRead: true)
        let (model, _) = try await makeModel(api)
        await model.openEditor()
        model.edit { $0.foodType = "vegan" }

        await model.save()

        XCTAssertEqual(model.phase, .conflictReloadFailed)
        XCTAssertEqual(model.draft?.preferences.foodType, "vegan")
        XCTAssertEqual(model.draft?.base.revision.etag, #""state-7""#)
        XCTAssertFalse(model.canSave)

        await model.reloadConflict()

        XCTAssertEqual(model.phase, .conflictReady)
        XCTAssertEqual(model.draft?.preferences.foodType, "vegan")
        let patchCount = await api.patches.count
        XCTAssertEqual(patchCount, 1)
    }

    @MainActor
    func testLateSaveCannotUpdateTheNextAccount() async throws {
        let requestStarted = expectation(description: "Profile PATCH entered the transport")
        let finishPatch = SessionResponseGate()
        defer { Task { await finishPatch.open() } }
        let api = ProfileTestAPI(
            displayName: nil,
            beforePatch: {
                requestStarted.fulfill()
                await finishPatch.wait()
            })
        let (oldModel, session) = try await makeModel(api)
        await oldModel.openEditor()
        let previous = try XCTUnwrap(oldModel.profile?.value)
        XCTAssertNil(previous.displayName)
        oldModel.edit { $0.lactoseFree = true }
        let saving = Task { await oldModel.save() }
        await fulfillment(of: [requestStarted], timeout: 5)

        let logout = try await session.signOut()
        XCTAssertEqual(logout, .revoked)
        await session.signIn()
        let newAccount = try XCTUnwrap(session.account)
        XCTAssertNotEqual(newAccount, oldModel.repository.account)
        let newModel = ServerProfileModel(repository: ProfileRepository(session: session, account: newAccount))
        await newModel.loadProfile()
        await finishPatch.open()
        await saving.value

        XCTAssertEqual(newModel.profile?.value.userID, SessionFixture.another.userID)
        let current = try XCTUnwrap(newModel.profile?.value)
        XCTAssertNil(current.displayName)
        XCTAssertNotEqual(previous.userID, current.userID)
        XCTAssertEqual(newModel.profile?.value.preferences.lactoseFree, false)
        XCTAssertEqual(session.revision?.stateVersion, 2)
        XCTAssertEqual(oldModel.profile?.value.preferences.lactoseFree, false)
    }

    @MainActor
    func testMountedProfileLoadsTheNewAccountAfterLogout() async throws {
        let originalProfile = expectation(description: "Mounted profile requests the original account")
        let nextProfile = expectation(description: "Mounted profile requests the new account")
        originalProfile.assertForOverFulfill = false
        nextProfile.assertForOverFulfill = false

        let api = ProfileTestAPI()
        let storage = SessionTestStorage(.active(SessionFixture.original))
        let session = try SessionFixture.store(storage: storage) { request in
            let response = try await api.respond(to: request)
            if request.url?.path == "/api/v1/me" {
                switch request.value(forHTTPHeaderField: "Authorization") {
                case "Bearer \(SessionFixture.original.accessToken)": originalProfile.fulfill()
                case "Bearer \(SessionFixture.another.accessToken)": nextProfile.fulfill()
                default: XCTFail("The profile must use the current account's bearer token")
                }
            }
            return response
        }
        await session.restore()
        let originalAccount = try XCTUnwrap(session.account)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(
            rootView: NavigationStack { ProfileScreen() }.environment(session)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }
        await fulfillment(of: [originalProfile], timeout: 10)

        let logout = try await session.signOut()
        XCTAssertEqual(logout, .revoked)
        XCTAssertFalse(session.isCurrent(originalAccount))
        XCTAssertNil(session.account)

        await session.signIn()
        await fulfillment(of: [nextProfile], timeout: 10)
        XCTAssertNotEqual(try XCTUnwrap(session.account), originalAccount)
    }

    @MainActor
    private func makeModel(_ api: ProfileTestAPI) async throws -> (ServerProfileModel, SessionStore) {
        let storage = SessionTestStorage(.active(SessionFixture.original))
        let session = try SessionFixture.store(storage: storage) { try await api.respond(to: $0) }
        await session.restore()
        let account = try XCTUnwrap(session.account)
        return (ServerProfileModel(repository: ProfileRepository(session: session, account: account)), session)
    }
}

private actor ProfileTestAPI {
    enum PatchResult: Equatable {
        case success, timeout, timeoutAfterCommit, conflict
    }

    struct Patch: Equatable {
        let etag: String
        let key: String
        let preferences: ProfilePreferences
    }

    private struct Update: Decodable {
        let preferences: ProfilePreferences
    }

    private(set) var requests: [URLRequest] = []
    private(set) var patches: [Patch] = []
    private var version = 7
    private var preferences = ProfilePreferences(
        foodType: "any", excludedAllergens: ["milk"], glutenFree: false, lactoseFree: false, diabetes: false,
        dietTableID: "table-value"
    )
    private var patchResults: [PatchResult]
    private var failConflictRead: Bool
    private let displayName: String?
    private let profileReadRetryAfter: String?
    private let beforePatch: (@Sendable () async -> Void)?
    private var beforeFirstProfileRead: (@Sendable () async -> Void)?

    init(
        patchResults: [PatchResult] = [], failConflictRead: Bool = false,
        displayName: String? = "Имя с сервера", profileReadRetryAfter: String? = nil,
        beforePatch: (@Sendable () async -> Void)? = nil,
        beforeFirstProfileRead: (@Sendable () async -> Void)? = nil
    ) {
        self.patchResults = patchResults
        self.failConflictRead = failConflictRead
        self.displayName = displayName
        self.profileReadRetryAfter = profileReadRetryAfter
        self.beforePatch = beforePatch
        self.beforeFirstProfileRead = beforeFirstProfileRead
    }

    func lastPatchRequest() -> URLRequest? {
        requests.last { $0.httpMethod == "PATCH" }
    }

    func applyRemoteChange() {
        version += 1
        preferences.foodType = "vegetarian"
        preferences.excludedAllergens.insert("sesame")
    }

    func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let fixture = SessionFixture.self
        let isOther = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixture.another.accessToken)"
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/api/v1/me/state"):
            if isOther { return try fixture.stateResponse(request, version: 2, user: fixture.another) }
            return try fixture.stateResponse(request, version: version)
        case ("POST", "/api/v1/auth/logout"):
            return try fixture.response(request, status: 204)
        case ("POST", "/api/v1/auth/yandex"):
            return try fixture.sessionResponse(request, fixture.another)
        case ("GET", "/api/v1/me"):
            if let beforeFirstProfileRead {
                self.beforeFirstProfileRead = nil
                await beforeFirstProfileRead()
            }
            if isOther { return try profile(request, user: fixture.another, version: 2) }
            if let profileReadRetryAfter {
                return try fixture.error(request, status: 429, code: "rate_limited", retryAfter: profileReadRetryAfter)
            }
            if version == 8 && failConflictRead {
                failConflictRead = false
                throw URLError(.timedOut)
            }
            return try profile(request, user: fixture.original, version: version)
        case ("GET", "/api/v1/allergens"):
            return try fixture.response(
                request,
                body: [
                    "catalog_version": "fixture",
                    "items": [
                        ["id": "milk", "name": "Молочный белок", "support": "supported"],
                        ["id": "eggs", "name": "Яйца", "support": "supported"],
                        ["id": "sesame", "name": "Кунжут", "support": "supported"]
                    ]
                ])
        case ("GET", "/api/v1/dietary-options"):
            return try fixture.response(
                request,
                body: [
                    "catalog_version": "fixture",
                    "items": [
                        option("any-option", "Без предпочтений", field: "food_type", value: "any"),
                        option("custom-lactose-option", "Без лактозы", field: "lactose_free", value: true),
                        option("custom-table-option", "Стол", field: "diet_table_id", value: "table-value"),
                        [
                            "id": "information", "name": "Пояснение", "support": "informational",
                            "profile_binding": NSNull()
                        ]
                    ]
                ])
        case ("PATCH", "/api/v1/me"):
            let body = try XCTUnwrap(request.httpBody)
            let payload = try JSONDecoder().decode(Update.self, from: body)
            patches.append(
                Patch(
                    etag: try XCTUnwrap(request.value(forHTTPHeaderField: "If-Match")),
                    key: try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key")),
                    preferences: payload.preferences
                )
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(fixture.original.accessToken)")
            await beforePatch?()
            let result = patchResults.isEmpty ? .success : patchResults.removeFirst()
            switch result {
            case .timeout:
                throw URLError(.timedOut)
            case .conflict:
                applyRemoteChange()
                return try fixture.error(request, status: 412, code: "state_conflict")
            case .success, .timeoutAfterCommit:
                guard patches.last?.etag == #""state-\#(version)""# else {
                    return try fixture.error(request, status: 412, code: "state_conflict")
                }
                version += 1
                preferences = payload.preferences
                if result == .timeoutAfterCommit { throw URLError(.timedOut) }
                return try profile(request, user: fixture.original, version: version)
            }
        default:
            XCTFail("Unexpected request: \(request)")
            throw URLError(.unsupportedURL)
        }
    }

    private func profile(_ request: URLRequest, user: SessionTokens, version: Int) throws -> (Data, URLResponse) {
        let name = user == SessionFixture.original ? displayName : nil
        return try SessionFixture.response(
            request,
            body: [
                "user_id": user.userID,
                "display_name": name as Any? ?? NSNull(),
                "preferences": [
                    "food_type": preferences.foodType,
                    "excluded_allergens": preferences.excludedAllergens.sorted(),
                    "gluten_free": preferences.glutenFree,
                    "lactose_free": preferences.lactoseFree,
                    "diabetes": preferences.diabetes,
                    "diet_table_id": preferences.dietTableID as Any? ?? NSNull()
                ],
                "unsupported_restrictions": preferences.dietTableID == nil ? [] : ["custom-table-option"],
                "state_version": version
            ],
            etag: #""state-\#(version)""#
        )
    }

    private func option(_ id: String, _ name: String, field: String, value: Any) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "support": field == "food_type" ? "supported" : "unsupported",
            "profile_binding": ["field": field, "value": value]
        ]
    }
}
