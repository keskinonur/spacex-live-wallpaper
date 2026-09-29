import AVFoundation
import CoreImage

@main
struct PhotoRenderer {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4, let composition = PhotoComposition(rawValue: args[3]),
              let image = CIImage(contentsOf: URL(fileURLWithPath: args[1]), options: [.applyOrientationProperty: true]) else {
            fputs("Usage: render-photo source.jpg output.mp4 wide|close\n", stderr)
            exit(1)
        }
        let output = URL(fileURLWithPath: args[2])
        let scene = try PhotoScene(image: image, composition: composition)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace, .cacheIntermediates: false])
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let track = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 3840, AVVideoHeightKey: 2160,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 22_000_000,
                                              AVVideoExpectedSourceFrameRateKey: 30,
                                              AVVideoMaxKeyFrameIntervalKey: 60]
        ])
        track.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: track,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 3840,
                                         kCVPixelBufferHeightKey as String: 2160,
                                         kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(track)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<540 {
            try autoreleasepool {
                while !track.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error! }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else {
                    throw NSError(domain: "PhotoRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pixel buffer allocation failed."])
                }
                context.render(scene.frame(at: Double(frame) / 30), to: buffer, bounds: scene.bounds, colorSpace: colorSpace)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
            }
        }
        track.markAsFinished()
        let completion = DispatchSemaphore(value: 0)
        writer.finishWriting { completion.signal() }
        completion.wait()
        guard writer.status == .completed else { throw writer.error! }
        print("Rendered cinemagraph: \(output.lastPathComponent)")
    }
}
