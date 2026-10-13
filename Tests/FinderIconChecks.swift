import Foundation

func require(_ condition: Bool, _ message: String) { precondition(condition, message) }
let args = CommandLine.arguments
let root = URL(fileURLWithPath: args[1])
let app = URL(fileURLWithPath: args[2])
let descriptor = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.icon/icon.json"))) as! [String: Any]
require(descriptor["fill"] as? String == "none", "Finder authoring must not add a background fill")
let groups = descriptor["groups"] as! [[String: Any]]
require(groups.count == 1, "Do not split or redesign approved artwork")
let group = groups[0]
let layers = group["layers"] as! [[String: Any]]
require(layers.count == 1 && layers[0]["image-name"] as? String == "AppIcon.png", "Use approved master as one unchanged layer")
require(layers[0]["glass"] as? Bool == false && layers[0]["fill"] == nil && layers[0]["position"] == nil, "No glass, recoloring or custom artwork transform")
require(group["specular"] as? Bool == false && group["blur-material"] as? Int == 0, "Do not add material effects")
let shadow = group["shadow"] as! [String: Any]
let translucency = group["translucency"] as! [String: Any]
require(shadow["kind"] as? String == "none" && shadow["opacity"] as? Int == 0, "No added artwork shadow")
require(translucency["enabled"] as? Bool == false, "No added translucency")
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
require(info["CFBundleIconName"] as? String == "AppIcon" && info["CFBundleIconFile"] as? String == "AppIcon.icns", "Modern Finder selection plus ICNS fallback")
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [[String: Any]]
let stacks = catalog.filter { $0["AssetType"] as? String == "IconImageStack" && $0["Name"] as? String == "AppIcon" }
require(!stacks.isEmpty, "Missing modern icon stack; ICNS-only packaging reintroduces Finder container")
let appearances = Set(stacks.compactMap { $0["Appearance"] as? String })
require(appearances.contains("NSAppearanceNameAqua") && appearances.contains("NSAppearanceNameDarkAqua"), "Missing native light/dark Finder renditions")
let artwork = catalog.filter { $0["AssetType"] as? String == "Image" && $0["Name"] as? String == "AppIcon_Assets/AppIcon" }
require(!artwork.isEmpty && artwork.allSatisfy { $0["Opaque"] as? Bool == false }, "Approved artwork alpha missing from catalog")
print("Finder icon checks passed: no authoring fill/effects, compiled modern light/dark stacks, retained artwork alpha, ICNS fallback and bundle declarations. Actual Finder appearance requires HAT.")
