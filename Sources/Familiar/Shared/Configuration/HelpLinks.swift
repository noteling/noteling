import Foundation

/// The guides the app points to, on GitHub, in one place: `docs/` in Noteling's repository, as on its main branch. Each
/// is a page someone can read without the source: the "How…" links in Jobs, Settings and the Morning folder's menu.
enum HelpLinks {
    static let base = "https://github.com/noteling/noteling/blob/main/docs/"

    /// Every guide, by reader: the Morning folder's Help.
    static let home = page("README.md")
    /// Linking your team's tools, for Settings.
    static let linkTeamTools = page("use/getting-started.md#link-your-teams-tools")
    /// Turning on your team's jobs and reading what they found, for Jobs.
    static let jobs = page("use/jobs.md")
    /// Where whoever keeps a team's tools starts.
    static let teamTools = page("team/README.md")
    /// What each message in Jobs means, beside a folder that can't be a job.
    static let messages = page("team/testing.md#what-each-message-means")

    static func page(_ path: String) -> URL {
        guard let url = URL(string: base + path) else { preconditionFailure("not a web address: \(base + path)") }
        return url
    }
}
