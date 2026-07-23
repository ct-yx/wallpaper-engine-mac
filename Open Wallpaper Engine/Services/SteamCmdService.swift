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
        case failed(String)
    }

    private static let lastUsernameKey = "SteamLastUsername"
    private let downloadQueue = DispatchQueue(label: "steamcmd.download.queue", qos: .userInitiated)
    private var hasCheckedCachedSessionForDownload = false
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
        // SteamCMD keeps its account configuration and login token relative to
        // its working directory.  Always use its install directory so login
        // state survives app relaunches as well as download commands.
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

    /// Browsing uses the Web API; only downloads need a locally configured,
    /// authenticated SteamCMD session.
    var isReadyForDownloads: Bool { isInstalled && isLoggedIn }

    @Published var pathError: String?

    /// Verify the saved SteamCMD session only after the user starts the
    /// download flow.  Browsing Workshop pages must never launch SteamCMD.
    func restoreCachedSessionForDownloadIfNeeded() {
        guard !hasCheckedCachedSessionForDownload,
              isInstalled,
              !isLoggedIn,
              !isLoggingIn,
              !steamUsername.isEmpty else {
            return
        }

        hasCheckedCachedSessionForDownload = true
        loginWithCachedSession(username: steamUsername)
    }

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
        hasCheckedCachedSessionForDownload = false
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
                if output.contains("Logged in OK") || (output.contains("OK") && exitCode == 0) {
                    self.isLoggedIn = true
                    self.loginError = nil
                    UserDefaults.standard.set(username, forKey: Self.lastUsernameKey)
                    self.hasCheckedCachedSessionForDownload = true
                } else if output.contains("Steam Guard") || output.contains("Two-factor") {
                    self.loginError = String(localized: "Steam Guard code required")
                } else if output.contains("Invalid Password") || output.contains("FAILED") {
                    self.loginError = String(localized: "Invalid username or password")
                } else {
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
                if output.contains("Logged in OK") || (output.contains("OK") && exitCode == 0) {
                    self.isLoggedIn = true
                    self.loginError = nil
                    UserDefaults.standard.set(username, forKey: Self.lastUsernameKey)
                } else {
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
        guard isLoggedIn else {
            downloadProgress[workshopId] = .failed(String(localized: "Log in to Steam before downloading wallpapers."))
            return
        }

        downloadProgress[workshopId] = .downloading(status: String(localized: "Queued"))

        downloadQueue.async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.downloadProgress[workshopId] = .downloading(status: String(localized: "Starting steamcmd..."))
            }

            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = self.steamCmdExecutableURL(cmdPath: cmdPath)
            process.currentDirectoryURL = self.steamCmdWorkingDirectory(cmdPath: cmdPath)
            process.arguments = [
                "+login", self.steamUsername,
                "+workshop_download_item", "431960", workshopId, "validate",
                "+quit"
            ]
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            // Read output in real-time for progress updates
            var fullOutput = ""
            let handle = outputPipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                fullOutput += line

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
            if let str = String(data: remaining, encoding: .utf8) { fullOutput += str }

            let exitCode = process.terminationStatus

            // SteamCMD installations do not all use the same steamapps
            // directory.  In particular Homebrew's executable is often a
            // symlink while its workshop content lives under the user's Steam
            // support directory.  Search the exact item in every supported
            // location instead of accepting the first existing steamapps dir.
            if let sourceDir = self.findWorkshopContentDirectory(
                workshopId: workshopId,
                cmdPath: cmdPath
            ),
               FileManager.default.fileExists(atPath: sourceDir.path) {
                DispatchQueue.main.async {
                    self.downloadProgress[workshopId] = .downloading(status: String(localized: "Copying to library..."))
                }

                let fm = FileManager.default
                let dest = fm.wallpapersDirectory.appending(path: workshopId)
                let staging = fm.wallpapersDirectory.appending(
                    path: ".\(workshopId).downloading-\(UUID().uuidString)"
                )
                do {
                    try fm.copyItem(at: sourceDir, to: staging)
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.moveItem(at: staging, to: dest)
                } catch {
                    try? fm.removeItem(at: staging)
                    DispatchQueue.main.async {
                        self.downloadProgress[workshopId] = .failed(
                            String(format: String(localized: "Copy failed: %@"), error.localizedDescription)
                        )
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.downloadProgress[workshopId] = .completed
                }
                return
            }

            let failure: String
            if fullOutput.contains("ERROR") || fullOutput.contains("FAILED") {
                failure = fullOutput.components(separatedBy: "\n")
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
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: contentDirectory.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
        }
        .map { $0.appending(path: "workshop/content/431960/\(workshopId)") }
    }

    private func steamAppsDirectories(cmdPath: String) -> [URL] {
        // SteamCMD typically stores downloads relative to its install location.
        // The user-level Steam directories cover Homebrew and manual packages
        // whose launcher redirects its data directory after startup.
        let workingDirectory = steamCmdWorkingDirectory(cmdPath: cmdPath)
        let possiblePaths = [
            workingDirectory.appending(path: "steamapps"),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Steam/steamapps"),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Steam/steamapps"),
        ]

        var seen = Set<String>()
        return possiblePaths.filter { path in
            let canonicalPath = path.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(canonicalPath).inserted else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func steamCmdWorkingDirectory(cmdPath: String) -> URL {
        steamCmdExecutableURL(cmdPath: cmdPath).deletingLastPathComponent()
    }

    private func steamCmdExecutableURL(cmdPath: String) -> URL {
        URL(fileURLWithPath: cmdPath).resolvingSymlinksInPath()
    }
}
