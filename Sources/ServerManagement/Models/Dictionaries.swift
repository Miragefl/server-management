import Foundation
import SwiftUI
import AppKit

/// 环境字典项：名称 + 可选自定义颜色
struct EnvDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// 环境名（唯一，建议小写；服务 envs 中存的就是这个名字）
    var name: String
    /// 自定义颜色 hex（如 "#FF5A5A"）；nil 走默认规则
    var colorHex: String?

    init(name: String, colorHex: String? = nil) {
        self.name = name
        self.colorHex = colorHex
    }
}

/// 操作系统字典项
struct OSDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// 系统名（唯一）
    var name: String

    init(name: String) {
        self.name = name
    }
}

// MARK: - 内置默认字典

extension EnvDefinition {
    /// 默认环境字典（首启/旧数据缺省时初始化）
    static let defaults: [EnvDefinition] = [
        EnvDefinition(name: "sit"),
        EnvDefinition(name: "uat"),
        EnvDefinition(name: "prod"),
    ]
}

extension OSDefinition {
    /// 默认操作系统字典
    static let defaults: [OSDefinition] = [
        "Windows 10", "Windows Server 2019",
        "Ubuntu 22.04", "Ubuntu 24.04", "Ubuntu 26.04",
        "CentOS 7.9",
        "Rocky Linux 9", "Rocky Linux 10",
    ].map { OSDefinition(name: $0) }
}

// MARK: - 颜色转换

extension EnvDefinition {
    /// 解析 hex 为 Color；非法/缺失返回 nil
    var color: Color? {
        guard let colorHex else { return nil }
        return Color(hex: colorHex)
    }
}

extension Color {
    /// hex（"#RRGGBB" / "#RRGGBBAA"）转 Color；非法返回 nil
    init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        // 每两位一个字节，逐字节解析避免移位歧义
        guard value.count == 6 || value.count == 8 else { return nil }
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard next <= value.endIndex,
                  let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        let r = Double(bytes[0]) / 255
        let g = Double(bytes[1]) / 255
        let b = Double(bytes[2]) / 255
        let a = bytes.count == 4 ? Double(bytes[3]) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Color 转 "#RRGGBB" hex（经 sRGB 分量提取，规避 AppKit 色彩空间偏移）
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ns = NSColor(self)
        // 明确转 sRGB 再取分量
        guard let srgb = ns.usingColorSpace(.sRGB) else { return nil }
        _ = srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    /// 环境默认配色规则（无自定义色时回退）：prod 红 / uat 橙 / sit 蓝 / 其他灰
    static func defaultEnvColor(_ env: String) -> Color {
        switch env.lowercased() {
        case "prod": .red
        case "uat": .orange
        case "sit": .blue
        default: .gray
        }
    }
}
