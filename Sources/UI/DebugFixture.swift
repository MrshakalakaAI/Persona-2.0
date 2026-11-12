#if DEBUG
import UIKit

/// Deterministic local image for simulator UI automation. Never included in Release.
enum DebugFixture {
    static func photo() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size:CGSize(width:800,height:1100),format:format).image { r in
            let c = r.cgContext
            c.setFillColor(UIColor(red:0.24,green:0.27,blue:0.36,alpha:1).cgColor)
            c.fill(CGRect(x:0,y:0,width:800,height:1100))
            c.setFillColor(UIColor(red:0.65,green:0.47,blue:0.43,alpha:1).cgColor)
            c.fillEllipse(in:CGRect(x:230,y:170,width:340,height:490))
            c.setFillColor(UIColor(red:0.25,green:0.15,blue:0.19,alpha:1).cgColor)
            c.fillEllipse(in:CGRect(x:300,y:350,width:45,height:25))
            c.fillEllipse(in:CGRect(x:455,y:350,width:45,height:25))
            c.setStrokeColor(UIColor(red:0.45,green:0.22,blue:0.26,alpha:1).cgColor)
            c.setLineWidth(14); c.move(to:CGPoint(x:350,y:520)); c.addQuadCurve(to:CGPoint(x:450,y:520),control:CGPoint(x:400,y:555)); c.strokePath()
            c.setFillColor(UIColor(red:0.47,green:0.38,blue:0.59,alpha:1).cgColor)
            c.fillEllipse(in:CGRect(x:120,y:700,width:560,height:550))
        }
        return image.jpegData(compressionQuality:0.95)!
    }
}
#endif
