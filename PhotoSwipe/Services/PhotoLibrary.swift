import Foundation
import Photos
import UIKit

/// PhotoKit 的唯一入口。
/// 所有重活（遍历、取图、删除）都丢到后台队列，主线程只负责刷新 UI。
final class PhotoLibrary: ObservableObject {
    static let shared = PhotoLibrary()

    @Published var status: PHAuthorizationStatus
    @Published var counts: [SmartCategory: Int] = [:]
    @Published var covers: [SmartCategory: String] = [:]   // 每个分类第一张的 localIdentifier，用来当封面
    @Published var isLoadingCounts = false
    @Published var lastError: String?

    /// 缓存每个分类的完整列表，避免每次进详情页都重新遍历
    private var listCache: [SmartCategory: [PHAsset]] = [:]
    /// 封面缩略图。加了 @Published，加载完成后网格会自动刷新
    @Published private var coverImageCache: [String: UIImage] = [:]

    let imageManager = PHCachingImageManager()

    private init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - 权限

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 请求相册读写权限（删除照片需要 readWrite，不能用 addOnly）
    @discardableResult
    func requestAccess() async -> PHAuthorizationStatus {
        let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { self.status = result }
        return result
    }

    /// 用户只授权了「部分照片」时，跳到系统设置重新选择。
    /// 注：presentLimitedLibraryPicker(from:) 在 iOS 18 的 SDK 里已不可用，
    /// 所以这里直接打开本 App 的设置页，用户在里面就能改照片权限。
    func presentLimitedPicker() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 统计与列表

    /// 统计每个分类的数量 + 取封面。全部在后台线程完成。
    func loadCounts() async {
        await MainActor.run { self.isLoadingCounts = true }

        let result = await withCheckedContinuation {
            (cont: CheckedContinuation<([SmartCategory: Int], [SmartCategory: String]), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var countMap: [SmartCategory: Int] = [:]
                var coverMap: [SmartCategory: String] = [:]
                for category in SmartCategory.allCases {
                    let fetched = PHAsset.fetchAssets(with: category.fetchOptions)
                    countMap[category] = fetched.count
                    if fetched.count > 0 {
                        coverMap[category] = fetched.object(at: 0).localIdentifier
                    }
                }
                cont.resume(returning: (countMap, coverMap))
            }
        }

        await MainActor.run {
            self.counts = result.0
            self.covers = result.1
            self.isLoadingCounts = false
        }
    }

    /// 取出某个分类的全部资源。第一次会遍历，之后走缓存。
    func assets(for category: SmartCategory, forceRefresh: Bool = false) async -> [PHAsset] {
        if !forceRefresh, let cached = listCache[category] {
            return cached
        }
        let list = await withCheckedContinuation { (cont: CheckedContinuation<[PHAsset], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fetched = PHAsset.fetchAssets(with: category.fetchOptions)
                var array: [PHAsset] = []
                array.reserveCapacity(fetched.count)
                fetched.enumerateObjects { asset, _, _ in array.append(asset) }
                cont.resume(returning: array)
            }
        }
        listCache[category] = list
        return list
    }

    func invalidateCache() {
        listCache.removeAll()
    }

    // MARK: - 取图

    /// 加载单张图片。targetSize 传 nil 表示按原图尺寸取。
    func image(for asset: PHAsset, targetSize: CGSize?) async -> UIImage? {
        let size = targetSize ?? CGSize(width: asset.pixelWidth, height: asset.pixelHeight)

        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true   // 关键：iCloud 里的照片也能取到
            options.version = .current

            var resumed = false
            self.imageManager.requestImage(for: asset,
                                           targetSize: size,
                                           contentMode: .aspectFill,
                                           options: options) { image, info in
                if let info = info, (info[PHImageCancelledKey] as? Bool) == true { return }
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }
        }
    }

    /// 预取。滑动到第 N 张时，把 N+1、N+2 提前读进缓存，滑起来才不会卡。
    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets,
                                        targetSize: targetSize,
                                        contentMode: .aspectFill,
                                        options: nil)
    }

    func stopPreheat() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - 封面

    func coverImage(for category: SmartCategory) -> UIImage? {
        guard let id = covers[category] else { return nil }
        return coverImageCache[id]
    }

    func loadCoverImages() async {
        for category in SmartCategory.allCases {
            guard let id = covers[category],
                  coverImageCache[id] == nil else { continue }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard let asset = result.firstObject else { continue }
            if let thumb = await self.image(for: asset, targetSize: CGSize(width: 300, height: 300)) {
                await MainActor.run { self.coverImageCache[id] = thumb }
            }
        }
    }

    // MARK: - 删除

    /// 批量删除。PhotoKit 会把它们一次性移进「最近删除」，系统只弹一次确认。
    /// 删除后 30 天内都能在系统相册的「最近删除」里恢复，所以不需要我们自己做备份。
    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var targets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in targets.append(asset) }
        guard !targets.isEmpty else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(targets as NSArray)
        }

        await MainActor.run {
            self.listCache.removeAll()
            for id in ids { self.coverImageCache.removeValue(forKey: id) }
        }
    }

    // MARK: - 收藏

    func setFavorite(_ asset: PHAsset, value: Bool) async {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = value
            }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }
}
