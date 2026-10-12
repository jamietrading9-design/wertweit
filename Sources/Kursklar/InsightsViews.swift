import SwiftUI

private let featureInk = Color(red: 0.10, green: 0.16, blue: 0.15)
private let featureGreen = Color(red: 0.12, green: 0.39, blue: 0.30)
private let featureCanvas = Color(red: 0.95, green: 0.96, blue: 0.93)

private struct TravelDestination: Identifiable, Hashable {
    let country: String
    let flag: String
    let currency: String
    let meal: Double
    let coffee: Double
    let transport: Double
    let tipping: String
    let budget: String
    let moderate: String
    let comfort: String

    var id: String { country }

    static let all: [TravelDestination] = [
        .init(country: "Japan", flag: "🇯🇵", currency: "JPY", meal: 900, coffee: 500, transport: 1800, tipping: "Trinkgeld ist in Japan normalerweise nicht üblich.", budget: "40–60 €", moderate: "80–130 €", comfort: "ab 150 €"),
        .init(country: "USA", flag: "🇺🇸", currency: "USD", meal: 16, coffee: 5, transport: 12, tipping: "In Restaurants sind etwa 18–22 % üblich.", budget: "70–110 €", moderate: "140–230 €", comfort: "ab 280 €"),
        .init(country: "Vereinigtes Königreich", flag: "🇬🇧", currency: "GBP", meal: 13, coffee: 4, transport: 8, tipping: "Service ist teils enthalten; sonst sind etwa 10–12,5 % üblich.", budget: "60–90 €", moderate: "120–190 €", comfort: "ab 240 €"),
        .init(country: "Schweiz", flag: "🇨🇭", currency: "CHF", meal: 24, coffee: 5, transport: 16, tipping: "Trinkgeld ist freiwillig; Aufrunden ist verbreitet.", budget: "100–150 €", moderate: "190–300 €", comfort: "ab 380 €"),
        .init(country: "Polen", flag: "🇵🇱", currency: "PLN", meal: 38, coffee: 14, transport: 12, tipping: "Bei gutem Service sind etwa 10 % üblich.", budget: "35–55 €", moderate: "70–115 €", comfort: "ab 145 €"),
        .init(country: "Thailand", flag: "🇹🇭", currency: "THB", meal: 90, coffee: 80, transport: 220, tipping: "Trinkgeld ist nicht verpflichtend; kleine Beträge werden geschätzt.", budget: "30–50 €", moderate: "65–110 €", comfort: "ab 140 €")
    ]
}

struct TravelView: View {
    @ObservedObject var model: ExchangeViewModel
    let hasProAccess: Bool
    let onUpgrade: () -> Void
    @AppStorage("wertweit.travelCurrency") private var savedTravelCurrency = "USD"

    private var destination: TravelDestination {
        TravelDestination.all.first { $0.currency == model.targetCode }
            ?? TravelDestination.all.first { $0.currency == savedTravelCurrency }
            ?? TravelDestination.all[0]
    }

