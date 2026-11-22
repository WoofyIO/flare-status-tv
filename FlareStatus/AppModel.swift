import FlareStatusKit
import Foundation
import SwiftUI

/// One configured status page. The password is kept in the Keychain.
struct PageConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var username: String?

    var host: String { url.host ?? url.absoluteString }
}

/// What the dashboard is showing for the selected page.
struct PageState: Equatable {
    var snapshot: StatusSnapshot?
    /// When data last arrived from the server.
    var lastSuccess: Date?
    /// The most recent failure, cleared by the next success.
    var error: StatusError?
    var isLoading = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pages: [PageConfig] = []
    @Published private(set) var selectedPageID: UUID?
    @Published private(set) var state = PageState()

    @Published var refreshSeconds: Int { didSet { save(); restartRefreshing() } }
    @Published var autoScroll: Bool { didSet { save() } }
    /// Minutes between switching pages when more than one is configured; 0 = off.
    @Published var cycleMinutes: Int { didSet { save(); restartCycling() } }

    static let refreshChoices = [30, 60, 120, 300]
    static let cycleChoices = [0, 1, 2, 5, 10]
    /// The history only changes when a monitor changes state, so the full page
    /// (which can be close to a megabyte) is fetched far less often than the
    /// small live endpoint.
    static let fullRefreshSeconds: TimeInterval = 600

    /// Set for previews, screenshots and the demo mode: no network.
    let demo: SampleData.Scenario?

