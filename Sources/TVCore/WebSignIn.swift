import Foundation
import Perception

/// Signing in on a service's own web page. A phone can't scan a code on its own screen, so iPhone
/// and iPad open the page in a private web view, and these read the sign-in it leaves behind: the
/// account cookies, or Aliyun Drive's refresh token in the page's storage.
public enum WebSignIn: String, Sendable, CaseIterable, Identifiable {
    case bilibili, quark, uc, baidu, aliyun
    public var id: String { rawValue }

    public enum Result: Sendable, Equatable {
        case cookie(String)
        /// Aliyun Drive.
        case refreshToken(String)
    }

    public var page: URL {
        switch self {
        case .bilibili: URL(string: "https://passport.bilibili.com/h5-app/passport/login")!
        case .quark: URL(string: "https://pan.quark.cn/")!
        case .uc: URL(string: "https://drive.uc.cn/")!
        case .baidu: URL(string: "https://wappass.baidu.com/passport/?login&tpl=netdisk&u=https%3A%2F%2Fpan.baidu.com%2Fwap%2Fhome")!
        case .aliyun: URL(string: "https://www.alipan.com/sign/in")!
        }
    }

    /// Quark, UC and Aliyun send phone browsers to their apps; their desktop pages sign in with a
    /// text-message code or a password.
    public var userAgent: String? {
        switch self {
        case .quark, .uc, .aliyun: Self.desktop
        case .bilibili, .baidu: nil
        }
    }

    /// The sign-in box on a desktop page wider than a phone (Quark's and UC's are 1,260 points wide, with
    /// the box at the right): the web view zooms to it.
    public var signInBox: String? {
        switch self {
        case .quark: #"[class*="LoginComponent--modal--"]"#
        case .uc: ".login-component-modal"
        case .bilibili, .baidu, .aliyun: nil
        }
    }

    /// The page's localStorage entry that holds the sign-in, for the hosts that keep it.
    public var storage: (key: String, hosts: [String])? {
        self == .aliyun ? ("token", ["www.alipan.com", "www.aliyundrive.com"]) : nil
    }

    /// Baidu issues the drive's STOKEN only when the drive asks for it: once BDUSS is set and STOKEN
    /// isn't, the web view opens this.
    public var followUp: URL? {
        self == .baidu ? URL(string: "https://passport.baidu.com/v3/login/api/auth/?return_type=5&tpl=netdisk&u=https%3A%2F%2Fpan.baidu.com%2Fdisk%2Fhome")! : nil
    }

    /// The sign-in the page holds, or nil while it's still signing in.
    public func result(cookies: [HTTPCookie], stored: String? = nil) -> Result? {
        switch self {
        case .bilibili:
            let fields = Self.fields(cookies, domain: "bilibili.com")
            guard fields["SESSDATA"]?.isEmpty == false else { return nil }
            return .cookie(Self.join(fields, only: ["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5"]))
        case .quark, .uc:
            let fields = Self.fields(cookies, domain: self == .quark ? "quark.cn" : "uc.cn")
            guard fields["__pus"]?.isEmpty == false else { return nil }
            return .cookie(Self.join(fields))
        case .baidu:
            let fields = Self.fields(cookies, domain: "baidu.com", preferring: "pan.baidu.com")
            guard fields["BDUSS"]?.isEmpty == false, fields["STOKEN"]?.isEmpty == false else { return nil }
            return .cookie(Self.join(fields, only: ["BDUSS", "STOKEN", "PTOKEN"]))
        case .aliyun:
            guard let data = stored?.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["refresh_token"] as? String, !token.isEmpty else { return nil }
            return .refreshToken(token)
        }
    }

    /// Signed in, but a cookie the drive needs is still missing (Baidu before its drive's STOKEN).
    public func needsFollowUp(cookies: [HTTPCookie]) -> Bool {
        guard self == .baidu else { return false }
        let fields = Self.fields(cookies, domain: "baidu.com")
        return fields["BDUSS"]?.isEmpty == false && fields["STOKEN"]?.isEmpty != false
    }

    /// Quark's page signs in inside a frame from uop.quark.cn, which hands the approved ticket (`st`) to
    /// the page; the page then sends it to /account/info in the background. The web view watches for it.
    public var catchesTicket: Bool { self == .quark }

    /// Quark's approved sign-in ticket (`st`) in an address the page opens; it also yields the mobile
    /// ticket FTY's player needs, as after scanning a code.
    public func serviceTicket(in url: URL) -> String? {
        guard self == .quark, let host = url.host, host == "quark.cn" || host.hasSuffix(".quark.cn"),
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "st" })?.value,
              !value.isEmpty else { return nil }
        return value
    }

    /// Unexpired cookies of the domain by name. A subdomain's cookie wins over the domain's, and the
    /// `preferring` host's over every other: Baidu sets STOKEN for the passport and for the drive,
    /// and the drive's is the one its API takes.
    static func fields(_ cookies: [HTTPCookie], domain: String, preferring preferred: String? = nil) -> [String: String] {
        var fields: [String: String] = [:]
        let now = Date()
        let matching = cookies.compactMap { cookie -> (String, HTTPCookie)? in
            let host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard host == domain || host.hasSuffix("." + domain), cookie.expiresDate.map({ $0 > now }) ?? true else { return nil }
            return (host, cookie)
        }
        func rank(_ host: String) -> Int { host == preferred ? 2 : host == domain ? 0 : 1 }
        for (_, cookie) in matching.sorted(by: { rank($0.0) < rank($1.0) }) where !cookie.value.isEmpty { fields[cookie.name] = cookie.value }
        return fields
    }

    static func join(_ fields: [String: String], only names: Set<String>? = nil) -> String {
        fields.filter { names?.contains($0.key) ?? true }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}

extension WebSignIn {
    /// Keeps the sign-in as the app's account for the service; plugins read it on their next request.
    /// `ticket` is Quark's approved sign-in ticket, when the page opened one.
    public func save(_ result: Result, ticket: String? = nil) async throws {
        var detail = ""
        switch result {
        case .cookie(let cookie) where self == .bilibili:
            var account = BilibiliAccount()
            account.cookie = cookie
            _ = await account.refresh()
            try account.save()
        case .cookie(let cookie):
            var accounts = (try? CloudDriveAccounts.load()) ?? CloudDriveAccounts()
            switch self {
            case .quark:
                accounts.quarkCookie = cookie
                // FTY's player also needs the mobile ticket; other plugins take the cookie alone.
                accounts.quarkServiceTicket = nil
                if let ticket { accounts.quarkServiceTicket = try? await CloudDriveQRLogin.quarkMobileTicket(ticket, cookie: cookie) }
                detail = " mobileTicket=\(accounts.quarkServiceTicket != nil)"
            case .uc: accounts.ucCookie = cookie
            case .baidu: accounts.baiduCookie = cookie
            case .bilibili, .aliyun: break
            }
            try accounts.save()
        case .refreshToken(let token):
            var accounts = (try? CloudDriveAccounts.load()) ?? CloudDriveAccounts()
            accounts.token = token
            try accounts.save()
        }
        Diagnostics.shared.record(.info, "cloud.signin", "signed in on the \(rawValue) page\(detail)")
    }
}
