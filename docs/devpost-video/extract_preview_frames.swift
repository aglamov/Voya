import AppKit
import AVFoundation

let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = workspace.appendingPathComponent("docs/devpost-video")
let frames = folder.appendingPathComponent("frames")
try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

let asset = AVURLAsset(url: folder.appendingPathComponent("Voya-OpenAI-Build-Week-Demo-v4.mp4"))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

for second in [2, 28, 58, 88, 112, 136] {
    let image = try generator.copyCGImage(
        at: CMTime(seconds: Double(second), preferredTimescale: 600),
        actualTime: nil
    )
    let bitmap = NSBitmapImageRep(cgImage: image)
    let data = bitmap.representation(using: .png, properties: [:])!
    let name = String(format: "%03d.png", second)
    try data.write(to: frames.appendingPathComponent(name))
    print(name)
}
