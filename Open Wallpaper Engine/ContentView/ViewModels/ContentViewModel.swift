//
//  ContentViewModel.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import AVKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

class ContentViewModel: ObservableObject, DropDelegate {
    @AppStorage("SortingBy") var sortingBy: WEWallpaperSortingMethod = .name
    @AppStorage("SortingSequence") var sortingSequence: WEWallpaperSortingSequence = .increase
    
    @AppStorage("FRShowOnly")                   public var showOnly                     =                   FRShowOnly.all
    @AppStorage("FRType")                       public var type                         =                       FRType.all
    @AppStorage("FRAgeRating")                  public var ageRating                    =                  FRAgeRating.all
    @AppStorage("FRWidescreenResolution")       public var widescreenResolution         =       FRWidescreenResolution.all
    @AppStorage("FRUltraWidescreenResolution")  public var ultraWidescreenResolution    =  FRUltraWidescreenResolution.all
    @AppStorage("FRDualscreenResolution")       public var dualscreenResolution         =       FRDualscreenResolution.all
    @AppStorage("FRTriplescreenResolution")     public var triplescreenResolution       =     FRTriplescreenResolution.all
    @AppStorage("FRPortraitScreenResolution")   public var potraitscreenResolution      =   FRPortraitScreenResolution.all
    @AppStorage("FRMiscResolution")             public var miscResolution               =             FRMiscResolution.all
    @AppStorage("FRSource")                     public var source                       =                     FRSource.all
    @AppStorage("FRTag")                        public var tag                          =                        FRTag.all
    
    @AppStorage("FilterReveal") var isFilterReveal = false
    @AppStorage("WallpaperURLs") var wallpaperUrls = [URL]()
    @AppStorage("SelectedIndex") var selectedIndex = 0
    
    @AppStorage("ExplorerIconSize") var explorerIconSize: Double = 200
    
    @Published var isDisplaySettingsReveal = false
    @Published var importAlertPresented = false
    @Published var isStaging = false
    
    @Published var topTabBarSelection: Int = 0
    @Published var topTabBarHoverSelection: Int = -1
    
    @Published var imageScaleIndex: Int = -1
    
    @Published var wallpapers = [WEWallpaper]()
    
    @Published var isUnsafeWallpaperWarningPresented = false
    
    @Published var hoveredWallpaper: WEWallpaper?
    
    @Published var isUnsubscribeConfirming = false

    @Published var selectedWallpapers = Set<URL>()
    @Published var isBatchUnsubscribeConfirming = false

    lazy var steamCmd: SteamCmdService = {
        let svc = SteamCmdService()
        steamCmdCancellable = svc.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        return svc
    }()
    lazy var workshopVM: WorkshopViewModel = WorkshopViewModel(steamCmd: steamCmd)
    private var steamCmdCancellable: AnyCancellable?

    @Published var searchText = ""
    
    @AppStorage("WallpapersPerPage") var wallpapersPerPage: Int = 50
    
    var importAlertError: WPImportError? = nil
    
    convenience init(isStaging: Bool, topTabBarSelection: Int = 0) {
        self.init()
        
        let wallpapers = autoRefreshWallpapers
        
        self.isStaging = isStaging
        self.topTabBarSelection = topTabBarSelection
        self.wallpapers = wallpapers
    }
    
    /// current page index number is starting from '1'
    @Published public var currentPage: Int = 1
//    {
//        willSet {
//            self.currentPage = newValue > self.maxPage ? self.maxPage : newValue
//        }
//    }
    
    private var cachedResolutionOptions: [URL: Set<String>] = [:]

    private var urls: [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.wallpapersDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return contents
    }
    
    /// Show all the wallpaper inside application wallpaper directory, without being filtered
    private var allWallpapers: [WEWallpaper] {
        self.urls.map({ url in
            if let data = try? Data(contentsOf: url.appending(path: "project.json")), let project = try? JSONDecoder().decode(WEProject.self, from: data) {
                return WEWallpaper(using: project, where: url)
            } else {
                return WEWallpaper(using: .invalid, where: url)
            }
        })
    }
    
