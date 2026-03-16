import Cocoa

// MARK: - Annotation Types

enum AnnotationTool {
    case none
    case arrow
    case rectangle
    case text
    case mosaic
}

struct Annotation {
    var tool: AnnotationTool
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""           // Only used for text annotations
    var mosaicPath: [NSPoint] = []  // Only used for mosaic brush (stores path points)
    var mosaicBrushSize: CGFloat = 20  // Brush radius for mosaic
}
