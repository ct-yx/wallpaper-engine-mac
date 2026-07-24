import Foundation
import Combine

class SteamCmdService: ObservableObject {
    @Published var steamCmdPath: String?
    @Published var isLoggedIn = false
    @Published var steamUsername: String = ""
    @Published var loginError: String?
    @Published var isLoggingIn = false
    @Published var downloadProgress: [String: DownloadState] = [:]

    enum DownloadState: Equatable {
        case downloading(status: String)
        case completed
        case requiresLogin(String)
        case failed(String)
    }

    private static let lastUsernameKey = "SteamLastUsername"
    private static let cachedSessionKey = "SteamCachedSessionLikelyAvailable"
    private let downloadQueue = DispatchQueue(label: "steamcmd.download.queue", qos: .userInitiated)
    private let maximumDownloadDuration: TimeInterval = 30 * 60

    init() {
        steamUsername = UserDefaults.standard.string(forKey: Self.lastUsernameKey) ?? ""
        detectSteamCmd()
    }

    /// Run a steamcmd process with proper pipe handling to avoid deadlocks.
    /// Reads stdout/stderr concurrently with process execution and applies a timeout.
    private func runSteamCmd(
        arguments: [String],
        input: String? = nil,
        timeout: TimeInterval = 30
    ) -> (output: String, exitCode: Int32) {
        guard let cmdPath = steamCmdPath else { return ("", -1) }

        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        process.executableURL = steamCmdExecutableURL(cmdPath: cmdPath)
        // Always run the executable from its own directory so standalone
        // scripts and Homebrew wrappers can find their bundled libraries.
        // SteamCMD itself persists account data in the user's Steam support
        // directory, independently of this working directory.
        process.currentDirectoryURL = steamCmdWorkingDirectory(cmdPath: cmdPath)
        process.arguments = arguments
        if let inputPipe {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Read pipe concurrently to prevent buffer deadlock
        var outputData = Data()
        let readQueue = DispatchQueue(label: "steamcmd.pipe.read")
        let handle = outputPipe.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty {
                readQueue.sync { outputData.append(data) }
            }
        }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            return (String(format: String(localized: "Failed to run steamcmd: %@"), error.localizedDescription), -1)
        }

