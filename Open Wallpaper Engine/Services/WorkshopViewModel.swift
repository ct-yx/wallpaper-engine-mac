import Foundation
import SwiftUI
import Combine

class WorkshopViewModel: ObservableObject {
    @Published var items: [WorkshopItem] = []
    @Published var searchText = ""
    @Published var sortOrder: WorkshopSortOrder = .trending
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTags: [String] = ["Everyone"]
    @Published private(set) var currentPage = 1
    @Published private(set) var hasMoreResults = true
    @Published var selectedItem: WorkshopItem?

    let steamCmd: SteamCmdService
    private let api = WorkshopAPIService()
    private var cancellable: AnyCancellable?
    private var searchGeneration = 0

    private let pageSize = 40

    static let contentRatingTags = ["Everyone", "Questionable", "Mature"]

    static let typeTags = ["Scene", "Video", "Web", "Application"]

    static let genreTags = [
        "Abstract", "Animal", "Anime", "Cartoon", "CGI",
        "Cyberpunk", "Fantasy", "Game", "Girls", "Guys",
        "Landscape", "Medieval", "Memes", "MMD", "Music",
        "Nature", "Pixel Art", "Relaxing", "Retro", "Sci-Fi",
        "Sports", "Technology", "Television", "Vehicle",
    ]

    static let resolutionTags = [
        "1920 x 1080", "2560 x 1440", "3840 x 2160",
        "3440 x 1440", "1440 x 2560",
    ]

    init(steamCmd: SteamCmdService) {
        self.steamCmd = steamCmd
        // Forward steamCmd changes (e.g. downloadProgress) to trigger view updates
        self.cancellable = steamCmd.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    @MainActor
    func search() async {
        searchGeneration += 1
        let generation = searchGeneration
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMoreResults = true
        items = []

        defer {
            if generation == searchGeneration {
                isLoading = false
            }
        }

        do {
            let results = try await api.searchItems(
                query: searchText,
                tags: selectedTags,
                sortOrder: sortOrder,
                page: currentPage,
                perPage: pageSize
            )
            guard generation == searchGeneration else { return }
            items = deduplicated(results)
            hasMoreResults = results.count >= pageSize
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadMore() async {
        guard !isLoading, hasMoreResults else { return }

        let generation = searchGeneration
        let nextPage = currentPage + 1
        isLoading = true

        defer {
            if generation == searchGeneration {
                isLoading = false
            }
        }

        do {
            let results = try await api.searchItems(
                query: searchText,
                tags: selectedTags,
                sortOrder: sortOrder,
                page: nextPage,
                perPage: pageSize
            )
            guard generation == searchGeneration else { return }
            currentPage = nextPage
            items = deduplicated(items + results)
            hasMoreResults = results.count >= pageSize
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadMoreIfNeeded(appearing item: WorkshopItem) async {
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func download(item: WorkshopItem) {
        steamCmd.downloadWorkshopItem(workshopId: item.id)
    }

    func downloadState(for item: WorkshopItem) -> SteamCmdService.DownloadState? {
        steamCmd.downloadProgress[item.id]
    }

    func isInstalled(_ item: WorkshopItem) -> Bool {
        let destination = FileManager.default.wallpapersDirectory.appending(path: item.id)
        return FileManager.default.fileExists(atPath: destination.path)
    }

    func hasCachedDownload(_ item: WorkshopItem) -> Bool {
        steamCmd.hasCachedWorkshopContent(workshopId: item.id)
    }

    func toggleTag(_ tag: String, in group: WorkshopTagGroup) {
        switch group {
        case .rating, .type:
            let groupTags = group.tags
            if selectedTags.contains(tag) {
                selectedTags.removeAll { $0 == tag }
            } else {
                selectedTags.removeAll { groupTags.contains($0) }
                selectedTags.append(tag)
            }
        case .genre:
            if selectedTags.contains(tag) {
                selectedTags.removeAll { $0 == tag }
            } else {
                selectedTags.append(tag)
            }
        }
    }

    func resetFilters() {
        selectedTags = ["Everyone"]
    }

    private func deduplicated(_ candidates: [WorkshopItem]) -> [WorkshopItem] {
        var ids = Set<String>()
        return candidates.filter { ids.insert($0.id).inserted }
    }
}

enum WorkshopTagGroup: CaseIterable, Identifiable, Hashable {
    case rating
    case type
    case genre

    var id: Self { self }

    var tags: [String] {
        switch self {
        case .rating:
            return WorkshopViewModel.contentRatingTags
        case .type:
            return WorkshopViewModel.typeTags
        case .genre:
            return WorkshopViewModel.genreTags
        }
    }
}
