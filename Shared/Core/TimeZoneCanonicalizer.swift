import Foundation

/// Canonical time-zone identifiers, as ICU (the system's Unicode and time-zone library) defines them.
///
/// Zones have several names: "Asia/Kolkata" and "Asia/Calcutta", "Europe/Kyiv" and "Europe/Kiev",
/// "US/Eastern" and "America/New_York". ICU maps each to one canonical name (CLDR's, which keeps the older
/// spelling: Asia/Calcutta, Europe/Kiev). Apple's Clock database uses those canonical names too.
///
/// Foundation has no public API for this, so this calls ICU's C function `ucal_getCanonicalTimeZoneID`,
/// which macOS exports, unversioned, from /usr/lib/libicucore.A.dylib (Foundation itself is built on it).
/// It is looked up with `dlsym`. If it's ever missing, every lookup returns nil and callers fall back to
/// exact identifiers.
enum TimeZoneCanonicalizer {
    // int32_t ucal_getCanonicalTimeZoneID(const UChar *id, int32_t len, UChar *result, int32_t resultCapacity,
    //                                     UBool *isSystemID, UErrorCode *status)
    private typealias Function = @convention(c) (
        UnsafePointer<UInt16>, Int32, UnsafeMutablePointer<UInt16>, Int32,
        UnsafeMutablePointer<Int8>?, UnsafeMutablePointer<Int32>
    ) -> Int32

    private static let function: Function? = {
        guard let handle = dlopen("/usr/lib/libicucore.A.dylib", RTLD_LAZY | RTLD_NOLOAD) ?? dlopen("/usr/lib/libicucore.A.dylib", RTLD_LAZY),
              let symbol = dlsym(handle, "ucal_getCanonicalTimeZoneID") else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    /// True if ICU's function was found (always, on macOS).
    static var isAvailable: Bool { function != nil }

    /// "Asia/Kolkata" → "Asia/Calcutta". Nil for identifiers ICU doesn't know.
    static func canonicalIdentifier(_ identifier: String) -> String? {
        guard let function, !identifier.isEmpty else { return nil }
        let input = Array(identifier.utf16)
        var output = [UInt16](repeating: 0, count: 128)
        var isSystemID: Int8 = 0
        var status: Int32 = 0 // U_ZERO_ERROR; > 0 is an error, < 0 a warning
        let length = function(input, Int32(input.count), &output, Int32(output.count), &isSystemID, &status)
        guard status <= 0, isSystemID != 0, length > 0, Int(length) <= output.count else { return nil }
        return String(decoding: output.prefix(Int(length)), as: UTF16.self)
    }

    /// True if both identifiers name the same zone ("Asia/Kolkata" and "Asia/Calcutta").
    static func sameZone(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let canonicalA = canonicalIdentifier(a) else { return false }
        return canonicalA == canonicalIdentifier(b)
    }
}
