import SwiftUI
import Photos
import UIKit

struct SwipeViewerView: View {
    /// 从首页分类进入时非空；从分组、月份、照片墙进入时为空
    private let category: SmartCategory?
    /// 分组 / 月份直接给定的列表，进来不再自己遍历
    private let preset: [PHAsset]?
    private let titleOverride: String?
    /// 分组模式：底部多一个「保留这张，其余全待删」
    private let group: PhotoGroup?
    /// 从照片墙点进来时落到第几张
    private let initialIndex: Int
    private let startID: String?

    init(category: SmartCategory) {
        self.category = category
        self.preset = nil
        self.titleOverride = nil
        self.group = nil
        self.initialIndex = 0
        self.startID = nil
    }

    init(title: String,
         assets: [PHAsset],
         group: PhotoGroup? = nil,
         startAt: Int = 0,
         startID: String? = nil) {
        self.category = nil
        self.preset = assets
        self.titleOverride = title
        self.group = group
        self.initialIndex = max(startAt, 0)
        self.startID = startID
    }

    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    /// 进来时的完整有序列表。撤销待删、整组操作都以它为基准，
    /// 不能用 assets —— 那是已经剔掉队列里那些的版本。
    @State private var baseList: [PHAsset] = []
    @State private var loading = true
    /// 进度 UI 是否该露面。慢任务才显示，秒开的分类不显示，
    /// 否则进度条会「闪一下就没」
    @State private var showLoadingUI = false
    /// 是否展开四列缩略图总览
    @State private var showGrid = false
    @State private var index = 0

    /// 整个横向内容被拖走了多少点。scrollX = index * 页宽 时正好停在第 index 张。
    /// 手指移动多少，画面就跟多少，松手后再吸附到最近的整数页。
    @State private var scrollX: CGFloat = 0
    /// 当前卡片纵向位移（上滑待删 / 下滑喜欢）
    @State private var dragY: CGFloat = 0
    /// 手势开始时的 scrollX，用来做增量计算
    @State private var startX: CGFloat = 0
    @State private var axis: DragAxis?
    @State private var animating = false

    @State private var toast: String?
    @State private var showTrash = false
    @State private var video: VideoSelection?
    /// 打开垃圾桶那一刻的队列快照。
    /// 关闭时和当前队列对比，就知道哪几张被撤销、哪几张被真删了。
    @State private var pendingBeforeTrash: Set<String> = []

    /// 双指缩放。zoom 是松手后保留的倍率，pinch 是当前手势的临时倍率
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    /// 放大后的平移量
    @State private var panOffset: CGSize = .zero
    /// 本次拖动开始时的平移量
    @State private var startPan: CGSize = .zero
    /// 双指缩放正在进行（或刚结束）的时间点，用来避免捏合的同时翻页
    @State private var pinchGuardUntil: Double = 0

    /// 浏览区实际尺寸。预取要用和卡片完全一致的尺寸，
    /// 差十几个点就是另一个缓存 key，预取白做。
    @State private var stageSize: CGSize = .zero

    /// 当前这批里哪些已经是「喜欢」。
    /// 用它做本地判断，下滑就能变成可撤销的开关，而不是只能单向加。
    @State private var favoriteIDs: Set<String> = []

    /// 排序方式存在本地，下次进任何分类都沿用上次的选择
    @AppStorage("photoswipe.sortOption") private var sortRaw = SortOption.newest.rawValue

    private enum DragAxis { case horizontal, vertical, pan }

    private struct VideoSelection: Identifiable {
        let id = UUID()
        let asset: PHAsset
    }

    /// 一页的引用。位置看 index，身份看 id。
    ///
    /// 之前 ForEach 直接拿 index 当标识，数组删掉一张之后，
    /// 后面每张照片的 index 都往前挪了一位 —— SwiftUI 认为
    /// 「还是那几个视图，只是内容换了」，于是三张卡片同时重新请求图片。
    /// 这就是上滑删除、以及删完之后左右滑都会卡一下的原因。
    private struct PageRef: Identifiable {
        let index: Int
        let id: String
    }

    private var sort: SortOption {
        SortOption(rawValue: sortRaw) ?? .newest
    }

