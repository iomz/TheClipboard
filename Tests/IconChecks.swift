import AppKit
import CryptoKit
import Foundation
import ImageIO

func require(_ value: Bool, _ message: String) {
    precondition(value, message)
}
let args = CommandLine.arguments
let root = URL(fileURLWithPath: args[1])
let master = root.appendingPathComponent("Resources/Artwork/AppIcon.png")
let masterData = try Data(contentsOf: master)
let digest = SHA256.hash(data: masterData).map { String(format: "%02x", $0) }.joined()
require(digest == "df55707e5d173611f066daa1c9fc3c04d8c0272c68d46ff401890f154f247c94", "Approved master pixels/file changed")
let masterSource = CGImageSourceCreateWithData(masterData as CFData, nil)!
let masterImage = CGImageSourceCreateImageAtIndex(masterSource, 0, nil)!
require(masterImage.width == 1254 && masterImage.height == 1254, "Master dimensions changed")
require(masterImage.colorSpace?.name == CGColorSpace.sRGB, "Untagged master must decode as sRGB")
require([.first, .last, .premultipliedFirst, .premultipliedLast].contains(masterImage.alphaInfo), "Master alpha missing")
let masterBitmap = NSBitmapImageRep(cgImage: masterImage)
for (x, y) in [(0, 0), (1253, 0), (0, 1253), (1253, 1253)] {
    require(masterBitmap.colorAt(x: x, y: y)!.alphaComponent < 0.02, "Approved master corner transparency missing")
}

let representations: [(String, Int)] = [
    ("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64),
    ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256),
    ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)
]
let iconset = URL(fileURLWithPath: args[2])
for (name, size) in representations {
    let url = iconset.appendingPathComponent(name).appendingPathExtension("png")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    require(image.width == size && image.height == size, "Wrong representation size: \(name)")
    require([.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo), "Alpha missing: \(name)")
    require(image.colorSpace?.name == CGColorSpace.sRGB, "sRGB missing: \(name)")
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    require(properties[kCGImagePropertyProfileName] as? String == "sRGB IEC61966-2.1", "Embedded sRGB profile missing: \(name)")
    let bitmap = NSBitmapImageRep(cgImage: image)
    for (x,y) in [(0,0),(size-1,0),(0,size-1),(size-1,size-1)] {
        require(bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.02, "Opaque corner: \(name)")
    }
    require(bitmap.colorAt(x: size/2, y: size/2)!.alphaComponent > 0.9, "Icon body missing: \(name)")
}
if args.count > 3 {
    let app = URL(fileURLWithPath: args[3])
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
    require(info["CFBundleIconFile"] as? String == "AppIcon.icns", "Icon metadata missing")
    require(info["CFBundleIconName"] as? String == "AppIcon", "Modern Finder icon metadata missing")
    let url = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
    let icon = NSImage(contentsOf: url)!
    require(icon.isValid, "AppKit cannot load icon")
    let finderIcon = NSWorkspace.shared.icon(forFile: app.path)
    require(finderIcon.isValid, "Workspace cannot resolve bundle icon")
    print("AppKit icon load and Workspace/Finder icon lookup passed; Dock/actual UI appearance still requires HAT.")
}
print("Icon checks passed: approved master hash, ten ICNS representations, dimensions, sRGB, alpha and transparent corners.")
