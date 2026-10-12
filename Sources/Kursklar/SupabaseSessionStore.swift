import Combine
import Foundation
import Security

struct WertweitAuthUser: Codable {
    let id: String
    let email: String?
}

struct WertweitAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let user: WertweitAuthUser
}

struct WertweitSupportMessage: Decodable, Identifiable {
    let id: String
    let senderIsAdmin: Bool
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case senderIsAdmin = "sender_is_admin"
        case body
        case createdAt = "created_at"
    }
}

struct WertweitSupportThread: Decodable, Identifiable {
    let id: String
    let subject: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let messages: [WertweitSupportMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messages
    }
}

@MainActor
final class SupabaseSessionStore: ObservableObject {
    @Published private(set) var session: WertweitAuthSession?
    @Published private(set) var isLoading = true
    @Published private(set) var maintenanceEnabled = false
    @Published private(set) var maintenanceMessage = "Wertweit wird gerade gewartet. Bitte versuche es später erneut."
    @Published private(set) var statusMessage: String?
    @Published private(set) var configurationError: String?
    @Published private(set) var isBlocked = false
    @Published private(set) var adminProUntil: String?
    @Published private(set) var isAwaitingEmailConfirmation = false
    @Published private(set) var emailConfirmationEmail = ""
    @Published private(set) var supportThreads: [WertweitSupportThread] = []
    @Published private(set) var supportStatusMessage: String?
    @Published private(set) var supportStatusIsError = false

    private let projectURL: URL?
    private let publishableKey: String
    private var hasStarted = false

    init() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        projectURL = URL(string: urlString)
        publishableKey = key

