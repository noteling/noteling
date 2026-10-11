import Foundation
import Network
import Testing
@testable import Familiar

/// The guides' examples are what the app reads: the template repository's job runs through the app's job runner as
/// its README says, and every JSON example in the team guides is read by the part of the app it's for. A change to
/// either side that breaks them fails here, before the guides go stale.
@Suite @MainActor
struct DocsExamplesTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private static var template: URL { repository.appendingPathComponent("docs/team/template") }
    private static var pagesUp: URL { template.appendingPathComponent("jobs/examples/pages-up") }

    // MARK: the template's job

    @Test func theTemplatesJobPutsThePagesThatNeedALookInItsPreviewAndOnACard() async throws {
        let pages = try await LocalPages(["/fine": (200, "<title>Fine</title><p>Hello from Noteling</p>"),
                                          "/plain": (200, "<p>Something else entirely</p>"),
                                          "/down": (503, "Down for maintenance")])
        defer { pages.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("docs-examples-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("jobs/examples/pages-up")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("input"), withIntermediateDirectories: true)
        for name in ["job.json", "job.py"] {
            try FileManager.default.copyItem(at: Self.pagesUp.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        let base = "http://127.0.0.1:\(pages.port)"
        try "url,expect\n\(base)/fine,Hello from Noteling\n\(base)/plain,Hello from Noteling\n\(base)/down,Hello from Noteling\n"
            .write(to: folder.appendingPathComponent("input/pages.csv"), atomically: true, encoding: .utf8)

        let inbox = root.appendingPathComponent("cards/inbox")
        let scripts = ScriptRunner(config: Config())
        scripts.cardsRoot = inbox
        let feature = FolderJobsFeature(registry: ToolRegistry(root: root.appendingPathComponent("tools"), runner: scripts),
                                        notifier: JobNotifier(),
                                        store: FolderJobStore(directory: root.appendingPathComponent("jobs"),
                                                              results: root.appendingPathComponent("job-results")),
                                        inbox: inbox)
        let morning = MorningStore(directory: root.appendingPathComponent("morning"))
        let cards = CardInbox(store: morning, directory: inbox)
        cards.folderName = { feature.cardFolderName($0) }
        feature.runner.onCardsChanged = { cards.scan() }
        let job = try #require(feature.store.jobs.first)
        #expect(job.name == "Pages up" && job.everyMinutes == 60 && job.contributors == ["Your name"])

        feature.runner.run(job.id)
        await feature.runner.finish()

        let state = try #require(feature.store.job(id: job.id)?.state)
        #expect(state.error == nil && state.said == "2 of 3 pages need a look")
        let result = try #require(feature.store.result(for: job))
        #expect(result.files.map(\.path) == ["preview/problems.csv", "all.csv"])
        #expect(FolderJobPreview.read(result.shown[0]) == .table(rows: [
            ["page", "what's wrong"],
            ["\(base)/plain", "it doesn't show “Hello from Noteling”"],
            ["\(base)/down", "it answered 503"],
        ], total: 2))
        let all = try String(contentsOf: try #require(result.files.first { $0.path == "all.csv" }).url, encoding: .utf8)
        #expect(all.hasPrefix("page,status,what's wrong,checked at") && all.contains("\(base)/fine,200,,"))
        let card = try #require(morning.cards.first { $0.inbox?.key == FolderJobCards.key(for: job) })
        #expect(card.title.hasPrefix("Pages up · ") && card.summary == "2 of 3 pages need a look" && !card.isResolved)

        // The README's next step: delete the row that's wrong on purpose and run it again, and the card goes.
        try "url,expect\n\(base)/fine,Hello from Noteling\n".write(to: folder.appendingPathComponent("input/pages.csv"),
                                                                  atomically: true, encoding: .utf8)
        feature.runner.run(job.id)
        await feature.runner.finish()
        #expect(feature.store.job(id: job.id)?.state.said == "The page is fine")
        #expect(feature.store.result(for: job)?.hasPreview == false)
        #expect(morning.cards.first { $0.inbox?.key == FolderJobCards.key(for: job) }?.isResolved == true)
    }

    @Test func theTemplatesPackIsAPackWithItsToolsAndBrief() throws {
        let skill = try String(contentsOf: Self.template.appendingPathComponent("example-pages/SKILL.md"), encoding: .utf8)
        let (front, body) = ToolRegistry.parseFrontmatter(skill)
        #expect(front["name"] as? String == "Example pages" && front["brief"] as? String == "brief" && !body.isEmpty)
        #expect((front["match"] as? [String: Any])?["urls"] as? [String] == ["example.com", "example.org"])
        let scripts = try FileManager.default.contentsOfDirectory(atPath: Self.template.appendingPathComponent("example-pages/scripts").path)
        #expect(Set(scripts.filter { $0.hasSuffix(".py") }) == ["brief.py", "page_status.py", "_fetch.py"])
        #expect(try String(contentsOf: Self.template.appendingPathComponent(".gitignore"), encoding: .utf8).contains("*.notelingsetup"))
    }

    // MARK: the guides' JSON

    /// Every JSON example in the team guides is read by what it's for: a job.json, a card file, a setup file, a team's
    /// noteling.json or a brief's glance.
    @Test func everyJSONExampleInTheTeamGuidesIsReadAsItSays() throws {
        let guides = Self.repository.appendingPathComponent("docs/team")
        var checked: [String: Int] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: guides.path).sorted() where name.hasSuffix(".md") {
            let text = try String(contentsOf: guides.appendingPathComponent(name), encoding: .utf8)
            for (index, block) in Self.blocks("json", in: text).enumerated() {
                let place = "\(name), JSON example \(index + 1)"
                let data = Data(block.utf8)
                let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], "\(place) isn't one object")
                let keys = Set(object.keys)
                if keys.contains("noteling_setup") {
                    let setup = try NotelingSetup.parse(data)
                    #expect(setup.unused.isEmpty, "\(place): \(setup.unused)")
                    checked["setup", default: 0] += 1
                } else if keys.contains("claude") {
                    let team = try TeamSettings.parse(data)
                    #expect(team.ignored.isEmpty && team.claude.baseURL != nil, "\(place)")
                    checked["noteling.json", default: 0] += 1
                } else if keys.contains("glance") {
                    #expect(PageGlance.parse(block) != nil, "\(place)")
                    checked["glance", default: 0] += 1
                } else if keys.contains("title") {
                    let card = try CardInboxFormat.parse(data, source: "docs", id: "example", modifiedAt: Date())
                    #expect(!card.title.isEmpty && card.actions.count == (object["actions"] as? [Any])?.count ?? 0, "\(place)")
                    checked["card", default: 0] += 1
                } else {
                    #expect(keys.isSubset(of: FolderJobFiles.known), "\(place) has keys a job.json doesn't: \(keys.subtracting(FolderJobFiles.known))")
                    _ = try FolderJobFiles.parse(data, path: "docs/example", source: .team)
                    checked["job.json", default: 0] += 1
                }
            }
        }
        #expect(checked["job.json", default: 0] >= 4 && checked["card", default: 0] >= 1 && checked["setup", default: 0] >= 1
                && checked["noteling.json", default: 0] >= 1 && checked["glance", default: 0] >= 1, "\(checked)")
        // And the template's own.
        _ = try FolderJobFiles.parse(Data(contentsOf: Self.pagesUp.appendingPathComponent("job.json")), path: "examples/pages-up", source: .team)
    }

    /// The fenced blocks of one language in a Markdown text.
    static func blocks(_ language: String, in text: String) -> [String] {
        var blocks: [String] = []
        var current: [String]?
        for line in text.components(separatedBy: "\n") {
            if current == nil, line.trimmingCharacters(in: .whitespaces) == "```" + language { current = []; continue }
            if current != nil, line.trimmingCharacters(in: .whitespaces) == "```" { blocks.append(current!.joined(separator: "\n")); current = nil; continue }
            current?.append(line)
        }
        return blocks
    }
}

/// A web server on this Mac for one test: each path answers with its status and its text, and anything else with 404.
final class LocalPages: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener

    init(_ pages: [String: (Int, String)]) async throws {
        let queue = DispatchQueue(label: "local-pages")
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let (status, text) = pages[path] ?? (404, "Not found")
                let body = Data(text.utf8)
                let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not OK")\r\nContent-Type: text/html; charset=utf-8\r\n"
                    + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        port = try await withCheckedThrowingContinuation { (done: CheckedContinuation<UInt16, Error>) in
            var answered = false
            listener.stateUpdateHandler = { state in
                guard !answered else { return }
                switch state {
                case .ready: answered = true; done.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): answered = true; done.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
    }

    func stop() { listener.cancel() }
}
