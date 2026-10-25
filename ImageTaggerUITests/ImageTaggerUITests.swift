//
//  ImageTaggerUITests.swift
//  ImageTaggerUITests
//
//  Created by Denis-Cosmin Nutiu on 25/10/2026.
//

import XCTest

final class ImageTaggerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testShowsEmptyStateAtLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["No Images"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add Images…"].exists)
        XCTAssertFalse(app.menuItems["Copy Tags"].isEnabled)
        attachScreenshot(of: app, named: "Empty State")
    }

    @MainActor
    func testTagsImagesOpenedFromFinder() throws {
        let app = XCUIApplication()
        app.launch()

        // Opening a folder adds all the images inside it, like dropping it on the Dock icon.
        let imagesFolder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "timisoara-bega", withExtension: "jpg"))
            .deletingLastPathComponent()
        app.open(imagesFolder)

        let images = app.outlines["images"]
        XCTAssertTrue(images.waitForExistence(timeout: 10))
        XCTAssertEqual(images.cells.count, 3)

        let tags = app.staticTexts["tags"]
        XCTAssertTrue(tags.waitForExistence(timeout: 60))
        let commaSeparatedTags = try XCTUnwrap(tags.value as? String)
        XCTAssertTrue(commaSeparatedTags.contains("night, no people"), commaSeparatedTags)
        XCTAssertTrue(app.menuItems["Copy Tags"].isEnabled)
        attachScreenshot(of: app, named: "Tagged Image")

        app.radioButtons["Hashtags"].click()
        let hashtags = try XCTUnwrap(tags.value as? String)
        XCTAssertTrue(hashtags.contains("#night #nopeople"), hashtags)

        images.cells.element(boundBy: 2).click()
        let waterTowerTags = try XCTUnwrap(app.staticTexts["tags"].value as? String)
        XCTAssertTrue(waterTowerTags.contains("#architecture"), waterTowerTags)
        attachScreenshot(of: app, named: "Hashtags")

        app.radioButtons["Comma"].click()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
