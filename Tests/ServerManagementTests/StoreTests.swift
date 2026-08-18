import Testing
import Foundation
import SwiftUI
@testable import ServerManagement

@Suite("Store 部署关系模型与迁移")
@MainActor
struct StoreTests {
    /// 每个测试用独立临时文件，避免串扰
    private func makeStore() throws -> Store {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        return Store(fileURL: url)
    }

    // MARK: - 服务器

    @Test("新增服务器后可按 id 查回，updatedAt 被刷新")
    func testUpsertServer() throws {
        let store = try makeStore()
        let server = Server(hostname: "web-01", ips: ["10.0.0.1"], os: "Ubuntu 24.04")

        store.upsertServer(server)

        let saved = store.server(id: server.id)
        #expect(saved?.hostname == "web-01")
        #expect(saved?.ips == ["10.0.0.1"])
        #expect((saved?.updatedAt ?? .distantPast) >= server.createdAt)
    }

    @Test("删除服务器级联删绑定，服务保留")
    func testDeleteServerCascade() throws {
        let store = try makeStore()
        let a = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        store.upsertServer(a)
        let svc = Service(name: "kafka", envs: ["sit"], ports: [ServicePort(port: 9092)])
        store.upsertService(svc)
        store.bind([svc.id], to: a.id)

        store.deleteServer(a)

        #expect(store.servers.isEmpty)
        #expect(store.services.map(\.name) == ["kafka"])
        #expect(store.deployments.isEmpty)
    }

    @Test("批量插入服务器：重复（hostname/IP/批内）跳过")
    func testAddServers() throws {
        let store = try makeStore()
        store.upsertServer(Server(hostname: "yd-vm121", ips: ["10.137.32.121"]))

        let result = store.addServers([
            Server(hostname: "yd-vm121", ips: ["10.137.32.999"]), // hostname 撞现存
            Server(hostname: "other", ips: ["10.137.32.121"]),    // IP 撞现存
            Server(hostname: "yd-vm122", ips: ["10.137.32.122"]),
            Server(hostname: "yd-vm122", ips: ["10.137.32.123"]), // hostname 撞批内
            Server(hostname: "yd-vm123", ips: ["10.137.32.123"]), // 上条已跳过未入库 → 正常添加
        ])

        #expect(result.added.map(\.hostname) == ["yd-vm122", "yd-vm123"])
        #expect(result.skipped.count == 3)
        #expect(store.servers.count == 3)
    }

    // MARK: - 服务与绑定

    @Test("服务一处编辑全局生效：编辑后所有绑定服务器的详情同步变化")
    func testServiceGlobalEdit() throws {
        let store = try makeStore()
        let vm121 = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        let vm122 = Server(hostname: "yd-vm122", ips: ["10.0.0.2"])
        store.upsertServer(vm121)
        store.upsertServer(vm122)

        var kafka = Service(name: "kafka", envs: ["sit"], ports: [ServicePort(port: 9092)], installMethod: "docker")
        store.upsertService(kafka)
        store.bind([kafka.id], to: vm121.id)
        store.bind([kafka.id], to: vm122.id)

        #expect(store.boundServices(of: vm121.id).first?.portsSummary == "9092")
        #expect(store.boundServices(of: vm122.id).first?.portsSummary == "9092")

        kafka.ports = [ServicePort(port: 9193, remark: "HTTP API")]
        kafka.envs = ["sit", "uat"]
        store.upsertService(kafka)

        for server in [vm121, vm122] {
            let bound = store.boundServices(of: server.id)
            #expect(bound.count == 1)
            #expect(bound.first?.portsSummary == "9193 · HTTP API")
            #expect(bound.first?.envs == ["sit", "uat"])
        }
    }