    private var searchedWallpapers: [WEWallpaper] {
        allWallpapers.filter { wallpaper in
            let project = wallpaper.project
            let searchText = searchText.lowercased()
            
            guard !searchText.isEmpty else { return true }
            
            guard !project.title.lowercased().contains(searchText) else { return true }
            
            guard !project.type.lowercased().contains(searchText) else { return true }
            
            if let description = project.description?.lowercased() {
                guard !description.contains(searchText) else { return true }
            }
            
            if let tags = project.tags {
                guard !tags.contains(where: { $0.lowercased().contains(searchText) })
                else { return true }
            }
            
            if let workshopid = project.workshopid {
                guard !workshopid.rawValue.contains(searchText) else { return true }
            }
            
            guard !wallpaper.wallpaperDirectory.lastPathComponent
                .lowercased()
                .contains(searchText) else { return true }
            
            return false
        }
    }
    
    private var filteredWallpapers: [WEWallpaper] {
        searchedWallpapers.filter { wallpaper in

            // `.all` is the persisted default and means no restriction;
            // `.none` is also used by Reset Filters to show every wallpaper.
            if self.showOnly != .none,
               self.showOnly != .all,
               self.showOnly.contains(.approved),
               wallpaper.project.approved != true {
                return false
            }
            
            // Type
            var type = FRType.none
            switch wallpaper.project.type.lowercased() {
            case "video":
                type = .video
            case "scene":
                type = .scene
            case "web":
                type = .web
            case "application":
                type = .application
            default:
                break
            }
            guard self.type.contains(type) else { return false }
            
            // 
            
            // Age Rating
            var ageRating: FRAgeRating
            switch wallpaper.project.contentrating {
            case "Everyone":
                ageRating = .everyone
            case "Questionable":
                ageRating = .partialNudity
            case "Mature":
                ageRating = .mature
            default:
                ageRating = .none
            }
            guard self.ageRating.contains(ageRating) else { return false }
            // Tags
            let wallpaperTags = mappedTags(for: wallpaper)
            guard !self.tag.intersection(wallpaperTags).isEmpty else { return false }

            // Resolution
            guard matchesResolutionFilter(for: wallpaper) else { return false }

            // Source
            guard self.source.contains(sourceOption(for: wallpaper)) else { return false }

            return true
        }
    }

