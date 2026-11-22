import FlareStatusKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var addPage: () -> Void

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
                    .contextMenu {
                        Button("Remove this page", role: .destructive) { model.removePage(page.id) }
                    }
                }
                Button(action: addPage) {
                    Label("Add a status page", systemImage: "plus")
                }
                if let page = model.selectedPage, model.demo == nil {
                    Button(role: .destructive) {
                        model.removePage(page.id)
                    } label: {
                        Label("Remove \(model.title(for: page))", systemImage: "trash")
                    }
                }
            }

            Section {
                Picker("Refresh every", selection: $model.refreshSeconds) {
                    ForEach(AppModel.refreshChoices, id: \.self) { seconds in
                        Text(Format.duration(seconds)).tag(seconds)
                    }
                }
                Toggle("Scroll through the page when idle", isOn: $model.autoScroll)
                if model.pages.count > 1 {
                    Picker("Switch between pages", selection: $model.cycleMinutes) {
                        ForEach(AppModel.cycleChoices, id: \.self) { minutes in
                            Text(minutes == 0 ? "Off" : "Every \(Format.duration(minutes * 60))").tag(minutes)
                        }
                    }
                }
                Button {
                    model.refreshNow()
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("UptimeFlare checks its monitors once a minute. The screen stays awake while this app is open.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                if let snapshot = model.state.snapshot {
                    LabeledContent("Data format", value: snapshot.format == .compacted ? "UptimeFlare D1 (2026 and later)" : "UptimeFlare KV (before 2026)")
                }
                Text("Flare Status is an unofficial viewer for UptimeFlare status pages. It talks only to the status pages you add here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView(addPage: {})
    }
    .environmentObject(AppModel(demo: .healthy))
}
