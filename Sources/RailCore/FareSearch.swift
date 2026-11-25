import Foundation

public protocol JourneySource: Sendable {
    var isSample: Bool { get }
    func journeys(for query: TravelQuery, on day: Date, now: Date) async throws -> [Journey]
}

public struct RankedJourney: Identifiable, Sendable {
    public let journey: Journey
    public let fare: Fare?
    public var id: String { journey.id }
}

public enum JourneyOrder: String, CaseIterable, Identifiable, Sendable {
    case cheapest = "Cheapest"
    case fastest = "Fastest"

    public var id: Self { self }

    fileprivate func ranksBefore(_ left: RankedJourney, _ right: RankedJourney) -> Bool {
        let leftPrice = left.fare?.cents ?? Int.max
        let rightPrice = right.fare?.cents ?? Int.max
        if self == .cheapest && leftPrice != rightPrice { return leftPrice < rightPrice }
        if left.journey.duration != right.journey.duration {
            return left.journey.duration < right.journey.duration
        }
        if leftPrice != rightPrice { return leftPrice < rightPrice }
        return left.journey.departure < right.journey.departure
    }
}

public struct DayResult: Identifiable, Sendable {
    public let date: Date
    public let journeys: [RankedJourney]
    public let failed: Bool
    public var id: Date { date }
    public var cheapest: RankedJourney? { journeys.first { $0.fare != nil } }
    public var fastest: RankedJourney? { journeys.min(by: JourneyOrder.fastest.ranksBefore) }

    public func journeys(orderedBy order: JourneyOrder) -> [RankedJourney] {
        order == .cheapest ? journeys : journeys.sorted(by: order.ranksBefore)
    }
}

public struct SearchResults: Sendable {
    public let days: [DayResult]
    public let isSample: Bool
    public var hasFailedDays: Bool { days.contains(where: \.failed) }
    public var cheapest: RankedJourney? {
        days.compactMap(\.cheapest).min(by: JourneyOrder.cheapest.ranksBefore)
    }
    public var fastest: RankedJourney? {
        days.compactMap(\.fastest).min(by: JourneyOrder.fastest.ranksBefore)
    }
}

public struct FareSearch: Sendable {
    private let source: any JourneySource
    private let berlin = RailCalendar()

    public init(source: any JourneySource) {
        self.source = source
    }

    public func run(_ query: TravelQuery, now: Date) async throws -> SearchResults {
        var days: [DayResult] = []
        var date = query.dates.lowerBound
        while date <= query.dates.upperBound {
            try Task.checkCancellation()
            do {
                let offers = try await source.journeys(for: query, on: date, now: now)
                let ranked = offers.map {
                    RankedJourney(journey: $0, fare: $0.price(hasPass: query.hasPass))
                }.sorted(by: JourneyOrder.cheapest.ranksBefore)
                days.append(DayResult(date: date, journeys: ranked, failed: false))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                days.append(DayResult(date: date, journeys: [], failed: true))
            }
            date = berlin.addingDays(1, to: date)
        }
        return SearchResults(days: days, isSample: source.isSample)
    }

}

public struct SampleJourneySource: JourneySource {
    public let isSample = true
    private let berlin = RailCalendar()

    public init() {}

    public func journeys(for query: TravelQuery, on day: Date, now: Date) async throws -> [Journey] {
        guard query.origin == .esslingen, query.destination == .munich else { return [] }

        func time(_ hour: Int, _ minute: Int) -> Date {
            berlin.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let weekday = berlin.calendar.component(.weekday, from: day)
        let dayFare = 1999 + 200 * weekday
        let promotion = berlin.isLastMinuteWindow(now: now, travelDate: day)
            ? Fare(cents: 699, kind: .lastMinute)
            : nil

        return [
            Journey(id: "regional", departure: time(9, 20), arrival: time(12, 35),
                    route: "MEX 16 → Ulm Hbf → RE 9", transfers: 1,
                    coverage: .covered, throughFare: Fare(cents: 4190), uncoveredFare: nil),
            Journey(id: "mixed", departure: time(10, 5), arrival: time(12, 12),
                    route: "MEX 16 → Ulm Hbf → ICE", transfers: 1,
                    coverage: .mixed, throughFare: promotion ?? Fare(cents: dayFare + 500),
                    uncoveredFare: promotion ?? Fare(cents: dayFare)),
            Journey(id: "express", departure: time(15, 2), arrival: time(16, 22),
                    route: "ICE", transfers: 0, coverage: .uncovered,
                    throughFare: Fare(cents: dayFare + 800), uncoveredFare: nil),
            Journey(id: "unpriced", departure: time(16, 15), arrival: time(19, 35),
                    route: "MEX 16 → Ulm Hbf → RE 9", transfers: 1,
                    coverage: .unknown, throughFare: nil, uncoveredFare: nil)
        ]
    }
}
