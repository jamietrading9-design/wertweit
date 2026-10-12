import StoreKit
import SwiftUI

private enum CurrencySide: String, Identifiable {
    case source
    case target

    var id: String { rawValue }
}

private enum LegalPage: String, Identifiable {
    case imprint = "Impressum"
    case privacy = "Datenschutz"

    var id: String { rawValue }
}

private enum AppSheet: Identifiable {
    case currencies(CurrencySide)
    case legal(LegalPage)
    case pro
    case support

    var id: String {
        switch self {
        case .currencies(let side): "currency-\(side.id)"
        case .legal(let page): "legal-\(page.id)"
        case .pro: "pro"
        case .support: "support"
        }
    }
}

private struct DecimalPad: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content.keyboardType(.decimalPad)
        #else
        content
        #endif
    }
}

struct PhoneContentView: View {
    @StateObject private var model = ExchangeViewModel()
    @StateObject private var subscriptionStore = SubscriptionStore()
    @ObservedObject var authStore: SupabaseSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeSheet: AppSheet?
    @State private var searchText = ""
    @State private var showLoadingPage = true
    @State private var showDeleteAccountConfirmation = false
    @State private var supportSubject = ""
    @State private var supportBody = ""
    @State private var supportSending = false
    private let ink = Color(red: 0.10, green: 0.16, blue: 0.15)
    private let green = Color(red: 0.12, green: 0.39, blue: 0.30)
    private let lime = Color(red: 0.80, green: 0.91, blue: 0.39)
    private let canvas = Color(red: 0.95, green: 0.96, blue: 0.93)

    private var privacyRevisionDate: String {
        let now = Date.now
        let dayAndMonth = now.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
        let year = String(Calendar.current.component(.year, from: now))
        return "\(dayAndMonth) \(year)"
    }

