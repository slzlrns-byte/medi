import Foundation

/// 약봉투에서 읽어 낸 글자 뭉치에서 "약으로 보이는 줄" 을 골라 낸다.
///
/// 글자 인식(Vision)은 앱이 하고, 그 결과를 사람이 확인할 목록으로 접는 일은 여기서 한다.
/// 순수 함수라 실제 봉투 문구를 테스트에 그대로 넣어 두고 회귀를 잡을 수 있다.
///
/// **추측한 것은 추측이라고 말한다.** 여기서 나온 값은 곧바로 저장되지 않고
/// 반드시 사용자가 보고 고치는 화면을 한 번 거친다(설계 03절).
public enum PharmacyLabelParser {

    /// 봉투에서 건져 낸 약 하나의 후보.
    public struct Candidate: Identifiable, Hashable, Sendable {

        public let id: UUID
        /// 약 이름으로 보이는 부분. "쿠에티아핀정"
        public let name: String
        /// 용량으로 보이는 부분. "25mg". 못 찾으면 빈 문자열.
        public let strengthText: String
        /// 인식된 원래 줄. 확인 화면에서 그대로 보여 준다.
        public let sourceLine: String

        public init(id: UUID = UUID(), name: String, strengthText: String, sourceLine: String) {
            self.id = id
            self.name = name
            self.strengthText = strengthText
            self.sourceLine = sourceLine
        }
    }

    /// 약 이름 줄에 붙어 다니지만 약과는 상관없는 말들.
    /// 이 말이 들어 있으면 후보에서 뺀다.
    static let noiseKeywords: [String] = [
        "조제", "환자", "처방", "약국", "병원", "의원", "医", "발행", "교부",
        "용법", "용량은", "복용법", "보험", "청구", "전화", "주소", "사업자",
        "일분", "일치", "총량", "投薬", "성명", "생년", "면허", "약사", "의사",
        // 설명문에도 용량이 적힌다. "1회 1정에 500mg 함유" 같은 줄은 약 이름 줄이 아니다.
        "함유", "성분명", "첨가"
    ]

    /// 용량 표기. "25mg", "0.5 mg", "12.5밀리그램", "10㎎", "5mcg", "1g", "100IU".
    /// 단위 뒤에 `\b` 를 쓰면 안 된다. `㎎` 은 글자가 아니라 기호로 분류돼서
    /// 뒤에 공백이 와도 단어 경계가 서지 않고, "10㎎ 1정" 을 통째로 놓친다.
    /// 로마자만 이어지지 않으면 되므로 부정 전방탐색으로 막는다.
    static let strengthPattern =
        #"(\d+(?:[.,]\d+)?)\s*(mg|밀리그램|㎎|mcg|㎍|μg|ug|g|그램|ml|㎖|밀리리터|IU|iu)(?![A-Za-z])"#

    /// 인식된 줄들에서 약 후보를 골라 낸다. 순서는 봉투에 적힌 순서를 지킨다.
    public static func candidates(from lines: [String]) -> [Candidate] {

        var results: [Candidate] = []
        var seen: Set<String> = []

        for raw in lines {
            let line = normalize(raw)
            guard isPlausibleMedicationLine(line) else { continue }

            // 용량을 못 찾는 봉투도 있다. 그때는 빈 문자열로 두고 사용자가 채운다.
            // 지역 이름이 static 메서드 이름을 가리지 않도록 타입 이름으로 부른다
            // (InventoryCalculator 에서 같은 이유로 정해 둔 규칙).
            let strength = PharmacyLabelParser.strength(in: line) ?? ""
            let name = PharmacyLabelParser.medicationName(in: line)
            guard PharmacyLabelParser.isPlausibleName(name) else { continue }

            // 같은 약이 봉투에 여러 번 적히는 일이 흔하다(요일별 칸 등).
            let key = "\(name)|\(strength)"
            guard seen.insert(key).inserted else { continue }

            results.append(
                Candidate(name: name, strengthText: strength, sourceLine: line)
            )
        }
        return results
    }

    // MARK: - 조각

