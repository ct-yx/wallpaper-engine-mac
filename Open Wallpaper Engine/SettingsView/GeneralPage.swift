//
//  GeneralPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI

struct GeneralPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    @ObservedObject private var updateService = AppUpdateService.shared
    @State private var languageChangeRequiresRelaunch = false
    
    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        Form {
            // MARK: Automatic Startup
            Section {
                Toggle("Start with macOS", isOn: $viewModel.settings.autoStart)
//                Toggle("Safe start after hibernation", isOn: $viewModel.settings.safeMode)
            } header: {
                Label("Automatic Startup", systemImage: "star.fill")
            }
            // MARK: Basic Setup
            Section {
                Picker("Language", selection: $viewModel.settings.language) {
                    Text("Follow System").tag(GSLocalization.followSystem)
                    Text("English").tag(GSLocalization.en_US)
                    Text("Chinese Simplified").tag(GSLocalization.zh_CN)
                }
                .onChange(of: viewModel.settings.language) { _ in
                    languageChangeRequiresRelaunch = true
                }

                if languageChangeRequiresRelaunch {
                    Text("Language changes take effect the next time you open Open Wallpaper Engine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Basic Setup", systemImage: "gearshape.fill")
            }
            // MARK: Updates
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Version")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(updateService.currentVersion)
                            .font(.body.monospacedDigit())
                    }
                    Spacer()
                    Button("Check for Updates") {
                        Task {
                            await updateService.checkForUpdates()
                        }
                    }
                    .disabled(updateService.isBusy)
                }

                HStack(spacing: 8) {
                    if updateService.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(updateService.statusText)
                        .font(.caption)
                        .foregroundStyle(updateStatusColor)
                }

                if let release = updateService.availableRelease {
                    HStack {
                        Button("Download and Install") {
                            Task {
                                await updateService.downloadAndInstall()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updateService.isBusy)

                        Link("View Release", destination: release.pageURL)
                            .font(.caption)
                    }
                }
            } header: {
                Label("Updates", systemImage: "arrow.down.circle.fill")
            }
            // MARK: macOS
            Section {
                Toggle("Adjust Menu Bar Color", isOn: $viewModel.settings.adjustMenuBarTint)
            } header: {
                Label("macOS", systemImage: "apple.logo")
            }
            // MARK: Appearance
            Section {
                Picker("Theme", selection: $viewModel.settings.appearance) {
                    Text("Light").tag(GSAppearance.light)
                    Text("Dark").tag(GSAppearance.dark)
                    Text("Auto").tag(GSAppearance.followSystem)
                }
            } header: {
                Label("Appearance", systemImage: "paintpalette.fill")
            }
            // MARK: Audio
            Section {
                Toggle(isOn: $viewModel.settings.audioOutput) {
                    Text("Audio Output")
                }.disabled(true)
                Toggle(isOn: $viewModel.settings.reloadWhenChangingOutputDevice) {
                    Text("Reload when changing output device")
                }.disabled(true)
            } header: {
                Label("Audio", systemImage: "speaker.3.fill")
            }
            // MARK: Video
            Section {
                Picker("Video Framework", selection: $viewModel.settings.videoFramework) {
                    Text("Apple AVKit").tag(GSVideoFramework.avkit)
                }
            } header: {
                Label("Video", systemImage: "film")
            }
            // MARK: Advanced
            Section {
                Picker("Process Piority", selection: $viewModel.settings.processPiority) {
                    Text("Normal").tag(GSProcessPiority.normal)
                    Text("Below Normal").tag(GSProcessPiority.belowNormal)
                }
                Toggle("Pause when VRAM is exhausted", isOn: $viewModel.settings.pauseOnVRAMExhausted)
                Toggle("Restart after crashing", isOn: $viewModel.settings.restartAfterCrashing)
            } header: {
                Label("Advanced", systemImage: "wrench.and.screwdriver.fill")
            }
            // MARK: Developers
            Section {
                Picker("Log Level", selection: $viewModel.settings.logLevel) {
                    Text("None").tag(GSLogLevel.none)
                    Text("Errors Only").tag(GSLogLevel.error)
                    Text("Verbose").tag(GSLogLevel.verbose)
                }
            } header: {
                Label("Developer", systemImage: "number")
            }
            // MARK: Reset
            Section {
                HStack {
                    Text("Reset Config")
                    Spacer()
                    Button {
                        viewModel.settings = GlobalSettings()
                    } label: {
                        Text("Reset").frame(width: 100)
                    }
                    .tint(Color.red)
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Label("Reset", systemImage: "exclamationmark.triangle.fill")
            }
        }.formStyle(.grouped)
    }

    private var updateStatusColor: Color {
        if case .failed = updateService.state {
            return .red
        }
        return .secondary
    }
}
