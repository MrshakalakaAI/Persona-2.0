import XCTest
import CoreImage
import UIKit
@testable import PersonaFree

final class StyleTests: XCTestCase {
    private let pipeline = ImagePipeline()
    private func chart() -> CIImage {
        let colors: [(CGFloat,CGFloat,CGFloat)] = [(0.03,0.03,0.03),(0.2,0.2,0.2),(0.5,0.5,0.5),(0.9,0.9,0.9),(0.7,0.45,0.3),(0.28,0.17,0.11),(0.8,0.2,0.3),(0.1,0.4,0.8),(0.2,0.6,0.2),(0.7,0.6,0.2),(0.3,0.2,0.5),(0.05,0.5,0.55)]
        return colors.enumerated().reduce(CIImage.empty()) { image, item in
            let (i,c) = item
            return CIImage(color:CIColor(red:c.0,green:c.1,blue:c.2)).cropped(to:CGRect(x:i*32,y:0,width:32,height:96)).composited(over:image)
        }.cropped(to:CGRect(x:0,y:0,width:384,height:96))
    }
    private func samples(_ image: CIImage) -> [Double] {
        (0..<12).flatMap { index -> [Double] in
            var bytes = [UInt8](repeating:0,count:4)
            pipeline.context.render(image,toBitmap:&bytes,rowBytes:4,bounds:CGRect(x:index*32+16,y:48,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
            XCTAssertEqual(bytes[3],255)
            return bytes.prefix(3).map(Double.init)
        }
    }
    private func delta(_ a: [Double],_ b: [Double]) -> Double {
        zip(a,b).reduce(0) { $0+abs($1.0-$1.1) }/Double(a.count)
    }
    func testEveryColorRecipeIsVisibleDistinctAndScales() throws {
        XCTAssertNotNil(StyleRenderer.balanceKernel,"Split-toning kernel must compile")
        let source = chart(), baseline = samples(source), renderer = StyleRenderer()
        var rendered: [(PhotoStyle,[Double])] = []
        for style in PhotoStyle.allCases where style != .natural {
            let full = renderer.render(source,style:style,amount:1)
            let pixels = samples(full), difference = delta(pixels,baseline)
            XCTAssertEqual(full.extent,source.extent)
            XCTAssertGreaterThan(difference,0.8,style.rawValue)
            XCTAssertEqual(samples(renderer.render(source,style:style,amount:0)),baseline)
            let partial = delta(samples(renderer.render(source,style:style,amount:0.5)),baseline)
            XCTAssertGreaterThan(difference,partial*1.15,style.rawValue)
            print("Style \(style.rawValue): chart RGB change \(difference), half \(partial)")
            for (other,values) in rendered { XCTAssertGreaterThan(delta(pixels,values),0.45,"\(style.rawValue) must differ from \(other.rawValue)") }
            rendered.append((style,pixels))
        }
    }
    func testWarmColdAndMonochromeHaveTheirAdvertisedDirection() {
        let renderer = StyleRenderer(), source = chart()
        let warm = samples(renderer.render(source,style:.warm,amount:1))
        let cold = samples(renderer.render(source,style:.cold,amount:1))
        XCTAssertGreaterThan(warm[6]-warm[8],cold[6]-cold[8]+3)
        let mono = samples(renderer.render(source,style:.monochrome,amount:1))
        for i in stride(from:0,to:mono.count,by:3) {
            XCTAssertLessThanOrEqual(abs(mono[i]-mono[i+1]),2)
            XCTAssertLessThanOrEqual(abs(mono[i+1]-mono[i+2]),2)
        }
    }
    func testNewBeautyRecipesKeepSkinOnlySeparateFromGeometryAndMakeup() {
        let clean = BeautyLook.clean.recipe
        XCTAssertGreaterThan(clean.smoothing,0)
        XCTAssertEqual(clean.faceWidth,0); XCTAssertEqual(clean.lipstick,0); XCTAssertEqual(clean.eyes,0)
        var bronze = EditSettings(); bronze.beautyLook = .bronze; bronze.beautyAmount = 1
        XCTAssertGreaterThan(bronze.effective().skinTone,0)
        var focus = EditSettings(); focus.beautyLook = .focus
        XCTAssertGreaterThan(focus.effective().eyeLift,0)
        XCTAssertEqual(BeautyLook.allCases.count,13); XCTAssertEqual(PhotoStyle.allCases.count,13)
    }
    func testRealPortraitStyleExamplesAndThumbnails() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource:"DemoPortrait",withExtension:"jpg"))
        let data = try Data(contentsOf:url), source = try MediaIO.decode(data,maxDimension:512)
        for style in [PhotoStyle.portrait,.cinematic,.peach,.rose,.mocha,.goldenHour,.editorial,.monochrome] {
            let output = StyleRenderer().render(source,style:style,amount:1)
            let attachment = XCTAttachment(image:try pipeline.bitmap(output)); attachment.name = "Style 1.3 — \(style.rawValue)";attachment.lifetime = .keepAlways;add(attachment)
        }
        let (looks,styles) = try await ThumbnailWorker().generate(data)
        XCTAssertEqual(styles.count,PhotoStyle.allCases.count)
        XCTAssertGreaterThan(looks.count,1,"Thumbnails must show actual face-aware processing")
        XCTAssertNotEqual(styles[.natural]?.pngData(),styles[.cinematic]?.pngData())
        XCTAssertNotEqual(looks[.none]?.pngData(),looks[.clean]?.pngData())
        XCTAssertLessThanOrEqual(styles.values.map { max($0.size.width,$0.size.height) }.max() ?? 0,256)
    }
}
