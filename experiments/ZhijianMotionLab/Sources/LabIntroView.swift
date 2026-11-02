import SwiftUI

struct LabIntroView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var step: Int
    let onFinish: () -> Void
    var sampledTime: Double? = nil
    var sampledPosition: Double? = nil
    @State private var position: Double = 0
    @State private var dragOrigin: Double?
    @State private var dragStep = 0
    @State private var sampleChapter = 0

    private var animates: Bool { !reducedMotion && !library.minimizesMotion && scenePhase == .active }
    private var renderedPosition: Double { sampledPosition ?? position }
    private let titles = ["想读的，正在来到眼前", "首页，由你定义", "一张书笺，收好心动", "读到哪里，记到哪里", "故事，不止一种格式", "每一次阅读，都有迹可循"]
    private let subtitles = ["从熟悉的书开始，找到下一本想读的。", "书架、书单和最近阅读，可以自由浏览。", "把喜欢的段落，留成属于你的藏书票。", "轻点翻一段，进度会真实变化。", "TXT、EPUB、PDF、有声与书源，在这里相遇。", "阅读时长、章节与足迹，都能好好珍藏。"]

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 650 || typeSize.isAccessibilitySize
            ZStack(alignment: .bottom) {
                background
                ReadingIntroStage(position: renderedPosition, isAnimated: animates, isDragging: dragOrigin != nil,
                                  chapter: sampleChapter, onNextChapter: { withAnimation(animates ? LabPalette.feedback : nil) { sampleChapter = (sampleChapter + 1) % 3 } }, sampledTime: sampledTime)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.77)
                    .offset(y: proxy.size.height * 0.05).frame(maxHeight: .infinity, alignment: .top)
                footer(compact: compact)
                    .padding(.horizontal, 20).padding(.bottom, max(proxy.safeAreaInsets.bottom, 24))
                VStack {
                    HStack {
                        Spacer()
                        Button("跳过", action: onFinish).font(.system(size: 12)).foregroundStyle(.black.opacity(0.5))
                            .frame(width: 44, height: 44).accessibilityIdentifier("intro.skip")
                    }
                    Spacer()
                }.padding(.top, max(proxy.safeAreaInsets.top, compact ? 36 : 60)).padding(.trailing, 12)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(pagingGesture(width: proxy.size.width))
        }
        .foregroundStyle(.black).ignoresSafeArea().preferredColorScheme(.light)
        .onAppear { position = Double(IntroChoreography.safeStep(step)) }
        .onChange(of: step) { proposed in
            guard dragOrigin == nil else { return }
            withAnimation(animates ? .spring(response: 0.42, dampingFraction: 0.87) : nil) { position = Double(IntroChoreography.safeStep(proposed)) }
        }
    }

    private func pagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { gesture in
                guard sampledPosition == nil, abs(gesture.translation.width) > abs(gesture.translation.height) * 1.15 else { return }
                if dragOrigin == nil { dragOrigin = position; dragStep = step }
                let next = IntroPaging.position(start: dragOrigin ?? position, translation: Double(gesture.translation.width), width: Double(width))
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { position = next }
            }
            .onEnded { gesture in
                guard dragOrigin != nil else { return }
                let target = IntroPaging.target(origin: dragStep, translation: Double(gesture.translation.width),
                                               predicted: Double(gesture.predictedEndTranslation.width), width: Double(width))
                dragOrigin = nil
                move(to: target)
            }
    }

    private func footer(compact: Bool) -> some View {
        VStack(spacing: compact ? 9 : 12) {
            ZStack {
                ForEach(0..<IntroPaging.count, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(titles[index]).font(typeSize.isAccessibilitySize ? .title3.bold() : .system(size: compact ? 18 : 20, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitles[index]).font(typeSize.isAccessibilitySize ? .subheadline : .system(size: compact ? 12 : 14, weight: .semibold))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(max(0, 1 - abs(renderedPosition - Double(index))))
                    .offset(x: CGFloat(Double(index) - renderedPosition) * 18)
                    .accessibilityHidden(step != index)
                }
            }.frame(minHeight: typeSize.isAccessibilitySize ? 122 : 62)
            HStack(spacing: 7) {
                ForEach(0..<IntroPaging.count, id: \.self) { index in
                    Capsule().fill(.black.opacity(index == step ? 1 : 0.28))
                        .frame(width: index == step ? 30 : 6, height: 6)
                }
            }.frame(minHeight: 28).accessibilityElement(children: .ignore)
                .accessibilityLabel("引导第 \(step + 1) 步，共 6 步")
                .accessibilityValue(titles[step])
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(to: step + 1)
                    case .decrement: move(to: step - 1)
                    @unknown default: break
                    }
                }
            HStack(spacing: 12) {
                Button { move(to: step - 1) } label: {
                    Image(systemName: "arrow.left").font(.body.weight(.medium)).frame(width: 49, height: 49)
                        .background(.white.opacity(0.75), in: Circle())
                }.disabled(step == 0).opacity(step == 0 ? 0.35 : 1)
                    .accessibilityLabel("上一页").accessibilityHint(step == 0 ? "已在第一步" : "返回上一幕")
                    .accessibilityIdentifier("intro.previous")
                Button {
                    if step == IntroPaging.count - 1 { onFinish() } else { move(to: step + 1) }
                } label: {
                    Text(step == IntroPaging.count - 1 ? "开始阅读" : "继续").font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 49).foregroundStyle(.white)
                        .background(LabPalette.accent, in: Capsule())
                }.accessibilityIdentifier("intro.continue")
            }.buttonStyle(LabPressStyle())
            Text("左右滑动，自由回看 · 书籍交互测试")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.top, 32)
        .background {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: LabPalette.paper.opacity(0.97), location: 0.18), .init(color: LabPalette.paper, location: 1)], startPoint: .top, endPoint: .bottom)
                .padding(.horizontal, -20).padding(.top, -16).padding(.bottom, -60)
        }
    }

    private var background: some View {
        ZStack {
            LabPalette.paper
            RadialGradient(colors: [.pink.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 600)
            RadialGradient(colors: [.purple.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 650)
        }
    }

    private func move(to proposed: Int) {
        let target = IntroChoreography.safeStep(proposed)
        withAnimation(animates ? .spring(response: 0.42, dampingFraction: 0.87) : nil) {
            step = target; position = Double(target)
        }
    }
}
