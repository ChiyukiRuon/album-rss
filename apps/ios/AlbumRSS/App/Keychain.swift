import AlbumCore
import Foundation
import Security

/// 访问令牌保存在钥匙串：只在本机、首次解锁后可读，不随 iCloud 同步
struct KeychainCredentialStore: CredentialStore {
  private let service = "top.chiyukiruon.albumrss.endpoint"

  private func query(_ endpointID: String? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if let endpointID { query[kSecAttrAccount as String] = endpointID }
    return query
  }

  func token(for endpointID: String) -> String? {
    var request = query(endpointID)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func setToken(_ token: String?, for endpointID: String) {
    SecItemDelete(query(endpointID) as CFDictionary)
    guard let token else { return }
    var item = query(endpointID)
    item[kSecValueData as String] = Data(token.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }

  func removeAll() {
    SecItemDelete(query() as CFDictionary)
  }
}
