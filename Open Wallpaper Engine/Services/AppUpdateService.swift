//
//  AppUpdateService.swift
//  Open Wallpaper Engine
//
//  Checks GitHub Releases, verifies the published archive, and replaces a
//  writable app bundle after the current process exits.
//

import Cocoa
import Combine
import CryptoKit
import Foundation

@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    struct Release: Equatable {
        let version: String
        let archiveURL: URL
        let checksumURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var availableRelease: Release?
    @Published private(set) var lastChecked: Date?
    /// Keep the child process alive until this app exits and the replacement runs.
    private var installer: Process?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            return String(localized: "Updates have not been checked yet.")
        case .checking:
            return String(localized: "Checking for updates…")
        case .upToDate:
            return String(localized: "You're up to date.")
        case .available:
            if let availableRelease {
                return String(format: String(localized: "Version %@ is available."), availableRelease.version)
            }
            return String(localized: "An update is available.")
        case .downloading:
            return String(localized: "Downloading and verifying update…")
        case .installing:
            return String(localized: "Installing update and restarting…")
        case .failed(let message):
            return message
        }
    }

    func checkForUpdates() async {
        guard !isBusy else { return }

        state = .checking
        availableRelease = nil

        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()

            if isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release
                state = .available
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall() async {
        guard let release = availableRelease, !isBusy else { return }

        state = .downloading

        do {
            let archiveURL = try await downloadVerifiedArchive(for: release)
            let appURL = try await unpackAndVerifyApp(from: archiveURL, version: release.version)
            try scheduleInstallation(of: appURL)
            state = .installing
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Release lookup

    private func fetchLatestRelease() async throws -> Release {
        let endpoint = URL(string: "https://api.github.com/repos/ct-yx/wallpaper-engine-mac/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Open-Wallpaper-Engine/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.requestFailed
        }

        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        let normalizedVersion = normalizedVersion(payload.tagName)
        guard !normalizedVersion.isEmpty,
              let archive = payload.assets.first(where: { $0.name.hasSuffix("-macOS.zip") }),
              let checksum = payload.assets.first(where: { $0.name == "\(archive.name).sha256" }) else {
            throw UpdateError.incompleteRelease
        }

        return Release(
            version: normalizedVersion,
            archiveURL: archive.downloadURL,
            checksumURL: checksum.downloadURL,
            pageURL: payload.pageURL
        )
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = normalizedVersion(lhs).split(separator: ".").map { Int($0) ?? 0 }
        let right = normalizedVersion(rhs).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let lhsComponent = index < left.count ? left[index] : 0
            let rhsComponent = index < right.count ? right[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent > rhsComponent
            }
        }
        return false
    }

    private func normalizedVersion(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? ""
    }

    // MARK: - Download and verification

    private func downloadVerifiedArchive(for release: Release) async throws -> URL {
        var archiveRequest = URLRequest(url: release.archiveURL)
        archiveRequest.setValue("Open-Wallpaper-Engine/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (temporaryArchiveURL, archiveResponse) = try await URLSession.shared.download(for: archiveRequest)
        guard let response = archiveResponse as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }

        var checksumRequest = URLRequest(url: release.checksumURL)
        checksumRequest.setValue("Open-Wallpaper-Engine/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (checksumData, checksumResponse) = try await URLSession.shared.data(for: checksumRequest)
        guard let response = checksumResponse as? HTTPURLResponse,
              response.statusCode == 200,
              let expectedHash = String(data: checksumData, encoding: .utf8)?
                .split(whereSeparator: { $0.isWhitespace })
                .first
                .lowercased(),
              expectedHash.count == 64 else {
            throw UpdateError.invalidChecksum
        }

        let updatesDirectory = try updateDirectory()
        let archiveURL = updatesDirectory.appending(path: "Open-Wallpaper-Engine-v\(release.version)-macOS.zip")
        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.copyItem(at: temporaryArchiveURL, to: archiveURL)

        let archiveData = try Data(contentsOf: archiveURL)
        let actualHash = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else {
            try? FileManager.default.removeItem(at: archiveURL)
            throw UpdateError.checksumMismatch
        }

        return archiveURL
    }

    private func unpackAndVerifyApp(from archiveURL: URL, version: String) async throws -> URL {
        let directory = try updateDirectory().appending(path: "v\(version)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try await runTool("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, directory.path])

        guard let appURL = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.invalidArchive
        }

        try await runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        return appURL
    }

    // MARK: - Installation

    private func scheduleInstallation(of replacementAppURL: URL) throws {
        let targetAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard targetAppURL.pathExtension == "app" else {
            throw UpdateError.invalidInstallationTarget
        }

        let parentDirectory = targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([replacementAppURL])
            throw UpdateError.installationPermission
        }

        let token = UUID().uuidString
        let stagingAppURL = parentDirectory.appending(path: ".Open-Wallpaper-Engine-update-\(token).app")
        let backupAppURL = parentDirectory.appending(path: ".Open-Wallpaper-Engine-backup-\(token).app")
        let scriptURL = try updateDirectory().appending(path: "install-\(token).sh")
        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/sh
        set -eu
        TARGET="$1"
        SOURCE="$2"
        STAGING="$3"
        BACKUP="$4"
        PID="$5"

        while kill -0 "$PID" 2>/dev/null; do
          /bin/sleep 1
        done

        /usr/bin/ditto "$SOURCE" "$STAGING"
        /bin/mv "$TARGET" "$BACKUP"
        /bin/mv "$STAGING" "$TARGET"
        /usr/bin/open "$TARGET"
        /bin/rm -rf "$BACKUP" "$SOURCE" "$0"
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/sh")
        installer.arguments = [
            scriptURL.path,
            targetAppURL.path,
            replacementAppURL.path,
            stagingAppURL.path,
            backupAppURL.path,
            "\(currentProcessID)",
        ]
        try installer.run()
        self.installer = installer
    }

    private func updateDirectory() throws -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = applicationSupport
            .appending(path: "Open Wallpaper Engine", directoryHint: .isDirectory)
            .appending(path: "Updates", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runTool(_ executablePath: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.toolFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension AppUpdateService {
    struct ReleasePayload: Decodable {
        let tagName: String
        let pageURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
            case assets
        }
    }

    struct Asset: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    enum UpdateError: LocalizedError {
        case requestFailed
        case incompleteRelease
        case downloadFailed
        case invalidChecksum
        case checksumMismatch
        case invalidArchive
        case invalidInstallationTarget
        case installationPermission
        case toolFailed

        var errorDescription: String? {
            switch self {
            case .requestFailed:
                return String(localized: "Unable to check for updates right now.")
            case .incompleteRelease:
                return String(localized: "The latest release is missing a macOS update package.")
            case .downloadFailed:
                return String(localized: "The update download failed.")
            case .invalidChecksum:
                return String(localized: "The update checksum file is invalid.")
            case .checksumMismatch:
                return String(localized: "The downloaded update did not pass its checksum verification.")
            case .invalidArchive:
                return String(localized: "The downloaded update archive is invalid.")
            case .invalidInstallationTarget:
                return String(localized: "This copy of the app cannot be updated automatically.")
            case .installationPermission:
                return String(localized: "The updated app was downloaded, but this app folder is not writable. Move the app to a writable folder and try again.")
            case .toolFailed:
                return String(localized: "The update could not be prepared for installation.")
            }
        }
    }
}
