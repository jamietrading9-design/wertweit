import Foundation

struct RateSnapshot: Codable {
    let amount: Double
    let base: String
    let date: String
    let rates: [String: Double]
}

struct HistoricalRatePoint: Identifiable {
    let date: Date
    let rate: Double

    var id: Date { date }
}

enum CurrencyServiceError: LocalizedError {
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Der Kursdienst hat eine ungültige Antwort gesendet."
        case .unavailable: "Wechselkurse sind gerade nicht verfügbar."
        }
    }
}

struct CurrencyService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRates(base: String) async throws -> RateSnapshot {
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
        components.queryItems = [URLQueryItem(name: "base", value: base)]
        let data = try await request(components.url!)
        return try JSONDecoder().decode(RateSnapshot.self, from: data)
    }

    func currencies() async throws -> [String: String] {
        let data = try await request(URL(string: "https://api.frankfurter.dev/v1/currencies")!)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func historicalRates(base: String, quote: String, days: Int) async throws -> [HistoricalRatePoint] {
        let calendar = Calendar(identifier: .gregorian)
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            throw CurrencyServiceError.invalidResponse
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let range = "\(formatter.string(from: startDate))..\(formatter.string(from: endDate))"
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/\(range)")!
        components.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: quote)
        ]
        let data = try await request(components.url!)
        let response = try JSONDecoder().decode(HistoricalResponse.self, from: data)

        return response.rates.compactMap { dateString, values in
            guard let date = formatter.date(from: dateString), let value = values[quote] else { return nil }
            return HistoricalRatePoint(date: date, rate: value)
        }
        .sorted { $0.date < $1.date }
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CurrencyServiceError.unavailable
        }
        return data
    }
}

private struct HistoricalResponse: Decodable {
    let rates: [String: [String: Double]]
}