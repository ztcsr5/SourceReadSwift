import SwiftUI

@main struct ZhijianMotionLabApp: App {
    @StateObject private var library = LabLibrary()
    @StateObject private var artwork = LabArtwork()
    @StateObject private var shelf = ReferenceShelf()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--lab-ui-testing") {
            UserDefaults.standard.set(false, forKey: "lab.hasSeenIntro")
            UserDefaults.standard.set(false, forKey: "lab.minimizesMotion")
            UserDefaults.standard.removeObject(forKey: "lab.reference.saved")
        }
    }
    var body: some Scene {
        WindowGroup {
            LabRootView().environmentObject(library).environmentObject(artwork).environmentObject(shelf)
                .task { await artwork.prepare() }
        }
    }
}

struct LabRootView: View {
    @EnvironmentObject private var library: LabLibrary
    @EnvironmentObject private var shelf: ReferenceShelf
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lab.hasSeenIntro") private var hasSeenIntro = false
    @State private var showsIntro = false
    @State private var introStep = 0
    @State private var tab = 0
    @State private var heroIndex = 0
    @State private var route: [ReferenceMedia] = []
    @State private var showsSearch = false
    @State private var isTourStarted = false
    @Namespace private var tabNamespace

    private var animates: Bool { !reducedMotion && !library.minimizesMotion }
    private var isTour: Bool { ProcessInfo.processInfo.arguments.contains("--lab-tour") }

    var body: some View {
        ZStack {
            if showsIntro || !hasSeenIntro {
                LabIntroView(step: $introStep, onFinish: finishIntro).transition(.opacity).zIndex(3)
            } else { mainContent.transition(.opacity) }
        }
        .animation(animates ? .easeInOut(duration: 0.65) : nil, value: showsIntro || !hasSeenIntro)
        .sheet(isPresented: $showsSearch) { ReferenceSearchView(onDetail: { route.append($0) }) }
        .task(id: scenePhase) {
            guard isTour, !isTourStarted, scenePhase == .active else { return }
            isTourStarted = true
            route = []; tab = 0; heroIndex = 0; introStep = 0; showsIntro = true
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                for step in 1..<IntroChoreography.stepCount {
                    withAnimation(animates ? LabPalette.navigation : nil) { introStep = step }
                    try await Task.sleep(nanoseconds: 2_700_000_000)
                }
                finishIntro()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { heroIndex = 1 }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(animates ? .easeInOut(duration: 0.45) : nil) { heroIndex = 0 }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                route.append(ReferenceMedia.samples[0])
                try await Task.sleep(nanoseconds: 2_000_000_000)
                route = []
            } catch { return }
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $route) {
            ZStack(alignment: .bottom) {
                Group {
                    if tab == 0 { ReferenceHomeView(selectedIndex: $heroIndex, onDetail: { route.append($0) }) }
                    else if tab == 1 { ReferenceShelfView(onDetail: { route.append($0) }) }
                    else if tab == 2 { resources }
                    else { settings }
                }
                dock.padding(.horizontal, 16).padding(.bottom, 7)
            }
            .background(LabPalette.paper)
            .navigationDestination(for: ReferenceMedia.self) { ReferenceDetailView(item: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }.tint(.primary).preferredColorScheme(tab == 0 && route.isEmpty ? .dark : .light)
    }

    private var dock: some View {
        HStack(spacing: 10) {
            LabGlass {
                HStack(spacing: 0) {
                    dockButton(0, title: "发现", symbol: "play.tv.fill")
                    dockButton(1, title: "我的", symbol: "person.crop.circle.fill")
                    dockButton(2, title: "资源库", symbol: "externaldrive.fill")
                    dockButton(3, title: "设置", symbol: "gearshape.fill")
                }.padding(5)
            }
            Button { showsSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 27, weight: .medium))
                    .frame(width: 58, height: 58).background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 0.8))
            }.accessibilityLabel("搜索片目").accessibilityIdentifier("home.search")
        }
        .foregroundStyle(.black).environment(\.colorScheme, .light)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }

    private func dockButton(_ index: Int, title: String, symbol: String) -> some View {
        Button {
            guard tab != index else { return }
            withAnimation(animates ? LabPalette.feedback : nil) { tab = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                Text(title).font(.system(size: 9, weight: .bold))
            }.frame(maxWidth: .infinity, minHeight: 48)
                .background {
                    if tab == index { Capsule().fill(.black.opacity(0.07)).matchedGeometryEffect(id: "dock.selection", in: tabNamespace) }
                }
        }.buttonStyle(LabPressStyle()).accessibilityAddTraits(tab == index ? .isSelected : [])
            .accessibilityIdentifier("dock.\(index)")
    }

    private var resources: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive").font(.system(size: 52))
            Text("尚未连接资源").font(.title2.bold())
            Text("这一版只测试视频中的界面与交互，不连接服务器、账号或媒体文件。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            Button("浏览离线样本") { tab = 0 }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 90)
    }

    private var settings: some View {
        Form {
            Section {
                Text("视频对照测试").font(.title2.bold())
                Text("按你提供的 REX 视频重建六段引导与海报主页。此 App 不是 REX 官方产品，也不是正式纸间。").font(.footnote).foregroundStyle(.secondary)
                Button("重播启动序章", action: replay)
            }
            Section("辅助功能") { Toggle("减少动态效果", isOn: $library.minimizesMotion) }
            Section("本地状态") { Text("已保存 \(shelf.saved.count) 部待看作品") }
            Section("测试边界") {
                Text("统计卡是引导演示；首页为离线片目，不代表实时榜单。未接入播放、付费、账号或真实媒体库。")
                Text("素材仅用于用户授权的私人视觉研究，不随正式纸间发布。影片信息来源 TheMovieDB；TMDB 未认证或背书此 App。")
            }.font(.footnote)
        }.padding(.bottom, 74)
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
