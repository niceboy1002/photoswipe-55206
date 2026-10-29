# 版本记录

这个文件记录每个版本的改动，方便对照手里的压缩包是不是最新的。

> 版本号从 v15 开始。之所以不是 v1，是因为前面 14 个包都是调试期反复
> 试编译用的，对应 GitHub Actions 跑的第 1～14 次，没有单独存档。
> 从这里开始正式编号，包名会直接写成 `PhotoSwipe-v15.zip`。

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
