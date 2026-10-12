import Combine
import Foundation
import UserNotifications

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}

@MainActor
final class ExchangeViewModel: ObservableObject {
    @Published var amountText = "1.000,00"
    @Published private(set) var currencies: [CurrencyOption] = [
        CurrencyOption(code: "EUR", name: "Euro"),
        CurrencyOption(code: "USD", name: "US-Dollar"),
        CurrencyOption(code: "GBP", name: "Britisches Pfund"),
        CurrencyOption(code: "CHF", name: "Schweizer Franken"),
        CurrencyOption(code: "JPY", name: "Japanischer Yen")
    ]
    @Published private(set) var sourceCode = "EUR"
    @Published private(set) var targetCode = "USD"
    @Published private(set) var rate: Double?
    @Published private(set) var rateDate: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUsingCachedRates = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var triggeredRateAlert: String?
    @Published private(set) var rateAlertStatusMessage: String?

    private var rates: [String: Double] = [:]
    private var ratesTask: Task<Void, Never>?
    private let germanLocale = Locale(identifier: "de_DE")
    private let service = CurrencyService()

    init() {
        if let savedTarget = UserDefaults.standard.string(forKey: "wertweit.targetCurrency"), savedTarget.count == 3 {
            targetCode = savedTarget
        }
        _ = restoreCachedRates(for: sourceCode)

        Task {
            await loadCurrencies()
            await loadRates()
        }
    }

    var convertedAmount: String {
        guard let amount = parseAmount() else {
            return amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "–" : "Betrag prüfen"
        }
        guard let rate else { return "–" }
        return (amount * rate).formatted(.currency(code: targetCode).locale(germanLocale))
    }

    var sourceName: String { currencyName(for: sourceCode) }
    var targetName: String { currencyName(for: targetCode) }
    var availableRates: [String: Double] { rates }

    var formattedRateDate: String? {
        guard let rateDate else { return nil }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: rateDate) else { return rateDate }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    func rate(to code: String) -> Double? {
        rates[code]
    }

    func convertedValue(_ amount: Double, to code: String) -> Double? {
        guard let rate = rates[code] else { return nil }
        return amount * rate
    }

    func parsedAmount() -> Double? { parseAmount() }

    func select(_ code: String, forSource: Bool) {
        if forSource {
            guard sourceCode != code else { return }
            sourceCode = code
            refreshRate()
        } else {
            targetCode = code
            UserDefaults.standard.set(code, forKey: "wertweit.targetCurrency")
            updateDisplayedRate()
        }
    }

    func swapCurrencies() {
        let previousSource = sourceCode
        sourceCode = targetCode
        targetCode = previousSource
        UserDefaults.standard.set(targetCode, forKey: "wertweit.targetCurrency")
        refreshRate()
    }

    func refreshRate() {
        ratesTask?.cancel()
        ratesTask = Task { await loadRates() }
    }

    func dismissTriggeredRateAlert() {
        triggeredRateAlert = nil
    }

    func dismissRateAlertStatusMessage() {
        rateAlertStatusMessage = nil
    }

    func addRateAlert(targetCode: String, threshold: Double) async -> Bool {
        guard threshold.isFinite, threshold > 0 else {
            rateAlertStatusMessage = "Bitte gib einen gültigen Zielkurs ein."
            return false
        }

        let notificationCenter = UNUserNotificationCenter.current()
        do {
            let settings = await notificationCenter.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            case .denied:
                rateAlertStatusMessage = "Benachrichtigungen sind ausgeschaltet. Aktiviere sie in den iPhone-Einstellungen für Wertweit."
                return false
            case .notDetermined:
                guard try await notificationCenter.requestAuthorization(options: [.alert, .sound]) else {
                    rateAlertStatusMessage = "Ohne Benachrichtigungs-Erlaubnis kann Wertweit dich nicht über erreichte Kursziele informieren."
                    return false
                }
            @unknown default:
                rateAlertStatusMessage = "Der Benachrichtigungsstatus konnte nicht ermittelt werden."
                return false
            }
        } catch {
            rateAlertStatusMessage = "Die Benachrichtigungserlaubnis konnte nicht eingerichtet werden: \(error.localizedDescription)"
            return false
        }

        let defaults = UserDefaults.standard
        let savedAlerts = defaults.string(forKey: "wertweit.rateAlerts") ?? ""
        let alerts = savedAlerts.split(separator: "|").map(String.init)
        let entry = "\(sourceCode)-\(targetCode)-\(threshold)"
        guard !alerts.contains(entry) else {
            rateAlertStatusMessage = "Dieser Kursalarm ist bereits gespeichert."
            return false
        }