    private var titleText: String {
        if let titleOverride { return titleOverride }
        return category?.title ?? "照片"
    }

    private var isAllCategory: Bool { category == SmartCategory.all }
    private var isFavoritesCategory: Bool { category == SmartCategory.favorites }
    /// 分组、月份这些是固定顺序，不提供排序切换
    private var sortEnabled: Bool { category != nil }

    /// 当前这张是不是已经标了「喜欢」
    private func isFavorite(at i: Int) -> Bool {
        guard i >= 0, i < assets.count else { return false }
        return favoriteIDs.contains(assets[i].localIdentifier)
    }

    /// 实际生效的缩放倍率，双指还在动的时候就要跟手
    private var effectiveZoom: CGFloat {
        min(max(zoom * pinch, 1), 5)
    }

    private var isZoomed: Bool {
        effectiveZoom > 1.01
    }

    /// 平移限制在图片范围内，不会把照片拖出屏幕外面找不回来
    private func clampPan(_ p: CGSize, cardW: CGFloat, cardH: CGFloat) -> CGSize {
        let z = effectiveZoom
        let maxX = max(cardW * (z - 1) / 2, 0)
        let maxY = max(cardH * (z - 1) / 2, 0)
        return CGSize(width: min(max(p.width, -maxX), maxX),
                      height: min(max(p.height, -maxY), maxY))
    }

