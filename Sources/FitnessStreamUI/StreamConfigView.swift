import SwiftUI
import FitnessStreamCore

/// Drop-in configuration panel for FitnessStream SDK.
///
/// Manages endpoint setup, connection verification, and metric toggle selection.
/// Present it however you want — sheet, NavigationLink, tab, etc.
///
/// ```swift
/// .sheet(isPresented: $showSettings) {
///     StreamConfigView(engine: sdk)
/// }
/// ```
public struct StreamConfigView: View {
    @ObservedObject private var engine: FitnessStreamEngine
    @ObservedObject private var config: StreamConfiguration

    @State private var urlField: String = ""
    @State private var apiKeyField: String = ""

    @State private var isVerifying = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    public init(engine: FitnessStreamEngine) {
        self.engine = engine
        self.config = engine.configuration
    }

    // MARK: - Derived state

    private var urlChanged: Bool {
        let saved = config.savedEndpointURL ?? ""
        return urlField.trimmingCharacters(in: .whitespacesAndNewlines) != saved
    }

    private var hasEndpoint: Bool {
        config.hasEndpoint
    }

    private var verifyEnabled: Bool {
        hasEndpoint && !isVerifying
    }

    // MARK: - Body

    public var body: some View {
        Form {
            streamToggleSection
            endpointSection
            connectionSection
            if hasEndpoint {
                metricToggleSection
            }
        }
        .onAppear {
            urlField = config.savedEndpointURL ?? ""
            apiKeyField = config.savedAPIKey ?? ""
        }
    }

    // MARK: - Streaming toggle

    private var streamToggleSection: some View {
        Section {
            Toggle("Stream Data", isOn: $config.streamEnabled)
                .font(.headline)
        }
    }

    // MARK: - Endpoint section

    private var endpointSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Endpoint URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/metrics", text: $urlField)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Bearer token (optional)", text: $apiKeyField)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Write Frequency")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(frequencyLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $config.frequency, in: 1...30, step: 1)

            Button(action: saveEndpoint) {
                Label("Save Endpoint", systemImage: "square.and.arrow.down")
            }
            .disabled(!urlChanged)
        } header: {
            Text("Connection")
        }
    }

    private var frequencyLabel: String {
        let s = Int(config.frequency)
        return s == 1 ? "1 second" : "\(s) seconds"
    }

    private func saveEndpoint() {
        let trimmed = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        engine.saveEndpoint(url: trimmed, apiKey: key.isEmpty ? nil : key)
        statusMessage = nil
    }

    // MARK: - Connection section

    private var connectionSection: some View {
        Section {
            Button(action: verifyConnection) {
                HStack {
                    if isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text("Verify Connection")
                }
            }
            .disabled(!verifyEnabled)

            if let statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? .red : .green)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(statusIsError ? .red : .primary)
                }
            }
        }
    }

    private func verifyConnection() {
        isVerifying = true
        statusMessage = nil

        engine.verifyConnection { result in
            isVerifying = false
            switch result {
            case .connectionFailed(let error):
                statusMessage = error.localizedDescription
                statusIsError = true
            case .connectedNoSchema:
                statusMessage = "No custom data requested"
                statusIsError = false
            case .connectedSchemaApplied:
                statusMessage = "Custom data applied"
                statusIsError = false
            case .connectedSchemaUnchanged:
                statusMessage = "Successful connection"
                statusIsError = false
            }
        }
    }

    // MARK: - Metric toggles

    private var metricToggleSection: some View {
        Section {
            let grouped = groupedMetrics()
            ForEach(grouped, id: \.group) { section in
                if grouped.count > 1 {
                    Text(section.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                }
                ForEach(section.identifiers, id: \.self) { id in
                    metricRow(identifier: id)
                }
            }
        } header: {
            Text("Data Points")
        }
    }

    private func metricRow(identifier: String) -> some View {
        let binding = Binding<Bool>(
            get: { config.metricToggles[identifier] ?? false },
            set: { config.metricToggles[identifier] = $0 }
        )

        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.friendlyName(for: identifier))
                    .font(.body)
                if config.remoteSchemaIdentifiers.contains(identifier) {
                    Text("Requested by endpoint")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private struct MetricGroup: Identifiable {
        let group: String
        let identifiers: [String]
        var id: String { group }
    }

    private func groupedMetrics() -> [MetricGroup] {
        let allIds = config.metricToggles.keys.sorted()
        var groups: [String: [String]] = [:]
        for id in allIds {
            let group = MetricCatalog.sourceGroup(for: id)
            groups[group, default: []].append(id)
        }

        let order = ["Health", "Computed", "Location", "Custom"]
        return order.compactMap { name in
            guard let ids = groups[name], !ids.isEmpty else { return nil }
            return MetricGroup(group: name, identifiers: ids)
        }
    }
}
