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
    private let detail = PortraitDetail()
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
    func render(_ image: CIImage, settings inputSettings: EditSettings, faces: [FaceGeometry] = [], includeCrop: Bool = true) throws -> CIImage {
        let s = inputSettings.effective()
        let activeFaces = faces.enumerated().filter { s.selectedFace == nil || s.selectedFace == $0.offset }.map(\.element)
        var out = color(image, settings:s)
        let masks = FaceMasks(extent:image.extent)
        for f in activeFaces {
            let skin = detail.skinMask(out,geometric:masks.skin(f))
            if s.smoothing > 0 {
                let strength = s.smoothing
                let smooth = detail.smooth(out,strength:strength,texture:s.texture,faceWidth:f.bounds.width)
                out = blend(smooth,over:out,mask:skin,amount:strength*0.95)
            }
            if s.wrinkles > 0 {
                let softened = out.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.025+s.wrinkles*0.065,"inputSharpness":0.35])
                out = blend(softened,over:out,mask:masks.forehead(f),amount:s.wrinkles*0.8)
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
                let light = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:s.underEyes*0.55])
                out = blend(light,over:out,mask:masks.eyeAreas(f,below:true),amount:0.8)
            }
            if [s.smoothing,s.wrinkles,s.blemishes,s.redness,abs(s.skinTone),s.underEyes].filter({ $0 > 0 }).count >= 3 {
                out = try materialize(out)
            }
            if s.skinEvenness > 0 {
                let radius = max(2,f.bounds.width*0.02)
                let even = out.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius]).cropped(to:out.extent)
                out = blend(even,over:out,mask:skin,amount:s.skinEvenness*0.4)
            }
            if s.skinGlow > 0 {
                let glow = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:s.skinGlow*0.3]).applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":0.8,"inputShadowAmount":0.1])
                out = blend(glow,over:out,mask:skin,amount:s.skinGlow*0.8)
            }
            if s.teethWhitening > 0 {
                let whitened = out.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0.1]).applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.35])
                out = blend(whitened,over:out,mask:detail.brightMask(out,geometric:masks.teeth(f)),amount:s.teethWhitening*0.85)
            }
            if s.eyeLight > 0 {
                let light = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.3])
                out = blend(light,over:out,mask:detail.brightMask(out,geometric:masks.eyes(f)),amount:s.eyeLight)
            }
            if s.eyeContrast > 0 || s.eyeSaturation != 0 {
                let eyes = out.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:1+s.eyeContrast*0.35,kCIInputSaturationKey:1+s.eyeSaturation*0.5])
                out = blend(eyes,over:out,mask:masks.eyes(f),amount:0.8)
            }
            if s.lipGloss > 0 {
                let gloss = out.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1,"inputShadowAmount":0.1]).applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.25])
                out = blend(gloss,over:out,mask:masks.lips(f),amount:s.lipGloss)
            }
            if [s.skinEvenness,s.skinGlow,s.teethWhitening,s.eyeLight,s.eyeContrast,abs(s.eyeSaturation),s.lipGloss].filter({ $0 > 0 }).count >= 3 {
                out = try materialize(out)
            }
            let palette: [(CGFloat,CGFloat,CGFloat)] = [(0.72,0.13,0.28),(0.65,0.26,0.29),(0.54,0.15,0.38),(0.85,0.35,0.29),(0.45,0.25,0.23)]
            let p = palette[min(max(s.makeupColor,0),palette.count-1)]
            if s.lipstick > 0 { out = tint(out,mask:masks.lips(f),rgb:p,amount:s.lipstick*0.85,mode:"CIColorBlendMode") }
            if s.blush > 0 { out = tint(out,mask:masks.cheeks(f),rgb:p,amount:s.blush*0.4) }
            if s.eyeshadow > 0 { out = tint(out,mask:masks.eyeAreas(f,below:false),rgb:p,amount:s.eyeshadow*0.35) }
            if s.eyeliner > 0 { out = tint(out,mask:masks.liner(f),rgb:(0.12,0.08,0.13),amount:s.eyeliner*0.8) }
            if s.brows > 0 { out = tint(out,mask:masks.eyebrows(f),rgb:(0.22,0.12,0.10),amount:s.brows*0.55) }
            if [s.lipstick,s.blush,s.eyeshadow,s.eyeliner,s.brows].filter({ $0 > 0 }).count >= 3 { out = try materialize(out) }
        }
        // Warp after retouch so masks stay attached to the altered features.
        for f in activeFaces { out = try geometry(out,face:f,settings:s) }
        out = try applyBrushes(out,dabs:s.dabs)
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
        if s.noiseReduction > 0 { out = out.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":s.noiseReduction*0.06,"inputSharpness":0.4]) }
        if s.sharpness > 0 { out = out.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:s.sharpness]) }
        if s.vignette > 0 { out = out.applyingFilter("CIVignette",parameters:[kCIInputIntensityKey:s.vignette*1.5,kCIInputRadiusKey:min(e.width,e.height)*0.5]) }
        return out.cropped(to:e)
    }
    func blend(_ front: CIImage, over back: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let m = mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:amount,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:amount,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:amount,w:0)])
        return front.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:back,kCIInputMaskImageKey:m]).cropped(to:back.extent)
    }
    private func tint(_ image: CIImage, mask: CIImage, rgb: (CGFloat,CGFloat,CGFloat), amount: Double, mode: String = "CISoftLightBlendMode") -> CIImage {
        // Soft-light retains luminance and lip/skin texture.
        let solid = CIImage(color:CIColor(red:rgb.0,green:rgb.1,blue:rgb.2)).cropped(to:image.extent)
        let colored = solid.applyingFilter(mode,parameters:[kCIInputBackgroundImageKey:image])
        return blend(colored,over:image,mask:mask,amount:amount)
    }
    private func geometry(_ input: CIImage, face f: FaceGeometry, settings s: EditSettings) throws -> CIImage {
        var out = input
        let b = f.bounds
        var warpCount = 0
        func apply(_ center: CGPoint?, _ rx: CGFloat, _ ry: CGFloat, _ sx: Double = 0, _ sy: Double = 0, _ dy: CGFloat = 0, dx: CGFloat = 0) throws {
            guard let center, sx != 0 || sy != 0 || dy != 0 || dx != 0 else { return }
            guard let warp else { throw ProcessingError(message:"Устройство не поддерживает геометрию Core Image") }
            let radius = CIVector(x:max(1,rx),y:max(1,ry))
            guard let result = warp.apply(extent:out.extent,roiCallback:{ _, r in r.insetBy(dx:-b.width*0.25,dy:-b.height*0.25) },image:out,
                                          arguments:[CIVector(cgPoint:center),radius,CIVector(x:sx,y:sy),CIVector(x:dx,y:dy)]) else {
                throw ProcessingError(message:"Не удалось обработать геометрию лица")
            }
            out = result
            warpCount += 1
            if warpCount % 4 == 0 { out = try materialize(out) }
        }
        try apply(CGPoint(x:b.midX,y:b.midY),b.width*0.65,b.height*0.65,s.faceWidth*0.32)
        try apply(CGPoint(x:b.midX,y:b.minY+b.height*0.12),b.width*0.38,b.height*0.28,0,0,CGFloat(s.chin)*b.height*0.035)
        for eye in [f.leftEye,f.rightEye] {
            guard let p = FaceGeometry.center(eye) else { continue }
            try apply(CGPoint(x:p.x,y:p.y-b.height*0.2),b.width*0.28,b.height*0.24,s.cheeks*0.24)
            try apply(p,b.width*0.21,b.height*0.16,-s.eyes*0.22,-s.eyes*0.22)
        }
        try apply(CGPoint(x:b.midX,y:b.midY),b.width*0.6,b.height*0.65,0,s.faceHeight*0.12)
        try apply(CGPoint(x:b.midX,y:b.minY+b.height*0.2),b.width*0.5,b.height*0.3,s.jaw*0.25)
        try apply(CGPoint(x:b.midX,y:b.maxY-b.height*0.08),b.width*0.45,b.height*0.23,0,s.forehead*0.2)
        for eye in [f.leftEye,f.rightEye] {
            guard let p = FaceGeometry.center(eye) else { continue }
            let sign: CGFloat = p.x < b.midX ? 1 : -1
            try apply(p,b.width*0.2,b.height*0.15,-s.eyeWidth*0.2,-s.eyeHeight*0.2)
            try apply(p,b.width*0.22,b.height*0.18,0,0,-CGFloat(s.eyeLift)*b.height*0.025,dx:sign*CGFloat(s.eyeDistance)*b.width*0.025)
            try apply(p,b.width*0.065,b.height*0.07,-s.irisSize*0.2,-s.irisSize*0.2)
        }
        if let p = FaceGeometry.center(f.nose) {
            try apply(p,b.width*0.17,b.height*0.25,0,s.noseLength*0.18)
            try apply(CGPoint(x:p.x,y:p.y+b.height*0.10),b.width*0.12,b.height*0.18,s.noseBridge*0.2)
            try apply(CGPoint(x:p.x,y:p.y-b.height*0.04),b.width*0.14,b.height*0.12,0,0,-CGFloat(s.noseTip)*b.height*0.025)
        }
        if let p = FaceGeometry.center(f.outerLips) {
            try apply(p,b.width*0.28,b.height*0.15,-s.lipsWidth*0.2,0,-CGFloat(s.lipsPosition)*b.height*0.025)
            for sign in [CGFloat(-1),CGFloat(1)] {
                try apply(CGPoint(x:p.x+sign*b.width*0.14,y:p.y),b.width*0.13,b.height*0.12,0,0,-CGFloat(s.smile)*b.height*0.028)
            }
        }
        try apply(FaceGeometry.center(f.nose),b.width*0.20,b.height*0.28,s.nose*0.22)
        try apply(FaceGeometry.center(f.outerLips),b.width*0.30,b.height*0.16,-s.lips*0.18,-s.lips*0.18)
        for brow in [f.leftBrow,f.rightBrow] {
            try apply(FaceGeometry.center(brow),b.width*0.23,b.height*0.13,0,0,-CGFloat(s.browShape)*b.height*0.025)
        }
        for brow in [f.leftBrow,f.rightBrow] {
            guard let p = FaceGeometry.center(brow) else { continue }
            let sign: CGFloat = p.x < b.midX ? 1 : -1
            try apply(p,b.width*0.24,b.height*0.13,0,0,0,dx:sign*CGFloat(s.browDistance)*b.width*0.025)
            try apply(CGPoint(x:p.x-sign*b.width*0.08,y:p.y),b.width*0.11,b.height*0.1,0,0,-CGFloat(s.browTilt)*b.height*0.025)
        }
        return out
    }
    func crop(_ input: CIImage, settings s: EditSettings) -> CIImage {
        let plan = CropPlan.make(extent:input.extent,settings:s)
        return input.transformed(by:plan.transform).cropped(to:plan.output)
    }
    private func applyBrushes(_ input: CIImage, dabs: [RetouchDab]) throws -> CIImage {
        var out = input
        let e = input.extent
        for (index,dab) in dabs.enumerated() {
            let center = CGPoint(x:CGFloat(dab.x)*e.width,y:CGFloat(dab.y)*e.height)
            let radius = max(2,CGFloat(dab.radius)*min(e.width,e.height))
            let mask = CIFilter(name:"CIRadialGradient",parameters:["inputCenter":CIVector(cgPoint:center),"inputRadius0":radius*0.5,"inputRadius1":radius,"inputColor0":CIColor.white,"inputColor1":CIColor.black])!.outputImage!.cropped(to:e)
            let front: CIImage
            switch dab.mode {
            case .heal:
                let direction: CGFloat = center.x+radius*3 < e.maxX ? 1 : -1
                front = input.clampedToExtent().transformed(by:CGAffineTransform(translationX:-direction*radius*2.4,y:0)).cropped(to:e)
            case .smooth:
                front = out.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius*0.25]).cropped(to:e)
            case .lighten: front = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.35])
            case .darken: front = out.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:-0.35])
            }
            out = blend(front,over:out,mask:mask,amount:dab.strength)
            if (index+1) % 8 == 0 { out = try materialize(out) }
        }
        return out
    }
    private func materialize(_ image: CIImage) throws -> CIImage {
        try autoreleasepool {
            guard let cg = context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else {
                throw ProcessingError(message:"Недостаточно памяти для промежуточной обработки")
            }
            return CIImage(cgImage:cg).transformed(by:CGAffineTransform(translationX:image.extent.minX,y:image.extent.minY))
        }
    }
    func bitmap(_ image: CIImage) throws -> UIImage {
        guard let cg = context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)) else { throw ProcessingError(message:"Недостаточно памяти для изображения") }
        return UIImage(cgImage:cg)
    }
}
