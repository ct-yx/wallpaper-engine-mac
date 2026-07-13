//
//  UnsafeWallpaper.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/9/2.
//

import SwiftUI

struct UnsafeWallpaper: View {
    @Environment(\.dismiss) var dismiss
    
    var wallpaper: WEWallpaper
    
    @State var seconds: Int = 5
    @State var isIgnored = false
    
    init(wallpaper: WEWallpaper) {
        self.wallpaper = wallpaper
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text(String(format: String(localized: "Opening Unknown %@"), wallpaperTypeName))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .font(.title2)
            Divider()
            HStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 6)
                    .frame(maxWidth: 100)
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(format: String(localized: "You are about to open an external %@ as a wallpaper:"), wallpaperTypeName.lowercased()))
                    Text("\(wallpaper.wallpaperDirectory.path(percentEncoded: false) + wallpaper.project.file)").bold()
                    Text("Open Wallpaper Engine has no control over this file, you must ensure that it comes from a rellable source before proceeding.")
                    Text(seconds > 0
                         ? String(format: String(localized: "Please wait %d seconds."), seconds)
                         : String(localized: "Please be aware of malware."))
                    Toggle("Don't ask again for this wallpaper", isOn: $isIgnored)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            Divider()
            HStack {
                Button {
                    AppDelegate.shared.wallpaperViewModel.currentWallpaper =
                    AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper
                    
                    if isIgnored {
                        var trustedWallpapers =
                        UserDefaults.standard.array(forKey: "TrustedWallpapers") as? [String] ?? [String]()
                        
                        trustedWallpapers.append(AppDelegate.shared.wallpaperViewModel.nextCurrentWallpaper.wallpaperDirectory.path(percentEncoded: false))
                        
                        UserDefaults.standard.set(trustedWallpapers, forKey: "TrustedWallpapers")
                    }
                    
                    dismiss()
                } label: {
                    Text("Proceed")
                        .padding(.horizontal, 10)
                }
                .animation(.default, value: seconds)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(seconds > 0 ? true : false)
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .padding(.horizontal, 10)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onAppear {
            let _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if self.seconds <= 0 {
                    timer.invalidate()
                } else {
                    self.seconds -= 1
                }
            }
        }
    }

    private var wallpaperTypeName: String {
        switch wallpaper.project.type.lowercased() {
        case "web": return String(localized: "Web Page")
        case "application": return String(localized: "Application")
        default: return String(localized: "Wallpaper")
        }
    }
}