        if URL(string: urlString)?.scheme != "https" || key.isEmpty || key.hasPrefix("REPLACE_") {
            configurationError = "Supabase ist noch nicht eingerichtet. Trage Projekt-URL und Publishable Key in Config/Supabase.xcconfig ein."
        }
    }

    func start() async {
        guard !hasStarted else {
            await refreshMaintenanceStatus()
            return
        }
        hasStarted = true

        do {
            session = try SessionKeychain.load()
        } catch {
            session = nil
            do {
                try SessionKeychain.delete()
            } catch {
                statusMessage = "Die gespeicherte Anmeldung konnte nicht sicher entfernt werden. Bitte starte die App neu."
            }
            if statusMessage == nil {
                statusMessage = "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."
            }
        }
        if session != nil {
            do {
                try await refreshSessionIfNeeded()
            } catch SupabaseRequestError.invalidResponse(let status, _) where status == 400 || status == 401 {
                do {
                    try SessionKeychain.delete()
                    session = nil
                    statusMessage = "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."
                } catch {
                    statusMessage = "Die abgelaufene Anmeldung konnte nicht sicher entfernt werden. Bitte starte die App neu."
                }
            } catch {
                statusMessage = "Die Anmeldung konnte gerade nicht erneuert werden. Deine gespeicherte Anmeldung bleibt auf diesem Gerät verfügbar."
            }
            await refreshAccountAccess()
        }
        await refreshMaintenanceStatus()
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        statusMessage = nil
        do {
            let response = try await request(
                path: ["auth", "v1", "token"],
                query: [URLQueryItem(name: "grant_type", value: "password")],
                body: Credentials(email: email, password: password)
            )
            try storeSession(from: response)
        } catch {
            if requiresEmailConfirmation(error) {
                emailConfirmationEmail = email
                isAwaitingEmailConfirmation = true
            }
            statusMessage = authenticationStatusMessage(for: error, operation: .signIn)
        }
    }

    func signUp(email: String, password: String) async {
        statusMessage = nil
        isAwaitingEmailConfirmation = false
        do {
            let response = try await request(
                path: ["auth", "v1", "signup"],
                body: Credentials(email: email, password: password)
            )
            if let newSession = try response.makeSession() {
                try SessionKeychain.save(newSession)
                session = newSession
                emailConfirmationEmail = ""
            } else {
                emailConfirmationEmail = email
                isAwaitingEmailConfirmation = true
                statusMessage = "Wir haben einen Bestätigungscode an deine E-Mail-Adresse gesendet."
            }
        } catch {
            statusMessage = authenticationStatusMessage(for: error, operation: .signUp)
        }
    }

    func confirmEmail(code: String) async {
        statusMessage = nil
        do {
            let response = try await request(
                path: ["auth", "v1", "verify"],
                body: VerifyEmailOTPRequest(
                    type: "signup",
                    email: emailConfirmationEmail,
                    token: code
                )
            )
            try storeSession(from: response)
            isAwaitingEmailConfirmation = false
            emailConfirmationEmail = ""
        } catch {
            statusMessage = authenticationStatusMessage(for: error, operation: .verifyEmail)
        }
    }

    func resendEmailConfirmation() async {
        statusMessage = nil
        do {
            _ = try await requestData(
                path: ["auth", "v1", "resend"],
                body: ResendEmailOTPRequest(type: "signup", email: emailConfirmationEmail)
            )
            statusMessage = "Wenn die Adresse noch nicht bestätigt ist, wurde ein neuer Code gesendet."
        } catch {
            statusMessage = authenticationStatusMessage(for: error, operation: .resendEmail)
        }
    }

    func cancelEmailConfirmation() {
        isAwaitingEmailConfirmation = false
        emailConfirmationEmail = ""
        statusMessage = nil
    }

    func resetPassword(email: String) async {
        statusMessage = nil
        do {
            _ = try await requestData(
                path: ["auth", "v1", "recover"],
                query: [URLQueryItem(
                    name: "redirect_to",
                    value: "https://jamietrading9-design.github.io/wertweit/set-password.html"
                )],
                body: EmailAddress(email: email)
            )
            statusMessage = "Wenn ein Konto mit dieser E-Mail besteht, erhältst du eine Nachricht zum Zurücksetzen des Passworts."
        } catch {
            statusMessage = "Die Anfrage konnte nicht gesendet werden. Prüfe deine Verbindung und versuche es erneut."
        }
    }

    func signOut() async {
        statusMessage = nil
        let currentSession = session
        var serverSignOutFailed = false
        if let currentSession {
            do {
                _ = try await requestData(
                    path: ["auth", "v1", "logout"],
                    body: EmptyRequest(),
                    accessToken: currentSession.accessToken
                )
            } catch {
                serverSignOutFailed = true
            }
        }

        do {
            try SessionKeychain.delete()
            session = nil
            isBlocked = false
            adminProUntil = nil
            isAwaitingEmailConfirmation = false
            emailConfirmationEmail = ""
            supportThreads = []
            if serverSignOutFailed {
                statusMessage = "Du wurdest auf diesem Gerät abgemeldet. Die Abmeldung beim Server konnte nicht bestätigt werden."
            }
        } catch {
            statusMessage = "Die Anmeldung konnte nicht sicher entfernt werden. Bitte versuche es erneut."
        }
    }

    func deleteAccount() async {
        guard session != nil else { return }
        statusMessage = nil
        do {
            try await refreshSessionIfNeeded()
            guard let session else {
                throw SupabaseRequestError.incompleteSession
            }
            _ = try await requestData(
                path: ["functions", "v1", "account-delete"],
                body: EmptyRequest(),
                accessToken: session.accessToken
            )
            try SessionKeychain.delete()
            self.session = nil
            statusMessage = "Dein Wertweit-Konto wurde gelöscht. Ein App-Store-Abo musst du separat bei Apple kündigen."
        } catch {
            statusMessage = "Das Konto konnte nicht gelöscht werden. Bitte versuche es erneut oder wende dich an den Support."
        }
    }

    func clearStatusMessage() {
        statusMessage = nil
    }

    func refreshAccountAccess() async {
        guard session != nil else { return }
        do {
            try await refreshSessionIfNeeded()
            guard let currentSession = self.session else { return }
            let data = try await requestData(
                path: ["functions", "v1", "user-portal"],
                body: PortalAction(action: "get-access"),
                accessToken: currentSession.accessToken
            )
            let access = try JSONDecoder().decode(AccountAccessResponse.self, from: data)
            isBlocked = false
            adminProUntil = access.hasAdminPro ? access.proUntil : nil
        } catch SupabaseRequestError.invalidResponse(403, _) {
            isBlocked = true
            adminProUntil = nil
        } catch {
            statusMessage = "Dein Kontozugriff konnte nicht geprüft werden. Bitte prüfe deine Internetverbindung."
        }
    }

    func refreshSupportThreads() async {
        guard session != nil else { return }
        do {
            try await refreshSessionIfNeeded()
            guard let currentSession = self.session else { return }
            let data = try await requestData(
                path: ["functions", "v1", "user-portal"],
                body: PortalAction(action: "list-support"),
                accessToken: currentSession.accessToken
            )
            supportThreads = try JSONDecoder().decode(SupportThreadsResponse.self, from: data).threads
            supportStatusMessage = nil
            supportStatusIsError = false
        } catch {
            supportStatusMessage = "Support-Nachrichten konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut."
            supportStatusIsError = true
        }
    }

    func sendSupportMessage(subject: String, body: String) async {
        guard session != nil else { return }
        supportStatusMessage = nil
        supportStatusIsError = false
        do {
            try await refreshSessionIfNeeded()
            guard let currentSession = self.session else { throw SupabaseRequestError.incompleteSession }
            _ = try await requestData(
                path: ["functions", "v1", "user-portal"],
                body: CreateSupportRequest(action: "create-support", subject: subject, body: body),
                accessToken: currentSession.accessToken
            )
            await refreshSupportThreads()
            if supportStatusIsError {
                supportStatusMessage = "Deine Nachricht wurde gesendet. Der Verlauf konnte nicht aktualisiert werden; tippe auf Aktualisieren."
                supportStatusIsError = false
            } else {
                supportStatusMessage = "Deine Nachricht wurde an den Wertweit-Support gesendet."
            }
        } catch {
            if case let SupabaseRequestError.invalidResponse(status, serverError) = error,
               let message = serverError?.message ?? serverError?.msg ?? serverError?.errorDescription {
                supportStatusMessage = "Nachricht konnte nicht gesendet werden (HTTP \(status)): \(message)"
            } else {
                supportStatusMessage = "Deine Nachricht konnte nicht gesendet werden. Prüfe deine Verbindung und versuche es erneut."
            }
            supportStatusIsError = true
        }
    }

    func refreshMaintenanceStatus() async {
        guard let projectURL, !publishableKey.isEmpty else { return }
        var components = URLComponents(url: projectURL.appendingPathComponent("rest/v1/app_settings"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "maintenance_enabled,maintenance_message"),
            URLQueryItem(name: "id", value: "eq.1")
        ]
        guard let url = components?.url else {
            statusMessage = "Die Supabase-Projektadresse ist ungültig."
            return
        }

        var request = URLRequest(url: url)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")

        request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw SupabaseRequestError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
            }
            let rows = try JSONDecoder().decode([AppSettings].self, from: data)
            guard let settings = rows.first else {
                throw SupabaseRequestError.missingSettings
            }
            maintenanceEnabled = settings.maintenanceEnabled
            maintenanceMessage = settings.maintenanceMessage
        } catch {
            statusMessage = "Der Wartungsstatus konnte nicht aktualisiert werden. Ohne Verbindung bleibt die App verfügbar."
        }
    }

    private func refreshSessionIfNeeded() async throws {
        guard let session, session.expiresAt <= Date.now.addingTimeInterval(60) else { return }
        let response = try await request(
            path: ["auth", "v1", "token"],
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: RefreshTokenRequest(refreshToken: session.refreshToken)
        )
        try storeSession(from: response)
    }

    private func request<Body: Encodable>(
        path: [String],
        query: [URLQueryItem] = [],
        body: Body,
        accessToken: String? = nil
    ) async throws -> AuthSessionResponse {
        let data = try await requestData(path: path, query: query, body: body, accessToken: accessToken)
        return try JSONDecoder().decode(AuthSessionResponse.self, from: data)
    }

    @discardableResult
    private func requestData<Body: Encodable>(
        path: [String],
        query: [URLQueryItem] = [],
        body: Body? = nil,
        accessToken: String? = nil
    ) async throws -> Data {
        guard let projectURL, var components = URLComponents(
            url: path.reduce(projectURL, { $0.appendingPathComponent($1) }),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseRequestError.invalidConfiguration
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw SupabaseRequestError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        request.setValue("Bearer \(accessToken ?? publishableKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let serverError = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data)
            throw SupabaseRequestError.invalidResponse(status, serverError)
        }
        return data
    }

    private func authenticationStatusMessage(for error: Error, operation: AuthOperation) -> String {
        guard case let SupabaseRequestError.invalidResponse(status, serverError) = error else {
            if error is URLError {
                return "Supabase ist gerade nicht erreichbar. Prüfe deine Internetverbindung und versuche es erneut."
            }
            return "Die Anfrage konnte nicht abgeschlossen werden. Prüfe die Supabase-Einrichtung und versuche es erneut."
        }

        let errorCode = serverError?.errorCode?.lowercased() ?? ""
        let message = [
            serverError?.message,
            serverError?.errorDescription,
            serverError?.msg
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if errorCode.contains("email_not_confirmed") || message.contains("email not confirmed") {
            return "Bitte bestätige zuerst deine E-Mail-Adresse mit dem zugesendeten Code."
        }
        if operation == .verifyEmail,
           errorCode.contains("otp_expired") || message.contains("expired") || message.contains("invalid token") {
            return "Der Code ist abgelaufen oder ungültig. Fordere einen neuen Bestätigungscode an."
        }
        if operation == .signIn,
           errorCode.contains("invalid_credentials") || message.contains("invalid login credentials") || status == 401 {
            return "Anmeldung fehlgeschlagen. Prüfe E-Mail und Passwort und versuche es erneut."
        }
        if operation == .signUp,
           errorCode.contains("user_already_exists") || message.contains("already registered") {
            return "Für diese E-Mail-Adresse besteht bereits ein Konto. Melde dich an oder setze dein Passwort zurück."
        }
        if status == 429 {
            return "Zu viele Versuche. Warte kurz und versuche es danach erneut."
        }
        return "Die Anfrage ist fehlgeschlagen (Supabase HTTP \(status)). Prüfe deine Eingaben und versuche es erneut."
    }

    private func requiresEmailConfirmation(_ error: Error) -> Bool {
        guard case let SupabaseRequestError.invalidResponse(_, serverError) = error else { return false }
        return serverError?.errorCode?.lowercased().contains("email_not_confirmed") == true
            || serverError?.msg?.lowercased().contains("email not confirmed") == true
    }

    private func storeSession(from response: AuthSessionResponse) throws {
        guard let session = try response.makeSession() else {
            throw SupabaseRequestError.incompleteSession
        }
        try SessionKeychain.save(session)
        self.session = session
    }
}

private struct Credentials: Encodable {
    let email: String
    let password: String
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct EmailAddress: Encodable {
    let email: String
}

private struct VerifyEmailOTPRequest: Encodable {
    let type: String
    let email: String
    let token: String
}

private struct ResendEmailOTPRequest: Encodable {
    let type: String
    let email: String
}

private struct EmptyRequest: Encodable {}

private struct PortalAction: Encodable {
    let action: String
}

private struct CreateSupportRequest: Encodable {
    let action: String
    let subject: String
    let body: String
}

private struct AccountAccessResponse: Decodable {
    let proUntil: String?
    let hasAdminPro: Bool
}

private struct SupportThreadsResponse: Decodable {
    let threads: [WertweitSupportThread]
}

private struct AuthSessionResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let user: WertweitAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }

    func makeSession() throws -> WertweitAuthSession? {
        guard let accessToken, let refreshToken, let tokenType, let expiresIn, let user else {
            return nil
        }
        return WertweitAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(expiresIn)),
            user: user
        )
    }
}

