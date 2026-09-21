import CoreImage
import Foundation
import UIKit
import Vision

/// Text recognition with Vision. Runs entirely on device and needs no
/// network, which is what makes camera translation work on a plane.
struct OCRService: Sendable {

    struct Block: Identifiable, Sendable {
        let id = UUID()
        let text: String
        /// Normalised Vision coordinates (origin bottom-left).
        let boundingBox: CGRect
        let confidence: Float
    }

    /// Recognise text in an image, optionally hinting at the language to
    /// improve accuracy for CJK and other non-Latin scripts.
    func recognise(in image: UIImage, languageHint: Locale.Language?) async throws -> [Block] {
        guard let cgImage = image.cgImage else { return [] }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let languageHint {
            let supported = await (try? RecognizeTextRequest.supportedRecognitionLanguages()) ?? []
            if supported.contains(languageHint) {
                request.recognitionLanguages = [languageHint]
            }
        }

        let observations = try await request.perform(on: cgImage, orientation: image.cgImagePropertyOrientation)

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox.cgRect
            return Block(text: candidate.string, boundingBox: box, confidence: candidate.confidence)
        }
    }

    /// Join recognised blocks into reading order, so the translator sees
    /// sentences rather than isolated fragments.
    func joinIntoParagraphs(_ blocks: [Block]) -> String {
        blocks
            .sorted { lhs, rhs in
                // Vision's y origin is bottom-left, so larger y is higher up.
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .map(\.text)
            .joined(separator: "\n")
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
