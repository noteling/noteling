import Foundation

/// The watch list, put together once by the app: where watches are kept, what checks them on schedule, how alerts
/// reach the person, the chat's tools and the window.
@MainActor
final class WatchListFeature {
    let store: WatchListStore
    let runner: WatchListRunner
    let notifier: WatchListNotifier
    let conversation: WatchListConversation
    let window: WatchListWindowController
    let checker: WatchListChecker

    init(registry: ToolRegistry, store: WatchListStore? = nil) {
        // Your team's watches are `watches/` in the linked tools, wherever the latest update put them.
        let store = store ?? WatchListStore(teamDirectory: { [weak registry] in
            registry?.linkedRoot.map { $0.appendingPathComponent(ToolRegistry.watchesFolder) }
        })
        let checker = WatchListChecker(registry: registry, folder: { [weak store] id in store?.folder(for: id) })
        let notifier = WatchListNotifier()
        let runner = WatchListRunner(store: store, prepare: { watch in await checker.plan(watch) })
        runner.onAlert = { [weak notifier] alert in notifier?.post(alert) }
        let cards = WatchListCards()
        cards.checkLabel = { [weak store] watch in store?.ownCheck(for: watch.id) == nil ? watch.check : "its own check.py" }
        runner.cards = cards
        let conversation = WatchListConversation(store: store, runner: runner)
        conversation.checks = { [weak registry] in registry.map(WatchListChecker.choices(in:)) ?? [] }
        conversation.takesList = { watch in (try? await checker.resolve(watch))?.takesList ?? false }
        conversation.askForNotifications = { [weak notifier] in notifier?.requestPermission() }
        conversation.notificationLine = { [weak notifier] in await notifier?.line() ?? "on" }
        self.store = store
        self.runner = runner
        self.notifier = notifier
        self.conversation = conversation
        self.checker = checker
        window = WatchListWindowController(store: store, runner: runner, notifier: notifier)
    }

    /// Starts the schedule. With watches kept from before, macOS is asked again for notifications, which only prompts
    /// someone who never answered. The items' cards are brought in line with what the watches show now.
    func start() {
        if !store.watches.isEmpty { notifier.requestPermission() }
        if runner.cards?.reconcile(store.watches) == true { runner.onCardsChanged?() }
        runner.start()
    }

    /// The watch and item an inbox card is about, when it is one of a watch's cards.
    func item(forCard key: String) -> (WatchListWatch, WatchListItem)? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        for watch in store.watches where WatchListCards.source(for: watch) == parts[0] {
            if let item = watch.items.first(where: { WatchListCards.fileName(for: $0.key) == parts[1] + ".json" }) { return (watch, item) }
        }
        return nil
    }

    /// The card view's folder name for a watch's cards: the watch's name.
    func cardFolderName(_ source: String) -> String? {
        store.watches.first { WatchListCards.source(for: $0) == source }?.name
    }

    func stop() {
        runner.stop()
        window.close()
    }

    /// Which check a watch uses, as an explanation names it: its own check.py, or the pack's script.
    func checkLabel(_ watch: WatchListWatch) -> String {
        store.ownCheck(for: watch.id) == nil ? watch.check : "its own check.py (in its folder)"
    }
}