    private var localAmount: Double? {
        guard let amount = model.parsedAmount() else { return nil }
        return model.convertedValue(amount, to: destination.currency)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                pageTitle("Reise", subtitle: "Was dein Geld vor Ort wert ist")

                Menu {
                    ForEach(TravelDestination.all) { option in
                        Button("\(option.flag)  \(option.country)") {
                            savedTravelCurrency = option.currency
                            model.select(option.currency, forSource: false)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(destination.flag).font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(destination.country).font(.system(size: 17, weight: .semibold, design: .rounded))
                                Text(destination.currency == model.targetCode ? "Mit Rechner-Zielwährung verknüpft" : "Rechner-Zielwährung: \(model.targetCode)")
                                    .font(.system(size: 12)).foregroundStyle(featureInk.opacity(0.54))
                        }
                        Spacer()
                        Text(destination.currency).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(featureGreen)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(featureGreen)
                    }
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 13) {
                    Text("UMRECHNUNG VOR ORT")
                        .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(featureInk.opacity(0.48))
                    if model.parsedAmount() == nil {
                        Text("Bitte einen gültigen Betrag im Rechner eingeben.")
                            .font(.system(size: 14)).foregroundStyle(featureInk.opacity(0.62))
                    } else if let localAmount {
                        Text(localAmount.formatted(.currency(code: destination.currency).locale(Locale(identifier: "de_DE"))))
                            .font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(featureGreen).minimumScaleFactor(0.7).lineLimit(1)
                        if hasProAccess {
                            HStack(spacing: 8) {
                                purchaseEstimate("Essen", count: localAmount / destination.meal, symbol: "fork.knife")
                                purchaseEstimate("Kaffees", count: localAmount / destination.coffee, symbol: "cup.and.saucer")
                                purchaseEstimate("Fahrten", count: localAmount / destination.transport, symbol: "tram")
                            }
                        }
                    } else {
                        Text(model.isLoading ? "Kurs wird geladen …" : "Für diese Währung ist gerade kein Kurs verfügbar.")
                            .font(.system(size: 14)).foregroundStyle(featureInk.opacity(0.62))
                    }
                }
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

                if hasProAccess {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Tagesbudget", detail: "Manuelle Schätzung pro Person")
                        budgetRow("Einfach", value: destination.budget)
                        budgetRow("Mittel", value: destination.moderate)
                        budgetRow("Komfortabel", value: destination.comfort)
                    }
                    .padding(17)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Trinkgeld").font(.system(size: 14, weight: .semibold))
                        Text(destination.tipping).font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.62))
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))

                    Text("Preise, Budgets und Trinkgeldhinweise sind manuelle Schätzungen, keine aktuellen Marktdaten. Sie werden nicht live abgerufen oder laufend geprüft und können je nach Ort und Situation abweichen.")
                        .font(.system(size: 11)).foregroundStyle(featureInk.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                } else {
                    proPrompt(
                        "Mehr Reiseinfos mit Pro",
                        detail: "Preisbeispiele, Tagesbudgets und Trinkgeldhinweise für ausgewählte Ziele.",
                        action: onUpgrade
                    )
                }
            }
            .padding(20)
        }
        .background(featureCanvas)
    }

    private func purchaseEstimate(_ title: String, count: Double, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(featureGreen)
            Text("ca. \(max(0, Int(count)))").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(featureInk)
            Text(title).font(.system(size: 10)).foregroundStyle(featureInk.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(featureCanvas, in: RoundedRectangle(cornerRadius: 11))
    }

    private func budgetRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.68))
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(featureInk)
        }
    }
}

private enum CalculatorMode: String, CaseIterable, Identifiable {
    case fees = "Gebühren"
    case compare = "Vergleich"
    case reverse = "Rückwärts"
    case phrase = "Frage"

    var id: String { rawValue }
}

struct ExchangeToolsView: View {
    @ObservedObject var model: ExchangeViewModel
    let hasProAccess: Bool
    let onUpgrade: () -> Void
    @State private var mode: CalculatorMode = .fees
    @State private var feeText = "2"
    @State private var offeredRateText = ""
    @State private var desiredAmountText = "500"
    @State private var phrase = "Wie viel sind 250 Euro in Dollar?"
    @State private var phraseResult: String?
    @State private var phraseError: String?
    @State private var isParsing = false

