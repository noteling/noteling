import Foundation
import FamiliarContracts
import FamiliarRuntime

/// The application resolves configuration, credentials, logging, and bundle paths
/// before selecting a provider. Runtime providers do not depend on app services.
enum ConversationBackend {
    /// `config` is the configuration in effect: your own, with what the team's tools set (`Config.applying`).
    static func make(config: Config) -> (any ConversationClient)? { make(config: config, secret: { Secrets.get($0) }) }

    /// `secret` finds the secrets that header values name (`$NAME`); without one of them there is no client, and
    /// `setupMessage` says which is missing. A secret a script makes (`secretScripts`) is made right before each
    /// request instead (`ScriptedSecrets`), so a short-lived token stays current however long the client lives.
    static func make(config: Config, secret: @escaping (String) -> String?) -> (any ConversationClient)? {
        if config.connectionMode == "claudeCode" {
            guard ClaudeCodeClient.executable(config: config) != nil else { return nil }
            return ClaudeCodeClient(config: config)
        }
        let scripted = scriptedSecrets(config)
        let headers = GatewayHeaders.resolve(config.apiHeaders, secret: { scripted.contains($0) ? nil : secret($0) })
        guard headers.missing.allSatisfy(scripted.contains) else { return nil }
        let client: ClaudeClient
        if sendsOwnKey(config), let key = config.resolvedApiKey(secret: secret) {
            client = ClaudeClient(config: config, apiKey: key, headers: headers.values)
        } else {
            // A company gateway may authenticate through its own headers (apiHeaders), so it needs no Anthropic key.
            guard !config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            client = ClaudeClient(config: config, apiKey: "", headers: headers.values)
        }
        if !scripted.isEmpty {
            client.refreshHeaders = { fresh in try await ScriptedSecrets.shared.headers(for: config, secret: secret, fresh: fresh) }
        }
        return client
    }

    /// The secrets the headers name that a script makes.
    static func scriptedSecrets(_ config: Config) -> Set<String> {
        Set(GatewayHeaders.secretNames(config.apiHeaders)).intersection(config.secretScripts.keys)
    }

    /// Your own Anthropic key goes to Anthropic, or to an address you set yourself; to a gateway your team's tools set
    /// only when their headers ask for it (`$ANTHROPIC_API_KEY`).
    static func sendsOwnKey(_ config: Config) -> Bool {
        guard config.teamClaude?.baseURL != nil else { return true }
        return URLComponents(string: config.apiBaseURL)?.host?.lowercased() == "api.anthropic.com"
    }

    static func setupMessage(config: Config) -> String { setupMessage(config: config, secret: { Secrets.get($0) }) }

    static func setupMessage(config: Config, secret: (String) -> String?) -> String {
        if config.connectionMode == "claudeCode" {
            return "Claude Code was not found. Install it and run claude auth login, then check the connection in Noteling Settings."
        }
        let scripted = scriptedSecrets(config)
        let missing = GatewayHeaders.resolve(config.apiHeaders, secret: secret).missing.filter { !scripted.contains($0) }
        if !missing.isEmpty {
            let whose = config.teamClaude?.headers != nil || config.teamClaude?.baseURL != nil ? "Your team's Claude settings" : "Your Claude gateway headers"
            let one = missing.count == 1
            return "\(whose) need \(one ? "a secret that isn't set" : "secrets that aren't set"): \(missing.joined(separator: ", ")). "
                + "Add \(one ? "it" : "them") in Noteling Settings, under Tool packs, then choose Save."
        }
        return "Add your API key in Noteling Settings to connect to Claude."
    }
}

extension ClaudeClient {
    /// `headers` are the ones sent, with their secrets filled in (`GatewayHeaders.resolve`), never `$NAME` as written.
    convenience init(config: Config, apiKey: String, headers: [String: String]) {
        self.init(options: ClaudeAPIOptions(apiKey: apiKey, model: config.model, effort: config.effort,
                                           maxTokens: config.maxTokens, baseURL: config.apiBaseURL,
                                           headers: headers), logger: { Log.info($0) })
    }
}

extension ClaudeCodeClient {
    convenience init(config: Config) {
        self.init(options: ClaudeCodeOptions(executablePath: config.claudePath, model: config.claudeModel,
                                            effort: config.effort, maxTokens: config.maxTokens),
                  pythonRuntime: PythonRuntime(config: config))
    }

    static func executable(config: Config) -> String? {
        executable(path: config.claudePath)
    }

    static func authenticationStatus(config: Config) async -> String {
        await authenticationStatus(path: config.claudePath)
    }
}

extension PythonRuntime {
    init(config: Config) {
        self = .discover(uvPath: config.uvPath, resourceURL: Bundle.main.resourceURL,
                         workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
}
