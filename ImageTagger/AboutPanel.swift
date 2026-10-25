//
//  AboutPanel.swift
//  ImageTagger
//

import AppKit

/// Shows the standard About panel with the app's credits.
enum AboutPanel {
    static let websiteURL = URL(string: "https://blog.nuculabs.dev")!
    static let sourceCodeURL = URL(string: "https://github.com/dnutiu/ImageTagger")!
    static let iconCreditURL = URL(string: "https://www.flaticon.com/free-icons/image-analysis")!

    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString()
        func append(_ text: String, link: URL? = nil) {
            var textAttributes = attributes
            if let link {
                textAttributes[.link] = link
            }
            credits.append(NSAttributedString(string: text, attributes: textAttributes))
        }

        append(String(localized: "ImageTagger predicts an image’s tags using deep learning. It helps photographers improve their workflow by auto-tagging images.\n"))
        append(String(localized: "Author: Denis-Cosmin Nutiu\n"))
        append("blog.nuculabs.dev", link: websiteURL)
        append("  ·  ")
        append("github.com/dnutiu/ImageTagger", link: sourceCodeURL)
        append("\n")
        append(String(localized: "Icon: Image analysis icons created by Dewi Sari – Flaticon"), link: iconCreditURL)
        return credits
    }
}