    /// 인식기가 흘린 겹공백·전각 문자를 정리한다. 글자를 지우지는 않는다.
    static func normalize(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "：", with: ":")
        return unified
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 약 이름 줄일 법한가.
    ///
    /// 걸러 내는 쪽으로 기운다. 후보가 하나 빠지면 사용자가 직접 적으면 되지만,
    /// "조제일자 2026-08-17" 이 약 이름으로 올라오면 확인 화면이 못 믿을 것이 된다.
    static func isPlausibleMedicationLine(_ line: String) -> Bool {
        guard line.count >= 3, line.count <= 60 else { return false }

        // 한글이나 로마자가 있어야 이름이다. 숫자·기호만 있는 줄은 뺀다.
        guard line.unicodeScalars.contains(where: isNameScalar) else { return false }

        let lowered = line.lowercased()
        if noiseKeywords.contains(where: { lowered.contains($0.lowercased()) }) { return false }

        // 날짜처럼 생긴 줄(2026-08-17, 2026.08.17)은 약이 아니다.
        if line.range(of: #"\d{4}[-./]\d{1,2}[-./]\d{1,2}"#, options: .regularExpression) != nil {
            return false
        }

        // 용량이 적혀 있으면 약일 가능성이 크다.
        if strength(in: line) != nil { return true }

        // 용량이 없어도 제형 이름이 붙어 있으면 약으로 본다.
        let forms = ["정", "캡슐", "서방정", "산", "시럽", "패치", "주사", "액"]
        return forms.contains { lowered.hasSuffix($0) }
    }

    /// 떼어 내고 남은 것이 이름 같은가.
    ///
    /// 용량과 용법 숫자를 걷어 내면 설명문에서는 조사 부스러기만 남는다.
    /// 그런 줄을 확인 화면에 올리면 사용자가 목록을 못 믿게 되고,
    /// 그러면 진짜 약 이름까지 하나하나 다시 읽어 봐야 한다.
    static func isPlausibleName(_ name: String) -> Bool {
        guard name.count >= 2 else { return false }
        guard name.unicodeScalars.contains(where: isNameScalar) else { return false }

        // 조사로 시작하는 이름은 없다. 문장 가운데를 잘라 낸 부스러기다.
        let particles = ["에 ", "을 ", "를 ", "이 ", "가 ", "은 ", "는 ", "의 ", "와 ", "과 "]
        if particles.contains(where: { name.hasPrefix($0) }) { return false }

        // 한글·로마자를 뺀 나머지가 절반을 넘으면 이름이 아니라 부스러기다.
        let letters = name.unicodeScalars.filter(isNameScalar).count
        return letters * 2 >= name.unicodeScalars.count
    }

    private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)    // 한글 음절
            || (0x1100...0x11FF).contains(scalar.value) // 한글 자모
            || (0x41...0x5A).contains(scalar.value)     // A-Z
            || (0x61...0x7A).contains(scalar.value)     // a-z
    }

    /// 줄 안의 용량 표기. "25mg"
    static func strength(in line: String) -> String? {
        guard let range = line.range(of: strengthPattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(line[range])
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }

    /// 용량과 꼬리 숫자를 떼어 낸 이름.
    static func medicationName(in line: String) -> String {
        var name = line

        if let range = name.range(of: strengthPattern, options: [.regularExpression, .caseInsensitive]) {
            name = name.replacingCharacters(in: range, with: " ")
        }

        // "쿠에티아핀정 1정 3회" 처럼 붙는 용법 숫자를 떼어 낸다.
        name = name.replacingOccurrences(
            of: #"\s*\d+(?:[.,]\d+)?\s*(정|캡슐|포|회|일|매|앰플|㎖|ml)(?![A-Za-z])"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        // 괄호 안의 성분명·제조사는 이름에서 뺀다. 사용자가 필요하면 직접 적는다.
        name = name.replacingOccurrences(
            of: #"[\(（\[][^\)）\]]*[\)）\]]"#,
            with: " ",
            options: .regularExpression
        )

        // "쿠에티아핀 1정 아침 식후" 처럼 붙는 복용 시점은 이름이 아니다.
        // 이 낱말들로 시작하는 약 이름은 없으므로 통째로 떼어도 안전하다.
        name = name.replacingOccurrences(
            of: #"\s*(취침\s*전|자기\s*전|아침|점심|저녁|취침|식후|식전|식간|하루|매일)\s*"#,
            with: " ",
            options: .regularExpression
        )

        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—:,.·[]()"))
        return normalize(name)
    }
}
