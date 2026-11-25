# Flexible rail fare finder for macOS

## Goal

Find the lowest additional rail fare for an origin, destination, and flexible date range in Germany. Compare regional journeys covered by an existing Deutschlandticket with faster journeys that require a separate fare. Open the chosen journey on bahn.de for booking.

## First release

- Native macOS app built with SwiftUI for local use on the user's Apple Silicon Mac. Start with one adult, second class, and one-way travel.
- Accept an origin, a destination, and an inclusive date range. Require valid, distinct stations and a start date on or before the end date.
- Provide a **Next week** shortcut for the next Monday through Sunday in Europe/Berlin. Accept single-day searches.
- Provide **I have a Deutschlandticket**, on by default on first launch, and remember the user's choice. With it on, show fully covered journeys at €0 additional cost and price mixed journeys using a verified offer for the uncovered portion. With it off, display through fares where available.
- Highlight the cheapest known fare and fastest journey across the selected dates. Let the user sort each day's journeys by Cheapest (default) or Fastest. Cheapest sorts by fare, duration, then departure. Fastest sorts by elapsed journey time including transfers, then fare, then departure. Show departure and arrival times, duration, transfers, fare name when supplied, and additional cost in EUR. Journeys with unknown fares can still qualify as fastest.
- Label verified **Super Sparpreis Last Minute** offers from the fare source. Show the next Saturday–Sunday booking window for the relevant Monday–Sunday travel week where applicable. Calculate eligibility in Europe/Berlin and confirm promotion availability from the source.
- Open the selected search or journey on bahn.de. The app does not purchase tickets.

## Data and implementation

Keep timetable, Deutschlandticket coverage, and fare information separate in the data model. Treat coverage and pricing as unknown when the source lacks evidence. For a mixed journey, price the uncovered portion from a provider quote. Keep source and retrieval time with live results, and display when individual dates could not be checked.

Build the SwiftUI search and results flow against a small deterministic fixture. Mark fixture results as **Sample data** throughout the flow. Put the source behind a Swift interface so a verified provider can replace the fixture. Represent monetary amounts as integer cents. Use a Berlin calendar for service dates and a fixed clock in date-sensitive tests.

Validate live fares separately before describing them as supported. Use a fare source whose access and promotional fare coverage have been confirmed. Deutsche Bahn returned access error 751 during the browser test, so the website automation path remains unverified. DB's Timetables API supplies timetable information. DB's online partner interface documents fare access for partners, and access for this project is open.

## Acceptance tests

Use synthetic offers for automated tests. Run the live checks separately with a permitted source.

| Case | Input | Expected result |
|---|---|---|
| T01 Default and persistence | First launch, then switch Deutschlandticket off and relaunch | The switch starts on and retains the new setting after relaunch. |
| T02 Esslingen test route | Esslingen (Neckar) → München Hbf, 2 December 2026, pass on. Fixture includes a covered regional route via Ulm and a faster paid alternative. | The regional journey shows €0 extra and ranks first. The paid alternative remains visible with its supplied fare. |
| T03 Without the pass | Repeat T02 with the pass off | A regional journey uses its through fare if supplied. Missing prices display as unavailable. |
| T04 Mixed itinerary | Covered regional feeder plus long-distance leg with a separate provider quote | Show the quoted uncovered fare and retain all legs in the itinerary. |
| T05 Unknown coverage or price | A regional-looking segment has unknown coverage, or the mixed journey lacks a quote | Display the unknown status and exclude that itinerary from cheapest-price ranking. |
| T06 Week calculation | Fixed clock on Wednesday 25 November 2026, then on Sunday 29 November 2026 | **Next week** selects 30 November–6 December inclusive in both cases. |
| T07 Last Minute window | Fixed clock on 27, 28, 29 and 30 November 2026, travel date 2 December | The booking window is active on 28–29 November only for that travel week. Only a returned offer identified as Last Minute receives the label. |
| T08 Sorting and date coverage | Three dates with differently priced journeys, tied offers, and one failed date | Sort by price, then duration, then departure. The range includes both endpoints. Mark the failed date and describe the cheapest result as the lowest found among successful dates. |
| T09 Input and empty results | Missing or identical station, reversed range, and a valid search returning no trains | Invalid queries are blocked with a clear message. A valid empty search shows a distinct no-results state. |
| T10 Sample data and booking handoff | Run the fixture search and open a result | Sample status remains visible. The handoff opens bahn.de with the selected route and date where supported. |
| T11 Cheapest and fastest | A range containing a slower €0 regional journey, a faster paid journey, and a still faster journey with an unknown fare | Highlight the €0 journey as cheapest and the shortest journey as fastest. Switching the sort reorders each day's rows without rerunning the search. With equal durations, rank lower known fares first, then earlier departures. |

### Live verification

During the 28–29 November 2026 booking window, use Esslingen (Neckar) → München Hbf for 1–3 December 2026. Compare returned train, departure, fare name, and price against bahn.de with the same traveller settings. Include searches with the Deutschlandticket enabled and disabled. Record missing dates and fares explicitly. If a Last Minute offer is absent on the route, record that and verify promotion identification separately against a confirmed example before marking it supported.

## Delivery

Use a short-lived feature branch and a pull request. Ask the project's `test_reviewer` subagent to run targeted checks and review the implementation against this specification. Run the reproducible Swift tests and build in GitHub Actions on a macOS runner when the remote is configured. Keep fixture-based CI independent of live fare access. Package the first usable build for local Mac use.

## References

- [Deutsche Bahn Bestpreissuche](https://www.bahn.de/service/informationen-buchung/bestpreissuche)
- [Deutsche Bahn Super Sparpreis Last Minute](https://www.bahn.de/angebot/sparpreis-flexpreis/super-sparpreis-lastminute)
- [Deutsche Bahn Deutschlandticket search filters](https://www.bahn.de/service/informationen-buchung/filter-deutschland-ticket)
- [Deutsche Bahn online partner interface](https://int.bahn.de/en/partner-programm/online-partner)
- [Deutsche Bahn Timetables API](https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables)
