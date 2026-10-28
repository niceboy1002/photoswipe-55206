# 相册整理 PhotoSwipe

一个只给自己用的 iOS 相册整理 App。滑动决定去留，攒够了再一次性清理。

**不需要 Mac，不需要 Xcode，不需要上架 App Store。** 全程用 GitHub 的免费苹果机器编译。

---

## 一、这个 App 长什么样

**首页**：7 个分类卡片，每张显示分类名和数量。

| 分类 | 判定依据 |
|---|---|
| 截屏 | 系统标记为截图的照片 |
| 实况照片 | 系统标记为 Live Photo |
| 视频 | 所有视频 |
| 自拍 | **前置摄像头拍的**（不是人脸识别，别人帮你拍的不算） |
| 全景 / 连拍 / 喜欢 | 对应的系统标记 |

**点进任意分类** → 全屏看照片，四个手势：

| 手势 | 效果 |
|---|---|
| 左右滑 | 上一张 / 下一张 |
| **向上滑** | 加入待删队列（不删除、不弹窗、不打断） |
| 向下滑 | 标为系统相册的「喜欢」，自动跳下一张 |

**右上角垃圾桶**（带数字角标）→ 看到所有准备删的照片 → 可以单张点 × 撤销 → 点「全部删除」→ 系统弹一次确认 → 删进「最近删除」，**30 天内都能恢复**。

待删队列会存下来，App 关了、手机重启了都还在。

---

## 二、开始之前，准备四样东西

1. **一个 GitHub 账号** —— 免费注册：https://github.com/signup
2. **一台 Windows 电脑** —— 你现在用的这台就行
3. **iPhone 一根数据线**
4. **你的 Apple ID** —— 就是登录 App Store 那个，不用付费开发者账号

---

## 三、第一步：把代码放进 GitHub（约 10 分钟）

### 3.1 新建仓库

1. 登录 GitHub，点右上角 `+` → `New repository`
2. **Repository name** 填：`photoswipe`
3. 选 **Public**（公开。免费额度无限，私有仓库每月只有 2000 分钟，浪费）
4. 下面三个勾（Add README / .gitignore / license）**都不要勾**
5. 点 `Create repository`

### 3.2 上传代码

创建完会看到一个空仓库页面，中间有一行 `uploading an existing file`，点它。

把你解压出来的 `PhotoSwipe` 文件夹里的**所有东西**（`PhotoSwipe` 文件夹、`.github` 文件夹、`project.yml`、`README.md`）全选，拖到网页的上传区域。

> **注意**：拖之前先在文件夹里按 `Ctrl + H` 或用「查看 → 显示 → 隐藏的项目」确认能看到 `.github` 这个文件夹。它是编译的开关，漏了就白干。

等文件列表全部出现，拉到底点绿色的 `Commit changes`。

### 3.3 检查一件事

回到仓库首页，确认里面能看到：

```
.github/
PhotoSwipe/
project.yml
README.md
```

**如果看不到 `.github`**：点 `Add file` → `Create new file`，文件名处输入 `.github/workflows/build.yml`（斜杠会自动建文件夹），把本地那个文件的内容整个粘进去，提交。

---

## 四、第二步：让 GitHub 帮你编译（约 8 分钟，全自动）

1. 点仓库顶部的 **Actions** 标签页
2. 如果提示 "Workflows aren't being run on this repository"，点绿色按钮 `I understand my workflows, go ahead and enable them`
3. 左边应该出现 `Build IPA`，点它
4. 右边点 `Run workflow` → 再点绿色 `Run workflow`
5. 刷新页面，会出现一条黄色圆点（进行中）→ 变成黄色转圈 → 变成 **绿色对勾**

**大约 6~10 分钟后变成绿色对勾，就成功了。**

如果变成**红色叉**：点进去，把报错那一段截图发给我，我改代码。

### 下载 IPA

1. 点进那条绿色的运行记录
2. 拉到底部 **Artifacts** 区域
3. 点 `PhotoSwipe-IPA` 下载（是个 zip）
4. 解压，里面就是 **`PhotoSwipe.ipa`**

---

## 五、第三步：装到 iPhone 上（约 10 分钟，只需做一次）

### 5.1 在 Windows 上装两个软件

| 软件 | 干什么用 | 哪里下 |
|---|---|---|
| **Apple Devices** | 让 Windows 能识别 iPhone | 微软商店搜 "Apple Devices" |
| **Sideloadly** | 用你的 Apple ID 给 IPA 签名 | https://sideloadly.io |

