import AppKit
import Foundation
import Testing
import FamiliarContracts
@testable import Familiar

/// Jobs: every job kept as a folder in one list, each row's words, the Jobs window's screens and every way in. Temp
/// folders only; nothing runs a script or reaches a model.
@Suite @MainActor
struct JobsPageTests {
    @Test func jobsBeforeTheirStartOrPastTheirEndWaitUnderOneLineOnlyToBeLookedAt() throws {
        var live = folderJob("Live sale", path: "live", state: failed("Signed out"))
        live.ends = moment(now + 3_600)
        var soon = folderJob("Soon", path: "soon", team: true, on: false)
        soon.starts = moment(now + 7_200)
        var later = folderJob("Later", path: "later")
        later.starts = moment(now + 86_400)
        let ranBefore = now - 7_200
        var ended = folderJob("Ended red", path: "ended", team: true, state: found("1 of 1 wrong", at: ranBefore))
        ended.ends = moment(now - 3_600)
        var gone = folderJob("Long gone", path: "gone", state: failed("Signed out", at: now - 2 * 86_400))
        gone.ends = moment(now - 86_400)
        var input = Jobs.Input(folderJobs: [live, soon, later, ended, gone], now: now)
        input.setup.missingJobSecrets = { ["Soon", "Ended red"].contains($0.name) ? ["SHOP_API_KEY"] : [] }

        // The list holds the live jobs; the rest wait, the soonest to start first and the latest to end first.
        let jobs = Jobs.list(input)
        #expect(jobs.filter(\.isLive).map(\.name) == ["Live sale"])
        let outside = Jobs.outside(jobs)
        #expect(outside.upcoming.map(\.name) == ["Soon", "Later"])
        #expect(outside.ended.map(\.name) == ["Ended red", "Long gone"])

        // Nothing out of the way asks for the person: no red, no problem, never first.
        for job in outside.upcoming + outside.ended {
            #expect(!job.needsAttention && !job.resultIsProblem && !job.status.isProblem && job.runProblem == nil)
        }
        let endedRed = outside.ended[0]
        #expect(endedRed.status == .ready && endedRed.problems.isEmpty)
        #expect(endedRed.every == "Every 2 hours · Ended " + (ended.ends?.words ?? ""))
        #expect(endedRed.lastRun == "Last run \(JobWords.time(ranBefore, now: now)) · 1 of 1 wrong")   // still there to look at
        #expect(outside.ended[1].status == .ready)                                                    // its last run failed: not Failed
        // An upcoming one still says, quietly, what it lacks, so it can be put right before it starts.
        #expect(outside.upcoming[0].status == .off && outside.upcoming[0].problems == ["Needs SHOP_API_KEY in Settings."])

        // No buttons, but an upcoming team job's switch, to turn it on ahead of its start.
        #expect(Jobs.controls(outside.upcoming[0], canOpenSettings: true) == [.onOff])
        #expect(Jobs.controls(outside.upcoming[1], canOpenSettings: true) == [])
        #expect(Jobs.controls(endedRed, canOpenSettings: true) == [] && Jobs.controls(outside.ended[1], canOpenSettings: true) == [])

        // One quiet line for them.
        #expect(Jobs.outsideLine(upcoming: 2, ended: 2, showing: false) == "Upcoming (2) · Ended (2) · Show")
        #expect(Jobs.outsideLine(upcoming: 0, ended: 1, showing: false) == "Ended (1) · Show")
        #expect(Jobs.outsideLine(upcoming: 2, ended: 2, showing: true) == "Hide upcoming and ended jobs")
        #expect(Jobs.outsideLine(upcoming: 1, ended: 0, showing: true) == "Hide upcoming jobs")
        #expect(Jobs.outsideLine(upcoming: 0, ended: 0, showing: false) == nil)
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var time: String { JobWords.time(now, now: now) }

    /// A job kept as a folder, as its store would have it.
    private func folderJob(_ name: String, path: String, team: Bool = false, on: Bool = true, every: Int? = 120, about: String = "",
                           state: FolderJobState = FolderJobState()) -> FolderJob {
        var job = FolderJob(id: UUID(), source: team ? .team : .own, path: path, name: name, about: about, everyMinutes: every)
        job.on = on
        job.state = state
        return job
    }

    private func failed(_ why: String, at: Date? = nil) -> FolderJobState { FolderJobState(lastRunAt: at ?? now, error: why) }
    private func found(_ said: String, at: Date? = nil) -> FolderJobState {
        FolderJobState(lastRunAt: at ?? now, lastSuccessAt: at ?? now, said: said)
    }
    private func moment(_ date: Date) -> JobMoment { JobMoment(text: ISO8601DateFormatter().string(from: date), date: date) }

    // MARK: one list

    @Test func jobsThatNeedAttentionComeFirstThenYoursThenTheTeamsByName() {
        let stuck = folderJob("Stuck orders", path: "stuck", state: failed("The orders service asked to sign in again."))
        let gift = folderJob("Gift guide", path: "gift", state: found("Nothing to look at"))
        let zeta = folderJob("Zeta", path: "zeta", team: true, state: failed("Signed out"))
        let alpha = folderJob("Alpha", path: "alpha", team: true, state: found("1 of 2 wrong"))
        let off = folderJob("Off and failed", path: "off", team: true, on: false, state: failed("Signed out"))
        let jobs = Jobs.list(Jobs.Input(folderJobs: [stuck, gift, zeta, alpha, off], now: now))
        // A job whose last run failed first (yours, then the team's); then the rest of yours, then the rest of the
        // team's, each by name. A team job that's off never needs attention.
        #expect(jobs.map(\.name) == ["Stuck orders", "Zeta", "Gift guide", "Alpha", "Off and failed"])
        #expect(jobs.map(\.needsAttention) == [true, true, false, false, false])
        let failedJob = jobs.first { $0.name == "Stuck orders" }
        #expect(failedJob?.status == .failed && failedJob?.runProblem == "The orders service asked to sign in again.")
        #expect(failedJob?.lastRun == "Last run \(time) · failed" && failedJob?.resultIsProblem == true)
        #expect(jobs.first { $0.name == "Alpha" }?.does == "Runs its job.py · from your team's tools")

        // Sorting alone: by name within each group, whatever came first.
        let a = Job(id: UUID(), kind: .job, name: "b job", does: "", every: "", lastRun: "", status: .ready)
        let b = Job(id: UUID(), kind: .job, name: "A job", does: "", every: "", lastRun: "", status: .ready)
        let c = Job(id: UUID(), kind: .teamJob, name: "a team job", does: "", every: "", lastRun: "", status: .ready)
        let d = Job(id: UUID(), kind: .teamJob, name: "z team job", does: "", every: "", lastRun: "", status: .failed, needsAttention: true)
        #expect(Jobs.sorted([c, a, d, b]).map(\.name) == ["z team job", "A job", "b job", "a team job"])
    }

    @Test func teamJobsSayWhereTheyComeFromAndShowTheirSwitch() async throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let fashion = try fixture.job("holiday/oct/fashion", #"{"name": "Fashion", "about": "Prices on the fashion items", "every_minutes": 120}"#, team: true)
        func job() throws -> Job { try #require(Jobs.list(fixture.input()).first { $0.id == fashion.id }) }

        // Off: what it is, and the switch, nothing to run.
        #expect(try job().status == .off && job().status.label == "Off")
        #expect(try job().does == "Prices on the fashion items · from your team's tools")
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.onOff])
        #expect(try !job().needsAttention)

        // The switch turns it on; then it runs at once and has Run now.
        #expect(try fixture.actions.turn(job(), on: true) == nil)
        #expect(fixture.jobs.job(id: fashion.id)?.on == true)
        #expect(try Jobs.controls(job(), canOpenSettings: true) == [.runNow, .onOff])
        await fixture.jobRunner.finish()   // turning it on runs it at once
        #expect(fixture.jobs.job(id: fashion.id)?.state.said == "Ran in the test.")
        #expect(Jobs.teamIntro == "From your team's tools. Turn on the ones that are yours: only those run and tell you.")

        // One of yours has no switch: it runs while its folder is there.
        let own = try fixture.job("mine", #"{"name": "Mine"}"#)
        let mine = try #require(Jobs.list(fixture.input()).first { $0.id == own.id })
        #expect(Jobs.controls(mine, canOpenSettings: true) == [.runNow])
        #expect(fixture.actions.turn(mine, on: false) == "Only your team's jobs are turned on and off. Yours run while their folder is there.")
    }

    @Test func everyStateHasItsWordAndOnlyAProblemIsRed() {
        let labels = [Job.Status.ready, .running, .waiting, .off, .needsSettings, .failed]
        #expect(labels.map(\.label) == [nil, "Running", "Waiting to run", "Off", "Needs Settings", "Failed"])
        #expect(labels.filter(\.isProblem) == [.needsSettings, .failed])

        // Running, waiting its turn, or needing a secret.
        let job = folderJob("Sale items", path: "sale", state: found("Nothing to look at"))
        #expect(Jobs.folderJob(job, Jobs.Input(folderJobs: [job], runningJob: job.id, now: now)).status == .running)
        #expect(Jobs.folderJob(job, Jobs.Input(folderJobs: [job], queuedJobs: [job.id], now: now)).status == .waiting)
        var input = Jobs.Input(folderJobs: [job], now: now)
        input.setup.missingJobSecrets = { _ in ["SHOP_TOKEN"] }
        let settings = Jobs.folderJob(job, input)
        #expect(settings.status == .needsSettings && settings.problems == ["Needs SHOP_TOKEN in Settings."] && settings.needsAttention)
        #expect(Jobs.controls(settings, canOpenSettings: true) == [.openSettings])
        #expect(Jobs.controls(settings, canOpenSettings: false) == [.runNow])
    }

    @Test func runNowRunsAJobKeptAsAFolderAndWaitsWhileItRuns() async throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        func job(_ id: UUID) throws -> Job { try #require(Jobs.list(fixture.input()).first { $0.id == id }) }
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)
        #expect(try fixture.actions.canRun(job(own.id)))
        #expect(try fixture.actions.runNow(job(own.id)) == nil)   // started, and nothing to say
        #expect(try !fixture.actions.canRun(job(own.id)))          // running or waiting its turn
        await fixture.jobRunner.finish()
        #expect(try job(own.id).lastRun == "Last run \(JobWords.time(fixture.jobs.job(id: own.id)?.state.lastRunAt ?? now)) · Ran in the test.")
    }

