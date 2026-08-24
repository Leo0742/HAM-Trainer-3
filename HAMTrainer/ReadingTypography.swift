import SwiftUI

extension ReadingSize {
    var questionFontSize: CGFloat {
        switch self { case .regular: 22; case .large: 26; case .extraLarge: 30 }
    }

    var answerFontSize: CGFloat {
        switch self { case .regular: 16; case .large: 18; case .extraLarge: 21 }
    }

    var explanationFontSize: CGFloat {
        switch self { case .regular: 16; case .large: 18; case .extraLarge: 21 }
    }

    var metadataFontSize: CGFloat {
        switch self { case .regular: 13; case .large: 14; case .extraLarge: 16 }
    }

    var contentMaxWidth: CGFloat {
        switch self { case .regular: 1180; case .large: 1240; case .extraLarge: 1320 }
    }

    var answerPadding: CGFloat {
        switch self { case .regular: 14; case .large: 17; case .extraLarge: 20 }
    }
}
