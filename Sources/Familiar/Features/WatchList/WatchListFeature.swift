import Foundation

/// The watch list, put together once by the app: where watches are kept, what checks them on schedule, how alerts
/// reach the person, and the chat's tools. Its pages are in Morning Files (`WatchesPage`, `WatchJobPage`).
@MainActor
final class WatchListFeature {
    let store: WatchListStore
    let runner: WatchListRunner
    let notifier: WatchListNotifier
    let conversation: WatchListConversation
    let checker: WatchListChecker
    /// The ways into the watch pages, which the app points at Morning Files: Watches, one watch's page, and the
    /// chat's explanation of an item.
    var showWatches: () -> Void = {}
    var showWatch: (UUID) -> Void = { _ in }
    var explain: (UUID, String) -> Void = { _, _ in }

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
    }

    /// What Morning Files needs to show the watches. Why? on an item asks the chat.
    var panel: WatchListPanel {
        WatchListPanel(store: store, runner: runner, notifier: notifier, why: { [weak self] watchID, key in self?.explain(watchID, key) })
    }

    /// The menu bar's Watches… and the chat's Open Watches tab.
    func openWatches() { showWatches() }

    /// A clicked notification: the chat explains an item that is still red or grey; anything else, such as an item
    /// back to as expected or a notification about several items, opens its watch's page.
    func openNotification(watchID: UUID, key: String) {
        if store.watch(id: watchID)?.item(key)?.needsExplaining == true { explain(watchID, key) } else { open(watchID) }
    }

    /// A watch's page, or Watches once the watch is gone.
    func open(_ id: UUID) {
        if store.watch(id: id) != nil { showWatch(id) } else { showWatches() }
    }

    /// Starts the schedule. With watches kept from before, macOS is asked again for notifications, which only prompts
    /// someone who never answered. The items' cards are brought in line with what the watches show now.
    func start() {
        if !store.watches.isEmpty { notifier.requestPermission() }
        if runner.cards?.reconcile(store.watches) == true { runner.onCardsChanged?() }
        runner.start()
    }

    /// The watch an inbox card is about, when it is a watch's card (`<source>/job`).
    func watch(forCard key: String) -> WatchListWatch? {
        store.watches.first { WatchListCards.key(for: $0) == key }
    }

    /// The card view's folder name for a watch's cards: the watch's name.
    func cardFolderName(_ source: String) -> String? {
        store.watches.first { WatchListCards.source(for: $0) == source }?.name
    }

    func stop() {
        runner.stop()
    }

    /// Which check a watch uses, as an explanation names it: its own check.py, or the pack's script.
    func checkLabel(_ watch: WatchListWatch) -> String {
        store.ownCheck(for: watch.id) == nil ? watch.check : "its own check.py (in its folder)"
    }
}
