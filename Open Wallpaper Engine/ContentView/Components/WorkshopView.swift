import SwiftUI

struct WorkshopView: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel

    init(contentViewModel viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        // Workshop browsing and item details use the Steam Web API.  Do not
        // make the entire browser wait for SteamCMD: it is only needed when
        // the user actually chooses to download an item.
        WorkshopBrowserView(viewModel: viewModel.workshopVM)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - steamcmd Not Installed

private struct SteamCmdNotInstalledView: View {
    @ObservedObject var steamCmd: SteamCmdService
    @State private var isCopied = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("steamcmd Not Found")
                .font(.title2)
                .bold()

            Text("Steam Workshop requires steamcmd to download wallpapers.\nInstall it with Homebrew:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack {
                Text("brew install steamcmd")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install steamcmd", forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            Divider().frame(width: 200)

            Text("Or locate an existing steamcmd binary:")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.message = String(localized: "Select the steamcmd executable")
                if panel.runModal() == .OK, let url = panel.url {
                    steamCmd.setCustomPath(url.path)
                }
            }
            .buttonStyle(.bordered)

            if let error = steamCmd.pathError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Re-detect") {
                steamCmd.detectSteamCmd()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(40)
    }
}

// MARK: - Steam Login

private struct SteamLoginView: View {
    @ObservedObject var steamCmd: SteamCmdService
    @State private var username = ""
    @State private var password = ""
    @State private var guardCode = ""
    @State private var showGuardCode = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Steam Login")
                .font(.title2)
                .bold()

            Text("Log in with your Steam account to download wallpapers.\nYou must own Wallpaper Engine on Steam.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(spacing: 10) {
                TextField("Steam Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                if showGuardCode {
                    TextField("Steam Guard Code", text: $guardCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                if let error = steamCmd.loginError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)

                    if error.contains("Steam Guard") && !showGuardCode {
                        Button("Enter Steam Guard Code") {
                            showGuardCode = true
                        }
                        .buttonStyle(.link)
                    }
                }

                HStack(spacing: 12) {
                    Button("Log In") {
                        steamCmd.login(
                            username: username,
                            password: password,
                            guardCode: showGuardCode ? guardCode : nil
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(username.isEmpty || password.isEmpty || steamCmd.isLoggingIn)

                    if !username.isEmpty {
                        Button("Use Cached Session") {
                            steamCmd.loginWithCachedSession(username: username)
                        }
                        .buttonStyle(.bordered)
                        .disabled(steamCmd.isLoggingIn)
                    }
                }

                if steamCmd.isLoggingIn {
                    ProgressView()
                        .controlSize(.small)
                    Text("Authenticating with Steam...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(40)
        .onAppear {
            if username.isEmpty {
                username = steamCmd.steamUsername
            }
        }
    }
}

// MARK: - Workshop Browser

private struct WorkshopBrowserView: View {
    @ObservedObject var viewModel: WorkshopViewModel

    var body: some View {
        HStack(spacing: 0) {
            WorkshopFilterSidebar(viewModel: viewModel)
            Divider()
            VStack(spacing: 0) {
                searchBar
                results
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $viewModel.selectedItem) { item in
            WorkshopItemDetailView(item: item, viewModel: viewModel)
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.search()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search wallpapers...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task { await viewModel.search() }
                }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    Task { await viewModel.search() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(WorkshopSortOrder.allCases) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .frame(width: 160)
            .onChange(of: viewModel.sortOrder) { _ in
                Task { await viewModel.search() }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            Spacer()
            ProgressView("Searching Workshop...")
            Spacer()
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                APIKeyInputView {
                    Task { await viewModel.search() }
                }
            }
            Spacer()
        } else if viewModel.items.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Search the Steam Workshop")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Find wallpapers by name, tag, or browse trending content.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)

                if WorkshopAPIService.loadAPIKey().isEmpty {
                    Divider().frame(width: 300).padding(.vertical, 4)
                    Text("A Steam Web API key is required to browse.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    APIKeyInputView {
                        Task { await viewModel.search() }
                    }
                }
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300))], spacing: 12) {
                    ForEach(viewModel.items) { item in
                        WorkshopItemCard(item: item, viewModel: viewModel)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(appearing: item) }
                            }
                    }
                }
                .padding()

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.bottom)
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable {
                await viewModel.search()
            }
        }
    }
}

