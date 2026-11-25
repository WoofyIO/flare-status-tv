import FlareStatusKit
import SwiftUI

/// Asks for the address of a status page (and its password, if it has one),
/// checks it by loading it, and saves it. Shown on first run and when adding
/// another page from Settings.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    var isFirstRun: Bool
    var onDone: () -> Void = {}

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isChecking = false
    @State private var error: StatusError?

    var body: some View {
        HStack(alignment: .center, spacing: 90) {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Theme.up)
                Text(isFirstRun ? "Flare Status" : "Add a status page")
                    .font(.system(size: 68, weight: .heavy))
                Text("Shows an UptimeFlare status page on your television. Enter the address you open in a browser to see the page.")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.secondaryText)
                Text("Unofficial. Not affiliated with the UptimeFlare project.")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
            .frame(maxWidth: 640, alignment: .leading)

            VStack(alignment: .leading, spacing: 22) {
                TextField("status.example.com", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Only if the page is password protected")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 10)
                TextField("User name (optional)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password (optional)", text: $password)

                Button(action: connect) {
                    HStack(spacing: 16) {
                        if isChecking { ProgressView() }
                        Text(isChecking ? "Checking…" : "Connect")
                            .font(.system(size: 32, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isChecking || address.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.top, 14)
                .accessibilityIdentifier("setup-connect")

                if isFirstRun {
                    Button {
                        model.startSample()
                    } label: {
                        Text("Try with sample data")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isChecking)
                    .accessibilityIdentifier("setup-try-sample")
                    Text("No status page yet? Look around with invented monitors. You can come back here at any time.")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(error.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.down)
                        Text(error.detail)
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.down.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(width: 760)
        }
        .padding(90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private func connect() {
        error = nil
        isChecking = true
        Task {
            do {
                try await model.addPage(address: address, username: username, password: password)
                isChecking = false
                onDone()
            } catch let failure as StatusError {
                error = failure
                isChecking = false
            } catch {
                self.error = .offline(error.localizedDescription)
                isChecking = false
            }
        }
    }
}

#Preview {
    SetupView(isFirstRun: true)
        .environmentObject(AppModel(demo: .healthy))
}
