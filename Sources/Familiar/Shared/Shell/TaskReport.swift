import CoreGraphics
import Foundation

/// What a background task came to, as the chat shows it: the door from Act's task window into Ask's chat. The title is
/// what the person asked, the text is the answer, the line says how it went, where and how long, and the image is the
/// last view of the window it worked in.
struct TaskReport {
    let id: UUID
    let title: String
    let text: String
    let line: String
    let image: CGImage?
}
