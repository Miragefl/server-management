import Foundation

/// 服务端口（带可选描述）
struct ServicePort: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var port: Int
    /// 端口描述（非必填，如「HTTP API」「JMX」）
    var remark: String = ""

    init(port: Int, remark: String = "") {
        self.port = port
        self.remark = remark
    }
}

/// 部署在服务器上的服务实体（独立实体，与服务器通过 Deployment 多对多关联）
struct Service: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// 所属环境列表（sit / uat / prod / ...），一个服务可属于多个环境；存字符串以兼容自由输入
    var envs: [String]
    /// 开放端口列表（每个端口可带可选描述）
    var ports: [ServicePort]
    /// 安装方式：docker / rpm / tar / brew / ...
    var installMethod: String = ""
    /// 账号凭据列表（可多条，如管理后台账号）
    var credentials: [Credential] = []
    var remark: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// 常见环境，供 UI 快捷选择
    /// - Deprecated: 已由 Store.envDefinitions 字典管理，仅保留兼容
    @available(*, deprecated)
    static let commonEnvs = ["sit", "uat", "prod"]
    /// 常见安装方式，供 UI 快捷选择
    static let commonInstallMethods = ["docker", "rpm", "tar", "brew", "binary", "源码编译"]

    init(name: String, envs: [String], ports: [ServicePort], installMethod: String = "", remark: String = "", credentials: [Credential] = []) {
        self.name = name
        self.envs = envs
        self.ports = ports
        self.installMethod = installMethod
        self.credentials = credentials
        self.remark = remark
    }

    /// 所有端口均合法（1-65535）；空列表视为有效
    var isValidPorts: Bool {
        ports.allSatisfy { (1...65535).contains($0.port) }
    }

    /// 便捷展示：端口描述串（如 "9092" / "9092 · HTTP API"）
    var portsSummary: String {
        ports.map { p in
            p.remark.isEmpty ? String(p.port) : "\(p.port) · \(p.remark)"
        }.joined(separator: "、")
    }

    // MARK: - Codable（兼容旧版数据：env 单值 / port 单值 / serverID 从属 / groupID 组）

    private enum CodingKeys: String, CodingKey {
        case id, name, envs, ports, installMethod, credentials, remark, createdAt, updatedAt
        case legacyEnv = "env"
        case legacyPort = "port"
        case legacyServerID = "serverID"
        case legacyGroupID = "groupID"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        // 优先读新版 envs 数组；旧数据为单值字符串且 key 名是 env
        if let array = try c.decodeIfPresent([String].self, forKey: .envs) {
            envs = array
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .legacyEnv) {
            envs = [legacy]
        } else {
            envs = []
        }
        // 优先读新版 ports 数组；旧数据为单值 port
        if let array = try c.decodeIfPresent([ServicePort].self, forKey: .ports) {
            ports = array
        } else if let legacyPort = try c.decodeIfPresent(Int.self, forKey: .legacyPort) {
            ports = legacyPort > 0 ? [ServicePort(port: legacyPort)] : []
        } else {
            ports = []
        }
        installMethod = try c.decodeIfPresent(String.self, forKey: .installMethod) ?? ""
        credentials = try c.decodeIfPresent([Credential].self, forKey: .credentials) ?? []
        remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(envs, forKey: .envs)
        try c.encode(ports, forKey: .ports)
        try c.encode(installMethod, forKey: .installMethod)
        try c.encode(credentials, forKey: .credentials)
        try c.encode(remark, forKey: .remark)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// 旧格式服务记录（从属于服务器），仅用于数据迁移解码
struct LegacyServiceRecord: Codable {
    var id: UUID?
    var name: String
    var envs: [String]?
    var env: String?
    var ports: [ServicePort]?
    var port: Int?
    var installMethod: String?
    var credentials: [Credential]?
    var remark: String?
    var createdAt: Date?
    var updatedAt: Date?
    var serverID: UUID?
    var groupID: UUID?
}

extension Service {
    /// 由旧记录转换（serverID/groupID 交由 Store 迁移逻辑处理）
    init(legacy: LegacyServiceRecord) {
        let migratedPorts: [ServicePort]
        if let ports = legacy.ports {
            migratedPorts = ports
        } else if let port = legacy.port, port > 0 {
            migratedPorts = [ServicePort(port: port)]
        } else {
            migratedPorts = []
        }
        self.init(
            name: legacy.name,
            envs: legacy.envs ?? (legacy.env.map { [$0] } ?? []),
            ports: migratedPorts,
            installMethod: legacy.installMethod ?? "",
            remark: legacy.remark ?? "",
            credentials: legacy.credentials ?? []
        )
        if let id = legacy.id { self.id = id }
        if let createdAt = legacy.createdAt { self.createdAt = createdAt }
        if let updatedAt = legacy.updatedAt { self.updatedAt = updatedAt }
    }
}
