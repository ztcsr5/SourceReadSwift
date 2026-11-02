import SwiftUI

struct LabIntroView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var step: Int
    let onFinish: () -> Void
    var sampledTime: Double? = nil
    @State private var droppedCount = 0
    @State private var isReady = false
    @State private var progress: CGFloat = 0

    private var animates: Bool { !reducedMotion && !library.minimizesMotion && scenePhase == .active }
    private let titles = ["想看的，正在来到眼前", "首页，由你定义", "一张票，收好想看的", "更新时间，一眼掌握", "连接你的所有资源", "每一次观看，都有迹可循"]
    private let subtitles = ["从熟悉的作品开始，找到下一部想看的。", "所有首页模块都能自由组合，也可以直接滑动浏览。", "在详情页加入待看，想看的作品随时都能回来。", "剧集进度和播出日期，会集中落进你的日历。", "统一浏览 Emby、网盘和本地媒体库。", "观看时长、类型偏好和趋势会持续汇总。"]

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 650 || typeSize.isAccessibilitySize
            ZStack(alignment: .bottom) {
                background
                ZStack {
                    ReferencePosterField(step: step, isAnimated: animates && step < 2, sampledTime: sampledTime)
                        .opacity(step < 2 ? 1 : 0)
                    if step == 2 { tickets.transition(.opacity) }
                    if step == 3 { ReferenceProgressCard().frame(height: proxy.size.width * 0.31).padding(.horizontal, 15).transition(.scale(scale: 0.87).combined(with: .opacity)) }
                    if step == 4 { ReferenceOrbit(isAnimated: animates, sampledTime: sampledTime).transition(.opacity.combined(with: .scale(scale: 0.8))) }
                    if step == 5 { ReferenceStatistics(isAnimated: animates, sampledTime: sampledTime).transition(.opacity) }
                }
                .frame(width: proxy.size.width, height: proxy.size.height * 0.77)
                .offset(y: proxy.size.height * 0.05)
                .frame(maxHeight: .infinity, alignment: .top).clipped()

                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: LabPalette.paper.opacity(0.96), location: 0.26), .init(color: LabPalette.paper, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: compact ? 207 : 234).allowsHitTesting(false)
                VStack(spacing: compact ? 11 : 14) {
                    VStack(spacing: 8) {
                        Text(titles[IntroChoreography.safeStep(step)])
                            .font(.system(size: compact ? 18 : 20, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitles[IntroChoreography.safeStep(step)])
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 10)
                    HStack(spacing: 7) {
                        ForEach(0..<IntroChoreography.stepCount, id: \.self) { index in
                            if step == index {
                                Capsule().fill(.black.opacity(0.20)).frame(width: 34, height: 6)
                                    .overlay(alignment: .leading) { Capsule().fill(.black).frame(width: 12 + progress * 22, height: 6) }
                            } else { Circle().fill(.black.opacity(index < step ? 0.55 : 0.30)).frame(width: 6, height: 6) }
                        }
                    }.padding(.top, 4).accessibilityLabel("引导第 \(step + 1) 步，共 6 步")
                    Button(action: advance) {
                        Text(step == 5 ? "开始使用" : "继续").font(.system(size: 17, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 49)
                            .foregroundStyle(isReady ? .white : .gray.opacity(0.5))
                            .background(isReady ? LabPalette.accent : .gray.opacity(0.13), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 0.8))
                    }.buttonStyle(LabPressStyle()).disabled(!isReady).accessibilityIdentifier("intro.continue")
                    Text(step == 5 ? "引导统计为示例，不是你的观看记录" : "影片信息来源 TheMovieDB · 私人视频对照测试")
                        .font(.system(size: 7)).foregroundStyle(.gray.opacity(0.65))
                }
                .padding(.horizontal, 20).padding(.bottom, max(proxy.safeAreaInsets.bottom, 24))
                VStack {
                    HStack { Spacer(); Button("跳过", action: onFinish).font(.system(size: 12)).foregroundStyle(.black.opacity(0.45)).frame(width: 44, height: 44).accessibilityIdentifier("intro.skip") }
                    Spacer()
                }.padding(.top, max(proxy.safeAreaInsets.top, compact ? 36 : 60)).padding(.trailing, 12)
            }
        }
        .foregroundStyle(.black).ignoresSafeArea().preferredColorScheme(.light)
        .animation(animates ? .spring(response: 0.65, dampingFraction: 0.9) : nil, value: step)
        .task(id: "\(step)-\(animates)") {
            isReady = sampledTime != nil || !animates
            progress = isReady ? 1 : 0
            droppedCount = sampledTime != nil || !animates ? 3 : 0
            guard animates, sampledTime == nil else { return }
            withAnimation(.linear(duration: 1.8)) { progress = 1 }
            do {
                if step == 2 {
                    for count in 1...3 {
                        try await Task.sleep(nanoseconds: count == 1 ? 180_000_000 : 350_000_000)
                        withAnimation(.spring(response: 0.56, dampingFraction: 0.77)) { droppedCount = count }
                    }
                    try await Task.sleep(nanoseconds: 920_000_000)
                } else { try await Task.sleep(nanoseconds: 1_800_000_000) }
                guard !Task.isCancelled else { return }
                isReady = true
            } catch { return }
        }
    }

    private var background: some View {
        ZStack {
            LabPalette.paper
            RadialGradient(colors: [(step < 2 ? Color.pink : Color.gray).opacity(step < 2 ? 0.15 : 0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 600)
            RadialGradient(colors: [(step < 2 ? Color.purple : Color.teal).opacity(0.13), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 650)
        }
    }

    private var tickets: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    ReferenceTicket(item: ReferenceMedia.item([82728, 71712, 87739][index]))
                        .frame(width: proxy.size.width * 0.89, height: proxy.size.width * 0.34)
                        .rotationEffect(.degrees(index == 0 ? 0 : (index == 1 ? -4 : 3)))
                        .offset(x: index == 2 ? 12 : 0, y: droppedCount > index ? CGFloat(index) * proxy.size.width * 0.29 - CGFloat(max(droppedCount - 1, 0)) * proxy.size.width * 0.145 : -proxy.size.height)
                        .opacity(droppedCount > index ? 1 : 0).zIndex(Double(3 - index))
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.accessibilityElement(children: .ignore).accessibilityLabel("三张电影票从上方依次落下叠放")
    }

    private func advance() {
        if step >= IntroChoreography.stepCount - 1 { onFinish() }
        else { step = IntroChoreography.safeStep(step + 1) }
    }
}
