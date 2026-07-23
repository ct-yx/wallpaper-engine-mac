Open Wallpaper Engine（修補版）
=========

[English](README.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [日本語](README.ja.md)

[![GitHub license](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

基於 [Open Wallpaper Engine](https://github.com/MrWindDog/wallpaper-engine-mac) 的修補分支，為 macOS 加入場景桌布渲染與網頁桌布修復。

> **注意：** 本專案與 Steam 上的商業版 Wallpaper Engine 無關。這是一個開源的 macOS 應用程式，可顯示來自 Wallpaper Engine Steam 創意工坊的桌布素材。

## 專案網站

前往[專案網站](https://ct-yx.github.io/wallpaper-engine-mac/)查看螢幕截圖、功能介紹與最新下載。

## 預先編譯的發行版本

可從 [Releases](../../releases) 下載最新的 macOS 版本。發行封包採用 ad-hoc 簽署，不依賴會過期的 Personal Team 佈建描述檔；但未經 Apple 公證，首次開啟時 macOS 可能要求您在「隱私權與安全性」中確認開啟。

每個發行版本都提供 `.sha256` 檔案，可用來驗證下載的封包。

## 相關專案

- **[Open Wallpaper Engine for Linux](https://github.com/Unayung/simple-linux-wallpaperengine-gui)** — 基於 [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) 的 PyQt6 圖形介面，Steam 工作坊整合與 UI 設計移植自本 macOS 版本。

## 致謝

本專案建立於以下貢獻者的成果之上：

- **[MrWindDog](https://github.com/MrWindDog)** — 上游 [wallpaper-engine-mac](https://github.com/MrWindDog/wallpaper-engine-mac) 分支的維護者，新增功能與 UI 優化
- **[Haren Chen](https://github.com/haren724)** — [open-wallpaper-engine-mac](https://github.com/haren724/open-wallpaper-engine-mac) 原作者，建構核心架構（SwiftUI、影片桌布播放、匯入系統、播放清單 UI）
- **[ct-yx](https://github.com/ct-yx)** — 目前維護者與簡體中文在地化
- **[Klaus Zhu](https://github.com/klauszhu1105)** — 應用程式圖示
- **[Chen Chia Yang](https://github.com/Unayung)** — 場景桌布渲染、網頁桌布修復、Steam 創意工坊整合、多螢幕支援、Zip 匯入

採用 [GPL-3.0](LICENSE) 授權，與原始專案相同。

## 0.9.4 新功能

### 場景桌布的滑鼠相機視差

- **遵從桌布定義的視差** — 啟用 `cameraparallax` 的場景桌布現在會跟隨指標移動。渲染器會讀取來源的強度、延遲、滑鼠影響與每個物件的 `parallaxDepth`，相容於創意工坊常見的 `{"user":…, "value":…}` 包裝形式。
- **依圖層深度移動** — 圖像圖層與粒子發射器會從各自的初始位置，依獨立深度移動；粒子圖層保留上游的最小深度行為，確保可見位移。
- **不使用全域輸入鉤子** — 視差在 SpriteKit 的畫面迴圈內更新，並使用目前桌布視圖的視窗座標，不會額外註冊全域事件監聽器。

## 0.9.3 新功能

### 場景粒子與更可靠的下載

- **常見場景粒子開始渲染** — SpriteKit 現可渲染雨、雪、閃光等常見方形／球形發射器場景，對應粒子紋理、混合模式、產生範圍、生命週期、尺寸、速度、重力、透明度漸變、旋轉與常用執行個體覆寫，並限制異常粒子池。
- **修正場景座標** — 靜態影像圖層與粒子系統現會將 Wallpaper Engine 的左上角座標系轉換為 SpriteKit 的左下角座標系。
- **按需恢復快取工作階段** — 開啟下載設定頁會自動檢查已儲存的 SteamCMD 工作階段；搜尋和瀏覽創意工坊詳情仍不會啟動 SteamCMD。
- **可靠同步到桌布庫** — 下載會在支援的 SteamCMD 資料目錄中查找精確的創意工坊項目，避免永久卡住；之後透過暫存目錄取代本機桌布庫副本。

## 0.9.2 新功能

### 創意工坊存取與場景紋理

- **先瀏覽，下載時再設定** — 創意工坊搜尋、篩選、連續捲動和桌布詳細資料僅使用 Steam Web API；只在詳細資料頁選擇下載時才需要設定 SteamCMD 與 Steam 登入。
- **可靠的快取下載工作階段** — 開啟創意工坊不再啟動 SteamCMD。下載佇列會解析 Homebrew 符號連結，並重複使用同一份 SteamCMD 快取登入工作階段與創意工坊內容目錄。
- **DXT 場景紋理** — TEX 解析器現可讀取 TEXB mipmap，並以軟體解碼 DXT1/BC1、DXT3/BC2、DXT5/BC3 紋理，包括 LZ4 壓縮的 mipmap。

## 0.9.1 新功能

### 應用程式內更新

- **在應用程式中檢查** — 應用程式啟動後會檢查最新 GitHub Release；也可從「Open Wallpaper Engine > 檢查更新…」或「設定 > 一般 > 更新」手動檢查。
- **驗證後安裝** — 更新會下載 macOS ZIP 與 SHA-256 檔案、驗證封存檔雜湊及應用程式簽章；結束後替換可寫入的應用程式套件並重新啟動。

## 0.9.0 新功能

### 創意工坊瀏覽與詳細資料

- **可收合的篩選側欄** — 內容分級、桌布類型與風格標籤已移至左側直向側欄，小型視窗也可使用全部篩選條件。
- **桌布詳細資料頁** — 點擊任一創意工坊卡片，即可在下載前檢視預覽、標籤、說明、檔案大小與訂閱數；詳細資料頁提供創意工坊連結與下載按鈕。
- **無縫捲動瀏覽** — 每頁載入 40 項；捲動到網格末端會自動預先載入下一頁，並保留向下重新整理。
- **更可靠的 SteamCMD 工作階段** — SteamCMD 一律從安裝目錄執行以保留快取工作階段；下載會依序執行，複製至桌布庫不再佔用主執行緒。

### 新安裝預設值

新安裝會在失去焦點時暫停、其他應用程式全螢幕或顯示器休眠時停止、其他應用程式播放音訊時靜音；使用電池時持續執行，隨 macOS 啟動，並使用低於正常的程序優先權。

## 0.8.2 新功能

### 簡體中文支援

應用程式現已提供完整的簡體中文介面，包括創意工坊瀏覽器、Steam 登入與下載狀態、多螢幕控制、匯入錯誤提示和狀態列選單。可在「設定 > 一般」中選擇「簡體中文」；下次啟動應用程式時生效。

## 0.8.1 新功能

### 多螢幕支援
為每個連接的螢幕指定不同的桌布，並可個別啟用或停用。
- **顯示器設定面板** — 以視覺化佈局顯示所有連接的螢幕，點擊選取
- **個別螢幕桌布** — 每個螢幕可獨立顯示不同的桌布
- **啟用/停用切換** — 可針對每個螢幕開啟或關閉桌布
- **自動偵測** — 新連接的螢幕會自動偵測並啟用

### 多桌面支援
桌布現在可在所有 macOS 桌面（空間）上顯示並持續播放，切換桌面時不會中斷。

### 最近使用的桌布選單
可從狀態列選單快速切換桌布。最近使用的 10 個桌布可一鍵存取。

### 播放設定 — 已修復
效能播放設定（切換應用程式時暫停/靜音/停止）現在對所有桌布類型均可正常運作。

### Steam 創意工坊瀏覽器
直接在應用程式內瀏覽、搜尋及下載 Steam 創意工坊的桌布。
- **搜尋與篩選** — 依名稱搜尋，依內容分級（Everyone/Questionable/Mature）、類型（Scene/Video/Web）及風格標籤篩選
- **排序選項** — 熱門趨勢、最新發布、最受歡迎、最多訂閱
- **steamcmd 整合** — 自動偵測 steamcmd（Homebrew 或自訂路徑），未安裝時提供安裝指引
- **Steam 登入** — 支援密碼、Steam Guard 及快取 Session 驗證
- **下載進度顯示** — 即時狀態更新（驗證中、下載百分比、驗證、複製中）
- **安全預設** — 內容分級預設為「Everyone」，過濾成人內容

### Zip 匯入
直接匯入 `.zip` 桌布套件，無需手動解壓縮。支援 檔案 > 匯入 及拖放操作。

### 多選與批次取消訂閱
Cmd+點擊選取多個桌布，右鍵選擇批次取消訂閱。

### 桌布儲存隔離
桌布現在儲存在 `~/Documents/Open Wallpaper Engine/`，不再使用原始 Documents 目錄，避免克隆專案時出現「error」桌布。

## 修補內容

### 網頁桌布 — 修復灰色/空白渲染
基於 WebGL 的桌布因 `WKWebView` 阻擋本地檔案存取而顯示為灰色方塊。

**修復：** 在 WKWebView 設定中啟用 `allowFileAccessFromFileURLs` 和 `allowUniversalAccessFromFileURLs`，允許 WebGL 著色器載入本地紋理檔案。

### 場景桌布 — 從零開始實作
場景桌布（Steam 創意工坊最常見的類型）原本完全未實作——僅顯示「Hello, World!」。

**新實作包括：**
- **PKG 解析器** — 讀取 Wallpaper Engine 的 PKGV 封存格式，提取 scene.json、模型、材質和紋理
- **TEX 解析器** — 讀取 TEXV0005 紋理容器，提取 JPEG/PNG 圖片，並以軟體解碼 DXT1/DXT3/DXT5 mipmap
- **Scene JSON 解碼器** — 解析 scene.json，靈活處理多態欄位（值可為純類型或 `{"script":..,"value":..}` 物件）
- **SpriteKit 渲染器** — 將場景圖層渲染為 SKSpriteNode，正確處理定位、尺寸、透明度、色彩調整和混合模式
- **預覽回退** — 無法提取紋理時回退至 preview.jpg/png/gif
- **TEXI 格式偵測** — 讀取紋理格式與邏輯尺寸，以正確解析壓縮 mipmap

### 匯入 — 修復資料夾匯入
匯入面板現在可正確處理單一桌布資料夾和包含多個桌布的父目錄。

## 目前限制

- **粒子效果** — 已支援常見的 SpriteKit 相容發射器；進階粒子運算子、繩索／拖尾渲染器、控制點與動畫精靈圖仍為近似實作或尚未支援。
- **音訊互動腳本** — Wallpaper Engine 基於 JavaScript 的音訊視覺化腳本不會執行。帶腳本的屬性回退至靜態 `value`。
- **著色器效果** — 自定義 GLSL 著色器（泛光、模糊、色彩校正）未套用。
- **相機視差** — 已支援常見正交場景的滑鼠視差；透視相機移動與相機抖動尚未實作。
- **動畫場景** — 精靈動畫和基於時間軸的物件動畫不支援。
- **部分 JPEG 縮圖** — 少數 TEXB 格式 1 檔案包含 macOS 無法解碼的非標準 JPEG 資料。

## 支援的桌布類型

| 類型 | 狀態 |
|------|------|
| 影片 (.mp4, .webm) | 正常運作（原始） |
| 網頁 (HTML/WebGL) | 正常運作（已修補） |
| 場景（靜態圖片） | 正常運作（新功能） |
| 場景（粒子） | 部分支援（常見發射器） |
| 場景（DXT1/DXT3/DXT5 紋理） | 軟體解碼 |
| 應用程式 | 不支援 |

## 從原始碼建置

### 前置需求
- macOS >= 13.0
- Xcode >= 14.4
- Xcode Command Line Tools

### 步驟
```sh
git clone https://github.com/ct-yx/wallpaper-engine-mac.git
cd wallpaper-engine-mac
open "Open Wallpaper Engine.xcodeproj"
```

在 Xcode 中，將簽署憑證更改為您自己的或選擇「Sign to Run Locally」，然後按 `Cmd + R` 建置並執行。

## 使用方式

### 從 Steam 創意工坊瀏覽與下載

1. 切換到 **Workshop** 分頁，並在提示時輸入 [Steam Web API 金鑰](https://steamcommunity.com/dev/apikey)
2. 搜尋、篩選後開啟桌布卡片檢視詳細資料；此步驟不需要 SteamCMD 或 Steam 登入
3. 點擊 **Download** 後，再安裝 steamcmd（`brew install steamcmd`）或指定現有二進位檔，並以擁有 Wallpaper Engine 的 Steam 帳號登入
4. 後續排隊下載會重複使用快取的 SteamCMD 登入工作階段

### 從本地檔案匯入

- **資料夾：** 檔案 > 從資料夾匯入——選擇包含 `project.json` 的桌布資料夾
- **Zip：** 檔案 > 匯入 或拖放包含桌布套件的 `.zip` 檔案
- **手動：** 直接將桌布資料夾複製到 `~/Documents/Open Wallpaper Engine/`

## 變更的檔案（相對上游）

**修改：**
- `WebWallpaperView.swift` — WKWebView 檔案存取設定
- `WallpaperView.swift` — 場景桌布分派
- `SceneWallpaperView.swift` — 改寫為 SpriteKit NSViewRepresentable
- `ImportPanels.swift` — 資料夾匯入邏輯修復

**新增：**
- `Services/SceneParsers/PKGParser.swift` — PKGV 封存解析器
- `Services/SceneParsers/TEXParser.swift` — TEXV 紋理解析器
- `Services/SceneParsers/SceneModels.swift` — Scene JSON 資料模型
- `Services/SceneWallpaperViewModel.swift` — 場景載入與 SpriteKit 渲染
- `Services/SteamCmdService.swift` — steamcmd 偵測、登入與創意工坊下載
- `Services/WorkshopAPIService.swift` — Steam Web API 客戶端
- `Services/WorkshopViewModel.swift` — 創意工坊瀏覽器狀態管理
- `Services/WallpaperDirectory.swift` — 集中式桌布儲存路徑
- `Services/ZipImporter.swift` — Zip 檔案解壓與匯入
- `ContentView/Components/WorkshopView.swift` — 創意工坊瀏覽器 UI
