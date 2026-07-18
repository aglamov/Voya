import AppKit
import AVFoundation
import CoreMedia

enum VideoAssemblyError: Error {
    case missingTrack(String)
    case cannotCreateTrack
    case cannotCreateExporter
    case exportFailed(String)
}

func assembleV2() async throws {
    let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let folder = workspace.appendingPathComponent("docs/devpost-video")
    let rawAsset = AVURLAsset(url: folder.appendingPathComponent("raw-demo.mp4"))
    let backgroundAsset = AVURLAsset(url: folder.appendingPathComponent("background-v3.mp4"))
    let audioAsset = AVURLAsset(url: folder.appendingPathComponent("voiceover.aiff"))
    let outputURL = folder.appendingPathComponent("Voya-OpenAI-Build-Week-Demo-v4.mp4")

    guard let rawSource = try await rawAsset.loadTracks(withMediaType: .video).first else {
        throw VideoAssemblyError.missingTrack("raw video")
    }
    guard let backgroundSource = try await backgroundAsset.loadTracks(withMediaType: .video).first else {
        throw VideoAssemblyError.missingTrack("background video")
    }
    guard let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first else {
        throw VideoAssemblyError.missingTrack("voiceover")
    }

    let rawSize = try await rawSource.load(.naturalSize)
    let rawTransform = try await rawSource.load(.preferredTransform)
    let rawRect = CGRect(origin: .zero, size: rawSize).applying(rawTransform)
    let orientedSize = CGSize(width: abs(rawRect.width), height: abs(rawRect.height))
    let backgroundDuration = try await backgroundAsset.load(.duration)
    let audioDuration = try await audioAsset.load(.duration)
    let outputDuration = CMTime(seconds: 140, preferredTimescale: 600)

    let composition = AVMutableComposition()
    guard let backgroundTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
          let phoneTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
          let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw VideoAssemblyError.cannotCreateTrack
    }

    try backgroundTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: min(backgroundDuration, outputDuration)),
        of: backgroundSource,
        at: .zero
    )

    var cursor = CMTime.zero
    let segments: [(start: Double, end: Double, target: Double)] = [
        (0, 44, 25),       // Inspiration
        (44, 91, 20),      // Import
        (91, 109, 55),     // Trips, held longer without opening inconsistent test-provider details
        (176, 220, 40)     // Trip Guardian; skips inconsistent demo flight-provider details
    ]

    for segment in segments {
        let sourceStart = CMTime(seconds: segment.start, preferredTimescale: 600)
        let sourceDuration = CMTime(seconds: segment.end - segment.start, preferredTimescale: 600)
        let targetDuration = CMTime(seconds: segment.target, preferredTimescale: 600)
        try phoneTrack.insertTimeRange(
            CMTimeRange(start: sourceStart, duration: sourceDuration),
            of: rawSource,
            at: cursor
        )
        phoneTrack.scaleTimeRange(
            CMTimeRange(start: cursor, duration: sourceDuration),
            toDuration: targetDuration
        )
        cursor = cursor + targetDuration
    }

    let voiceStart = CMTime(seconds: 0.8, preferredTimescale: 600)
    try audioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: audioDuration),
        of: audioSource,
        at: voiceStart
    )

    let renderSize = CGSize(width: 1920, height: 1080)
    let targetHeight: CGFloat = 1000
    let scale = targetHeight / orientedSize.height
    let targetWidth = orientedSize.width * scale
    let targetX = renderSize.width - targetWidth - 92
    let targetY: CGFloat = 40

    let normalized = rawTransform.concatenating(
        CGAffineTransform(translationX: -rawRect.minX, y: -rawRect.minY)
    )
    let phoneTransform = normalized
        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        .concatenating(CGAffineTransform(translationX: targetX, y: targetY))

    let phoneInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: phoneTrack)
    phoneInstruction.setTransform(phoneTransform, at: .zero)
    let backgroundInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: backgroundTrack)
    backgroundInstruction.setTransform(.identity, at: .zero)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
    instruction.layerInstructions = [phoneInstruction, backgroundInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = [instruction]

    let audioParameters = AVMutableAudioMixInputParameters(track: audioTrack)
    audioParameters.setVolumeRamp(
        fromStartVolume: 0,
        toEndVolume: 1,
        timeRange: CMTimeRange(start: voiceStart, duration: CMTime(seconds: 0.3, preferredTimescale: 600))
    )
    let fadeStart = voiceStart + audioDuration - CMTime(seconds: 0.5, preferredTimescale: 600)
    audioParameters.setVolumeRamp(
        fromStartVolume: 1,
        toEndVolume: 0,
        timeRange: CMTimeRange(start: fadeStart, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
    )
    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = [audioParameters]

    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw VideoAssemblyError.cannotCreateExporter
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = videoComposition
    exporter.audioMix = audioMix

    print("Exporting truthful 140-second cut…")
    await exporter.export()
    guard exporter.status == .completed else {
        throw VideoAssemblyError.exportFailed(exporter.error?.localizedDescription ?? "unknown export error")
    }
    print(outputURL.path)
}

Task {
    do {
        try await assembleV2()
        exit(0)
    } catch {
        fputs("\(error)\n", stderr)
        exit(1)
    }
}
RunLoop.main.run()
