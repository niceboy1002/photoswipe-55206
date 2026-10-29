# 版本记录

这个文件记录每个版本的改动，方便对照手里的压缩包是不是最新的。

> 版本号从 v15 开始。之所以不是 v1，是因为前面 14 个包都是调试期反复
> 试编译用的，对应 GitHub Actions 跑的第 1～14 次，没有单独存档。
> 从这里开始正式编号，包名会直接写成 `PhotoSwipe-v15.zip`。

---

## v16 — 2026-10-29

### 修复：四列照片墙点错行

`Views/SmartGroupsView.swift` 的 `AssetThumb`：

- 根因：`Image` 用 `scaledToFill()` 填方形格子时，竖图（3:4）会被放大到
  高 = 格宽 × 4/3，上下各溢出 1/6 格（约 15pt）。
  `.frame()` 只限制布局、`.clipped()` 只裁剪**绘制**，两者都不改命中测试区域，
  溢出的那 15pt 仍然可点。SwiftUI 命中测试优先问子视图，于是点这一格的下半部分，
  会被下一行那张接走。
- 修复：`Image` 自身和外层各加一道 `.contentShape(Rectangle())`，
  把图片和整格的可点范围都锁成侧长正方形。
- 同时把 `PhotoGridView` 的列宽从 `UIScreen` 估算改成 `GeometryReader` + 整数取整，
  消除四列累积误差。

### 修复：喜欢后回上一张会退两张

`Views/SwipeViewerView.swift`：

- 新增 `startIndex`（手势起点的整数页号），`settle` 用它算落点，
  不再用 `Int(scrollX / pageW)` 反推浮点位置。
- 新增 `lockToIndex(pageW:)`，任何程序化跳页（自动前进、跳网格、删除、撤销对账）
  之后都把 `index` 和 `scrollX` 钉在同一页。
- `settle` 的速度预测只用来判断「翻不翻」，不再用它算「翻几页」，
  一次手势最多翻一张。
- 自动前进的动画收尾时调用 `lockToIndex`，避免下一次手势从半路起算。

### 新增：缩放转场

`Views/ZoomTransition.swift`：

- `zoomSource(id:in:)` / `zoomDestination(id:in:)` 两个扩展，
  内部用 `#available(iOS 18.0, *)` 包住
  `matchedTransitionSource(id:in:)` 与 `navigationTransition(.zoom(sourceID:in:))`。
- 接入位置：首页「全部照片」横幅、首页八个分类卡片、按月整理的月份行。
- iOS 17 上自动退回系统默认推入动画，不影响编译与运行。

### 打包结构

改成「大包套中包」：外层 `PhotoSwipe-v16/` 放说明，`upload/` 里才是要上传仓库的内容。

---

## v15 — 2026-10-29

**改了什么**：1 行。

- `Models/PhotoGroup.swift`：`asset.mediaSubtype` → `asset.mediaSubtypes`

**为什么**：PhotoKit 里这个属性是复数（`mediaSubtypes`，OptionSet 类型）。
写成单数，编译器找不到成员，连带同一行的 `.photoScreenshot` 也失去上下文。

**对应报错**（run #14）：

```
PhotoGroup.swift:101:25: error: value of type 'PHAsset' has no member 'mediaSubtype'
PhotoGroup.swift:101:48: error: cannot infer contextual base in reference to member 'photoScreenshot'
```

**顺带核过的地方**：`SmartCategory.swift` 里出现的 `mediaSubtype` 是
NSPredicate 的字符串键名，查询谓词里确实是单数，属于正确写法，未改动。

---

## v1 – v14（调试期，未单独存档）

主要在做这些事：

- 建立工程骨架（SwiftUI + PhotoKit，XcodeGen 生成，GitHub Actions 编译）
- 分类浏览：全部 / 自拍 / 截屏 / 实况 / 视频 / 全景 / 人像 / 喜欢
- 左右滑动切换，上滑进待删队列，下滑切换「喜欢」
- 连续跟手分页、双指缩放、缩略图总览
- 视频播放、按文件大小排序
- 相似与连拍分组、按月整理、90 天前截屏、拍糊检测
- 修复若干编译错误（Optional 枚举比较、不存在的 PhotoKit API、漏写 return 等）
