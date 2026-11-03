import Foundation
import Testing
@testable import Familiar

/// Noteling is three products and a shared harness, in four folders of `Sources/Familiar`: `Ask` (the pen and the
/// chat), `Act` (Teach me and Do it for me, in front of the person or in the background), `Attend` (the jobs, what they
/// find, and the stickers) and `Shared` (what they all run on). Each product owns its data and its UI; the others reach
/// it only through a door: a type in Shared, or one of the few named here. `App` is the composition root and may name
/// anything. This test reads the sources and fails when a file under one folder names a type declared under another,
/// unless that type is a door or the crossing is on the debt list, which only shrinks: a debt that is paid off fails
/// too, so the list stays true.
@Suite struct ProductBoundariesTests {
    static let folders = ["Ask", "Act", "Attend", "Shared"]

    /// Types another product may name: the doors. All of them are Act's "do this": `TaskExecutor` and what a task is
    /// made of, `DesktopExecutionService`, what came of a task (`BackgroundTaskOutcome`), and Teach me's entry and
    /// progress (`ShowMeConversation`, `TourProgress`). Chat uses them for its three verbs; the reading jobs and the
    /// card queue use them to run.
    static let doors: Set<String> = [
        "TaskExecutor", "TaskRequest", "TaskPlan", "TaskExecution", "DesktopExecutionService", "BackgroundTaskOutcome",
        "ShowMeConversation", "TourProgress",
    ]

    /// Crossings that exist today: the file, relative to `Sources/Familiar`, and the foreign types it names. Each line is
    /// a debt; pay one off and take its line out. What pays them off, by group:
    /// - `ToolRegistry` and `ScriptTool` are the harness as much as the packs: the team repository's layout, the runner
    ///   and a script as a tool move to `Shared/Harness`, and `ToolRegistry` keeps the packs and the page leads.
    /// - `NoteAnchor` names an element on a page: it belongs in `Shared/Screen`, beside `PageKey`.
    /// - `WatchRecorder.looksSecret` and `CaptureSpace` are screen-reading rules living in Act; they move to `Shared/Screen`.
    /// - `Intent` and `IntentWords` are read from `noteling.json` and the config: the words move to `Shared/Configuration`.
    /// - `Prompt.watchSystem` goes to WatchLearn; `ShowPath` loading leaves the registry; `PackWriter` leaves WatchLearn.
    /// - Chat's hold on `WatchLearnSession`, `PackDraft`, `PeekFeed` and `ComputerController` becomes part of the Act door.
    /// - Everything that names Morning, the card queue, the cards inbox or the reading jobs' screens goes with the
    ///   minister (`docs/plans/attention-minister.md`), and `SettingsWindow` takes rows instead of `FolderJob` and `ToolPack`.
    static let debt: [String: Set<String>] = [
        "Act/Control/Background/ActionVerifier.swift": ["NoteAnchor"],
        "Act/Control/Background/IrreversibleGuard.swift": ["NoteAnchor"],
        "Act/ShowMe/ShowFinder.swift": ["NoteAnchor"],
        "Act/ShowMe/ShowMeConversation.swift": ["IntentWords", "ToolRegistry"],
        "Act/ShowMe/ShowPath.swift": ["NoteAnchor"],
        "Act/Tasks/BackgroundTaskPanel.swift": ["MorningStore", "MorningWorkItem"],
        "Act/Tasks/BackgroundTaskStore.swift": ["MorningWorkItem"],
        "Act/Tasks/DesktopExecutionService.swift": ["Prompt", "ReadingNavigationPolicy", "ToolRegistry", "TrackedSourceItem"],
        "Act/WatchLearn/WatchLearnComposition.swift": ["ToolRegistry"],
        "Act/WatchLearn/WatchRecorder.swift": ["NoteAnchor"],
        "Act/WatchLearn/WatchSummarizer.swift": ["Prompt"],
        "Ask/Chat/Assistant.swift": ["CardConversation", "ComputerController", "FolderJobConversation", "MorningCard", "PackDraft",
                                     "PeekFeed", "SourceConversation", "WatchLearnSession"],
        "Ask/Packs/ToolRegistry.swift": ["ShowPath", "ShowPathStore"],
        "Ask/Pen/Notes.swift": ["PackWriter"],
        "Attend/FolderJobs/FolderJobRunner.swift": ["ScriptTool", "ToolRegistry"],
        "Attend/FolderJobs/FolderJobStore.swift": ["ToolRegistry"],
        "Attend/Morning/JobsRender.swift": ["ComputerController", "NativeActivityGate", "ToolRegistry"],
        "Attend/Morning/LatestRunRender.swift": ["ComputerController", "NativeActivityGate", "ToolRegistry"],
        "Attend/Morning/MorningFilesView.swift": ["TaskResultText"],
        "Attend/Morning/MorningRender.swift": ["BackgroundTaskPanelView", "BackgroundTaskStore", "PeekFeed"],
        "Attend/Morning/MorningTaskRunner.swift": ["NativeActivityGate", "ToolRegistry"],
        "Attend/Reading/CalendarCollectionRunner.swift": ["NativeActivityGate", "ToolRegistry"],
        "Attend/Reading/ReadingNavigationPolicy.swift": ["IrreversibleGuard"],
        "Attend/Reading/ScriptReadWindow.swift": ["ScriptTool"],
        "Attend/Reading/SourceCollectionTask.swift": ["ToolRegistry"],
        "Shared/Configuration/Config.swift": ["IntentWords"],
        "Shared/Configuration/NotelingSetup.swift": ["FolderJobFiles", "ToolRegistry"],
        "Shared/Configuration/TeamSettings.swift": ["Intent", "IntentWords"],
        "Shared/Harness/BuiltinTools.swift": ["ToolRegistry", "WatchRecorder"],
        "Shared/Harness/LinkedTools.swift": ["ToolRegistry"],
        "Shared/Harness/ScriptRunner.swift": ["CardInboxFormat", "ScriptTool"],
        "Shared/Harness/SecretScripts.swift": ["ScriptTool", "ToolRegistry"],
        "Shared/Screen/PageReader.swift": ["WatchRecorder"],
        "Shared/Screen/ScreenCapture.swift": ["CaptureSpace"],
        "Shared/Settings/SettingsWindow.swift": ["FolderJob", "ToolPack"],
    ]

