import Foundation

/// 账号凭据（可挂在服务器或服务上）
struct Credential: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var username: String
    var password: String
    /// 用途备注（如「root 登录」「管理后台」）
    var remark: String = ""
    var createdAt: Date = Date()

    init(username: String, password: String, remark: String = "") {
        self.username = username
        self.password = password
        self.remark = remark
    }
}
