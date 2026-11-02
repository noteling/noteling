import Foundation

/// The packs and scene notes used to assemble one request. Each request gets a fresh selection from the registry.
struct PackContext {
    let selection: PackSelection
    let sceneNotes: [StickyNote]
    let missingRequirements: [(pack: ToolPack, keys: [String])]
    let promptSection: String

    var active: [ToolPack] { selection.active }
    var hooked: [ToolPack] { selection.hooked }
    var global: [ToolPack] { selection.global }
    var others: [ToolPack] { selection.others }
}

/// Builds the existing tool-pack context without owning a conversation, capture, or recording.
enum PackContextProvider {
    /// `includeNotes` lets a pen request place target notes separately. The headless path can omit setup notices
    /// with `includeMissingRequirements`; tests supply the lookup so no real credentials are inspected.
    @MainActor
    static func context(
        for scene: ScreenContext?,
        registry: ToolRegistry,
        docsLimit: Int,
        includeNotes: Bool = true,
        includeMissingRequirements: Bool = true,
        missingRequirements: (([ToolPack]) -> [(pack: ToolPack, keys: [String])])? = nil
    ) -> PackContext {
        let selection = registry.select(for: scene)
        let notes = registry.notes(for: scene)
        let missing: [(pack: ToolPack, keys: [String])]
        if includeMissingRequirements {
            let selected = selection.offered
            missing = missingRequirements?(selected) ?? registry.missingRequirements(for: selected)
        } else {
            missing = []
        }
        let prompt = promptSection(selection, scene: scene, notes: includeNotes ? notes : [], missingRequirements: missing, docsLimit: docsLimit)
        return PackContext(selection: selection, sceneNotes: notes, missingRequirements: missing, promptSection: prompt)
    }

    /// Formatting uses the supplied values only; availability checks and scene selection happen above.
    static func promptSection(
        _ selection: PackSelection,
        scene: ScreenContext?,
        notes: [StickyNote],
        missingRequirements: [(pack: ToolPack, keys: [String])],
        docsLimit: Int
    ) -> String {
        var section = Prompt.toolPacks(selection, scene: scene, stuffLimit: docsLimit)
        section += Prompt.notes(onTarget: [], elsewhere: notes)
        if !missingRequirements.isEmpty {
            section += "\n## Not configured yet\n"
            for missing in missingRequirements {
                section += "- \(missing.pack.name) needs \(missing.keys.joined(separator: ", ")). Its scripts will fail until the user adds it in Noteling Settings (right-click the bubble → Settings…).\n"
            }
        }
        return section
    }
}
