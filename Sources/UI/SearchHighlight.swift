import SwiftUI

/// 把搜索命中的关键词在列表标题里标出来。
///
/// 搜索是 Clip 最常用的入口：输入几个字后列表可能只剩几条，但「这条为什么被命中」
/// 并不总是显然——尤其命中位置在标题中段、或者只命中来源应用名时。这里把命中的
/// 片段加深底色，用户扫一眼就知道该按哪一条。
///
/// 只在可见行（`LazyVStack`）里对**已经截断过的标题**调用，单次代价是
/// 「关键词数 × 标题长度」的 `NSString` 定位，远小于一次 SwiftUI 布局。
enum SearchHighlight {
    /// 命中片段的底色。用强调色的低透明度：深色 / 浅色外观下都能保证文字对比度。
    private static let markColor = Color.accentColor.opacity(0.28)

    /// 返回带高亮的富文本；没有命中时退化成普通 `AttributedString`。
    static func attributed(_ text: String, keywords: [String]) -> AttributedString {
        let matched = ranges(in: text, keywords: keywords)
        guard !matched.isEmpty else { return AttributedString(text) }
        // 按片段拼接，而不是把 NSRange 换算成 AttributedString.Index：
        // 文本里可能含 emoji / 组合字素，逐个 Range 转换容易在边界上出错。
        var result = AttributedString()
        var cursor = text.startIndex
        for range in matched {
            result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            var chunk = AttributedString(String(text[range]))
            chunk.backgroundColor = markColor
            result.append(chunk)
            cursor = range.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return result
    }

    /// 所有命中区间，已排序并合并重叠部分。
    private static func ranges(in text: String, keywords: [String]) -> [Range<String.Index>] {
        guard !text.isEmpty, !keywords.isEmpty else { return [] }
        // 用 NSString 定位：`String.range(of:options:)` 的默认选项是全字素簇比较，
        // 比这里的逐码位定位慢，而且要自己处理重叠。
        let source = text as NSString
        guard source.length > 0 else { return [] }
        var found: [Range<String.Index>] = []
        for keyword in keywords where !keyword.isEmpty {
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let match = source.range(
                    of: keyword,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                guard match.location != NSNotFound else { break }
                if let range = Range(match, in: text) {
                    found.append(range)
                }
                let next = match.location + max(match.length, 1)
                searchRange = NSRange(location: next, length: source.length - next)
            }
        }
        guard found.count > 1 else { return found }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in found {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