        if let input,
           let inputData = input.data(using: .utf8),
           let inputPipe {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: inputData)
            } catch {
                // The process may have exited before consuming stdin.
            }
            inputPipe.fileHandleForWriting.closeFile()
        }

        // Wait with timeout
        let deadline = DispatchTime.now() + timeout
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        if waitGroup.wait(timeout: deadline) == .timedOut {
            process.terminate()
            handle.readabilityHandler = nil
            return (String(format: String(localized: "steamcmd timed out after %d s"), Int(timeout)), -1)
        }

        handle.readabilityHandler = nil
        // Read any remaining data
        let remaining = handle.readDataToEndOfFile()
        readQueue.sync { outputData.append(remaining) }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    private func setDetectedSteamCmdPath(_ path: String) {
        steamCmdPath = path
    }

    func detectSteamCmd() {
        // Check user-configured path first
        if let customPath = UserDefaults.standard.string(forKey: "SteamCmdPath"),
           FileManager.default.isExecutableFile(atPath: customPath) {
            setDetectedSteamCmdPath(customPath)
            return
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let searchPaths = [
            // Homebrew / system installs
            "/usr/local/bin/steamcmd",
            "/opt/homebrew/bin/steamcmd",
            "/usr/bin/steamcmd",
            // Steam client / SDK locations
            "\(homeDir)/Library/Application Support/Steam/steamcmd",
            "\(homeDir)/Library/Application Support/Steam/steamcmd/steamcmd",
            "\(homeDir)/Library/Application Support/Steam/steamcmd.sh",
            // Standalone SteamCMD package (common extract locations)
            "\(homeDir)/steamcmd/steamcmd.sh",
            "\(homeDir)/steamcmd/steamcmd",
            "\(homeDir)/Downloads/steamcmd/steamcmd.sh",
            "\(homeDir)/Downloads/steamcmd/steamcmd",
            "/Applications/steamcmd/steamcmd.sh",
            "/Applications/steamcmd/steamcmd",
            "\(homeDir)/Projects/SteamSDK/tools/ContentBuilder/builder_osx/steamcmd",
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                setDetectedSteamCmdPath(path)
                return
            }
        }

        // Try `which` as fallback — run on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["steamcmd"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    DispatchQueue.main.async {
                        self?.setDetectedSteamCmdPath(path)
                    }
                }
            }
        }
    }

    var isInstalled: Bool { steamCmdPath != nil }

    /// Browsing uses the Web API; downloads need SteamCMD plus either a
    /// verified session from this launch or a stored session from a prior
    /// successful login.  The latter is checked only by the actual download
    /// command, so opening a detail page never starts SteamCMD.
    var isReadyForDownloads: Bool { isInstalled && (isLoggedIn || hasSavedSessionForDownloads) }

    var hasSavedSessionForDownloads: Bool {
        guard isInstalled, !steamUsername.isEmpty else { return false }
        let defaults = UserDefaults.standard
        // Existing installs only have the username key. Treat that as a
        // migration candidate once, then record subsequent verification.
        guard defaults.object(forKey: Self.cachedSessionKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.cachedSessionKey)
    }

    @Published var pathError: String?

    func setCustomPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            pathError = String(localized: "File not found at selected path.")
            return
        }
        // Make executable if needed (e.g. steamcmd.sh from Steam package)
        if !FileManager.default.isExecutableFile(atPath: path) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: path
            )
        }
        pathError = nil
        UserDefaults.standard.set(path, forKey: "SteamCmdPath")
        isLoggedIn = false
        steamCmdPath = path
    }

    /// Attempt login with username and password. Steam Guard code is optional.
    func login(username: String, password: String, guardCode: String? = nil) {
        guard steamCmdPath != nil else { return }

        isLoggingIn = true
        loginError = nil
        steamUsername = username

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Keep the password and Steam Guard code out of the process list.
            // steamcmd accepts these responses through its interactive stdin.
            let args = ["+login", username]
            var input = password + "\n"
            if let code = guardCode, !code.isEmpty {
                input += code + "\n"
            }
            input += "+quit\n"

            let (output, exitCode) = self.runSteamCmd(arguments: args, input: input, timeout: 60)

            DispatchQueue.main.async {
                self.isLoggingIn = false
                if self.authenticationSucceeded(output: output, exitCode: exitCode) {
                    self.isLoggedIn = true
                    self.loginError = nil
                    self.recordCachedSession(username: username, isAvailable: true)
                } else if self.outputRequiresSteamGuard(output) {
                    self.recordCachedSession(username: username, isAvailable: false)
                    self.loginError = String(localized: "Steam Guard code required")
                } else if output.contains("Invalid Password") || output.contains("FAILED") {
                    self.recordCachedSession(username: username, isAvailable: false)
                    self.loginError = String(localized: "Invalid username or password")
                } else {
                    self.recordCachedSession(username: username, isAvailable: false)
                    self.loginError = String(localized: "Login failed. Check credentials and try again.")
                }
            }
        }
    }

    /// Try login with cached session (no password needed if previously authenticated).
    func loginWithCachedSession(username: String) {
        guard steamCmdPath != nil else { return }

        isLoggingIn = true
        loginError = nil
        steamUsername = username

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let (output, exitCode) = self.runSteamCmd(arguments: ["+login", username, "+quit"], timeout: 30)

            DispatchQueue.main.async {
                self.isLoggingIn = false
                if self.authenticationSucceeded(output: output, exitCode: exitCode) {
                    self.isLoggedIn = true
                    self.loginError = nil
                    self.recordCachedSession(username: username, isAvailable: true)
                } else {
                    self.isLoggedIn = false
                    self.recordCachedSession(username: username, isAvailable: false)
                    self.loginError = String(localized: "Cached session expired. Please log in with password.")
                }
            }
        }
    }

    /// Download a workshop item by its ID.
    func downloadWorkshopItem(workshopId: String) {
        guard let cmdPath = steamCmdPath else {
            downloadProgress[workshopId] = .failed(String(localized: "SteamCMD is required to download wallpapers."))
            return
        }

        downloadProgress[workshopId] = .downloading(status: String(localized: "Queued"))
        let username = steamUsername
        let canUseSavedSession = isLoggedIn || hasSavedSessionForDownloads

        downloadQueue.async { [weak self] in
            guard let self = self else { return }

            // A prior SteamCMD invocation may already have finished writing
            // this item when the app was relaunched or interrupted before the
            // library copy.  Reuse it immediately instead of starting the
            // SteamCMD bootstrap process again.
            if let sourceDir = self.findWorkshopContentDirectory(
                workshopId: workshopId,
                cmdPath: cmdPath
            ) {
                self.importWorkshopContent(at: sourceDir, workshopId: workshopId)
                return
            }

            guard canUseSavedSession, !username.isEmpty else {
                DispatchQueue.main.async {
                    self.downloadProgress[workshopId] = .requiresLogin(
                        String(localized: "Log in to Steam before downloading wallpapers.")
                    )
                }
                return
            }

            DispatchQueue.main.async {
                self.downloadProgress[workshopId] = .downloading(status: String(localized: "Starting steamcmd..."))
            }

            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = self.steamCmdExecutableURL(cmdPath: cmdPath)
            process.currentDirectoryURL = self.steamCmdWorkingDirectory(cmdPath: cmdPath)
            process.arguments = [
                "+login", username,
                "+workshop_download_item", "431960", workshopId, "validate",
                "+quit"
            ]
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            // Read output in real-time for progress updates
            var fullOutput = ""
            let outputLock = NSLock()
            let handle = outputPipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                outputLock.lock()
                fullOutput += line
                outputLock.unlock()

                let status = self?.parseProgress(line) ?? nil
                if let status = status {
                    DispatchQueue.main.async {
                        self?.downloadProgress[workshopId] = .downloading(status: status)
                    }
                }
            }

            do {
                try process.run()
                let waitGroup = DispatchGroup()
                waitGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    waitGroup.leave()
                }

                if waitGroup.wait(timeout: .now() + self.maximumDownloadDuration) == .timedOut {
                    process.terminate()
                    process.waitUntilExit()
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async {
                        self.downloadProgress[workshopId] = .failed(
                            String(localized: "steamcmd timed out while downloading this wallpaper.")
                        )
                    }
                    return
                }
            } catch {
                handle.readabilityHandler = nil
                DispatchQueue.main.async {
                    self.downloadProgress[workshopId] = .failed(
                        String(format: String(localized: "steamcmd failed to run: %@"), error.localizedDescription)
                    )
                }
                return
            }

            handle.readabilityHandler = nil
            // Read any remaining data
            let remaining = handle.readDataToEndOfFile()
            outputLock.lock()
            if let str = String(data: remaining, encoding: .utf8) { fullOutput += str }
            let output = fullOutput
            outputLock.unlock()

            let exitCode = process.terminationStatus

            // SteamCMD installations do not all use the same steamapps
            // directory.  In particular Homebrew's executable is often a
            // symlink while its workshop content lives under the user's Steam
            // support directory.  Search the exact item in every supported
            // location instead of accepting the first existing steamapps dir.
            if let sourceDir = self.findWorkshopContentDirectory(
                workshopId: workshopId,
                cmdPath: cmdPath
            ) {
                self.importWorkshopContent(at: sourceDir, workshopId: workshopId)
                return
            }

            if self.outputIndicatesLoginFailure(output) {
                DispatchQueue.main.async {
                    self.isLoggedIn = false
                    self.recordCachedSession(username: username, isAvailable: false)
                    self.downloadProgress[workshopId] = .requiresLogin(
                        String(localized: "Cached session expired. Please log in with password.")
                    )
                }
                return
            }

            let failure: String
            if output.contains("ERROR") || output.contains("FAILED") {
                failure = output.components(separatedBy: "\n")
                    .first(where: { $0.contains("ERROR") || $0.contains("FAILED") })
                    ?? String(localized: "Unknown error")
            } else if exitCode != 0 {
                failure = String(format: String(localized: "Exit code %d"), exitCode)
            } else {
                failure = String(localized: "Files not found at expected path")
            }
            DispatchQueue.main.async {
                self.downloadProgress[workshopId] = .failed(failure)
            }
        }
    }

    private func recordCachedSession(username: String, isAvailable: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(username, forKey: Self.lastUsernameKey)
        defaults.set(isAvailable, forKey: Self.cachedSessionKey)
    }

    private func outputIndicatesLoginFailure(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("invalid password")
            || normalized.contains("login failure")
            || normalized.contains("failed to log in")
            || normalized.contains("not logged in")
            || normalized.contains("steam guard")
            || normalized.contains("two-factor")
    }

    private func outputRequiresSteamGuard(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("steam guard") || normalized.contains("two-factor")
    }

    private func authenticationSucceeded(output: String, exitCode: Int32) -> Bool {
        // SteamCMD emits unrelated `OK` lines while loading Steam API.  Only
        // its explicit login confirmation proves a reusable account session.
        exitCode == 0
            && !outputIndicatesLoginFailure(output)
            && output.localizedCaseInsensitiveContains("Logged in OK")
    }

    /// Returns true when SteamCMD has already downloaded an item into one of
    /// its local libraries.  This path can be imported without starting a new
    /// SteamCMD process or restoring a Steam session.
    func hasCachedWorkshopContent(workshopId: String) -> Bool {
        guard let cmdPath = steamCmdPath else { return false }
        return findWorkshopContentDirectory(workshopId: workshopId, cmdPath: cmdPath) != nil
    }

    private func importWorkshopContent(at sourceDir: URL, workshopId: String) {
        DispatchQueue.main.async {
            self.downloadProgress[workshopId] = .downloading(status: String(localized: "Copying to library..."))
        }

        let fm = FileManager.default
        let destination = fm.wallpapersDirectory.appending(path: workshopId)
        let staging = fm.wallpapersDirectory.appending(
            path: ".\(workshopId).downloading-\(UUID().uuidString)"
        )
        let backup = fm.wallpapersDirectory.appending(
            path: ".\(workshopId).previous-\(UUID().uuidString)"
        )
        var movedExistingDestination = false
        do {
            try fm.copyItem(at: sourceDir, to: staging)
            if fm.fileExists(atPath: destination.path) {
                // Never delete an installed wallpaper before its replacement
                // has been copied successfully.  A failed disk write or an
                // interrupted import must leave the previous working copy
                // recoverable instead of turning an update into data loss.
                try fm.moveItem(at: destination, to: backup)
                movedExistingDestination = true
            }
            do {
                try fm.moveItem(at: staging, to: destination)
            } catch {
                if movedExistingDestination, !fm.fileExists(atPath: destination.path) {
                    try? fm.moveItem(at: backup, to: destination)
                }
                throw error
            }
            if movedExistingDestination {
                try? fm.removeItem(at: backup)
            }
            DispatchQueue.main.async {
                self.downloadProgress[workshopId] = .completed
            }
        } catch {
            try? fm.removeItem(at: staging)
            if movedExistingDestination,
               !fm.fileExists(atPath: destination.path),
               fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: destination)
            }
            DispatchQueue.main.async {
                self.downloadProgress[workshopId] = .failed(
                    String(format: String(localized: "Copy failed: %@"), error.localizedDescription)
                )
            }
        }
    }

    /// Parse steamcmd output lines into human-readable progress.
    private func parseProgress(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("Logging in") || trimmed.contains("Logged in") {
            return String(localized: "Authenticating...")
        }
        if trimmed.contains("Downloading item") || trimmed.contains("workshop_download_item") {
            return String(localized: "Requesting download...")
        }
        if trimmed.contains("Downloading") || trimmed.contains("downloading") {
            // Try to extract percentage like "Update state (0x61) downloading, progress: 45.23"
            if let range = trimmed.range(of: "progress:\\s*([\\d.]+)", options: .regularExpression),
               let pct = Double(trimmed[range].replacingOccurrences(of: "progress:", with: "").trimmingCharacters(in: .whitespaces)) {
                return String(format: String(localized: "Downloading... %.0f%%"), min(pct, 100))
            }
            return String(localized: "Downloading...")
        }
        if trimmed.contains("Validating") || trimmed.contains("validating") {
            return String(localized: "Validating...")
        }
        if trimmed.contains("Success") {
            return String(localized: "Download complete, importing...")
        }
        if trimmed.contains("Update state") {
            // Generic state update
            if trimmed.contains("0x5") { return String(localized: "Validating...") }
            if trimmed.contains("0x61") { return String(localized: "Downloading...") }
            if trimmed.contains("0x101") { return String(localized: "Committing...") }
        }
        return nil
    }

    private func findWorkshopContentDirectory(workshopId: String, cmdPath: String) -> URL? {
        steamAppsDirectories(cmdPath: cmdPath).first { steamAppsDirectory in
            let contentDirectory = steamAppsDirectory
                .appending(path: "workshop/content/431960/\(workshopId)")
            return isCompleteWorkshopContentDirectory(contentDirectory)
        }
        .map { $0.appending(path: "workshop/content/431960/\(workshopId)") }
    }

    /// SteamCMD creates the target directory and can write `project.json`
    /// before the referenced scene/video package is complete.  Reusing only
    /// that marker can import a truncated wallpaper and replace a working
    /// local copy.  Require the project manifest and its playable root asset
    /// (loose source or matching PKG) before treating a cache entry as ready.
    private func isCompleteWorkshopContentDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let projectURL = directory.appending(path: "project.json")
        guard isNonEmptyRegularFile(projectURL),
              let data = try? Data(contentsOf: projectURL),
              let project = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rootAsset = project["file"] as? String,
              let rootAssetURL = safeWorkshopAssetURL(rootAsset, in: directory) else {
            return false
        }

        var candidates = [rootAssetURL]
        let rootPath = rootAsset as NSString
        if rootPath.pathExtension.lowercased() != "pkg" {
            candidates.append(
                directory.appending(path: rootPath.deletingPathExtension + ".pkg")
            )
        }
        return candidates.contains(where: isNonEmptyRegularFile)
    }

    private func safeWorkshopAssetURL(_ relativePath: String, in directory: URL) -> URL? {
        let normalizedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              !normalizedPath.split(separator: "/").contains("..") else {
            return nil
        }
        let candidate = directory.appending(path: normalizedPath).standardizedFileURL
        let normalizedDirectory = directory.standardizedFileURL.path
        guard candidate.path.hasPrefix(normalizedDirectory + "/") else { return nil }
        return candidate
    }

    private func isNonEmptyRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0 else {
            return false
        }
        return true
    }

    private func steamAppsDirectories(cmdPath: String) -> [URL] {
        // SteamCMD normally stores downloads relative to its install location,
        // but Homebrew wrappers and regular Steam installs can redirect content
        // into any library listed in `libraryfolders.vdf`.  Search both the
        // known macOS roots and every configured Steam library before reporting
        // that an otherwise successful download is missing.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let workingDirectory = steamCmdWorkingDirectory(cmdPath: cmdPath)
        let initialPaths = [
            workingDirectory.appending(path: "steamapps"),
            home
                .appending(path: "Library/Application Support/Steam/steamapps"),
            home
                .appending(path: "Steam/steamapps"),
            home
                .appending(path: ".steam/steam/steamapps"),
            home
                .appending(path: ".steam/steamcmd/steamapps"),
        ]

        let possiblePaths = initialPaths + initialPaths.flatMap(librarySteamAppsDirectories)

        var seen = Set<String>()
        return possiblePaths.filter { path in
            let canonicalPath = path.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(canonicalPath).inserted else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func librarySteamAppsDirectories(from steamAppsDirectory: URL) -> [URL] {
        let libraryFolders = steamAppsDirectory.appending(path: "libraryfolders.vdf")
        guard let contents = try? String(contentsOf: libraryFolders, encoding: .utf8) else {
            return []
        }

        // VDF stores each configured library as: "path" "/Volumes/...".
        // Values can escape quotes and backslashes, so retain escaped pairs
        // while matching and unescape them before constructing the URL.
        let pattern = #""path"\s*"((?:\\.|[^"])*)""#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return expression.matches(in: contents, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: contents) else { return nil }
            let libraryRoot = URL(fileURLWithPath: unescapedVDFString(String(contents[valueRange])))
            return libraryRoot.lastPathComponent == "steamapps"
                ? libraryRoot
                : libraryRoot.appending(path: "steamapps")
        }
    }

    private func unescapedVDFString(_ value: String) -> String {
        var result = ""
        var isEscaping = false
        for character in value {
            if isEscaping {
                result.append(character)
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                result.append(character)
            }
        }
        if isEscaping {
            result.append("\\")
        }
        return result
    }

    private func steamCmdWorkingDirectory(cmdPath: String) -> URL {
        steamCmdExecutableURL(cmdPath: cmdPath).deletingLastPathComponent()
    }

    private func steamCmdExecutableURL(cmdPath: String) -> URL {
        URL(fileURLWithPath: cmdPath).resolvingSymlinksInPath()
    }
}
