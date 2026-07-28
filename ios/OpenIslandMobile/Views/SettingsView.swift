import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        Form {
            notificationSettingsSection
            deviceSection
            dangerSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Notification Settings

    @ViewBuilder
    private var notificationSettingsSection: some View {
        Section("Notification Types") {
            Toggle(isOn: $connectionManager.notifyPermissions) {
                Label("Approval Requests", systemImage: "lock.shield")
            }
            Toggle(isOn: $connectionManager.notifyQuestions) {
                Label("Questions", systemImage: "questionmark.bubble")
            }
            Toggle(isOn: $connectionManager.notifyCompletions) {
                Label("Task Completions", systemImage: "checkmark.circle")
            }
        }

        Section {
            Toggle(isOn: $connectionManager.silentCompletions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quiet Mode")
                    Text("Deliver completion notifications without sound")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!connectionManager.notifyCompletions)
        } header: {
                    Text("Sound")
        }
    }

    // MARK: - Device Info

    @ViewBuilder
    private var deviceSection: some View {
        Section("Paired Device") {
            if let macName = connectionManager.connectedMacName {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macName)
                                .font(.body)
                            if let pairedAt = connectionManager.pairedAt {
                        Text("Paired: \(pairedAt, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    connectionStatusBadge
                }
            } else {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                Text("Not Paired")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch connectionManager.state {
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .paired:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Connecting")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .discovering:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Searching")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .disconnected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("Offline")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Danger Zone

    @ViewBuilder
    private var dangerSection: some View {
        Section {
            if connectionManager.connectedMacName != nil {
                Button(role: .destructive) {
                    connectionManager.disconnect()
                } label: {
                Label("Disconnect and Unpair", systemImage: "xmark.circle")
                }
            }

            Button {
                connectionManager.startDiscovery()
            } label: {
                Label("Search for Mac Again", systemImage: "arrow.clockwise")
            }
        }
    }
}
