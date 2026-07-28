import SwiftUI
import OpenIslandCore

struct FilteringSettingsPane: View {
    var model: AppModel
    @State private var silenceStore = SilenceRuleStore.settingsBacked()
    @State private var admissionStore = AdmissionRuleStore.settingsBacked()
    @State private var silenceLabel = ""
    @State private var cwdPattern = ""
    @State private var promptPattern = ""
    @State private var launcherLabel = ""
    @State private var launcherBundleID = ""

    var body: some View {
        Form {
            Section("Silence notifications") {
                Text("Matching sessions remain visible, but Orbit suppresses island and watch notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(silenceStore.rules) { rule in
                    Toggle(rule.label, isOn: Binding(
                        get: { silenceStore.rules.first(where: { $0.id == rule.id })?.isEnabled == true },
                        set: { enabled in
                            silenceStore.setEnabled(id: rule.id, enabled: enabled)
                            model.reloadSessionFilteringRules()
                        }
                    ))
                }
                TextField("Rule label", text: $silenceLabel)
                TextField("Working-directory pattern", text: $cwdPattern)
                TextField("Prompt pattern", text: $promptPattern)
                Button("Add silence rule") {
                    silenceStore.add(
                        label: silenceLabel.isEmpty ? "Custom silence rule" : silenceLabel,
                        cwdPattern: cwdPattern,
                        promptPattern: promptPattern
                    )
                    if silenceStore.saveState == .saved {
                        silenceLabel = ""
                        cwdPattern = ""
                        promptPattern = ""
                        model.reloadSessionFilteringRules()
                    }
                }
                .disabled(cwdPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && promptPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                saveStateView(silenceStore.saveState)
            }

            Section("Admission control") {
                Text("Enabled launcher rules prevent matching sessions from entering Orbit's display state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(admissionStore.rules) { rule in
                    Toggle(rule.label.isEmpty ? rule.bundleID : rule.label, isOn: Binding(
                        get: { admissionStore.rules.first(where: { $0.id == rule.id })?.isEnabled == true },
                        set: { enabled in
                            admissionStore.setEnabled(id: rule.id, enabled: enabled)
                            model.reloadSessionFilteringRules()
                        }
                    ))
                    .help(rule.bundleID)
                }
                TextField("Launcher label", text: $launcherLabel)
                TextField("Launcher bundle identifier", text: $launcherBundleID)
                Button("Add or re-enable launcher rule") {
                    admissionStore.add(bundleID: launcherBundleID, label: launcherLabel)
                    if admissionStore.saveState == .saved {
                        launcherLabel = ""
                        launcherBundleID = ""
                        model.reloadSessionFilteringRules()
                    }
                }
                .disabled(launcherBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                saveStateView(admissionStore.saveState)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Filtering")
    }

    @ViewBuilder
    private func saveStateView(_ state: RuleSaveState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
