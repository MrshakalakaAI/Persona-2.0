import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

struct ProcessingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class ImagePipeline {
    let context: CIContext
    private let warp = CIWarpKernel(source: """
    kernel vec2 localWarp(vec2 center, vec2 radius, vec2 scale, vec2 shift) {
        vec2 p = destCoord();
        vec2 d = (p-center)/radius;
        float r = dot(d,d);
        float w = pow(max(0.0,1.0-r),3.0);
        return p + (p-center)*scale*w + shift*w;
    }
    """)
    init() {
        if let device = MTLCreateSystemDefaultDevice() { context = CIContext(mtlDevice:device,options:[.cacheIntermediates:false]) }
        else { context = CIContext(options:[.cacheIntermediates:false]) }
    }
    func render(_ image: CIImage, settings s: EditSettings, faces: [FaceGeometry] = [], includeCrop: Bool = true) throws -> CIImage {
        var out = color(image, settings:s)
        let masks = FaceMasks(extent:image.extent)
        for f in faces {
            let skin = masks.skin(f)
            if s.smoothing > 0 || s.wrinkles > 0 {
                let strength = max(s.smoothing,s.wrinkles*0.65)
                let smooth = out.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.02+strength*0.07,"inputSharpness":0.5])
                out = blend(smooth,over:out,mask:skin,amount:strength*0.85)
            }
            if s.blemishes > 0 {
                // Small-scale median suppression, never described as neural lesion removal.
                let reduced = out.applyingFilter("CIMedianFilter")
                out = blend(reduced,over:out,mask:skin,amount:s.blemishes*0.75)
            }
            if s.redness > 0 {
                let corrected = out.applyingFilter("CIColorMatrix",parameters:[
                    "inputRVector":CIVector(x:0.82,y:0.12,z:0.06,w:0),
                    "inputGVector":CIVector(x:0.03,y:0.97,z:0,w:0)])
                out = blend(corrected,over:out,mask:skin,amount:s.redness)
            }
            if s.skinTone != 0 {
                let tone = out.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500+s.skinTone*900,y:s.skinTone*12)])
                out = blend(tone,over:out,mask:skin,amount:0.7)
            }
            if s.underEyes > 0 {
                let light = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:s.underEyes*0.4])
                out = blend(light,over:out,mask:masks.eyeAreas(f,below:true),amount:0.8)
            }
            let palette: [(CGFloat,CGFloat,CGFloat)] = [(0.72,0.13,0.28),(0.65,0.26,0.29),(0.54,0.15,0.38),(0.85,0.35,0.29),(0.45,0.25,0.23)]
            let p = palette[min(max(s.makeupColor,0),palette.count-1)]
            if s.lipstick > 0 { out = tint(out,mask:masks.lips(f),rgb:p,amount:s.lipstick*0.7) }
            if s.blush > 0 { out = tint(out,mask:masks.cheeks(f),rgb:p,amount:s.blush*0.25) }
            if s.eyeshadow > 0 { out = tint(out,mask:masks.eyeAreas(f,below:false),rgb:p,amount:s.eyeshadow*0.35) }
            if s.eyeliner > 0 { out = tint(out,mask:masks.liner(f),rgb:(0.12,0.08,0.13),amount:s.eyeliner*0.8) }
            if s.brows > 0 { out = tint(out,mask:masks.eyebrows(f),rgb:(0.22,0.12,0.10),amount:s.brows*0.55) }
        }
        // Warp after retouch so masks stay attached to the altered features.
        for f in faces { out = try geometry(out,face:f,settings:s) }
        return includeCrop ? crop(out,settings:s) : out
    }
    func color(_ input: CIImage, settings s: EditSettings) -> CIImage {
        let e = input.extent
        var out = input
        var styled = input
        switch s.filter {
        case .natural: break
        case .portrait: styled = input.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.9,kCIInputContrastKey:1.07])
        case .softBeauty: styled = input.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:0.025,kCIInputContrastKey:0.95,kCIInputSaturationKey:0.92])
        case .cinematic: styled = input.applyingFilter("CIPhotoEffectProcess").applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.78])
        case .vintage: styled = input.applyingFilter("CIPhotoEffectTransfer")
        case .warm: styled = input.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:5200,y:0)])
        case .cold: styled = input.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:8000,y:0)])
        case .monochrome: styled = input.applyingFilter("CIPhotoEffectMono")
        }
        if s.filter != .natural { out = blend(styled,over:out,mask:CIImage(color:.white).cropped(to:e),amount:s.filterAmount) }
        out = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:s.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:s.brightness,kCIInputContrastKey:s.contrast,kCIInputSaturationKey:s.saturation])
        if s.warmth != 0 {
            out = out.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500-s.warmth*1800,y:0)])
        }
        out = out.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":s.highlights,"inputShadowAmount":s.shadows])
        if s.sharpness > 0 { out = out.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:s.sharpness]) }
        if s.vignette > 0 { out = out.applyingFilter("CIVignette",parameters:[kCIInputIntensityKey:s.vignette*1.5,kCIInputRadiusKey:min(e.width,e.height)*0.5]) }
        return out.cropped(to:e)
    }
    func blend(_ front: CIImage, over back: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let m = mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:amount,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:amount,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:amount,w:0)])
        return front.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:back,kCIInputMaskImageKey:m]).cropped(to:back.extent)
    }
    private func tint(_ image: CIImage, mask: CIImage, rgb: (CGFloat,CGFloat,CGFloat), amount: Double) -> CIImage {
        // Soft-light retains luminance and lip/skin texture.
        let solid = CIImage(color:CIColor(red:rgb.0,green:rgb.1,blue:rgb.2)).cropped(to:image.extent)
        let colored = solid.applyingFilter("CISoftLightBlendMode",parameters:[kCIInputBackgroundImageKey:image])
        return blend(colored,over:image,mask:mask,amount:amount)
    }
    private func geometry(_ input: CIImage, face f: FaceGeometry, settings s: EditSettings) throws -> CIImage {
        var out = input
        let b = f.bounds
        func apply(_ center: CGPoint?, _ rx: CGFloat, _ ry: CGFloat, _ sx: Double = 0, _ sy: Double = 0, _ dy: CGFloat = 0) throws {
            guard let center, sx != 0 || sy != 0 || dy != 0 else { return }
            guard let warp else { throw ProcessingError(message:"Устройство не поддерживает геометрию Core Image") }
            let radius = CIVector(x:max(1,rx),y:max(1,ry))
            guard let result = warp.apply(extent:out.extent,roiCallback:{ _, r in r.insetBy(dx:-b.width*0.25,dy:-b.height*0.25) },image:out,
                                          arguments:[CIVector(cgPoint:center),radius,CIVector(x:sx,y:sy),CIVector(x:0,y:dy)]) else {
                throw ProcessingError(message:"Не удалось обработать геометрию лица")
            }
            out = result
        }
        try apply(CGPoint(x:b.midX,y:b.midY),b.width*0.65,b.height*0.65,s.faceWidth*0.14)
        try apply(CGPoint(x:b.midX,y:b.minY+b.height*0.12),b.width*0.38,b.height*0.28,0,0,CGFloat(s.chin)*b.height*0.035)
        for eye in [f.leftEye,f.rightEye] {
            guard let p = FaceGeometry.center(eye) else { continue }
            try apply(CGPoint(x:p.x,y:p.y-b.height*0.2),b.width*0.28,b.height*0.24,s.cheeks*0.16)
            try apply(p,b.width*0.21,b.height*0.16,-s.eyes*0.22,-s.eyes*0.22)
        }
        try apply(FaceGeometry.center(f.nose),b.width*0.20,b.height*0.28,s.nose*0.22)
        try apply(FaceGeometry.center(f.outerLips),b.width*0.30,b.height*0.16,-s.lips*0.18,-s.lips*0.18)
        for brow in [f.leftBrow,f.rightBrow] {
            try apply(FaceGeometry.center(brow),b.width*0.23,b.height*0.13,0,0,-CGFloat(s.browShape)*b.height*0.025)
        }
        return out
    }
    func crop(_ input: CIImage, settings s: EditSettings) -> CIImage {
        var out = input
        let turns = ((s.quarterTurns % 4)+4)%4
        if turns != 0 { out = out.oriented([CGImagePropertyOrientation.up,.right,.down,.left][turns]) }
        out = out.transformed(by:CGAffineTransform(translationX:-out.extent.minX,y:-out.extent.minY))
        let base = out.extent
        if s.straighten != 0 {
            let angle = CGFloat(s.straighten)*CGFloat.pi/180
            let t = CGAffineTransform(translationX:base.midX,y:base.midY).rotated(by:angle).translatedBy(x:-base.midX,y:-base.midY)
            out = out.transformed(by:t)
            // Inscribe the original aspect in the rotation, excluding black corners.
            let factor = 1/(abs(cos(angle))+max(base.width/base.height,base.height/base.width)*abs(sin(angle)))
            out = out.cropped(to:CGRect(x:base.midX-base.width*factor/2,y:base.midY-base.height*factor/2,width:base.width*factor,height:base.height*factor))
        }
        let e = out.extent
        let ratio = CGFloat(s.aspect.ratio ?? Double(e.width/e.height))
        let w = min(e.width,e.height*ratio)/CGFloat(max(1,s.cropZoom))
        let h = w/ratio
        let x = e.minX+(e.width-w)*(CGFloat(s.cropX)+1)/2
        let y = e.minY+(e.height-h)*(CGFloat(s.cropY)+1)/2
        out = out.cropped(to:CGRect(x:x,y:y,width:w,height:h).integral.intersection(e))
        return out.transformed(by:CGAffineTransform(translationX:-out.extent.minX,y:-out.extent.minY))
    }
    func bitmap(_ image: CIImage) throws -> UIImage {
        guard let cg = context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else { throw ProcessingError(message:"Недостаточно памяти для изображения") }
        return UIImage(cgImage:cg)
    }
}