    private func normalizedMetadataValue(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func mappedTag(for tag: String) -> FRTag? {
        switch normalizedMetadataValue(tag) {
        case "abstract": return .abstract
        case "animal": return .animal
        case "anime": return .anime
        case "cartoon": return .cartoon
        case "cgi": return .cgi
        case "cyberpunk": return .cyberpunk
        case "fantasy": return .fantasy
        case "game": return .game
        case "girls": return .girls
        case "guys": return .guys
        case "landscape": return .landscape
        case "medieval": return .medieval
        case "memes": return .memes
        case "mmd": return .mmd
        case "music": return .music
        case "nature": return .nature
        case "pixelart": return .pixelArt
        case "relaxing": return .relaxing
        case "retro": return .retro
        case "scifi": return .sciFi
        case "sports": return .sports
        case "technology": return .technology
        case "television": return .television
        case "vehicle": return .vehicle
        default: return nil
        }
    }

    private func mappedTags(for wallpaper: WEWallpaper) -> FRTag {
        guard let projectTags = wallpaper.project.tags else {
            return .unspecifiedGenre
        }

        let mappedTags = projectTags.compactMap { mappedTag(for: $0) }
        guard !mappedTags.isEmpty else { return .unspecifiedGenre }

        return mappedTags.reduce(into: FRTag.none) { result, tag in
            result.insert(tag)
        }
    }

    private func resolutionOptionName(for tag: String) -> String? {
        switch normalizedMetadataValue(tag) {
        case "standarddefinition", "sd": return "StandardDefinition"
        case "1280x720": return "1280x720"
        case "1920x1080", "1920x1080fullhd": return "1920x1080-FullHD"
        case "2560x1440": return "2560x1440"
        case "3840x2160", "3840x21604k": return "3840x2160-4K"
        case "ultrawidestandard", "ultrawide", "219": return "Ultrawide Standard"
        case "2560x1080": return "2560x1080"
        case "3440x1440": return "3440x1440"
        case "dualstandard", "dualmonitor": return "Dual Standard"
        case "3840x1080": return "3840x1080"
        case "5120x1440": return "5120x1440"
        case "7680x2160": return "7680x2160"
        case "triplestandard", "triplemonitor": return "Triple Standard"
        case "4096x768": return "4096x768"
        case "5760x1080": return "5760x1080"
        case "7680x1440": return "7680x1440"
        case "11520x2160": return "11520x2160"
        case "potraitstandard", "portraitstandard", "portrait": return "PotraitStandard"
        case "720x1280": return "720x1280"
        case "1080x1920": return "1080x1920"
        case "1440x2560": return "1440x2560"
        case "2160x3840": return "2160x3840"
        case "otherresolution", "other": return "OtherResolution"
        case "dynamicresolution", "dynamic": return "DynamicResolution"
        default: return nil
        }
    }

    private func wallpaperDimensions(for wallpaper: WEWallpaper) -> (width: Int, height: Int)? {
        let type = wallpaper.project.type.lowercased()
        if type == "web" || type == "application" {
            return nil
        }

        let mediaURL = wallpaper.wallpaperDirectory.appending(path: wallpaper.project.file)

        if type == "scene" {
            let sceneData: Data?
            if let data = try? Data(contentsOf: mediaURL) {
                sceneData = data
            } else {
                let packageName = (wallpaper.project.file as NSString).deletingPathExtension + ".pkg"
                let packageURL = wallpaper.wallpaperDirectory.appending(path: packageName)
                sceneData = (try? PKGParser(url: packageURL))?.extractFile(named: wallpaper.project.file)
            }

            if let sceneData,
               let scene = try? JSONDecoder().decode(WEScene.self, from: sceneData),
               let projection = scene.general.orthogonalprojection,
               projection.width > 0,
               projection.height > 0 {
                return (projection.width, projection.height)
            }
        }

        if type == "video" {
            let asset = AVAsset(url: mediaURL)
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                let width = Int(abs(size.width).rounded())
                let height = Int(abs(size.height).rounded())
                if width > 0, height > 0 {
                    return (width, height)
                }
            }
        }

        if let imageSource = CGImageSourceCreateWithURL(mediaURL as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0,
           height > 0 {
            return (width, height)
        }

        return nil
    }

    private func resolutionOptions(for width: Int, height: Int) -> Set<String> {
        let exactResolutions: [(Int, Int, String)] = [
            (1280, 720, "1280x720"),
            (1920, 1080, "1920x1080-FullHD"),
            (2560, 1440, "2560x1440"),
            (3840, 2160, "3840x2160-4K"),
            (2560, 1080, "2560x1080"),
            (3440, 1440, "3440x1440"),
            (3840, 1080, "3840x1080"),
            (5120, 1440, "5120x1440"),
            (7680, 2160, "7680x2160"),
            (4096, 768, "4096x768"),
            (5760, 1080, "5760x1080"),
            (7680, 1440, "7680x1440"),
            (11520, 2160, "11520x2160"),
            (720, 1280, "720x1280"),
            (1080, 1920, "1080x1920"),
            (1440, 2560, "1440x2560"),
            (2160, 3840, "2160x3840")
        ]

        if let exact = exactResolutions.first(where: { $0.0 == width && $0.1 == height }) {
            return [exact.2]
        }

        let ratio = Double(width) / Double(height)
        let isApproximately: (Double) -> Bool = { abs(ratio - $0) < 0.08 }

        if isApproximately(16.0 / 9.0) {
            return ["StandardDefinition"]
        }
        if isApproximately(21.0 / 9.0) {
            return ["Ultrawide Standard"]
        }
        if isApproximately(32.0 / 9.0) {
            return ["Dual Standard"]
        }
        if isApproximately(48.0 / 9.0) {
            return ["Triple Standard"]
        }
        if isApproximately(9.0 / 16.0) {
            return ["PotraitStandard"]
        }

        return ["OtherResolution"]
    }

    private func resolutionOptionNames(for wallpaper: WEWallpaper) -> Set<String> {
        let taggedOptions = Set((wallpaper.project.tags ?? []).compactMap { resolutionOptionName(for: $0) })
        if !taggedOptions.isEmpty {
            return taggedOptions
        }

        if let cachedOptions = cachedResolutionOptions[wallpaper.wallpaperDirectory] {
            return cachedOptions
        }

        let options: Set<String>
        if ["web", "application"].contains(wallpaper.project.type.lowercased()) {
            options = ["DynamicResolution"]
        } else if let dimensions = wallpaperDimensions(for: wallpaper) {
            options = resolutionOptions(for: dimensions.width, height: dimensions.height)
        } else {
            options = ["OtherResolution"]
        }

        cachedResolutionOptions[wallpaper.wallpaperDirectory] = options
        return options
    }

    private var hasUnrestrictedResolutionFilter: Bool {
        widescreenResolution == .all &&
        ultraWidescreenResolution == .all &&
        dualscreenResolution == .all &&
        triplescreenResolution == .all &&
        potraitscreenResolution == .all &&
        miscResolution == .all
    }

    private func matchesResolutionFilter(for wallpaper: WEWallpaper) -> Bool {
        guard !hasUnrestrictedResolutionFilter else { return true }
        let options = resolutionOptionNames(for: wallpaper)

        for (index, option) in FRWidescreenResolution.allOptions.enumerated()
        where options.contains(option) && widescreenResolution.contains(FRWidescreenResolution(rawValue: 1 << index)) {
            return true
        }
        for (index, option) in FRUltraWidescreenResolution.allOptions.enumerated()
        where options.contains(option) && ultraWidescreenResolution.contains(FRUltraWidescreenResolution(rawValue: 1 << index)) {
            return true
        }
        for (index, option) in FRDualscreenResolution.allOptions.enumerated()
        where options.contains(option) && dualscreenResolution.contains(FRDualscreenResolution(rawValue: 1 << index)) {
            return true
        }
        for (index, option) in FRTriplescreenResolution.allOptions.enumerated()
        where options.contains(option) && triplescreenResolution.contains(FRTriplescreenResolution(rawValue: 1 << index)) {
            return true
        }
        for (index, option) in FRPortraitScreenResolution.allOptions.enumerated()
        where options.contains(option) && potraitscreenResolution.contains(FRPortraitScreenResolution(rawValue: 1 << index)) {
            return true
        }
        for (index, option) in FRMiscResolution.allOptions.enumerated()
        where options.contains(option) && miscResolution.contains(FRMiscResolution(rawValue: 1 << index)) {
            return true
        }

        return false
    }

    private func sourceOption(for wallpaper: WEWallpaper) -> FRSource {
        if let visibility = wallpaper.project.visibility,
           ["official", "builtin", "bundled"].contains(normalizedMetadataValue(visibility)) {
            return .official
        }

        if let workshopID = wallpaper.project.workshopid,
           !workshopID.rawValue.isEmpty,
           workshopID.rawValue != "0" {
            return .workshop
        }

        return .myWallpapers
    }
    
    private func ordered(_ lhs: String, _ rhs: String) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        switch sortingSequence {
        case .increase:
            return comparison == .orderedAscending
        case .decrease:
            return comparison == .orderedDescending
        }
    }

