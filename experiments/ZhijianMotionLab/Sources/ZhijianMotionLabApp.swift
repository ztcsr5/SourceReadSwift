import SwiftUI

@main struct ZhijianMotionLabApp: App {
    @StateObject private var library = LabLibrary()
    @StateObject private var artwork = LabArtwork()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--lab-ui-testing") {
            UserDefaults.standard.set(false, forKey: "lab.hasSeenIntro")
            UserDefaults.standard.set(false, forKey: "lab.minimizesMotion")
        }
    }
    var body: some Scene {
        WindowGroup {
            LabRootView().environmentObject(library).environmentObject(artwork)
                .task { await artwork.prepare() }
        }
    }
}

struct LabRootView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lab.hasSeenIntro") private var hasSeenIntro = false
    @State private var showsIntro = false
    @State private var introStep = 0
    @State private var tab = 0
    @State private var heroIndex = 0
    @State private var route: [LabBook] = []
    @State private var readerBook: LabBook?
    @State private var isTourStarted = false
    @Namespace private var tabNamespace

    private var animates: Bool { !reducedMotion && !library.minimizesMotion }
    private var isTour: Bool { ProcessInfo.processInfo.arguments.contains("--lab-tour") }

    var body: some View {
        ZStack {
            if showsIntro || !hasSeenIntro {
                LabIntroView(step: $introStep, onFinish: finishIntro)
                    .transition(.opacity.combined(with: .scale(scale: animates ? 1.06 : 1)))
                    .zIndex(3)
            } else {
                mainContent.transition(.opacity)
            }
        }
        .animation(animates ? .easeInOut(duration: 0.65) : nil, value: showsIntro || !hasSeenIntro)
        .fullScreenCover(item: $readerBook) { book in LabReaderView(book: book) }
        .task(id: scenePhase) {
            guard isTour, !isTourStarted, scenePhase == .active else { return }
            isTourStarted = true
            route = []; tab = 0; heroIndex = 0; introStep = 0; showsIntro = true
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                for step in 1..<5 {
                    withAnimation(animates ? LabPalette.navigation : nil) { introStep = step }
                    try await Task.sleep(nanoseconds: 2_700_000_000)
                }
                finishIntro()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { heroIndex = 1 }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { heroIndex = 0 }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                route.append(library.books[0])
                try await Task.sleep(nanoseconds: 2_000_000_000)
                route = []
            } catch { return }
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $route) {
            ZStack(alignment: .bottom) {
                Group {
                    if tab == 0 {
                        LabHomeView(selectedIndex: $heroIndex,
                                    onDetail: { route.append($0) }, onRead: { readerBook = $0 }, onReplay: replay)
                    } else if tab == 1 { LabCollectionView() }
                    else { LabSettingsView(onReplay: replay) }
                }
                dock.padding(.horizontal, 38).padding(.bottom, 8)
            }
            .background(tab == 0 ? LabPalette.midnight : LabPalette.paper)
            .navigationDestination(for: LabBook.self) { book in
                LabDetailView(book: book, onRead: { readerBook = book })
            }
            .toolbar(tab == 2 ? .visible : .hidden, for: .navigationBar)
        }.tint(tab == 0 ? .white : LabPalette.accent)
    }

    private var dock: some View {
        LabGlass(isDark: tab == 0) {
            HStack(spacing: 4) {
                dockButton(0, title: "故事", symbol: "square.stack")
                dockButton(1, title: "书笺", symbol: "bookmark")
                dockButton(2, title: "实验室", symbol: "slider.horizontal.3")
            }.padding(6)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .environment(\.colorScheme, tab == 0 ? .dark : .light)
    }

    private func dockButton(_ index: Int, title: String, symbol: String) -> some View {
        Button {
            guard tab != index else { return }
            withAnimation(animates ? LabPalette.feedback : nil) { tab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: tab == index ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(tab == 0 ? Color.white.opacity(tab == index ? 1 : 0.55) : LabPalette.ink.opacity(tab == index ? 1 : 0.5))
            .background {
                if tab == index {
                    Capsule().fill(tab == 0 ? Color.white.opacity(0.16) : LabPalette.accent.opacity(0.09))
                        .matchedGeometryEffect(id: "dock.selection", in: tabNamespace)
                }
            }
        }.buttonStyle(LabPressStyle()).accessibilityAddTraits(tab == index ? .isSelected : [])
            .accessibilityIdentifier("dock.\(index)")
    }

    private func replay() {
        route = []; introStep = 0
        withAnimation(animates ? LabPalette.navigation : nil) { showsIntro = true }
    }

    private func finishIntro() {
        hasSeenIntro = true
        withAnimation(animates ? .easeInOut(duration: 0.65) : nil) { showsIntro = false }
    }
}

