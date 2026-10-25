//
//  TagFormat.swift
//  ImageTagger
//

import Foundation

/// Determines how tags are displayed and copied.
nonisolated enum TagFormat: String, CaseIterable, Identifiable, Sendable {
    /// `lake, nature, no people`
    case comma
    /// `lake nature no people`
    case space
    /// `#lake #nature #nopeople`
    case hashtags

    /// The user defaults key that stores the selected format.
    static let storageKey = "tagFormat"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .comma: "Comma"
        case .space: "Space"
        case .hashtags: "Hashtags"
        }
    }

    /// Joins the tags into a single string using this format.
    func format(_ tags: [String]) -> String {
        switch self {
        case .comma:
            tags.joined(separator: ", ")
        case .space:
            tags.joined(separator: " ")
        case .hashtags:
            // Hashtags can't contain whitespace, so multi-word tags are joined together.
            tags.map { "#" + $0.filter { !$0.isWhitespace } }.joined(separator: " ")
        }
    }
}
