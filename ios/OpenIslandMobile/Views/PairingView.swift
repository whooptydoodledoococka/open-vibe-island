import SwiftUI

struct PairingView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMac: DiscoveredMac?
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @State private var showManualEntry = false
    @State private var manualHost = ""
    @State private var manualPort = "7890"
    @State private var manualCode = ""
    @State private var manualError: String?
    @State private var isManualPairing = false

    var body: some View {
        NavigationStack {
            Group {
                if selectedMac == nil {
                    macListView
                } else {
                    codeInputView
                }
            }
        .navigationTitle("Pair with Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        connectionManager.discovery.stopBrowsing()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            connectionManager.discovery.startBrowsing()
        }
    }

    // MARK: - Mac List

    @ViewBuilder
    private var macListView: some View {
        List {
            if connectionManager.discovery.isSearching {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                Text("Searching for Orbit on your local network…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !connectionManager.discovery.discoveredMacs.isEmpty {
            Section("Available Macs") {
                    ForEach(connectionManager.discovery.discoveredMacs) { mac in
                        Button {
                            selectedMac = mac
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                    .frame(width: 32)

                                VStack(alignment: .leading) {
                                    Text(mac.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if !connectionManager.discovery.isSearching && connectionManager.discovery.discoveredMacs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)

                    Text("No Mac Found")
                            .font(.headline)

                    Text("Make sure Orbit is running on your Mac and both devices are on the same Wi-Fi network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                    Button("Search Again") {
                            connectionManager.discovery.startBrowsing()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
            }

            Section {
                Button {
                    showManualEntry = true
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                    Text("Enter IP Address Manually")
                    }
                }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            manualEntrySheet
        }
    }

    // MARK: - Manual Entry Sheet

    private var manualEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $manualHost)
                        .keyboardType(.decimalPad)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    TextField("4-Digit Pairing Code", text: $manualCode)
                        .keyboardType(.numberPad)
                        .onChange(of: manualCode) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(4))
                            if filtered != newValue {
                                manualCode = filtered
                            }
                        }
                } footer: {
                Text("If Bonjour discovery is unavailable, enter your Mac's IP address and port manually.")
                }

                if let manualError {
                    Section {
                        Text(manualError)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        performManualPairing()
                    } label: {
                        if isManualPairing {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                        Text("Connect and Pair")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(manualHost.isEmpty || manualCode.count != 4 || isManualPairing)
                }
            }
            .navigationTitle("Manual Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showManualEntry = false
                    }
                }
            }
        }
    }

    // MARK: - Manual Pairing

    private func performManualPairing() {
        guard let port = UInt16(manualPort) else {
            manualError = "Enter a valid port number."
            return
        }
        isManualPairing = true
        manualError = nil

        Task {
            do {
                try await connectionManager.pairManual(host: manualHost, port: port, code: manualCode)
                showManualEntry = false
            } catch {
                manualError = error.localizedDescription
                manualCode = ""
            }
            isManualPairing = false
        }
    }

    // MARK: - Code Input

    @ViewBuilder
    private var codeInputView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(selectedMac?.name ?? "Mac")
                    .font(.title3)
                    .fontWeight(.medium)
            }

            VStack(spacing: 12) {
            Text("Enter the 4-digit pairing code shown on your Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("0000", text: $pairingCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pairingCode) { _, newValue in
                        // Limit to 4 digits
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            pairingCode = filtered
                        }
                    }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                performPairing()
            } label: {
                if isPairing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                Text("Pair")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairingCode.count != 4 || isPairing)
            .padding(.horizontal, 40)

            Button("Choose Another Mac") {
                selectedMac = nil
                pairingCode = ""
                errorMessage = nil
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Pairing

    private func performPairing() {
        guard let mac = selectedMac else { return }
        isPairing = true
        errorMessage = nil

        Task {
            do {
                try await connectionManager.pair(mac: mac, code: pairingCode)
            } catch {
                errorMessage = error.localizedDescription
                pairingCode = ""
            }
            isPairing = false
        }
    }
}
