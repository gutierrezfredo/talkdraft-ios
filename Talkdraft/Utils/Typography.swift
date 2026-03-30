import SwiftUI
import UIKit

extension UIFont {
    static func roundedBody() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: 0)
        }
        return base
    }
}

extension Font {
    static let brandLargeTitle = Font.custom("Bricolage Grotesque", size: 34, relativeTo: .largeTitle).weight(.semibold)
    static let brandTitle = Font.custom("Bricolage Grotesque", size: 28, relativeTo: .title).weight(.semibold)
    static let brandTitle2 = Font.custom("Bricolage Grotesque", size: 22, relativeTo: .title2).weight(.medium)
    static let brandTitle3 = Font.custom("Bricolage Grotesque", size: 20, relativeTo: .title3).weight(.regular)
    static let brandCardTitle = Font.custom("Bricolage Grotesque", size: 16, relativeTo: .headline).weight(.medium)
}
