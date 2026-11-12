import XCTest
import CoreImage
import UIKit
import AVFoundation
@testable import PersonaFree

final class ProcessingTests: XCTestCase {
    private var pipeline: ImagePipeline!
    override func setUp() { pipeline = ImagePipeline() }
    private func image(_ size: CGSize = CGSize(width:400,height:600)) -> CIImage {
        CIImage(color:CIColor(red:0.6,green:0.4,blue:0.3)).cropped(to:CGRect(origin:.zero,size:size))
    }
    private func pixel(_ image: CIImage, at p: CGPoint = CGPoint(x:10,y:10)) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:4)
        pipeline.context.render(image,toBitmap:&bytes,rowBytes:4,bounds:CGRect(x:p.x,y:p.y,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        return bytes
    }
    func testDefaultSettingsPreservePixelsAndDimensions() throws {
        let input = image()
        let output = try pipeline.render(input,settings:EditSettings())
        XCTAssertEqual(output.extent,input.extent)
        for (a,b) in zip(pixel(input),pixel(output)) { XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),2) }
    }
    func testExposureChangesRenderedPixels() throws {
        var s = EditSettings(); s.exposure = 1
        let output = try pipeline.render(image(),settings:s)
        XCTAssertGreaterThan(Int(pixel(output)[0]),Int(pixel(image())[0]))
    }
    func testEveryStyleRendersFiniteBitmap() throws {
        for style in PhotoStyle.allCases {
            var s = EditSettings(); s.filter = style
            let output = try pipeline.render(image(),settings:s)
            XCTAssertNotNil(try pipeline.bitmap(output).cgImage,style.rawValue)
            XCTAssertEqual(output.extent,image().extent)
        }
    }
    func testCropRatiosAndOffsetsStayInsideImage() {
        for aspect in CropAspect.allCases {
            var s = EditSettings(); s.aspect = aspect; s.cropZoom = 1.7; s.cropX = 1; s.cropY = -1
            let result = pipeline.crop(image(),settings:s)
            XCTAssertEqual(result.extent.minX,0); XCTAssertEqual(result.extent.minY,0)
            XCTAssertLessThanOrEqual(result.extent.width,400); XCTAssertLessThanOrEqual(result.extent.height,600)
            if let ratio = aspect.ratio { XCTAssertEqual(Double(result.extent.width/result.extent.height),ratio,accuracy:0.02) }
        }
    }
    func testRotationAndStraightening() {
        var s = EditSettings(); s.quarterTurns = 1
        let rotated = pipeline.crop(image(),settings:s)
        XCTAssertEqual(rotated.extent.width,600); XCTAssertEqual(rotated.extent.height,400)
        s.straighten = 15
        let result = pipeline.crop(image(),settings:s)
        XCTAssertGreaterThan(result.extent.width,0)
        XCTAssertEqual(pixel(result,at:CGPoint(x:1,y:1))[3],255)
    }
    func testUndoRedoAndBranching() {
        var h = EditHistory(); let initial = EditSettings(); var changed = initial; changed.lipstick = 0.7
        h.record(initial)
        XCTAssertEqual(h.undo(changed),initial); XCTAssertEqual(h.redo(initial),changed)
        _ = h.undo(changed); h.record(initial)
        XCTAssertNil(h.redo(initial))
        for _ in 0..<90 { h.record(initial) }; XCTAssertEqual(h.undoStack.count,60)
    }
    func testSettingsRoundtrip() throws {
        var s = EditSettings(); s.filter = .cinematic; s.aspect = .story; s.faceWidth = -0.4
        XCTAssertEqual(try JSONDecoder().decode(EditSettings.self,from:JSONEncoder().encode(s)),s)
    }
    func testVisionNoFaceAndInvalidImage() throws {
        XCTAssertEqual(try FaceAnalyzer().detect(in:image()).count,0)
        XCTAssertThrowsError(try MediaIO.decode(Data([0,1,2]),maxDimension:100))
    }
    func testDecodeNormalizesOrientationAndDownsamples() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let ui = UIGraphicsImageRenderer(size:CGSize(width:300,height:100),format:format).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x:0,y:0,width:300,height:100))
        }
        let oriented = UIImage(cgImage:ui.cgImage!,scale:1,orientation:.right)
        let data = oriented.jpegData(compressionQuality:1)!
        let output = try MediaIO.decode(data,maxDimension:150)
        XCTAssertLessThanOrEqual(max(output.extent.width,output.extent.height),150)
        XCTAssertGreaterThan(output.extent.height,output.extent.width)
    }
    private func face() -> FaceGeometry {
        FaceGeometry(bounds:CGRect(x:100,y:180,width:200,height:270),contour:[],
                     leftEye:[CGPoint(x:155,y:350),CGPoint(x:170,y:355),CGPoint(x:180,y:350),CGPoint(x:170,y:344)],
                     rightEye:[CGPoint(x:220,y:350),CGPoint(x:235,y:355),CGPoint(x:250,y:350),CGPoint(x:235,y:344)],
                     leftBrow:[CGPoint(x:150,y:375),CGPoint(x:180,y:382)],rightBrow:[CGPoint(x:220,y:382),CGPoint(x:250,y:375)],
                     outerLips:[CGPoint(x:170,y:250),CGPoint(x:200,y:260),CGPoint(x:230,y:250),CGPoint(x:200,y:238)],
                     innerLips:[CGPoint(x:185,y:250),CGPoint(x:200,y:254),CGPoint(x:215,y:250),CGPoint(x:200,y:247)],
                     nose:[CGPoint(x:200,y:300)])
    }
    func testMaskCoordinatesAndExclusion() {
        let f = face(); let masks = FaceMasks(extent:image().extent)
        let lip = masks.lips(f)
        XCTAssertGreaterThan(pixel(lip,at:CGPoint(x:200,y:242))[0],50)
        XCTAssertLessThan(pixel(lip,at:CGPoint(x:200,y:350))[0],10)
        XCTAssertLessThan(pixel(masks.skin(f),at:CGPoint(x:170,y:350))[0],25)
    }
    func testFaceEffectsPreserveDistantBackground() throws {
        var s = EditSettings()
        s.smoothing = 1; s.blemishes = 1; s.redness = 1; s.skinTone = 0.8; s.underEyes = 1; s.wrinkles = 1
        s.faceWidth = 0.6; s.chin = 0.4; s.cheeks = 0.5; s.nose = 0.5; s.eyes = 0.5; s.lips = 0.5; s.browShape = 0.5
        s.lipstick = 1; s.blush = 1; s.eyeshadow = 1; s.eyeliner = 1; s.brows = 1
        let output = try pipeline.render(image(),settings:s,faces:[face()])
        XCTAssertNotNil(try pipeline.bitmap(output).cgImage)
        for (a,b) in zip(pixel(image()),pixel(output)) { XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),2) }
        XCTAssertNotEqual(pixel(image(),at:CGPoint(x:200,y:242)),pixel(output,at:CGPoint(x:200,y:242)))
    }
    func testGeometryMovesPixelsLocally() throws {
        let gradient = CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:400,y:0),"inputColor0":CIColor.black,"inputColor1":CIColor.white])!.outputImage!.cropped(to:image().extent)
        var settings = EditSettings(); settings.faceWidth = 1
        let output = try pipeline.render(gradient,settings:settings,faces:[face()])
        XCTAssertNotEqual(pixel(gradient,at:CGPoint(x:240,y:315)),pixel(output,at:CGPoint(x:240,y:315)))
        for (a,b) in zip(pixel(gradient),pixel(output)) { XCTAssertLessThanOrEqual(abs(Int(a)-Int(b)),2) }
    }
    func testJPEGExportDecodes() throws {
        let data = try XCTUnwrap(pipeline.context.jpegRepresentation(of:image(),colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!,options:[:]))
        XCTAssertEqual(try MediaIO.decode(data,maxDimension:4096).extent,image().extent)
    }
    func testVideoExportPreservesAudioAndPortrait() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mov")
        defer { try? FileManager.default.removeItem(at:url) }
        let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:240])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime:.zero)
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:10_000_000) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer),kCVReturnSuccess)
            let b = buffer!; CVPixelBufferLockBaseAddress(b,[])
            memset(CVPixelBufferGetBaseAddress(b),128,CVPixelBufferGetDataSize(b)); CVPixelBufferUnlockBaseAddress(b,[])
            XCTAssertTrue(adaptor.append(b,withPresentationTime:CMTime(value:Int64(frame),timescale:15)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status,.completed)
        // Generate PCM audio locally, then mux it into the source fixture.
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".caf")
        defer { try? FileManager.default.removeItem(at:wav) }
        let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:1)!
        let audioFile = try AVAudioFile(forWriting:wav,settings:format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:44100)!
        buffer.frameLength = 44100
        for i in 0..<44100 { buffer.floatChannelData![0][i] = Float(sin(Double(i)*2*Double.pi*440/44100))*0.1 }
        try audioFile.write(from:buffer)
        let composition = AVMutableComposition()
        let source = AVURLAsset(url:url), audio = AVURLAsset(url:wav)
        let sourceVideos = try await source.loadTracks(withMediaType:.video)
        let sourceAudio = try await audio.loadTracks(withMediaType:.audio)
        let v = try XCTUnwrap(sourceVideos.first)
        let a = try XCTUnwrap(sourceAudio.first)
        let range = CMTimeRange(start:.zero,duration:CMTime(value:14,timescale:15))
        try composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:v,at:.zero)
        try composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(range,of:a,at:.zero)
        let muxed = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mov")
        defer { try? FileManager.default.removeItem(at:muxed) }
        let mux = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
        mux.outputURL = muxed; mux.outputFileType = .mov
        await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in mux.exportAsynchronously { c.resume() } }
        XCTAssertEqual(mux.status,.completed)
        var s = EditSettings(); s.aspect = .story; s.exposure = 0.3; s.filter = .warm
        let result = try await VideoEngine().export(url:muxed,settings:s,progress:{_ in})
        defer { try? FileManager.default.removeItem(at:result) }
        let output = AVURLAsset(url:result)
        let videoTracks = try await output.loadTracks(withMediaType:.video)
        let audioTracks = try await output.loadTracks(withMediaType:.audio)
        XCTAssertEqual(videoTracks.count,1); XCTAssertEqual(audioTracks.count,1)
        let size = try await XCTUnwrap(videoTracks.first).load(.naturalSize)
        XCTAssertEqual(size.width/size.height,9.0/16,accuracy:0.015)
        let duration = try await output.load(.duration)
        XCTAssertGreaterThan(duration.seconds,0.8)
    }
}
