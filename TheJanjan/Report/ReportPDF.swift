import CoreText
import Foundation
import OSLog
import UIKit
import JanjanCore

/// 4주 요약을 A4 한 장(넘치면 여러 장)으로 그려 파일로 낸다.
///
/// 무엇을 적을지는 `ReportComposer` 가 이미 정해 두었다. 여기서는 종이에 앉히기만 한다.
/// 파일은 임시 폴더에 만들고, 사용자가 공유 시트에서 보내지 않으면 기기 밖으로 나가지 않는다.
///
/// MainActor 로 묶지 않는다. `writePDF` 가 넘겨주는 그리기 클로저는 격리가 없어서,
/// 이 타입이 MainActor 면 클로저 안에서 자기 메서드조차 부를 수 없다.
/// 그릴 때 화면을 건드리지도 않으므로 묶을 이유도 없다.
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

                /// 한 쪽에 실제로 글을 쓸 수 있는 높이.
                let usableHeight = pageSize.height - margin * 2 - footerHeight

                for line in content.lines {
                    let text = attributed(line.text, style: style(for: line.style))
                    let spacing = (line.style == .heading) ? 14 : CGFloat(6)

                    // 한 쪽보다 긴 문단은 쪽을 넘긴다고 잘리지 않는다.
                    // 진료 질문 메모를 줄바꿈 없이 길게 쓰면 여기 걸리는데,
                    // 예전에는 남는 만큼만 그리고 나머지를 조용히 버렸다 —
                    // 의사에게 물어보려던 말이 PDF 에서 사라지는 셈이었다.
                    if height(of: text) > usableHeight {
                        for piece in split(text, into: usableHeight) {
                            room(for: min(height(of: piece), usableHeight))
                            cursor += draw(piece, at: cursor)
                        }
                        cursor += spacing
                        continue
                    }

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

    /// 한 쪽에 안 들어가는 글을 쪽 높이에 맞춰 토막 낸다.
    ///
    /// CoreText 에게 "이 높이에 몇 글자가 들어가느냐" 를 묻고 딱 그만큼씩 떼어 간다.
    /// 글자 수로 어림잡으면 서체와 줄바꿈에 따라 어긋나서 또 잘린다.
    private static func split(
        _ text: NSAttributedString,
        into height: CGFloat
    ) -> [NSAttributedString] {

        let width = pageSize.width - margin * 2
        var pieces: [NSAttributedString] = []
        var start = 0

        while start < text.length {
            let rest = text.attributedSubstring(
                from: NSRange(location: start, length: text.length - start)
            )
            let framesetter = CTFramesetterCreateWithAttributedString(rest)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(0, 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)

            // 한 글자도 못 넣는다면 더 쪼개도 소용이 없다. 남은 것을 통째로 넘긴다.
            guard visible.length > 0 else {
                pieces.append(rest)
                break
            }

            pieces.append(
                text.attributedSubstring(from: NSRange(location: start, length: visible.length))
            )
            start += visible.length
        }

        return pieces
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
        let typeface = font(style)
        let size = Double(typeface.pointSize)
        let role: JanjanTypography.Role
        switch style {
        case .title: role = .display
        case .heading, .body, .caption: role = .body
        }

        let paragraph = NSMutableParagraphStyle()
        // 화면과 같은 규칙을 쓴다. 종이만 행간이 다르면 그것도 어긋남이다.
        paragraph.lineSpacing = CGFloat(JanjanTypography.lineSpacing(forSize: size, role: role))
        paragraph.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: typeface,
                .foregroundColor: color(style),
                .paragraphStyle: paragraph,
                // 자간도 화면과 맞춘다. NSAttributedString 은 pt 단위로 받는다.
                .kern: CGFloat(JanjanTypography.tracking(forSize: size))
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
        return "\(filePrefix)\(formatter.string(from: Date())).pdf"
    }

    /// 내보낸 파일을 알아볼 수 있게 이름 앞을 고정해 둔다. 걷어 낼 때 이걸로 찾는다.
    private static let filePrefix = "\(Janjan.appNameKo)-4주요약-"

    /// 지금까지 내보낸 리포트 PDF 를 지운다.
    ///
    /// 공유 시트를 닫은 뒤와 "모든 데이터 삭제" 에서 부른다.
    /// 이 파일 한 장에 약 이름·복약률·기분·의사에게 물어볼 말이 다 들어 있다.
    /// 임시 폴더는 iOS 가 언젠가는 비우지만 언제인지는 약속돼 있지 않아서,
    /// 그때까지 기기에 남아 있는 것을 그냥 두면 "모두 사라집니다" 가 거짓말이 된다.
    static func removeExportedFiles() {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory

        guard let files = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.lastPathComponent.hasPrefix(filePrefix) {
            try? manager.removeItem(at: file)
        }
    }
}
