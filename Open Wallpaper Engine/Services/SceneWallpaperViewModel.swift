//
//  SceneWallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Loads and renders Wallpaper Engine scene wallpapers using SpriteKit.
//  Follows the same ViewModel pattern as VideoWallpaperViewModel.
//

import AVFoundation
import Combine
import CoreText
import SpriteKit
import SwiftUI

class SceneWallpaperViewModel: ObservableObject {
    static func log(_ msg: String) {
        let line = "[SceneVM] \(msg)"
        NSLog("%@", line)
    }

    var currentWallpaper: WEWallpaper {
        willSet {
            loadScene(from: newValue)
        }
    }

    @Published var skScene: SKScene?

    private var pkgParser: PKGParser?
    private var parallaxNodes: [ParallaxNode] = []
    private var parallaxConfiguration: ParallaxConfiguration?
    private var parallaxDisplacement = CGPoint.zero
    private var lastParallaxUpdateTime: TimeInterval?
    /// Core Text registers embedded scene fonts process-wide.  Retain the
    /// resolved PostScript name per source file so repeated scene loads do not
    /// register the same font again.
    private static var registeredTextFonts = [String: String]()
    private var sceneAudioPlayers: [AVAudioPlayer] = []
    private var sceneAudioCancellables = Set<AnyCancellable>()
    private var playbackRate: Float = 1
    private var playbackVolume: Float = 1

    /// Exposed for diagnostics and the focused renderer fixture.  A scene can
    /// have multiple sound objects and each one can reference multiple assets.
    var activeSceneAudioCount: Int { sceneAudioPlayers.count }

    private struct ParallaxNode {
        let node: SKNode
        let basePosition: CGPoint
        let depth: CGPoint
    }

    private struct ParallaxConfiguration {
        let amount: CGFloat
        let delay: CGFloat
        let mouseInfluence: CGFloat
        let referenceSize: CGFloat
    }

    private struct SceneTextureAsset {
        let image: NSImage
        let animationFrames: [TEXAnimationFrame]
    }