private struct SupabaseErrorResponse: Decodable {
    let errorCode: String?
    let message: String?
    let errorDescription: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case message
        case errorDescription = "error_description"
        case msg
    }
}

private struct AppSettings: Decodable {
    let maintenanceEnabled: Bool
    let maintenanceMessage: String

    enum CodingKeys: String, CodingKey {
        case maintenanceEnabled = "maintenance_enabled"
        case maintenanceMessage = "maintenance_message"
    }
}

private enum SessionKeychain {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "de.wertweit.app",
            kSecAttrAccount as String: "supabase-auth-session"
        ]
    }

    static func load() throws -> WertweitAuthSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SessionKeychainError.operationFailed(status)
        }
        return try JSONDecoder().decode(WertweitAuthSession.self, from: data)
    }

    static func save(_ session: WertweitAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SessionKeychainError.operationFailed(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionKeychainError.operationFailed(status)
        }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionKeychainError.operationFailed(status)
        }
    }
}

private enum SessionKeychainError: Error {
    case operationFailed(OSStatus)
}

private enum SupabaseRequestError: Error {
    case invalidConfiguration
    case invalidResponse(Int, SupabaseErrorResponse?)
    case incompleteSession
    case missingSettings
}

private enum AuthOperation {
    case signIn
    case signUp
    case verifyEmail
    case resendEmail
}
