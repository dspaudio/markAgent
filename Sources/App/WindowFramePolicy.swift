import AppKit

enum WindowFramePolicy {
    static let minimumContentSize = NSSize(width: 570, height: 320)

    static func normalizedSavedFrame(_ frame: NSRect, minimumFrameSize: NSSize) -> NSRect {
        let width = max(frame.width, minimumFrameSize.width)
        let height = max(frame.height, minimumFrameSize.height)
        return NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
    }

    static func restoredSavedFrame(
        _ savedFrame: NSRect,
        minimumFrameSize: NSSize,
        isVisible: (NSRect) -> Bool
    ) -> NSRect? {
        let normalizedFrame = normalizedSavedFrame(savedFrame, minimumFrameSize: minimumFrameSize)
        return isVisible(normalizedFrame) ? normalizedFrame : nil
    }
}
