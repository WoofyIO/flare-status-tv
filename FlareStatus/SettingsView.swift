import FlareStatusKit
import SwiftUI

/// Every row here is a button or a toggle, so the remote can reach all of it.
/// Choices and the About text open on their own screens: tvOS only scrolls to
/// what can take focus, and its built-in picker does not work inside a
/// navigation stack that is driven by a typed path.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var open: (Route) -> Void

    var body: some View {
        Form {
            Section("Status pages") {
                ForEach(model.pages) { page in
                    Button {
                        model.select(page.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.title(for: page))
                                Text(page.host + (page.username == nil ? "" : "  ·  password protected"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if page.id == model.selectedPageID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.up)
                            }
                        }
                    }
                }
                Button {
                    open(.addPage)
                } label: {
                    Label("Add a status page", systemImage: "plus")
                }
                .accessibilityIdentifier("settings-add-page")
                if let page = model.selectedPage, model.demo == nil {
                    Button(role: .destructive) {
                        model.removePage(page.id)
                    } label: {
                        Label("Remove \(model.title(for: page))", systemImage: "trash")
                    }
                }
            }

            Section {
                ChoiceRow(title: "Refresh every", value: Format.duration(model.refreshSeconds)) {
                    open(.refreshInterval)
                }
                .accessibilityIdentifier("settings-refresh-every")
                Toggle("Scroll through the page when idle", isOn: $model.autoScroll)
                    .accessibilityIdentifier("settings-idle-scroll")
                if model.pages.count > 1 {
                    ChoiceRow(title: "Switch between pages", value: SettingsView.cycleLabel(model.cycleMinutes)) {
                        open(.pageCycle)
                    }
                    .accessibilityIdentifier("settings-switch-pages")
                }
                Button {
                    model.refreshNow()
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("settings-refresh-now")
            } header: {
                Text("Display")
            } footer: {
                Text("UptimeFlare checks its monitors once a minute. The screen stays awake while this app is open.")
            }

            Section {
                ChoiceRow(title: "About Flare Status", value: SettingsView.version) {
                    open(.about)
                }
                .accessibilityIdentifier("settings-about")
            }
        }
        .navigationTitle("Settings")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static func cycleLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Off" : "Every \(Format.duration(minutes * 60))"
    }
}

/// A settings row that shows its current value and opens another screen.
private struct ChoiceRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A full-screen list of choices; picking one stores it and goes back.
struct ChoiceListView<Value: Hashable>: View {
    let title: String
    let choices: [(value: Value, label: String)]
    @Binding var selection: Value
    var footer: String?
    var done: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(choices, id: \.value) { choice in
                    Button {
                        selection = choice.value
                        done()
                    } label: {
                        HStack {
                            Text(choice.label)
                            Spacer()
                            if choice.value == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.up)
                            }
                        }
                    }
                    .accessibilityIdentifier(choice.label)
                    .accessibilityValue(choice.value == selection ? "selected" : "")
                }
            } footer: {
                if let footer { Text(footer) }
            }
        }
        .navigationTitle(title)
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            Text("Flare Status")
                .font(.system(size: 64, weight: .heavy))
            VStack(alignment: .leading, spacing: 18) {
                row("Version", SettingsView.version)
                row("Data format", dataFormat)
                row("Status page", model.selectedPage?.host ?? "–")
            }
            Text("Flare Status is an unofficial viewer for UptimeFlare status pages. It is not affiliated with the UptimeFlare project.")
                .font(.system(size: 30))
                .foregroundStyle(Theme.secondaryText)
            Text("It talks only to the status pages you add in Settings. It has no accounts, no analytics and no advertising.")
                .font(.system(size: 30))
                .foregroundStyle(Theme.secondaryText)
            Text("Press Menu to go back.")
                .font(.system(size: 24))
                .foregroundStyle(Theme.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: 1300, alignment: .leading)
        .padding(90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
        // Nothing here needs focus, but tvOS wants something to hold it.
        .focusable()
    }

    private var dataFormat: String {
        guard let snapshot = model.state.snapshot else { return "–" }
        return snapshot.format == .compacted ? "UptimeFlare D1 (2026 and later)" : "UptimeFlare KV (before 2026)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 30) {
            Text(label)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 320, alignment: .leading)
            Text(value)
                .font(.system(size: 32, weight: .bold))
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(open: { _ in })
    }
    .environmentObject(AppModel(demo: .healthy))
}

#Preview("About") {
    AboutView()
        .environmentObject(AppModel(demo: .healthy))
}