    private var referenceRate: Double { model.rate(to: model.targetCode) ?? 0 }
    private var amount: Double? { model.parsedAmount() }
    private var feePercent: Double { Double(feeText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var offeredRate: Double { Double(offeredRateText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                pageTitle("Geld wechseln", subtitle: "Gebühren und Kurse besser einschätzen")
                if hasProAccess {
                    HStack(spacing: 5) {
                        ForEach(CalculatorMode.allCases) { option in
                            Button(option.rawValue) { mode = option }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(mode == option ? .white : featureInk.opacity(0.68))
                                .padding(.horizontal, 10).padding(.vertical, 9)
                                .background(mode == option ? featureGreen : .white, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Gebühren-Simulator · kostenlos")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(featureGreen)
                }

                if hasProAccess {
                    switch mode {
                    case .fees: feesPanel
                    case .compare: comparePanel
                    case .reverse: reversePanel
                    case .phrase: phrasePanel
                    }
                } else {
                    feesPanel
                    proPrompt(
                        "Mehr Wechselwerkzeuge mit Pro",
                        detail: "Kursangebote vergleichen, Zielbeträge zurückrechnen und Umrechnungen in Alltagssprache eingeben.",
                        action: onUpgrade
                    )
                }
                Text("Ergebnisse dienen der Orientierung. Gebühren und Aufschläge unterscheiden sich je nach Anbieter.")
                    .font(.system(size: 11)).foregroundStyle(featureInk.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(featureCanvas)
    }

    private var feesPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("Gebühren-Simulator", detail: "\(model.sourceCode) → \(model.targetCode)")
            labeledInput("Gebühr in Prozent", text: $feeText, suffix: "%")
            if let amount {
                resultRow("Ausgangsbetrag", value: money(amount, model.sourceCode))
                resultRow("Gebühr", value: "− \(money(amount * feePercent / 100, model.sourceCode))")
                resultRow("Nach Gebühr", value: money(amount * (1 - feePercent / 100), model.sourceCode))
                Divider()
                resultRow("Voraussichtlicher Zielbetrag", value: referenceRate > 0 ? money(amount * (1 - feePercent / 100) * referenceRate, model.targetCode) : "Kein aktueller Kurs")
            } else {
                Text("Bitte einen gültigen Betrag im Rechner eingeben.")
                    .font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.58))
            }
        }
        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var comparePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("Kursangebot vergleichen", detail: "Referenz: 1 \(model.sourceCode) = \(referenceRate.formatted(.number.precision(.fractionLength(2...5)))) \(model.targetCode)")
            labeledInput("Angebotener Kurs", text: $offeredRateText, suffix: model.targetCode)
            if amount == nil {
                Text("Bitte einen gültigen Betrag im Rechner eingeben.")
                    .font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.58))
            } else if referenceRate > 0, offeredRate > 0, let amount {
                resultRow("Zum Referenzkurs", value: money(amount * referenceRate, model.targetCode))
                resultRow("Zum angebotenen Kurs", value: money(amount * offeredRate, model.targetCode))
                let difference = amount * (referenceRate - offeredRate)
                resultRow("Unterschied", value: "\(money(abs(difference), model.targetCode)) \(difference >= 0 ? "weniger" : "mehr")")
                resultRow("Abweichung", value: "\((1 - offeredRate / referenceRate).formatted(.percent.precision(.fractionLength(1))))")
            } else {
                Text("Gib den angebotenen Kurs ein, um den Vergleich zu sehen.")
                    .font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.58))
            }
        }
        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var reversePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("Zielbetrag rückwärts rechnen", detail: "Wie viel \(model.sourceCode) brauchst du?")
            labeledInput("Gewünschter Betrag in \(model.targetCode)", text: $desiredAmountText, suffix: model.targetCode)
            let desired = Double(desiredAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            if referenceRate > 0 {
                resultRow("Ohne Gebühr", value: money(desired / referenceRate, model.sourceCode))
                resultRow("Mit \(feePercent.formatted()) % Gebühr", value: money(desired / referenceRate / max(0.01, 1 - feePercent / 100), model.sourceCode))
            } else {
                Text("Kein aktueller Referenzkurs verfügbar.").font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.58))
            }
        }
        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var phrasePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Natürlich fragen", detail: "Einfache lokale Erkennung, ohne Konto")
            TextField("250 Euro in Dollar", text: $phrase)
                .font(.system(size: 14)).padding(12)
                .background(featureCanvas, in: RoundedRectangle(cornerRadius: 10))
            Button {
                Task { await parsePhrase() }
            } label: {
                HStack(spacing: 8) {
                    if isParsing { ProgressView().tint(.white) }
                    Text("Berechnen").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(12).background(featureGreen, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            if let phraseResult {
                Text(phraseResult).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(featureGreen)
            }
            if let phraseError {
                Text(phraseError).font(.system(size: 13)).foregroundStyle(.orange)
            }
        }
        .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func parsePhrase() async {
        phraseError = nil
        phraseResult = nil
        guard let parsed = LocalCurrencyQuery.parse(phrase) else {
            phraseError = "Bitte Betrag und bekannte Währungen nennen, z. B. „250 Euro in Dollar“."
            return
        }
        isParsing = true
        defer { isParsing = false }
        do {
            let snapshot = try await CurrencyService().latestRates(base: parsed.source)
            guard let rate = snapshot.rates[parsed.target] else {
                phraseError = "Für dieses Währungspaar gibt es gerade keinen Referenzkurs."
                return
            }
            phraseResult = "\(money(parsed.amount, parsed.source)) = \(money(parsed.amount * rate, parsed.target))"
        } catch {
            phraseError = "Kurse konnten nicht geladen werden. Bitte Internetverbindung prüfen."
        }
    }
}

private struct LocalCurrencyQuery {
    let amount: Double
    let source: String
    let target: String

    static func parse(_ text: String) -> LocalCurrencyQuery? {
        let lower = text.lowercased()
        let amountPattern = #"\d+(?:[.,]\d{3})*(?:[.,]\d+)?"#
        guard let range = lower.range(of: amountPattern),
              let amount = Double(lower[range].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) else { return nil }

        let names: [(String, String)] = [
            ("euro", "EUR"), ("eur", "EUR"), ("€", "EUR"),
            ("dollar", "USD"), ("usd", "USD"), ("\u{24}", "USD"),
            ("yen", "JPY"), ("jpy", "JPY"), ("\u{00a5}", "JPY"),
            ("pfund", "GBP"), ("gbp", "GBP"), ("£", "GBP"),
            ("franken", "CHF"), ("chf", "CHF"),
            ("zloty", "PLN"), ("pln", "PLN"), ("baht", "THB"), ("thb", "THB")
        ]
        let found = names.filter { lower.contains($0.0) }.map(\.1)
        guard found.count >= 2, found[0] != found[1] else { return nil }
        return LocalCurrencyQuery(amount: amount, source: found[0], target: found[1])
    }
}

struct MoreFeaturesView: View {
    @ObservedObject var model: ExchangeViewModel
    let hasProAccess: Bool
    let onUpgrade: () -> Void
    @AppStorage("wertweit.favoritePairs") private var favoritePairs = "EUR-USD,EUR-GBP,EUR-JPY"
    @AppStorage("wertweit.rateAlerts") private var savedAlerts = ""
    @State private var history: [HistoricalRatePoint] = []
    @State private var historyDays = 7
    @State private var historyError: String?
    @State private var historyLoading = false
    @State private var multiCodes = ["USD", "GBP", "JPY", "CHF", "PLN"]
    @State private var newAlertThreshold = ""
    @State private var selectedCurrency = ""

    private var favorites: [String] {
        favoritePairs.split(separator: ",").map(String.init)
    }

    private var alerts: [String] {
        savedAlerts.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                pageTitle("Übersicht", subtitle: hasProAccess ? "Verlauf, Favoriten und Kursalarme" : "7-Tage-Verlauf kostenlos")
                historyPanel
                if hasProAccess {
                    multiPanel
                    favoritesPanel
                    alertsPanel
                } else {
                    proPrompt(
                        "Mehr Überblick mit Pro",
                        detail: "Längere Kursverläufe, mehrere Währungen, Favoriten und Kursziele freischalten.",
                        action: onUpgrade
                    )
                }
            }
            .padding(20)
        }
        .background(featureCanvas)
        .task(id: "\(model.sourceCode)-\(model.targetCode)-\(historyDays)") {
            await loadHistory()
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Wechselkurs-Verlauf", detail: "\(model.sourceCode) → \(model.targetCode)")
            HStack(spacing: 6) {
                ForEach([(7, "7T"), (30, "30T"), (365, "1J"), (1825, "5J")].filter { hasProAccess || $0.0 == 7 }, id: \.0) { days, label in
                    Button(label) { historyDays = days }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(historyDays == days ? .white : featureInk.opacity(0.65))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(historyDays == days ? featureGreen : featureCanvas, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            if historyLoading {
                ProgressView().tint(featureGreen).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if history.count > 1 {
                RateLineChart(points: history.map(\.rate))
                    .frame(height: 120)
                let values = history.map(\.rate)
                let change = (values.last! / values.first!) - 1
                HStack {
                    stat("Hoch", value: rateText(values.max() ?? 0))
                    Spacer()
                    stat("Tief", value: rateText(values.min() ?? 0))
                    Spacer()
                    stat("Ø", value: rateText(values.reduce(0, +) / Double(values.count)))
                    Spacer()
                    stat("Veränderung", value: change.formatted(.percent.precision(.fractionLength(1))))
                }
            } else {
                Text(historyError ?? "Für diesen Zeitraum liegen noch keine Kursdaten vor.")
                    .font(.system(size: 12)).foregroundStyle(featureInk.opacity(0.58))
            }
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var multiPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Mehrere Währungen", detail: "Ausgang: \(model.sourceCode)")
                Spacer()
                Menu {
                    ForEach(model.currencies.filter { !multiCodes.contains($0.code) }) { currency in
                        Button("\(currency.code) · \(currency.name)") {
                            multiCodes.append(currency.code)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(featureGreen)
                }
                .accessibilityLabel("Währung hinzufügen")
            }
            ForEach(multiCodes, id: \.self) { code in
                HStack {
                    Text(code).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(featureInk)
                    Spacer()
                    Text(model.parsedAmount().flatMap { model.convertedValue($0, to: code) }.map { money($0, code) } ?? (model.parsedAmount() == nil ? "Betrag prüfen" : "–"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(featureGreen)
                    Button { multiCodes.removeAll { $0 == code } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(featureInk.opacity(0.28))
                    }
                    .buttonStyle(.plain).accessibilityLabel("\(code) entfernen")
                }
                if code != multiCodes.last { Divider() }
            }
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var favoritesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Favoriten", detail: "Auf diesem Gerät gespeichert")
                Spacer()
                Button {
                    let pair = "\(model.sourceCode)-\(model.targetCode)"
                    if !favorites.contains(pair) {
                        favoritePairs = (favorites + [pair]).joined(separator: ",")
                    }
                } label: {
                    Image(systemName: "star.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(featureGreen)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aktuelles Währungspaar als Favorit speichern")
            }
            if favorites.isEmpty {
                Text("Noch keine Favoriten gespeichert.").font(.system(size: 12)).foregroundStyle(featureInk.opacity(0.55))
            } else {
                ForEach(favorites, id: \.self) { pair in
                    HStack {
                        Button {
                            let codes = pair.split(separator: "-")
                            guard codes.count == 2 else { return }
                            model.select(String(codes[0]), forSource: true)
                            model.select(String(codes[1]), forSource: false)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Color(red: 0.72, green: 0.61, blue: 0.27))
                                Text(pair.replacingOccurrences(of: "-", with: " → ")).font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Währungspaar \(pair) auswählen")
                        Spacer()
                        Button { favoritePairs = favorites.filter { $0 != pair }.joined(separator: ",") } label: {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(featureInk.opacity(0.44))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Favorit entfernen")
                    }
                }
            }
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private var alertsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Kursalarme", detail: "Beim Kursabruf geprüft, nicht im Hintergrund")
            HStack(spacing: 8) {
                TextField("Zielkurs", text: $newAlertThreshold)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14)).padding(11)
                    .background(featureCanvas, in: RoundedRectangle(cornerRadius: 9))
                Text(model.targetCode).font(.system(size: 11, weight: .bold)).foregroundStyle(featureInk.opacity(0.6))
                Button {
                    guard let threshold = Double(newAlertThreshold.replacingOccurrences(of: ",", with: ".")), threshold > 0 else { return }
                    let entry = "\(model.sourceCode)-\(model.targetCode)-\(threshold)"
                    if !alerts.contains(entry) {
                        savedAlerts = (alerts + [entry]).joined(separator: "|")
                    }
                    newAlertThreshold = ""
                    model.refreshRate()
                } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(featureGreen, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Kursalarm hinzufügen")
            }
            ForEach(alerts, id: \.self) { alert in
                let parts = alert.split(separator: "-")
                HStack {
                    Image(systemName: "bell").font(.system(size: 12)).foregroundStyle(featureGreen)
                    Text(parts.count == 3 ? "\(parts[0]) → \(parts[1]) mindestens \(parts[2])" : alert)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { savedAlerts = alerts.filter { $0 != alert }.joined(separator: "|") } label: {
                        Image(systemName: "trash").foregroundStyle(featureInk.opacity(0.42))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Kursalarm löschen")
                }
            }
            Text("Ein Ziel wird nach einem frischen Kursabruf einmal gemeldet, sobald der Kurs mindestens den Zielwert erreicht. Im Hintergrund werden keine Kurse überwacht.")
                .font(.system(size: 11)).foregroundStyle(featureInk.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func loadHistory() async {
        historyLoading = true
        historyError = nil
        defer { historyLoading = false }
        do {
            history = try await CurrencyService().historicalRates(base: model.sourceCode, quote: model.targetCode, days: historyDays)
        } catch {
            history = []
            historyError = "Historische Kurse sind gerade nicht verfügbar."
        }
    }

    private func rateText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...4)))
    }
}

private struct RateLineChart: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geometry in
            let minimum = points.min() ?? 0
            let maximum = points.max() ?? 1
            let spread = max(maximum - minimum, 0.000001)
            Path { path in
                for index in points.indices {
                    let x = CGFloat(index) / CGFloat(max(points.count - 1, 1)) * geometry.size.width
                    let y = geometry.size.height - CGFloat((points[index] - minimum) / spread) * (geometry.size.height - 8) - 4
                    if index == points.startIndex { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(featureGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

private func pageTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(featureInk)
        Text(subtitle).font(.system(size: 13)).foregroundStyle(featureInk.opacity(0.55))
    }
    .padding(.bottom, 3)
}

private func sectionTitle(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(featureInk)
        Text(detail).font(.system(size: 11)).foregroundStyle(featureInk.opacity(0.52))
    }
}

private func resultRow(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(title).font(.system(size: 12)).foregroundStyle(featureInk.opacity(0.62))
        Spacer(minLength: 6)
        Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(featureInk).multilineTextAlignment(.trailing)
    }
}

private func stat(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 9)).foregroundStyle(featureInk.opacity(0.5))
        Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(featureInk)
    }
}

private func proPrompt(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        Label("WERTWEIT PRO", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(featureGreen)
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(featureInk)
        Text(detail)
            .font(.system(size: 12))
            .foregroundStyle(featureInk.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
        Button("Pro ansehen", action: action)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(featureGreen)
            .buttonStyle(.plain)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
}

private func labeledInput(_ title: String, text: Binding<String>, suffix: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(featureInk.opacity(0.62))
        HStack(spacing: 8) {
            TextField("0", text: text).keyboardType(.decimalPad).font(.system(size: 15, weight: .medium, design: .rounded))
            Text(suffix).font(.system(size: 11, weight: .semibold)).foregroundStyle(featureInk.opacity(0.5))
        }
        .padding(11).background(featureCanvas, in: RoundedRectangle(cornerRadius: 9))
    }
}

private func money(_ value: Double, _ currency: String) -> String {
    value.formatted(.currency(code: currency).locale(Locale(identifier: "de_DE")))
}