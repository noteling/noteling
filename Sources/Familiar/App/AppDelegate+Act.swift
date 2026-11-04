import AppKit

/// Act: Teach me and Do it for me, in front of the person or in the background. Mouse and keyboard control and what the
/// bubble does while Noteling has them, the background tasks and their panel, Watch Me's recordings and Teach me's tours.
extension AppDelegate {
    /// Control's settings and what happens around a grant, the task panel, Watch Me and Teach me in the chat.
    func setupAct() {
        assistant.onOpenWatchDraft = { [weak self] title, markdown in
            guard let self else { return }
            self.watchDraftWindow.show(title: title, markdown: markdown, hideFromScreenShare: self.config.hideFromScreenShare)
        }
        assistant.onSetControlLane = { [weak self] allow, background in
            guard let self else { return }
            self.config.allowControl = allow
            self.config.controlInBackground = background
            self.config.save()
            self.assistant.reconfigure(self.effectiveConfig)
            Log.info("control lane: allow=\(allow) background=\(background)")
        }
        control.maxLongEdge = config.maxImageLongEdge
        control.hideFromScreenShare = config.hideFromScreenShare
        control.preciseClicks = config.backgroundDirectClicks
        control.asksFirst = config.backgroundAsksFirst
        control.onCaption = { [weak self] c in
            guard let self else { return }
            guard self.control.lane != .background else { return }
            self.assistant.status = c
        }
        // Desktop tasks have their own surface; starting or finishing one never opens chat.
        control.onBackgroundTaskBegin = { [weak self] in
            self?.desktop.executor.backgroundDidBegin()
        }
        control.onBegin = { [weak self] in
            guard let self else { return }
            self.origami.cancel()
            if self.control.lane == .background {
                self.desktop.executor.nativeDidBegin()
                return
            }
            self.jobsWindow?.setHiddenForForegroundGrant(true)
            self.bubbleWasVisibleBeforeControl = self.panel.isVisible
            self.shell.expanded = false
            self.panel.orderOut(nil)          // keep our own windows out of the way of clicks
            self.stickersPanel?.hiddenForControl = true
            self.placeRunStickers()
        }
        control.onEnd = { [weak self] in
            guard let self else { return }
            self.jobsWindow?.setHiddenForForegroundGrant(false)
            if self.control.lane == .background {
                self.taskPanel.setHiddenForForegroundGrant(false)
                return
            }
            if self.bubbleWasVisibleBeforeControl { self.panel.orderFrontRegardless() }
            self.shell.expanded = true
            self.stickersPanel?.hiddenForControl = false
            self.placeRunStickers()
        }
        control.onGrant = { [weak self] entering in
            guard let self else { return }
            self.taskPanel.setHiddenForForegroundGrant(entering)
            self.jobsWindow?.setHiddenForForegroundGrant(entering)
            if entering {
                self.bubbleWasVisibleBeforeControl = self.panel.isVisible
                self.panel.orderOut(nil)
            } else {
                if self.bubbleWasVisibleBeforeControl { self.panel.orderFrontRegardless() }
            }
            self.stickersPanel?.hiddenForControl = entering
            self.placeRunStickers()
        }
        // While Watch Me records, the pen points at what the last click meant: from the caption, the pad or the menu.
        recorder.onFixRequest = { [weak self] in self?.fixWatchStep() }
        assistant.onFixWatchStep = { [weak self] in self?.fixWatchStep() }
        learning.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, phase != .recording, self.wand.isPointing else { return }
                self.wand.cancel()   // the recording ended under the pen: nothing left to fix
            }
            .store(in: &cancellables)
        taskPanel = BackgroundTaskPanelController(store: desktop.tasks, hideFromScreenShare: config.hideFromScreenShare)
        let showMe = ShowMeConversation(registry: registry)
        showMe.hideFromScreenShare = { [weak self] in self?.config.hideFromScreenShare ?? false }
        assistant.showMe = showMe
        // The way is done: the note, folded for the lesson, hops once to say the chat is there when wanted.
        assistant.onTourDone = { [weak self] in
            guard let self, self.panel.isVisible, !self.shell.expanded, !self.origami.isFlying else { return }
            self.hop()
        }
    }

    /// The pen, while Watch Me records: it points at what the last click meant, and that becomes the click's step. The
    /// highlight shows what will be kept, as a click there would keep it.
    func fixWatchStep() {
        guard assistant.watching, !wand.isActive, let step = recorder.captured.last else { return }
        origami.cancel()
        recorder.setHUDHidden(true)
        wand.point(caption: "Point at what you clicked for step \(step.number)  ·  Esc to leave it as it is",
                   resolve: { [weak self] p in self?.recorder.pointing(at: p) },
                   then: { [weak self] p in
                       self?.recorder.setHUDHidden(false)
                       if let p { self?.recorder.fixLastStep(at: p) }
                   })
    }

    @objc func menuStopWork() {
        if !desktop.executor.stopActive() { control.stop(reason: "menu") }
    }

    @objc func menuShowTasks() { desktop.tasks.show() }

    @objc func menuWatch() {
        if assistant.watching { stopWatchingAndShow() } else { assistant.startWatching() }
    }

    /// The pad comes back for the "what were you doing?" note even when the bubble was hidden in the menu bar.
    func stopWatchingAndShow() {
        assistant.stopWatching()
        if !panel.isVisible { showBubble() }
    }
}
