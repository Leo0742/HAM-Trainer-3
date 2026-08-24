import Foundation

enum CategoryProfile {
    static let productName = "HAM Trainer 3"
    static let categoryDisplayName = "третья категория"
    static let bankCount = 218
    static let examQuestionCount = 25
    static let passingScore = 20
    static let persistenceNamespace = "HAMTrainer3"
    static let backupFilename = "HAMTrainer3-backup.json"

    static let examNumberRanges: [ClosedRange<Int>] = [
        1...34,
        47...98,
        100...135,
        150...226,
        387...391,
        409...422,
    ]

    static let examNumbers = Set(examNumberRanges.flatMap(Array.init))

    static func contains(examNumber: Int) -> Bool {
        examNumbers.contains(examNumber)
    }
}
