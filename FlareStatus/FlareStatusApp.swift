import FlareStatusKit
import SwiftUI
import UIKit

@main
struct FlareStatusApp: App {
    @StateObject private var model = FlareStatusApp.makeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) {
                    let active = scenePhase == .active
                    // A wall display must not fall asleep or start the screen saver.
                    UIApplication.shared.isIdleTimerDisabled = active
                    if active { model.start() } else if scenePhase == .background { model.stop() }
                }
        }
    }

    /// Launch arguments, for demos and screenshots:
    ///   -demo healthy|outage|single|large   show invented data, no network
    ///   -url https://status.example.com     show this page without saving it
    @MainActor
    private static func makeModel() -> AppModel {
        let arguments = UserDefaults.standard
        if let name = arguments.string(forKey: "demo"), let scenario = SampleData.Scenario(rawValue: name) {
            return AppModel(demo: scenario)
        }
        let model = AppModel()
        if let text = arguments.string(forKey: "url"), let url = try? PageAddress.normalize(text) {
            model.useTransientPage(url)
        }
        return model
    }
}

enum Route: Hashable {
    case monitor(String)
    case settings
    case addPage
    case refreshInterval
    case pageCycle
    case about
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var path: [Route] = RootView.initialPath

    var body: some View {
        if !model.isConfigured {
            SetupView(isFirstRun: true)
        } else {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .monitor(let id):
                            if let snapshot = model.state.snapshot,
                               let monitor = snapshot.monitor(id: id) ?? (id == "first-down" ? snapshot.downMonitors.first ?? snapshot.monitors.first : nil) {
                                MonitorDetailView(monitor: monitor, snapshot: snapshot)
                            } else {
                                Text("This monitor is no longer on the status page.")
                                    .font(.system(size: 32))
                            }
                        case .settings:
                            SettingsView(open: { path.append($0) })
                        case .addPage:
                            SetupView(isFirstRun: false, onDone: { path.removeAll() })
                        case .refreshInterval:
                            ChoiceListView(
                                title: "Refresh every",
                                choices: AppModel.refreshChoices.map { ($0, Format.duration($0)) },
                                selection: $model.refreshSeconds,
                                footer: "UptimeFlare checks its monitors once a minute, so a shorter interval rarely shows anything sooner.",
                                done: { if path.last == .refreshInterval { path.removeLast() } })
                        case .pageCycle:
                            ChoiceListView(
                                title: "Switch between pages",
                                choices: AppModel.cycleChoices.map { ($0, SettingsView.cycleLabel($0)) },
                                selection: $model.cycleMinutes,
                                footer: nil,
                                done: { if path.last == .pageCycle { path.removeLast() } })
                        case .about:
                            AboutView()
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.state.snapshot {
            DashboardView(
                snapshot: snapshot,
                openDetail: { path.append(.monitor($0.id)) },
                openSettings: { path.append(.settings) })
        } else {
            LoadingView(openSettings: { path.append(.settings) })
        }
    }

    /// `-open settings`, `-open add` or `-open <monitor id>` (or `first-down`)
    /// starts on that screen; used for screenshots.
    private static var initialPath: [Route] {
        guard let target = UserDefaults.standard.string(forKey: "open") else { return [] }
        switch target {
        case "settings": return [.settings]
        case "about": return [.settings, .about]
        case "add": return [.settings, .addPage]
        default: return [.monitor(target)]
        }
    }
}

/// Shown until the first load succeeds: either a spinner or the reason the
/// page cannot be shown, while the app keeps retrying.
private struct LoadingView: View {
    @EnvironmentObject private var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            if let error = model.state.error {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 100))
                    .foregroundStyle(Theme.warning)
                Text(error.title)
                    .font(.system(size: 52, weight: .heavy))
                Text(error.detail)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                Text("Trying again every \(Format.duration(model.refreshSeconds)).")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView()
                    .scaleEffect(2)
                    .padding(30)
                Text("Loading \(model.selectedPage?.host ?? "status page")…")
                    .font(.system(size: 36, weight: .semibold))
            }
            HStack(spacing: 30) {
                Button("Try again") { model.refreshNow() }
                Button("Settings", action: openSettings)
            }
            .padding(.top, 20)
        }
        .padding(90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
