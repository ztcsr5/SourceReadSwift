import SwiftUI

@main struct ZhijianMotionLabApp: App {
    @StateObject private var library = LabLibrary()
    @StateObject private var artwork = LabArtwork()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--lab-ui-testing") {
            UserDefaults.standard.set(false, forKey: "lab.readingIntroSeen.v3")
            UserDefaults.standard.set(false, forKey: "lab.minimizesMotion")
            UserDefaults.standard.removeObject(forKey: "lab.snapshot")
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
    @EnvironmentObject private var artwork: LabArtwork
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @AppStorage("lab.readingIntroSeen.v3") private var hasSeenIntro = false
    @State private var showsIntro = false
    @State private var introStep = 0
    @State private var tab = 0
    @State private var heroIndex = 0
    @State private var route: [LabBook] = []
    @State private var readerBook: LabBook?
    @State private var showsSearch = false
    @Namespace private var tabNamespace
    private var animates: Bool { !reducedMotion && !library.minimizesMotion }

    var body: some View {
        ZStack {
            if !artwork.isReady { launchStage.transition(.opacity) }
            else if showsIntro || !hasSeenIntro {
                LabIntroView(step: $introStep, onFinish: finishIntro).transition(.opacity).zIndex(3)
            } else { mainContent.transition(.opacity) }
        }
        .animation(animates ? .easeInOut(duration: 0.45) : nil, value: showsIntro || !hasSeenIntro)
        .animation(animates ? .easeInOut(duration: 0.45) : nil, value: artwork.isReady)
        .sheet(isPresented: $showsSearch) { ReadingSearchView(onDetail: { route.append($0) }) }
        .fullScreenCover(item: $readerBook) { LabReaderView(book: $0) }
    }

    private var launchStage: some View {
        GeometryReader { proxy in
            ZStack {
                LabPalette.paper
                RadialGradient(colors: [.pink.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 600)
                RadialGradient(colors: [.purple.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 650)
                LabMark().foregroundStyle(.black).scaleEffect(1.05)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.4273)
                Text("正在准备书封").font(.caption2).foregroundStyle(.secondary)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.84)
            }
        }.ignoresSafeArea().preferredColorScheme(.light).accessibilityIdentifier("intro.loading")
    }

    private var mainContent: some View {
        NavigationStack(path: $route) {
            ZStack(alignment: .bottom) {
                Group {
                    if tab == 0 { ReadingHomeView(selectedIndex: $heroIndex, onDetail: { route.append($0) }, onRead: { readerBook = $0 }) }
                    else if tab == 1 { LabCollectionView() }
                    else { LabSettingsView(onReplay: replay) }
                }
                dock.padding(.horizontal, 20).padding(.bottom, 7)
            }
            .background(LabPalette.paper)
            .navigationDestination(for: LabBook.self) { book in ReadingDetailView(book: book, onRead: { readerBook = book }) }
            .toolbar(tab == 2 ? .visible : .hidden, for: .navigationBar)
        }.tint(.primary).preferredColorScheme(tab == 0 && route.isEmpty ? .dark : .light)
    }

    private var dock: some View {
        HStack(spacing: 10) {
            LabGlass {
                HStack(spacing: 0) {
                    dockButton(0, title: "书架", symbol: "books.vertical.fill")
                    dockButton(1, title: "书笺", symbol: "bookmark.fill")
                    dockButton(2, title: "设置", symbol: "gearshape.fill")
                }.padding(5)
            }
            Button { showsSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 27, weight: .medium))
                    .frame(width: 58, height: 58).background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 0.8))
            }.accessibilityLabel("搜索书籍").accessibilityIdentifier("home.search")
        }.foregroundStyle(.black).environment(\.colorScheme, .light).shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }

    private func dockButton(_ index: Int, title: String, symbol: String) -> some View {
        Button {
            guard tab != index else { return }
            withAnimation(animates ? LabPalette.feedback : nil) { tab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .background {
                    if tab == index { Capsule().fill(.black.opacity(0.07)).matchedGeometryEffect(id: "dock.selection", in: tabNamespace) }
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
        withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { showsIntro = false }
    }
}
