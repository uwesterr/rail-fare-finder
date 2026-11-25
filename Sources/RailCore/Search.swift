import Foundation

public enum Station: String, CaseIterable, Identifiable, Sendable {
    case esslingen = "Esslingen (Neckar)"
    case munich = "München Hbf"

    public var id: Self { self }

    var evaNumber: String {
        switch self {
        case .esslingen: "8001920"
        case .munich: "8000261"
        }
    }
}

public struct RailCalendar: Sendable {
    public let calendar: Calendar

    public init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    public func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func addingDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }

    public func nextWeek(after now: Date) -> ClosedRange<Date> {
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.end
        return monday...addingDays(6, to: monday)
    }

    public func bookingWindow(for travelDate: Date) -> ClosedRange<Date> {
        let monday = calendar.dateInterval(of: .weekOfYear, for: travelDate)!.start
        return addingDays(-2, to: monday)...addingDays(-1, to: monday)
    }

    public func isLastMinuteWindow(now: Date, travelDate: Date) -> Bool {
        bookingWindow(for: travelDate).contains(day(now))
    }
}

public struct TravelQuery: Sendable {
    public let origin: Station
    public let destination: Station
    public let dates: ClosedRange<Date>
    public let hasPass: Bool

    public enum ValidationError: LocalizedError {
        case missingStation, sameStation, reversedDates

        public var errorDescription: String? {
            switch self {
            case .missingStation: "Choose an origin and destination."
            case .sameStation: "Choose two different stations."
            case .reversedDates: "The last date must be on or after the first date."
            }
        }
    }

    public init(origin: Station?, destination: Station?, start: Date, end: Date, hasPass: Bool) throws {
        guard let origin, let destination else { throw ValidationError.missingStation }
        guard origin != destination else { throw ValidationError.sameStation }
        let berlin = RailCalendar()
        let first = berlin.day(start)
        let last = berlin.day(end)
        guard first <= last else { throw ValidationError.reversedDates }
        self.origin = origin
        self.destination = destination
        self.dates = first...last
        self.hasPass = hasPass
    }

    // Prefill DB's journey planner. DB resolves the results and current fares.
    public func bookingURL(on date: Date) -> URL {
        let berlin = RailCalendar()
        let day = berlin.calendar.dateComponents([.year, .month, .day], from: date)
        var url = URLComponents(string: "https://www.bahn.de/buchung/fahrplan/suche")!
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "sts", value: "true"),
            URLQueryItem(name: "so", value: origin.rawValue),
            URLQueryItem(name: "zo", value: destination.rawValue),
            URLQueryItem(name: "soid", value: "A=1@L=\(origin.evaNumber)@"),
            URLQueryItem(name: "zoid", value: "A=1@L=\(destination.evaNumber)@"),
            URLQueryItem(name: "hd", value: String(format: "%04d-%02d-%02dT00:00:00", day.year!, day.month!, day.day!)),
            URLQueryItem(name: "dltv", value: String(hasPass))
        ]
        url.percentEncodedFragment = fragment.percentEncodedQuery
        return url.url!
    }
}

public enum Coverage: Sendable {
    case covered, mixed, uncovered, unknown
}

public enum FareKind: Sendable {
    case regular, lastMinute

    public var label: String {
        switch self {
        case .regular: "Sample fare"
        case .lastMinute: "Super Sparpreis Last Minute"
        }
    }
}

public struct Fare: Sendable {
    public let cents: Int
    public let kind: FareKind

    public init(cents: Int, kind: FareKind = .regular) {
        self.cents = cents
        self.kind = kind
    }
}

public struct Journey: Identifiable, Sendable {
    public let id: String
    public let departure: Date
    public let arrival: Date
    public let route: String
    public let transfers: Int
    public let coverage: Coverage
    public let throughFare: Fare?
    public let uncoveredFare: Fare?
    public var duration: TimeInterval { arrival.timeIntervalSince(departure) }

    public init(id: String, departure: Date, arrival: Date, route: String, transfers: Int,
                coverage: Coverage, throughFare: Fare?, uncoveredFare: Fare?) {
        self.id = id
        self.departure = departure
        self.arrival = arrival
        self.route = route
        self.transfers = transfers
        self.coverage = coverage
        self.throughFare = throughFare
        self.uncoveredFare = uncoveredFare
    }

    public func price(hasPass: Bool) -> Fare? {
        guard hasPass else { return throughFare }
        switch coverage {
        case .covered: return Fare(cents: 0)
        case .mixed: return uncoveredFare
        case .uncovered: return throughFare
        case .unknown: return nil
        }
    }
}
