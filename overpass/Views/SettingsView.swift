import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var store: StationStore
    @AppStorage("balance_mpg") private var balanceMpg: Double = 28
    @AppStorage("balance_tank") private var balanceTank: Double = 12
    @State private var baseURL: String = ""
    @State private var deviceSecret: String = ""
    @State private var registrationError: String?
    @State private var isRegistering = false
    @State private var health: HealthResponse?
    @State private var isLoadingHealth = false
    @State private var hasApiKey = false
    @State private var showClearConfirm = false

    private static let iso8601 = ISO8601DateFormatter()

    var body: some View {
        NavigationStack {
            Form {
                bestValueSection
                cacheSection
                authSection
                versionSection
            }
            .navigationTitle("Settings")
            .onAppear {
                baseURL = api.baseURL
                deviceSecret = KeychainService.load(forKey: "device_secret") ?? ""
                hasApiKey = KeychainService.load(forKey: "user_api_key") != nil
                Task { await loadHealth() }
            }
            .onChange(of: baseURL) { _, new in api.baseURL = new }
            .onChange(of: deviceSecret) { _, new in
                if new.isEmpty {
                    KeychainService.delete(forKey: "device_secret")
                } else {
                    KeychainService.save(new, forKey: "device_secret")
                }
            }
            .confirmationDialog(
                "Clear on-device cache?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear \(store.byId.count) stations", role: .destructive) {
                    store.clear()
                }
            } message: {
                Text("Station data will be re-fetched from the server when you next open the map.")
            }
        }
    }

    // MARK: - Sections

    private var cacheSection: some View {
        Section {
            LabeledContent("On device") {
                Text("\(store.byId.count) stations")
                    .foregroundStyle(.secondary)
            }

            if isLoadingHealth {
                LabeledContent("Server") {
                    ProgressView()
                }
            } else if let h = health {
                LabeledContent("Server") {
                    Text("\(h.cachedStations) stations")
                        .foregroundStyle(.secondary)
                }
                if let raw = h.newestFetch,
                   let date = Self.iso8601.date(from: raw) {
                    LabeledContent("Last fetched") {
                        Text(date, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !baseURL.isEmpty {
                LabeledContent("Server") {
                    Text("Unavailable")
                        .foregroundStyle(.tertiary)
                }
            }

            Button("Clear on-device cache", role: .destructive) {
                showClearConfirm = true
            }
            .disabled(store.byId.isEmpty)
        } header: {
            HStack {
                Text("Cache")
                Spacer()
                if !baseURL.isEmpty {
                    Button("Refresh") { Task { await loadHealth() } }
                        .disabled(isLoadingHealth)
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    private var bestValueSection: some View {
        Section {
            Stepper(value: $balanceMpg, in: 10...60, step: 1) {
                LabeledContent("Fuel economy", value: "\(Int(balanceMpg)) mpg")
            }
            Stepper(value: $balanceTank, in: 5...40, step: 1) {
                LabeledContent("Tank size", value: "\(Int(balanceTank)) gal")
            }
        } header: {
            Text("Best Value Sort")
        } footer: {
            Text("Used to estimate the real cost of driving to a cheaper station.")
        }
    }

    @ViewBuilder
    private var authSection: some View {
        Section("Authentication") {
            TextField("Server URL", text: $baseURL, prompt: Text("https://overpass.dunkirk.sh"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            if hasApiKey {
                Label("API key registered", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Button("Reset API key", role: .destructive) {
                    KeychainService.delete(forKey: "user_api_key")
                    hasApiKey = false
                }
            } else {
                SecureField("Device secret", text: $deviceSecret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button(isRegistering ? "Registering…" : "Register API key") {
                    Task { await register() }
                }
                .disabled(isRegistering || deviceSecret.isEmpty || baseURL.isEmpty)

                if let error = registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var versionSection: some View {
        Section {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
            LabeledContent("Version", value: "\(version) (\(build))")
                .foregroundStyle(.secondary)
        } footer: {
            HStack {
                Spacer()
                Text("Made with ♥ by ") +
                Text("[Kieran Klukas](https://dunkirk.sh)")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func loadHealth() async {
        guard !baseURL.isEmpty else { return }
        isLoadingHealth = true
        health = try? await api.fetchHealth()
        isLoadingHealth = false
    }

    private func register() async {
        isRegistering = true
        registrationError = nil
        do {
            try await api.registerKey()
            hasApiKey = true
        } catch {
            registrationError = error.localizedDescription
        }
        isRegistering = false
    }
}
