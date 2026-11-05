import Foundation
import Testing
import FamiliarRuntime
@testable import Familiar

/// The four reading tools: list, read, search and rows over Noteling's roots, nothing outside them, secrets hidden.
@Suite struct RecallTests {
    /// Noteling's folder as recall sees it, in a temp folder: two days of memory log, a matter, an own job with what
    /// its run left, a pack of one's own, the team's tools, and things that must stay out of reach.
    struct Fixture {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("recall-\(UUID())")
        let tools: URL
        let team: URL
        let recall: Recall

        static let token = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"

        init() throws {
            tools = home.appendingPathComponent("tools")
            team = home.appendingPathComponent("linked")
            let files: [(String, String)] = [
                ("memory/2026-11-01.jsonl", #"{"at":"2026-11-01T09:02:11-05:00","ran":"team/sales/stuck-orders","read":2113,"found":3}"# + "\n"
                    + #"{"at":"2026-11-01T09:02:12-05:00","finding":"team/sales/stuck-orders/4417","verdict":"show","why":"Acme's, past the SLA."}"# + "\n"),
                ("memory/2026-11-02.jsonl", #"{"at":"2026-11-02T09:02:11-05:00","matter":"m-1","put_away":true,"said":"with \#(Self.token)"}"# + "\n"),
                ("matters/m-1/matter.json", #"{"id":"m-1","state":"open"}"#),
                ("matters/m-1/notes.md", "## Acme order 4417\n- stuck 3 days\n- the warehouse was nudged\n"),
                ("jobs/pages/job.md", "Each row is a page that didn't say what it should.\n"),
                ("jobs/pages/input/pages.csv", "url,expects\nhttps://example.com/,Example\n"),
                ("job-results/own/pages/output/findings.csv",
                 "order_id,customer,waiting_days,card_number,note\n4417,Acme Ltd,3,4111111111111111,fine\n4390,Beta-TEST,5,,\"has a, comma\"\n4402,Cora,1,,token sk-abcdefghijklmnopqrstuvwxyz\n"),
                ("memos/n-1a2b3c4d.md", "---\ncolour: yellow\n---\n# Marco\nCall Marco about the lease.\n"),
                ("tools/shop/docs/mine.md", "Mine: returns take a week.\n"),
                ("tools/shop/.hidden.md", "Hidden.\n"),
                ("linked/crm/docs/guide.md", "Approvals take two days.\nAsk Lena about the rest.\n"),
                ("outside.md", "Never read.\n"),
            ]
            for (path, text) in files {
                let url = home.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            // A link that leads out of a root is as unreadable as what it points at.
            try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("jobs/pages/link.md"), withDestinationURL: home.appendingPathComponent("outside.md"))
            let team = self.team
            recall = Recall.standard(home: home, tools: tools, team: { team })
        }

        func run(_ name: String, _ input: [String: Any] = [:], with recall: Recall? = nil) -> (text: String, isError: Bool) {
            let result = (recall ?? self.recall).execute(name, input)
            return (result.content as? String ?? "", result.isError)
        }

        func remove() { try? FileManager.default.removeItem(at: home) }
    }

    @Test func theRootsAreNamedAndNothingOutsideOrHiddenIsRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let roots = fixture.run("list").text
        #expect(roots.hasPrefix("memory/  Noteling's log, one file a day") && roots.contains("\nteam/  The team's tools as linked from GitHub"))
        #expect(roots.hasSuffix("A path starts with one of these names.") && !roots.contains("nothing there yet"))
        #expect(fixture.recall.roots().map(\.name) == ["memory", "matters", "notes", "jobs", "results", "tools", "team"])
        #expect(MemoryLog.folder == "memory" && Matters.folder == "matters" && MemoStore.folder == "memos")   // the roots are where Noteling writes

        for path in ["../outside.md", "memory/../outside.md", "/etc/hosts", "~/outside.md", "jobs/pages/link.md", "tools/../outside.md"] {
            #expect(fixture.run("read", ["path": path]) == ("That path isn't under a root Noteling can read. Roots: memory, matters, notes, jobs, results, tools, team.", true), "\(path)")
        }
        #expect(fixture.run("read", ["path": "tools/shop/.hidden.md"]) == ("Hidden files aren't read.", true))
        #expect(fixture.run("read", ["path": "nowhere/x.md"]).text.hasPrefix("No root called nowhere. Roots: memory, matters, notes, jobs, results, tools, team."))
        #expect(fixture.run("read", ["path": ""]) == ("Say a path, starting with a root: memory, matters, notes, jobs, results, tools, team.", true))
        #expect(fixture.run("read", ["path": "matters/m-9/notes.md"]) == ("There is no matters/m-9/notes.md.", true))
        // A pack's docs as the prompt lists them, with no root in front: yours first, then the team's.
        #expect(fixture.run("read", ["path": "shop/docs/mine.md"]) == ("Mine: returns take a week.", false))
        #expect(fixture.run("read", ["path": "crm/docs/guide.md"]) == ("Approvals take two days.\nAsk Lena about the rest.", false))
        #expect(fixture.run("read", ["path": "team/crm/docs/guide.md"]).text == fixture.run("read", ["path": "crm/docs/guide.md"]).text)
        #expect(fixture.run("lookup", [:]) == ("Unknown tool lookup", true))
    }

    @Test func listShowsFilesWithSizeAndDateFoldersFirstAndGlobsAtAnyDepth() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lines = fixture.run("list", ["path": "jobs/pages"]).text.components(separatedBy: "\n")
        #expect(lines.count == 2 && lines[0] == "jobs/pages/input/" && lines[1].hasPrefix("jobs/pages/job.md  51 B  "))
        #expect(lines[1].range(of: #"\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil)   // the link out isn't listed
        #expect(fixture.run("list", ["pattern": "findings.csv"]).text.hasPrefix("results/own/pages/output/findings.csv  "))
        #expect(fixture.run("list", ["path": "results", "pattern": "*.CSV"]).text.hasPrefix("results/own/pages/output/findings.csv  "))
        #expect(fixture.run("list", ["path": "tools", "pattern": "*.md"]).text.hasPrefix("tools/shop/docs/mine.md  "))   // hidden ones never
        #expect(fixture.run("list", ["path": "memory/2026-11-01.jsonl"]) == ("memory/2026-11-01.jsonl is a file; read it.", true))
        #expect(fixture.run("list", ["path": "matters/m-9"]) == ("There is no matters/m-9.", true))
        #expect(fixture.run("list", ["path": "tools", "pattern": "*.py"]) == ("No file named like *.py under tools.", false))
        var small = fixture.recall
        small.limits.entries = 1
        #expect(fixture.run("list", ["path": "jobs/pages"], with: small).text == "jobs/pages/input/\n…and 1 more")
    }

