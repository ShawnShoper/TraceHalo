import AppKit
import Foundation

enum ReportPDFExporter {
    @MainActor
    static func write(_ report: String, to destination: URL) throws {
        let pageSize = NSSize(width: 595, height: 842)
        let printableWidth = pageSize.width - 72
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: printableWidth, height: pageSize.height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: report, attributes: attributes))
        textView.sizeToFit()
        textView.frame.size.width = printableWidth

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