    private func contentRatingRank(_ rating: String?) -> Int {
        switch rating?.lowercased() {
        case "everyone": return 0
        case "questionable": return 1
        case "mature": return 2
        default: return -1
        }
    }

    private var sortedWallpapers: [WEWallpaper] {
        let wallpapers = filteredWallpapers

        switch sortingBy {
        case .name:
            return wallpapers.sorted { ordered($0.project.title, $1.project.title) }
        case .rating:
            return wallpapers.sorted {
                let left = contentRatingRank($0.project.contentrating)
                let right = contentRatingRank($1.project.contentrating)
                if left == right {
                    return ordered($0.project.title, $1.project.title)
                }
                return sortingSequence == .increase ? left < right : left > right
            }
        case .fileSize:
            let sizes = Dictionary(uniqueKeysWithValues: wallpapers.map {
                ($0.wallpaperDirectory, $0.wallpaperSize)
            })
            return wallpapers.sorted {
                let left = sizes[$0.wallpaperDirectory] ?? 0
                let right = sizes[$1.wallpaperDirectory] ?? 0
                if left == right {
                    return ordered($0.project.title, $1.project.title)
                }
                return sortingSequence == .increase ? left < right : left > right
            }
        }
    }
    
    /// Provide wallpapers information for UI, being filtered by FilterResults and divided in pages
    public var autoRefreshWallpapers: [WEWallpaper] {
        let sortedWallpapers = self.sortedWallpapers
        let pageSize = max(1, wallpapersPerPage)
        guard !sortedWallpapers.isEmpty else { return [] }

        let pageCount = (sortedWallpapers.count + pageSize - 1) / pageSize
        let page = min(max(currentPage, 1), pageCount)
        let startIndex = (page - 1) * pageSize
        guard startIndex < sortedWallpapers.count else { return [] }

        let endIndex = min(startIndex + pageSize, sortedWallpapers.count)
        return Array(sortedWallpapers[startIndex..<endIndex])
    }
    
    /// Caculates the maximium possible page index for all wallpapers in your application wallpaper directory
    var maxPage: Int {
        let pageSize = max(1, wallpapersPerPage)
        guard !filteredWallpapers.isEmpty else { return 0 }
        return (filteredWallpapers.count + pageSize - 1) / pageSize
    }
    