    // MARK: the window

    @Test func theWindowsScreensHaveTitlesAndBackLeadsToJobs() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)
        func title(_ route: JobsNavigation.Route) -> String {
            JobsNavigation.title(for: route, jobName: { fixture.jobs.job(id: $0)?.name })
        }
        #expect(title(.jobs) == "Jobs" && title(.folderJob(own.id)) == "Stuck orders" && title(.folderJob(UUID())) == "Job")
        #expect(title(.matter("m-1")) == "On your note")
        #expect(JobsWindowController.width == 650)
        for route: JobsNavigation.Route in [.jobs, .folderJob(own.id), .matter("m-1")] {
            #expect(JobsWindowController.preferredHeight(for: route) == 680)
        }
        #expect(JobsWindowView.symbol(.jobs) == "checklist" && JobsWindowView.symbol(.folderJob(own.id)) == "folder"
                && JobsWindowView.symbol(.matter("m")) == "note.text")

        // Each screen shows its view.
        fixture.navigation.route = .folderJob(own.id)
        #expect(find(FolderJobPage.self, in: fixture.window().body)?.id == own.id)
        fixture.navigation.route = .matter("m-1")
        #expect(find(MatterPage.self, in: fixture.window().body)?.id == "m-1")
        fixture.navigation.route = .jobs
        #expect(find(JobsPage.self, in: fixture.window().body) != nil)

        // Back: a job's page and a matter's page go to Jobs, and Jobs stays.
        for route: JobsNavigation.Route in [.folderJob(own.id), .matter("m-1"), .jobs] {
            fixture.navigation.route = route
            fixture.navigation.back()
            #expect(fixture.navigation.route == .jobs, "Back from \(route)")
        }

        // A screen opened from somewhere else comes back there; any other way off the screen forgets that.
        fixture.navigation.open(.matter("m-1"), returningTo: .jobs)
        #expect(fixture.navigation.returning == JobsNavigation.Return(from: .matter("m-1"), to: .jobs))
        fixture.navigation.back()
        #expect(fixture.navigation.route == .jobs && fixture.navigation.returning == nil)
        fixture.navigation.open(.matter("m-2"), returningTo: .folderJob(own.id))
        fixture.navigation.route = .jobs
        #expect(fixture.navigation.returning == nil)
    }

    // MARK: ways in

    @Test func theMenuBarTheChatTabAStickerAndANotificationOpenTheWindowOnTheRightScreen() throws {
        let fixture = try JobsFixture()
        defer { fixture.remove() }
        let own = try fixture.job("stuck-orders", #"{"name": "Stuck orders"}"#)
        #expect(AppDelegate.jobsMenuTitle == "Jobs…")
        var opens = 0
        let window = JobsWindowController(folderJobs: fixture.panel, hideFromScreenShare: true)
        defer { window.close() }
        window.onOpen = { opens += 1 }
        window.setHiddenForForegroundGrant(true)   // nothing comes on screen in a test
        window.showJobs()
        #expect(window.route == .jobs && opens == 1)
        window.showFolderJob(id: own.id)
        #expect(window.route == .folderJob(own.id) && opens == 1)   // open already: the team's tools aren't checked again
        window.showMatter(id: "m-1")
        #expect(window.route == .matter("m-1"))
        window.navigation.back()
        #expect(window.route == .jobs)

        let chat = ChatFixture()
        defer { chat.remove() }
        var opened = 0
        chat.assistant.onOpenJobs = { opened += 1 }
        #expect(Assistant.openJobsTab == "Open Jobs")
        chat.assistant.askSuggestion(Assistant.openJobsTab)
        #expect(opened == 1 && chat.assistant.transcript.isEmpty)   // never sent as a question
    }
}

