import Foundation
import Security

struct WorkshopItem: Identifiable, Codable {
    let id: String
    let title: String
    let previewURL: String?
    let tags: [String]
    let subscriptions: Int
    let fileSize: Int
    let creatorAppId: Int?
    let description: String?

    var previewImageURL: URL? {
        guard let urlString = previewURL else { return nil }
        return URL(string: urlString)
    }
}

enum WorkshopSortOrder: Int, CaseIterable, Identifiable {
    case trending = 0
    case mostRecent = 1
    case mostPopular = 2
    case mostSubscribed = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .trending: return String(localized: "Trending")
        case .mostRecent: return String(localized: "Most Recent")
        case .mostPopular: return String(localized: "Most Popular")
        case .mostSubscribed: return String(localized: "Most Subscribed")
        }
    }

    var queryType: Int {
        switch self {
        case .trending: return 3      // RankedByTrend
        case .mostRecent: return 1     // RankedByPublicationDate
        case .mostPopular: return 0    // RankedByVote
        case .mostSubscribed: return 9 // RankedByTotalUniqueSubscriptions
        }
    }

    /// When search_text is provided, Steam requires query_type=12 (RankedByTextSearch)
    func queryTypeForSearch(hasText: Bool) -> Int {
        hasText ? 12 : queryType
    }
}

class WorkshopAPIService {
    static let wallpaperEngineAppId = 431960

    /// Search workshop items using the public Steam API.
    /// GetPublishedFileDetails doesn't require an API key for basic queries.
    func searchItems(
        query: String = "",
        tags: [String] = [],
        sortOrder: WorkshopSortOrder = .trending,
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> [WorkshopItem] {
        // Use ISteamRemoteStorage/GetPublishedFileDetails for specific IDs
        // Use the public search endpoint for browsing
        var components = URLComponents(string: "https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/")!

        let hasSearchText = !query.isEmpty
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "query_type", value: "\(sortOrder.queryTypeForSearch(hasText: hasSearchText))"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "numperpage", value: "\(perPage)"),
            URLQueryItem(name: "appid", value: "\(Self.wallpaperEngineAppId)"),
            URLQueryItem(name: "return_tags", value: "true"),
            URLQueryItem(name: "return_previews", value: "true"),
            URLQueryItem(name: "return_metadata", value: "true"),
            URLQueryItem(name: "return_short_description", value: "true"),
        ]

        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "search_text", value: query))
        }

        for (index, tag) in tags.enumerated() {
            queryItems.append(URLQueryItem(name: "requiredtags[\(index)]", value: tag))
        }

        let apiKey = Self.loadAPIKey()
        guard !apiKey.isEmpty else {
            throw WorkshopAPIError.noAPIKey
        }
        queryItems.append(URLQueryItem(name: "key", value: apiKey))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw WorkshopAPIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkshopAPIError.requestFailed
        }

        if httpResponse.statusCode == 403 {
            throw WorkshopAPIError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw WorkshopAPIError.httpError(httpResponse.statusCode)
        }

        return try parseQueryResponse(data)
    }

    /// Get details for specific workshop items by their IDs.
    func getItemDetails(workshopIds: [String]) async throws -> [WorkshopItem] {
        let url = URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        var bodyParts = ["itemcount=\(workshopIds.count)"]
        for (index, id) in workshopIds.enumerated() {
            bodyParts.append("publishedfileids[\(index)]=\(id)")
        }
        request.httpBody = bodyParts.joined(separator: "&").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WorkshopAPIError.requestFailed
        }

        return try parseFileDetailsResponse(data)
    }

    // MARK: - API Key

    private static let apiKeyDefault = "SteamWebAPIKey"
    private static let keychainService = "Open Wallpaper Engine"
    private static let keychainAccount = "SteamWebAPIKey"

    static func loadAPIKey() -> String {
        if let keychainKey = loadKeychainAPIKey(), !keychainKey.isEmpty {
            // Remove the legacy copy once the Keychain copy is available.
            UserDefaults.standard.removeObject(forKey: apiKeyDefault)
            return keychainKey
        }

        // Migrate keys saved by older versions without breaking existing setups
        // if the Keychain is temporarily unavailable.
        guard let legacyKey = UserDefaults.standard.string(forKey: apiKeyDefault)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyKey.isEmpty else {
            return ""
        }

        if saveKeychainAPIKey(legacyKey) {
            UserDefaults.standard.removeObject(forKey: apiKeyDefault)
        }
        return legacyKey
    }

    static func saveAPIKey(_ key: String) {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            deleteKeychainAPIKey()
            UserDefaults.standard.removeObject(forKey: apiKeyDefault)
            return
        }

        if saveKeychainAPIKey(normalizedKey) {
            UserDefaults.standard.removeObject(forKey: apiKeyDefault)
        } else {
            // Keep the old storage path only as a last-resort fallback so a
            // transient Keychain failure does not discard a user's key.
            UserDefaults.standard.set(normalizedKey, forKey: apiKeyDefault)
        }
    }

    private static func keychainQuery(returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    private static func loadKeychainAPIKey() -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(
            keychainQuery(returningData: true) as CFDictionary,
            &result
        )
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private static func saveKeychainAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let query = keychainQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychainAPIKey() {
        _ = SecItemDelete(keychainQuery() as CFDictionary)
    }

    // MARK: - Response Parsing

    private func parseQueryResponse(_ data: Data) throws -> [WorkshopItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let files = response["publishedfiledetails"] as? [[String: Any]]
        else {
            return []
        }

        return files.compactMap { parseFileDict($0) }
    }

    private func parseFileDetailsResponse(_ data: Data) throws -> [WorkshopItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let files = response["publishedfiledetails"] as? [[String: Any]]
        else {
            return []
        }

        return files.compactMap { parseFileDict($0) }
    }

    private func parseFileDict(_ dict: [String: Any]) -> WorkshopItem? {
        guard let publishedFileId = dict["publishedfileid"] as? String,
              let title = dict["title"] as? String
        else { return nil }

        let previewURL = dict["preview_url"] as? String
        let tags: [String] = (dict["tags"] as? [[String: Any]])?.compactMap { $0["tag"] as? String } ?? []
        let subscriptions = dict["subscriptions"] as? Int ?? dict["lifetime_subscriptions"] as? Int ?? 0
        let fileSize = dict["file_size"] as? Int ?? 0
        let creatorAppId = dict["creator_app_id"] as? Int
        let description = dict["short_description"] as? String ?? dict["description"] as? String

        return WorkshopItem(
            id: publishedFileId,
            title: title,
            previewURL: previewURL,
            tags: tags,
            subscriptions: subscriptions,
            fileSize: fileSize,
            creatorAppId: creatorAppId,
            description: description
        )
    }
}

enum WorkshopAPIError: LocalizedError {
    case invalidURL
    case requestFailed
    case noAPIKey
    case invalidAPIKey
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid API URL")
        case .requestFailed:
            return String(localized: "API request failed — check your network connection")
        case .noAPIKey:
            return String(localized: "Steam Web API key required.\nGet a free key at steamcommunity.com/dev/apikey\nthen enter it below.")
        case .invalidAPIKey:
            return String(localized: "Invalid API key.\nGet a valid key at steamcommunity.com/dev/apikey")
        case .httpError(let code):
            return String(format: String(localized: "Steam API returned HTTP %d"), code)
        }
    }
}
