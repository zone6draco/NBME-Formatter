
import Foundation
import PDFKit
import CoreGraphics
import AppKit

enum PDFPageFactory {

    struct TextLine {
        let text: String
        let font: NSFont
        let color: NSColor
    }

    /// Create a single-page PDFPage with a simple vertical list of lines.
    static func makeTextPage(
        title: String,
        titleColor: NSColor = .labelColor,
        lines: [TextLine],
        pageSize: CGSize = CGSize(width: 595, height: 842) // US Letter
    ) throws -> PDFPage {

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw NSError(domain: "PDFPageFactory", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF graphics context"])
        }

        ctx.beginPDFPage(nil)

        // Background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(mediaBox)

        // Title
        var y: CGFloat = pageSize.height - 72
        drawText(ctx, text: title, x: 50, y: y,
                 font: NSFont.boldSystemFont(ofSize: 24),
                 color: titleColor)
        y -= 44

        // Lines
        for line in lines {
            drawText(ctx, text: line.text, x: 50, y: y, font: line.font, color: line.color)
            y -= 22
            if y < 72 {
                // keep it simple: stop drawing if page full
                break
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()

        guard let doc = PDFDocument(data: data as Data),
              let page = doc.page(at: 0)
        else {
            throw NSError(domain: "PDFPageFactory", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page"])
        }

        return page
    }

    private static func drawText(
        _ ctx: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        font: NSFont,
        color: NSColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            // ✅ CoreText color key — ALWAYS BLACK
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor
        ]

        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)

        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
