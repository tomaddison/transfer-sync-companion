import Foundation

/// Ports the name-matching algorithm from
/// `transfersync/features/versioning/features/auto-stacking/utils.ts`
enum AutoStackMatcher {

    struct Match {
        let assetId: String
        let assetName: String
        let assetType: String
    }

    static func findBestMatch(fileName: String, candidates: [FolderAsset]) -> Match? {
        let fileWords = tokenize(fileName)
        guard !fileWords.isEmpty else { return nil }

        var bestMatch: FolderAsset?
        var bestScore: Double = -1

        for candidate in candidates {
            guard let name = candidate.name else { continue }
            let candidateWords = tokenize(name)
            guard !candidateWords.isEmpty else { continue }

            let score = computeMatchScore(
                uploadedWords: fileWords,
                existingWords: candidateWords,
                isStack: candidate.assetType == "stack"
            )
            if score > bestScore {
                bestScore = score
                bestMatch = candidate
            }
        }

        guard let match = bestMatch, bestScore > 0 else { return nil }
        return Match(assetId: match.id, assetName: match.name ?? "", assetType: match.assetType)
    }

    // MARK: - Private

    private static func stripExtension(_ name: String) -> String {
        guard let dotIndex = name.lastIndex(of: ".") else { return name }
        return String(name[name.startIndex..<dotIndex])
    }

    private static func tokenize(_ name: String) -> [String] {
        stripExtension(name)
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " _-"))
            .filter { !$0.isEmpty }
    }

    private static func isNumericToken(_ token: String) -> Bool {
        token.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil
    }

    private static func longestCommonWordSequence(_ a: [String], _ b: [String]) -> [String] {
        var best: [String] = []
        for i in 0..<a.count {
            for j in 0..<b.count {
                if a[i] == b[j] {
                    var len = 1
                    while i + len < a.count && j + len < b.count && a[i + len] == b[j + len] {
                        len += 1
                    }
                    if len > best.count {
                        best = Array(a[i..<(i + len)])
                    }
                }
            }
        }
        return best
    }

    private static func computeMatchScore(
        uploadedWords: [String],
        existingWords: [String],
        isStack: Bool
    ) -> Double {
        let shared = longestCommonWordSequence(uploadedWords, existingWords)

        let sharedMeaningful = shared.filter { !isNumericToken($0) }
        guard !sharedMeaningful.isEmpty else { return -1 }

        let uploadedMeaningful = uploadedWords.filter { !isNumericToken($0) }.count
        let existingMeaningful = existingWords.filter { !isNumericToken($0) }.count
        let shorterMeaningful = min(uploadedMeaningful, existingMeaningful)

        guard shorterMeaningful > 0 else { return -1 }

        let coverage = Double(sharedMeaningful.count) / Double(shorterMeaningful)
        guard coverage >= 0.5 else { return -1 }

        let maxLen = max(uploadedWords.count, existingWords.count)
        var score = Double(shared.count) / Double(maxLen)

        score += coverage * 0.3

        if sharedMeaningful.count == shorterMeaningful {
            score += 0.2
        }

        if isStack {
            score += 0.25
        }

        return score
    }
}