    init(wallpaper: WEWallpaper) {
        self.currentWallpaper = wallpaper
        Self.log("init: wallpaper=\(wallpaper.project.title) dir=\(wallpaper.wallpaperDirectory.path)")
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        observeGlobalPlayback()
        loadScene(from: wallpaper)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Scene Loading

    func loadScene(from wallpaper: WEWallpaper) {
        stopSceneAudio()
        let dir = wallpaper.wallpaperDirectory
        let sceneFile = wallpaper.project.file  // e.g. "scene.json" or "gifscene.json"

        // Derive PKG name from scene file: "scene.json" → "scene.pkg", "gifscene.json" → "gifscene.pkg"
        let pkgName = (sceneFile as NSString).deletingPathExtension + ".pkg"
        let pkgURL = dir.appending(path: pkgName)
        let looseSceneURL = dir.appending(path: sceneFile)

        var scene: WEScene?

        if FileManager.default.fileExists(atPath: pkgURL.path(percentEncoded: false)) {
            do {
                let parser = try PKGParser(url: pkgURL)
                self.pkgParser = parser
                scene = try parser.extractJSON(named: sceneFile, as: WEScene.self)
            } catch {
                Self.log("Failed to parse PKG: \(error)")
            }
        } else if FileManager.default.fileExists(atPath: looseSceneURL.path(percentEncoded: false)) {
            // Loose files (no .pkg)
            self.pkgParser = nil
            do {
                let data = try Data(contentsOf: looseSceneURL)
                scene = try JSONDecoder().decode(WEScene.self, from: data)
            } catch {
                Self.log("Failed to parse loose \(sceneFile): \(error)")
            }
        }

        guard let scene = scene else {
            print("[SceneVM] No scene data found")
            NSLog("[SceneVM] No scene data found")
            return
        }

        Self.log("Scene loaded: \(scene.objects.count) objects from \(sceneFile)")
        let skScene = buildSKScene(from: scene, wallpaperDir: dir)
        Self.log("SKScene built: \(skScene.children.count) children")
        DispatchQueue.main.async {
            self.skScene = skScene
        }
    }

    // MARK: - SpriteKit Scene Building

    private func buildSKScene(from scene: WEScene, wallpaperDir: URL) -> SKScene {
        let projection = scene.general.orthogonalprojection ?? WEOrthogonalProjection(width: 1920, height: 1080)
        let skScene = WEParallaxSKScene(size: CGSize(width: projection.width, height: projection.height))
        skScene.parallaxOwner = self
        skScene.scaleMode = .aspectFill
        configureParallax(from: scene.general, sceneSize: skScene.size)

        // Background color from clearcolor
        if let colorStr = scene.general.clearcolor {
            let c = colorStr.parseColor()
            skScene.backgroundColor = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
        }

        // Preserve the source hierarchy as well as source order.  Scene files
        // commonly place images and particle systems beneath transform-only
        // group objects; applying those transforms to a container lets
        // SpriteKit compose origin, scale, and angle just like the reference
        // renderer instead of treating every object as a root layer.
        var objectIndicesByID = [Int: Int]()
        for (index, object) in scene.objects.enumerated() {
            if let id = object.id {
                objectIndicesByID[id] = index
            }
        }

        var containers = [Int: SKNode]()
        var buildingContainers = Set<Int>()
        func container(for index: Int) -> SKNode {
            if let existing = containers[index] {
                return existing
            }

            let object = scene.objects[index]
            let node = SKNode()
            node.name = object.id.map { "scene-object-\($0)" } ?? "scene-object-index-\(index)"
            containers[index] = node
            buildingContainers.insert(index)

            let parentIndex = object.parent.flatMap { objectIndicesByID[$0] }
            let hasParent = parentIndex != nil && parentIndex != index
            configureSceneObjectContainer(
                node,
                object: object,
                sceneSize: skScene.size,
                isParented: hasParent
            )
            node.zPosition = CGFloat(index)

            if let parentIndex, parentIndex != index, !buildingContainers.contains(parentIndex) {
                container(for: parentIndex).addChild(node)
            } else {
                if let parentIndex, parentIndex != index, buildingContainers.contains(parentIndex) {
                    Self.log("Ignoring cyclic parent relationship for scene object \(object.id ?? -1)")
                }
                skScene.addChild(node)
            }

            buildingContainers.remove(index)
            return node
        }

        var hasRenderableContent = false
        var imageCount = 0
        var particleCount = 0
        var textCount = 0
        var soundCount = 0
        for (index, obj) in scene.objects.enumerated() {
            let objectContainer = container(for: index)
            guard obj.visible?.value != false else { continue }
            if obj.image != nil,
               let node = buildImageNode(obj, wallpaperDir: wallpaperDir) {
                objectContainer.addChild(node)
                registerParallax(node: objectContainer, object: obj, isParticle: false)
                hasRenderableContent = true
                imageCount += 1
            } else if obj.particle != nil,
                      let node = buildParticleNode(obj, wallpaperDir: wallpaperDir) {
                objectContainer.addChild(node)
                registerParallax(node: objectContainer, object: obj, isParticle: true)
                hasRenderableContent = true
                particleCount += 1
            } else if obj.text != nil,
                      let node = buildTextNode(obj, wallpaperDir: wallpaperDir) {
                objectContainer.addChild(node)
                registerParallax(node: objectContainer, object: obj, isParticle: false)
                hasRenderableContent = true
                textCount += 1
            } else if let soundPaths = obj.sound {
                soundCount += buildSceneSoundPlayers(
                    soundPaths,
                    playbackMode: obj.playbackmode,
                    wallpaperDir: wallpaperDir
                )
            }
        }
        Self.log(
            "Scene render nodes: \(imageCount + particleCount + textCount) "
                + "(\(imageCount) images, \(particleCount) particle systems, \(textCount) text objects, "
                + "\(soundCount) sound assets)"
        )
        applySceneAudioPlayback()

        // Fallback: use preview image
        if !hasRenderableContent {
            let previewImage = loadPreviewImage(wallpaperDir: wallpaperDir)
            if let img = previewImage {
                let node = SKSpriteNode(texture: SKTexture(image: img))
                node.size = skScene.size
                node.position = CGPoint(x: skScene.size.width / 2, y: skScene.size.height / 2)
                skScene.addChild(node)
            }
        }

        return skScene
    }

    private func loadPreviewImage(wallpaperDir: URL) -> NSImage? {
        for name in ["preview.jpg", "preview.png", "preview.gif"] {
            let url = wallpaperDir.appending(path: name)
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    // MARK: - Image Objects

    private func buildImageNode(
        _ obj: WESceneObject,
        wallpaperDir: URL
    ) -> SKSpriteNode? {
        guard let imagePath = obj.image else { return nil }

        // Load model JSON → material JSON → texture
        let model: WEModel? = loadJSON(path: imagePath, wallpaperDir: wallpaperDir)
        guard let materialPath = model?.material else {
            print("[SceneVM] No material for image object '\(obj.name ?? "")' (model path: \(imagePath))")
            return nil
        }

        let material: WEMaterial? = loadJSON(path: materialPath, wallpaperDir: wallpaperDir)
        guard let textureName = material?.passes?.first?.textures?.first else {
            print("[SceneVM] No texture in material '\(materialPath)' (material decoded: \(material != nil))")
            return nil
        }

        // Load texture: try .tex file first, then common image formats
        Self.log("Loading texture '\(textureName)' for '\(obj.name ?? "")'")
        guard let textureAsset = loadTextureAsset(
            named: textureName,
            materialDir: materialPath,
            wallpaperDir: wallpaperDir
        ) else {
            Self.log("FAILED to load texture '\(textureName)' from material dir '\(materialPath)'")
            return nil
        }
        let image = textureAsset.image
        Self.log("Texture loaded: \(image.size)")

        let texture = SKTexture(image: image)
        let node = SKSpriteNode(texture: texture)

        // Size from object, or use pixel dimensions (not point size, which is halved on Retina)
        if let sizeValue = obj.size {
            let (w, h, _) = sizeValue.vectorValue
            node.size = CGSize(width: w, height: h)
        } else {
            let pixelW = image.representations.first?.pixelsWide ?? Int(image.size.width)
            let pixelH = image.representations.first?.pixelsHigh ?? Int(image.size.height)
            node.size = CGSize(width: pixelW, height: pixelH)
        }

        // Image transforms are applied around the alignment anchor.  The
        // upstream renderer treats origin as the anchor point rather than
        // always as the visual centre (e.g. `top-left` pins that corner).
        let alignment = (obj.horizontalalign ?? obj.alignment ?? "center").lowercased()
        node.anchorPoint = imageAnchorPoint(for: alignment)

        // Alpha
        node.alpha = safeParticleScalar(obj.alpha?.doubleValue ?? 1, fallback: 1, minimum: 0, maximum: 1)

        // Color tint
        if let color = obj.color?.vectorValue {
            node.color = particleColor(from: color)
            node.colorBlendFactor = (obj.colorBlendMode?.doubleValue ?? 0) > 0 ? 1.0 : 0.0
        }

        // Blend mode from material
        if let blending = material?.passes?.first?.blending {
            switch blending {
            case "additive": node.blendMode = .add
            case "translucent": node.blendMode = .alpha
            default: node.blendMode = .alpha
            }
        }

        applyTextureAnimation(textureAsset.animationFrames, to: node)

        return node
    }

    private func imageAnchorPoint(for alignment: String) -> CGPoint {
        var anchor = CGPoint(x: 0.5, y: 0.5)

        if alignment.contains("left") {
            anchor.x = 0
        } else if alignment.contains("right") {
            anchor.x = 1
        }

        // Source scene coordinates are Y-down.  In SpriteKit, a source `top`
        // anchor is the node's bottom edge after that coordinate conversion.
        if alignment.contains("top") {
            anchor.y = 0
        } else if alignment.contains("bottom") {
            anchor.y = 1
        }

        return anchor
    }

    // MARK: - Text Objects

    /// Builds the static text-object subset implemented by the Linux renderer:
    /// content, custom/system font, point size, bounding width, color, alpha,
    /// alignment, padding, and the enclosing scene transform.  Script-driven
    /// text retains its initial `value` when one is present in the source.
    private func buildTextNode(_ obj: WESceneObject, wallpaperDir: URL) -> SKLabelNode? {
        guard let text = obj.text?.stringValue, !text.isEmpty else { return nil }

        let pointSize = safeParticleScalar(
            obj.pointsize?.doubleValue ?? 32,
            fallback: 32,
            minimum: 1,
            maximum: 512
        )
        let label = SKLabelNode(fontNamed: textFontName(reference: obj.font, wallpaperDir: wallpaperDir))
        label.name = obj.name.map { "scene-text-\($0)" }
        label.text = text
        label.fontSize = pointSize
        label.fontColor = obj.color.map { particleColor(from: $0.vectorValue) } ?? .white
        label.alpha = safeParticleScalar(
            obj.alpha?.doubleValue ?? 1,
            fallback: 1,
            minimum: 0,
            maximum: 1
        )

        let horizontalAlignment = (obj.horizontalalign ?? obj.alignment ?? "center").lowercased()
        let verticalAlignment = (obj.verticalalign ?? "center").lowercased()
        let padding = safeParticleScalar(
            obj.padding?.doubleValue ?? 0,
            fallback: 0,
            minimum: 0,
            maximum: 10_000
        )

        switch horizontalAlignment {
        case let value where value.contains("left"):
            label.horizontalAlignmentMode = .left
            label.position.x = padding
        case let value where value.contains("right"):
            label.horizontalAlignmentMode = .right
            label.position.x = -padding
        default:
            label.horizontalAlignmentMode = .center
        }

        // Match the image-anchor conversion above: source scene coordinates
        // are Y-down while the SpriteKit scene has already been flipped.
        switch verticalAlignment {
        case let value where value.contains("top"):
            label.verticalAlignmentMode = .bottom
            label.position.y = padding
        case let value where value.contains("bottom"):
            label.verticalAlignmentMode = .top
            label.position.y = -padding
        default:
            label.verticalAlignmentMode = .center
        }

        if let sourceSize = obj.size?.vectorValue, sourceSize.0 > 0 {
            label.preferredMaxLayoutWidth = max(1, CGFloat(sourceSize.0) - (padding * 2))
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
        }

        return label
    }

    private func textFontName(reference: String?, wallpaperDir: URL) -> String? {
        let defaultFontName = NSFont.systemFont(ofSize: NSFont.systemFontSize).fontName
        guard let reference else { return defaultFontName }

        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else { return defaultFontName }

        // `systemfont_arial` is the convention used by many source scenes.
        // Prefer the font's actual PostScript name so SpriteKit can resolve it.
        let systemReference = trimmedReference
            .replacingOccurrences(of: "systemfont_", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
        for candidate in [trimmedReference, systemReference] {
            if let font = NSFont(name: candidate, size: NSFont.systemFontSize) {
                return font.fontName
            }
        }

        var paths = [String]()
        func appendPath(_ path: String) {
            guard !path.isEmpty, !paths.contains(path) else { return }
            paths.append(path)
        }

        appendPath(trimmedReference)
        if !trimmedReference.hasPrefix("materials/") {
            appendPath("materials/fonts/\(trimmedReference)")
            appendPath("materials/\(trimmedReference)")
        }
        if (trimmedReference as NSString).pathExtension.isEmpty {
            for extensionName in ["ttf", "otf"] {
                appendPath("\(trimmedReference).\(extensionName)")
                if !trimmedReference.hasPrefix("materials/") {
                    appendPath("materials/fonts/\(trimmedReference).\(extensionName)")
                }
            }
        }

        for path in paths {
            if let name = registerTextFont(path: path, wallpaperDir: wallpaperDir) {
                return name
            }
        }
        return defaultFontName
    }

    private func registerTextFont(path: String, wallpaperDir: URL) -> String? {
        let cacheKey = "\(wallpaperDir.path):\(path)"
        if let existingName = Self.registeredTextFonts[cacheKey] {
            return existingName
        }
        guard let fontData = loadSceneAssetData(path: path, wallpaperDir: wallpaperDir) else {
            return nil
        }

        // PKG-contained fonts have no stable file URL.  Core Text's supported
        // process registration API accepts URLs, so materialize the data in the
        // system temporary directory for this app run rather than relying on
        // the deprecated graphics-font registration API.
        let extensionName = (path as NSString).pathExtension.isEmpty
            ? "ttf"
            : (path as NSString).pathExtension
        let fontDirectory = FileManager.default.temporaryDirectory
            .appending(path: "OpenWallpaperEngine/scene-fonts", directoryHint: .isDirectory)
        let fontURL = fontDirectory.appending(path: "\(UUID().uuidString).\(extensionName)")
        do {
            try FileManager.default.createDirectory(at: fontDirectory, withIntermediateDirectories: true)
            try fontData.write(to: fontURL, options: .atomic)
        } catch {
            Self.log("Unable to stage text font '\(path)': \(error.localizedDescription)")
            return nil
        }

        var registrationError: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError), let registrationError {
            // An already-registered PostScript name is usable as-is.  Keep the
            // diagnostic for malformed fonts but still allow the renderer to
            // request the resolved name below.
            Self.log("Text font registration for '\(path)' returned \(registrationError.takeRetainedValue().localizedDescription)")
        }

        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first,
              let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
            return nil
        }
        Self.registeredTextFonts[cacheKey] = postScriptName
        return postScriptName
    }

    // MARK: - Sound Objects

    /// Mirrors the reference renderer's `CSound`: each `sound` asset is
    /// loaded from the loose directory or scene package and repeats only when
    /// the object's playback mode is `loop`.  Playback rate/volume follow the
    /// shared wallpaper controls just like video wallpapers do.
    @discardableResult
    private func buildSceneSoundPlayers(
        _ paths: [String],
        playbackMode: String?,
        wallpaperDir: URL
    ) -> Int {
        let shouldLoop = playbackMode?.caseInsensitiveCompare("loop") == .orderedSame
        var createdCount = 0

        for path in paths {
            guard let data = loadSceneAssetData(path: path, wallpaperDir: wallpaperDir) else {
                Self.log("Unable to load scene sound '\(path)'")
                continue
            }
            do {
                let player = try AVAudioPlayer(data: data)
                player.numberOfLoops = shouldLoop ? -1 : 0
                player.enableRate = true
                player.prepareToPlay()
                sceneAudioPlayers.append(player)
                createdCount += 1
            } catch {
                Self.log("Unable to decode scene sound '\(path)': \(error.localizedDescription)")
            }
        }

        return createdCount
    }

    private func observeGlobalPlayback() {
        let wallpaperViewModel = AppDelegate.shared.wallpaperViewModel
        wallpaperViewModel.$playRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.playbackRate = rate
                self?.applySceneAudioPlayback()
            }
            .store(in: &sceneAudioCancellables)
        wallpaperViewModel.$playVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.playbackVolume = volume
                self?.applySceneAudioPlayback()
            }
            .store(in: &sceneAudioCancellables)
    }

