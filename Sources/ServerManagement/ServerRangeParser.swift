import Foundation

/// 区间表达式解析器：把 `前缀起始数~结束数` / 单值 的逗号分隔列表展开为有序值数组。
/// 例：`yd-vm121~125,yd-vm131` → ["yd-vm121", …, "yd-vm125", "yd-vm131"]
enum ServerRangeParser {
    /// 展开结果：成功值按输入段顺序排列；失败段原样返回供 UI 明示
    struct Result: Equatable {
        var values: [String]
        var failedSegments: [String]
    }

    /// 单段上限，防误输超大区间
    static let maxPerSegment = 500

    static func expand(_ text: String) -> Result {
        var values: [String] = []
        var failed: [String] = []

        // 统一分隔符：全角逗号、分号 → 英文逗号；全角波浪线 → 半角（placeholder 示例用全角避免被渲染成日期范围）
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "〜", with: "~")

        for rawSegment in normalized.split(separator: ",", omittingEmptySubsequences: true) {
            let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { continue }

            if let expanded = expandSegment(segment) {
                values.append(contentsOf: expanded)
            } else {
                failed.append(segment)
            }
        }
        return Result(values: values, failedSegments: failed)
    }

    /// 展开单段：`前缀起始数~结束数` 或 单值；`~` 后必须纯数字且 ≥ 起始数
    private static func expandSegment(_ segment: String) -> [String]? {
        // 无 ~：单值直通（要求非空即合法）
        guard let tilde = segment.lastIndex(of: "~") else {
            return [segment]
        }

        let startPart = String(segment[segment.startIndex..<tilde])
        let endText = String(segment[segment.index(after: tilde)...])

        // 结束侧必须纯数字
        guard let end = Int(endText), !endText.isEmpty else { return nil }

        // 起始侧 = 前缀 + 结尾数字串
        guard let startNumber = startPart.lastNumberRun, let start = Int(startNumber.run) else {
            return nil
        }
        let prefix = String(startPart[startPart.startIndex..<startNumber.range.lowerBound])

        guard end >= start, end - start + 1 <= maxPerSegment else { return nil }

        return (start...end).map { "\(prefix)\($0)" }
    }
}

private extension String {
    /// 结尾的连续数字串及其范围（如 "yd-vm121" → "121"）
    var lastNumberRun: (run: String, range: Range<Index>)? {
        guard let last = lastIndex(where: { $0.isNumber }) else { return nil }
        var lower = last
        while lower > startIndex, self[index(before: lower)].isNumber {
            lower = index(before: lower)
        }
        let range = lower..<index(after: last)
        return (String(self[range]), range)
    }
}
