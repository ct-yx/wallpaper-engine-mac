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
- **TEX 解析器** — 读取 TEXV0005 纹理容器，从 TEXI/TEXB 分段提取 JPEG/PNG 图像数据
- **场景 JSON 解码器** — 灵活解析 scene.json 的多态字段（值可以是普通类型，也可以是 `{"script":..,"value":..}` 对象）
- **SpriteKit 渲染器** — 使用 SKSpriteNode 渲染场景图像图层，正确处理位置、尺寸、透明度、色调和混合模式
- **预览回退** — 无法提取纹理时回退至 preview.jpg/png/gif
- **TEXI 格式检测** — 快速识别并跳过无法解码的 DXT 压缩纹理

### 导入：修复文件夹导入

导入面板现在可正确识别单个壁纸文件夹，以及包含多个壁纸文件夹的父目录。

## 当前限制

- **DXT 纹理** — 使用 DXT1/DXT5 压缩纹理（TEXI 格式 4/7/8）的壁纸无法直接渲染。这些是 GPU 原生压缩格式，需要软件解压器或 Metal 渲染；应用会回退到预览图。
- **粒子效果** — 场景粒子系统（雨、雪、火花）虽可解析，但为避免视觉瑕疵暂未启用；粒子映射代码仍需进一步完善。
- **音频响应脚本** — 不执行 Wallpaper Engine 基于 JavaScript 的音频可视化脚本；带脚本的属性会回退到静态 `value`。
- **着色器效果** — 不应用自定义 GLSL 着色器（泛光、模糊、颜色校正）。
- **相机视差** — 尚未实现鼠标跟踪的相机移动。
- **动画场景** — 尚不支持精灵动画和基于时间轴的对象动画。
- **部分 JPEG 缩略图** — 少数 TEXB 格式 1 文件包含 macOS 无法解码的非标准 JPEG 数据，通常是被误识别为格式 1 的 DXT 压缩纹理。

## 支持的壁纸类型

| 类型 | 状态 |
|------|------|
| 视频（.mp4、.webm） | 可用（原有功能） |
| 网页（HTML/WebGL） | 可用（已修复） |
| 场景（静态图像） | 可用（新增） |
| 场景（粒子） | 部分支持（已禁用） |
| 场景（DXT 纹理） | 回退到预览图 |
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

1. 安装 steamcmd（`brew install steamcmd`），或在应用中指定已有二进制文件
2. 切换至 **创意工坊** 标签页，并使用拥有 Wallpaper Engine 的 Steam 帐号登录
3. 出现提示时输入 [Steam Web API 密钥](https://steamcommunity.com/dev/apikey)
4. 搜索、筛选后打开壁纸卡片，并在详情页点击 **下载**

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
