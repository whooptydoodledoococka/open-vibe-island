import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            List {
                connectionStatusCard

                if connectionManager.recentEvents.isEmpty {
                    emptyStateSection
                } else {
                    eventSections
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await refreshStatus()
            }
            .navigationTitle("Orbit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(connectionManager)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $connectionManager.showPairing) {
                PairingView()
                    .environmentObject(connectionManager)
            }
        }
    }

    // MARK: - Connection Status Card

    @ViewBuilder
    private var connectionStatusCard: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(connectionManager.state.iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: connectionManager.state.iconName)
                        .font(.system(size: 22))
                        .foregroundStyle(connectionManager.state.iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionManager.state.displayText)
                        .font(.headline)
                        .foregroundStyle(connectionManager.state.iconColor)

                    if let macName = connectionManager.connectedMacName {
                        Text(macName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let error = connectionManager.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                connectionActionButton
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var connectionActionButton: some View {
        switch connectionManager.state {
        case .disconnected:
            Button("Connect") {
                connectionManager.startDiscovery()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .discovering:
            ProgressView()

        case .paired:
            ProgressView()
                .padding(.trailing, 4)

        case .connected:
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)

                Text("No events yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Approval requests, questions, and completed agent tasks will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    // MARK: - Event Sections (grouped by date)

    @ViewBuilder
    private var eventSections: some View {
        let grouped = groupEventsByDate(connectionManager.recentEvents)
        ForEach(grouped, id: \.key) { group in
            Section(group.label) {
                ForEach(group.events) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                            .environmentObject(connectionManager)
                    } label: {
                        eventRow(event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: WatchEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.isResolved ? "checkmark.circle.fill" : event.iconName)
                .foregroundStyle(event.isResolved ? .green : event.iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if event.isResolved {
                Text("Resolved")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text(event.agentTool)
                        .font(.caption)
                        .foregroundStyle(.blue)

                    if let subtitle = event.subtitle {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(event.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .opacity(event.isResolved ? 0.7 : 1.0)
    }

    // MARK: - Helpers

    private func refreshStatus() async {
        // If connected, the SSE stream keeps us updated.
        // If disconnected with a saved pairing, try reconnecting.
        if connectionManager.state == .disconnected,
           connectionManager.connectedMacName != nil {
            connectionManager.startDiscovery()
        }
        // Small delay so the refresh indicator feels responsive
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private struct DateGroup {
        let key: String
        let label: String
        let events: [WatchEvent]
    }

    private func groupEventsByDate(_ events: [WatchEvent]) -> [DateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event -> String in
            if calendar.isDateInToday(event.timestamp) {
                return "today"
            } else if calendar.isDateInYesterday(event.timestamp) {
                return "yesterday"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: event.timestamp)
            }
        }

        let sortedKeys = grouped.keys.sorted { a, b in
            if a == "today" { return true }
            if b == "today" { return false }
            if a == "yesterday" { return true }
            if b == "yesterday" { return false }
            return a > b
        }

        return sortedKeys.map { key in
            let label: String
            switch key {
            case "today": label = "Today"
            case "yesterday": label = "Yesterday"
            default:
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: key) {
                    let display = DateFormatter()
                    display.dateFormat = "MMM d"
                    label = display.string(from: date)
                } else {
                    label = key
                }
            }
            return DateGroup(key: key, label: label, events: grouped[key] ?? [])
        }
    }
}
