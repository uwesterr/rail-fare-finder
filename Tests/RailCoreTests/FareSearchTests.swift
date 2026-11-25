import Foundation
import RailCore
import Testing

private let berlin = RailCalendar()

private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    berlin.calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private func query(hasPass: Bool = true, origin: Station = .esslingen, destination: Station = .munich,
                   first: Date = date(12, 2), last: Date = date(12, 2)) throws -> TravelQuery {
    try TravelQuery(origin: origin, destination: destination, start: first, end: last, hasPass: hasPass)
}

@Test func passCoversRegionalJourney() async throws {
    let results = try await FareSearch(source: SampleJourneySource()).run(query(), now: date(11, 25))
    let day = try #require(results.days.first)
    #expect(day.cheapest?.journey.id == "regional")
    #expect(day.cheapest?.fare?.cents == 0)
    #expect(day.journeys.first { $0.journey.id == "mixed" }?.fare?.cents == 2799)
    #expect(day.journeys.first { $0.journey.id == "unpriced" }?.fare == nil)
}

@Test func noPassUsesThroughFare() async throws {
    let results = try await FareSearch(source: SampleJourneySource()).run(query(hasPass: false), now: date(11, 25))
    let day = try #require(results.days.first)
    #expect(day.journeys.first { $0.journey.id == "regional" }?.fare?.cents == 4190)
    #expect(day.journeys.first { $0.journey.id == "mixed" }?.fare?.cents == 3299)
    #expect(day.journeys.first { $0.journey.id == "unpriced" }?.fare == nil)
}

@Test func missingUncoveredQuoteIsUnknown() {
    let journey = Journey(id: "mixed", departure: date(12, 2, 8), arrival: date(12, 2, 10),
                          route: "RE → ICE", transfers: 1, coverage: .mixed,
                          throughFare: Fare(cents: 1999), uncoveredFare: nil)
    #expect(journey.price(hasPass: true) == nil)
    #expect(journey.price(hasPass: false)?.cents == 1999)
}

@Test(arguments: [25, 29]) func nextWeekStartsOnMonday(day: Int) {
    #expect(berlin.nextWeek(after: date(11, day, 12)) == date(11, 30)...date(12, 6))
}

@Test(arguments: [date(11, 27, 23), date(11, 28), date(11, 29, 23), date(11, 30)])
func lastMinuteWindowAndOfferLabel(now: Date) async throws {
    let expected = now >= date(11, 28) && now < date(11, 30)
    let results = try await FareSearch(source: SampleJourneySource()).run(query(), now: now)
    let day = try #require(results.days.first)
    #expect(berlin.isLastMinuteWindow(now: now, travelDate: day.date) == expected)
    #expect(day.journeys.contains { $0.fare?.kind == .lastMinute } == expected)
}

private struct PartialSource: JourneySource {
    let isSample = true

    func journeys(for query: TravelQuery, on day: Date, now: Date) async throws -> [Journey] {
        let number = berlin.calendar.component(.day, from: day)
        if number == 2 { throw CocoaError(.fileReadUnknown) }
        func offer(_ id: String, _ hour: Int, _ duration: Int, _ cents: Int) -> Journey {
            let departure = date(12, number, hour)
            return Journey(id: id, departure: departure, arrival: departure.addingTimeInterval(Double(duration * 60)),
                           route: "ICE", transfers: 0, coverage: .uncovered,
                           throughFare: Fare(cents: cents), uncoveredFare: nil)
        }
        return [
            offer("long", 7, 100, 1000),
            offer("late", 10, 90, 1000),
            offer("early", 8, 90, number == 3 ? 900 : 1000),
            offer("costly", 6, 40, 2000)
        ]
    }
}

@Test func ranksInclusiveRangeAndPreservesFailedDates() async throws {
    let request = try query(first: date(12, 1), last: date(12, 3))
    let results = try await FareSearch(source: PartialSource()).run(request, now: date(11, 25))
    #expect(results.days.map(\.date) == [date(12, 1), date(12, 2), date(12, 3)])
    #expect(results.days[0].journeys.map(\.id) == ["early", "late", "long", "costly"])
    #expect(results.days[1].failed && results.hasFailedDays)
    #expect(results.cheapest?.fare?.cents == 900)
}

@Test func validatesInputAndDistinguishesEmptySearch() async throws {
    #expect(throws: TravelQuery.ValidationError.missingStation) {
        try TravelQuery(origin: nil, destination: .munich, start: date(12, 2), end: date(12, 2), hasPass: true)
    }
    #expect(throws: TravelQuery.ValidationError.sameStation) { try query(destination: .esslingen) }
    #expect(throws: TravelQuery.ValidationError.reversedDates) { try query(last: date(12, 1)) }
    let request = try query(origin: .munich, destination: .esslingen)
    let results = try await FareSearch(source: SampleJourneySource()).run(request, now: date(11, 25))
    #expect(results.days.first?.journeys.isEmpty == true)
    #expect(!results.hasFailedDays)
}

@Test func sampleFlagAndBookingHandoff() async throws {
    let request = try query()
    let results = try await FareSearch(source: SampleJourneySource()).run(request, now: date(11, 25))
    #expect(results.isSample)
    let url = request.bookingURL(on: date(12, 2))
    #expect(url.host == "www.bahn.de")
    var fragment = URLComponents()
    fragment.percentEncodedQuery = try #require(url.fragment())
    let items = try #require(fragment.queryItems)
    #expect(items.contains(URLQueryItem(name: "hd", value: "2026-12-02T00:00:00")))
    #expect(items.contains(URLQueryItem(name: "soid", value: "A=1@L=8001920@")))
    #expect(items.contains(URLQueryItem(name: "zoid", value: "A=1@L=8000261@")))
    #expect(items.contains(URLQueryItem(name: "dltv", value: "true")))
}
