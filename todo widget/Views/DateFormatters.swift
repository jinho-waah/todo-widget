import Foundation

// 캐싱된 DateFormatter 풀.
// 매 row render 마다 `DateFormatter()` 를 새로 만드는 비용 (특히 Calendar /
// Locale 초기화) 을 제거하기 위해 4 가지 조합을 static let 으로 공유한다.

@MainActor
enum DateFormatters {
    /// 같은 해, 한국어 — "M월 d일 (E)"
    static let koCurrentYear: DateFormatter = make(format: "M월 d일 (E)", locale: "ko")
    /// 같은 해, 영어 — "MMM d (EEE)"
    static let enCurrentYear: DateFormatter = make(format: "MMM d (EEE)", locale: "en")
    /// 다른 해, 한국어 — "yyyy년 M월 d일"
    static let koOtherYear: DateFormatter = make(format: "yyyy년 M월 d일", locale: "ko")
    /// 다른 해, 영어 — "MMM d, yyyy"
    static let enOtherYear: DateFormatter = make(format: "MMM d, yyyy", locale: "en")

    static func formatter(isKo: Bool, sameYear: Bool) -> DateFormatter {
        switch (isKo, sameYear) {
        case (true,  true):  return koCurrentYear
        case (true,  false): return koOtherYear
        case (false, true):  return enCurrentYear
        case (false, false): return enOtherYear
        }
    }

    private static func make(format: String, locale: String) -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: locale)
        df.dateFormat = format
        return df
    }
}
