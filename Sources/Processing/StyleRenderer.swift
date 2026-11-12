import CoreImage

/// Original, deterministic recipes shared by stills, thumbnails and video.
/// No downloaded LUTs, proprietary weights or time-varying noise.
struct StyleRenderer {
    struct Recipe {
        var curve: [Double] = [0,0.25,0.5,0.75,1]
        var vibrance = 0.0
        var saturation = 1.0
        var shadows: (Double,Double,Double) = (0,0,0)
        var lights: (Double,Double,Double) = (0,0,0)
        var bloom = 0.0
    }
    static let balanceKernel = CIColorKernel(source:"""
    kernel vec4 splitTone(__sample source, vec3 dark, vec3 light) {
        vec4 s = unpremultiply(source);
        float l = clamp(dot(s.rgb,vec3(0.2126,0.7152,0.0722)),0.0,1.0);
        float warm = smoothstep(0.0,0.12,s.r-s.b) * smoothstep(-0.02,0.06,s.g-s.b);
        float mid = smoothstep(0.03,0.18,l)*(1.0-smoothstep(0.75,1.0,l));
        float protection = 1.0-0.65*warm*mid;
        vec3 c = s.rgb + protection*(dark*(1.0-l)*(1.0-l)+light*l*l);
        return premultiply(vec4(clamp(c,0.0,1.0),s.a));
    }
    """)
    static func recipe(_ style: PhotoStyle) -> Recipe {
        switch style {
        case .natural: return Recipe()
        case .portrait: return Recipe(curve:[0,0.22,0.52,0.79,1],vibrance:0.12,saturation:0.97,shadows:(-0.008,0,0.012),lights:(0.012,0.006,-0.008))
        case .softBeauty: return Recipe(curve:[0.025,0.29,0.55,0.79,0.99],vibrance:0.08,saturation:0.94,lights:(0.022,0.008,0.012),bloom:0.12)
        case .cinematic: return Recipe(curve:[0.018,0.20,0.49,0.77,0.97],vibrance:-0.10,saturation:0.86,shadows:(-0.025,0.018,0.032),lights:(0.035,0.012,-0.025))
        case .vintage: return Recipe(curve:[0.065,0.28,0.53,0.76,0.94],vibrance:-0.18,saturation:0.82,shadows:(0.025,0.008,0.022),lights:(0.045,0.018,-0.035))
        case .warm: return Recipe(curve:[0,0.26,0.52,0.77,1],vibrance:0.10,shadows:(0.018,0.004,-0.02),lights:(0.055,0.018,-0.045))
        case .cold: return Recipe(curve:[0,0.24,0.51,0.77,1],vibrance:0.04,shadows:(-0.028,0.008,0.045),lights:(-0.03,0.008,0.045))
        case .monochrome: return Recipe(curve:[0.005,0.19,0.51,0.81,0.995],saturation:0)
        case .peach: return Recipe(curve:[0.015,0.28,0.55,0.8,1],vibrance:0.12,saturation:0.96,shadows:(0.025,0.008,-0.012),lights:(0.055,0.012,-0.018))
        case .rose: return Recipe(curve:[0.03,0.27,0.53,0.78,0.99],vibrance:0.04,saturation:0.91,shadows:(0.025,-0.012,0.025),lights:(0.04,-0.01,0.018))
        case .mocha: return Recipe(curve:[0.035,0.21,0.46,0.73,0.95],vibrance:-0.12,saturation:0.78,shadows:(0.028,0.012,-0.008),lights:(0.045,0.018,-0.035))
        case .goldenHour: return Recipe(curve:[0.018,0.25,0.54,0.82,0.99],vibrance:0.20,saturation:1.02,shadows:(0.022,0.003,-0.02),lights:(0.09,0.033,-0.065),bloom:0.08)
        case .editorial: return Recipe(curve:[0,0.18,0.49,0.82,1],vibrance:-0.05,saturation:0.86,shadows:(-0.012,0.005,0.025),lights:(0.015,0.005,-0.012))
        }
    }
    func render(_ input: CIImage, style: PhotoStyle, amount: Double) -> CIImage {
        let strength = min(1,max(0,amount))
        guard style != .natural, strength > 0 else { return input }
        let r = Self.recipe(style)
        var points: [String:Any] = [:]
        for i in 0..<5 { points["inputPoint\(i)"] = CIVector(x:Double(i)*0.25,y:r.curve[i]) }
        var out = input.applyingFilter("CIToneCurve",parameters:points)
            .applyingFilter("CIVibrance",parameters:["inputAmount":r.vibrance])
            .applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:r.saturation])
        if let kernel = Self.balanceKernel,
           let balanced = kernel.apply(extent:input.extent,arguments:[out,CIVector(x:r.shadows.0,y:r.shadows.1,z:r.shadows.2),CIVector(x:r.lights.0,y:r.lights.1,z:r.lights.2)]) { out = balanced }
        if r.bloom > 0 {
            out = out.clampedToExtent().applyingFilter("CIBloom",parameters:[kCIInputRadiusKey:max(1,min(input.extent.width,input.extent.height)*0.008),kCIInputIntensityKey:r.bloom]).cropped(to:input.extent)
        }
        return out.applyingFilter("CIDissolveTransition",parameters:[kCIInputTargetImageKey:input,kCIInputTimeKey:1-strength]).cropped(to:input.extent)
    }
}
