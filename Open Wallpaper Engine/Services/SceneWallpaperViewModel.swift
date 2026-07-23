//
//  SceneWallpaperViewModel.swift
//  Open Wallpaper Engine
//
//  Loads and renders Wallpaper Engine scene wallpapers using SpriteKit.
//  Follows the same ViewModel pattern as VideoWallpaperViewModel.
//

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

    init(wallpaper: WEWallpaper) {
        self.currentWallpaper = wallpaper
        Self.log("init: wallpaper=\(wallpaper.project.title) dir=\(wallpaper.wallpaperDirectory.path)")
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        loadScene(from: wallpaper)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Scene Loading

    func loadScene(from wallpaper: WEWallpaper) {
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

        // Preserve source order: scene image layers and particle systems are
        // composited in the same order that the upstream renderer creates them.
        var hasImage = false
        var particleCount = 0
        for (index, obj) in scene.objects.enumerated() {
            guard obj.visible != false else { continue }
            if obj.image != nil,
               let node = buildImageNode(obj, wallpaperDir: wallpaperDir, sceneSize: skScene.size) {
                node.zPosition = CGFloat(index)
                skScene.addChild(node)
                registerParallax(node: node, object: obj, isParticle: false)
                hasImage = true
            } else if obj.particle != nil,
                      let node = buildParticleNode(obj, wallpaperDir: wallpaperDir, sceneSize: skScene.size) {
                node.zPosition = CGFloat(index)
                skScene.addChild(node)
                registerParallax(node: node, object: obj, isParticle: true)
                particleCount += 1
            }
        }
        Self.log("Scene render nodes: \(skScene.children.count) (\(particleCount) particle systems)")

        // Fallback: use preview image
        if !hasImage {
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
        wallpaperDir: URL,
        sceneSize: CGSize
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
        let image = loadTexture(named: textureName, materialDir: materialPath, wallpaperDir: wallpaperDir)
        guard let image = image else {
            Self.log("FAILED to load texture '\(textureName)' from material dir '\(materialPath)'")
            return nil
        }
        Self.log("Texture loaded: \(image.size)")

        let texture = SKTexture(image: image)
        let node = SKSpriteNode(texture: texture)

        // Size from object, or use pixel dimensions (not point size, which is halved on Retina)
        if let sizeStr = obj.size {
            let (w, h) = sizeStr.parseVector2()
            node.size = CGSize(width: w, height: h)
        } else {
            let pixelW = image.representations.first?.pixelsWide ?? Int(image.size.width)
            let pixelH = image.representations.first?.pixelsHigh ?? Int(image.size.height)
            node.size = CGSize(width: pixelW, height: pixelH)
        }

        // Position: Wallpaper Engine uses a top-left origin with Y-down while
        // SpriteKit uses a bottom-left origin with Y-up.
        if let originStr = obj.origin {
            let (x, y, _) = originStr.parseVector3()
            node.position = CGPoint(x: x, y: sceneSize.height - y)
        }

        // Alpha
        node.alpha = CGFloat(obj.alpha ?? 1.0)

        // Color tint
        if let colorStr = obj.color {
            let c = colorStr.parseColor()
            node.color = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
            node.colorBlendFactor = (obj.colorBlendMode ?? 0) > 0 ? 1.0 : 0.0
        }

        // Blend mode from material
        if let blending = material?.passes?.first?.blending {
            switch blending {
            case "additive": node.blendMode = .add
            case "translucent": node.blendMode = .alpha
            default: node.blendMode = .alpha
            }
        }

        return node
    }

    // MARK: - Particle Objects

    private func buildParticleNode(_ obj: WESceneObject, wallpaperDir: URL, sceneSize: CGSize) -> SKNode? {
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
            overrides?.alpha?.value ?? obj.alpha ?? 1,
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
                let texImage = loadTexture(named: texName, materialDir: materialPath, wallpaperDir: wallpaperDir)
                    ?? generateProceduralTexture(named: texName)
                if let img = texImage {
                    emitter.particleTexture = SKTexture(image: img)
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

        // Position from object origin
        if let originStr = obj.origin {
            let (x, y, _) = originStr.parseVector3()
            emitter.position = CGPoint(x: x, y: sceneSize.height - y)
        }

        // Scale from object
        if let scaleStr = obj.scale {
            let (sx, sy, _) = scaleStr.parseVector3()
            emitter.xScale = CGFloat(sx)
            emitter.yScale = CGFloat(sy)
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

    private func loadTexture(named name: String, materialDir: String, wallpaperDir: URL) -> NSImage? {
        // Build candidate .tex paths: relative to material dir, then relative to materials/ root
        let materialDirPath = (materialDir as NSString).deletingLastPathComponent
        var texPaths = [String]()
        if !materialDirPath.isEmpty {
            texPaths.append("\(materialDirPath)/\(name).tex")
        }
        // Also try materials/{name}.tex for textures with embedded paths (e.g. "workshop/xxx/foo")
        let materialsRoot = materialDirPath.split(separator: "/").first.map(String.init) ?? "materials"
        let rootPath = "\(materialsRoot)/\(name).tex"
        if !texPaths.contains(rootPath) {
            texPaths.append(rootPath)
        }
        texPaths.append("\(name).tex")

        for texPath in texPaths {
            // Try .tex from PKG
            if let parser = pkgParser, let texData = parser.extractFile(named: texPath) {
                Self.log("  TEX from PKG '\(texPath)' size=\(texData.count)")
                let texParser = TEXParser(data: Data(texData))  // Copy to reset indices
                if let image = texParser.extractImage() {
                    return image
                }
                Self.log("  TEXParser.extractImage() returned nil for '\(texPath)'")
            }

            // Try .tex from loose file
            let texURL = wallpaperDir.appending(path: texPath)
            if let texData = try? Data(contentsOf: texURL) {
                let texParser = TEXParser(data: texData)
                if let image = texParser.extractImage() {
                    return image
                }
            }
        }

        // Try common image formats directly
        for ext in ["png", "jpg", "jpeg", "gif"] {
            let imgPath = materialDirPath.isEmpty ? "\(name).\(ext)" : "\(materialDirPath)/\(name).\(ext)"
            if let parser = pkgParser, let imgData = parser.extractFile(named: imgPath) {
                if let image = NSImage(data: imgData) { return image }
            }
            let imgURL = wallpaperDir.appending(path: imgPath)
            if let image = NSImage(contentsOf: imgURL) { return image }
        }

        Self.log("  No texture found for '\(name)'")
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
    }

    @objc func systemDidWake(_ notification: Notification) {
        print("[SceneVM] System woke up")
        skScene?.isPaused = false
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