    private func applySceneAudioPlayback() {
        let volume = max(0, min(playbackVolume, 1))
        let rate = max(0.25, min(playbackRate, 2))
        for player in sceneAudioPlayers {
            player.volume = volume
            player.rate = rate
            if playbackRate == 0 {
                player.pause()
            } else if !player.isPlaying {
                player.play()
            }
        }
    }

    private func stopSceneAudio() {
        sceneAudioPlayers.forEach { $0.stop() }
        sceneAudioPlayers.removeAll()
    }

    private func configureSceneObjectContainer(
        _ node: SKNode,
        object: WESceneObject,
        sceneSize: CGSize,
        isParented: Bool
    ) {
        let origin = object.origin?.vectorValue ?? (0, 0, 0)
        node.position = isParented
            ? CGPoint(x: origin.0, y: -origin.1)
            : CGPoint(x: origin.0, y: sceneSize.height - origin.1)

        let scale = object.scale?.vectorValue ?? (1, 1, 1)
        node.xScale = safeParticleScalar(scale.0, fallback: 1)
        node.yScale = safeParticleScalar(scale.1, fallback: 1)

        let angle = object.angles?.vectorValue.2 ?? 0
        // Converted local coordinates have a flipped Y axis, so the source
        // angle is inverted before SpriteKit composes parent/child transforms.
        node.zRotation = -safeParticleScalar(angle, fallback: 0)
        node.isHidden = object.visible?.value == false
    }

