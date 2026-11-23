import Foundation

/// Localized string from BadKit's own catalog (`Localizable.xcstrings`, German source, English translation).
/// Interpolations become format arguments, e.g. `L("bis \(time)")` → key "bis %@".
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Translates a term scraped from berlinerbaeder.de (facility, pool type, area/basin name, slot label)
/// via the BadKit catalog. Unknown terms (new on the site) fall back to the German original.
public func siteTerm(_ german: String) -> String {
    String(localized: String.LocalizationValue(german), bundle: .module)
}
