import AppKit
import AVFoundation
import CoreMedia
import QuartzCore

enum DemoVideoError: Error {
    case missingTrack(String)
    case cannotCreateCompositionTrack
    case cannotCreateExporter
    case exportFailed(String)
}

func textLayer(
    _ text: String,
    frame: CGRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    wrapped: Bool = true
) -> CATextLayer {
    let layer = CATextLayer()
    layer.string = text
    layer.frame = frame
    layer.font = NSFont.systemFont(ofSize: size, weight: weight)
    layer.fontSize = size
    layer.foregroundColor = color.cgColor
    layer.contentsScale = 2
    layer.isWrapped = wrapped
    layer.alignmentMode = .left
    layer.truncationMode = .end
    return layer
}

func makePill(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> CALayer {
    let pill = CALayer()
    pill.frame = CGRect(x: x, y: y, width: width, height: 54)
    pill.backgroundColor = NSColor.white.withAlphaComponent(0.11).cgColor
    pill.cornerRadius = 27
    pill.addSublayer(textLayer(
        text,
        frame: CGRect(x: 24, y: 13, width: width - 48, height: 30),
        size: 21,
        weight: .semibold,
        color: NSColor(calibratedRed: 1, green: 0.96, blue: 0.84, alpha: 1),
        wrapped: false
    ))
    return pill
}

func assemble() async throws {
    let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let folder = workspace.appendingPathComponent("docs/devpost-video")
    let videoURL = folder.appendingPathComponent("raw-demo.mp4")
    let audioURL = folder.appendingPathComponent("voiceover.aiff")
    let outputURL = folder.appendingPathComponent("Voya-OpenAI-Build-Week-Demo-v1.mp4")

    let videoAsset = AVURLAsset(url: videoURL)
    let audioAsset = AVURLAsset(url: audioURL)

    guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
        throw DemoVideoError.missingTrack("video")
    }
    guard let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
        throw DemoVideoError.missingTrack("audio")
    }

    let videoDuration = try await videoAsset.load(.duration)
    let audioDuration = try await audioAsset.load(.duration)
    let naturalSize = try await sourceVideo.load(.naturalSize)
    let preferredTransform = try await sourceVideo.load(.preferredTransform)

    let composition = AVMutableComposition()
    guard let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ), let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw DemoVideoError.cannotCreateCompositionTrack
    }

    try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: sourceVideo,
        at: .zero
    )
    let outputVideoDuration = CMTime(seconds: 140, preferredTimescale: 600)
    videoTrack.scaleTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        toDuration: outputVideoDuration
    )
    let voiceStart = CMTime(seconds: 1.0, preferredTimescale: 600)
    try audioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: audioDuration),
        of: sourceAudio,
        at: voiceStart
    )

    let renderSize = CGSize(width: 1920, height: 1080)
    let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    let orientedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
    let targetHeight: CGFloat = 1000
    let scale = targetHeight / orientedSize.height
    let targetWidth = orientedSize.width * scale
    let targetX = renderSize.width - targetWidth - 92
    let targetY: CGFloat = 40

    let normalizedTransform = preferredTransform.concatenating(
        CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
    )
    let finalTransform = normalizedTransform
        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        .concatenating(CGAffineTransform(translationX: targetX, y: targetY))

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(finalTransform, at: .zero)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: outputVideoDuration)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = [instruction]

    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.isGeometryFlipped = false

    let background = CAGradientLayer()
    background.frame = parentLayer.bounds
    background.colors = [
        NSColor(calibratedRed: 0.035, green: 0.086, blue: 0.122, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.015, green: 0.24, blue: 0.25, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.015, green: 0.43, blue: 0.40, alpha: 1).cgColor
    ]
    background.startPoint = CGPoint(x: 0, y: 0.5)
    background.endPoint = CGPoint(x: 1, y: 0.5)
    parentLayer.addSublayer(background)

    let glow = CALayer()
    glow.frame = CGRect(x: 720, y: 370, width: 980, height: 980)
    glow.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
    glow.cornerRadius = 490
    parentLayer.addSublayer(glow)

    let phoneBorder = CALayer()
    phoneBorder.frame = CGRect(x: targetX - 12, y: targetY - 12, width: targetWidth + 24, height: targetHeight + 24)
    phoneBorder.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
    phoneBorder.cornerRadius = 58
    phoneBorder.shadowColor = NSColor.black.cgColor
    phoneBorder.shadowOpacity = 0.40
    phoneBorder.shadowRadius = 34
    phoneBorder.shadowOffset = CGSize(width: 0, height: -14)
    parentLayer.addSublayer(phoneBorder)

    let videoLayer = CALayer()
    videoLayer.frame = parentLayer.bounds
    parentLayer.addSublayer(videoLayer)

    let iconLayer = CALayer()
    iconLayer.frame = CGRect(x: 92, y: 886, width: 104, height: 104)
    iconLayer.cornerRadius = 26
    iconLayer.masksToBounds = true
    if let icon = NSImage(contentsOf: workspace.appendingPathComponent("Voya/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")),
       let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        iconLayer.contents = cgImage
        iconLayer.contentsGravity = .resizeAspectFill
    }
    parentLayer.addSublayer(iconLayer)

    parentLayer.addSublayer(textLayer(
        "VOYA  ·  OPENAI BUILD WEEK",
        frame: CGRect(x: 226, y: 921, width: 750, height: 40),
        size: 25,
        weight: .bold,
        color: NSColor(calibratedRed: 0.79, green: 0.98, blue: 0.91, alpha: 1),
        wrapped: false
    ))
    parentLayer.addSublayer(textLayer(
        "From confirmation\nto the next best action.",
        frame: CGRect(x: 92, y: 565, width: 1010, height: 250),
        size: 66,
        weight: .bold,
        color: .white
    ))
    parentLayer.addSublayer(textLayer(
        "A verified, living journey with bounded agents and grounded travel context.",
        frame: CGRect(x: 96, y: 400, width: 900, height: 120),
        size: 30,
        weight: .medium,
        color: NSColor.white.withAlphaComponent(0.74)
    ))
    parentLayer.addSublayer(makePill("Inspiration", x: 96, y: 278, width: 190))
    parentLayer.addSublayer(makePill("Smart import", x: 304, y: 278, width: 205))
    parentLayer.addSublayer(makePill("Trip Guardian", x: 527, y: 278, width: 225))
    parentLayer.addSublayer(textLayer(
        "BUILT WITH CODEX + GPT-5.6",
        frame: CGRect(x: 96, y: 92, width: 650, height: 42),
        size: 24,
        weight: .bold,
        color: NSColor(calibratedRed: 1, green: 0.82, blue: 0.32, alpha: 1),
        wrapped: false
    ))

    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: parentLayer
    )

    let audioMixInput = AVMutableAudioMixInputParameters(track: audioTrack)
    audioMixInput.setVolumeRamp(
        fromStartVolume: 0,
        toEndVolume: 1,
        timeRange: CMTimeRange(start: voiceStart, duration: CMTime(seconds: 0.35, preferredTimescale: 600))
    )
    let fadeStart = voiceStart + audioDuration - CMTime(seconds: 0.5, preferredTimescale: 600)
    audioMixInput.setVolumeRamp(
        fromStartVolume: 1,
        toEndVolume: 0,
        timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
    )
    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = [audioMixInput]

    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw DemoVideoError.cannotCreateExporter
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = videoComposition
    exporter.audioMix = audioMix

    print("Source video: \(String(format: "%.1f", videoDuration.seconds))s, \(Int(orientedSize.width))×\(Int(orientedSize.height))")
    print("Voiceover: \(String(format: "%.1f", audioDuration.seconds))s")
    print("Exporting 1920×1080…")

    await exporter.export()
    guard exporter.status == .completed else {
        throw DemoVideoError.exportFailed(exporter.error?.localizedDescription ?? "unknown export error")
    }
    print(outputURL.path)
}

Task {
    do {
        try await assemble()
        exit(0)
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}
RunLoop.main.run()
