import Foundation

/// 服务器实体
struct Server: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var hostname: String
    /// IP 列表（支持多 IP；第一个视为主 IP）
    var ips: [String]
    var os: String = ""
    /// 分组名（如「测试 / 生产」，空 = 未分组；字典见 GroupDefinition）
    var group: String = ""
    /// CPU 信息（自由输入，如 "8C Intel Xeon"）
    var cpu: String = ""
    /// 内存信息（自由输入，如 "32G"）
    var memory: String = ""
    /// 硬盘信息（自由输入，如 "500G SSD + 2T HDD"）
    var disk: String = ""
    /// 账号凭据列表（可多条）
    var credentials: [Credential] = []
    var remark: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// 常用操作系统模板，供表单快捷选择
    /// - Deprecated: 已由 Store.osDefinitions 字典管理，仅保留兼容
    @available(*, deprecated)
    static let commonOSs = [
        "Windows 10", "Windows Server 2019",
        "Ubuntu 22.04", "Ubuntu 24.04", "Ubuntu 26.04",
        "CentOS 7.9",
        "Rocky Linux 9", "Rocky Linux 10",
    ]

    init(
        hostname: String,
        ips: [String],
        os: String = "",
        group: String = "",
        cpu: String = "",
        memory: String = "",
        disk: String = "",
        remark: String = ""
    ) {
        self.hostname = hostname
        self.ips = ips
        self.os = os
        self.group = group
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.remark = remark
    }

    /// 便捷展示：主 IP 或 "—"
    var primaryIP: String {
        ips.first ?? "—"
    }

    /// 便捷展示：全部 IP 逗号串
    var ipsSummary: String {
        ips.joined(separator: ", ")
    }

    // MARK: - Codable（缺省字段容错 + 旧版单 ip 迁移）

    private enum CodingKeys: String, CodingKey {
        case id, hostname, ips, os, group, cpu, memory, disk, credentials, remark, createdAt, updatedAt
        case legacyIP = "ip"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hostname = try c.decode(String.self, forKey: .hostname)
        if let array = try c.decodeIfPresent([String].self, forKey: .ips) {
            ips = array
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .legacyIP) {
            ips = legacy.isEmpty ? [] : [legacy]
        } else {
            ips = []
        }
        os = try c.decodeIfPresent(String.self, forKey: .os) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        cpu = try c.decodeIfPresent(String.self, forKey: .cpu) ?? ""
        memory = try c.decodeIfPresent(String.self, forKey: .memory) ?? ""
        disk = try c.decodeIfPresent(String.self, forKey: .disk) ?? ""
        credentials = try c.decodeIfPresent([Credential].self, forKey: .credentials) ?? []
        remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(ips, forKey: .ips)
        try c.encode(os, forKey: .os)
        try c.encode(group, forKey: .group)
        try c.encode(cpu, forKey: .cpu)
        try c.encode(memory, forKey: .memory)
        try c.encode(disk, forKey: .disk)
        try c.encode(credentials, forKey: .credentials)
        try c.encode(remark, forKey: .remark)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
