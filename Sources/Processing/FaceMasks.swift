import UIKit
import CoreImage

/// All public coordinates are Core Image pixels (origin at lower left).
/// UIKit rasterization explicitly flips y exactly once.
struct FaceMasks {
    let extent: CGRect
    func raster(blur: CGFloat = 0, draw: (CGContext) -> Void) -> CIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let scale = min(1, 1024 / max(extent.width, extent.height))
        let size = CGSize(width: extent.width*scale, height: extent.height*scale)
        let ui = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let c = renderer.cgContext
            c.setFillColor(UIColor.black.cgColor); c.fill(CGRect(origin:.zero,size:size))
            c.scaleBy(x:scale,y:scale)
            c.translateBy(x:0,y:extent.height); c.scaleBy(x:1,y:-1)
            c.setFillColor(UIColor.white.cgColor); c.setStrokeColor(UIColor.white.cgColor)
            draw(c)
        }
        let image = CIImage(cgImage: ui.cgImage!).transformed(by:CGAffineTransform(scaleX:1/scale,y:1/scale))
        return blur > 0 ? image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters:[kCIInputRadiusKey:blur]).cropped(to:extent) : image
    }
    func polygon(_ c: CGContext, _ points: [CGPoint]) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to:first)
        for p in points.dropFirst() { c.addLine(to:p) }
        c.closePath(); c.fillPath()
    }
    /// Andrew's monotone chain: a closed, non-self-intersecting face envelope.
    /// Contour samples are treated as points, never assumed to be a boundary walk.
    func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var unique: [CGPoint] = []
        for point in sorted { if unique.last != point { unique.append(point) } }
        guard unique.count > 2 else { return unique }
        func cross(_ a: CGPoint,_ b: CGPoint,_ c: CGPoint) -> CGFloat {
            (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
        }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for point in unique {
            while lower.count >= 2 && cross(lower[lower.count-2],lower[lower.count-1],point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        for point in unique.reversed() {
            while upper.count >= 2 && cross(upper[upper.count-2],upper[upper.count-1],point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        return Array(lower.dropLast())+Array(upper.dropLast())
    }
    func skin(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.018) { c in
            // Jaw landmarks plus an estimated forehead cap; excludes eye/brow/lip/nose edges.
            let b = f.bounds
            if f.contour.count >= 5 {
                var p = f.contour
                // Vision contour direction must not create a self-intersecting
                // jaw/forehead polygon when closing the upper face.
                if let first = p.first, let last = p.last, first.x > last.x { p.reverse() }
                p += [CGPoint(x:b.maxX-b.width*0.10,y:b.maxY-b.height*0.12),
                      CGPoint(x:b.midX,y:b.maxY),CGPoint(x:b.minX+b.width*0.10,y:b.maxY-b.height*0.12)]
                polygon(c,convexHull(p))
            } else { c.fillEllipse(in:b.insetBy(dx:b.width*0.1,dy:b.height*0.03)) }
            c.setFillColor(UIColor.black.cgColor)
            for region in [f.leftEye,f.rightEye,f.leftBrow,f.rightBrow,f.outerLips] {
                let r = bounding(region).insetBy(dx:-b.width*0.035,dy:-b.height*0.025)
                c.fillEllipse(in:r)
            }
        }
    }
    func eyes(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.004) { c in polygon(c,f.leftEye); polygon(c,f.rightEye) }
    }
    func teeth(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.003) { c in polygon(c,f.innerLips) }
    }
    func forehead(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.025) { c in
            let b = f.bounds
            c.fillEllipse(in:CGRect(x:b.minX+b.width*0.2,y:b.maxY-b.height*0.23,width:b.width*0.6,height:b.height*0.17))
        }
    }
    func lips(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.004) { c in
            polygon(c,f.outerLips)
            c.setFillColor(UIColor.black.cgColor); polygon(c,f.innerLips)
        }
    }
    func eyebrows(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.005) { c in
            for p in [f.leftBrow,f.rightBrow] {
                guard let first = p.first else { continue }
                c.setLineWidth(f.bounds.width*0.022); c.setLineCap(.round)
                c.beginPath(); c.move(to:first); p.dropFirst().forEach { c.addLine(to:$0) }; c.strokePath()
            }
        }
    }
    func eyeAreas(_ f: FaceGeometry, below: Bool) -> CIImage {
        raster(blur:f.bounds.width*0.018) { c in
            for p in [f.leftEye,f.rightEye] {
                let r = bounding(p)
                guard r.width > 0 else { continue }
                let y = below ? r.minY-r.height*0.9 : r.maxY
                c.fillEllipse(in:CGRect(x:r.minX-r.width*0.05,y:y,width:r.width*1.1,height:r.height*0.9))
            }
        }
    }
    func liner(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.002) { c in
            for p in [f.leftEye,f.rightEye] {
                let mid = bounding(p).midY
                let upper = p.filter { $0.y >= mid }.sorted { $0.x < $1.x }
                guard let first = upper.first else { continue }
                c.setLineWidth(f.bounds.width*0.008); c.setLineCap(.round)
                c.beginPath(); c.move(to:first); upper.dropFirst().forEach { c.addLine(to:$0) }; c.strokePath()
            }
        }
    }
    func cheeks(_ f: FaceGeometry) -> CIImage {
        raster(blur:f.bounds.width*0.045) { c in
            for p in [f.leftEye,f.rightEye] {
                guard let eye = FaceGeometry.center(p) else { continue }
                let w = f.bounds.width*0.19
                c.fillEllipse(in:CGRect(x:eye.x-w/2,y:eye.y-f.bounds.height*0.27,width:w,height:w*0.65))
            }
        }
    }
    func bounding(_ p: [CGPoint]) -> CGRect {
        guard !p.isEmpty else { return .zero }
        let minX = p.map(\.x).min()!, maxX = p.map(\.x).max()!
        let minY = p.map(\.y).min()!, maxY = p.map(\.y).max()!
        return CGRect(x:minX,y:minY,width:maxX-minX,height:maxY-minY)
    }
}