    // MARK: - Particle Objects

    private func buildParticleNode(_ obj: WESceneObject, wallpaperDir: URL) -> SKNode? {
        guard let particlePath = obj.particle else { return nil }

        let particleSystem: WEParticleSystem? = loadJSON(path: particlePath, wallpaperDir: wallpaperDir)
        guard let ps = particleSystem else {
            print("[SceneVM] Failed to load particle system '\(particlePath)'")
            return nil
        }

        // SpriteKit cannot reproduce every Wallpaper Engine particle operator,
        // but its emitter maps the common rain/snow/sparkle systems closely.
        // Give it safe defaults first: many scene files omit some initializer
        // blocks and SKEmitterNode otherwise produces no visible particles.
        let overrides = obj.instanceoverride
        let sizeMultiplier = safeParticleScalar(overrides?.size?.value ?? 1, fallback: 1, minimum: 0)
        let baseAlpha = safeParticleScalar(
            overrides?.alpha?.value ?? obj.alpha?.doubleValue ?? 1,
            fallback: 1,
            minimum: 0,
            maximum: 1
        )
        let lifetimeMultiplier = safeParticleScalar(overrides?.lifetime?.value ?? 1, fallback: 1, minimum: 0.05)
        let countMultiplier = safeParticleScalar(overrides?.count?.value ?? 1, fallback: 1, minimum: 0.01)

        let emitter = SKEmitterNode()
        var requestedBirthRate: CGFloat = 10
        emitter.particleLifetime = lifetimeMultiplier
        emitter.particleSize = CGSize(width: 12 * sizeMultiplier, height: 12 * sizeMultiplier)
        emitter.particleColor = .white
        emitter.particleAlpha = baseAlpha
        if let defaultTexture = generateProceduralTexture(named: "particle/default") {
            emitter.particleTexture = SKTexture(image: defaultTexture)
        }

        // Particle texture from material
        if let materialPath = ps.material {
            let material: WEMaterial? = loadJSON(path: materialPath, wallpaperDir: wallpaperDir)
            if let texName = material?.passes?.first?.textures?.first {
                if let textureAsset = loadTextureAsset(
                    named: texName,
                    materialDir: materialPath,
                    wallpaperDir: wallpaperDir
                ) {
                    emitter.particleTexture = SKTexture(image: textureAsset.image)
                    applyParticleTextureAnimation(
                        textureAsset.animationFrames,
                        to: emitter,
                        animationMode: ps.animationmode,
                        speedMultiplier: ps.sequencemultiplier
                    )
                } else if let fallbackImage = generateProceduralTexture(named: texName) {
                    emitter.particleTexture = SKTexture(image: fallbackImage)
                }
            }

            // Blend mode
            if let blending = material?.passes?.first?.blending {
                emitter.particleBlendMode = blending == "additive" ? .add : .alpha
            }
        }

        // Emitter properties.  Emitter origins are local to the scene object,
        // while particlePositionRange approximates WE's box/sphere spawn area.
        if let em = ps.emitter?.first {
            let rateMultiplier = safeParticleScalar(overrides?.rate?.value ?? 1, fallback: 1, minimum: 0)
            requestedBirthRate = safeParticleScalar(em.rate?.doubleValue ?? 10, fallback: 10, minimum: 0) * rateMultiplier

            if let origin = em.origin {
                let (x, y, _) = origin.parseVector3()
                emitter.particlePosition = CGPoint(x: x, y: -y)
            }

            let maximumDistance = em.distancemax?.vectorValue ?? (0, 0, 0)
            let minimumDistance = em.distancemin?.vectorValue ?? (0, 0, 0)
            let rangeX = max(abs(maximumDistance.0), abs(minimumDistance.0))
            let rangeY = max(abs(maximumDistance.1), abs(minimumDistance.1))
            if rangeX > 0 || rangeY > 0 {
                emitter.particlePositionRange = CGVector(
                    dx: safeParticleScalar(rangeX * 2, fallback: 0, minimum: 0),
                    dy: safeParticleScalar(rangeY * 2, fallback: 0, minimum: 0)
                )
            }
        }

        if let colorString = obj.instanceoverride?.colorn {
            let color = colorString.parseColor()
            emitter.particleColor = particleColor(from: color)
        }

        // Initializers
        for ini in ps.initializer ?? [] {
            switch ini.name {
            case "lifetimerandom":
                let lifetimeRange = orderedParticleRange(
                    ini.min?.doubleValue ?? 1,
                    ini.max?.doubleValue ?? 1,
                    fallback: 1
                )
                emitter.particleLifetime = safeParticleScalar(
                    ((lifetimeRange.lowerBound + lifetimeRange.upperBound) / 2) * Double(lifetimeMultiplier),
                    fallback: 1,
                    minimum: 0.05
                )
                emitter.particleLifetimeRange = safeParticleScalar(
                    (lifetimeRange.upperBound - lifetimeRange.lowerBound) * Double(lifetimeMultiplier),
                    fallback: 0,
                    minimum: 0
                )

            case "sizerandom":
                let sizeRange = orderedParticleRange(
                    ini.min?.doubleValue ?? 12,
                    ini.max?.doubleValue ?? 12,
                    fallback: 12
                )
                let averageSize = max((sizeRange.lowerBound + sizeRange.upperBound) / 2, 0.01)
                emitter.particleSize = CGSize(
                    width: safeParticleScalar(averageSize * Double(sizeMultiplier), fallback: 12, minimum: 0.01),
                    height: safeParticleScalar(averageSize * Double(sizeMultiplier), fallback: 12, minimum: 0.01)
                )
                emitter.particleScaleRange = safeParticleScalar(
                    ((sizeRange.upperBound - sizeRange.lowerBound) / averageSize) * Double(sizeMultiplier),
                    fallback: 0,
                    minimum: 0
                )

            case "velocityrandom":
                let minV = ini.min?.vectorValue ?? (0, 0, 0)
                let maxV = ini.max?.vectorValue ?? (0, 0, 0)
                let avgSpeedY = (minV.1 + maxV.1) / 2
                let avgSpeedX = (minV.0 + maxV.0) / 2
                let speed = sqrt(avgSpeedX * avgSpeedX + avgSpeedY * avgSpeedY)
                let minSpeed = sqrt(minV.0 * minV.0 + minV.1 * minV.1)
                let maxSpeed = sqrt(maxV.0 * maxV.0 + maxV.1 * maxV.1)
                let speedMultiplier = safeParticleScalar(overrides?.speed?.value ?? 1, fallback: 1, minimum: 0)
                emitter.particleSpeed = safeParticleScalar(
                    ((minSpeed + maxSpeed) / 2) * Double(speedMultiplier),
                    fallback: 0,
                    minimum: 0
                )
                emitter.particleSpeedRange = safeParticleScalar(
                    abs(maxSpeed - minSpeed) * Double(speedMultiplier),
                    fallback: 0,
                    minimum: 0
                )
                if speed > 0 {
                    emitter.emissionAngle = CGFloat(atan2(-avgSpeedY, avgSpeedX))
                    let spansBothDirections = minV.0 * maxV.0 < 0 || minV.1 * maxV.1 < 0
                    emitter.emissionAngleRange = spansBothDirections ? .pi : 0.1
                }

            case "alpharandom":
                let alphaRange = orderedParticleRange(
                    ini.min?.doubleValue ?? 1,
                    ini.max?.doubleValue ?? 1,
                    fallback: 1
                )
                emitter.particleAlpha = safeParticleScalar(
                    ((alphaRange.lowerBound + alphaRange.upperBound) / 2) * Double(baseAlpha),
                    fallback: 1,
                    minimum: 0,
                    maximum: 1
                )
                emitter.particleAlphaRange = safeParticleScalar(
                    (alphaRange.upperBound - alphaRange.lowerBound) * Double(baseAlpha),
                    fallback: 0,
                    minimum: 0,
                    maximum: 1
                )

            case "colorrandom":
                let minColor = ini.min?.vectorValue ?? (1, 1, 1)
                let maxColor = ini.max?.vectorValue ?? minColor
                emitter.particleColor = particleColor(from: (
                    (minColor.0 + maxColor.0) / 2,
                    (minColor.1 + maxColor.1) / 2,
                    (minColor.2 + maxColor.2) / 2
                ))

            case "rotationrandom":
                let minRotation = ini.min?.vectorValue ?? (0, 0, 0)
                let maxRotation = ini.max?.vectorValue ?? (0, 0, 0)
                let rotationRange = orderedParticleRange(
                    minRotation.2,
                    maxRotation.2,
                    fallback: 0
                )
                emitter.particleRotation = CGFloat(-(rotationRange.lowerBound + rotationRange.upperBound) / 2)
                emitter.particleRotationRange = CGFloat(rotationRange.upperBound - rotationRange.lowerBound)

            case "angularvelocityrandom":
                let minAngularVelocity = ini.min?.vectorValue ?? (0, 0, 0)
                let maxAngularVelocity = ini.max?.vectorValue ?? (0, 0, 0)
                let angularRange = orderedParticleRange(
                    minAngularVelocity.2,
                    maxAngularVelocity.2,
                    fallback: 0
                )
                emitter.particleRotationSpeed = CGFloat(-(angularRange.lowerBound + angularRange.upperBound) / 2)

            default:
                break
            }
        }

        // Operators
        for op in ps.operator ?? [] {
            switch op.name {
            case "movement":
                if let gravity = op.gravity?.vectorValue {
                    emitter.xAcceleration = safeParticleScalar(gravity.0, fallback: 0)
                    emitter.yAcceleration = safeParticleScalar(-gravity.1, fallback: 0)
                }

            case "alphafade":
                applyAlphaFade(
                    to: emitter,
                    fadeIn: op.fadeintime?.doubleValue ?? 0,
                    fadeOut: op.fadeouttime?.doubleValue ?? 0
                )

            case "sizechange":
                // Wallpaper Engine changes the particle's scale relative to
                // its initialized size.  SpriteKit expresses the same idea as
                // a lifetime scale sequence, so the randomized initial size
                // remains intact.
                applyScaleChange(
                    to: emitter,
                    startTime: op.starttime?.doubleValue ?? 0,
                    endTime: op.endtime?.doubleValue ?? 1,
                    startValue: op.startvalue?.doubleValue ?? 1,
                    endValue: op.endvalue?.doubleValue ?? 0
                )

            case "alphachange":
                // The upstream operator multiplies initial alpha.  Capture
                // the current SpriteKit base alpha so this also respects the
                // alpha initializer and scene instance override.
                applyAlphaChange(
                    to: emitter,
                    startTime: op.starttime?.doubleValue ?? 0,
                    endTime: op.endtime?.doubleValue ?? 1,
                    startValue: op.startvalue?.doubleValue ?? 1,
                    endValue: op.endvalue?.doubleValue ?? 0
                )

            case "colorchange":
                // Like the Linux renderer, use the operator's colours as
                // multipliers of the initialized particle colour instead of
                // replacing it outright.
                applyColorChange(
                    to: emitter,
                    startTime: op.starttime?.doubleValue ?? 0,
                    endTime: op.endtime?.doubleValue ?? 1,
                    startValue: op.startvalue?.vectorValue ?? (1, 1, 1),
                    endValue: op.endvalue?.vectorValue ?? (1, 1, 1)
                )

            default:
                break
            }
        }

        // Renderer: spritetrail gets elongated aspect ratio
        if let renderer = ps.renderer?.first, renderer.name == "spritetrail" {
            let trailLength = safeParticleScalar(renderer.maxlength ?? renderer.length ?? 50, fallback: 50, minimum: 1)
            emitter.particleSize = CGSize(width: max(emitter.particleSize.width, 1), height: trailLength)
            // Align particles to movement direction
            emitter.particleRotation = emitter.emissionAngle
        }

        // SKEmitterNode does not expose a live-particle pool size.  Restrict
        // the birth rate by the source maxcount so malformed Workshop files
        // cannot exhaust the SpriteKit renderer.
        let requestedMaxCount = safeParticleScalar(
            (ps.maxcount?.doubleValue ?? 1_000) * Double(countMultiplier),
            fallback: 1_000,
            minimum: 1,
            maximum: 4_096
        )
        let shortestLifetime = max(emitter.particleLifetime - emitter.particleLifetimeRange / 2, 0.05)
        emitter.particleBirthRate = min(requestedBirthRate, requestedMaxCount / shortestLifetime)
        emitter.numParticlesToEmit = 0 // infinite

        return emitter
    }

