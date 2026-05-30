import Foundation

// 사용자가 시스템 설정에서 지정한 1순위 언어.
// `Locale.current` / `.autoupdatingCurrent` 는 "앱이 지원한다고 선언한 언어와의 교집합"이라
// 이 앱처럼 .lproj/.xcstrings 가 없으면 시스템이 한국어여도 영어로 떨어진다.
// 날짜 표시만큼은 번들 localization 상태와 무관하게 사용자 언어를 따라야 하므로
// `preferredLanguages.first` 를 직접 사용한다.
extension Locale {
    static var userPreferred: Locale {
        if let code = Locale.preferredLanguages.first {
            return Locale(identifier: code)
        }
        return .autoupdatingCurrent
    }
}

// 캐싱된 DateFormatter 풀.
// 매 row render 마다 `DateFormatter()` 를 새로 만드는 비용 (특히 Calendar /
// Locale 초기화) 을 제거하기 위해 같은 해 / 다른 해 두 가지를 static let 으로 공유한다.
//
// 포맷은 템플릿 기반(`setLocalizedDateFormatFromTemplate`)이라
// 사용자 locale 에 따라 요일·월·일의 순서와 구분자가 자동으로 결정된다.
// (예: ko → "5월 12일 (화)", en → "May 12 (Tue)", ja → "5月12日(火)")

@MainActor
enum DateFormatters {
    /// 같은 해 — 월/일/요일 (locale 이 순서·구분자를 결정)
    static let currentYear: DateFormatter = make(template: "MMMdEEE")
    /// 다른 해 — 연/월/일
    static let otherYear: DateFormatter = make(template: "yMMMd")

    static func formatter(sameYear: Bool) -> DateFormatter {
        sameYear ? currentYear : otherYear
    }

    private static func make(template: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = .userPreferred
        df.setLocalizedDateFormatFromTemplate(template)
        return df
    }
}
