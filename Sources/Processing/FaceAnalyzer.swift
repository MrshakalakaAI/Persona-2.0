import Vision
import CoreImage

struct FaceGeometry {
    var bounds: CGRect
    var contour: [CGPoint]
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    var leftBrow: [CGPoint]
    var rightBrow: [CGPoint]
    var outerLips: [CGPoint]
    var innerLips: [CGPoint]
    var nose: [CGPoint]

    static func center(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        return CGPoint(x: points.map(\.x).reduce(0,+)/CGFloat(points.count), y: points.map(\.y).reduce(0,+)/CGFloat(points.count))
    }
}

struct FaceAnalyzer {
    func detect(in image: CIImage) throws -> [FaceGeometry] {
        let request = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        let size = image.extent.size
        return (request.results ?? []).filter { $0.confidence > 0.5 && $0.landmarks != nil }.map { face in
            let b = face.boundingBox
            func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                guard let region else { return [] }
                return region.normalizedPoints.map { CGPoint(x: (b.minX + CGFloat($0.x)*b.width)*size.width,
                                                            y: (b.minY + CGFloat($0.y)*b.height)*size.height) }
            }
            let l = face.landmarks!
            return FaceGeometry(bounds: CGRect(x:b.minX*size.width,y:b.minY*size.height,width:b.width*size.width,height:b.height*size.height),
                                contour:points(l.faceContour),leftEye:points(l.leftEye),rightEye:points(l.rightEye),
                                leftBrow:points(l.leftEyebrow),rightBrow:points(l.rightEyebrow),outerLips:points(l.outerLips),
                                innerLips:points(l.innerLips),nose:points(l.nose))
        }.sorted { $0.bounds.midX < $1.bounds.midX }
    }
}
