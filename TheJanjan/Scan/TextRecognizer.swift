import Foundation
import UIKit
import Vision

/// 사진에서 글자를 읽는다. 전부 기기 안에서 끝난다 —
/// 사진도 인식 결과도 네트워크로 나가지 않고, 사진은 아예 저장하지 않는다.
enum TextRecognizer {

    /// 인식된 줄들. 못 읽으면 빈 배열이고 던지지 않는다 —
    /// 스캔이 실패해도 사용자는 직접 입력으로 계속 갈 수 있어야 한다.
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = cgOrientation(from: image.imageOrientation)

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // 약 이름은 사전에 없는 말이라 언어 교정이 오히려 글자를 바꿔 놓는다.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ko-KR", "en-US"]

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string
            }
        }.value
    }

    /// 카메라로 찍은 사진은 대개 세워서 들고 찍어 `.right` 로 온다.
    /// 이걸 넘겨주지 않으면 Vision 이 옆으로 누운 글자를 읽으려다 다 놓친다.
    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