    private func resetZoom() {
        zoom = 1
        pinch = 1
        panOffset = .zero
        startPan = .zero
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            stage

            VStack {
                topBar
                Spacer()
            }

            VStack {
                Spacer()
                if !showGrid {
                    bottomBar
                }
            }

            toastLayer
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await loadList() }
        .onChange(of: sortRaw) { _, _ in
            guard sortEnabled else { return }
            Task { await reload() }
        }
        .onChange(of: index) { _, _ in
            // 换了一张，缩放和平移都归零
            zoom = 1
            pinch = 1
            panOffset = .zero
            startPan = .zero
        }
        .onChange(of: isZoomed) { _, zoomed in
            if zoomed {
                // 关键：一放大，正在进行的拖动立刻改判为「平移」。
                // 不改的话，手指先横拖（已经定成 horizontal）、
                // 再来第二根手指放大，松手时仍按翻页处理，正是会误翻下一张的那条路。
                axis = .pan
                startPan = panOffset
            } else {
                panOffset = .zero
                startPan = .zero
            }
        }
        .sheet(isPresented: $showTrash, onDismiss: {
            // 垃圾桶关掉之后对一次账：撤销的放回列表，真删的剔出去
            Task { await syncAfterTrash() }
        }) {
            TrashView()
        }
        .fullScreenCover(item: $video) { selection in
            VideoPlayerView(asset: selection.asset)
        }
        .onDisappear {
            library.stopPreheat()
        }
    }

    // MARK: - 主体

    private var stage: some View {
        GeometryReader { geo in
            let pageW = max(geo.size.width, 1)
            let cardW = max(geo.size.width - 26, 80)
            let cardH = max(geo.size.height, 80)

            ZStack {
                // 加载态延后 0.16 秒才显示：多数分类是秒开的，
                // 立刻显示进度条反而会「闪一下就没」，看着像出错
                if loading && showLoadingUI {
                    VStack(spacing: 14) {
                        if sort.needsSize {
                            // 换成确定的进度条：转圈 + 百分比一起跳，看着像在闪
                            ProgressView(value: library.sortProgress)
                                .progressViewStyle(.linear)
                                .tint(.white.opacity(0.55))
                                .frame(width: 168)
                                .animation(.linear(duration: 0.16), value: library.sortProgress)

                            Text("正在计算文件大小 \(sortPercentText)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                                .monospacedDigit()
                        } else {
                            ProgressView().tint(.white.opacity(0.5))
                        }
                    }
                } else if assets.isEmpty {
                    if !loading { emptyState }
                } else if showGrid {
                    gridView(width: geo.size.width, pageW: pageW)
                } else {
                    pager(pageW: pageW, cardW: cardW, cardH: cardH)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(pageW: pageW, cardH: cardH))
                        .simultaneousGesture(magnifyGesture(pageW: pageW, cardH: cardH))
                        .simultaneousGesture(doubleTapGesture())
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { stageSize = geo.size }
            .onChange(of: geo.size) { _, newValue in stageSize = newValue }
        }
        .padding(.top, 58)
        // 分组模式底部多一条按钮，卡片区要相应让出位置，否则会被压住
        .padding(.bottom, group != nil ? 132 : 84)
    }

    // MARK: - 网格总览

    /// 全部分类的四列缩略图。用来快速扫一遍、找到要处理的那一段，
    /// 点任意一张就收起网格，落回那一张继续左右滑。
    private func gridView(width: CGFloat, pageW: CGFloat) -> some View {
        let spacing: CGFloat = 2
        let inset: CGFloat = 8
        let columnCount = 4
        let side = max((width - inset * 2 - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount), 40)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(side), spacing: spacing),
                                   count: columnCount),
                    spacing: spacing
                ) {
                    ForEach(assets.indices, id: \.self) { i in
                        Button {
                            jump(to: i, pageW: pageW)
                        } label: {
                            GridThumb(
                                asset: assets[i],
                                side: side,
                                isCurrent: i == index,
                                favorite: favoriteIDs.contains(assets[i].localIdentifier)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // 打开时直接停在你正看的那张附近，不用从第一张往下翻。
                // LazyVGrid 第一次布局时行还没生成完，太早 scrollTo 会滚不到位，
                // 所以补一次延迟调用。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(index, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    /// 从网格里选了一张：收起网格，落到那一张
    private func jump(to i: Int, pageW: CGFloat) {
        guard !assets.isEmpty else { return }
        let target = min(max(i, 0), assets.count - 1)
        index = target
        scrollX = CGFloat(target) * pageW
        dragY = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            showGrid = false
        }
        preheat(pageW: pageW)
    }

    private func pager(pageW: CGFloat, cardW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            // 用 localIdentifier 当标识：删掉一张时只有那一张消失，
            // 相邻两张的身份不变，已经解码好的图片不会被重新请求。
            ForEach(visiblePages(pageW: pageW)) { page in
                cardView(i: page.index, pageW: pageW, cardW: cardW, cardH: cardH)
            }

            verticalFeedback(cardH: cardH)
                .allowsHitTesting(false)
        }
    }

    private func cardView(i: Int, pageW: CGFloat, cardW: CGFloat, cardH: CGFloat) -> some View {
        let x = CGFloat(i) * pageW - scrollX
        let fade = Double(min(abs(x) / pageW, 1))
        let current = (i == index)
        // 缩放只作用在当前这张上；先缩放再位移，
        // 这样平移量不会被缩放系数再放大一遍
        let zoomed = current ? effectiveZoom : 1
        let pan = current ? panOffset : .zero

        let blurred = ImageAnalyzer.shared.isLikelyBlurry(assets[i].localIdentifier)

        return PhotoCard(asset: assets[i], onPlay: playAction(for: i), blurry: blurred)
            .frame(width: cardW, height: cardH)
            .scaleEffect((1 - CGFloat(fade) * 0.06) * zoomed)
            .opacity(1 - fade * 0.45)
            .offset(x: x + pan.width, y: (current ? dragY : 0) + pan.height)
            .zIndex(Double(1000 - abs(x)))
            .allowsHitTesting(current)
    }

    /// 只有视频才给点击回调
    private func playAction(for i: Int) -> (() -> Void)? {
        guard i >= 0, i < assets.count, assets[i].mediaType == .video else { return nil }
        let item = assets[i]
        return { video = VideoSelection(asset: item) }
    }

    /// 只渲染当前页和左右相邻页，几千张也不会卡
    private func visiblePages(pageW: CGFloat) -> [PageRef] {
        guard !assets.isEmpty else { return [] }
        let current = Int(floor(scrollX / pageW))
        let low = max(0, current - 1)
        let high = min(assets.count - 1, current + 1)
        guard low <= high else { return [] }
        return (low...high).map { PageRef(index: $0, id: assets[$0].localIdentifier) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text(isAllCategory ? "全部看完了"
                 : (group != nil ? "这一组处理完了" : "这个分类处理完了"))
                .font(.system(size: 16, weight: .semibold))
            Text("已标记的照片都在右上角的垃圾桶里")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                // 网格展开时，返回键先收起网格，再点一次才退出页面。
                // 否则从网格里想回看大图，只能去点标题，容易误退。
                if showGrid {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showGrid = false
                    }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: showGrid ? "chevron.down" : "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showGrid.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(titleText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        // 已经是「喜欢」的，标题旁挂一颗实心红心，
                        // 下滑前就能看出来这一下是加还是取消
                        if !showGrid, isFavorite(at: index) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.pink)
                                .transition(.opacity)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .rotationEffect(.degrees(showGrid ? 180 : 0))
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(assets.isEmpty)
                .opacity(assets.isEmpty ? 0.5 : 1)

                Text(showGrid ? "共 \(assets.count) 张 · 点任意一张跳过去" : progressText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            Spacer()

            if sortEnabled {
                Menu {
                    ForEach(SortOption.allCases) { option in
                        Button {
                            sortRaw = option.rawValue
                        } label: {
                            if option == sort {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }

            Button {
                openTrash()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())

                    if pending.count > 0 {
                        Text("\(pending.count)")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
            }
            .disabled(pending.isEmpty)
            .opacity(pending.isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var progressText: String {
        guard !assets.isEmpty else { return "0" }
        if let size = currentSizeText {
            return "\(index + 1) / \(assets.count) · \(size)"
        }
        return "\(index + 1) / \(assets.count)"
    }

    /// 排序进度的百分比文字，四舍五入到整数
    private var sortPercentText: String {
        "\(Int((library.sortProgress * 100).rounded()))%"
    }

    /// 按大小排序时，顺带把当前这张的体积显示出来
    private var currentSizeText: String? {
        guard sort.needsSize, index < assets.count,
              let bytes = library.cachedFileSize(for: assets[index]), bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - 底部提示

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if group != nil {
                keepGroupButton
            }

            HStack(spacing: 18) {
                hint(icon: "arrow.left.arrow.right", text: "滑动切换")
                hint(icon: "arrow.up", text: "待删")
                hint(icon: isFavorite(at: index) ? "heart.slash" : "heart",
                     text: isFavorite(at: index) ? "取消喜欢" : "喜欢")
                hint(icon: isZoomed ? "hand.draw" : "arrow.up.left.and.arrow.down.right",
                     text: isZoomed ? "拖动看图" : "双指放大")
            }
            .opacity(0.55)
        }
        .padding(.bottom, 28)
    }

    /// 分组模式专属：滑到想留的那张，一下把同组其余全部丢进待删。
    /// 这是「整组滑一次就处理完」的那一下。
    private var keepGroupButton: some View {
        Button {
            keepCurrentRestOfGroup()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("保留这张，其余 \(max(assets.count - 1, 0)) 张待删")
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(assets.isEmpty)
        .opacity(assets.isEmpty ? 0.35 : 1)
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(text)
                .font(.system(size: 9))
        }
        .foregroundStyle(.white)
    }

    // MARK: - 拖动时的方向反馈

    @ViewBuilder
    private func verticalFeedback(cardH: CGFloat) -> some View {
        if dragY < -28 {
            feedbackBadge(symbol: "trash.fill",
                          text: "加入待删",
                          tint: .red,
                          progress: min(-dragY / (cardH * 0.32), 1))
        } else if dragY > 28 {
            let already = isFavorite(at: index)
            feedbackBadge(symbol: already ? "heart.slash.fill" : "heart.fill",
                          text: already ? "取消喜欢" : "加入喜欢",
                          tint: already ? .gray : .pink,
                          progress: min(dragY / (cardH * 0.32), 1))
        }
    }

    private func feedbackBadge(symbol: String, text: String, tint: Color, progress: CGFloat) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(width: 130, height: 130)
        .background(tint.opacity(0.85), in: Circle())
        .shadow(color: tint.opacity(0.4), radius: 24)
        .opacity(Double(progress))
        .scaleEffect(0.72 + progress * 0.28)
    }

    // MARK: - 手势

    private func dragGesture(pageW: CGFloat, cardH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !animating, !assets.isEmpty else { return }

                // 双指捏合期间，两指同样会触发单指拖动。
                // 这里统一挡住，既不会翻页，也不会把画面拖歪。
                if Date.timeIntervalSinceReferenceDate < pinchGuardUntil { return }

                // 放大状态下，单指拖动是「平移看图」，
                // 不再翻页、也不会触发上滑待删——避免放大看细节时误操作
                if isZoomed {
                    if axis == nil {
                        axis = .pan
                        startPan = panOffset
                    }
                    let cardW = max(pageW - 26, 80)
                    panOffset = clampPan(
                        CGSize(width: startPan.width + value.translation.width,
                               height: startPan.height + value.translation.height),
                        cardW: cardW,
                        cardH: cardH
                    )
                    return
                }

                if axis == nil {
                    let t = value.translation
                    guard abs(t.width) > 7 || abs(t.height) > 7 else { return }
                    // 横向判定比纵向严格一点，斜着划不会误翻页
                    if abs(t.width) > abs(t.height) * 1.15 {
                        axis = .horizontal
                        startX = scrollX
                    } else {
                        axis = .vertical
                    }
                }

                switch axis {
                case .some(.horizontal):
                    // 手指向左 → scrollX 增大（内容左移，右邻页进来）
                    scrollX = rubber(startX - value.translation.width, pageW: pageW)
                case .some(.vertical):
                    dragY = value.translation.height
                case .some(.pan), .none:
                    break
                }
            }
            .onEnded { value in
                guard !animating, !assets.isEmpty else { axis = nil; return }
                guard Date.timeIntervalSinceReferenceDate > pinchGuardUntil else { axis = nil; return }

                switch axis {
                case .some(.horizontal):
                    settle(value, pageW: pageW)
                case .some(.vertical):
                    let threshold = max(cardH * 0.12, 72)
                    if value.translation.height < -threshold {
                        markForDeletion(pageW: pageW, cardH: cardH)
                    } else if value.translation.height > threshold {
                        toggleFavorite(pageW: pageW)
                    } else {
                        snapBack()
                    }
                case .some(.pan):
                    // 平移结束不做吸附，停在原地
                    let cardW = max(pageW - 26, 80)
                    let clamped = clampPan(panOffset, cardW: cardW, cardH: cardH)
                    withAnimation(.easeOut(duration: 0.18)) {
                        panOffset = clamped
                    }
                case .none:
                    break
                }
                axis = nil
            }
    }

    /// 双指缩放。松手时把倍率钳在 1…5 之间，
    /// 回到 1 就顺手把平移量清零。
    private func magnifyGesture(pageW: CGFloat, cardH: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !assets.isEmpty else { return }
                pinch = value.magnification
                // 两根手指同时也会触发单指拖动，必须挡住，
                // 否则一边放大一边就翻到隔壁照片了
                pinchGuardUntil = Date.timeIntervalSinceReferenceDate + 0.35
            }
            .onEnded { value in
                guard !assets.isEmpty else { pinch = 1; return }
                pinchGuardUntil = Date.timeIntervalSinceReferenceDate + 0.25
                zoom = min(max(zoom * value.magnification, 1), 5)
                pinch = 1

                if zoom <= 1.02 {
                    zoom = 1
                    withAnimation(.easeOut(duration: 0.2)) {
                        panOffset = .zero
                    }
                } else {
                    let cardW = max(pageW - 26, 80)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        panOffset = clampPan(panOffset, cardW: cardW, cardH: cardH)
                    }
                }
            }
    }

    /// 双击：在 1× 和 2.5× 之间切换。
    /// 放大之后想翻页，双击还原比反手捏合省事。
    private func doubleTapGesture() -> some Gesture {
        TapGesture(count: 2).onEnded {
            guard !assets.isEmpty else { return }
            haptic(style: .light)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                if effectiveZoom > 1.01 {
                    zoom = 1
                    pinch = 1
                    panOffset = .zero
                    startPan = .zero
                } else {
                    zoom = 2.5
                }
            }
        }
    }

    /// 到边界时的橡皮筋阻尼，手感和系统相册一致
    private func rubber(_ x: CGFloat, pageW: CGFloat) -> CGFloat {
        let maxX = CGFloat(max(assets.count - 1, 0)) * pageW
        if x < 0 { return x * 0.32 }
        if x > maxX { return maxX + (x - maxX) * 0.32 }
        return x
    }

    /// 松手后吸附到最近的页。带速度预测，轻轻一甩也能翻过去。
    private func settle(_ value: DragGesture.Value, pageW: CGFloat) {
        // 放大状态下绝不翻页。哪怕前面的判定出了偏差，这里再兜一层。
        guard !isZoomed else { return }

        let startPage = Int((startX / pageW).rounded())
        let projected = -value.predictedEndTranslation.width / pageW
        var target = startPage + Int(projected.rounded())

        // 甩得慢但拖得远，也算翻页
        if target == startPage, abs(value.translation.width) > pageW * 0.18 {
            target += value.translation.width < 0 ? 1 : -1
        }

        // 一次手势最多翻两页，避免一下甩过好几张
        target = min(max(target, startPage - 2), startPage + 2)
        target = min(max(target, 0), max(assets.count - 1, 0))

        if target != startPage { haptic() }

        animating = true
        index = target
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) {
            scrollX = CGFloat(target) * pageW
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            scrollX = CGFloat(target) * pageW
            animating = false
            preheat(pageW: pageW)
        }
    }

    private func snapBack() {
        animating = true
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            dragY = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            animating = false
        }
    }

    // MARK: - 三种动作

    /// 上滑：加入待删队列（不删除、不打断、不弹窗）
    private func markForDeletion(pageW: CGFloat, cardH: CGFloat) {
        guard index < assets.count else { return }
        let asset = assets[index]

        animating = true
        haptic(style: .medium)
        pending.add(asset.localIdentifier)

        withAnimation(.easeIn(duration: 0.26)) {
            dragY = -(cardH * 1.35)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            dragY = 0
            // 只让这一张离场，其余卡片平滑补位；
            // 配合 stable id，相邻两张不会因此重新解码
            withAnimation(.easeOut(duration: 0.18)) {
                if index < assets.count {
                    assets.remove(at: index)
                }
            }
            if assets.isEmpty {
                index = 0
                scrollX = 0
            } else if index >= assets.count {
                index = assets.count - 1
                scrollX = CGFloat(index) * pageW
            }
            animating = false
            showToast("已加入待删 · 共 \(pending.count) 张")
            preheat(pageW: pageW)
        }
    }

    /// 下滑：在「喜欢」和「取消喜欢」之间切换。
    /// 手滑标错了，滑回上一张再下滑一次就取消了。
    private func toggleFavorite(pageW: CGFloat) {
        guard index < assets.count else { return }
        let asset = assets[index]
        let willFavorite = !favoriteIDs.contains(asset.localIdentifier)

        animating = true
        haptic(style: willFavorite ? .light : .medium)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            dragY = 0
        }

        Task { @MainActor in
            await library.setFavorite(asset, value: willFavorite)

            if willFavorite {
                favoriteIDs.insert(asset.localIdentifier)
            } else {
                favoriteIDs.remove(asset.localIdentifier)
                // 在「喜欢」分类里取消之后，它就不该再出现在这本相册里了
                if isFavoritesCategory {
                    library.forget(localIdentifier: asset.localIdentifier, in: .favorites)
                }
            }
            showToast(willFavorite ? "已加入「喜欢」" : "已取消「喜欢」")

            try? await Task.sleep(nanoseconds: 240_000_000)

            if !willFavorite, isFavoritesCategory {
                // 取消了喜欢，它已经不属于这本相册了
                dropCurrent(pageW: pageW)
            } else if willFavorite {
                // 加入后自动前进一张，节奏不被打断
                let target = min(index + 1, assets.count - 1)
                if target != index {
                    index = target
                    withAnimation(.easeOut(duration: 0.22)) {
                        scrollX = CGFloat(target) * pageW
                    }
                }
            }
            // 取消喜欢时留在原地：方便你确认，想加回来再滑一次就行

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                animating = false
                preheat(pageW: pageW)
            }
        }
    }

    /// 把当前这张从列表里拿掉，顺手把位置和偏移修正到合法范围
    private func dropCurrent(pageW: CGFloat) {
        if index < assets.count {
            assets.remove(at: index)
        }
        if assets.isEmpty {
            index = 0
            scrollX = 0
        } else if index >= assets.count {
            index = assets.count - 1
            scrollX = CGFloat(index) * pageW
        }
    }

    /// 分组模式：留下当前这张，同组其余全部进待删。
    ///
    /// 只写队列，不直接删——删除仍然走垃圾桶里的那一次确认，
    /// 这样手滑也不会真的丢东西。
    private func keepCurrentRestOfGroup() {
        guard !assets.isEmpty else { return }
        let keepID = index < assets.count ? assets[index].localIdentifier : nil

        var added = 0
        for asset in assets where asset.localIdentifier != keepID {
            if !pending.contains(asset.localIdentifier) {
                pending.add(asset.localIdentifier)
                added += 1
            }
        }

        haptic(style: .medium)
        showToast(added > 0 ? "其余 \(added) 张已加入待删" : "这一组只剩这一张了")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            dismiss()
        }
    }

    /// 打开垃圾桶前先记下当前队列，关闭时好对比
    private func openTrash() {
        pendingBeforeTrash = Set(pending.ids)
        showTrash = true
    }

    /// 从垃圾桶回来后和浏览列表对账。
    ///
    /// 原来的问题：上滑只把照片从列表里摘掉、写进队列，
    /// 在垃圾桶里点 × 撤销后只清了队列，列表没有动 ——
    /// 于是那张照片要等下次重新进这个分类才会回来。
    /// 这里在关闭时统一处理两种结果：撤销的插回原位，真删掉的剔除。
    @MainActor
    private func syncAfterTrash() async {
        let now = Set(pending.ids)
        let before = pendingBeforeTrash
        guard now != before else { return }
        pendingBeforeTrash = now

        let currentID: String? = (index >= 0 && index < assets.count)
            ? assets[index].localIdentifier
            : nil

        // 完整有序列表。分组、月份也用这份，不再按分类重新遍历；
        // existing 会把已经被真删掉的剔出去，避免滑到一张空图
        var full = baseList
        if full.isEmpty, let cat = category {
            full = await library.sortedAssets(for: cat, by: sort)
        }
        full = await library.existing(full)
        let fullIDs = Set(full.map { $0.localIdentifier })

        // 保留 = 原本就在列表里的（且没被真删）+ 在垃圾桶里撤销回来的
        var keep = Set(assets.map { $0.localIdentifier })
        keep = keep.intersection(fullIDs)
        for asset in full {
            let id = asset.localIdentifier
            if before.contains(id), !now.contains(id) {
                keep.insert(id)   // 撤销：重新收录
            }
        }

        let ordered = full.filter { keep.contains($0.localIdentifier) && !now.contains($0.localIdentifier) }
        let pageW = max(UIScreen.main.bounds.width, 1)
        let oldCount = assets.count

        assets = ordered
        // 撤销回来的如果本来就是「喜欢」，红心要跟着亮起来
        for asset in ordered where asset.isFavorite {
            favoriteIDs.insert(asset.localIdentifier)
        }

        if let cid = currentID,
           let i = ordered.firstIndex(where: { $0.localIdentifier == cid }) {
            index = i
            scrollX = CGFloat(i) * pageW
        } else {
            let i = min(max(index, 0), max(ordered.count - 1, 0))
            index = i
            scrollX = CGFloat(i) * pageW
        }

        dragY = 0
        resetZoom()

        if ordered.count > oldCount {
            showToast("已放回 \(ordered.count - oldCount) 张")
        }
        preheat(pageW: pageW)
    }

    // MARK: - 数据

    @MainActor
    private func loadList() async {
        loading = true
        showLoadingUI = false
        // 0.16 秒后才允许进度条出现，秒开的分类就完全没有这个中间态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if loading {
                withAnimation(.easeIn(duration: 0.15)) {
                    showLoadingUI = true
                }
            }
        }

        let base: [PHAsset]
        if let preset {
            // 分组、月份、照片墙：列表已经定好了，直接按原顺序用
            base = preset
        } else if let category {
            base = await library.sortedAssets(for: category, by: sort)
        } else {
            base = []
        }
        baseList = base

        let queued = Set(PendingStore.shared.ids)
        assets = base.filter { !queued.contains($0.localIdentifier) }
        // 进来时先把已有的「喜欢」读一遍，之后本地维护，
        // 这样下手滑下滑不会重复加，而是能取消
        favoriteIDs = Set(assets.filter { $0.isFavorite }.map { $0.localIdentifier })

        // 从照片墙点进来的，落到点的那一张
        let pageW = max(UIScreen.main.bounds.width, 1)
        if let startID, let i = assets.firstIndex(where: { $0.localIdentifier == startID }) {
            index = i
        } else {
            index = min(max(initialIndex, 0), max(assets.count - 1, 0))
        }
        scrollX = CGFloat(index) * pageW
        dragY = 0
        showLoadingUI = false
        loading = false
        preheat(pageW: pageW)
    }

    /// 切换排序后重新取一遍，回到第一张
    @MainActor
    private func reload() async {
        loading = true
        showLoadingUI = false
        // 不清空 assets：旧列表先留在屏幕上，等新顺序算好再整体替换，
        // 中间不会出现黑屏
        index = 0
        scrollX = 0
        dragY = 0
        await loadList()
        if sort.needsSize {
            showToast("已按\(sort.shortTitle)排序")
        }
    }

    private func preheat(pageW: CGFloat) {
        guard !assets.isEmpty else { return }
        let low = max(0, index - 1)
        let high = min(assets.count, index + 3)
        guard low < high else { return }

        let scale = UIScreen.main.scale
        let cardW = max(pageW - 26, 80)
        let fallbackH = UIScreen.main.bounds.height - 142
        let cardH = max(stageSize.height > 1 ? stageSize.height : fallbackH, 80)
        library.preheat(Array(assets[low..<high]),
                        targetSize: CGSize(width: cardW * scale, height: cardH * scale))
    }

    private var toastLayer: some View {
        VStack {
            Spacer()
            if let toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                if toast == text { toast = nil }
            }
        }
    }

    private func haptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - 单张照片卡片

