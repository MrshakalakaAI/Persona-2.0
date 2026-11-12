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
    func testRecipeIntensityAndManualControls() {
        var s = EditSettings(); s.beautyLook = .evening; s.beautyAmount = 0
        XCTAssertEqual(s.effective().lipstick,0)
        s.beautyAmount = 0.5
        XCTAssertEqual(s.effective().lipstick,0.325,accuracy:0.001)
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
