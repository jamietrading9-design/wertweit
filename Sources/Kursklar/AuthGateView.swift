import SwiftUI

struct AuthGateView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: SupabaseSessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var emailCode = ""
    @State private var isCreatingAccount = false
    @State private var requestInProgress = false
    @State private var showDeleteAccountConfirmation = false

    private let ink = Color(red: 0.10, green: 0.16, blue: 0.15)
    private let green = Color(red: 0.12, green: 0.39, blue: 0.30)
    private let lime = Color(red: 0.80, green: 0.91, blue: 0.39)
    private let canvas = Color(red: 0.95, green: 0.96, blue: 0.93)

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("Wertweit wird vorbereitet …")
                    .tint(green)
            } else if store.isBlocked {
                blockedView
            } else if store.maintenanceEnabled {
                maintenanceView
            } else if store.session != nil {
                PhoneContentView(authStore: store)
            } else if store.isAwaitingEmailConfirmation {
                emailConfirmationView
            } else {
                signInView
            }
        }
        .task {
            await store.start()
        }
        .onChange(of: store.session?.accessToken) { _ in
            Task {
                await store.refreshMaintenanceStatus()
                await store.refreshAccountAccess()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await store.refreshMaintenanceStatus() }
        }
        .confirmationDialog(
            "Wertweit-Konto löschen?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Konto endgültig löschen", role: .destructive) {
                Task { await store.deleteAccount() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Wertweit-Konto und deine Kontodaten werden gelöscht. Ein App-Store-Abo musst du separat bei Apple kündigen.")
        }
        .alert("Konto", isPresented: Binding(
            get: { store.statusMessage != nil },
            set: { isPresented in
                if !isPresented { store.clearStatusMessage() }
            }
        )) {
            Button("OK", role: .cancel) { store.clearStatusMessage() }
        } message: {
            Text(store.statusMessage ?? "")
        }
        .preferredColorScheme(.light)
    }

    private var blockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 36))
                .foregroundStyle(green)
            Text("Konto gesperrt")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text("Dieses Wertweit-Konto ist derzeit gesperrt. Wenn du glaubst, dass das ein Fehler ist, wende dich an den Support.")
                .font(.system(size: 15))
                .foregroundStyle(ink.opacity(0.68))
                .multilineTextAlignment(.center)
            Button("Abmelden") {
                Task { await store.signOut() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(green, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas.ignoresSafeArea())
    }

    private var signInView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("WertweitLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    Text(isCreatingAccount ? "Konto erstellen" : "Willkommen zurück")
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("Melde dich mit deinem Wertweit-Konto an, um die App zu nutzen.")
                        .font(.system(size: 14))
                        .foregroundStyle(ink.opacity(0.64))
                }

                VStack(alignment: .leading, spacing: 14) {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Passwort (mindestens 8 Zeichen)", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))

                    Button(action: submit) {
                        HStack {
                            if requestInProgress { ProgressView().tint(.white) }
                            Text(isCreatingAccount ? "Konto erstellen" : "Anmelden")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(green, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(requestInProgress || !isValidInput)

                    Button(isCreatingAccount ? "Ich habe schon ein Konto" : "Neues Konto erstellen") {
                        isCreatingAccount.toggle()
                        store.clearStatusMessage()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(green)
                    .frame(maxWidth: .infinity)
                    .disabled(requestInProgress)

                    if !isCreatingAccount {
                        Button("Passwort vergessen?") {
                            Task {
                                requestInProgress = true
                                await store.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                                requestInProgress = false
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .disabled(requestInProgress || !email.contains("@"))
                    }
                }

                if let message = store.configurationError ?? store.statusMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(store.configurationError == nil ? green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(canvas.ignoresSafeArea())
    }

    private var maintenanceView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 36))
                .foregroundStyle(green)
            Text("Kurz in Wartung")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text(store.maintenanceMessage)
                .font(.system(size: 15))
                .foregroundStyle(ink.opacity(0.68))
                .multilineTextAlignment(.center)
            if let email = store.session?.user.email {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.5))
            }

            Button("Erneut prüfen") {
                Task { await store.refreshMaintenanceStatus() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(green)
            if store.session != nil {
                Button("Abmelden") {
                    Task { await store.signOut() }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(green)

                Button("Konto löschen", role: .destructive) {
                    showDeleteAccountConfirmation = true
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvas.ignoresSafeArea())
    }

    private var emailConfirmationView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image("WertweitLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text("E-Mail bestätigen")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Text("Gib den Bestätigungscode ein, den wir an \(store.emailConfirmationEmail) gesendet haben.")
                    .font(.system(size: 14))
                    .foregroundStyle(ink.opacity(0.64))
            }

            TextField("Bestätigungscode", text: $emailCode)
                .textContentType(.oneTimeCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                #endif
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: emailCode) { value in
                    emailCode = String(value.filter(\.isNumber).prefix(8))
                }

            Button {
                requestInProgress = true
                Task {
                    await store.confirmEmail(code: emailCode)
                    if !store.isAwaitingEmailConfirmation { emailCode = "" }
                    requestInProgress = false
                }
            } label: {
                HStack {
                    if requestInProgress { ProgressView().tint(.white) }
                    Text("E-Mail bestätigen")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(green, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(requestInProgress || emailCode.isEmpty)

            Button("Neuen Code senden") {
                requestInProgress = true
                Task {
                    await store.resendEmailConfirmation()
                    requestInProgress = false
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(green)
            .frame(maxWidth: .infinity)
            .disabled(requestInProgress)

            Button("Zurück zur Anmeldung") {
                emailCode = ""
                isCreatingAccount = false
                store.cancelEmailConfirmation()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ink.opacity(0.6))
            .frame(maxWidth: .infinity)
            .disabled(requestInProgress)
        }
        .padding(24)
        .frame(maxWidth: 480, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(canvas.ignoresSafeArea())
    }

    private var isValidInput: Bool {
        email.contains("@") && (!isCreatingAccount || password.count >= 8) && !password.isEmpty
    }

    private func submit() {
        guard isValidInput else { return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        requestInProgress = true
        Task {
            if isCreatingAccount {
                await store.signUp(email: normalizedEmail, password: password)
            } else {
                await store.signIn(email: normalizedEmail, password: password)
            }
            requestInProgress = false
        }
    }
}