struct PhotoCard: View {
    let asset: PHAsset
    var onPlay: (() -> Void)? = nil
    /// 分析判定「可能虚焦」，在右上角贴一个角标
    var blurry: Bool = false

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.08))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.slash")
                            .font(.system(size: 24, weight: .light))
                        Text("这张还在 iCloud 里")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.35))
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.3))
                }

                if asset.mediaType == .video {
                    videoOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if blurry {
                    HStack(spacing: 3) {
                        Image(systemName: "camera.filters")
                            .font(.system(size: 8, weight: .bold))
                        Text("可能虚焦")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(Color.orange.opacity(0.88), in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                if asset.mediaType == .video, let onPlay {
                    onPlay()
                }
            }
            .task(id: asset.localIdentifier) {
                let target = CGSize(width: max(geo.size.width, 1) * UIScreen.main.scale,
                                    height: max(geo.size.height, 1) * UIScreen.main.scale)
                for await loaded in PhotoLibrary.shared.imageStream(for: asset, targetSize: target) {
                    await MainActor.run {
                        image = loaded
                        failed = false
                    }
                }
                await MainActor.run {
                    if image == nil { failed = true }
                }
            }
        }
    }

    private var videoOverlay: some View {
        ZStack {
            Image(systemName: "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                }

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                        Text(durationText)
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.45), in: Capsule())

                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var durationText: String {
        let total = Int(asset.duration.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 总览网格里的缩略图

struct GridThumb: View {
    let asset: PHAsset
    let side: CGFloat
    let isCurrent: Bool
    let favorite: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.10, green: 0.10, blue: 0.12)

            if let image {
                // 尺寸写死 + clipped：宽幅全景图不会溢出到隔壁格子去抢点击
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            }

            if asset.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(4)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if favorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.pink)
                    .padding(4)
            }
        }
        .overlay {
            if isCurrent {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .task(id: asset.localIdentifier) {
            let pixel = side * UIScreen.main.scale
            image = await PhotoLibrary.shared.image(
                for: asset,
                targetSize: CGSize(width: pixel, height: pixel)
            )
        }
    }
}
