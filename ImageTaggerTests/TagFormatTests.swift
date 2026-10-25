//
//  TagFormatTests.swift
//  ImageTaggerTests
//

import Testing
@testable import ImageTagger

struct TagFormatTests {
    private let tags = ["lake", "no people", "outdoors"]

    @Test func comma() {
        #expect(TagFormat.comma.format(tags) == "lake, no people, outdoors")
    }

    @Test func space() {
        #expect(TagFormat.space.format(tags) == "lake no people outdoors")
    }

    @Test func hashtagsRemoveWhitespace() {
        #expect(TagFormat.hashtags.format(tags) == "#lake #nopeople #outdoors")
    }

    @Test(arguments: TagFormat.allCases)
    func emptyTags(format: TagFormat) {
        #expect(format.format([]).isEmpty)
    }
}
