import CoreImage

/// Original local frequency separation; no downloaded or extracted model weights.
final class PortraitDetail {
    private let restore = CIColorKernel(source:"""
        kernel vec4 restoreDetail(__sample original, __sample low, __sample soft, float texture) {
            return vec4(clamp(soft.rgb+(original.rgb-low.rgb)*texture,0.0,1.0),original.a);
        }
        """)
    private let skinGate = CIColorKernel(source:"""
        kernel vec4 skinGate(__sample p) {
            float l=dot(p.rgb,vec3(0.2126,0.7152,0.0722));
            float warm=smoothstep(-0.02,0.06,p.r-p.b)*smoothstep(-0.04,0.025,p.r-p.g);
            float light=smoothstep(0.015,0.07,l)*(1.0-smoothstep(0.94,1.0,l));
            float m=warm*light;
            return vec4(m,m,m,1.0);
        }
        """)
    private let brightGate = CIColorKernel(source:"""
        kernel vec4 brightGate(__sample p) {
            float hi=max(p.r,max(p.g,p.b)); float lo=min(p.r,min(p.g,p.b));
            float l=dot(p.rgb,vec3(0.2126,0.7152,0.0722));
            float m=smoothstep(0.12,0.55,l)*(1.0-smoothstep(0.18,0.42,hi-lo));
            return vec4(m,m,m,1.0);
        }
        """)
    func smooth(_ image: CIImage, strength: Double, texture: Double) -> CIImage {
        let radius = max(0.7,min(image.extent.width,image.extent.height)*0.002)
        let low = image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius]).cropped(to:image.extent)
        let soft = image.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.025+strength*0.07,"inputSharpness":0.2])
        return restore?.apply(extent:image.extent,arguments:[image,low,soft,texture]) ?? soft
    }
    func skinMask(_ image: CIImage, geometric: CIImage) -> CIImage {
        guard let gate = skinGate?.apply(extent:image.extent,arguments:[image]) else { return geometric }
        return geometric.applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:gate]).cropped(to:image.extent)
    }
    func brightMask(_ image: CIImage, geometric: CIImage) -> CIImage {
        guard let gate = brightGate?.apply(extent:image.extent,arguments:[image]) else { return geometric }
        return geometric.applyingFilter("CIMultiplyCompositing",parameters:[kCIInputBackgroundImageKey:gate]).cropped(to:image.extent)
    }
}
