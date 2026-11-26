// Loads a bundle's Metadata.appintents with the system's own parser (LinkMetadata.framework's
// LNBundleMetadata — what linkd uses) and prints what it understood. Private API, used only as a build check.
//
//   ln_validate <path/to/Bundle.appex> [full]
import Foundation
import ObjectiveC

let linkMetadata = dlopen("/System/Library/PrivateFrameworks/LinkMetadata.framework/LinkMetadata", RTLD_NOW)
_ = dlopen("/System/Library/PrivateFrameworks/LinkServices.framework/LinkServices", RTLD_NOW)
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: ln_validate <bundle> [full]")
    exit(2)
}
let full = args.count > 2 && args[2] == "full"
let bundleURL = URL(fileURLWithPath: args[1])
let fileURL = bundleURL.appendingPathComponent("Contents/Resources/Metadata.appintents/extract.actionsdata")
guard let cls = NSClassFromString("LNBundleMetadata") as? NSObject.Type else {
    print("PARSE: UNAVAILABLE (LNBundleMetadata not found on this macOS)")
    exit(3)
}
let sel = NSSelectorFromString("initWithMetadataFileURL:bundleURL:effectiveBundleIdentifier:error:")
typealias InitFn = @convention(c) (AnyObject, Selector, NSURL, NSURL, AnyObject?, UnsafeMutablePointer<NSError?>?) -> AnyObject?
let raw = cls.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
guard let imp = (raw as! NSObject).method(for: sel) else {
    print("PARSE: UNAVAILABLE (initializer not found on this macOS)")
    exit(3)
}
let initialize = unsafeBitCast(imp, to: InitFn.self)
var error: NSError?
let metadata = initialize(raw, sel, fileURL as NSURL, bundleURL as NSURL, nil, &error)
print("PARSE:", metadata == nil ? "FAILED \(String(describing: error))" : "OK")
// The widget family names a collection size may use (the parser accepts any string; the Edit Widget UI looks
// these up).
let familySymbols = ["Wildcard", "SystemSmall", "SystemMedium", "SystemLarge", "SystemExtraLarge",
                     "SystemExtraLargePortrait", "AccessoryCorner", "AccessoryCircular", "AccessoryRectangular",
                     "AccessoryInline"]
let families = familySymbols.compactMap { name -> String? in
    guard let symbol = dlsym(linkMetadata, "LNActionConfigurationContextWidgetFamily\(name)") else { return nil }
    return symbol.assumingMemoryBound(to: NSString.self).pointee as String
}
print("WIDGET FAMILIES:", families.joined(separator: " "))
if let metadata = metadata as? NSObject {
    for key in ["actions", "entities", "queries", "enums"] {
        let description = String(describing: metadata.value(forKey: key))
        print("\n#### \(key):", full ? description : String(description.prefix(1500)))
    }
}
exit(metadata == nil ? 1 : 0)
