import XCTest
import CoreImage
import UIKit
@testable import PersonaFree

final class PortraitToolsTests: XCTestCase {
    private let pipeline = ImagePipeline()
    private func portrait() throws -> CIImage {
        let url = try XCTUnwrap(Bundle.main.url(forResource:"DemoPortrait",withExtension:"jpg"))
        return try MediaIO.decode(Data(contentsOf:url),maxDimension:1280)
    }
    func testRealPortraitLandmarksAndAllLooksRender() throws {
        let image = try portrait()
        let faces = try FaceAnalyzer().detect(in:image)
        XCTAssertGreaterThanOrEqual(faces.count,1)
        let f = try XCTUnwrap(faces.first)
        XCTAssertGreaterThan(f.leftEye.count,3); XCTAssertGreaterThan(f.outerLips.count,5)
        let eyesY = try XCTUnwrap(FaceGeometry.center(f.leftEye)).y
        XCTAssertGreaterThan(eyesY,try XCTUnwrap(FaceGeometry.center(f.outerLips)).y)
        for look in BeautyLook.allCases {
            var s = EditSettings(); s.beautyLook = look; s.beautyAmount = 0.8
            let result = try pipeline.bitmap(pipeline.render(image,settings:s,faces:faces))
            XCTAssertEqual(result.size.width,image.extent.width)
            if look == .studio {
                let attachment = XCTAttachment(image:result); attachment.name = "Real portrait — independent studio look"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
    func testBeautyChangesFacePixelsAndRespondsToIntensity() throws {
        let image = try portrait()
        let faces = try FaceAnalyzer().detect(in:image)
        let face = try XCTUnwrap(faces.first)
        let roi = face.bounds.insetBy(dx:face.bounds.width*0.08,dy:face.bounds.height*0.08).integral.intersection(image.extent)
        let width = Int(roi.width), height = Int(roi.height)
        let geometric = FaceMasks(extent:image.extent).skin(face)
        let skin = PortraitDetail().skinMask(image,geometric:geometric)
        var maskPixels = [UInt8](repeating:0,count:width*height*4)
        pipeline.context.render(skin,toBitmap:&maskPixels,rowBytes:width*4,bounds:roi,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        let coverage = stride(from:0,to:maskPixels.count,by:4).reduce(0.0) { $0+Double(maskPixels[$1])/255 }/Double(width*height)
        print("Beauty actual skin mask coverage \(coverage), contour endpoints \(String(describing:face.contour.first)) → \(String(describing:face.contour.last))")
        XCTAssertGreaterThan(coverage,0.2,"Skin effects must cover actual face pixels")
        let maskAttachment = XCTAttachment(image:try pipeline.bitmap(skin)); maskAttachment.name = "Beauty actual skin coverage"; maskAttachment.lifetime = .keepAlways; add(maskAttachment)
        func pixels(_ output: CIImage) -> [UInt8] {
            var bytes = [UInt8](repeating:0,count:width*height*4)
            pipeline.context.render(output,toBitmap:&bytes,rowBytes:width*4,bounds:roi,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
            return bytes
        }
        let baseline = pixels(try pipeline.render(image,settings:EditSettings(),faces:faces))
        func difference(_ output: [UInt8]) -> Double {
            var sum = 0.0
            for i in stride(from:0,to:output.count,by:4) {
                for channel in 0..<3 { sum += abs(Double(output[i+channel])-Double(baseline[i+channel])) }
            }
            return sum/Double(width*height*3)
        }
        for (look,minimum) in [(BeautyLook.natural,1.0),(.studio,2.0),(.evening,3.0),(.sculpt,2.0)] {
            var settings = EditSettings(); settings.beautyLook = look; settings.beautyAmount = 1
            settings.makeupColor = look.recipe.makeupColor
            let result = try pipeline.render(image,settings:settings,faces:faces)
            let delta = difference(pixels(result))
            print("Beauty face ROI \(look.rawValue): mean RGB difference \(delta)")
            XCTAssertGreaterThan(delta,minimum,"\(look.rawValue) must measurably change the face, not merely render")
            let attachment = XCTAttachment(image:try pipeline.bitmap(result)); attachment.name = "Beauty 1.2 — \(look.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            if look == .evening {
                let lipRect = FaceMasks(extent:image.extent).bounding(face.outerLips).integral.intersection(image.extent)
                let w = Int(lipRect.width), h = Int(lipRect.height)
                XCTAssertGreaterThan(w*h,0)
                if w*h > 0 {
                    var mask = [UInt8](repeating:0,count:w*h*4), original = mask, changed = mask
                    pipeline.context.render(FaceMasks(extent:image.extent).lips(face),toBitmap:&mask,rowBytes:w*4,bounds:lipRect,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
                    pipeline.context.render(image,toBitmap:&original,rowBytes:w*4,bounds:lipRect,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
                    pipeline.context.render(result,toBitmap:&changed,rowBytes:w*4,bounds:lipRect,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
                    var difference = 0.0, channels = 0
                    for i in stride(from:0,to:mask.count,by:4) where mask[i] > 128 {
                        for c in 0..<3 { difference += abs(Double(original[i+c])-Double(changed[i+c])); channels += 1 }
                    }
                    XCTAssertGreaterThan(channels,0)
                    let lipDelta = difference/Double(max(1,channels))
                    print("Beauty evening lipstick ROI difference \(lipDelta)")
                    XCTAssertGreaterThan(lipDelta,3,"Evening must change the actual lips, not just overall lighting")
                }
            }
            if look == .studio {
                settings.beautyAmount = 0
                XCTAssertEqual(pixels(try pipeline.render(image,settings:settings,faces:faces)),baseline)
                settings.beautyAmount = 0.25
                let low = difference(pixels(try pipeline.render(image,settings:settings,faces:faces)))
                XCTAssertGreaterThan(delta,low*1.2)
            }
        }
    }
    @MainActor func testEditorPublishesBeautyPreview() async throws {
        let model = EditorModel()
        let url = try XCTUnwrap(Bundle.main.url(forResource:"DemoPortrait",withExtension:"jpg"))
        await model.loadPhoto(try Data(contentsOf:url))
        XCTAssertGreaterThan(model.faceCount,0)
        let before = model.preview?.pngData()
        model.change { $0.beautyLook = .glow; $0.beautyAmount = 1 }
        model.scheduleRender()
        let deadline = ProcessInfo.processInfo.systemUptime+45
        while !model.message.hasPrefix("Применён образ") && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTAssertTrue(model.message.hasPrefix("Применён образ"),model.message)
        XCTAssertNotEqual(model.preview?.pngData(),before)
    }
    func testMakeupPaletteOverridesLookColor() {
        var settings = EditSettings(); settings.beautyLook = .evening; settings.makeupColor = 3
        XCTAssertEqual(settings.effective().makeupColor,3)
    }
    func testRecipeIntensityAndManualControls() {
        var s = EditSettings(); s.beautyLook = .evening; s.beautyAmount = 0
        XCTAssertEqual(s.effective().lipstick,0)
        s.beautyAmount = 0.5
        XCTAssertEqual(s.effective().lipstick,0.45,accuracy:0.001)
        s.lipstick = 0.9
        XCTAssertEqual(s.effective().lipstick,1)
        XCTAssertEqual(s.effective().beautyLook,.none)
    }
    func testCropMappingRoundtripForEveryOrientation() {
        let source = CGSize(width:800,height:1200)
        for turn in 0..<4 {
            for angle in [-12.0,0,15] {
                var s = EditSettings(); s.quarterTurns = turn; s.straighten = angle; s.aspect = .story; s.cropZoom = 1.4; s.cropX = 0.3; s.cropY = -0.2
                let plan = CropPlan.make(extent:CGRect(origin:.zero,size:source),settings:s)
                let point = plan.sourcePoint(displayUnit:CGPoint(x:0.37,y:0.61),source:source)
                let output = CGPoint(x:point.x*source.width,y:point.y*source.height).applying(plan.transform)
                XCTAssertEqual(output.x/plan.output.width,0.37,accuracy:0.0001)
                XCTAssertEqual(1-output.y/plan.output.height,0.61,accuracy:0.0001)
            }
        }
    }
    func testSpotHealingReplacesAnIsolatedDefect() throws {
        let extent = CGRect(x:0,y:0,width:400,height:600)
        let background = CIImage(color:CIColor(red:0.6,green:0.5,blue:0.4)).cropped(to:extent)
        let defect = CIImage(color:.black).cropped(to:CGRect(x:195,y:295,width:10,height:10)).composited(over:background).cropped(to:extent)
        var s = EditSettings(); s.dabs = [RetouchDab(x:0.5,y:0.5,radius:0.05,strength:1,mode:.heal)]
        let result = try pipeline.render(defect,settings:s)
        func value(_ image: CIImage) -> UInt8 {
            var bytes = [UInt8](repeating:0,count:4)
            pipeline.context.render(image,toBitmap:&bytes,rowBytes:4,bounds:CGRect(x:200,y:300,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
            return bytes[0]
        }
        XCTAssertLessThan(value(defect),5); XCTAssertGreaterThan(value(result),80)
    }
    func testSelectedFaceCanExcludePortrait() throws {
        let image = try portrait(), faces = try FaceAnalyzer().detect(in:portrait())
        var s = EditSettings(); s.selectedFace = 99; s.faceWidth = 1; s.lipstick = 1
        let excluded = try pipeline.bitmap(pipeline.render(image,settings:s,faces:faces)).pngData()
        let baseline = try pipeline.bitmap(pipeline.render(image,settings:EditSettings(),faces:faces)).pngData()
        XCTAssertEqual(excluded,baseline)
    }
    func testVideoAnalyzerFindsRealFace() throws {
        let faces = try VideoFaceAnalyzer().faces(in:portrait())
        XCTAssertGreaterThanOrEqual(faces.count,1)
    }
    func testAllDetailedGeometryAndLocalColorRender() throws {
        let image = try portrait(), faces = try FaceAnalyzer().detect(in:portrait())
        var s = EditSettings()
        let tools = ["Кожа","Лицо","Глаза","Нос","Улыбка","Макияж"].flatMap { AdjustmentTool.tools($0) }
        for tool in tools { s[keyPath:tool.key] = 0.35 }
        let result = try pipeline.render(image,settings:s,faces:faces)
        XCTAssertNotNil(try pipeline.bitmap(result).cgImage)
        XCTAssertEqual(result.extent,image.extent)
    }
}
