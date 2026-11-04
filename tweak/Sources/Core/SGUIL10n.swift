import Foundation

// UI-only localization. Translation prompts, Spotify strings and song metadata never use this API.
enum SGUIL10n {
    static var language: String {
        let manual = UserDefaults.standard.string(forKey: "spotifyglass.interfaceLanguage")
        if manual == "en" || manual == "vi" { return manual! }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("vi") == true ? "vi" : "en"
    }
    static var locale: Locale { Locale(identifier: language) }
    static func string(_ key: String, language: String? = nil) -> String {
        let language = (language ?? self.language).hasPrefix("vi") ? "vi" : "en"
        guard language == "vi", let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Vitrine")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
    static func error(_ error: Error) -> String {
        format("%@ (%ld)", string("Could not complete the operation. Please try again."), (error as NSError).code)
    }
}