    private func orderedParticleRange(_ first: Double, _ second: Double, fallback: Double) -> ClosedRange<Double> {
        let lower = first.isFinite ? first : fallback
        let upper = second.isFinite ? second : fallback
        return min(lower, upper)...max(lower, upper)
    }

    private func safeParticleScalar(
        _ value: Double,
        fallback: Double,
        minimum: Double = -Double.greatestFiniteMagnitude,
        maximum: Double = Double.greatestFiniteMagnitude
    ) -> CGFloat {
        let finiteValue = value.isFinite ? value : fallback
        return CGFloat(min(max(finiteValue, minimum), maximum))
    }

    private func particleColor(from value: (Double, Double, Double)) -> NSColor {
        // Scene JSON usually stores particle colors as 0...255, but a few
        // authored wallpapers use normalized 0...1 components.
        let normalizer = max(abs(value.0), abs(value.1), abs(value.2)) > 1 ? 255.0 : 1.0
        return NSColor(
            red: safeParticleScalar(value.0 / normalizer, fallback: 1, minimum: 0, maximum: 1),
            green: safeParticleScalar(value.1 / normalizer, fallback: 1, minimum: 0, maximum: 1),
            blue: safeParticleScalar(value.2 / normalizer, fallback: 1, minimum: 0, maximum: 1),
            alpha: 1
        )
    }

