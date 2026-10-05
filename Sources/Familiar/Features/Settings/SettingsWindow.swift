import FamiliarRuntime
import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var connectionMode = "api" {
        didSet { if connectionMode == "api" { loadAPIKeyIfNeeded() } }
    }
    @Published var claudePath = "" {
        didSet { connectionStatus = "" }
    }
    @Published var claudeModel = ""
    @Published var claudeEffort = "medium"
    @Published var connectionStatus = ""
    @Published var checkingConnection = false
    @Published var apiKey = ""
    @Published var model = ""
    @Published var effort = "medium"
    @Published var apiBaseURL = ""
    @Published var hotkey = ""
    @Published var wandHoldSeconds = 0.8
    @Published var attachScreenshotOnText = true
    @Published var screenshotMode = "auto"
    @Published var hideFromScreenShare = false
    @Published var notesShortcut = true
    @Published var showMorningFolder = true
    /// Opens a team's setup file (`.notelingsetup`); set by the app.
    var importSetup: (() -> Void)?
    @Published var startAtLogin = false
    @Published var allowControl = false
    @Published var controlInBackground = true
    @Published var backgroundVirtualDisplay = false
    @Published var backgroundPreciseClicks = false
    @Published var mascotStyle = "innocent"
    @Published var packSecrets: [PackSecret] = []
    @Published var toolsRepo = ""
    @Published var toolsRepoToken = ""
    @Published var message = ""

    struct PackSecret: Identifiable {
        let id: String            // env var name
        let packNames: [String]
        var team = false          // a header in the team's Claude settings names it (`$NAME`)
        var value: String

        var usedBy: String { "used by " + ((team ? ["your team's Claude settings"] : []) + packNames).joined(separator: ", ") }
    }

    var toolsDir = ""
    var toolsRepoBranch = "main"
    private var savedToolsRepo = ""
    private var savedToolsRepoToken = ""
    private var loadedConfig = Config()
    private var apiKeyLoaded = false
    private var packRequirements: [String: [String]] = [:]   // secret name → the packs that need it
    private var packSecretValues: [String: String] = [:]     // their values as loaded, legacy token files included

    // MARK: the team's Claude settings

    /// What the team's linked tools set (`noteling.json`), if anything. The fields it sets show its values, can't be
    /// changed here, and are never saved into config.json.
    @Published private(set) var team: TeamSettings?
    var teamClaude: TeamSettings.Claude? { team.flatMap { $0.claude.isEmpty ? nil : $0.claude } }

    enum TeamField: CaseIterable { case connection, gateway, model, effort }

    static let teamNote = "Your team's tools set this. Unlink them to use your own."

    func teamSets(_ field: TeamField) -> Bool {
        guard let claude = teamClaude else { return false }
        switch field {
        case .connection, .gateway: return claude.baseURL != nil
        case .model: return claude.model != nil
        case .effort: return claude.effort != nil
        }
    }

    /// The note under the fields the team sets.
    var teamNoteText: String? {
        switch TeamField.allCases.filter(teamSets).count {
        case 0: return nil
        case 1: return Self.teamNote
        default: return "Your team's tools set these. Unlink them to use your own."
        }
    }

    /// One plain line on what is in effect, e.g. "Claude through llm-gateway.example.com · model claude-opus-5 · set by your team's tools".
    var teamLine: String? {
        guard let claude = teamClaude else { return nil }
        var parts = ["Claude" + (claude.host.map { " through \($0)" } ?? "")]
        if let model = claude.model { parts.append("model \(model)") }
        parts.append("set by your team's tools")
        return parts.joined(separator: " · ")
    }

    /// Where requests go when the team names the address: what someone needs to know before asking anything.
    var teamPrivacyLine: String? {
        teamClaude?.host.map { "Everything Noteling sends to Claude goes to \($0): your questions, screenshots and the text it reads from your screen." }
    }

    /// The headers the team's settings send, by name only.
    var teamHeaderNames: [String] { teamClaude?.headers?.keys.sorted() ?? [] }

    /// What the team's file asks for that isn't done as written (a header Noteling sets itself, …).
    var teamNotes: [String] { teamClaude == nil ? [] : team?.notes ?? [] }

    /// Your Anthropic key isn't sent to a gateway your team's tools set, so its field goes while one is.
    var showsAPIKey: Bool { connectionMode == "api" && !teamSets(.gateway) }

    /// The secrets the team's headers name. ANTHROPIC_API_KEY is the API key field's, while that shows.
    var teamSecretNames: [String] {
        GatewayHeaders.secretNames(teamClaude?.headers ?? [:]).filter { $0 != "ANTHROPIC_API_KEY" || !showsAPIKey }
    }

    /// Shows what the team's tools set, now or after an update while Settings is open. Fields the team stops
    /// setting show your own saved values again.
    func applyTeam(_ next: TeamSettings?) {
        team = next
        let own = loadedConfig, claude = teamClaude
        connectionMode = claude?.baseURL != nil ? "api" : (own.connectionMode == "claudeCode" ? "claudeCode" : "api")
        apiBaseURL = claude?.baseURL ?? own.apiBaseURL
        model = claude?.model ?? own.model
        claudeModel = claude?.model ?? own.claudeModel
        let level = claude?.effort ?? own.effort
        effort = level
        claudeEffort = ["low", "medium", "high"].contains(level) ? level : "high"
        rebuildSecrets()
    }

    /// The secret fields: those packs require, then those the team's headers name, keeping what is typed in them.
    private func rebuildSecrets() {
        let teamNames = Set(teamSecretNames)
        let typed = Dictionary(packSecrets.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        packSecrets = Set(packRequirements.keys).union(teamNames).sorted().map { key in
            PackSecret(id: key, packNames: packRequirements[key] ?? [], team: teamNames.contains(key),
                       value: typed[key] ?? packSecretValues[key] ?? Secrets.get(key) ?? "")
        }
    }

    /// The team-tools address or token differ from what is saved.
    var toolsRepoChanged: Bool {
        toolsRepo.trimmingCharacters(in: .whitespacesAndNewlines) != savedToolsRepo
            || toolsRepoToken.trimmingCharacters(in: .whitespacesAndNewlines) != savedToolsRepoToken
    }

    private func loadAPIKeyIfNeeded() {
        guard !apiKeyLoaded else { return }
        apiKey = loadedConfig.apiKey.isEmpty ? (Secrets.get("ANTHROPIC_API_KEY") ?? "") : loadedConfig.apiKey
        apiKeyLoaded = true
    }

    func load(config: Config, packs: [ToolPack], team: TeamSettings? = nil) {
        loadedConfig = config
        apiKeyLoaded = false
        apiKey = config.apiKey
        connectionMode = config.connectionMode == "claudeCode" ? "claudeCode" : "api"
        claudePath = config.claudePath
        claudeModel = config.claudeModel
        claudeEffort = ["low", "medium", "high"].contains(config.effort) ? config.effort : "high"
        connectionStatus = ""
        model = config.model
        effort = config.effort
        apiBaseURL = config.apiBaseURL
        hotkey = config.hotkey
        wandHoldSeconds = config.wandHoldSeconds
        attachScreenshotOnText = config.attachScreenshotOnText
        screenshotMode = config.screenshotMode
        hideFromScreenShare = config.hideFromScreenShare
        notesShortcut = config.notesShortcut
        showMorningFolder = config.showMorningFolder
        startAtLogin = SMAppService.mainApp.status == .enabled
        allowControl = config.allowControl
        controlInBackground = config.controlInBackground
        backgroundVirtualDisplay = config.backgroundVirtualDisplay
        backgroundPreciseClicks = config.backgroundPreciseClicks
        mascotStyle = config.mascotStyle
        toolsDir = config.resolvedToolsDir.path
        toolsRepo = config.toolsRepo
        toolsRepoBranch = LinkedToolsUpdater.branch(config)
        toolsRepoToken = Secrets.get(LinkedTools.tokenKey) ?? ""
        savedToolsRepo = toolsRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        savedToolsRepoToken = toolsRepoToken
        var byKey: [String: [String]] = [:]
        for p in packs { for k in p.requires { byKey[k, default: []].append(p.name) } }
        packRequirements = byKey
        packSecretValues = Dictionary(uniqueKeysWithValues: byKey.keys.map { key in
            var value = Secrets.get(key) ?? ""
            if value.isEmpty {   // legacy: a bare `token` file inside a pack folder that needs this key
                for p in packs where p.requires.contains(key) {
                    if let t = try? String(contentsOf: p.dir.appendingPathComponent("token"), encoding: .utf8),
                       let first = t.split(separator: "\n").first, !first.contains("=") { value = first.trimmingCharacters(in: .whitespaces); break }
                }
            }
            return (key, value)
        })
        packSecrets = []
        applyTeam(team)
        message = ""
    }

    func checkConnection() async {
        guard !checkingConnection else { return }
        checkingConnection = true
        connectionStatus = ""
        defer { checkingConnection = false }
        var config = loadedConfig
        config.connectionMode = "claudeCode"
        config.claudePath = claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        config.claudeModel = claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.effort = claudeEffort
        let checkedPath = claudePath
        let status = await ClaudeCodeClient.authenticationStatus(config: config)
        if claudePath == checkedPath { connectionStatus = status }
    }

    /// Your own settings with what the form says, except the fields your team's tools set: those keep your own values,
    /// so the team's are never written into config.json.
    func fields(into config: Config) -> Config {
        var c = config
        if !teamSets(.connection) { c.connectionMode = connectionMode }
        c.claudePath = claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !teamSets(.model) {
            c.claudeModel = claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
            c.model = model.trimmingCharacters(in: .whitespaces)
        }
        if !teamSets(.effort) { c.effort = connectionMode == "claudeCode" ? claudeEffort : effort }
        if !teamSets(.gateway) { c.apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespaces) }
        c.hotkey = hotkey.trimmingCharacters(in: .whitespaces)
        c.wandHoldSeconds = max(0.3, min(3, wandHoldSeconds))
        c.attachScreenshotOnText = screenshotMode != "never"
        c.screenshotMode = screenshotMode
        c.hideFromScreenShare = hideFromScreenShare
        c.notesShortcut = notesShortcut
        c.showMorningFolder = showMorningFolder
        c.allowControl = allowControl
        c.controlInBackground = controlInBackground
        c.backgroundVirtualDisplay = backgroundVirtualDisplay
        c.backgroundPreciseClicks = backgroundPreciseClicks
        c.mascotStyle = mascotStyle
        c.toolsRepo = RepoAddress.cleaned(toolsRepo)   // the plain address: credentials pasted into it are never kept
        return c
    }

    /// Returns the updated config; secrets go to the Keychain, never into the file.
    func save(into config: Config) -> Config {
        message = ""
        var c = fields(into: config)
        if showsAPIKey {
            if Secrets.set("ANTHROPIC_API_KEY", apiKey) {
                c.apiKey = ""
            } else {
                message = "Could not save the API key to the Keychain."
            }
        }
        for s in packSecrets where !Secrets.set(s.id, s.value) { message = "Could not save \(s.id) to the Keychain." }
        toolsRepo = c.toolsRepo
        savedToolsRepo = c.toolsRepo
        if Secrets.set(LinkedTools.tokenKey, toolsRepoToken) {
            savedToolsRepoToken = toolsRepoToken.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            message = "Could not save the team tools token to the Keychain."
        }
        do {
            if startAtLogin, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !startAtLogin, SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Start at login: \(error.localizedDescription)"
        }
        c.save()
        loadedConfig = c
        if message.isEmpty { message = "Saved." }
        return c
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var linkedTools: LinkedToolsUpdater?
    let onSave: () -> Void
    let onOpenTools: () -> Void
    let onReloadTools: () -> Void

    var body: some View {
        Form {
            Section("Claude") {
                if let line = model.teamLine {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if let privacy = model.teamPrivacyLine {
                            Text(privacy).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if !model.teamHeaderNames.isEmpty {
                            Text("Headers sent: " + model.teamHeaderNames.joined(separator: ", ") + ".").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(model.teamNotes, id: \.self) { note in
                            Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Picker("Connection", selection: $model.connectionMode) {
                    Text("API key").tag("api")
                    Text("Local Claude CLI").tag("claudeCode")
                }
                .setByTeam(model.teamSets(.connection))
                if model.connectionMode == "claudeCode" {
                    Text("Uses your installed Claude Code and its existing login. Requests share your Claude Code usage allowance.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Claude executable (optional)", text: $model.claudePath, prompt: Text("Find automatically"))
                    TextField("Model (optional)", text: $model.claudeModel, prompt: Text("Claude Code default"))
                        .setByTeam(model.teamSets(.model))
                    Picker("Effort", selection: $model.claudeEffort) {
                        ForEach(["low", "medium", "high"], id: \.self) { Text($0) }
                    }
                    .setByTeam(model.teamSets(.effort))
                    HStack {
                        Text("To sign in, run `claude auth login` in Terminal.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.checkingConnection ? "Checking…" : "Check connection") {
                            Task { await model.checkConnection() }
                        }
                        .disabled(model.checkingConnection)
                    }
                    if !model.connectionStatus.isEmpty {
                        Text(model.connectionStatus).font(.caption).textSelection(.enabled)
                    }
                } else {
                    if model.showsAPIKey { SecureField("API key", text: $model.apiKey) }
                    TextField("Model", text: $model.model)
                        .setByTeam(model.teamSets(.model))
                    Picker("Effort", selection: $model.effort) {
                        ForEach(TeamSettings.efforts, id: \.self) { Text($0) }
                    }
                    .setByTeam(model.teamSets(.effort))
                    TextField("Gateway base URL (optional)", text: $model.apiBaseURL, prompt: Text("https://api.anthropic.com"))
                        .setByTeam(model.teamSets(.gateway))
                }
                if let note = model.teamNoteText {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Team tools from GitHub") {
                TextField("Repository", text: $model.toolsRepo, prompt: Text(RepoAddress.example))
                SecureField("Token", text: $model.toolsRepoToken)
                if let linkedTools { LinkedToolsRow(updater: linkedTools, model: model, onSave: onSave) }
                Text("Noteling keeps a copy of this repository's \(model.toolsRepoBranch) branch and checks for changes every 10 minutes. A tool in your own folder with the same name wins.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tool packs") {
                if model.packSecrets.isEmpty {
                    Text("No pack declares a required secret. Add `requires: [NAME]` to a pack's SKILL.md and it will appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($model.packSecrets) { $s in
                    VStack(alignment: .leading, spacing: 2) {
                        SecureField(s.id, text: $s.value)
                        Text(s.usedBy).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(model.toolsDir).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Open folder", action: onOpenTools)
                    Button("Reload", action: onReloadTools)
                }
            }
            Section("Behaviour") {
                TextField("Pen hotkey", text: $model.hotkey, prompt: Text("control+option+space"))
                HStack {
                    Text("Hold to pick up the pen")
                    Slider(value: $model.wandHoldSeconds, in: 0.3...2.0, step: 0.1)
                    Text(String(format: "%.1fs", model.wandHoldSeconds)).monospacedDigit().frame(width: 36)
                }
                Picker("Screenshot with typed questions", selection: $model.screenshotMode) {
                    Text("Auto (when the question is about the screen)").tag("auto")
                    Text("Always").tag("always")
                    Text("Never").tag("never")
                }
                Toggle("Hide the bubble from screenshots and screen shares", isOn: $model.hideFromScreenShare)
                Toggle("Press ⌥ Option twice to show or hide your notes on the screen", isOn: $model.notesShortcut)
                Toggle("Show the Morning folder on the screen", isOn: $model.showMorningFolder)
                Toggle("Start Noteling at login", isOn: $model.startAtLogin)
                Toggle("Allow Noteling to control the mouse and keyboard when asked", isOn: $model.allowControl)
                Toggle("Do things in the window you asked from, keeping your mouse and keyboard", isOn: $model.controlInBackground)
                    .disabled(!model.allowControl)
                Toggle("Use a separate display for background tasks (experimental)", isOn: $model.backgroundVirtualDisplay)
                    .disabled(!model.allowControl || !model.controlInBackground)
                Text("Moves the task window off your screen while Noteling works. Returns it when the task ends.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Precise clicks in the background (experimental)", isOn: $model.backgroundPreciseClicks)
                    .disabled(!model.allowControl || !model.controlInBackground)
                Text("Lets Noteling click exact spots in a window behind your work through a private macOS path. Off, it only presses controls it can name and asks for the mouse for anything else.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Character brows", selection: $model.mascotStyle) {
                    Text("Innocent").tag("innocent")
                    Text("Innocent v1").tag("innocentV1")
                    Text("Innocent v3 (experiment)").tag("innocentV3")
                    Text("Innocent v4 (Bashful)").tag("innocentV4")
                    Text("Sharp").tag("sharp")
                }
            }
            Section {
                HStack {
                    Text(model.message).font(.caption).foregroundStyle(model.message == "Saved." ? .green : .orange)
                    Spacer()
                    Button("Save", action: onSave).keyboardShortcut(.defaultAction)
                }
                Text(Secrets.store == .file
                     ? "Secrets are stored owner-only in ~/.noteling/secrets.json (dev build) and handed to pack scripts only as environment variables."
                     : "Secrets are stored in your macOS Keychain and handed to pack scripts only as environment variables.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 700)
    }
}

/// The linked copy's status, kept current while Settings is open, which team packs your own folder overrides, and
/// Update now. Unsaved changes to the address or token are saved first; saving them checks right away.
private struct LinkedToolsRow: View {
    @ObservedObject var updater: LinkedToolsUpdater
    @ObservedObject var model: SettingsModel
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    let line = updater.checking ? "Checking for changes…" : updater.status(now: context.date)
                    if !line.isEmpty {
                        Text(line).font(.caption).foregroundStyle(updater.record?.lastError == nil || updater.checking ? Color.secondary : Color.orange)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if let problem = updater.team.problem {
                        Text(problem + (updater.team.fromEarlierFile ? " The team's earlier settings stay in effect." : " Your own Claude settings are in use."))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if !updater.team.fromEarlierFile, let ignored = updater.team.settings?.ignored, !ignored.isEmpty {
                        Text("\(TeamSettings.fileName): Noteling doesn't use \(ignored.joined(separator: ", ")), so \(ignored.count == 1 ? "it is" : "they are") ignored.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    let own = updater.overriddenPacks()
                    if !own.isEmpty {
                        Text("\(own.joined(separator: ", ")): your own folder's \(own.count == 1 ? "copy is" : "copies are") used, not the team's.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button(model.toolsRepoChanged ? "Save and update" : "Update now") {
                    if model.toolsRepoChanged { onSave() } else { Task { await updater.check() } }
                }
                .disabled(updater.checking || (model.toolsRepo.isEmpty && !model.toolsRepoChanged))
                if let importSetup = model.importSetup {
                    Button("Import setup file…", action: importSetup).help("A .notelingsetup file from your team: it links their tools for you")
                }
            }
        }
    }
}

extension View {
    /// A field your team's tools set: shown, not changeable, and saying why on hover.
    @ViewBuilder func setByTeam(_ team: Bool) -> some View {
        if team { disabled(true).help(SettingsModel.teamNote) } else { self }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var teamChanges: AnyCancellable?
    let model = SettingsModel()

    func show(config: Config, packs: [ToolPack], linkedTools: LinkedToolsUpdater? = nil, onSave: @escaping () -> Void,
              onOpenTools: @escaping () -> Void, onReloadTools: @escaping () -> Void) {
        model.load(config: config, packs: packs, team: linkedTools?.team.settings)
        if teamChanges == nil, let linkedTools {   // an update while Settings is open, such as right after linking
            teamChanges = linkedTools.$team.dropFirst().removeDuplicates().receive(on: RunLoop.main)
                .sink { [weak self] state in self?.model.applyTeam(state.settings) }
        }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Noteling Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model, linkedTools: linkedTools, onSave: onSave,
                                                                 onOpenTools: onOpenTools, onReloadTools: onReloadTools))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