    private var filteredCurrencies: [CurrencyOption] {
        guard !searchText.isEmpty else { return model.currencies }
        return model.currencies.filter {
            $0.code.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView {
                    calculatorPage
                        .tabItem { Label("Rechner", systemImage: "arrow.left.arrow.right") }
                    TravelView(model: model, hasProAccess: subscriptionStore.hasProAccess) {
                        activeSheet = .pro
                    }
                        .tabItem { Label("Reise", systemImage: "airplane") }
                    ExchangeToolsView(model: model, hasProAccess: subscriptionStore.hasProAccess) {
                        activeSheet = .pro
                    }
                        .tabItem { Label("Wechseln", systemImage: "percent") }
                    MoreFeaturesView(model: model, hasProAccess: subscriptionStore.hasProAccess) {
                        activeSheet = .pro
                    }
                        .tabItem { Label("Übersicht", systemImage: "chart.xyaxis.line") }
                }
                .tint(green)
                footer
            }
        }
        .onTapGesture {
            dismissKeyboard()
        }
        .preferredColorScheme(.light)
        .overlay {
            if showLoadingPage {
                loadingPage
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await authStore.refreshAccountAccess()
            subscriptionStore.setAdminPro(until: authStore.adminProUntil)
            await authStore.refreshSupportThreads()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showLoadingPage = false
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.refreshRate()
                Task { await authStore.refreshMaintenanceStatus() }
                Task {
                    await authStore.refreshAccountAccess()
                    subscriptionStore.setAdminPro(until: authStore.adminProUntil)
                    await authStore.refreshSupportThreads()
                }
                Task { await subscriptionStore.refreshEntitlements() }
            }
        }
        .onChange(of: subscriptionStore.hasProAccess) { hasProAccess in
            if hasProAccess, activeSheet?.id == AppSheet.pro.id {
                activeSheet = nil
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .currencies(let side):
                currencyPicker(forSource: side == .source)
            case .legal(let page):
                legalPage(page)
            case .pro:
                ProPaywallView(
                    store: subscriptionStore,
                    onShowPrivacy: { activeSheet = .legal(.privacy) },
                    onClose: { activeSheet = nil }
                )
            case .support:
                supportView
            }
        }
        .alert("Kursziel erreicht", isPresented: Binding(
            get: { model.triggeredRateAlert != nil },
            set: { isPresented in
                if !isPresented { model.dismissTriggeredRateAlert() }
            }
        )) {
            Button("OK", role: .cancel) { model.dismissTriggeredRateAlert() }
        } message: {
            Text(model.triggeredRateAlert ?? "")
        }
        .confirmationDialog(
            "Wertweit-Konto löschen?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Konto endgültig löschen", role: .destructive) {
                Task { await authStore.deleteAccount() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Wertweit-Konto und deine Kontodaten werden gelöscht. Ein App-Store-Abo musst du separat bei Apple kündigen.")
        }
        .alert("Konto", isPresented: Binding(
            get: { authStore.statusMessage != nil },
            set: { isPresented in
                if !isPresented { authStore.clearStatusMessage() }
            }
        )) {
            Button("OK", role: .cancel) { authStore.clearStatusMessage() }
        } message: {
            Text(authStore.statusMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("WertweitLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("Wertweit")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Spacer()

            Button {
                model.refreshRate()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(green)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wechselkurse aktualisieren")

            Menu {
                Button {
                    activeSheet = .legal(.imprint)
                } label: {
                    Label("Impressum", systemImage: "doc.text")
                }

                Button {
                    activeSheet = .legal(.privacy)
                } label: {
                    Label("Datenschutz", systemImage: "hand.raised")
                }

                Button {
                    activeSheet = .support
                    Task { await authStore.refreshSupportThreads() }
                } label: {
                    Label("Support", systemImage: "questionmark.circle")
                }

                if let email = authStore.session?.user.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.6))
                }

                Button {
                    Task { await authStore.signOut() }
                } label: {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    Label("Konto löschen", systemImage: "person.crop.circle.badge.minus")
                }

                if subscriptionStore.hasProAccess {
                    Label("Wertweit Pro aktiv", systemImage: "checkmark.seal.fill")
                }

                Button {
                    Task { await subscriptionStore.restorePurchases() }
                } label: {
                    Label("Käufe wiederherstellen", systemImage: "arrow.clockwise")
                }

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Label("Abo verwalten", systemImage: "creditcard")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Menü")
            .alert("Wertweit Pro", isPresented: Binding(
                get: { subscriptionStore.message != nil },
                set: { isPresented in
                    if !isPresented { subscriptionStore.dismissMessage() }
                }
            )) {
                Button("OK", role: .cancel) { subscriptionStore.dismissMessage() }
            } message: {
                Text(subscriptionStore.message ?? "")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var appLogoBadge: some View {
        Image("WertweitLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 74, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        VStack(spacing: 1) {
            Text("© \(String(Calendar.current.component(.year, from: .now))) Jamie Lübcke · 1.1")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ink.opacity(0.48))
            .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Button("Impressum") { activeSheet = .legal(.imprint) }
                Button("Datenschutz") { activeSheet = .legal(.privacy) }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(green)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(canvas)
    }

    private var supportView: some View {
        NavigationView {
            Form {
                Section("Neue Nachricht") {
                    TextField("Betreff", text: $supportSubject)
                        .textInputAutocapitalization(.sentences)
                    TextEditor(text: $supportBody)
                        .frame(minHeight: 120)
                    Button {
                        Task {
                            supportSending = true
                            await authStore.sendSupportMessage(subject: supportSubject, body: supportBody)
                            supportSending = false
                            if authStore.statusMessage?.contains("wurde an den Wertweit-Support gesendet") == true {
                                supportSubject = ""
                                supportBody = ""
                            }
                        }
                    } label: {
                        HStack {
                            if supportSending { ProgressView().tint(.white) }
                            Text("Nachricht senden")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(green, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(supportSending || supportSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || supportBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Deine Unterhaltungen") {
                    if authStore.supportThreads.isEmpty {
                        Text("Noch keine Support-Nachrichten.")
                            .foregroundStyle(ink.opacity(0.6))
                    } else {
                        ForEach(authStore.supportThreads) { thread in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(thread.subject)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ink)
                                ForEach(thread.messages) { message in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.senderIsAdmin ? "Wertweit-Support" : "Du")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(green)
                                        Text(message.body)
                                            .font(.system(size: 13))
                                            .foregroundStyle(ink)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(message.senderIsAdmin ? green.opacity(0.08) : canvas,
                                                in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("Wertweit Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") { activeSheet = nil }
                        .foregroundStyle(green)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await authStore.refreshSupportThreads() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(green)
                    }
                    .accessibilityLabel("Support-Nachrichten aktualisieren")
                }
            }
        }
        .tint(green)
    }

    private var loadingPage: some View {
        ZStack {
            canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                appLogoBadge

                Text("Wertweit")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)

                ProgressView()
                    .controlSize(.small)
                    .tint(green)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kursklar wird geladen")
    }

    private var calculatorPage: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                converter
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
        .background(canvas)
    }

    private var converter: some View {
        VStack(spacing: 0) {
            amountRow(label: "ICH HABE", isSource: true) {
                TextField("0,00", text: $model.amountText)
                    .font(.system(size: 29, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.plain)
                    .modifier(DecimalPad())
                    .accessibilityLabel("Betrag in \(model.sourceName)")
            }

                    if !model.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       model.parsedAmount() == nil {
                    Text("Betrag prüfen. Beispiel: 1.234,56")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }

            HStack(spacing: 10) {
                Rectangle().fill(ink.opacity(0.1)).frame(height: 1)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.swapCurrencies()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(green, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Währungen tauschen")
                Rectangle().fill(ink.opacity(0.1)).frame(height: 1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 7)

            amountRow(label: "ICH ERHALTE", isSource: false) {
                Group {
                    if model.rate == nil && model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Wechselkurs wird geladen")
                    } else {
                        HStack(spacing: 8) {
                            Text(model.convertedAmount)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Umgerechneter Betrag: \(model.convertedAmount)")

                            if model.rate == nil {
                                Button {
                                    model.refreshRate()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(green)
                                        .frame(width: 32, height: 32)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Kurs erneut laden")
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.rate == nil && !model.isLoading ? .orange : green)

                VStack(alignment: .leading, spacing: 3) {
                    if let rate = model.rate {
                        Text(model.isUsingCachedRates ? "Gespeicherter EZB-Referenzkurs" : "EZB-Referenzkurs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.72))
                        Text("1 \(model.sourceCode) = \(rate.formatted(.number.precision(.fractionLength(2...5)).locale(Locale(identifier: "de_DE")))) \(model.targetCode)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(ink.opacity(0.82))
                        if let date = model.formattedRateDate {
                            Text("\(model.isUsingCachedRates ? "Gespeichert · " : "")Stand: \(date)")
                                .font(.system(size: 10))
                                .foregroundStyle(ink.opacity(0.5))
                        }
                    } else {
                        Text(model.isLoading ? "EZB-Referenzkurs wird geladen …" : (model.errorMessage ?? "EZB-Referenzkurs nicht verfügbar"))
                            .font(.system(size: 11))
                            .foregroundStyle(model.isLoading ? ink.opacity(0.55) : .orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 9)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ink.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: ink.opacity(0.045), radius: 16, x: 0, y: 7)
    }

    private func amountRow<Value: View>(
        label: String,
        isSource: Bool,
        @ViewBuilder amount: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(ink.opacity(0.48))

            HStack(spacing: 8) {
                amount()

                Button {
                    searchText = ""
                    activeSheet = .currencies(isSource ? .source : .target)
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(isSource ? model.sourceCode : model.targetCode)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(ink)
                            Text(isSource ? model.sourceName : model.targetName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(ink.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(green)
                    }
                    .frame(width: 112, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Währung auswählen")
            }
            .frame(minHeight: 36)
        }
        .padding(.vertical, 15)
    }

    private func currencyPicker(forSource: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Währung auswählen")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Button("Fertig") { activeSheet = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(green)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            TextField("Name oder Kürzel suchen", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            List(filteredCurrencies) { currency in
                Button {
                    model.select(currency.code, forSource: forSource)
                    activeSheet = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(currency.code)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                            .frame(width: 44, alignment: .leading)
                        Text(Locale(identifier: "de_DE").localizedString(forCurrencyCode: currency.code) ?? currency.name)
                            .font(.system(size: 14))
                            .foregroundStyle(ink.opacity(0.78))
                        Spacer()
                        if currency.code == (forSource ? model.sourceCode : model.targetCode) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .background(canvas)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func legalPage(_ page: LegalPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(page.rawValue)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Button("Schließen") { activeSheet = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(green)
                    .buttonStyle(.plain)
            }

            if page == .imprint {
                VStack(alignment: .leading, spacing: 16) {
                    legalSection("Betreiber") {
                        Text("Jamie Lübcke")
                        Text("Bojum 1")
                        Text("24402 Esgrus")
                    }

                    legalSection("Kontakt") {
                        Link("jamie.trading.9@gmail.com", destination: URL(string: "mailto:jamie.trading.9@gmail.com")!)
                        Link("01747685433", destination: URL(string: "tel:01747685433")!)
                    }

                    Text("Privat betriebene App. Es besteht kein Registereintrag und es liegt keine Umsatzsteuer-ID vor.")
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Stand: \(privacyRevisionDate)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ink.opacity(0.5))

                        privacySection("Verantwortlich") {
                            Text("Jamie Lübcke")
                            Text("Bojum 1, 24402 Esgrus")
                            Link("jamie.trading.9@gmail.com", destination: URL(string: "mailto:jamie.trading.9@gmail.com")!)
                        }

                        privacySection("Daten auf deinem Gerät") {
                            Text("Dein eingegebener Betrag wird zur Berechnung vorübergehend im Arbeitsspeicher verarbeitet. Zielwährung, Reiseziel, Favoriten und Kursalarme speichert die App lokal auf deinem Gerät. Der Betrag wird nicht in den App-Einstellungen gespeichert.")
                            Text("Zuletzt erfolgreich geladene Wechselkurse sowie Favoriten und Kursalarme werden lokal gespeichert, damit der Rechner ohne Internetverbindung weiterverwendet werden kann. Diese Inhalte werden nicht mit einem Konto oder Server synchronisiert.")
                        }

                        privacySection("Wertweit-Konto und Supabase") {
                            Text("Für die App ist ein Konto mit E-Mail-Adresse und Passwort erforderlich. Supabase Auth verarbeitet die Anmeldedaten und speichert Konto-ID, E-Mail-Adresse, Registrierungs- und letzte Anmeldezeit. Passwörter werden nicht in der Wertweit-App-Datenbank gespeichert. Administratoren können E-Mail-Adresse und Anmeldezeit im geschützten Adminbereich einsehen.")
                            Text("Die App fragt außerdem den Wartungsstatus von Supabase ab. Ohne Internetverbindung kann eine neu eingeschaltete Wartung nicht sofort auf dem Gerät ankommen; der zuletzt bekannte Zustand bleibt wirksam.")
                        }

                        privacySection("Kursdienst") {
                            Text("Für Währungsliste, aktuelle Kurse und historische Verläufe verbindet sich die App mit api.frankfurter.dev. Übertragen werden die angefragte Währung und bei historischen Kursen der Zeitraum. Dein eingegebener Betrag und der Text deiner lokalen Umrechnungsfrage werden nicht an den Kursdienst gesendet.")
                            Text("Wie bei Internetanfragen üblich, können der Kursdienst und seine Hosting- oder Netzwerkdienstleister technische Verbindungsdaten wie IP-Adresse, Zeitpunkt und angefragte Ressource verarbeiten. Die App selbst bindet keine Analyse- oder Werbedienste ein.")
                            Link("Datenschutzangaben von Frankfurter", destination: URL(string: "https://www.frankfurter.dev/")!)
                                .font(.system(size: 14))
                        }

                        privacySection("Abonnement und Zahlung") {
                            Text("Wenn du ein Wertweit-Pro-Abo abschließt, verarbeitet Apple Zahlung und Abrechnungsdaten über deinen Apple Account. Die App erhält von StoreKit den verifizierten Abo-Status, um Pro-Funktionen freizuschalten. Wir erhalten keine Kartennummer. Dein Wertweit-Konto ist davon getrennt.")
                        }

                        privacySection("Zweck und Rechtsgrundlage") {
                            Text("Die Konto- und Anmeldedaten werden zur Bereitstellung und Absicherung des App-Zugangs verarbeitet. Lokale Einstellungen und gespeicherte Kurse dienen der Rechner- und Reisefunktion. Kursanfragen dienen der angeforderten Umrechnung. Der Kursdienst kann technische Verbindungsdaten nach seinen Datenschutzinformationen verarbeiten.")
                        }

                        privacySection("Speicherdauer und Löschung") {
                            Text("Du kannst dein Wertweit-Konto in der App im Menü löschen. Dabei werden dein Auth-Konto und die dazugehörigen Kontodaten gelöscht. Ein App-Store-Abo musst du separat über Apple kündigen. Favoriten, Kursalarme, Reiseziel, Rechner-Zielwährung und gespeicherte Wechselkurse liegen lokal auf deinem Gerät und werden beim Löschen der App entfernt.")
                        }

                        privacySection("Deine Rechte") {
                            Text("Du kannst im Rahmen der gesetzlichen Voraussetzungen Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung und Datenübertragbarkeit verlangen sowie einer Verarbeitung widersprechen. Eine erteilte Einwilligung kannst du mit Wirkung für die Zukunft widerrufen. Außerdem kannst du dich bei einer Datenschutzaufsichtsbehörde beschweren, insbesondere beim Unabhängigen Landeszentrum für Datenschutz Schleswig-Holstein.")
                            Link("Datenschutzaufsicht Schleswig-Holstein", destination: URL(string: "https://www.datenschutzzentrum.de/")!)
                                .font(.system(size: 14))
                        }

                        privacySection("Berechtigungen und Änderungen") {
                            Text("Die App fordert keinen Zugriff auf Kontakte, Standort, Kamera oder Fotos an. Diese Hinweise werden bei Änderungen an Funktionen, Dienstleistern oder Datenverarbeitung aktualisiert.")
                        }

                        Text("Diese Angaben beschreiben die implementierte App und ersetzen keine rechtliche Prüfung. Vor öffentlicher Verteilung müssen Betreiberangaben und tatsächliche Datenverarbeitung geprüft werden.")
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(canvas.ignoresSafeArea())
    }

    private func legalSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
            content()
                .font(.system(size: 14))
                .foregroundStyle(ink.opacity(0.72))
        }
    }

    private func privacySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 8, content: content)
                .font(.system(size: 13))
                .foregroundStyle(ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum ProBillingPeriod: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }
}

private struct ProPaywallView: View {
    @State private var billingPeriod: ProBillingPeriod = .yearly
    @ObservedObject var store: SubscriptionStore
    let onShowPrivacy: () -> Void
    let onClose: () -> Void

    private let ink = Color(red: 0.10, green: 0.16, blue: 0.15)
    private let green = Color(red: 0.12, green: 0.39, blue: 0.30)
    private let lime = Color(red: 0.80, green: 0.91, blue: 0.39)
    private let canvas = Color(red: 0.95, green: 0.96, blue: 0.93)

    private var monthlyProduct: Product? {
        store.product(for: SubscriptionStore.monthlyProductID)
    }

    private var yearlyProduct: Product? {
        store.product(for: SubscriptionStore.yearlyProductID)
    }

    private var selectedProduct: Product? {
        billingPeriod == .monthly ? monthlyProduct : yearlyProduct
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Wertweit Pro")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ink.opacity(0.65))
                            .frame(width: 34, height: 34)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")
                }

                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(green)
                    Text("WERTWEIT PRO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(green)
                }

                Text("Mehr Überblick auf Reisen.")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Der Währungsrechner bleibt kostenlos. Pro bündelt die Reise- und Analysewerkzeuge.")
                    .font(.system(size: 14))
                    .foregroundStyle(ink.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)

                subscriptionOptions

                VStack(alignment: .leading, spacing: 14) {
                    proBenefit("Reisebudgets, Trinkgeld und Preis-Richtwerte", icon: "airplane")
                    proBenefit("Gebührenvergleich und Rückwärtsrechnung", icon: "percent")
                    proBenefit("Historische Kurse bis zu fünf Jahre", icon: "chart.xyaxis.line")
                    proBenefit("Mehrfachwährungen, Favoriten und Kursziele", icon: "star")
                }

                HStack(spacing: 16) {
                    Button("Datenschutz", action: onShowPrivacy)
                    Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(green)

                Text("Für die App ist ein Wertweit-Konto erforderlich. Abrechnung und Kündigung des Pro-Abos laufen getrennt davon über deinen Apple Account.")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(canvas)
    }

    @ViewBuilder
    private var subscriptionOptions: some View {
        if store.isLoadingProducts {
            HStack(spacing: 10) {
                ProgressView().tint(green)
                Text("Abo-Preise werden von Apple geladen …")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        } else if let product = selectedProduct {
            VStack(alignment: .leading, spacing: 14) {
                if monthlyProduct != nil, yearlyProduct != nil {
                    Picker("Abrechnung", selection: $billingPeriod) {
                        Text("Monatlich").tag(ProBillingPeriod.monthly)
                        Text("Jährlich").tag(ProBillingPeriod.yearly)
                    }
                    .pickerStyle(.segmented)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(product.displayPrice)
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("/ \(billingPeriod == .monthly ? "Monat" : "Jahr")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ink.opacity(0.58))
                }

                Text(store.purchaseDisclosure(for: product))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(green)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await store.purchase(product) }
                } label: {
                    Text(store.isEligibleForFreeTrial(product) ? "Kostenlose Testphase starten" : "Pro-Abo starten")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(lime, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(store.purchaseInProgressFor != nil)

                if store.purchaseInProgressFor == product.id {
                    ProgressView("Kauf wird bestätigt …")
                        .font(.system(size: 12))
                        .tint(green)
                }
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.productLoadMessage ?? "Dieses Abo-Angebot ist derzeit nicht verfügbar.")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Abo-Angebote erneut laden") {
                    Task { await store.loadProducts() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(green)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }

        if let message = store.message {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(green)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button("Käufe wiederherstellen") {
            Task { await store.restorePurchases() }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(green)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    private func proBenefit(_ title: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}