import SwiftUI

private struct NumericContentTransition: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}

private enum CurrencySide: String, Identifiable {
    case source
    case target

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = ExchangeViewModel()
    @State private var pickerSide: CurrencySide?
    @State private var searchText = ""

    private let ink = Color(red: 0.10, green: 0.16, blue: 0.15)
    private let green = Color(red: 0.12, green: 0.39, blue: 0.30)
    private let lime = Color(red: 0.80, green: 0.91, blue: 0.39)

    private var filteredCurrencies: [CurrencyOption] {
        guard !searchText.isEmpty else { return model.currencies }
        return model.currencies.filter {
            $0.code.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.96, blue: 0.93).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.bottom, 58)

                    VStack(alignment: .leading, spacing: 22) {
                        eyebrow("WÄHRUNGSRECHNER", color: green)

                        Text("Geld kennt\nkeine Grenzen.")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .tracking(-1.4)
                            .lineSpacing(-2)
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Schnell umgerechnet. Immer auf dem neuesten Stand.")
                            .font(.system(size: 16))
                            .foregroundStyle(ink.opacity(0.62))
                            .padding(.bottom, 12)

                        converter
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)

                    footer
                        .padding(.top, 28)
                }
                .padding(.horizontal, 52)
                .padding(.top, 30)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.light)
        .sheet(item: $pickerSide) { side in
            currencyPicker(forSource: side == .source)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("WertweitLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text("Wertweit")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(ink)

            Spacer()

            Button {
                model.refreshRate()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.rate == nil || model.isUsingCachedRates ? Color.orange : green)
                        .frame(width: 7, height: 7)
                    Text(model.isUsingCachedRates ? "Gespeicherter Referenzkurs" : model.isLoading ? "Referenzkurs wird geladen" : "EZB-Referenzkurse")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.opacity(0.76))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(green)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(.white.opacity(0.82), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Wechselkurse aktualisieren")
        }
        .frame(maxWidth: 1040)
        .frame(maxWidth: .infinity)
    }

    private var converter: some View {
        VStack(spacing: 0) {
            currencyRow(
                label: "ICH HABE",
                code: model.sourceCode,
                name: model.sourceName,
                isSource: true
            ) {
                TextField("Betrag", text: $model.amountText)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 180, maxWidth: 270)
                    .accessibilityLabel("Betrag in \(model.sourceName)")
            }

                    if !model.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       model.parsedAmount() == nil {
                        Text("Betrag prüfen. Beispiel: 1.234,56")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 26)
                    }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(ink.opacity(0.09))
                    .frame(height: 1)
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                        model.swapCurrencies()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                }
                .buttonStyle(.plain)
                .help("Währungen tauschen")
                Rectangle()
                    .fill(ink.opacity(0.09))
                    .frame(height: 1)
            }
            .padding(.horizontal, 24)
            .zIndex(1)

            currencyRow(
                label: "ICH ERHALTE",
                code: model.targetCode,
                name: model.targetName,
                isSource: false
            ) {
                Text(model.convertedAmount)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(minWidth: 180, maxWidth: 270, alignment: .trailing)
                    .modifier(NumericContentTransition())
                    .accessibilityLabel("Umgerechneter Betrag: \(model.convertedAmount)")
            }

            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(green)

                if let rate = model.rate {
                    Text("1 \(model.sourceCode) = \(rate.formatted(.number.precision(.fractionLength(2...4)).locale(Locale(identifier: "de_DE")))) \(model.targetCode)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.78))
                } else if model.isLoading {
                    Text("Aktueller Kurs wird abgerufen …")
                        .font(.system(size: 13))
                        .foregroundStyle(ink.opacity(0.55))
                } else {
                    Text(model.errorMessage ?? "Kein Kurs verfügbar")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 4)
                Text("\(model.currencies.count) Währungen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.opacity(0.48))
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
        }
        .padding(.vertical, 24)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ink.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: ink.opacity(0.07), radius: 26, x: 0, y: 13)
    }

    private func currencyRow<Value: View>(
        label: String,
        code: String,
        name: String,
        isSource: Bool,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 16) {
            Button {
                searchText = ""
                pickerSide = isSource ? .source : .target
            } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(ink.opacity(0.44))
                        HStack(spacing: 6) {
                            Text(code)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(ink)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(green)
                        }
                        Text(name)
                            .font(.system(size: 12))
                            .foregroundStyle(ink.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 160, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Währung auswählen")

            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .frame(minHeight: 105)
    }

    private func currencyPicker(forSource: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Währung auswählen")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                Spacer()
                Button("Fertig") { pickerSide = nil }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(green)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 14)

            TextField("Währung oder Kürzel suchen", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)

            List(filteredCurrencies) { currency in
                Button {
                    model.select(currency.code, forSource: forSource)
                    pickerSide = nil
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
        .frame(minWidth: 420, minHeight: 470)
        .background(Color(red: 0.97, green: 0.98, blue: 0.96))
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("KLAR UMRECHNEN.")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(green)
                Text("Kurse von Frankfurter · Referenzkurse, keine Gebühren")
                    .font(.system(size: 12))
                    .foregroundStyle(ink.opacity(0.52))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                if let rateDate = model.formattedRateDate {
                    Text("\(model.isUsingCachedRates ? "Gespeichert · " : "")Stand: \(rateDate)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.52))
                }
                Text("1.1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(0.48))
            }
        }
        .frame(maxWidth: 680)
    }

    private func eyebrow(_ title: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Capsule().fill(lime).frame(width: 24, height: 3)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(color)
        }
    }
}