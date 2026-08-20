import Foundation
import OSLog
import UIKit
import JanjanCore

/// 4주 요약을 A4 한 장(넘치면 여러 장)으로 그려 파일로 낸다.
///
/// 무엇을 적을지는 `ReportComposer` 가 이미 정해 두었다. 여기서는 종이에 앉히기만 한다.
/// 파일은 임시 폴더에 만들고, 사용자가 공유 시트에서 보내지 않으면 기기 밖으로 나가지 않는다.
@MainActor
enum ReportPDF {

    private static let logger = Logger(subsystem: Janjan.appBundleID, category: "report-pdf")

    /// A4 72dpi.
    private static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48
    /// 면책 한 줄이 앉을 자리. 모든 쪽 아래에 같은 문장이 들어간다.
    private static let footerHeight: CGFloat = 44

    /// - Returns: 만들어진 PDF 파일 주소. 실패하면 nil.
    static func write(_ content: ReportContent) -> URL? {
        // 이름에 이미 .pdf 가 붙어 있어 UTType 오버로드를 쓰지 않는다
        // (그쪽을 쓰면 UniformTypeIdentifiers 를 더 끌어와야 한다).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: content))

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        do {
            try renderer.writePDF(to: url) { context in
                var cursor = margin
                var pageNumber = 0

                func newPage() {
                    context.beginPage()
                    pageNumber += 1
                    cursor = margin
                    drawFooter(content.disclaimerKo, page: pageNumber)
                }

                /// 남은 자리가 모자라면 쪽을 넘긴다.
                func room(for height: CGFloat) {
                    if pageNumber == 0 || cursor + height > pageSize.height - margin - footerHeight {
                        newPage()
                    }
                }

                let title = attributed(content.titleKo, style: .title)
                room(for: height(of: title) + 6)
                cursor += draw(title, at: cursor) + 6

                let period = attributed(content.periodKo, style: .caption)
                room(for: height(of: period) + 20)
                cursor += draw(period, at: cursor) + 20

                for line in content.lines {
                    let text = attributed(line.text, style: style(for: line.style))
                    let spacing = (line.style == .heading) ? 14 : CGFloat(6)
                    room(for: height(of: text) + spacing)
                    if line.style == .heading, cursor > margin { cursor += 8 }
                    cursor += draw(text, at: cursor) + spacing
                }
            }
            return url
        } catch {
            logger.error("PDF 를 쓰지 못했습니다: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - 그리기

    private enum TextStyle {
        case title
        case heading
        case body
        case caption
    }

    private static func style(for lineStyle: ReportContent.Line.Style) -> TextStyle {
        switch lineStyle {
        case .heading: return .heading
        case .body: return .body
        case .caption: return .caption
        }
    }

    /// 번들 서체가 없으면 시스템 서체로 떨어진다. 화면 규칙과 같다 —
    /// 덜 예쁜 편이 글자가 안 보이는 것보다 낫다.
    private static func font(_ style: TextStyle) -> UIFont {
        switch style {
        case .title:
            return UIFont(name: JanjanFontName.displayLight, size: 26)
                ?? .systemFont(ofSize: 26, weight: .light)
        case .heading:
            return UIFont(name: JanjanFontName.bodySemiBold, size: 14)
                ?? .systemFont(ofSize: 14, weight: .semibold)
        case .body:
            return UIFont(name: JanjanFontName.bodyRegular, size: 13)
                ?? .systemFont(ofSize: 13, weight: .regular)
        case .caption:
            return UIFont(name: JanjanFontName.bodyLight, size: 11)
                ?? .systemFont(ofSize: 11, weight: .light)
        }
    }

    private static func color(_ style: TextStyle) -> UIColor {
        switch style {
        case .title, .heading, .body: return UIColor(white: 0.11, alpha: 1)
        case .caption: return UIColor(white: 0.45, alpha: 1)
        }
    }

    private static func attributed(_ text: String, style: TextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font(style),
                .foregroundColor: color(style),
                .paragraphStyle: paragraph
            ]
        )
    }

    private static var textWidth: CGFloat { pageSize.width - margin * 2 }

    private static func height(of text: NSAttributedString) -> CGFloat {
        let bounds = text.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }

    @discardableResult
    private static func draw(_ text: NSAttributedString, at y: CGFloat) -> CGFloat {
        let drawn = height(of: text)
        text.draw(with: CGRect(x: margin, y: y, width: textWidth, height: drawn),
                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                  context: nil)
        return drawn
    }

    /// 면책은 어느 쪽을 뜯어 가도 함께 가야 하므로 쪽마다 넣는다(심사 체크리스트 1.2).
    private static func drawFooter(_ disclaimer: String, page: Int) {
        let text = attributed(disclaimer, style: .caption)
        let y = pageSize.height - margin - height(of: text)
        draw(text, at: y)

        let number = attributed("\(page)", style: .caption)
        number.draw(
            with: CGRect(
                x: margin,
                y: y - 16,
                width: textWidth,
                height: 14
            ),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }

    /// "더잔잔-4주요약-2026-08-17.pdf"
    private static func fileName(for content: ReportContent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(Janjan.appNameKo)-4주요약-\(formatter.string(from: Date())).pdf"
    }
}