        defaults.set((alerts + [entry]).joined(separator: "|"), forKey: "wertweit.rateAlerts")
        rateAlertStatusMessage = "Kursalarm gespeichert. Er wird beim nächsten Kursabruf geprüft; im Hintergrund werden Kurse nicht überwacht."
        refreshRate()
        return true
    }

    private func parseAmount() -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = germanLocale
        formatter.numberStyle = .decimal
        guard let value = formatter.number(from: amountText)?.doubleValue,
              value.isFinite,
              value >= 0 else { return nil }
        return value
    }

    private func currencyName(for code: String) -> String {
        germanLocale.localizedString(forCurrencyCode: code)
            ?? currencies.first(where: { $0.code == code })?.name
            ?? code
    }

    private func loadCurrencies() async {
        do {
            let names = try await service.currencies()
            currencies = names.keys.sorted().map { code in
                CurrencyOption(code: code, name: names[code] ?? code)
            }
        } catch {
            errorMessage = "Währungsliste konnte nicht geladen werden."
        }
    }

    private func loadRates() async {
        let requestedSource = sourceCode
        isLoading = true
        errorMessage = nil
        if !restoreCachedRates(for: requestedSource) {
            rates = [:]
            rate = nil
            rateDate = nil
            isUsingCachedRates = false
        }
        defer { isLoading = false }

        do {
            let payload = try await service.latestRates(base: requestedSource)
            guard requestedSource == sourceCode else { return }
            rates = payload.rates
            rates[requestedSource] = 1
            rateDate = payload.date
            isUsingCachedRates = false
            if let data = try? JSONEncoder().encode(payload) {
                UserDefaults.standard.set(data, forKey: cacheKey(for: requestedSource))
            }
            updateDisplayedRate()
            checkRateAlerts()
        } catch is CancellationError {
            return
        } catch {
            guard requestedSource == sourceCode else { return }
            if restoreCachedRates(for: requestedSource) {
                errorMessage = "Offline. Gespeicherter Kurs wird verwendet."
                return
            }
            errorMessage = "Kurse gerade nicht verfügbar. Bitte erneut versuchen."
            rate = nil
        }
    }

    private func restoreCachedRates(for base: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: base)),
              let snapshot = try? JSONDecoder().decode(RateSnapshot.self, from: data),
              snapshot.base == base else { return false }

        rates = snapshot.rates
        rates[base] = 1
        rateDate = snapshot.date
        isUsingCachedRates = true
        updateDisplayedRate()
        return true
    }

    private func cacheKey(for base: String) -> String {
        "wertweit.rateCache.\(base)"
    }

    private func updateDisplayedRate() {
        rate = rates[targetCode]
    }

    private func checkRateAlerts() {
        let defaults = UserDefaults.standard
        let savedAlerts = defaults.string(forKey: "wertweit.rateAlerts") ?? ""
        let entries = savedAlerts.split(separator: "|").map(String.init)
        var pendingAlerts: [String] = []
        var reachedAlerts: [String] = []

        for entry in entries {
            let parts = entry.split(separator: "-")
            guard parts.count == 3,
                  String(parts[0]) == sourceCode,
                  let threshold = Double(parts[2]),
                  let currentRate = rates[String(parts[1])] else {
                pendingAlerts.append(entry)
                continue
            }

            if currentRate >= threshold {
                let currentText = currentRate.formatted(.number.precision(.fractionLength(2...5)).locale(germanLocale))
                let thresholdText = threshold.formatted(.number.precision(.fractionLength(2...5)).locale(germanLocale))
                reachedAlerts.append("\(sourceCode) → \(parts[1]): \(currentText) hat dein Ziel von \(thresholdText) erreicht.")
            } else {
                pendingAlerts.append(entry)
            }
        }

        guard !reachedAlerts.isEmpty else { return }
        defaults.set(pendingAlerts.joined(separator: "|"), forKey: "wertweit.rateAlerts")
        let message = reachedAlerts.joined(separator: "\n")
        triggeredRateAlert = message

        let content = UNMutableNotificationContent()
        content.title = "Kursziel erreicht"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "wertweit-rate-alert-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                triggeredRateAlert = "\(message)\n\nDie Gerätebenachrichtigung konnte nicht gesendet werden: \(error.localizedDescription)"
            }
        }
    }
}