    func toggleSelection(for wallpaper: WEWallpaper) {
        let url = wallpaper.wallpaperDirectory
        if selectedWallpapers.contains(url) {
            selectedWallpapers.remove(url)
        } else {
            selectedWallpapers.insert(url)
        }
    }

    func clearSelection() {
        selectedWallpapers.removeAll()
    }

    func isSelected(_ wallpaper: WEWallpaper) -> Bool {
        selectedWallpapers.contains(wallpaper.wallpaperDirectory)
    }

    func selectedWallpaperItems() -> [WEWallpaper] {
        sortedWallpapers.filter { selectedWallpapers.contains($0.wallpaperDirectory) }
    }

    func toggleFilter() {
        isFilterReveal.toggle()
    }
    
    func alertImportModal(which error: WPImportError) {
        self.importAlertError = error
        self.importAlertPresented = true
    }
    
    func warningUnsafeWallpaperModal(which wallpaper: WEWallpaper) {
        self.isUnsafeWallpaperWarningPresented = true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let proposal = DropProposal(operation: .copy)
        return proposal
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [UTType.fileURL]).first
        else {
            alertImportModal(which: .unkown)
            return false
        }
        itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                self?.alertImportModal(which: .unkown)
                return
            }
            // Do something with the file url
            // remember to dispatch on main in case of a @State change
            guard let wallpaper = try? FileWrapper(url: url)
            else{
                self?.alertImportModal(which: .unkown)
                return
            }
            
            if wallpaper.isDirectory {
                guard wallpaper.fileWrappers?["project.json"] != nil
                else{
                    self?.alertImportModal(which: .doesNotContainWallpaper)
                    return
                }
                DispatchQueue.main.async {
                    try? FileManager.default.copyItem(
                        at: url,
                        to: FileManager.default.wallpapersDirectory
                            .appending(path: url.lastPathComponent)
                    )
                }
            } else if wallpaper.isRegularFile, url.pathExtension.lowercased() == "zip" {
                DispatchQueue.main.async {
                    let count = ZipImporter.importZip(at: url)
                    if count == 0 {
                        self?.alertImportModal(which: .doesNotContainWallpaper)
                    }
                }
            } else if wallpaper.isRegularFile { // hello.mp4
                guard let filename = wallpaper.filename, [".mp4", ".mov"].contains(filename.suffix(4).lowercased()) else { return }
                
                let wallpaperDirectoryWrapper = FileWrapper(directoryWithFileWrappers: [filename: wallpaper])
                
                let projectData = WEProject(file: filename,
                                            preview: "preview.jpg",
                                            title: String(filename.prefix(filename.count - 4)),
                                            type: "video")
                
                // Generate a thumbnail (preview) image for importing video wallpaper
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                let time = CMTimeMake(value: 1, timescale: 1) // 第一帧的时间
                imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { (_, cgImage, _, _, error) in
                    if let error = error {
                        print(error)
                    } else if let cgImage = cgImage {
                        if let data = NSBitmapImageRep(cgImage: cgImage).representation(using: NSBitmapImageRep.FileType.jpeg, properties: [:]) {
                            wallpaperDirectoryWrapper.addRegularFile(withContents: data, preferredFilename: "preview.jpg")

                            guard let projectJSON = try? JSONEncoder().encode(projectData) else { return }
                            wallpaperDirectoryWrapper.addRegularFile(withContents: projectJSON, preferredFilename: "project.json")
                            
                            // Write to Work Directory
                            DispatchQueue.main.async {
                                do {
                                    try wallpaperDirectoryWrapper.write(
                                        to: FileManager.default.wallpapersDirectory.appending(path: String(filename.prefix(filename.count - 4))),
                                        originalContentsURL: nil)
                                } catch {
                                    print(error)
                                    return
                                }
                            }
                        }
                    }
                }
            }
        }
        return true
    }
    
    public func refresh() {
        cachedResolutionOptions.removeAll()
        self.wallpapers = autoRefreshWallpapers
    }
    
    /// Provide a filter reset to default function, usually being used to show all wallpapers without filtered
    public func reset() {
        self.showOnly                   = .none // notice it's show ONLY, it acts oppositely to the others
        self.type                       = .all
        self.ageRating                  = .all
        self.type                       = .all
        self.ageRating                  = .all
        self.widescreenResolution       = .all
        self.ultraWidescreenResolution  = .all
        self.dualscreenResolution       = .all
        self.triplescreenResolution     = .all
        self.potraitscreenResolution    = .all
        self.miscResolution             = .all
        self.source                     = .all
        self.tag                        = .all
    }
}

extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