/// Jobs kept as folders in a temp folder, with the Jobs window's view over them. A job's run only says it ran; no
/// model is reached.
@MainActor
private final class JobsFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-page-\(UUID())")
    let jobs: FolderJobStore
    let jobRunner: FolderJobRunner
    let matters = Matters(directory: nil)
    let navigation = JobsNavigation()
    var own: URL { root.appendingPathComponent("jobs") }
    var team: URL { root.appendingPathComponent("linked/jobs") }

    init() throws {
        let team = root.appendingPathComponent("linked/jobs")
        jobs = FolderJobStore(directory: root.appendingPathComponent("jobs"), results: root.appendingPathComponent("job-results"),
                              teamDirectory: { team })
        jobRunner = FolderJobRunner(store: jobs, execute: { _ in "Ran in the test." })
    }

    var panel: FolderJobsPanel {
        var panel = FolderJobsPanel(store: jobs, runner: jobRunner)
        panel.matters = matters
        return panel
    }
    var actions: JobActions { JobActions(folderJobs: panel) }

    func input(now: Date = Date()) -> Jobs.Input { Jobs.Input(now: now, folderJobs: panel) }

    func window() -> JobsWindowView {
        JobsWindowView(navigation: navigation, folderJobs: panel, close: {})
    }

    /// A job's folder, yours or your team's, as found at once.
    @discardableResult
    func job(_ path: String, _ json: String, team: Bool = false) throws -> FolderJob {
        let folder = (team ? self.team : own).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json.write(to: folder.appendingPathComponent("job.json"), atomically: true, encoding: .utf8)
        try "def run():\n    return None\n".write(to: folder.appendingPathComponent("job.py"), atomically: true, encoding: .utf8)
        jobs.refresh()
        return try #require(jobs.jobs.first { $0.path == path && $0.isTeam == team })
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// An assistant with no screen, no network and no desktop: enough for its tabs.
@MainActor
private final class ChatFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-chat-\(UUID().uuidString)")
    let assistant: Assistant

    init() {
        var config = Config()
        config.apiKey = "fixture-no-network"
        config.screenshotMode = "never"
        let registry = ToolRegistry(root: root, runner: ScriptRunner(config: config))
        let root = root
        let learning = WatchLearnSession(operations: .init(
            start: { _ in }, stop: { Recording(dir: root, events: [], meta: WatchMeta(startedAt: "test", clicks: 0)) }, abandon: {},
            summarize: { _, _, _ in throw ClaudeError(message: "Not recording") }, write: { _ in [] }, reload: {}
        ))
        assistant = Assistant(config: config, watcher: ContextWatcher(), registry: registry, shell: ShellState(), learning: learning)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// Finds a view composed inside a SwiftUI body, without GUI coordinates.
private func find<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    if let value = value as? T { return value }
    guard depth < 60 else { return nil }
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle != .class else { return nil }
    for child in mirror.children {
        if let result = find(type, in: child.value, depth: depth + 1) { return result }
    }
    return nil
}
