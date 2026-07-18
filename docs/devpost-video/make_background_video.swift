import AppKit
import AVFoundation
import CoreVideo

let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = workspace.appendingPathComponent("docs/devpost-video")
let imageURL = folder.appendingPathComponent("background.png")
let outputURL = folder.appendingPathComponent("background-v3.mp4")
let width = 1920
let height = 1080
let duration = CMTime(seconds: 140, preferredTimescale: 600)

guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load background.png")
}

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 1_500_000,
        AVVideoExpectedSourceFrameRateKey: 30,
        AVVideoMaxKeyFrameIntervalKey: 30
    ]
])
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ]
)

guard writer.canAdd(input) else { fatalError("Cannot add writer input") }
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

var pixelBuffer: CVPixelBuffer?
CVPixelBufferCreate(
    kCFAllocatorDefault,
    width,
    height,
    kCVPixelFormatType_32BGRA,
    [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
    &pixelBuffer
)
guard let pixelBuffer else { fatalError("Could not create pixel buffer") }

CVPixelBufferLockBaseAddress(pixelBuffer, [])
let context = CGContext(
    data: CVPixelBufferGetBaseAddress(pixelBuffer),
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
)!
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

while !input.isReadyForMoreMediaData { usleep(10_000) }
adaptor.append(pixelBuffer, withPresentationTime: .zero)
while !input.isReadyForMoreMediaData { usleep(10_000) }
adaptor.append(pixelBuffer, withPresentationTime: duration - CMTime(value: 1, timescale: 30))

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else {
    fatalError(writer.error?.localizedDescription ?? "Background video export failed")
}
print(outputURL.path)