    @Test("绑定/解绑/幂等/未知服务忽略")
    func testBindUnbind() throws {
        let store = try makeStore()
        let vm = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        let vm2 = Server(hostname: "yd-vm122", ips: ["10.0.0.2"])
        store.upsertServer(vm)
        store.upsertServer(vm2)
        let kafka = Service(name: "kafka", envs: ["sit"], ports: [ServicePort(port: 9092)])
        let mysql = Service(name: "mysql", envs: ["prod"], ports: [ServicePort(port: 3306)])
        store.upsertService(kafka)
        store.upsertService(mysql)

        store.bind([kafka.id, mysql.id, kafka.id, UUID()], to: vm.id)
        #expect(store.boundServices(of: vm.id).count == 2)
        #expect(store.bindingCount(of: kafka.id) == 1)
        #expect(store.boundServers(of: kafka.id).map(\.hostname) == ["yd-vm121"])

        // 解绑只删绑定
        let binding = store.binding(serverID: vm.id, serviceID: kafka.id)!
        store.unbind(binding)
        #expect(store.boundServices(of: vm.id).map(\.name) == ["mysql"])
        #expect(store.services.count == 2)
        #expect(store.servers.count == 2)

        // 删除服务级联删绑定，服务器保留
        store.deleteService(mysql)
        #expect(store.services.map(\.name) == ["kafka"])
        #expect(store.boundServices(of: vm.id).isEmpty)
        #expect(store.servers.count == 2)
    }

    @Test("按环境集合过滤绑定服务（多选）")
    func testBoundServicesEnvFilter() throws {
        let store = try makeStore()
        let vm = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        store.upsertServer(vm)
        let kafka = Service(name: "kafka", envs: ["sit", "uat"], ports: [ServicePort(port: 9092)])
        let nginx = Service(name: "nginx", envs: ["prod"], ports: [ServicePort(port: 443)])
        store.upsertService(kafka)
        store.upsertService(nginx)
        store.bind([kafka.id, nginx.id], to: vm.id)

        #expect(store.boundServices(of: vm.id).count == 2)
        #expect(store.boundServices(of: vm.id, envs: ["uat"]).map(\.name) == ["kafka"])
        #expect(store.boundServices(of: vm.id, envs: ["sit", "prod"]).count == 2)
        #expect(store.boundServices(of: vm.id, envs: ["gray"]).isEmpty)
    }

    @Test("搜索：多关键字载体 = 服务器字段或其绑定服务字段")
    func testSearchViaBinding() throws {
        let store = try makeStore()
        let web = Server(hostname: "mq-01", ips: ["10.1.1.1"], os: "Ubuntu")
        let db = Server(hostname: "db-01", ips: ["10.2.2.2"], os: "Rocky Linux 9")
        store.upsertServer(web)
        store.upsertServer(db)
        let kafkaS = Service(name: "kafka", envs: ["sit"], ports: [ServicePort(port: 9092)])
        let kafkaP = Service(name: "kafka", envs: ["prod"], ports: [ServicePort(port: 9092)])
        let mysql = Service(name: "mysql", envs: ["sit"], ports: [ServicePort(port: 3306)])
        store.upsertService(kafkaS)
        store.upsertService(kafkaP)
        store.upsertService(mysql)
        store.bind([kafkaS.id], to: web.id)
        store.bind([kafkaP.id, mysql.id], to: db.id)

        // kafka + sit：同一服务须同时满足 → 只有 web（db 的 kafka 是 prod）
        #expect(store.filteredServers(keyword: "kafka sit").map(\.id) == [web.id])
        // 单关键字 OR 多字段
        #expect(store.filteredServers(keyword: "kafka").count == 2)
        #expect(store.filteredServers(keyword: "sit").count == 2)
        // 服务器自身字段载体
        #expect(store.filteredServers(keyword: "mq-01 10.1").map(\.id) == [web.id])
        // 无命中
        #expect(store.filteredServers(keyword: "redis").isEmpty)
    }

    // MARK: - 持久化与迁移

