import Foundation

/// Names a page makes up as it loads, which can name another thing on the next load: ids such as `ember412`, `:r5:`,
/// `ext-gen12`, `mat-input-3`, `ui-id-4` and long hex, and class names a styling tool generates, such as `css-1x2y3z`
/// and `sc-AbCdE`. Nothing is stuck to one of these.
enum GeneratedID {
    static func isSteady(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return id.range(of: #"\d{3,}|^:r|«r|^(ember|ext-|mat-|ui-id-|gwt-uid|react-|radix-|headlessui-)|[0-9a-f]{8,}|^[0-9]"#,
                        options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func isSteadyClass(_ name: String) -> Bool {
        isSteady(name) && name.count <= 40
            && name.range(of: #"^(css|sc|jsx|styled|emotion|chakra|mui)-"#, options: [.regularExpression, .caseInsensitive]) == nil
    }
}
