// FlagUtils.swift
// Utility to produce emoji flag from ISO alpha-2 codes

import Foundation

func flagEmoji(from isoRaw: String?) -> String? {
    guard let iso = isoRaw?.trimmingCharacters(in: .whitespacesAndNewlines), iso.count == 2 else { return nil }
    let upper = iso.uppercased()
    var scalars: [UnicodeScalar] = []
    for ch in upper.unicodeScalars {
        guard let scalar = UnicodeScalar(127397 + ch.value) else { return nil }
        scalars.append(scalar)
    }
    return String(String.UnicodeScalarView(scalars))
}