> 如果微软商店装不了 Apple Devices，改装 iTunes（必须是**官网下载的版本**，不能是微软商店版）。两个装一个就行。

### 5.2 手机这边

1. 数据线连电脑，手机上点「**信任**」
2. 打开 `设置 → 隐私与安全性 → 开发者模式`，打开它（**装完 App 才会出现这个选项，先跳过也行**）

### 5.3 Sideloadly 签名安装

1. 打开 Sideloadly
2. **iOS device** 那里确认已经识别到你的 iPhone（下拉能看到机型）
3. 把 `PhotoSwipe.ipa` 拖进 **IPA** 那一栏
4. **Apple ID** 填你的 Apple 账号
5. 点 `Start`
6. 会弹窗让你输 Apple ID 密码。如果开了双重认证，可能会让你去手机上点「允许」或者生成专用密码 —— **按提示走就行**
7. 进度条跑完，出现 `Done` 就装好了

### 5.4 最后一步：信任

1. 手机上打开 App，如果提示"不受信任的开发者"
2. `设置 → 通用 → VPN与设备管理 → 开发者App` → 点你的 Apple ID → `信任`
3. 如果还提示需要开发者模式：`设置 → 隐私与安全性 → 开发者模式` → 打开 → **重启手机**

现在可以用了。

---

## 六、7 天后会失效，怎么办

免费 Apple ID 签名的 App **有效期 7 天**。到期后点开图标会闪退。这不是 bug，是苹果对免费开发者的限制。

**续期方法**：把手机连电脑，打开 Sideloadly，重新拖一次 IPA，点 Start。一分钟搞定。

**你的数据不会丢** —— 待删队列、设置都还在。

> 嫌麻烦的话，以后可以上 SideStore（自动续签），但那要多折腾一轮，先用着这个。

---

## 七、出问题怎么办

| 现象 | 原因 | 解决 |
|---|---|---|
| 首页所有分类都是 0 | 权限只给了「部分照片」 | 首页顶部有黄色提示条，点「管理」全选 |
| 照片一直转圈圈 | 照片在 iCloud 上没下载到本地 | 等一下，或者先在系统相册里打开一次那张图 |
| 点「全部删除」没反应 | 系统弹的确认框被划掉了 | 再点一次，注意屏幕中间的「删除」按钮 |
| Actions 变红叉 | 代码有编译错误 | 截图报错发我 |
| Sideloadly 报 `Invalid anisette` | 本地验证组件出错 | 关掉重开，或换台电脑试 |
| 装完闪退 | 没信任开发者证书 | 见 5.4 |

---

## 八、代码结构（你不用看，留个底）

```
PhotoSwipe/
├── project.yml                      # 工程描述文件，GitHub 上用它生成 Xcode 工程
├── .github/workflows/build.yml      # 自动编译脚本
└── PhotoSwipe/
    ├── PhotoSwipeApp.swift          # 入口
    ├── Models/
    │   ├── SmartCategory.swift      # 分类定义（全部/自拍/截屏/实况/视频/全景/人像/喜欢）
    │   └── PendingStore.swift       # 待删队列（持久化）
    ├── Services/
    │   └── PhotoLibrary.swift       # 权限、取图、预取、批量删除
    └── Views/
        ├── RootView.swift           # 权限引导
        ├── CategoryGridView.swift   # 分类网格
        ├── SwipeViewerView.swift    # 全屏浏览（连续分页 + 上滑待删 + 下滑喜欢）
        ├── VideoPlayerView.swift    # 视频播放器
        └── TrashView.swift          # 待删列表
```

隐私：**所有处理都在手机本地完成，App 没有联网权限，不上传任何照片。**

## v1.1 更新说明

| 改动 | 说明 |
|---|---|
| 视频可播放 | 点视频卡片任意位置进入全屏播放，支持 iCloud 视频与静音开关下出声 |
| 新增「全部」 | 首页顶部横幅，按时间倒序浏览全库，不再只能按分类看 |
| 新增「自拍」 | 直接读取系统「自拍」智能相簿（`smartAlbumSelfPortraits`），和系统相册结果一致 |
| 连续滑动 | 左右滑动改为跟手分页：手指拖多少画面走多少，松手按速度吸附到上一张/下一张 |

> 注：分类现在统一从系统智能相簿读取（截屏、实况、视频、全景、人像、喜欢、自拍），
> 与系统「相簿」页里的那几本完全对应，不再靠自己写条件去猜。