    @Test func readGivesLinesFromAPointWithATablesColumnsFirstAndHidesSecrets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.run("read", ["path": "memory/2026-11-01.jsonl"]).text
        #expect(log == #"{"at":"2026-11-01T09:02:11-05:00","found":3,"ran":"team/sales/stuck-orders","read":2113}"# + "\n"
                + #"{"at":"2026-11-01T09:02:12-05:00","finding":"team/sales/stuck-orders/4417","verdict":"show","why":"Acme's, past the SLA."}"#)
        #expect(fixture.run("read", ["path": "memory/2026-11-02.jsonl"]).text.contains(#""said":"(hidden)""#))
        let findings = "results/own/pages/output/findings.csv"
        #expect(fixture.run("read", ["path": findings, "from": 3, "lines": 1]).text
                == "order_id,customer,waiting_days,card_number,note\n4390,Beta-TEST,5,(hidden),\"has a, comma\"\n(lines 3–3 of 4)")
        #expect(fixture.run("read", ["path": findings, "from": "4"]).text == "order_id,customer,waiting_days,card_number,note\n4402,Cora,1,(hidden),token (hidden)\n(lines 4–4 of 4)")
        #expect(fixture.run("read", ["path": findings]).text.hasPrefix("order_id,customer,waiting_days,card_number,note\n4417,Acme Ltd,3,(hidden),fine\n"))
        #expect(fixture.run("read", ["path": findings, "from": 9]) == ("results/own/pages/output/findings.csv has 4 line(s); there is no line 9.", true))
        #expect(fixture.run("read", ["path": "matters/m-1"]) == ("matters/m-1 is a folder; list it.", true))
        var small = fixture.recall
        small.limits.characters = 30
        #expect(fixture.run("read", ["path": "matters/m-1/notes.md"], with: small).text == "## Acme order 4417\n- stuck 3 d\n…(cut at 30 characters; read fewer lines at a time)")
        #expect(PageWalk.hidingSecrets("key sk-abcdefghijklmnopqrstuvwxyz and card 4111 1111 1111 1111 ok") == "key (hidden) and card (hidden) ok")
    }

    @Test func searchFindsLinesAcrossRootsWithContextAndCapsHits() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let acme = fixture.run("search", ["pattern": "acme"]).text.components(separatedBy: "\n")
        // In the roots' order: the log first, then the matters, then what the jobs found.
        #expect(acme == [#"memory/2026-11-01.jsonl:2: {"at":"2026-11-01T09:02:12-05:00","finding":"team/sales/stuck-orders/4417","verdict":"show","why":"Acme's, past the SLA."}"#,
                         "matters/m-1/notes.md:1: ## Acme order 4417",
                         "results/own/pages/output/findings.csv:2: 4417,Acme Ltd,3,(hidden),fine"])
        #expect(fixture.run("search", ["pattern": "nudged", "path": "matters", "context": 1]).text == "matters/m-1/notes.md-2- - stuck 3 days\nmatters/m-1/notes.md:3: - the warehouse was nudged")
        #expect(fixture.run("search", ["pattern": "take", "path": "team"]).text == "team/crm/docs/guide.md:1: Approvals take two days.")
        #expect(fixture.run("search", ["pattern": "take", "path": "team/crm/docs/guide.md"]).text == "team/crm/docs/guide.md:1: Approvals take two days.")
        #expect(fixture.run("search", ["pattern": "sk-abc"]).text == "results/own/pages/output/findings.csv:4: 4402,Cora,1,(hidden),token (hidden)")
        #expect(fixture.run("search", ["pattern": "Hidden|Never read"]) == ("No matches.", false))
        #expect(fixture.run("search", ["pattern": "("]) == ("That isn't a regular expression that can be read.", true))
        #expect(fixture.run("search", ["pattern": "x", "path": "../outside.md"]).isError && fixture.run("search", ["pattern": "x", "path": "jobs/nowhere"]).isError)
        var small = fixture.recall
        small.limits.hits = 1
        let capped = fixture.run("search", ["pattern": "a"], with: small).text.components(separatedBy: "\n")
        #expect(capped.count == 2 && capped.last == "…(more matches left out: narrow the pattern or the folder)")
    }

    @Test func rowsFiltersSortsProjectsAndCountsATable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let findings = "results/own/pages/output/findings.csv"
        #expect(fixture.run("rows", ["path": findings, "where": ["customer": "acme"]]).text
                == "order_id,customer,waiting_days,card_number,note\n4417,Acme Ltd,3,(hidden),fine\n(1 of 1 matching rows; 3 in the file)")
        #expect(fixture.run("rows", ["path": findings, "where": ["waiting_days": ">=3"], "sort": "-waiting_days", "columns": ["order_id", "waiting_days"]]).text
                == "order_id,waiting_days\n4390,5\n4417,3\n(2 of 2 matching rows; 3 in the file)")
        #expect(fixture.run("rows", ["path": findings, "where": ["customer": "!=cora", "waiting_days": 3], "columns": ["customer"]]).text
                == "customer\nAcme Ltd\n(1 of 1 matching rows; 3 in the file)")
        #expect(fixture.run("rows", ["path": findings, "where": ["customer": "=Cora"], "count": true]) == ("1 of 3 rows match.", false))
        #expect(fixture.run("rows", ["path": findings, "count": true]) == ("3 rows.", false))
        #expect(fixture.run("rows", ["path": findings, "sort": "customer", "limit": 1, "columns": ["order_id"]]).text == "order_id\n4417\n(1 of 3 matching rows; 3 in the file)")
        #expect(fixture.run("rows", ["path": findings, "where": ["size": "big"]]) == ("No column size. Columns: order_id, customer, waiting_days, card_number, note.", true))
        #expect(fixture.run("rows", ["path": "memory/2026-11-01.jsonl", "where": ["verdict": "=show"], "columns": ["finding", "why"]]).text
                == #"{"finding":"team/sales/stuck-orders/4417","why":"Acme's, past the SLA."}"# + "\n(1 of 1 matching rows; 2 in the file)")
        #expect(fixture.run("rows", ["path": "memory/2026-11-01.jsonl", "where": ["read": ">2000"], "count": true]) == ("1 of 2 rows match.", false))
        #expect(fixture.run("rows", ["path": "matters/m-1/notes.md"]) == ("rows reads a csv, tsv or jsonl file; matters/m-1/notes.md is a .md file. Use read.", true))
    }

    @Test func theToolsAreRoutesAChatCanUse() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let router = try ToolRouter(routes: fixture.recall.routes())
        #expect(Set(router.definitions.compactMap { $0["name"] as? String }) == Recall.names)
        #expect(router.definitions.allSatisfy { ($0["input_schema"] as? [String: Any])?["additionalProperties"] as? Bool == false })
        let read = await router.execute("read", ["path": "tools/shop/docs/mine.md"])
        #expect(read.content as? String == "Mine: returns take a week." && !read.isError)
        #expect(await router.execute("rows", ["path": "jobs/pages/input/pages.csv", "count": true]).content as? String == "1 rows.")
    }
}
