import UIKit
import CoreImage

/// Separate worker: the catalogue never queues ahead of interactive full-size rendering.
actor ThumbnailWorker {
    func generate(_ data: Data) throws -> ([BeautyLook:UIImage],[PhotoStyle:UIImage]) {
        let pipeline = ImagePipeline()
        let source = try MediaIO.decode(data,maxDimension:256)
        let faces = try FaceAnalyzer().detect(in:source)
        var looks: [BeautyLook:UIImage] = [:], styles: [PhotoStyle:UIImage] = [:]
        for look in BeautyLook.allCases {
            try Task.checkCancellation()
            if look != .none && faces.isEmpty { continue }
            var settings = EditSettings(); settings.beautyLook = look; settings.makeupColor = look.recipe.makeupColor
            looks[look] = try autoreleasepool { try pipeline.bitmap(pipeline.render(source,settings:settings,faces:faces)) }
        }
        for style in PhotoStyle.allCases {
            try Task.checkCancellation()
            styles[style] = try autoreleasepool { try pipeline.bitmap(StyleRenderer().render(source,style:style,amount:1)) }
        }
        return (looks,styles)
    }
}
