import SwiftUI
import Photos
import UIKit

struct TrashView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var pending: PendingStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var loading = true
    @State private var deleting = false
    @State private var errorMessage: String?
    @State private var showError = false
    /// 队列加起来多大。0 且 computing 为真时显示「计算中」
    @State private var totalBytes: Int64 = 0
    @State private var computingBytes = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 4)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if loading {
                    ProgressView().tint(.white.opacity(0.5))
                } else if assets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        sizeCard
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                            .padding(.bottom, 10)

                        notice
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                TrashThumb(asset: asset) {
                                    remove(asset)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !assets.isEmpty {
                    deleteBar
                }
            }
            .navigationTitle("待删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task { await loadAssets() }
            .alert("删除失败", isPresented: $showError) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - 子视图

    /// 顶部「删掉这批能腾出多少空间」。
    /// 这是整个 App 唯一的量化回报，放在最上面，比任何说明都直接。
    private var sizeCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("这批删掉，可释放")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(sizeText)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if computingBytes {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text("\(assets.count)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("张")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.13, blue: 0.16),
                         Color(red: 0.11, green: 0.11, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var sizeText: String {
        if computingBytes && totalBytes == 0 { return "计算中…" }
        if totalBytes <= 0 { return "未知" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var notice: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 13))
                .foregroundStyle(.green)
            Text("删除后会进入系统「最近删除」，30 天内都能恢复")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("队列是空的")
                .font(.system(size: 15, weight: .semibold))
            Text("回到相册，向上滑动照片就会出现在这里")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var deleteBar: some View {
        VStack(spacing: 8) {
            Button {
                deleteAll()
            } label: {
                ZStack {
                    if deleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("全部删除 \(assets.count) 张")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(deleting)

            Text("系统会再确认一次，点「删除」即可")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - 数据

    private func loadAssets() async {
        let ids = pending.ids
        guard !ids.isEmpty else {
            await MainActor.run { loading = false }
            return
        }

        let ordered = await withCheckedContinuation { (cont: CheckedContinuation<[PHAsset], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var map: [String: PHAsset] = [:]
                fetched.enumerateObjects { asset, _, _ in
                    map[asset.localIdentifier] = asset
                }
                // 按入队顺序排列，而不是系统返回顺序
                cont.resume(returning: ids.compactMap { map[$0] })
            }
        }

        await MainActor.run {
            assets = ordered
            loading = false
        }
        await refreshBytes()
    }

    /// 重新汇总体积。删除流程一行没改，这里只是在旁边看一眼大小。
    private func refreshBytes() async {
        computingBytes = true
        let bytes = await library.totalBytes(for: pending.ids)
        await MainActor.run {
            totalBytes = bytes
            computingBytes = false
        }
    }

    private func remove(_ asset: PHAsset) {
        pending.remove(asset.localIdentifier)
        withAnimation(.easeOut(duration: 0.2)) {
            assets.removeAll { $0.localIdentifier == asset.localIdentifier }
        }
        Task { await refreshBytes() }
    }

    private func deleteAll() {
        guard !deleting else { return }
        deleting = true
        let ids = pending.ids

        Task {
            do {
                try await library.delete(ids: ids)
                await MainActor.run {
                    pending.clear()
                    assets.removeAll()
                    deleting = false
                    dismiss()
                }
                await library.loadCounts()
                await library.loadCoverImages()
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    deleting = false
                    // 用户点了系统的「取消」，不算错误，安静返回
                    if !message.lowercased().contains("cancel") {
                        errorMessage = message
                        showError = true
                    }
                }
            }
        }
    }
}

// MARK: - 队列里的缩略图

struct TrashThumb: View {
    let asset: PHAsset
    let onRemove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    // 和分类格子一样的坑：不框死尺寸的话，宽幅照片会溢出去，
                    // 盖住隔壁格子的 × 按钮，让那个按钮点不动
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.black.opacity(0.65), in: Circle())
                }
                .padding(4)
            }
            .task(id: asset.localIdentifier) {
                image = await PhotoLibrary.shared.image(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300)
                )
            }
    }
}
