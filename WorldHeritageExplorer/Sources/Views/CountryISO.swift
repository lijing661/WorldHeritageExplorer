// CountryISO.swift
// Simple country name -> ISO alpha-2 lookup with sensible normalization.

import Foundation

// Small curated mapping. Expand as needed or generate automatically from whc001.csv.
private let countryNameToISO: [String: String] = [
    "albania": "al",
    "andorra": "ad",
    "australia": "au",
    "austria": "at",
    "belgium": "be",
    "brazil": "br",
    "canada": "ca",
    "china": "cn",
    "denmark": "dk",
    "egypt": "eg",
    "finland": "fi",
    "france": "fr",
    "greece": "gr",
    "india": "in",
    "indonesia": "id",
    "iran": "ir",
    "iran (islamic republic of)": "ir",
    "italy": "it",
    "japan": "jp",
    "jordan": "jo",
    "mongolia": "mn",
    "netherlands": "nl",
    "new zealand": "nz",
    "norway": "no",
    "poland": "pl",
    "portugal": "pt",
    "russia": "ru",
    "saint kitts and nevis": "kn",
    "sao tome and principe": "st",
    "south africa": "za",
    "spain": "es",
    "sweden": "se",
    "switzerland": "ch",
    "thailand": "th",
    "tunisia": "tn",
    "united kingdom": "gb",
    "united states of america": "us",
    "united states": "us",
    "vietnam": "vn",
    "state of palestine": "ps",
    "palestine": "ps",
]

// Normalize country name: lowercased, trimmed, remove punctuation often present
private func normalizeCountryName(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    // remove surrounding quotes
    if t.hasPrefix("\"") && t.hasSuffix("\"") {
        t = String(t.dropFirst().dropLast())
    }
    // remove contents within parentheses and commas
    t = t.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
    t = t.replacingOccurrences(of: ",", with: "")
    // collapse multiple spaces
    t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    return t
}

/// Return ISO alpha-2 code (lowercased) for a country name if known
func isoForCountry(_ countryName: String) -> String? {
    let n = normalizeCountryName(countryName)
    if let v = countryNameToISO[n] { return v }
    // try some heuristics: split by ";" or "," and check first token
    let separators = CharacterSet(charactersIn: ",;/|、")
    let parts = n.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    for p in parts {
        if let v = countryNameToISO[p] { return v }
    }
    return nil
}
