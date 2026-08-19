import Testing
import Foundation
@testable import ServerManagement

@Suite("区间表达式解析器")
struct ServerRangeParserTests {
    @Test("基本区间展开：yd-vm121~125")
    func testBasicRange() {
        let r = ServerRangeParser.expand("yd-vm121~125")
        #expect(r.values == ["yd-vm121", "yd-vm122", "yd-vm123", "yd-vm124", "yd-vm125"])
        #expect(r.failedSegments.isEmpty)
    }

    @Test("多段混合：区间 + 单值 + IP 段")
    func testMultipleSegments() {
        let r = ServerRangeParser.expand("yd-vm121~125,yd-vm131~134")
        #expect(r.values.count == 9)
        #expect(r.values.first == "yd-vm121")
        #expect(r.values.last == "yd-vm134")

        let ip = ServerRangeParser.expand("10.137.32.121~125,10.137.32.131~134")
        #expect(ip.values.count == 9)
        #expect(ip.values.first == "10.137.32.121")
        #expect(ip.values.last == "10.137.32.134")

        let mixed = ServerRangeParser.expand("yd-vm100,yd-vm121~122")
        #expect(mixed.values == ["yd-vm100", "yd-vm121", "yd-vm122"])
    }

    @Test("全角逗号/分号分隔与空白容错")
    func testSeparators() {
        let r = ServerRangeParser.expand("yd-vm121~122，yd-vm125；yd-vm130")
        #expect(r.values == ["yd-vm121", "yd-vm122", "yd-vm125", "yd-vm130"])

        let spaced = ServerRangeParser.expand("  yd-vm121 , yd-vm122  ")
        #expect(spaced.values == ["yd-vm121", "yd-vm122"])
    }

    @Test("全角波浪线〜与半角~等价（placeholder 复制容错）")
    func testFullWidthTilde() {
        let r = ServerRangeParser.expand("yd-vm121〜125")
        #expect(r.values == ["yd-vm121", "yd-vm122", "yd-vm123", "yd-vm124", "yd-vm125"])
        #expect(r.failedSegments.isEmpty)
    }

    @Test("非法段进失败列表，不中断其余段")
    func testInvalidSegments() {
        // 结束侧非数字 / 起始侧无数字 / 结束<起始
        let r = ServerRangeParser.expand("yd-vm121~abc,yd-vm~5,yd-vm9~8,host-1~3")
        #expect(r.values == ["host-1", "host-2", "host-3"])
        #expect(r.failedSegments == ["yd-vm121~abc", "yd-vm~5", "yd-vm9~8"])
    }

    @Test("空串与空段：返回空结果不报错")
    func testEmpty() {
        #expect(ServerRangeParser.expand("").values.isEmpty)
        #expect(ServerRangeParser.expand(" , ,，").values.isEmpty)
    }

    @Test("超大区间拒绝：单段超 500")
    func testOversizedRange() {
        let r = ServerRangeParser.expand("vm1~501")
        #expect(r.values.isEmpty)
        #expect(r.failedSegments == ["vm1~501"])

        let ok = ServerRangeParser.expand("vm1~500")
        #expect(ok.values.count == 500)
    }

    @Test("跨位宽递增不抹零")
    func testNoZeroPadding() {
        let r = ServerRangeParser.expand("vm9~11")
        #expect(r.values == ["vm9", "vm10", "vm11"])
    }
}
