Open Wallpaper Engine（修补版）
=========

[English](README.md) | **简体中文** | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

[Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的 macOS 修补分支，加入场景壁纸渲染并修复网页壁纸。

> **注意：** 本项目与 Steam 上的商业版 Wallpaper Engine 没有任何关联。这是一款可显示 Wallpaper Engine Steam 创意工坊壁纸资源的开源 macOS 应用。

## 项目主页

前往[项目主页](https://ct-yx.github.io/wallpaper-engine-mac/)查看截图、功能亮点和最新下载。

## 预编译发行版

请从 [Releases](../../releases) 下载最新 macOS 构建。发行压缩包使用 ad-hoc 签名，不依赖会过期的 Personal Team 描述文件。它们尚未通过 Apple 公证，首次启动时 macOS 可能要求你在“隐私与安全性”中确认打开。

每个发行版都附带 `.sha256` 文件，用于校验下载的压缩包。

## 相关项目

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — 面向 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 的 PyQt6 图形界面，移植了本 macOS 版本的 Steam 创意工坊集成与 UI 设计。

## 致谢

本项目基于以下贡献者的成果构建：

- **[MrWindDog](https://github.com/MrWindDog)** — 上游 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 分支维护者，增加了新功能与 UI 改进
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) 原作者，构建了核心架构（SwiftUI、视频壁纸播放、导入系统和播放列表 UI）
- **[ct-yx](https://github.com/ct-yx)** — 当前维护者与简体中文本地化
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 应用图标
- **[Chen Chia Yang](https://github.com/Unayung)** — 场景壁纸渲染、网页壁纸修复、Steam 创意工坊集成、多显示器支持和 ZIP 导入

采用与原项目相同的 [GPL-3.0](LICENSE) 许可证。

## 0.9.8 新功能

### 场景变换与粒子生命周期一致性

- **粒子生命周期算子** — `sizechange`、`alphachange` 和 `colorchange` 现会遵循作者设定的生命周期区间，在区间前后保持对应值，并像 Linux 参考渲染器一样乘以初始尺寸、透明度或颜色。
- **嵌套场景变换** — 图像和粒子对象现会保留父级分组、源坐标原点、缩放、角度、可见性与对齐锚点，不再把所有图层扁平化到场景根节点。
- **灵活场景属性** — 变换、颜色、尺寸、透明度和可见性都支持 `{"value": ...}` 自定义包装；材质中显式带图片扩展名的纹理条目（如 `texture.png`）也可直接加载。

## 0.9.7 新功能

### 粒子动画纹理

- **TEXS 粒子开始动画** — 粒子材质现在会复用已解码的 TEXS 多图像/图集帧和 `.tex-json` 精灵图，而不再只显示第一帧。
- **遵从源动画模式** — 循环、`once` 和 `randomframe` 粒子模式会按作者设定的帧时长与 `sequencemultiplier` 速度调度。
- **SpriteKit 兼容回退** — SpriteKit 为每个发射器而不是每个存活粒子提供纹理时间轴，因此同一发射器内会共享帧选择；粒子运动、生命周期和既有发射器行为保持不变。

## 0.9.6 新功能

### SteamCMD 缓存与库目录可靠性

- **立即复用已下载内容** — 如果 SteamCMD 已下载某个创意工坊项目，详情页会直接导入缓存文件，不再启动另一个 SteamCMD 进程，也不要求先恢复登录会话。
- **发现全部已配置 Steam 库** — 除标准 macOS、Homebrew 和独立 SteamCMD 位置外，导入器还会读取 `libraryfolders.vdf`，因此能正确发现存放在第二个或外接 Steam 库中的内容。
- **继续使用原子导入** — 缓存内容和新下载内容均通过暂存目录替换，避免半复制的壁纸出现在本地库中。

## 0.9.5 新功能

### TEXS 场景动画纹理

- **支持多帧及图集 TEXS** — TEX 解析器现会遍历每个 TEXB 图像，并读取 TEXS0001/0002/0003 帧表，包括源图像索引、显示时长和图集裁剪区域。
- **精灵图元数据** — 静态 `materials/<texture>.tex-json` 精灵图序列也会在场景图像图层上播放；兼容两种常见的历史附属文件命名方式。
- **更多原生纹理格式** — 在 DXT1/DXT3/DXT5 以及内嵌 PNG/JPEG 之外，现可渲染原始 RGBA/RGB、RG88 和 R8 TEX mipmap。非视频 TEXB0004 容器会使用与上游 v3 兼容的 mipmap 布局。
- **已验证的二进制解析** — 图像、mipmap 和帧记录均有边界检查，并已使用合成的多图像 TEXS、图集 TEXS、附属元数据和原始 RGBA 夹具验证。

## 0.9.4 新功能

### 场景壁纸的鼠标相机视差

- **遵从壁纸定义的视差** — 启用 `cameraparallax` 的场景壁纸现会跟随指针移动。渲染器会读取源文件的强度、延迟、鼠标影响和每个对象的 `parallaxDepth`，兼容创意工坊常用的 `{"user":…, "value":…}` 包装形式。
- **按图层深度移动** — 图像图层和粒子发射器会从各自的初始位置按独立深度移动；粒子图层保留上游的最小深度行为，确保可见位移。
- **不使用全局输入钩子** — 视差在 SpriteKit 的帧循环内更新，并使用当前壁纸视图的窗口坐标，不会额外注册全局事件监听器。

## 0.9.3 新功能

### 场景粒子与更可靠的下载

- **常见场景粒子开始渲染** — SpriteKit 现可渲染雨、雪、火花等常见方形/球形发射器场景，映射粒子纹理、混合模式、生成范围、生命周期、尺寸、速度、重力、透明度渐变、旋转和常用实例覆盖，并限制异常粒子池。
- **修正场景坐标** — 静态图像图层和粒子系统现会将 Wallpaper Engine 的左上角坐标系转换为 SpriteKit 的左下角坐标系。
- **按需恢复缓存会话** — 打开下载配置页会自动检查已保存的 SteamCMD 会话；搜索和浏览创意工坊详情仍不会启动 SteamCMD。
- **可靠同步到壁纸库** — 下载会在支持的 SteamCMD 数据目录中查找精确的创意工坊项目，避免永久卡住；随后通过暂存目录替换本地壁纸库副本。

## 0.9.2 新功能

### 创意工坊访问与场景纹理

- **先浏览，下载时再配置** — 创意工坊搜索、筛选、连续滚动和壁纸详情仅使用 Steam Web API；只有在详情页选择下载时，才会要求配置 SteamCMD 和 Steam 登录。
- **可靠的缓存下载会话** — 打开创意工坊不再启动 SteamCMD。下载队列会先解析 Homebrew 符号链接，再复用同一个 SteamCMD 缓存登录会话和创意工坊内容目录。
- **DXT 场景纹理** — TEX 解析器现可读取 TEXB mipmap，并以软件方式解码 DXT1/BC1、DXT3/BC2、DXT5/BC3 纹理，包括 LZ4 压缩的 mipmap。

## 0.9.1 新功能

### 应用内更新

- **在应用内检查** — 应用启动后会检查最新 GitHub Release；也可通过“Open Wallpaper Engine > 检查更新…”或“设置 > 通用 > 更新”手动检查。
- **校验后安装** — 更新会下载 macOS ZIP 及其 SHA-256 文件，校验压缩包哈希与应用签名；退出后替换可写入的应用包，并重新启动新版本。

## 0.9.0 新功能

### 创意工坊浏览与详情

- **可收起的筛选侧栏** — 内容分级、壁纸类型和风格标签已移至左侧纵向侧栏；窗口较小时也能访问全部筛选项。
- **壁纸详情页** — 点击任意创意工坊卡片即可在下载前查看预览、标签、简介、文件大小和订阅数；详情页提供创意工坊链接与下载按钮。
- **无缝滚动浏览** — 每页加载 40 项；滚动到网格末尾会自动预加载下一页，并保留下拉刷新。
- **更可靠的 SteamCMD 会话** — SteamCMD 始终从安装目录运行以保留缓存会话；下载按顺序执行，复制到壁纸库不再占用主线程。

### 新安装默认设置

新安装会在失去焦点时暂停、其他应用全屏或显示器休眠时停止、其他应用播放音频时静音；使用电池时继续运行，随 macOS 启动，并使用低于正常的进程优先级。

## 0.8.2 新功能

### 简体中文支持

应用现已提供完整的简体中文界面，包括创意工坊浏览器、Steam 登录与下载状态、多显示器控制、导入错误提示和状态栏菜单。可在“设置 > 通用”中选择“简体中文”；下次启动应用时生效。

## 0.8.1 新功能

### 多显示器支持

可为每台已连接显示器设置不同壁纸，并单独控制启用状态。

- **显示器设置面板** — 直观展示全部显示器布局，点击即可选择
- **每屏独立壁纸** — 每台显示器可独立显示不同壁纸
- **启用/禁用开关** — 按显示器开启或关闭壁纸
- **自动检测** — 新接入的显示器会自动检测并启用

### 多桌面支持

壁纸会在所有 macOS 桌面空间（Spaces）中持续显示与播放，切换桌面不会中断。

### 最近壁纸菜单

可在状态栏菜单中快速切换壁纸，最近使用的 10 张壁纸支持一键访问。

### 播放设置修复

性能相关的播放设置（其他应用获得焦点时暂停、静音或停止）现已对所有壁纸类型正常生效。

### Steam 创意工坊浏览器

无需离开应用即可浏览、搜索和下载 Steam 创意工坊壁纸。

- **搜索与筛选** — 可按名称、内容分级（全年龄/敏感内容/成人内容）、类型（场景/视频/网页）和风格标签筛选
- **排序选项** — 热门、最新、最受欢迎、订阅最多
- **steamcmd 集成** — 自动检测 Homebrew 或自定义路径的 steamcmd；未安装时显示指引
- **Steam 登录** — 支持密码、Steam 令牌和缓存会话认证
- **下载进度** — 实时显示认证、下载百分比、校验和复制状态
- **安全默认值** — 内容分级默认设为“全年龄”，过滤成人内容

### ZIP 导入

可直接导入 `.zip` 壁纸包，无需手动解压。支持“文件 > 导入”和拖放。

### 多选与批量取消订阅

使用 Cmd+点按选择多个壁纸，再通过右键菜单批量取消订阅。

### 壁纸存储隔离

壁纸将存储在 `~/Documents/Open Wallpaper Engine/`，而不是 Documents 根目录；在全新机器克隆仓库时不会出现“error”壁纸。

## 修补内容

### 网页壁纸：修复灰色或空白渲染

基于 WebGL 的壁纸此前会显示为灰色矩形，因为 `WKWebView` 阻止了纹理和资源的本地文件访问。

**修复方式：** 在 `WKWebView` 配置中启用 `allowFileAccessFromFileURLs` 和 `allowUniversalAccessFromFileURLs`，让 WebGL 着色器可以加载本地纹理资源。

### 场景壁纸：从零实现

场景壁纸（Steam 创意工坊中最常见的类型）此前完全没有实现，只会显示“Hello, World!”。

**新增实现包括：**

- **PKG 解析器** — 读取 Wallpaper Engine 的 PKGV 存档格式，提取 scene.json、模型、材质和纹理
- **TEX 解析器** — 读取 TEXV0005 纹理容器，提取 JPEG/PNG 图像数据，并以软件方式解码 DXT1/DXT3/DXT5 mipmap
- **场景 JSON 解码器** — 灵活解析 scene.json 的多态字段（值可以是普通类型，也可以是 `{"script":..,"value":..}` 对象）
- **SpriteKit 渲染器** — 使用 SKSpriteNode 渲染场景图像图层，正确处理位置、尺寸、透明度、色调和混合模式
- **预览回退** — 无法提取纹理时回退至 preview.jpg/png/gif
- **TEXI 格式检测** — 读取纹理格式和逻辑尺寸，以正确解析压缩 mipmap

### 导入：修复文件夹导入

导入面板现在可正确识别单个壁纸文件夹，以及包含多个壁纸文件夹的父目录。

## 当前限制

- **粒子效果** — 已支持常见的 SpriteKit 兼容发射器和共享 TEXS/精灵图纹理动画；高级粒子算子、绳索/拖尾渲染器、控制点及按粒子选择帧仍为近似实现或暂未支持。
- **音频响应脚本** — 不执行 Wallpaper Engine 基于 JavaScript 的音频可视化脚本；带脚本的属性会回退到静态 `value`。
- **着色器效果** — 不应用自定义 GLSL 着色器（泛光、模糊、颜色校正）。
- **相机视差** — 已支持常见正交场景的鼠标视差；透视相机移动和相机抖动尚未实现。
- **动画场景** — 已支持场景图像和粒子图层上的 TEXS 多图像/图集动画与 `.tex-json` 精灵图；按粒子选择帧以及时间轴/脚本驱动的对象动画尚未实现。
- **部分 JPEG 缩略图** — 少数 TEXB 格式 1 文件包含 macOS 无法解码的非标准 JPEG 数据，通常是被误识别为格式 1 的 DXT 压缩纹理。

## 支持的壁纸类型

| 类型 | 状态 |
|------|------|
| 视频（.mp4、.webm） | 可用（原有功能） |
| 网页（HTML/WebGL） | 可用（已修复） |
| 场景（静态图像） | 可用（新增） |
| 场景（粒子） | 部分支持（常见发射器） |
| 场景（DXT1/DXT3/DXT5 纹理） | 软件解码 |
| 应用程序 | 不支持 |

## 从源码构建

### 前置条件

- macOS >= 13.0
- Xcode >= 14.4
- Xcode Command Line Tools

### 步骤

```sh
git clone https://github.com/ct-yx/wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "Open Wallpaper Engine.xcodeproj"
```

在 Xcode 中将签名证书改为你自己的证书，或选择“Sign to Run Locally”，然后按 `Cmd + R` 构建并运行。

## 使用方法

### 浏览和下载 Steam 创意工坊壁纸

1. 切换至 **创意工坊** 标签页，并在提示时输入 [Steam Web API 密钥](https://steamcommunity.com/dev/apikey)
2. 搜索、筛选并打开壁纸卡片查看详情；此步骤不需要 SteamCMD 或 Steam 登录
3. 点击 **下载** 后，再安装 steamcmd（`brew install steamcmd`）或选择已有二进制文件，并使用拥有 Wallpaper Engine 的 Steam 帐号登录
4. 后续排队下载会复用缓存的 SteamCMD 登录会话

### 从本地文件导入

- **文件夹：** 选择“文件 > 从文件夹导入”，然后选择包含 `project.json` 的壁纸文件夹
- **ZIP：** 选择“文件 > 导入”，或直接拖放包含壁纸包的 `.zip` 文件
- **手动：** 直接将壁纸文件夹复制到 `~/Documents/Open Wallpaper Engine/`

## 相较上游的文件改动

**已修改：**

- `WebWallpaperView.swift` — WKWebView 本地文件访问配置
- `WallpaperView.swift` — 场景壁纸分发
- `SceneWallpaperView.swift` — 重写为 SpriteKit 的 NSViewRepresentable
- `ImportPanels.swift` — 文件夹导入逻辑修复

**已新增：**

- `Services/SceneParsers/PKGParser.swift` — PKGV 存档解析器
- `Services/SceneParsers/TEXParser.swift` — TEX 纹理解析器
- `Services/SceneParsers/SceneModels.swift` — 场景 JSON 数据模型
- `Services/SceneWallpaperViewModel.swift` — 场景加载与 SpriteKit 渲染
- `Services/SteamCmdService.swift` — steamcmd 检测、登录和创意工坊下载
- `Services/WorkshopAPIService.swift` — Steam Web API 创意工坊客户端
- `Services/WorkshopViewModel.swift` — 创意工坊浏览器状态管理
- `Services/WallpaperDirectory.swift` — 集中的壁纸存储路径
- `Services/ZipImporter.swift` — ZIP 文件解压与导入
- `ContentView/Components/WorkshopView.swift` — 创意工坊浏览器 UI
