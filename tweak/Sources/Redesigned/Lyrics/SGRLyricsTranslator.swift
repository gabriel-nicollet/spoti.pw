import Foundation
#if canImport(FoundationModels)
import FoundationModels

@objc(SGRLyricsTranslator)
public final class SGRLyricsTranslator: NSObject {
    @objc public class func isAvailable() -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @objc(translateLines:targetLanguage:completion:)
    public class func translateLines(_ lines: [String], targetLanguage: String,
                                     completion: @escaping ([String]?, NSError?) -> Void) {
        guard #available(iOS 26.0, *), isAvailable() else {
            completion(nil, NSError(domain: "SGRLyricsTranslator", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "On-device language model unavailable"]))
            return
        }
        Task {
            do {
                let session = LanguageModelSession(instructions: "You translate song lyrics faithfully. Preserve meaning, tone, line order, names, punctuation, and line count. Return translations only, without commentary.")
                var output = Array(repeating: "", count: lines.count)
                let batchSize = 8
                var start = 0
                while start < lines.count {
                    let end = min(start + batchSize, lines.count)
                    let batch = Array(lines[start..<end])
                    let source = batch.enumerated().map { "\($0.offset + 1)\t\($0.element.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n")
                    let prompt = "Translate each numbered lyric line into \(targetLanguage). Return exactly one numbered translated line for each input, keeping the numbering. Do not explain.\n\n\(source)"
                    let response = try await session.respond(to: prompt)
                    let parsed = Self.parse(response.content, expected: batch.count)
                    guard parsed.count == batch.count else {
                        throw NSError(domain: "SGRLyricsTranslator", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "The model returned an unexpected number of lyric lines"])
                    }
                    for index in 0..<parsed.count { output[start + index] = parsed[index] }
                    start = end
                }
                let completedOutput = output
                await MainActor.run { completion(completedOutput, nil) }
            } catch {
                await MainActor.run { completion(nil, error as NSError) }
            }
        }
    }

    private class func parse(_ text: String, expected: Int) -> [String] {
        let rows = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)[\.)\t:]\s*(.*?)\s*$"#)
        var numbered: [Int: String] = [:]
        for row in rows {
            let range = NSRange(row.startIndex..<row.endIndex, in: row)
            guard let match = regex?.firstMatch(in: row, range: range),
                  let numberRange = Range(match.range(at: 1), in: row),
                  let bodyRange = Range(match.range(at: 2), in: row),
                  let number = Int(row[numberRange]), number >= 1, number <= expected else { continue }
            numbered[number - 1] = String(row[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if numbered.count == expected { return (0..<expected).map { numbered[$0] ?? "" } }
        if rows.count == expected { return rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        return []
    }
}
#else
@objc(SGRLyricsTranslator)
public final class SGRLyricsTranslator: NSObject {
    @objc public class func isAvailable() -> Bool { false }
    @objc(translateLines:targetLanguage:completion:)
    public class func translateLines(_ lines: [String], targetLanguage: String,
                                     completion: @escaping ([String]?, NSError?) -> Void) {
        completion(nil, NSError(domain: "SGRLyricsTranslator", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Foundation Models is unavailable in this SDK"]))
    }
}
#endif
