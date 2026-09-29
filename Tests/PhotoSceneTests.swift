import CoreImage
import Foundation

@main
struct PhotoSceneTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var results: [String: Bool] = [:]
        for (index, composition) in [PhotoComposition.wide, .close].enumerated() {
            let image = CIImage(contentsOf: root.appendingPathComponent("Media/spacex_20260929_\(index + 1).jpeg"))!
            let scene = try PhotoScene(image: image, composition: composition, width: 960, height: 540)
            func pixels(_ time: Double) -> [UInt8] {
                var data = [UInt8](repeating: 0, count: 960 * 540 * 4)
                context.render(scene.frame(at: time, cameraMotion: false), toBitmap: &data,
                               rowBytes: 960 * 4, bounds: scene.bounds, format: .RGBA8, colorSpace: colorSpace)
                return data
            }
            let early = pixels(3), late = pixels(13), adjacent = pixels(3 + 1.0 / 30)
            func difference(_ a: [UInt8], _ b: [UInt8], region: CGRect) -> Double {
                var total = 0.0, count = 0
                for y in Int(region.minY)..<Int(region.maxY) {
                    for x in Int(region.minX)..<Int(region.maxX) {
                        for channel in 0..<3 {
                            // Bitmap rows run top to bottom; Core Image uses bottom-left coordinates.
                            let offset = ((539 - y) * 960 + x) * 4 + channel
                            total += Double(abs(Int(a[offset]) - Int(b[offset])))
                            count += 1
                        }
                    }
                }
                return total / Double(count)
            }
            let cloudRegion = CGRect(x: 700, y: 180, width: 160, height: 180)
            let subjectRegion = CGRect(x: 460, y: 320, width: 20, height: 140)
            let groundRegion = CGRect(x: 100, y: 0, width: 200, height: 50)
            let cloudChange = difference(early, late, region: cloudRegion)
            let frameStep = difference(early, adjacent, region: cloudRegion)
            let subjectChange = difference(early, late, region: subjectRegion)
            let groundChange = difference(early, late, region: groundRegion)
            results["\(composition.rawValue).cloudsAnimate"] = cloudChange > 0.3
            results["\(composition.rawValue).smoothFrameStep"] = frameStep < 1.0 && frameStep < cloudChange / 5
            results["\(composition.rawValue).subjectProtected"] = subjectChange < 0.1
            results["\(composition.rawValue).groundProtected"] = groundChange < 0.1
            results["\(composition.rawValue).deterministic"] = early == pixels(3)
            print("\(composition.rawValue): cloud=\(cloudChange), step=\(frameStep), subject=\(subjectChange), ground=\(groundChange)")
            try context.writeJPEGRepresentation(of: scene.frame(at: 8), to: root.appendingPathComponent("Build/\(composition.rawValue)-cinemagraph.jpg"), colorSpace: colorSpace)
        }
        let passed = results.values.allSatisfy { $0 }
        let report = try JSONSerialization.data(withJSONObject: ["passed": passed, "checks": results], options: [.prettyPrinted, .sortedKeys])
        try report.write(to: root.appendingPathComponent("Tests/photo-scene.json"))
        print(String(data: report, encoding: .utf8)!)
        if !passed { exit(1) }
    }
}