    private func applyAlphaFade(to emitter: SKEmitterNode, fadeIn: Double, fadeOut: Double) {
        let lifetime = max(Double(emitter.particleLifetime), 0.05)
        let fadeInFraction = min(max(fadeIn / lifetime, 0), 0.99)
        let fadeOutStart = max(fadeInFraction, min(1 - max(fadeOut, 0) / lifetime, 1))
        guard fadeInFraction > 0 || fadeOutStart < 1 else { return }

        emitter.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [
                NSNumber(value: 0),
                NSNumber(value: Double(emitter.particleAlpha)),
                NSNumber(value: Double(emitter.particleAlpha)),
                NSNumber(value: 0),
            ],
            times: [
                NSNumber(value: 0),
                NSNumber(value: fadeInFraction),
                NSNumber(value: fadeOutStart),
                NSNumber(value: 1),
            ]
        )
    }

    /// Build an SKKeyframeSequence timeline equivalent to the upstream
    /// `fadeValue(life, startTime, endTime, startValue, endValue)` helper.
    /// The source times are lifetime fractions, not seconds.  It holds the
    /// start value before `startTime`, interpolates to `endValue`, then holds
    /// that final value for the remainder of the particle's lifetime.
    private func particleLifecycleKeyframeTimes(startTime: Double, endTime: Double) -> [NSNumber] {
        let start = min(max(startTime.isFinite ? startTime : 0, 0), 1)
        let end = min(max(endTime.isFinite ? endTime : 1, 0), 1)

        // Wallpaper Engine treats an inverted or zero-width interval as a
        // step: it preserves the start value through `startTime`, then uses
        // the end value.  Keep a very small non-zero segment because SpriteKit
        // keyframes are interpolated and cannot express an exact discontinuity.
        if end <= start {
            guard start < 1 else {
                return [NSNumber(value: 0), NSNumber(value: 1)]
            }
            let stepEnd = min(start + 0.0001, 1)
            return [
                NSNumber(value: 0),
                NSNumber(value: start),
                NSNumber(value: stepEnd),
                NSNumber(value: 1),
            ]
        }

        return [
            NSNumber(value: 0),
            NSNumber(value: start),
            NSNumber(value: end),
            NSNumber(value: 1),
        ]
    }

    private func applyScaleChange(
        to emitter: SKEmitterNode,
        startTime: Double,
        endTime: Double,
        startValue: Double,
        endValue: Double
    ) {
        let startScale = safeParticleScalar(startValue, fallback: 1, minimum: 0)
        let endScale = safeParticleScalar(endValue, fallback: 0, minimum: 0)
        let times = particleLifecycleKeyframeTimes(startTime: startTime, endTime: endTime)
        let values: [NSNumber]

        if times.count == 2 {
            values = [NSNumber(value: Double(startScale)), NSNumber(value: Double(startScale))]
        } else {
            values = [
                NSNumber(value: Double(startScale)),
                NSNumber(value: Double(startScale)),
                NSNumber(value: Double(endScale)),
                NSNumber(value: Double(endScale)),
            ]
        }

        emitter.particleScaleSequence = SKKeyframeSequence(keyframeValues: values, times: times)
    }

    private func applyAlphaChange(
        to emitter: SKEmitterNode,
        startTime: Double,
        endTime: Double,
        startValue: Double,
        endValue: Double
    ) {
        let baseAlpha = Double(emitter.particleAlpha)
        let startAlpha = safeParticleScalar(baseAlpha * startValue, fallback: baseAlpha, minimum: 0, maximum: 1)
        let endAlpha = safeParticleScalar(baseAlpha * endValue, fallback: baseAlpha, minimum: 0, maximum: 1)
        let times = particleLifecycleKeyframeTimes(startTime: startTime, endTime: endTime)
        let values: [NSNumber]

        if times.count == 2 {
            values = [NSNumber(value: Double(startAlpha)), NSNumber(value: Double(startAlpha))]
        } else {
            values = [
                NSNumber(value: Double(startAlpha)),
                NSNumber(value: Double(startAlpha)),
                NSNumber(value: Double(endAlpha)),
                NSNumber(value: Double(endAlpha)),
            ]
        }

        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: values, times: times)
    }

    private func applyColorChange(
        to emitter: SKEmitterNode,
        startTime: Double,
        endTime: Double,
        startValue: (Double, Double, Double),
        endValue: (Double, Double, Double)
    ) {
        let baseColor = emitter.particleColor
        let startColor = particleColor(baseColor, multipliedBy: startValue)
        let endColor = particleColor(baseColor, multipliedBy: endValue)
        let times = particleLifecycleKeyframeTimes(startTime: startTime, endTime: endTime)
        let values: [NSColor]

        if times.count == 2 {
            values = [startColor, startColor]
        } else {
            values = [startColor, startColor, endColor, endColor]
        }

        emitter.particleColorSequence = SKKeyframeSequence(keyframeValues: values, times: times)
    }

    private func particleColor(
        _ color: NSColor,
        multipliedBy multiplier: (Double, Double, Double)
    ) -> NSColor {
        let source = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            red: safeParticleScalar(Double(source.redComponent) * multiplier.0, fallback: 1, minimum: 0, maximum: 1),
            green: safeParticleScalar(Double(source.greenComponent) * multiplier.1, fallback: 1, minimum: 0, maximum: 1),
            blue: safeParticleScalar(Double(source.blueComponent) * multiplier.2, fallback: 1, minimum: 0, maximum: 1),
            alpha: source.alphaComponent
        )
    }

    // MARK: - Camera Parallax

    private func configureParallax(from general: WESceneGeneral, sceneSize: CGSize) {
        parallaxNodes = []
        parallaxDisplacement = .zero
        lastParallaxUpdateTime = nil

        guard general.cameraparallax?.value == true else {
            parallaxConfiguration = nil
            return
        }

        parallaxConfiguration = ParallaxConfiguration(
            amount: safeParticleScalar(
                general.cameraparallaxamount?.doubleValue ?? 1,
                fallback: 1,
                minimum: -5,
                maximum: 5
            ),
            delay: safeParticleScalar(
                general.cameraparallaxdelay?.doubleValue ?? 0,
                fallback: 0,
                minimum: 0,
                maximum: 60
            ),
            mouseInfluence: safeParticleScalar(
                general.cameraparallaxmouseinfluence?.doubleValue ?? 1,
                fallback: 1,
                minimum: 0,
                maximum: 5
            ),
            referenceSize: max(sceneSize.width, 1)
        )
    }

    private func registerParallax(node: SKNode, object: WESceneObject, isParticle: Bool) {
        guard parallaxConfiguration != nil else { return }

        let sourceDepth = object.parallaxDepth?.vectorValue ?? (0, 0, 0)
        var depth = CGPoint(
            x: safeParticleScalar(sourceDepth.0, fallback: 0, minimum: -10, maximum: 10),
            y: safeParticleScalar(sourceDepth.1, fallback: 0, minimum: -10, maximum: 10)
        )

        // The upstream renderer enforces a minimum depth for particles so a
        // source file with a zero depth still visibly follows camera motion.
        if isParticle {
            let minimumDepth: CGFloat = 0.65
            if abs(depth.x) < minimumDepth {
                depth.x = depth.x < 0 ? -minimumDepth : minimumDepth
            }
            if abs(depth.y) < minimumDepth {
                depth.y = depth.y < 0 ? -minimumDepth : minimumDepth
            }
        }

        parallaxNodes.append(ParallaxNode(node: node, basePosition: node.position, depth: depth))
    }

    fileprivate func updateParallax(in view: SKView?, currentTime: TimeInterval) {
        guard let configuration = parallaxConfiguration,
              !parallaxNodes.isEmpty,
              let view,
              let window = view.window,
              view.bounds.width > 0,
              view.bounds.height > 0 else {
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = view.convert(windowPoint, from: nil)
        let normalizedX = min(max((viewPoint.x - view.bounds.minX) / view.bounds.width, 0), 1)
        // Wallpaper Engine scene JSON uses a top-left origin.  Convert the
        // AppKit bottom-left coordinate into the same normalized convention.
        let normalizedY = 1 - min(max((viewPoint.y - view.bounds.minY) / view.bounds.height, 0), 1)

        let targetDisplacement = CGPoint(
            x: (normalizedX - 0.5) * configuration.amount * configuration.mouseInfluence,
            y: (normalizedY - 0.5) * configuration.amount * configuration.mouseInfluence
        )
        let deltaTime = lastParallaxUpdateTime.map { max(0, min(currentTime - $0, 0.1)) } ?? 0
        lastParallaxUpdateTime = currentTime
        // A zero delay means immediate response; positive values use the
        // upstream-style time-scaled smoothing factor.
        let smoothing = configuration.delay == 0 ? 1 : min(configuration.delay * deltaTime, 1)
        parallaxDisplacement.x += (targetDisplacement.x - parallaxDisplacement.x) * smoothing
        parallaxDisplacement.y += (targetDisplacement.y - parallaxDisplacement.y) * smoothing

        for binding in parallaxNodes {
            let offsetX = (binding.depth.x + configuration.amount)
                * parallaxDisplacement.x * configuration.referenceSize
            let offsetY = (binding.depth.y + configuration.amount)
                * parallaxDisplacement.y * configuration.referenceSize
            binding.node.position = CGPoint(
                x: binding.basePosition.x + offsetX,
                y: binding.basePosition.y + offsetY
            )
        }
    }

    private func applyTextureAnimation(_ frames: [TEXAnimationFrame], to node: SKSpriteNode) {
        guard frames.count > 1 else { return }

        var actions: [SKAction] = []
        actions.reserveCapacity(frames.count * 2)
        for frame in frames {
            actions.append(SKAction.setTexture(SKTexture(image: frame.image), resize: false))
            actions.append(SKAction.wait(forDuration: max(frame.duration, 1.0 / 60.0)))
        }
        node.run(.repeatForever(.sequence(actions)), withKey: "wallpaper-engine-texs-animation")
    }

    /// SpriteKit's emitter API has one texture for the whole particle system,
    /// rather than a per-particle texture sequence.  Updating it in the scene
    /// timeline nevertheless makes the common looping and random-frame TEXS
    /// particle materials animate, while the existing particle lifetime and
    /// movement simulation remains handled by SKEmitterNode.
    private func applyParticleTextureAnimation(
        _ frames: [TEXAnimationFrame],
        to emitter: SKEmitterNode,
        animationMode: String?,
        speedMultiplier: Double?
    ) {
        guard frames.count > 1 else { return }

        let configuredSpeed = speedMultiplier ?? 1
        let speed = configuredSpeed.isFinite && configuredSpeed > 0 ? configuredSpeed : 1
        let frameActions: [SKAction] = frames.map { frame in
            .sequence([
                .run { [weak emitter] in
                    emitter?.particleTexture = SKTexture(image: frame.image)
                },
                .wait(forDuration: max(frame.duration / speed, 1.0 / 60.0)),
            ])
        }

        let sequence: SKAction
        if animationMode == "once" {
            sequence = .sequence(frameActions)
        } else if animationMode == "randomframe" {
            let averageDuration = max(
                frames.map(\.duration).reduce(0, +) / Double(frames.count) / speed,
                1.0 / 60.0
            )
            sequence = .repeatForever(.sequence([
                .run { [weak emitter] in
                    guard let frame = frames.randomElement() else { return }
                    emitter?.particleTexture = SKTexture(image: frame.image)
                },
                .wait(forDuration: averageDuration),
            ]))
        } else {
            sequence = .repeatForever(.sequence(frameActions))
        }
        emitter.run(sequence, withKey: "wallpaper-engine-particle-texture-animation")
    }

    // MARK: - Asset Loading

    private func loadJSON<T: Decodable>(path: String, wallpaperDir: URL) -> T? {
        // Try PKG first
        if let parser = pkgParser, let data = parser.extractFile(named: path) {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        // Fall back to loose file
        let url = wallpaperDir.appending(path: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func loadSceneAssetData(path: String, wallpaperDir: URL) -> Data? {
        if let parser = pkgParser, let data = parser.extractFile(named: path) {
            return Data(data)
        }
        return try? Data(contentsOf: wallpaperDir.appending(path: path))
    }

    private func loadTexture(named name: String, materialDir: String, wallpaperDir: URL) -> NSImage? {
        loadTextureAsset(named: name, materialDir: materialDir, wallpaperDir: wallpaperDir)?.image
    }

    private func loadTextureAsset(
        named name: String,
        materialDir: String,
        wallpaperDir: URL
    ) -> SceneTextureAsset? {
        // Build candidate .tex paths: relative to material dir, then relative to materials/ root.
        // Most material JSON uses extensionless texture names, but exported
        // scenes can explicitly reference `foo.tex` or `foo.png`; preserve
        // that extension instead of producing paths such as `foo.png.png`.
        let materialDirPath = (materialDir as NSString).deletingLastPathComponent
        let explicitExtension = (name as NSString).pathExtension.lowercased()
        let textureFileName = explicitExtension == "tex" ? name : "\(name).tex"
        var texPaths = [String]()
        func appendTexPath(_ path: String) {
            guard !texPaths.contains(path) else { return }
            texPaths.append(path)
        }
        if !materialDirPath.isEmpty {
            appendTexPath("\(materialDirPath)/\(textureFileName)")
        }
        // Also try materials/{name}.tex for textures with embedded paths (e.g. "workshop/xxx/foo")
        let materialsRoot = materialDirPath.split(separator: "/").first.map(String.init) ?? "materials"
        appendTexPath("\(materialsRoot)/\(textureFileName)")
        appendTexPath(textureFileName)

        for texPath in texPaths {
            // Try .tex from PKG
            if let parser = pkgParser, let texData = parser.extractFile(named: texPath) {
                Self.log("  TEX from PKG '\(texPath)' size=\(texData.count)")
                let texParser = TEXParser(data: Data(texData))  // Copy to reset indices
                if let image = texParser.extractImage() {
                    return SceneTextureAsset(
                        image: image,
                        animationFrames: texParser.extractAnimationFrames(
                            spriteSheetMetadata: loadSpriteSheetMetadata(
                                forTexturePath: texPath,
                                wallpaperDir: wallpaperDir
                            )
                        )
                    )
                }
                Self.log("  TEXParser.extractImage() returned nil for '\(texPath)'")
            }

            // Try .tex from loose file
            let texURL = wallpaperDir.appending(path: texPath)
            if let texData = try? Data(contentsOf: texURL) {
                let texParser = TEXParser(data: texData)
                if let image = texParser.extractImage() {
                    return SceneTextureAsset(
                        image: image,
                        animationFrames: texParser.extractAnimationFrames(
                            spriteSheetMetadata: loadSpriteSheetMetadata(
                                forTexturePath: texPath,
                                wallpaperDir: wallpaperDir
                            )
                        )
                    )
                }
            }
        }

        // Try common image formats directly.  If the material supplies an
        // image extension, try that exact path before extensionless fallbacks.
        let imageExtensions = ["png", "jpg", "jpeg", "gif"]
        var imagePaths = [String]()
        func appendImagePath(_ path: String) {
            guard !imagePaths.contains(path) else { return }
            imagePaths.append(path)
        }
        if imageExtensions.contains(explicitExtension) {
            if !materialDirPath.isEmpty {
                appendImagePath("\(materialDirPath)/\(name)")
            }
            appendImagePath(name)
        }
        for ext in imageExtensions {
            let imageName = explicitExtension.isEmpty ? "\(name).\(ext)" : name
            let imgPath = materialDirPath.isEmpty ? imageName : "\(materialDirPath)/\(imageName)"
            appendImagePath(imgPath)
        }

        for imgPath in imagePaths {
            if let parser = pkgParser, let imgData = parser.extractFile(named: imgPath) {
                if let image = NSImage(data: imgData) {
                    return SceneTextureAsset(image: image, animationFrames: [])
                }
            }
            let imgURL = wallpaperDir.appending(path: imgPath)
            if let image = NSImage(contentsOf: imgURL) {
                return SceneTextureAsset(image: image, animationFrames: [])
            }
        }

        Self.log("  No texture found for '\(name)'")
        return nil
    }

    /// The reference renderer looks for `materials/<texture>.tex-json` to
    /// obtain static sprite-sheet sequences.  Keep two historical spellings
    /// as fallbacks because Workshop assets exist with both `.tex-json` and
    /// `.tex.json` names.
    private func loadSpriteSheetMetadata(forTexturePath texPath: String, wallpaperDir: URL) -> Data? {
        let pathWithoutExtension = (texPath as NSString).deletingPathExtension
        let candidates = [
            "\(pathWithoutExtension).tex-json",
            "\(texPath)-json",
            "\(texPath).json",
        ]

        for path in candidates {
            if let parser = pkgParser, let data = parser.extractFile(named: path) {
                return data
            }
            let url = wallpaperDir.appending(path: path)
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }

    /// Generate simple procedural textures for built-in particle names
    private func generateProceduralTexture(named name: String) -> NSImage? {
        let size: CGFloat = 32

        switch name {
        case "particle/drop":
            // Elongated raindrop: bright center, soft edges
            return generateRadialGradient(size: CGSize(width: 4, height: 16), color: .white)

        case _ where name.contains("halo"):
            // Soft circular glow
            return generateRadialGradient(size: CGSize(width: size, height: size), color: .white)

        default:
            // Generic soft circle
            return generateRadialGradient(size: CGSize(width: size, height: size), color: .white)
        }
    }

    private func generateRadialGradient(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Convert to RGB color space to guarantee 4 components (r, g, b, a)
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent
        let a = rgbColor.alphaComponent
        let colors = [
            CGColor(colorSpace: colorSpace, components: [r, g, b, a])!,
            CGColor(colorSpace: colorSpace, components: [r, g, b, 0])!
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius, options: [])

        image.unlockFocus()
        return image
    }

    // MARK: - System Events

    @objc func systemWillSleep(_ notification: Notification) {
        print("[SceneVM] System is going to sleep")
        skScene?.isPaused = true
        sceneAudioPlayers.forEach { $0.pause() }
    }

    @objc func systemDidWake(_ notification: Notification) {
        print("[SceneVM] System woke up")
        skScene?.isPaused = playbackRate == 0
        applySceneAudioPlayback()
    }
}

/// SpriteKit invokes `update(_:)` once per rendered frame.  Keeping parallax
/// here avoids a global mouse monitor and keeps movement scoped to the active
/// wallpaper view.
private final class WEParallaxSKScene: SKScene {
    weak var parallaxOwner: SceneWallpaperViewModel?

    override func update(_ currentTime: TimeInterval) {
        parallaxOwner?.updateParallax(in: view, currentTime: currentTime)
    }
}
