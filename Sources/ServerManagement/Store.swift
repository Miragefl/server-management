import Foundation
import SwiftUI

/// 数据仓库：内存 CRUD + JSON 文件持久化
/// 领域模型：Server / Service 独立实体，Deployment 多对多关联
@MainActor
final class Store: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var services: [Service] = []
    @Published private(set) var deployments: [Deployment] = []
    /// 环境字典（候选 + 颜色）
    @Published private(set) var envDefinitions: [EnvDefinition] = EnvDefinition.defaults
    /// 操作系统字典（候选）
    @Published private(set) var osDefinitions: [OSDefinition] = OSDefinition.defaults

    /// 持久化错误，UI 可展示
    @Published private(set) var lastError: String?

    private let fileURL: URL

    /// 默认数据文件：~/Library/Application Support/ServerManagement/data.json
    static func defaultFileURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = dir.appendingPathComponent("ServerManagement", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("data.json")
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // defaultFileURL 理论上只会在磁盘满/权限异常时抛错，降级为临时目录
            self.fileURL = (try? Self.defaultFileURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("ServerManagement-fallback.json")
        }
        load()
    }

    // MARK: - 服务器

    /// 新增或按 id 更新
    func upsertServer(_ server: Server) {
        var toSave = server
        toSave.updatedAt = Date()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = toSave
        } else {
            servers.append(toSave)
        }
        persist()
    }

    /// 删除服务器并级联删除其绑定（服务保留）
    func deleteServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        deployments.removeAll { $0.serverID == server.id }
        persist()
    }

    func server(id: UUID?) -> Server? {
        guard let id else { return nil }
        return servers.first { $0.id == id }
    }

    /// 批量插入服务器：hostname 或 IP 与现存重复的条目跳过
    /// 返回 (实际新增, 因重复跳过)
    @discardableResult
    func addServers(_ candidates: [Server]) -> (added: [Server], skipped: [Server]) {
        let now = Date()
        var added: [Server] = []
        var skipped: [Server] = []

        // 同批次内部也要去重（hostname 唯一；IP 任一命中即视为重复）
        var seenHostnames = Set(servers.map(\.hostname))
        var seenIPs = Set(servers.flatMap(\.ips))

        for var candidate in candidates {
            let ipOverlap = !Set(candidate.ips).isDisjoint(with: seenIPs)
            if seenHostnames.contains(candidate.hostname) || ipOverlap {
                skipped.append(candidate)
                continue
            }
            candidate.createdAt = now
            candidate.updatedAt = now
            servers.append(candidate)
            seenHostnames.insert(candidate.hostname)
            seenIPs.formUnion(candidate.ips)
            added.append(candidate)
        }

        if !added.isEmpty {
            persist()
        }
        return (added, skipped)
    }

    /// 按关键字过滤服务器：空格分隔多个关键字，须全部命中同一载体（AND）。
    /// 载体 = 服务器自身（hostname/ip/os）或其绑定的某个服务（服务名/环境）
    func filteredServers(keyword: String) -> [Server] {
        let queries = keyword
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !queries.isEmpty else { return servers }

        return servers.filter { server in
            // 载体 1：服务器自身字段
            if queries.allSatisfy({ query in
                server.hostname.lowercased().contains(query)
                    || server.ips.contains { $0.lowercased().contains(query) }
                    || server.os.lowercased().contains(query)
            }) {
                return true
            }
            // 载体 2：其绑定的某个服务的全部字段
            let boundServiceIDs = Set(deployments.filter { $0.serverID == server.id }.map(\.serviceID))
            return services.contains { service in
                boundServiceIDs.contains(service.id)
                    && queries.allSatisfy { query in
                        service.name.lowercased().contains(query)
                            || service.envs.contains { $0.lowercased().contains(query) }
                    }
            }
        }
    }

    // MARK: - 服务

    /// 新增或按 id 更新（全局实体，一处编辑处处生效）
    func upsertService(_ service: Service) {
        var toSave = service
        toSave.updatedAt = Date()
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            services[index] = toSave
        } else {
            services.append(toSave)
        }
        persist()
    }

    /// 删除服务并级联删除其绑定（服务器保留）
    func deleteService(_ service: Service) {
        services.removeAll { $0.id == service.id }
        deployments.removeAll { $0.serviceID == service.id }
        persist()
    }

    func service(id: UUID?) -> Service? {
        guard let id else { return nil }
        return services.first { $0.id == id }
    }

    /// 全部出现过的环境值（去重排序，供筛选器）
    var allEnvs: [String] {
        Array(Set(services.flatMap(\.envs))).sorted()
    }

    // MARK: - 绑定

    /// 绑定服务到服务器（幂等：已存在的组合或同批内重复忽略）
    func bind(_ serviceIDs: [UUID], to serverID: UUID) {
        var existing = Set(deployments.filter { $0.serverID == serverID }.map(\.serviceID))
        let knownIDs = Set(services.map(\.id))
        var newDeployments: [Deployment] = []
        for id in serviceIDs where !existing.contains(id) && knownIDs.contains(id) {
            newDeployments.append(Deployment(serverID: serverID, serviceID: id))
            existing.insert(id)
        }
        guard !newDeployments.isEmpty else { return }
        deployments.append(contentsOf: newDeployments)
        touchServer(serverID)
        persist()
    }

    /// 解绑（只删绑定，服务与服务器都保留）
    func unbind(_ binding: Deployment) {
        deployments.removeAll { $0.id == binding.id }
        touchServer(binding.serverID)
        persist()
    }

    /// 某服务器绑定的服务（按环境集合过滤，命中任一选中环境即保留；空集合表示全部）
    func boundServices(of serverID: UUID, envs filters: Set<String> = []) -> [Service] {
        let serviceIDs = Set(deployments.filter { $0.serverID == serverID }.map(\.serviceID))
        return services.filter { service in
            serviceIDs.contains(service.id)
                && (filters.isEmpty || !Set(service.envs).isDisjoint(with: filters))
        }
    }

    /// 某服务绑定的服务器
    func boundServers(of serviceID: UUID) -> [Server] {
        let serverIDs = Set(deployments.filter { $0.serviceID == serviceID }.map(\.serverID))
        return servers.filter { serverIDs.contains($0.id) }
    }

    /// 绑定关系本身（供解绑入口取 id）
    func binding(serverID: UUID, serviceID: UUID) -> Deployment? {
        deployments.first { $0.serverID == serverID && $0.serviceID == serviceID }
    }

    /// 某服务的绑定数（列表展示用）
    func bindingCount(of serviceID: UUID) -> Int {
        deployments.lazy.filter { $0.serviceID == serviceID }.count
    }

    private func touchServer(_ serverID: UUID) {
        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            servers[index].updatedAt = Date()
        }
    }

    // MARK: - 字典（环境 / 操作系统）

    /// 环境查询：自定义色优先，否则默认规则
    func color(for env: String) -> Color {
        envDefinitions.first { $0.name.lowercased() == env.lowercased() }?.color
            ?? Color.defaultEnvColor(env)
    }

    /// 新增环境（重名忽略，返回是否成功）
    @discardableResult
    func addEnv(name: String, colorHex: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty,
              !envDefinitions.contains(where: { $0.name.lowercased() == trimmed }) else { return false }
        envDefinitions.append(EnvDefinition(name: trimmed, colorHex: colorHex))
        persist()
        return true
    }

    /// 更新环境（改名时同步刷写所有引用它的服务；重名忽略）
    @discardableResult
    func updateEnv(_ id: UUID, name: String, colorHex: String?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = envDefinitions.firstIndex(where: { $0.id == id }),
              !trimmed.isEmpty,
              !envDefinitions.contains(where: { $0.id != id && $0.name.lowercased() == trimmed })
        else { return false }

        let oldName = envDefinitions[index].name
        envDefinitions[index].name = trimmed
        envDefinitions[index].colorHex = colorHex

        // 同步刷写服务引用
        if oldName != trimmed {
            for serviceIndex in services.indices {
                services[serviceIndex].envs = services[serviceIndex].envs.map { env in
                    env.lowercased() == oldName.lowercased() ? trimmed : env
                }
            }
        }
        persist()
        return true
    }

    /// 删除环境字典项（服务里的旧值保留，颜色回退默认规则）
    func deleteEnv(_ id: UUID) {
        envDefinitions.removeAll { $0.id == id }
        persist()
    }

    /// 新增操作系统（重名忽略）
    @discardableResult
    func addOS(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !osDefinitions.contains(where: { $0.name == trimmed }) else { return false }
        osDefinitions.append(OSDefinition(name: trimmed))
        persist()
        return true
    }

    /// 更新操作系统名（同步刷写所有引用它的服务器）
    @discardableResult
    func updateOS(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = osDefinitions.firstIndex(where: { $0.id == id }),
              !trimmed.isEmpty,
              !osDefinitions.contains(where: { $0.id != id && $0.name == trimmed })
        else { return false }

        let oldName = osDefinitions[index].name
        osDefinitions[index].name = trimmed

        if oldName != trimmed {
            for serverIndex in servers.indices where servers[serverIndex].os == oldName {
                servers[serverIndex].os = trimmed
            }
        }
        persist()
        return true
    }

    /// 删除操作系统字典项（服务器里的旧值保留）
    func deleteOS(_ id: UUID) {
        osDefinitions.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 持久化

    private struct Snapshot: Codable {
        var servers: [Server]
        var services: [Service]
        var deployments: [Deployment]
        var envDefinitions: [EnvDefinition]?
        var osDefinitions: [OSDefinition]?

        /// 兼容旧 JSON（v1：services 内嵌 serverID/groupID）的自定义解码；磁盘 key 保持 bindings
        enum CodingKeys: String, CodingKey {
            case servers, services, deployments = "bindings"
            case envDefinitions = "envDictionary"
            case osDefinitions = "osDictionary"
        }

        init(servers: [Server], services: [Service], deployments: [Deployment],
             envDefinitions: [EnvDefinition]? = nil, osDefinitions: [OSDefinition]? = nil) {
            self.servers = servers
            self.services = services
            self.deployments = deployments
            self.envDefinitions = envDefinitions
            self.osDefinitions = osDefinitions
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            servers = try c.decodeIfPresent([Server].self, forKey: .servers) ?? []
            // 字典缺省（旧数据）时由 Store 落内置默认
            envDefinitions = try c.decodeIfPresent([EnvDefinition].self, forKey: .envDefinitions)
            osDefinitions = try c.decodeIfPresent([OSDefinition].self, forKey: .osDefinitions)

            let legacy = try c.decodeIfPresent([LegacyServiceRecord].self, forKey: .services) ?? []
            var migrated: [Service] = []
            var migratedDeployments: [Deployment] = []

            // 旧 groupID 组：合并为首条服务 + 多绑定（组的"一处改处处生效"由绑定天然实现）
            var groups: [UUID: Service] = [:]
            var groupServers: [UUID: [UUID]] = [:]

            for record in legacy {
                if let groupID = record.groupID, let serverID = record.serverID {
                    if groups[groupID] == nil {
                        let service = Service(legacy: record)
                        migrated.append(service)
                        groups[groupID] = service
                        groupServers[groupID] = []
                    }
                    groupServers[groupID]?.append(serverID)
                } else if let serverID = record.serverID {
                    // 旧从属服务：独立化 + 一条绑定
                    let service = Service(legacy: record)
                    migrated.append(service)
                    migratedDeployments.append(Deployment(serverID: serverID, serviceID: service.id))
                } else {
                    // 已是新格式
                    migrated.append(Service(legacy: record))
                }
            }
            for (groupID, service) in groups {
                for serverID in groupServers[groupID] ?? [] {
                    migratedDeployments.append(Deployment(serverID: serverID, serviceID: service.id))
                }
            }

            // 新格式已有 bindings 则直接用（迁移只在缺省时发生）
            services = migrated
            deployments = try c.decodeIfPresent([Deployment].self, forKey: .deployments) ?? migratedDeployments
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(servers, forKey: .servers)
            try c.encode(services, forKey: .services)
            try c.encode(deployments, forKey: .deployments)
            try c.encodeIfPresent(envDefinitions, forKey: .envDefinitions)
            try c.encodeIfPresent(osDefinitions, forKey: .osDefinitions)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            servers = snapshot.servers
            services = snapshot.services
            deployments = snapshot.deployments
            envDefinitions = snapshot.envDefinitions ?? EnvDefinition.defaults
            osDefinitions = snapshot.osDefinitions ?? OSDefinition.defaults
        } catch {
            lastError = "读取数据失败：\(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Snapshot(
                servers: servers,
                services: services,
                deployments: deployments,
                envDefinitions: envDefinitions,
                osDefinitions: osDefinitions
            ))
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "保存数据失败：\(error.localizedDescription)"
        }
    }
}