    @Test("round-trip：新 Store 实例读回全部数据")
    func testPersistenceRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        let store = Store(fileURL: url)
        let vm = Server(hostname: "yd-vm121", ips: ["10.0.0.1"], os: "Ubuntu")
        store.upsertServer(vm)
        let redis = Service(name: "redis", envs: ["uat", "sit"], ports: [ServicePort(port: 6379)], installMethod: "docker")
        store.upsertService(redis)
        store.bind([redis.id], to: vm.id)

        let reloaded = Store(fileURL: url)
        #expect(reloaded.servers.count == 1)
        #expect(reloaded.services.count == 1)
        #expect(reloaded.services.first?.envs == ["uat", "sit"])
        #expect(reloaded.deployments.count == 1)
        #expect(reloaded.boundServices(of: vm.id).map(\.name) == ["redis"])
    }

    @Test("旧格式迁移：从属服务独立化 + groupID 组合并为单服务多绑定")
    func testLegacyMigration() throws {
        let sid1 = UUID(), sid2 = UUID(), sid3 = UUID(), sid4 = UUID()
        let vm121 = UUID(), vm122 = UUID(), vm123 = UUID(), vm99 = UUID()
        let group = UUID()
        let json = """
        {
          "servers": [
            {"id": "\(vm121.uuidString)", "hostname": "yd-vm121", "ip": "10.0.0.1"},
            {"id": "\(vm122.uuidString)", "hostname": "yd-vm122", "ip": "10.0.0.2"},
            {"id": "\(vm123.uuidString)", "hostname": "yd-vm123", "ip": "10.0.0.3"},
            {"id": "\(vm99.uuidString)", "hostname": "yd-vm99", "ip": "10.0.0.99"}
          ],
          "services": [
            {"id": "\(sid1.uuidString)", "name": "kafka", "envs": ["sit"], "port": 9092, "serverID": "\(vm121.uuidString)", "groupID": "\(group.uuidString)"},
            {"id": "\(sid2.uuidString)", "name": "kafka", "envs": ["sit"], "port": 9092, "serverID": "\(vm122.uuidString)", "groupID": "\(group.uuidString)"},
            {"id": "\(sid3.uuidString)", "name": "kafka", "envs": ["sit"], "port": 9092, "serverID": "\(vm123.uuidString)", "groupID": "\(group.uuidString)"},
            {"id": "\(sid4.uuidString)", "name": "solo", "env": "prod", "port": 80, "serverID": "\(vm99.uuidString)"}
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: url)

        let store = Store(fileURL: url)

        // 组合并为一条 kafka（保留首条 id），三台绑定；solo 独立 + 一绑定
        #expect(store.services.count == 2)
        let kafka = store.services.first { $0.name == "kafka" }!
        #expect(kafka.id == sid1)
        #expect(store.boundServers(of: kafka.id).count == 3)
        #expect(Set(store.boundServers(of: kafka.id).map(\.hostname)) == ["yd-vm121", "yd-vm122", "yd-vm123"])

        let solo = store.services.first { $0.name == "solo" }!
        #expect(solo.id == sid4)
        #expect(solo.envs == ["prod"])
        #expect(store.boundServers(of: solo.id).map(\.hostname) == ["yd-vm99"])

        // 迁移结果持久化为新格式（round-trip 稳定）
        let reloaded = Store(fileURL: url)
        #expect(reloaded.services.count == 2)
        #expect(reloaded.deployments.count == 4)
    }

    @Test("多 IP：展示摘要 / 搜索命中任一 / 旧单 ip 数据迁移")
    func testMultipleIPs() throws {
        let store = try makeStore()
        var multi = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        store.upsertServer(multi)

        multi.ips.append("192.168.1.1")
        store.upsertServer(multi)

        #expect(store.server(id: multi.id)?.ipsSummary == "10.0.0.1, 192.168.1.1")
        // 搜索任一 IP 命中
        #expect(store.filteredServers(keyword: "192.168").count == 1)

        // 旧 JSON 单 ip 字段自动迁移
        let json = """
        {"servers": [{"hostname": "legacy-01", "ip": "10.9.9.9"}], "services": []}
        """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: url)
        let migrated = Store(fileURL: url)
        #expect(migrated.servers.first?.ips == ["10.9.9.9"])
    }

    @Test("环境字典：默认初始化 / 增改删 / 颜色查询 / 改名同步引用")
    func testEnvDictionary() throws {
        let store = try makeStore()
        // 首启默认
        #expect(store.envDefinitions.map(\.name) == ["sit", "uat", "prod"])

        // 新增（小写规范化 + 重名拒绝）
        #expect(store.addEnv(name: " Gray "))
        #expect(!store.addEnv(name: "gray"))
        #expect(store.envDefinitions.map(\.name) == ["sit", "uat", "prod", "gray"])

        // 颜色：自定义优先，未配置走默认规则
        #expect(store.color(for: "sit") == Color.defaultEnvColor("sit"))
        let grayID = store.envDefinitions.first { $0.name == "gray" }!.id
        #expect(store.updateEnv(grayID, name: "gray", colorHex: "#7C3AED"))
        #expect(store.color(for: "gray") == Color(hex: "#7C3AED"))
        // 大小写不敏感命中
        #expect(store.color(for: "GRAY") == Color(hex: "#7C3AED"))
        // 未知环境回退灰
        #expect(store.color(for: "unknown") == .gray)

        // 改名同步服务引用
        let vm = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        store.upsertServer(vm)
        let svc = Service(name: "kafka", envs: ["gray", "sit"], ports: [ServicePort(port: 9092)])
        store.upsertService(svc)
        #expect(store.updateEnv(grayID, name: "purple", colorHex: nil))
        #expect(store.service(id: svc.id)?.envs == ["purple", "sit"])

        // 重名修改拒绝
        #expect(!store.updateEnv(grayID, name: "SIT", colorHex: nil))

        // 删除：服务旧值保留，颜色回退默认
        store.deleteEnv(grayID)
        #expect(store.service(id: svc.id)?.envs == ["purple", "sit"])
        #expect(store.color(for: "purple") == .gray)
    }

    @Test("操作系统字典：增改删 / 改名同步服务器存量")
    func testOSDictionary() throws {
        let store = try makeStore()
        #expect(store.osDefinitions.count == 8)

        #expect(store.addOS(name: " Debian 12 "))
        #expect(!store.addOS(name: "Debian 12"))
        #expect(store.osDefinitions.last?.name == "Debian 12")

        // 改名同步服务器存量
        store.upsertServer(Server(hostname: "yd-vm121", ips: ["10.0.0.1"], os: "Debian 12"))
        let id = store.osDefinitions.first { $0.name == "Debian 12" }!.id
        #expect(store.updateOS(id, name: "Debian 13"))
        #expect(store.servers.first?.os == "Debian 13")
        // 重名拒绝
        #expect(!store.updateOS(id, name: "CentOS 7.9"))

        // 删除：服务器旧值保留
        store.deleteOS(id)
        #expect(store.servers.first?.os == "Debian 13")
        #expect(store.osDefinitions.count == 8)
    }

    @Test("字典 round-trip：自定义颜色与新增项持久化")
    func testDictionaryRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        let store = Store(fileURL: url)
        store.addEnv(name: "gray", colorHex: "#7C3AED")
        store.addOS(name: "Debian 12")

        let reloaded = Store(fileURL: url)
        #expect(reloaded.envDefinitions.contains { $0.name == "gray" && $0.colorHex == "#7C3AED" })
        #expect(reloaded.osDefinitions.contains { $0.name == "Debian 12" })
        // 旧数据（无字典字段）→ 默认字典
        let legacyURL = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        try #"{"servers": [], "services": []}"#.data(using: .utf8)!.write(to: legacyURL)
        let legacy = Store(fileURL: legacyURL)
        #expect(legacy.envDefinitions == EnvDefinition.defaults)
        #expect(legacy.osDefinitions == OSDefinition.defaults)
    }

    @Test("颜色 hex 转换 round-trip 与预设色字节序")
    func testColorHexConversion() {
        // round-trip
        for hex in ["#E5484D", "#7C3AED", "#30A46C", "#8B8D98", "#0091FF"] {
            let color = Color(hex: hex)
            #expect(color != nil)
            #expect(color?.hexString == hex)
        }
        // 8 位（带 alpha）
        #expect(Color(hex: "#7C3AED80") != nil)
        // 非法
        #expect(Color(hex: "xyz") == nil)
        #expect(Color(hex: "#12345") == nil)
        // 预设紫 #7C3AED：R≈0.49 G≈0.23 B≈0.93（防字节序错位回归）
        let purple = Color(hex: "#7C3AED")!
        let ns = NSColor(purple).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0x7C / 255.0) < 0.01)
        #expect(abs(ns.greenComponent - 0x3A / 255.0) < 0.01)
        #expect(abs(ns.blueComponent - 0xED / 255.0) < 0.01)
    }

    @Test("凭据：服务器与服务均可挂多条并持久化")
    func testCredentials() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        let store = Store(fileURL: url)

        var server = Server(hostname: "yd-vm121", ips: ["10.0.0.1"])
        server.credentials = [
            Credential(username: "root", password: "p@ss", remark: "ssh 登录"),
            Credential(username: "deploy", password: "123456"),
        ]
        store.upsertServer(server)

        var service = Service(name: "kafka", envs: ["sit"], ports: [ServicePort(port: 9092)])
        service.credentials = [Credential(username: "admin", password: "admin", remark: "管理后台")]
        store.upsertService(service)

        let reloaded = Store(fileURL: url)
        #expect(reloaded.servers.first?.credentials.count == 2)
        #expect(reloaded.servers.first?.credentials.first?.username == "root")
        #expect(reloaded.servers.first?.credentials.first?.remark == "ssh 登录")
        #expect(reloaded.services.first?.credentials.first?.password == "admin")

        // 旧 JSON（无 credentials 字段）解码不崩、默认空
        let legacyJSON = #"{"servers": [{"hostname": "old", "ip": "10.0.0.9"}], "services": [{"name": "solo", "env": "prod", "port": 80, "serverID": "11111111-2222-3333-4444-555555555555"}]}"#
        let legacyURL = FileManager.default.temporaryDirectory
            .appending(path: "store-tests-\(UUID().uuidString).json")
        try legacyJSON.data(using: .utf8)!.write(to: legacyURL)
        let legacy = Store(fileURL: legacyURL)
        #expect(legacy.servers.first?.credentials.isEmpty == true)
        #expect(legacy.services.first?.credentials.isEmpty == true)
    }

    @Test("端口校验：未填合法，填了必须 1-65535")
    func testPortValidation() {
        #expect(Service(name: "a", envs: ["sit"], ports: []).isValidPorts)
        #expect(Service(name: "a", envs: ["sit"], ports: [ServicePort(port: 1)]).isValidPorts)
        #expect(Service(name: "a", envs: ["sit"], ports: [ServicePort(port: 65535)]).isValidPorts)
        #expect(!Service(name: "a", envs: ["sit"], ports: [ServicePort(port: 0)]).isValidPorts)
        #expect(!Service(name: "a", envs: ["sit"], ports: [ServicePort(port: 65536)]).isValidPorts)
        // 多端口摘要
        #expect(Service(name: "a", envs: ["sit"], ports: [ServicePort(port: 9092, remark: "HTTP API"), ServicePort(port: 9999)]).portsSummary == "9092 · HTTP API、9999")
    }
}
