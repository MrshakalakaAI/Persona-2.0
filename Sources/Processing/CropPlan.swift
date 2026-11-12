import CoreImage
import ImageIO

struct CropPlan {
    var transform: CGAffineTransform
    var output: CGRect
    static func make(extent: CGRect, settings s: EditSettings) -> CropPlan {
        let image = CIImage(color:.black).cropped(to:extent)
        let turns = ((s.quarterTurns % 4)+4)%4
        let orientation: [CGImagePropertyOrientation] = [.up,.right,.down,.left]
        var transform = image.orientationTransform(forExifOrientation:Int32(orientation[turns].rawValue))
        var frame = extent.applying(transform)
        transform = transform.concatenating(CGAffineTransform(translationX:-frame.minX,y:-frame.minY))
        frame.origin = .zero
        if s.straighten != 0 {
            let a = CGFloat(s.straighten)*CGFloat.pi/180
            let rotation = CGAffineTransform(translationX:frame.midX,y:frame.midY).rotated(by:a).translatedBy(x:-frame.midX,y:-frame.midY)
            transform = transform.concatenating(rotation)
            let f = 1/(abs(cos(a))+max(frame.width/frame.height,frame.height/frame.width)*abs(sin(a)))
            frame = CGRect(x:frame.midX-frame.width*f/2,y:frame.midY-frame.height*f/2,width:frame.width*f,height:frame.height*f)
        }
        let ratio = CGFloat(s.aspect.ratio ?? Double(frame.width/frame.height))
        let width = min(frame.width,frame.height*ratio)/CGFloat(max(1,s.cropZoom)), height = width/ratio
        let crop = CGRect(x:frame.minX+(frame.width-width)*(CGFloat(s.cropX)+1)/2,y:frame.minY+(frame.height-height)*(CGFloat(s.cropY)+1)/2,width:width,height:height).integral.intersection(frame)
        transform = transform.concatenating(CGAffineTransform(translationX:-crop.minX,y:-crop.minY))
        return CropPlan(transform:transform,output:CGRect(origin:.zero,size:crop.size))
    }
    func sourcePoint(displayUnit: CGPoint, source: CGSize) -> CGPoint {
        let point = CGPoint(x:displayUnit.x*output.width,y:(1-displayUnit.y)*output.height).applying(transform.inverted())
        return CGPoint(x:min(1,max(0,point.x/source.width)),y:min(1,max(0,point.y/source.height)))
    }
}
