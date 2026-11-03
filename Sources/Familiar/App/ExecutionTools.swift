import Foundation
import FamiliarContracts
import FamiliarRuntime

/// Assembles the tools available to one request. GUI and headless callers share
/// the same dispatch; native implementations stay on the app side of the boundary.
@MainActor
enum ExecutionTools {
    /// `facts` is what the page's brief found (its result's `facts`, compact JSON): every pack script on this turn gets
    /// it as `NOTELING_FACTS`, so a tool for the page in front can default to the thing on it.
    static func make(registry: ToolRegistry, context: ScreenContext?,
                     control: ComputerController?, background: Bool,
                     packScripts: Bool = true, facts: String? = nil, additionalRoutes: [ToolRoute] = [],
                     recall: Recall? = nil,
                     lookAtScreen: @escaping () async -> ToolResult,
                     readScreen: (() async -> ToolResult)? = nil) throws -> ToolRouter {
        var routes: [ToolRoute] = []
        let selection = registry.select(for: context)
        let runner = registry.runner
        let env = facts.map { ["NOTELING_FACTS": $0] } ?? [:]
        // The packs for this page, the ones they use here, and the ones for anywhere: a library nobody uses here and a
        // pack for other pages stay out. `packScripts: false` when the pack's brief already answered for them, so the
        // turn needs no round trips.
        for pack in packScripts ? selection.offered : [] {
            let scope = selection.scope(of: pack)
            for script in pack.scripts {
                let requirements = pack.requires
                routes.append(ToolRoute(match: .tool(name: script.id), definition: script.definition(scope: scope)) { _, input, _ in
                    do { return .text(try await runner.run(script, args: input, context: context, secrets: requirements, env: env)) }
                    catch { return .text(error.localizedDescription, isError: true) }
                })
            }
        }

        for definition in BuiltinTools.definitions(background: background && control != nil) {
            guard let name = definition["name"] as? String else { continue }
            routes.append(ToolRoute(match: .tool(name: name), definition: definition) { _, input, _ in
                if background, let control {
                    if name == "look_at_screen" { return await control.lookAtTargetScreen() }
                    if name == "read_screen" { return control.readTargetScreen() }
                }
                if name == "look_at_screen" { return await lookAtScreen() }
                if name == "read_screen" {
                    if let readScreen { return await readScreen() }
                    return await ScreenText.readFrontmost()
                }
                return BuiltinTools.execute(name, input)
            })
        }
        // The four reading tools: the packs' docs, the memory log, the matters, the jobs and what they found.
        if let recall { routes += recall.routes() }

        if let control {
            routes.append(ToolRoute(match: .tool(name: "find_on_screen"), definition: ComputerController.findDefinition) { _, input, _ in
                control.find(input["query"] as? String ?? "")
            })
            routes.append(ToolRoute(match: .toolset("computer"), definition: ComputerController.toolsetDefinition) { name, input, _ in
                await control.perform(name, input)
            })
            if background {
                for definition in ComputerController.backgroundDefinitions {
                    guard let name = definition["name"] as? String else { continue }
                    routes.append(ToolRoute(match: .tool(name: name), definition: definition) { _, input, _ in
                        switch name {
                        case "target_window": return await control.targetWindow(input)
                        case "click_element": return await control.clickElement(input)
                        case "send_message": return await control.sendMessage(input)
                        case "ask_for_the_mouse": return await control.askForMouse(input)
                        case "give_the_mouse_back": return control.giveMouseBack()
                        default: return .text("Unknown tool \(name)", isError: true)
                        }
                    })
                }
            }
        }
        return try ToolRouter(routes: routes + additionalRoutes)
    }
}
