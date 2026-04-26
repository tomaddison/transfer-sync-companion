import SwiftUI

extension Font {
    // Everything renders as Geologica-Regular to match the CTA button weight.
    static func companion(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geologica-Regular", size: size)
    }
}
