import SwiftUI
import Photos
import UIKit

// MARK: - 首页上的智能入口小卡片

struct SmartTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color(red: 0.10, green: 0.10, blue: 0.11),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 通用缩略图

struct AssetThumb: View {
    let asset: PHAsset?
    let side: CGFloat
    var radius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(red: 0.13, green: 0.13, blue: 0.14))

            if let image {
                // 尺寸写死再 clipped：宽幅全景不会溢出到隔壁去抢点击
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: asset?.localIdentifier) {
            guard let asset else { return }
            let pixel = side * UIScreen.main.scale
            image = await PhotoLibrary.shared.image(
                for: asset,
                targetSize: CGSize(width: pixel, height: pixel)
            )
        }
    }
}

// MARK: - 分组行

struct GroupRow: View {
    let group: PhotoGroup

    var body: some View {
        HStack(spacing: 11) {
            AssetThumb(asset: group.assets.first, side: 54, radius: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(group.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("\(group.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.07), in: Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(9)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - 分析进度

struct AnalysisProgressView: View {
    @ObservedObject var analyzer: ImageAnalyzer
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.55))

            Text("正在分析照片")
                .font(.system(size: 16, weight: .semibold))

            ProgressView(value: analyzer.progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.6))
                .frame(width: 210)

            Text("\(analyzer.doneCount) / \(analyzer.totalCount)")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()

            Text("只分析本机已有的照片，存在 iCloud 上、还没下载的会自动跳过\n最多分析最近 5000 张，结果会缓存，下次打开是瞬时的")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.32))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button("先停下") { onCancel() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 按月整理

struct MonthListView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore

    @State private var groups: [PhotoGroup] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loading {
                ProgressView().tint(.white.opacity(0.5))
            } else if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(groups) { group in
                            NavigationLink {
                                SwipeViewerView(title: group.title, assets: group.assets)
                            } label: {
                                GroupRow(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("按月整理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let all = await library.assets(for: .all)
            await MainActor.run {
                groups = PhotoGroup.months(from: all)
                loading = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("还没有照片")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - 相似 / 连拍

struct SimilarGroupsView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @ObservedObject private var analyzer = ImageAnalyzer.shared

    @State private var groups: [PhotoGroup] = []
    @State private var loading = true
    @State private var started = false
    /// 留着整库列表，从某一组退回来重算时不用再取一遍
    @State private var allAssets: [PHAsset] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if analyzer.running {
                AnalysisProgressView(analyzer: analyzer, onCancel: { analyzer.stop() })
            } else if loading {
                ProgressView().tint(.white.opacity(0.5))
            } else if groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    header
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 10)

                    LazyVStack(spacing: 7) {
                        ForEach(groups) { group in
                            NavigationLink {
                                SwipeViewerView(title: group.kind.title,
                                                assets: group.assets,
                                                group: group)
                            } label: {
                                GroupRow(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("相似与连拍")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
        .onAppear {
            // 从某一组退回来时重算一次：刚处理掉的组应该从列表消失
            guard started, !analyzer.running, !allAssets.isEmpty else { return }
            Task { await refresh(with: allAssets) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("共 \(groups.count) 组")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("连拍排在前面。进去之后滑到想留的那张，点底部按钮，其余一次进待删。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("没有找到明显的重复")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("连拍需要系统保留连拍信息；\n相似照片需要本机有可读的缩略图。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(24)
    }

    @MainActor
    private func start() async {
        guard !started else { return }
        started = true

        analyzer.loadCacheIfNeeded()
        let all = await library.assets(for: .all)
        allAssets = all

        let photos = all.filter { $0.mediaType == .image }
        await analyzer.ensureAnalyzed(photos, limit: 5000)

        await refresh(with: all)
    }

    @MainActor
    private func refresh(with all: [PHAsset]) async {
        let raw = analyzer.similarityGroups(from: all)
        let queued = Set(pending.ids)

        // 已经进了待删队列的那几张不该再算进组里；
        // 一整组都进队列了，这一组就不再显示
        var visible: [PhotoGroup] = []
        visible.reserveCapacity(raw.count)
        for group in raw {
            let left = group.assets.filter { !queued.contains($0.localIdentifier) }
            guard left.count >= 2 else { continue }
            visible.append(
                PhotoGroup(id: group.id,
                           kind: group.kind,
                           title: "\(group.kind.title) · \(left.count) 张",
                           subtitle: group.subtitle,
                           assets: left)
            )
        }

        await MainActor.run {
            groups = visible
            loading = false
        }
    }
}

// MARK: - 90 天前的截屏

struct OldScreenshotsView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore

    @State private var assets: [PHAsset] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white.opacity(0.5))
                }
            } else if assets.isEmpty {
                ZStack {
                    Color.black.ignoresSafeArea()
                    emptyState
                }
            } else {
                PhotoGridView(
                    title: "90 天前的截屏",
                    assets: assets,
                    caption: "\(assets.count) 张 · 三个月前的截图基本不会再看了"
                )
            }
        }
        .navigationTitle("过期截屏")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let all = await library.assets(for: .all)
            let queued = Set(pending.ids)
            let group = PhotoGroup.oldScreenshots(from: all)
            await MainActor.run {
                assets = (group?.assets ?? []).filter { !queued.contains($0.localIdentifier) }
                loading = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("没有过期的截屏")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("三个月内的截图不算过期，这里只放更早的")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - 拍糊的照片

struct BlurryPhotosView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @ObservedObject private var analyzer = ImageAnalyzer.shared

    @State private var assets: [PHAsset] = []
    @State private var loading = true
    @State private var started = false

    var body: some View {
        Group {
            if analyzer.running {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AnalysisProgressView(analyzer: analyzer, onCancel: { analyzer.stop() })
                }
            } else if loading {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white.opacity(0.5))
                }
            } else if assets.isEmpty {
                ZStack {
                    Color.black.ignoresSafeArea()
                    emptyState
                }
            } else {
                PhotoGridView(
                    title: "可能拍糊",
                    assets: assets,
                    caption: "\(assets.count) 张 · 按模糊程度从重到轻排，仍然需要你过一眼"
                )
            }
        }
        .navigationTitle("可能拍糊")
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.filters")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("没有明显拍糊的照片")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("这个判定偏保守，只挑明显失焦的")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    @MainActor
    private func start() async {
        guard !started else { return }
        started = true

        analyzer.loadCacheIfNeeded()
        let all = await library.assets(for: .all)

        let photos = all.filter { $0.mediaType == .image }
        await analyzer.ensureAnalyzed(photos, limit: 5000)

        let queued = Set(pending.ids)
        let list = analyzer.blurryAssets(from: all).filter { !queued.contains($0.localIdentifier) }
        await MainActor.run {
            assets = list
            loading = false
        }
    }
}

// MARK: - 四列照片墙

struct IndexBox: Hashable {
    let index: Int
}

struct PhotoGridView: View {
    let title: String
    let assets: [PHAsset]
    let caption: String

    @State private var selection: IndexBox?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    private var side: CGFloat {
        max((UIScreen.main.bounds.width - 24 - 6) / 4, 40)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 2)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(assets.indices), id: \.self) { index in
                        Button {
                            selection = IndexBox(index: index)
                        } label: {
                            AssetThumb(asset: assets[index], side: side, radius: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selection) { box in
            SwipeViewerView(
                title: title,
                assets: assets,
                startAt: box.index,
                startID: assets.indices.contains(box.index) ? assets[box.index].localIdentifier : nil
            )
        }
    }
}
