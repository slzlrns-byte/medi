import Foundation

/// 정신과에서 흔한 성분명의 한글 ↔ 영문 표기.
///
/// 약 이름은 사용자가 적는 데이터라 앱이 번역할 수 없다. 다만 성분명은
/// 국제 일반명(INN)의 음차라서 표기 대응이 기계적이다 - "로라제팜" 은
/// 어느 언어에서도 lorazepam 이다. 그래서 **저장된 이름이 이 표의 표기와
/// 정확히 일치할 때만** 다른 언어의 표기로 바꿔 보여 준다. 조금이라도
/// 다르게 적은 이름(상품명·별명·용량 붙임)은 사용자의 글자 그대로 둔다 -
/// 사용자가 쓴 말을 앱이 고쳐 쓰지 않는다.
///
/// 여기는 **이름의 표기만** 있다. 효능·용량·주의사항 같은 약 정보는
/// 싣지 않는다(2026-08-26 결정: 약 정보는 담당의에게 들은 몇 줄로 대신한다).
public enum DrugNames {

    /// (한글 표기, 영문 표기). 영문은 소문자 비교 후 첫 글자만 올려 보여 준다.
    static let pairs: [(ko: String, en: String)] = [
        // 항우울제
        ("에스시탈로프람", "Escitalopram"),
        ("시탈로프람", "Citalopram"),
        ("설트랄린", "Sertraline"),
        ("세르트랄린", "Sertraline"),
        ("플루옥세틴", "Fluoxetine"),
        ("파록세틴", "Paroxetine"),
        ("플루복사민", "Fluvoxamine"),
        ("벤라팍신", "Venlafaxine"),
        ("데스벤라팍신", "Desvenlafaxine"),
        ("둘록세틴", "Duloxetine"),
        ("미르타자핀", "Mirtazapine"),
        ("부프로피온", "Bupropion"),
        ("트라조돈", "Trazodone"),
        ("보티옥세틴", "Vortioxetine"),
        ("티아넵틴", "Tianeptine"),
        ("아미트리프틸린", "Amitriptyline"),
        ("노르트립틸린", "Nortriptyline"),
        ("이미프라민", "Imipramine"),
        ("클로미프라민", "Clomipramine"),
        // 기분조절제
        ("리튬", "Lithium"),
        ("탄산리튬", "Lithium carbonate"),
        ("라모트리진", "Lamotrigine"),
        ("발프로산", "Valproate"),
        ("발프로에이트", "Valproate"),
        ("디발프로엑스", "Divalproex"),
        ("카르바마제핀", "Carbamazepine"),
        ("옥스카르바제핀", "Oxcarbazepine"),
        ("토피라메이트", "Topiramate"),
        // 항정신병약
        ("쿠에티아핀", "Quetiapine"),
        ("퀘티아핀", "Quetiapine"),
        ("아리피프라졸", "Aripiprazole"),
        ("올란자핀", "Olanzapine"),
        ("리스페리돈", "Risperidone"),
        ("팔리페리돈", "Paliperidone"),
        ("아미설프리드", "Amisulpride"),
        ("지프라시돈", "Ziprasidone"),
        ("루라시돈", "Lurasidone"),
        ("클로자핀", "Clozapine"),
        ("블로난세린", "Blonanserin"),
        ("할로페리돌", "Haloperidol"),
        // 항불안제 · 수면
        ("로라제팜", "Lorazepam"),
        ("알프라졸람", "Alprazolam"),
        ("클로나제팜", "Clonazepam"),
        ("디아제팜", "Diazepam"),
        ("브로마제팜", "Bromazepam"),
        ("에티졸람", "Etizolam"),
        ("부스피론", "Buspirone"),
        ("졸피뎀", "Zolpidem"),
        ("트리아졸람", "Triazolam"),
        ("멜라토닌", "Melatonin"),
        ("독세핀", "Doxepin"),
        ("하이드록시진", "Hydroxyzine"),
        ("히드록시진", "Hydroxyzine"),
        // ADHD · 기타
        ("메틸페니데이트", "Methylphenidate"),
        ("아토목세틴", "Atomoxetine"),
        ("프로프라놀롤", "Propranolol"),
        ("벤즈트로핀", "Benztropine"),
        ("프로시클리딘", "Procyclidine"),
        ("가바펜틴", "Gabapentin"),
        ("프레가발린", "Pregabalin"),
        ("날트렉손", "Naltrexone"),
        ("아캄프로세이트", "Acamprosate")
    ]

    static let koToEn: [String: String] = Dictionary(
        pairs.map { ($0.ko, $0.en) },
        uniquingKeysWith: { first, _ in first }
    )

    static let enToKo: [String: String] = Dictionary(
        pairs.map { ($0.en.lowercased(), $0.ko) },
        uniquingKeysWith: { first, _ in first }
    )

    /// 이 이름을 `language` 표기로. 표에 없으면 적힌 그대로 돌려준다.
    public static func display(_ name: String, in language: JanjanLanguage) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch language {
        case .english:
            return koToEn[trimmed] ?? name
        case .korean:
            return enToKo[trimmed.lowercased()] ?? name
        }
    }
}

public extension Medication {

    /// 표시용 이름. 성분명 표에 있는 이름만 언어를 따라가고, 그 밖의 이름은
    /// 사용자가 적은 그대로다. 저장된 값은 바뀌지 않는다 - 표시만 바꾼다.
    func localizedName(_ language: JanjanLanguage) -> String {
        DrugNames.display(name, in: language)
    }

    /// "Quetiapine 25mg" 처럼 표시용 이름과 용량을 합친 한 줄.
    func localizedDisplayTitle(_ language: JanjanLanguage) -> String {
        let localized = localizedName(language)
        return strengthText.isEmpty ? localized : "\(localized) \(strengthText)"
    }
}