    private let defaults: UserDefaults
    private var cache: [UUID: PageState] = [:]
    private var configs: [UUID: StatusClient.CachedConfig] = [:]
    private var lastFull: [UUID: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?
    private var transient = false

    init(defaults: UserDefaults = .standard, demo: SampleData.Scenario? = nil) {
        self.defaults = defaults
        self.demo = demo
        refreshSeconds = defaults.object(forKey: Keys.refresh) as? Int ?? 60
        autoScroll = defaults.object(forKey: Keys.autoScroll) as? Bool ?? true
        cycleMinutes = defaults.object(forKey: Keys.cycle) as? Int ?? 0
        if let demo {
            pages = [PageConfig(url: URL(string: "https://status.example.com/")!)]
            selectedPageID = pages[0].id
            state = PageState(snapshot: SampleData.snapshot(demo), lastSuccess: Date())
            return
        }
        if let data = defaults.data(forKey: Keys.pages),
           let stored = try? JSONDecoder().decode([PageConfig].self, from: data) {
            pages = stored
        }
        if let id = defaults.string(forKey: Keys.selected).flatMap(UUID.init), pages.contains(where: { $0.id == id }) {
            selectedPageID = id
        } else {
            selectedPageID = pages.first?.id
        }
    }

    /// Shows one page for this launch only, without saving it. Used with the
    /// `-url` launch argument.
    func useTransientPage(_ url: URL) {
        transient = true
        let page = PageConfig(url: url)
        pages = [page]
        selectedPageID = page.id
    }

    var selectedPage: PageConfig? { pages.first { $0.id == selectedPageID } }
    var isConfigured: Bool { !pages.isEmpty }

    // MARK: Pages

    /// Checks that the address is a working UptimeFlare page, then saves it.
    func addPage(address: String, username: String, password: String) async throws {
        let url = try PageAddress.normalize(address)
        let user = username.trimmingCharacters(in: .whitespaces)
        let credentials = (user.isEmpty && password.isEmpty) ? nil : Credentials(username: user, password: password)
        let result = try await StatusClient(baseURL: url, credentials: credentials).fetchFull()

        var page = PageConfig(url: url, username: credentials?.username)
        if let existing = pages.first(where: { $0.url == url }) { page.id = existing.id }
        Keychain.setPassword(credentials?.password, account: page.id.uuidString)
        pages.removeAll { $0.id == page.id }
        pages.append(page)
        cache[page.id] = PageState(snapshot: result.snapshot, lastSuccess: Date())
        configs[page.id] = result.config
        lastFull[page.id] = Date()
        save()
        select(page.id)
    }

    func removePage(_ id: UUID) {
        pages.removeAll { $0.id == id }
        cache[id] = nil
        configs[id] = nil
        Keychain.setPassword(nil, account: id.uuidString)
        if selectedPageID == id {
            selectedPageID = pages.first?.id
            state = selectedPageID.flatMap { cache[$0] } ?? PageState()
            restartRefreshing()
        }
        save()
    }

    func select(_ id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        if let current = selectedPageID { cache[current] = state }
        selectedPageID = id
        state = cache[id] ?? PageState()
        save()
        restartRefreshing()
    }

    func title(for page: PageConfig) -> String {
        let snapshot = page.id == selectedPageID ? state.snapshot : cache[page.id]?.snapshot
        return snapshot?.title ?? page.host
    }

    // MARK: Refreshing

    /// Starts (or restarts) the refresh loop; called when the app becomes active.
    func start() {
        restartRefreshing()
        restartCycling()
    }

    func stop() {
        refreshTask?.cancel()
        cycleTask?.cancel()
    }

    func refreshNow() {
        if let id = selectedPageID { lastFull[id] = nil }
        restartRefreshing()
    }

    private func restartRefreshing() {
        refreshTask?.cancel()
        guard demo == nil, let page = selectedPage else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = await self.refreshOnce(page)
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
            }
        }
    }

    /// Loads the page once and returns how long to wait before the next load.
    private func refreshOnce(_ page: PageConfig) async -> Int {
        let credentials: Credentials? = page.username.map {
            Credentials(username: $0, password: Keychain.password(account: page.id.uuidString) ?? "")
        }
        let client = StatusClient(baseURL: page.url, credentials: credentials)
        var maxAge: Int?
        state.isLoading = true
        do {
            let fullIsDue = state.snapshot == nil
                || lastFull[page.id].map { Date().timeIntervalSince($0) > AppModel.fullRefreshSeconds } ?? true
            var needsFull = fullIsDue
            if !needsFull, let snapshot = state.snapshot {
                let live = try await client.fetchLive()
                let merged = snapshot.applying(live.data)
                maxAge = live.maxAge
                if merged.needsFullRefresh {
                    needsFull = true
                } else {
                    try Task.checkCancellation()
                    state.snapshot = merged.snapshot
                }
            }
            if needsFull {
                let result = try await client.fetchFull(cachedConfig: configs[page.id])
                try Task.checkCancellation()
                state.snapshot = result.snapshot
                configs[page.id] = result.config
                lastFull[page.id] = Date()
                maxAge = result.maxAge
            }
            state.lastSuccess = Date()
            state.error = nil
        } catch is CancellationError {
            return 0
        } catch let error as StatusError {
            if !Task.isCancelled { state.error = error }
        } catch {
            if !Task.isCancelled { state.error = .offline(error.localizedDescription) }
        }
        state.isLoading = false
        // Never refresh more often than the server says its answer stays fresh.
        return max(refreshSeconds, min(maxAge ?? 0, 3600))
    }

    private func restartCycling() {
        cycleTask?.cancel()
        guard demo == nil, cycleMinutes > 0 else { return }
        cycleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let minutes = self?.cycleMinutes, minutes > 0 else { return }
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.selectNextPage()
            }
        }
    }

    private func selectNextPage() {
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == selectedPageID }) else { return }
        select(pages[(index + 1) % pages.count].id)
    }

    // MARK: Persistence

    private enum Keys {
        static let pages = "pages"
        static let selected = "selectedPage"
        static let refresh = "refreshSeconds"
        static let autoScroll = "autoScroll"
        static let cycle = "cycleMinutes"
    }

    private func save() {
        guard demo == nil, !transient else { return }
        if let data = try? JSONEncoder().encode(pages) { defaults.set(data, forKey: Keys.pages) }
        defaults.set(selectedPageID?.uuidString, forKey: Keys.selected)
        defaults.set(refreshSeconds, forKey: Keys.refresh)
        defaults.set(autoScroll, forKey: Keys.autoScroll)
        defaults.set(cycleMinutes, forKey: Keys.cycle)
    }
}
