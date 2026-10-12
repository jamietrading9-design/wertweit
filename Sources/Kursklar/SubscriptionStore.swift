import Combine
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let monthlyProductID = "de.wertweit.app.pro.monthly"
    static let yearlyProductID = "de.wertweit.app.pro.yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var hasProAccess = false
    @Published private(set) var isLoadingProducts = true
    @Published private(set) var productLoadMessage: String?
    @Published private(set) var purchaseInProgressFor: String?
    @Published private(set) var message: String?

    private var eligibleTrialProductIDs: Set<String> = []
    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStoreProAccess = false
    private var adminProUntil: Date?
    private var adminProExpiryTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }

        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    func product(for identifier: String) -> Product? {
        products.first { $0.id == identifier }
    }

    func isEligibleForFreeTrial(_ product: Product) -> Bool {
        eligibleTrialProductIDs.contains(product.id)
    }

    func billingPeriod(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.id == Self.yearlyProductID ? "Jahr" : "Monat"
        }

        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "Tag" : "Tage"
        case .week: unit = period.value == 1 ? "Woche" : "Wochen"
        case .month: unit = period.value == 1 ? "Monat" : "Monate"
        case .year: unit = period.value == 1 ? "Jahr" : "Jahre"
        @unknown default: unit = "Abrechnungszeitraum"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)"
    }

    func trialDuration(for product: Product) -> String? {
        guard isEligibleForFreeTrial(product),
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }

        let period = offer.period
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "Tag" : "Tage"
        case .week: unit = period.value == 1 ? "Woche" : "Wochen"
        case .month: unit = period.value == 1 ? "Monat" : "Monate"
        case .year: unit = period.value == 1 ? "Jahr" : "Jahre"
        @unknown default: unit = "Abrechnungszeitraum"
        }
        return "\(period.value) \(unit) kostenlos"
    }

    func purchaseDisclosure(for product: Product) -> String {
        let period = billingPeriod(for: product)
        if let trial = trialDuration(for: product) {
            return "\(trial), danach \(product.displayPrice) pro \(period). Verlängert sich automatisch, bis du über deinen Apple Account kündigst."
        }
        return "\(product.displayPrice) pro \(period). Verlängert sich automatisch, bis du über deinen Apple Account kündigst."
    }

    func loadProducts() async {
        isLoadingProducts = true
        productLoadMessage = nil
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: Self.productIDs)
            products = loadedProducts.sorted { left, right in
                Self.productSortOrder(left.id) < Self.productSortOrder(right.id)
            }

            var eligibleProducts: Set<String> = []
            for product in products {
                guard let subscription = product.subscription,
                      subscription.introductoryOffer?.paymentMode == .freeTrial,
                      await subscription.isEligibleForIntroOffer else { continue }
                eligibleProducts.insert(product.id)
            }
            eligibleTrialProductIDs = eligibleProducts

            let loadedIDs = Set(products.map(\.id))
            if !Self.productIDs.isSubset(of: loadedIDs) {
                productLoadMessage = "Abo-Angebote sind derzeit nicht verfügbar."
            }
        } catch {
            products = []
            eligibleTrialProductIDs = []
            productLoadMessage = "Abo-Angebote konnten nicht geladen werden. Prüfe deine Verbindung und die StoreKit-Produkte."
        }
    }

    func purchase(_ product: Product) async {
        guard purchaseInProgressFor == nil else { return }
        purchaseInProgressFor = product.id
        message = nil
        defer { purchaseInProgressFor = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verifiedTransaction(verification)
                await transaction.finish()
                await refreshEntitlements()
                message = hasProAccess ? "Wertweit Pro ist aktiviert." : "Der Kauf wurde bestätigt. Pro-Zugriff wird aktualisiert."
            case .pending:
                message = "Der Kauf wartet noch auf eine Bestätigung."
            case .userCancelled:
                break
            @unknown default:
                message = "Der Kauf konnte nicht abgeschlossen werden."
            }
        } catch {
            message = "Der Kauf konnte nicht verifiziert werden. Bitte versuche es erneut."
        }
    }

    func restorePurchases() async {
        message = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = hasProAccess
                ? "Dein Wertweit-Pro-Abo wurde wiederhergestellt."
                : "Für diesen Apple Account wurde kein aktives Pro-Abo gefunden."
        } catch {
            message = "Käufe konnten nicht wiederhergestellt werden. Bitte versuche es erneut."
        }
    }

    func refreshEntitlements() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            hasActiveSubscription = true
        }

        hasStoreProAccess = hasActiveSubscription
        updateProAccess()
    }

    func setAdminPro(until value: String?) {
        adminProExpiryTask?.cancel()
        adminProUntil = value.flatMap(Self.parseISO8601Date)
        updateProAccess()

        guard let adminProUntil, adminProUntil > .now else { return }
        let delay = adminProUntil.timeIntervalSinceNow
        adminProExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.adminProUntil = nil
            self?.updateProAccess()
        }
    }

    func dismissMessage() {
        message = nil
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            do {
                let transaction = try verifiedTransaction(result)
                await transaction.finish()
                await refreshEntitlements()
            } catch {
                message = "Eine Abo-Änderung konnte nicht verifiziert werden."
            }
        }
    }

    private func verifiedTransaction(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction): transaction
        case .unverified: throw SubscriptionError.failedVerification
        }
    }

    private func updateProAccess() {
        hasProAccess = hasStoreProAccess || (adminProUntil.map { $0 > .now } ?? false)
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func productSortOrder(_ identifier: String) -> Int {
        switch identifier {
        case monthlyProductID: 0
        case yearlyProductID: 1
        default: 2
        }
    }
}

private enum SubscriptionError: Error {
    case failedVerification
}