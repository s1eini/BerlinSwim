import Foundation

/// Localized string from BadKit's own catalog (`Localizable.xcstrings`, German source, English translation).
/// Interpolations become format arguments, e.g. `L("bis \(time)")` → key "bis %@".
func L(_ key: String.LocalizationValue) -> String {
    glueUhr(String(localized: key, bundle: .module))
}

/// German "18:00 Uhr": a non-breaking space keeps "Uhr" glued to the time, so it never wraps onto its own line.
func glueUhr(_ s: String) -> String {
    s.replacingOccurrences(of: " Uhr", with: "\u{00A0}Uhr")
}

/// Translates a term scraped from berlinerbaeder.de (facility, pool type, area/basin name, slot label)
/// via the BadKit catalog. Unknown terms (new on the site) fall back to the German original.
public func siteTerm(_ german: String) -> String {
    String(localized: String.LocalizationValue(german), bundle: .module)
}
