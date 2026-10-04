import Foundation
import FamiliarContracts
import FamiliarRuntime

/// The application resolves configuration, credentials, logging, and bundle paths
/// before selecting a provider. Runtime providers do not depend on app services.
enum ConversationBackend {
    /// `config` is the configuration in effect: your own, with what the team's tools set (`Config.applying`).
    static func make(config: Config) -> (any ConversationClient)? { make(config: config, secret: { Secrets.get($0) }) }

    /// `secret` finds the secrets that header values name (`$NAME`); without one of them there is no client, and
    /// `setupMessage` says which is missing.
    static func make(config: Config, secret: (String) -> String?) -> (any ConversationClient)? {
        if config.connectionMode == "claudeCode" {
            guard ClaudeCodeClient.executable(config: config) != nil else { return nil }
            return ClaudeCodeClient(config: config)
        }
        let headers = GatewayHeaders.resolve(config.apiHeaders, secret: secret)
        guard headers.missing.isEmpty else { return nil }
        if sendsOwnKey(config), let key = config.resolvedApiKey(secret: secret) {
            return ClaudeClient(config: config, apiKey: key, headers: headers.values)
        }
        // A company gateway may authenticate through its own headers (apiHeaders), so it needs no Anthropic key.
        let gateway = config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return gateway.isEmpty ? nil : ClaudeClient(config: config, apiKey: "", headers: headers.values)
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
        let missing = GatewayHeaders.resolve(config.apiHeaders, secret: secret).missing
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