    @Test func productsNameEachOtherOnlyThroughTheDoors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Familiar")
        var sources: [String: (folder: String, text: String)] = [:]   // relative path → its product and text
        for folder in Self.folders {
            let base = root.appendingPathComponent(folder)
            guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk where url.pathExtension == "swift" {
                let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
                sources[relative] = (folder, try String(contentsOf: url, encoding: .utf8))
            }
        }
        #expect(sources.count > 100, "the sources weren't found under \(root.path)")

        // Every type declared at the top level of a file, by the product that declares it. A private type can't be named
        // from another file, so it isn't a crossing whatever its name.
        let declaration = try NSRegularExpression(
            pattern: #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(public|internal|private|fileprivate)\s+)?(?:final\s+|indirect\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z]\w*)"#,
            options: .anchorsMatchLines)
        var owner: [String: String] = [:]   // type → product
        for (_, source) in sources {
            let text = source.text as NSString
            for match in declaration.matches(in: source.text, range: NSRange(location: 0, length: text.length)) {
                if match.range(at: 1).location != NSNotFound, ["private", "fileprivate"].contains(text.substring(with: match.range(at: 1))) { continue }
                owner[text.substring(with: match.range(at: 2))] = source.folder
            }
        }

        // A product may name anything in Shared, that is what Shared is for; Shared may name nothing of a product's. A
        // name a file declares itself, nested in one of its own types, is its own whatever another product calls one.
        let nested = try NSRegularExpression(pattern: #"^\s+(?:\w+\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z]\w*)"#, options: .anchorsMatchLines)
        var crossings: [String: Set<String>] = [:]
        for (path, source) in sources {
            let text = source.text as NSString
            let own = Set(nested.matches(in: source.text, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) })
            let foreign = owner.filter { type, product in
                product != source.folder && product != "Shared" && !Self.doors.contains(type) && !own.contains(type)
            }.map(\.key)
            guard !foreign.isEmpty else { continue }
            let code = Self.withoutCommentsAndStrings(source.text)
            let names = try NSRegularExpression(pattern: #"(?<![\w.])(?:"# + foreign.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")\b"#)
            let found = Set(names.matches(in: code, range: NSRange(location: 0, length: (code as NSString).length)).map { (code as NSString).substring(with: $0.range) })
            if !found.isEmpty { crossings[path] = found }
        }

        var problems: [String] = []
        for (path, types) in crossings.sorted(by: { $0.key < $1.key }) {
            let owed = Self.debt[path] ?? []
            let new = types.subtracting(owed)
            if !new.isEmpty {
                problems.append("\(path) names \(new.sorted().map { "\($0) (\(owner[$0]!))" }.joined(separator: ", ")): a product reaching into another; go through a door, or add it to the debt")
            }
        }
        for (path, owed) in Self.debt.sorted(by: { $0.key < $1.key }) {
            let paid = owed.subtracting(crossings[path] ?? [])
            if !paid.isEmpty { problems.append("\(path) no longer names \(paid.sorted().joined(separator: ", ")): take it off the debt list") }
        }
        #expect(problems.isEmpty, Comment(rawValue: "\n" + problems.joined(separator: "\n")))
    }

    /// The code alone: no comments, no string literals, so a name in a doc comment or a message isn't a crossing.
    static func withoutCommentsAndStrings(_ text: String) -> String {
        let quote = "\"", three = quote + quote + quote
        var code = text.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: " ", options: .regularExpression)
        code = code.replacingOccurrences(of: "//[^\\n]*", with: "", options: .regularExpression)
        code = code.replacingOccurrences(of: "#*" + three + "[\\s\\S]*?" + three + "#*", with: quote + quote, options: .regularExpression)
        code = code.replacingOccurrences(of: "#+" + quote + "(?:[^" + quote + "\\\\\\n]|\\\\.)*" + quote + "#+", with: quote + quote, options: .regularExpression)
        code = code.replacingOccurrences(of: quote + "(?:[^" + quote + "\\\\\\n]|\\\\.)*" + quote, with: quote + quote, options: .regularExpression)
        return code
    }
}
