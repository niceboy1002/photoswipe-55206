import Foundation
import Photos

/// 相册分类。
///
/// 关键改动：不再用谓词自己猜，而是直接读系统「智能相簿」
/// （`PHAssetCollectionType.smartAlbum`）。这和你在系统相册「相簿」页里看到的那几本
/// 完全一致，是苹果自己算好的结果。
///
/// 其中「自拍」必须走这条路——PhotoKit 没有提供「前置摄像头」对应的谓词，
/// 但 `smartAlbumSelfPortraits` 这个智能相簿是公开 API，可以正常读取。
enum SmartCategory: String, CaseIterable, Identifiable {
    case all
    case selfies
    case screenshots
    case livePhotos
    case videos
    case panoramas
    case portraits
    case favorites

    var id: String { rawValue }

    /// 网格里显示的分类。「全部」单独做成顶部横幅，不占格子。
    static var gridCases: [SmartCategory] {
        allCases.filter { $0 != .all }
    }

    var title: String {
        switch self {
        case .all:         return "全部照片"
        case .selfies:     return "自拍"
        case .screenshots: return "截屏"
        case .livePhotos:  return "实况照片"
        case .videos:      return "视频"
        case .panoramas:   return "全景"
        case .portraits:   return "人像模式"
        case .favorites:   return "喜欢"
        }
    }

    var symbol: String {
        switch self {
        case .all:         return "square.grid.2x2.fill"
        case .selfies:     return "person.crop.square"
        case .screenshots: return "camera.viewfinder"
        case .livePhotos:  return "livephoto"
        case .videos:      return "video.fill"
        case .panoramas:   return "pano"
        case .portraits:   return "person.crop.rectangle"
        case .favorites:   return "heart.fill"
        }
    }

    /// 卡片配色（渐变的两个端点）
    var colors: [String] {
        switch self {
        case .all:         return ["#3B3B4A", "#15151C"]
        case .selfies:     return ["#4A3A6B", "#1C1529"]
        case .screenshots: return ["#2C3E63", "#16213A"]
        case .livePhotos:  return ["#5A3C6B", "#2A1A33"]
        case .videos:      return ["#1F4E5F", "#0D242C"]
        case .panoramas:   return ["#3A5C4A", "#15261E"]
        case .portraits:   return ["#6B3A3A", "#2E1717"]
        case .favorites:   return ["#6B2740", "#2E0F1B"]
        }
    }

    // MARK: - 取数

    /// 对应的系统智能相簿。「全部」没有相簿，直接全库取。
    var smartAlbumSubtype: PHAssetCollectionSubtype? {
        switch self {
        case .all:         return nil
        case .selfies:     return .smartAlbumSelfPortraits
        case .screenshots: return .smartAlbumScreenshots
        case .livePhotos:  return .smartAlbumLivePhotos
        case .videos:      return .smartAlbumVideos
        case .panoramas:   return .smartAlbumPanoramas
        case .portraits:   return .smartAlbumDepthEffect
        case .favorites:   return .smartAlbumFavorites
        }
    }

    /// 智能相簿取不到时的兜底谓词。
    /// 「自拍」没有兜底方案（系统没给谓词），返回 nil，此时宁可返回空也不返回全部。
    var fallbackPredicate: NSPredicate? {
        switch self {
        case .all:
            return NSPredicate(
                format: "mediaType == %d OR mediaType == %d",
                Int(PHAssetMediaType.image.rawValue),
                Int(PHAssetMediaType.video.rawValue)
            )
        case .selfies:
            return nil
        case .screenshots:
            return NSPredicate(format: "mediaSubtype & %d != 0",
                               Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        case .livePhotos:
            return NSPredicate(format: "mediaSubtype & %d != 0",
                               Int(PHAssetMediaSubtype.photoLive.rawValue))
        case .videos:
            return NSPredicate(format: "mediaType == %d",
                               Int(PHAssetMediaType.video.rawValue))
        case .panoramas:
            return NSPredicate(format: "mediaSubtype & %d != 0",
                               Int(PHAssetMediaSubtype.photoPanorama.rawValue))
        case .portraits:
            return NSPredicate(format: "mediaSubtype & %d != 0",
                               Int(PHAssetMediaSubtype.photoDepthEffect.rawValue))
        case .favorites:
            return NSPredicate(format: "isFavorite == YES")
        }
    }

    /// 统一入口：所有分类都从这里取，保证计数和列表用的是同一套规则。
    func fetchAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if let subtype = smartAlbumSubtype {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            if let collection = collections.firstObject {
                return PHAsset.fetchAssets(in: collection, options: options)
            }
            // 系统里没有这本相簿（例如新机还没拍过自拍）
            if let predicate = fallbackPredicate {
                options.predicate = predicate
                return PHAsset.fetchAssets(with: options)
            }
            return PHAsset.fetchAssets(withLocalIdentifiers: [], options: nil)
        }

        options.predicate = fallbackPredicate
        return PHAsset.fetchAssets(with: options)
    }
}
