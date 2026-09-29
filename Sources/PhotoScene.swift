import CoreImage

enum PhotoComposition: String {
    case wide, close
}

/// A restrained cinemagraph treatment of a still, not simulated launch footage.
/// All motion is evaluated from time, so frames are deterministic and seekable.
final class PhotoScene {
    let bounds: CGRect
    let source: CIImage
    let composition: PhotoComposition
    private let kernel: CIKernel

    init(image: CIImage, composition: PhotoComposition, width: Int = 3840, height: Int = 2160) throws {
        self.composition = composition
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let scale = max(CGFloat(width) / image.extent.width, CGFloat(height) / image.extent.height)
        source = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: bounds)
        // Coordinates are normalized; the 4K displacement scales with output size.
        // A feathered central exclusion protects the rocket, tower and exhaust.
        let program = """
        kernel vec4 plume(sampler image, vec2 size, float time, float wide) {
            vec2 p = destCoord();
            vec2 uv = p / size;
            vec2 lc = (uv - vec2(0.23, 0.43)) / vec2(0.23, 0.29);
            vec2 rc = (uv - vec2(0.82, 0.49)) / vec2(0.24, 0.38);
            float clouds = max(exp(-dot(lc, lc) * 1.6), exp(-dot(rc, rc) * 1.5));
            float ground = smoothstep(0.15, 0.29, uv.y);
            float subject = smoothstep(0.07, 0.12, abs(uv.x - 0.493));
            float edge = smoothstep(0.0, 0.06, uv.x) * (1.0 - smoothstep(0.94, 1.0, uv.x));
            float mask = clouds * ground * subject * edge;
            float progress = clamp(time / 18.0, 0.0, 1.0);
            float direction = uv.x < 0.493 ? -1.0 : 1.0;
            float roll = sin(time * 0.42 + uv.y * 9.0 + uv.x * 5.0);
            // Inverse sampling: negative vertical offset lifts the plume.
            vec2 flow = vec2(-direction * (35.0 * progress + 4.0 * roll),
                            -(24.0 * progress + 3.0 * sin(time * 0.36 + uv.x * 8.0)));
            flow *= mask * size.x / 3840.0;
            vec4 color = sample(image, samplerTransform(image, p + flow));
            vec2 lightCenter = mix(vec2(0.494, 0.145), vec2(0.488, 0.31), wide);
            vec2 lightUV = (uv - lightCenter) / vec2(0.075, 0.13);
            float lightMask = exp(-dot(lightUV, lightUV) * 2.5);
            float pulse = 0.035 + 0.018 * sin(time * 1.17) + 0.009 * sin(time * 2.13 + 0.4);
            // Screen-blended warm light preserves existing highlight detail.
            vec3 warm = vec3(1.0, 0.47, 0.12) * lightMask * pulse;
            color.rgb = 1.0 - (1.0 - color.rgb) * (1.0 - warm);
            return color;
        }
        """
        guard let kernel = CIKernel(source: program) else {
            throw NSError(domain: "PhotoScene", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not compile the photo animation kernel."])
        }
        self.kernel = kernel
    }

    func frame(at seconds: Double, cameraMotion: Bool = true) -> CIImage {
        let time = max(0, min(18, seconds))
        let extent = bounds
        let animated = kernel.apply(extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -50 * extent.width / 3840, dy: -50 * extent.width / 3840) },
            arguments: [source.clampedToExtent(), CIVector(x: bounds.width, y: bounds.height),
                        time, composition == .wide ? 1.0 : 0.0])!
        guard cameraMotion else { return animated.cropped(to: bounds) }
        let progress = time / 18
        let ease = progress * progress * (3 - 2 * progress)
        let zoom = composition == .wide ? 1 + 0.012 * ease : 1.012 - 0.012 * ease
        let x = -(bounds.width * zoom - bounds.width) * 0.493
        let y = -(bounds.height * zoom - bounds.height) * (composition == .wide ? 0.62 : 0.92)
        return animated.clampedToExtent().transformed(by: CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: x, ty: y)).cropped(to: bounds)
    }
}
