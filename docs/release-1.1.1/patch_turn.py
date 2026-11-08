from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(n,f):
 p=R/n;s=p.read_text(encoding='utf-8');p.write_text(f(s),encoding='utf-8')
def once(s,a,b):
 assert s.count(a)==1,(a[:80],s.count(a));return s.replace(a,b,1)
def reader(s):
 s=once(s,'    @State private var pagedPageIndex = 0','    @State private var pagedPageIndex = 0\n    @State private var tapPageTurnRequest: ReaderPageTurnRequest?')
 s=s.replace('            currentPageIndex: $pagedPageIndex,','            currentPageIndex: $pagedPageIndex,\n            turnRequest: tapPageTurnRequest,')
 s=once(s,'            pageIdentity: currentBlock.map', '            turnRequest: tapPageTurnRequest,\n            pageIdentity: currentBlock.map')
 s=once(s,'            moveReaderTarget(to: currentReaderTarget - 1)','            requestAnimatedPageTurn(direction: -1)')
 s=once(s,'            moveReaderTarget(to: currentReaderTarget + 1)','            requestAnimatedPageTurn(direction: 1)')
 i=s.index('    private func requestPageStep(')
 s=s[:i]+'''    private func requestAnimatedPageTurn(direction: Int) {
        guard pendingWindowJump == nil, !interactionGate.isPageInteractionActive,
              pagedBlocks.indices.contains(pagedPageIndex + direction) else { return }
        tapPageTurnRequest = ReaderPageTurnRequest(direction: direction)
    }

'''+s[i:]
 return s
edit('SourceReadSwift/Features/Reader/ReaderView.swift',reader)
def cover(s):
 s=once(s,'    var pageIdentity: String','    var turnRequest: ReaderPageTurnRequest? = nil\n    var pageIdentity: String')
 s=once(s,'        )\n    }\n\n    static func dismantle','        )\n        controller.requestTurn(turnRequest)\n    }\n\n    static func dismantle')
 i=s.index('    func beginInteraction()')
 s=s[:i]+'''    private var consumedTurnRequest: UUID?

    func requestTurn(_ request: ReaderPageTurnRequest?) {
        guard let request, consumedTurnRequest != request.id else { return }
        consumedTurnRequest = request.id
        let identity = window?.identity
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.identity == identity,
                  !self.isDragging, self.animator == nil,
                  self.awaitingIdentityChangeFrom == nil,
                  let window = self.window,
                  request.direction > 0 ? window.hasNext : window.hasPrevious else { return }
            self.beginInteraction()
            // The pan policy projects velocity into a complete turn. Starting
            // at zero retains the swipe's cover/slide displacement and shadows.
            let velocity = -CGFloat(request.direction) * max(self.view.bounds.width, 1) * 10
            self.endInteraction(velocity: velocity, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

'''+s[i:];return s
edit('SourceReadSwift/Features/Reader/CoverPageReaderView.swift',cover)
def curl(s):
 s=once(s,'    @Binding var currentPageIndex: Int','    @Binding var currentPageIndex: Int\n    let turnRequest: ReaderPageTurnRequest?')
 s=once(s,'        currentPageIndex: Binding<Int>,','        currentPageIndex: Binding<Int>,\n        turnRequest: ReaderPageTurnRequest? = nil,')
 s=once(s,'        self._currentPageIndex = currentPageIndex','        self._currentPageIndex = currentPageIndex\n        self.turnRequest = turnRequest')
 s=once(s,'        context.coordinator.sync(uiViewController, contentRevision: contentRevision)','        context.coordinator.sync(uiViewController, contentRevision: contentRevision)\n        context.coordinator.requestTurn(turnRequest, on: uiViewController)')
 i=s.index('        func reportVisibleIdentity(')
 s=s[:i]+'''        private var consumedTurnRequest: UUID?

        func requestTurn(_ request: ReaderPageTurnRequest?, on pvc: UIPageViewController) {
            guard let request, consumedTurnRequest != request.id else { return }
            consumedTurnRequest = request.id
            DispatchQueue.main.async { [weak self, weak pvc] in
                guard let self, let pvc, !self.isUserInteracting,
                      let host = pvc.viewControllers?.first as? PageHostingController<Content>,
                      let current = self.currentIndex(for: host) else { return }
                let target = current + request.direction
                guard self.parent.pages.indices.contains(target) else { return }
                let revision = self.parent.contentRevision
                let controller = self.viewController(at: target)
                self.isUserInteracting = true
                self.parent.onInteractionChanged?(true)
                pvc.setViewControllers([controller], direction: request.direction > 0 ? .forward : .reverse,
                    animated: !UIAccessibility.isReduceMotionEnabled) { [weak self, weak pvc] completed in
                    guard let self, let pvc else { return }
                    self.isUserInteracting = false
                    if completed, self.parent.contentRevision == revision,
                       pvc.viewControllers?.first === controller {
                        self.parent.currentPageIndex = target
                        self.lastDesiredIndex = target
                        self.parent.onPageChanged?(target)
                        self.reportVisibleIdentity(controller)
                    }
                    self.parent.onInteractionChanged?(false)
                    self.sync(pvc, contentRevision: self.parent.contentRevision)
                }
            }
        }

'''+s[i:];return s
edit('SourceReadSwift/Features/Reader/PageCurlReaderView.swift',curl)
print('tap animation transaction patched')