private struct WorkshopFilterSidebar: View {
    @ObservedObject var viewModel: WorkshopViewModel
    @State private var expandedSections = Set(WorkshopTagGroup.allCases)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Filter Results", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.resetFilters()
                    Task { await viewModel.search() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Reset Filters")
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    filterSection(.rating)
                    filterSection(.type)
                    filterSection(.genre)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 190, idealWidth: 220, maxWidth: 260, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func filterSection(_ group: WorkshopTagGroup) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedSections.contains(group) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(group)
                } else {
                    expandedSections.remove(group)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.tags, id: \.self) { tag in
                    Button {
                        viewModel.toggleTag(tag, in: group)
                        Task { await viewModel.search() }
                    } label: {
                        HStack(spacing: 8) {
                            Text(localizedTagName(tag))
                            Spacer(minLength: 0)
                            if viewModel.selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(viewModel.selectedTags.contains(tag) ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(viewModel.selectedTags.contains(tag) ? Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        } label: {
            Text(sectionTitle(group))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private func sectionTitle(_ group: WorkshopTagGroup) -> String {
        switch group {
        case .rating: return String(localized: "Rating")
        case .type: return String(localized: "Type")
        case .genre: return String(localized: "Tags")
        }
    }

    private func localizedTagName(_ tag: String) -> String {
        workshopLocalizedTagName(tag)
    }
}

// MARK: - Workshop Item Card

private struct WorkshopItemCard: View {
    let item: WorkshopItem
    @ObservedObject var viewModel: WorkshopViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview image
            AsyncImage(url: item.previewImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                case .failure:
                    placeholder
                default:
                    placeholder
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(height: 120)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack {
                    if !item.tags.isEmpty {
                        Text(item.tags.prefix(2).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if item.subscriptions > 0 {
                        Label("\(formatCount(item.subscriptions))", systemImage: "heart")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if viewModel.isInstalled(item) {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("View Details", systemImage: "chevron.right")
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                .font(.caption2)
            }
            .padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            viewModel.selectedItem = item
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .aspectRatio(16/9, contentMode: .fill)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

private struct WorkshopItemDetailView: View {
    let item: WorkshopItem
    @ObservedObject var viewModel: WorkshopViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isDownloadSetupPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncImage(url: item.previewImageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        case .failure:
                            previewPlaceholder
                        default:
                            previewPlaceholder
                                .overlay(ProgressView().controlSize(.small))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 16) {
                        Label(formatCount(item.subscriptions), systemImage: "heart")
                        Label(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file), systemImage: "externaldrive")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !item.tags.isEmpty {
                        Text(item.tags.map(localizedTagName).joined(separator: "  ·  "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let description = item.description,
                       !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(description)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Link("Open in Workshop", destination: workshopURL)
                Spacer()
                downloadControl
            }
            .padding()
        }
        .frame(width: 620, height: 620)
        .sheet(isPresented: $isDownloadSetupPresented) {
            SteamDownloadSetupView(steamCmd: viewModel.steamCmd)
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if viewModel.isInstalled(item) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            switch viewModel.downloadState(for: item) {
            case .downloading(let status):
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .completed:
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .requiresLogin(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Button("Set Up Downloads") {
                        isDownloadSetupPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            case .failed(let message):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    downloadButton
                }
            case .none:
                if viewModel.steamCmd.isReadyForDownloads || viewModel.hasCachedDownload(item) {
                    downloadButton
                } else {
                    Button("Set Up Downloads") {
                        isDownloadSetupPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var downloadButton: some View {
        Button {
            viewModel.download(item: item)
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        .buttonStyle(.borderedProminent)
    }

    private var previewPlaceholder: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
    }

    private var workshopURL: URL {
        URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(item.id)")!
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func localizedTagName(_ tag: String) -> String {
        workshopLocalizedTagName(tag)
    }
}

private struct SteamDownloadSetupView: View {
    @ObservedObject var steamCmd: SteamCmdService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if steamCmd.isLoggedIn {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("Downloads Ready")
                        .font(.title3.weight(.semibold))
                    Text("SteamCMD is configured and its cached Steam session will be reused for downloads.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 440, height: 260)
                .padding()
            } else if steamCmd.hasSavedSessionForDownloads {
                VStack(spacing: 14) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("Saved Steam Session")
                        .font(.title3.weight(.semibold))
                    Text("Your saved Steam session will be reused and checked only when you choose Download.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 440, height: 260)
                .padding()
            } else if !steamCmd.isInstalled {
                VStack(spacing: 12) {
                    Text("SteamCMD is only required to download wallpapers. Browsing and viewing details use the Steam Web API.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SteamCmdNotInstalledView(steamCmd: steamCmd)
                }
                .frame(width: 480)
            } else {
                SteamLoginView(steamCmd: steamCmd)
                    .frame(width: 480)
            }
        }
    }
}

private func workshopLocalizedTagName(_ tag: String) -> String {
    switch tag {
    case "Everyone": return String(localized: "Everyone")
    case "Questionable": return String(localized: "Questionable")
    case "Mature": return String(localized: "Mature")
    case "Scene": return String(localized: "Scene")
    case "Video": return String(localized: "Video")
    case "Web": return String(localized: "Web")
    case "Application": return String(localized: "Application")
    case "Abstract": return String(localized: "Abstract")
    case "Animal": return String(localized: "Animal")
    case "Anime": return String(localized: "Anime")
    case "Cartoon": return String(localized: "Cartoon")
    case "CGI": return String(localized: "CGI")
    case "Cyberpunk": return String(localized: "Cyberpunk")
    case "Fantasy": return String(localized: "Fantasy")
    case "Game": return String(localized: "Game")
    case "Girls": return String(localized: "Girls")
    case "Guys": return String(localized: "Guys")
    case "Landscape": return String(localized: "Landscape")
    case "Medieval": return String(localized: "Medieval")
    case "Memes": return String(localized: "Memes")
    case "MMD": return String(localized: "MMD")
    case "Music": return String(localized: "Music")
    case "Nature": return String(localized: "Nature")
    case "Pixel Art": return String(localized: "Pixel Art")
    case "Relaxing": return String(localized: "Relaxing")
    case "Retro": return String(localized: "Retro")
    case "Sci-Fi": return String(localized: "Sci-Fi")
    case "Sports": return String(localized: "Sports")
    case "Technology": return String(localized: "Technology")
    case "Television": return String(localized: "Television")
    case "Vehicle": return String(localized: "Vehicle")
    default: return tag
    }
}

// MARK: - API Key Input

private struct APIKeyInputView: View {
    @State private var apiKey = WorkshopAPIService.loadAPIKey()
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                SecureField("Steam Web API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit { save() }

                Button("Save & Search") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 4) {
                Text("Get a free key at")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Link("steamcommunity.com/dev/apikey", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                    .font(.caption)
            }
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        WorkshopAPIService.saveAPIKey(trimmed)
        onSave()
    }
}
