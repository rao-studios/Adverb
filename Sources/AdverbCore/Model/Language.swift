//
//  Language.swift
//  AdverbCore
//
//  WHAT: The languages a voice-over speaks: the 29 that ElevenLabs' Multilingual v2 reads, by ISO
//        639-1 code (Filipino is "fil", as ElevenLabs names it). English is the source every asset
//        is written in; the rest are targets, made after the English is confirmed.
//  PIN:  Cases are English names, never the code: Indonesian's code is "id", which an `id` case
//        would collide with Identifiable.
//

import Foundation

public enum Language: String, Codable, Sendable, CaseIterable, Hashable, Identifiable, Comparable {
    case english = "en", japanese = "ja", chinese = "zh", german = "de", hindi = "hi", french = "fr", korean = "ko",
         portuguese = "pt", italian = "it", spanish = "es", indonesian = "id", dutch = "nl", turkish = "tr", filipino = "fil",
         polish = "pl", swedish = "sv", bulgarian = "bg", romanian = "ro", arabic = "ar", czech = "cs", greek = "el",
         finnish = "fi", croatian = "hr", malay = "ms", slovak = "sk", danish = "da", tamil = "ta", ukrainian = "uk", russian = "ru"

    public var id: String { rawValue }
    public var code: String { rawValue }

    /// Every language but English, in the order the chips show them.
    public static var targets: [Language] { allCases.filter { $0 != .english } }

    /// Canonical (allCases) order, so a saved list reads the same however it was toggled.
    public static func < (a: Language, b: Language) -> Bool {
        (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
    }

    public var title: String {
        switch self {
        case .english: "English"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        case .german: "German"
        case .hindi: "Hindi"
        case .french: "French"
        case .korean: "Korean"
        case .portuguese: "Portuguese"
        case .italian: "Italian"
        case .spanish: "Spanish"
        case .indonesian: "Indonesian"
        case .dutch: "Dutch"
        case .turkish: "Turkish"
        case .filipino: "Filipino"
        case .polish: "Polish"
        case .swedish: "Swedish"
        case .bulgarian: "Bulgarian"
        case .romanian: "Romanian"
        case .arabic: "Arabic"
        case .czech: "Czech"
        case .greek: "Greek"
        case .finnish: "Finnish"
        case .croatian: "Croatian"
        case .malay: "Malay"
        case .slovak: "Slovak"
        case .danish: "Danish"
        case .tamil: "Tamil"
        case .ukrainian: "Ukrainian"
        case .russian: "Russian"
        }
    }

    /// The language's name for itself.
    public var nativeTitle: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        case .chinese: "中文"
        case .german: "Deutsch"
        case .hindi: "हिन्दी"
        case .french: "Français"
        case .korean: "한국어"
        case .portuguese: "Português"
        case .italian: "Italiano"
        case .spanish: "Español"
        case .indonesian: "Bahasa Indonesia"
        case .dutch: "Nederlands"
        case .turkish: "Türkçe"
        case .filipino: "Filipino"
        case .polish: "Polski"
        case .swedish: "Svenska"
        case .bulgarian: "Български"
        case .romanian: "Română"
        case .arabic: "العربية"
        case .czech: "Čeština"
        case .greek: "Ελληνικά"
        case .finnish: "Suomi"
        case .croatian: "Hrvatski"
        case .malay: "Bahasa Melayu"
        case .slovak: "Slovenčina"
        case .danish: "Dansk"
        case .tamil: "தமிழ்"
        case .ukrainian: "Українська"
        case .russian: "Русский"
        }
    }

    /// Codes to languages, dropping any this build does not know (a newer file's list).
    public static func decode(_ codes: [String]) -> [Language] {
        var seen = Swift.Set<Language>()
        return codes.compactMap(Language.init(rawValue:)).filter { seen.insert($0).inserted }.sorted()
    }
}
