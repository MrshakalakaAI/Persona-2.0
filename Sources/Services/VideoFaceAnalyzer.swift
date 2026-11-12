import CoreImage
import Foundation

/// Offline video analysis: landmarks are detected on each requested frame.
/// No claim of live camera tracking or measured device FPS.
final class VideoFaceAnalyzer {
    private let lock = NSLock()
    func faces(in image: CIImage) throws -> [FaceGeometry] {
        try lock.withLock {
            let scale = min(1,640/max(image.extent.width,image.extent.height))
            let small = image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            return try FaceAnalyzer().detect(in:small).map { f in
                func points(_ p: [CGPoint]) -> [CGPoint] { p.map { CGPoint(x:$0.x/scale,y:$0.y/scale) } }
                return FaceGeometry(bounds:CGRect(x:f.bounds.minX/scale,y:f.bounds.minY/scale,width:f.bounds.width/scale,height:f.bounds.height/scale),contour:points(f.contour),leftEye:points(f.leftEye),rightEye:points(f.rightEye),leftBrow:points(f.leftBrow),rightBrow:points(f.rightBrow),outerLips:points(f.outerLips),innerLips:points(f.innerLips),nose:points(f.nose))
            }
        }
    }
}
