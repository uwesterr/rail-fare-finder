import RailCore
import SwiftUI

@main
struct RailFinderApp: App {
    var body: some Scene {
        WindowGroup("Rail Fare Finder") {
            SearchView()
                .frame(minWidth: 720, minHeight: 540)
        }
    }
}

private struct SearchView: View {
    @AppStorage("hasDeutschlandticket") private var hasPass = true
    @State private var origin: Station? = .esslingen
    @State private var destination: Station? = .munich
    @State private var start = RailCalendar().nextWeek(after: .now).lowerBound
    @State private var end = RailCalendar().nextWeek(after: .now).upperBound
    @State private var request: TravelQuery?
    @State private var results: SearchResults?
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searching = false
    @State private var order: JourneyOrder = .cheapest
    private let berlin = RailCalendar()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rail Fare Finder").font(.largeTitle.bold())
            Label("Sample data · Times and fares are illustrative", systemImage: "info.circle")
                .foregroundStyle(.secondary)
            HStack(spacing: 20) {
                stationPicker("From", selection: $origin)
                stationPicker("To", selection: $destination)
            }
            HStack(spacing: 16) {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Through", selection: $end, displayedComponents: .date)
                Button("Next week") {
                    let week = berlin.nextWeek(after: .now)
                    start = week.lowerBound
                    end = week.upperBound
                }
            }
            HStack {
                Toggle("I have a Deutschlandticket", isOn: $hasPass)
                Spacer()
                if searching { ProgressView().controlSize(.small) }
                Button("Search fares", action: runSearch)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
            }
            if let results, let request {
                resultList(results, query: request)
            } else {
                Spacer()
            }
        }
        .padding(24)
        .environment(\.timeZone, berlin.calendar.timeZone)
        .environment(\.calendar, berlin.calendar)
        .onChange(of: origin) { clearSearch() }
        .onChange(of: destination) { clearSearch() }
        .onChange(of: start) { clearSearch() }
        .onChange(of: end) { clearSearch() }
        .onChange(of: hasPass) { clearSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private func stationPicker(_ label: String, selection: Binding<Station?>) -> some View {
        Picker(label, selection: selection) {
            Text("Choose a station").tag(nil as Station?)
            ForEach(Station.allCases) { station in
                Text(station.rawValue).tag(Optional(station))
            }
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searching = false
        request = nil
        results = nil
        message = nil
    }

    private func runSearch() {
        clearSearch()
        do {
            let query = try TravelQuery(origin: origin, destination: destination,
                                        start: start, end: end, hasPass: hasPass)
            request = query
            searching = true
            searchTask = Task {
                defer { if !Task.isCancelled { searching = false } }
                do {
                    let found = try await FareSearch(source: SampleJourneySource()).run(query, now: .now)
                    if !Task.isCancelled { results = found }
                } catch is CancellationError {
                    return
                } catch {
                    message = error.localizedDescription
                }
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func resultList(_ results: SearchResults, query: TravelQuery) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                resultSummary(results, query: query)
                ForEach(results.days) { day in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            if day.failed {
                                Text("This date could not be checked.")
                            } else if day.journeys.isEmpty {
                                Text("No journeys found in the sample data.")
                            }
                            ForEach(day.journeys(orderedBy: order)) { offer in
                                journeyRow(offer, query: query)
                            }
                            let window = berlin.bookingWindow(for: day.date)
                            if berlin.day(.now) < window.lowerBound {
                                Text("Last Minute booking window · \(dateLabel(window.lowerBound)) – \(dateLabel(window.upperBound))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Link("Open this date on bahn.de", destination: query.bookingURL(on: day.date))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        let summary = day.cheapest?.fare.map { " · from \(price($0))" } ?? ""
                        Text(dateLabel(day.date) + summary).font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultSummary(_ results: SearchResults, query: TravelQuery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Sort each day by", selection: $order) {
                ForEach(JourneyOrder.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            if results.hasFailedDays {
                Text("Highlights reflect the dates that could be checked.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let cheapest = results.cheapest {
                Text("Cheapest · \(dateLabel(cheapest.journey.departure))").font(.headline)
                journeyRow(cheapest, query: query)
            }
            if let fastest = results.fastest {
                Text("Fastest · \(dateLabel(fastest.journey.departure))").font(.headline)
                journeyRow(fastest, query: query)
            }
        }
    }

    private func journeyRow(_ offer: RankedJourney, query: TravelQuery) -> some View {
        let journey = offer.journey
        let minutes = Int(journey.duration) / 60
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(timeLabel(journey.departure))–\(timeLabel(journey.arrival)) · \(journey.route)")
                Text("\(minutes / 60) h \(minutes % 60) min · Transfers: \(journey.transfers)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(offer.fare.map(price) ?? "Price unavailable").monospacedDigit()
                if let fare = offer.fare {
                    Text(fare.cents == 0 && query.hasPass ? "Covered by Deutschlandticket" : fare.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if query.hasPass && journey.coverage == .unknown {
                    Text("Pass coverage unknown").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func dateLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = berlin.calendar.timeZone
        return date.formatted(style)
    }

    private func timeLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = berlin.calendar.timeZone
        return date.formatted(style)
    }

    private func price(_ fare: Fare) -> String {
        (Decimal(fare.cents) / 100).formatted(.currency(code: "EUR"))
    }
}
