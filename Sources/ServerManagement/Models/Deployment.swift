import Foundation

/// 服务与服务器之间的部署关系（多对多连接记录）
/// 命名避开 SwiftUI.Binding
struct Deployment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var serverID: UUID
    var serviceID: UUID
    var createdAt: Date = Date()

    init(serverID: UUID, serviceID: UUID) {
        self.serverID = serverID
        self.serviceID = serviceID
    }
}
