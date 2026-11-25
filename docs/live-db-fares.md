# Live Deutsche Bahn fare access

Research date: 25 November 2026.

## Recommendation

Check first whether Deutsche Bahn can provide low-volume access to its partner fare interface for a macOS comparison app that hands booking off to bahn.de. Try Rail Europe ERA if direct access is unavailable and its terms allow the intended booking handoff. Implement the provider only after verifying access and representative live offers. The current app uses sample data.

## Sources assessed

| Source | Verified from the public documentation | Still to verify |
| --- | --- | --- |
| [DB online partner interface](https://int.bahn.de/en/partner-programm/online-partner) | DB describes displaying saver and flexible fares and handing off to bahn.de for booking. Its application asks for a business model and company details. | Eligibility and cost for a personal app, access to production and sandbox, domestic inventory, promotional fare codes and Deutschlandticket-aware pricing. |
| [Rail Europe ERA](https://raileurope.github.io/era-api/) | Rail Europe [announced its integration with DB’s PST interface](https://press.raileurope.com/article/43609-deutsche-bahn-and-rail-europe-forge-continued-strategic-partnership-to-transform-international-rail-travel). Its [test environment requires credentials from Rail Europe](https://raileurope.github.io/era-api/postman/). | Low-volume access, Germany point of sale and domestic offers for the test route, Last Minute, Deutschlandticket, and whether we can send the user to bahn.de for booking. |
| [Omio Meta Search API](https://www.omio.com/corporate/omio-b2b/) | Omio offers real-time travel results, prices and availability for partners, with checkout through Omio or a branded environment. | Eligibility, DB product coverage and whether a DB booking handoff is available for this use case. |
| [DB API Marketplace Timetables](https://developers.deutschebahn.com/db-api-marketplace/apis/product/timetables) | The published endpoints return station and timetable data, including departures and changes. | No bookable fare endpoint was found in the public DB documentation reviewed. |
| [bahn.de Bestpreissuche](https://www.bahn.de/service/informationen-buchung/bestpreissuche) | DB displays the fares it can find for a selected future day. This is the reference for spot checks. | The browser test in this project returned DB access error 751. Keep the booking handoff as a user-facing fallback. |

[OSDM lists DB as a production provider](https://osdm.io/tools/implementations/). This establishes implementation of a standard. An endpoint, credentials and inventory access still come from the provider.

## What to verify with a provider

- Can a low-volume personal or academic macOS app query and display live offers and hand booking off to bahn.de? Is there a minimum volume, fee or commercial requirement?
- Can we get sandbox credentials and then verify production inventory for one adult, second class, one way, in the German point of sale? What are the rate limits, date-range and pagination options, display terms, cache limits and offer expiry rules?
- Does the response identify **Super Sparpreis Last Minute** by a stable code? DB says the offer is sold through its digital channels and online sales partners on weekends for the following week, while inventory lasts. Availability through a particular API still needs verification. [DB Last Minute offer](https://www.bahn.de/angebot/sparpreis-flexpreis/super-sparpreis-lastminute) · [DB offer FAQ](https://int.bahn.de/en/faq/pk/offers)
- Can it quote the uncovered part of a trip when the traveller has a Deutschlandticket? Can it verify that all legs of a regional journey are covered? DB describes those as separate options. Covered regional legs at the start and end can be excluded from the price calculation, which DB describes as the journey between the first and last long-distance stop. [DB’s Deutschlandticket filters](https://www.bahn.de/service/informationen-buchung/filter-deutschland-ticket)

## First live test

1. Use Esslingen (Neckar) → München Hbf for three future travel dates in Europe/Berlin. The original comparison is 1–3 December 2026 during the 28–29 November booking window. Use the same weekday pattern in a later week if provider access comes after that window.
2. Compare results for an identical route, departure, train and passenger configuration on bahn.de and the provider within a short interval. Check one through fare, one covered regional journey, and one mixed journey with a quoted uncovered price. Record discrepancies, offer expiry and the check time.
3. During a valid weekend, verify an actual returned Last Minute offer against DB. Use a second route if no such offer is available on the original one. Absence of a promotional offer can mean the inventory is exhausted or the provider lacks coverage. Confirm using a fare DB displays at the time of the check.
4. Treat a sandbox response as evidence that the integration works. Verify production separately before labelling fares live.

## Swift integration

- Add a provider-backed implementation of `JourneySource` and keep `SampleJourneySource` for offline tests. Extend the station model to carry provider station IDs and extend offers to include fare code, price and currency, retrieval time, expiry if provided, and the booking link. Keep the current Cheapest and Fastest ranking.
- Use the provider’s supported date-range request, or query individual Berlin service dates in line with its limits. Show failed or incomplete dates so users can see what the app compared. Display the lowest verified offer returned and show its timestamp. Keep unpriced journeys eligible for Fastest.
- Show €0 extra only for verified fully covered trips. For a mixed trip, show the provider’s quote for the uncovered scope. Treat a missing quote as unknown. Label a promotion only when the provider identifies it.
- Use Keychain for credentials intended for an individual installation. Keep shared supplier credentials on a backend if the provider issues credentials that cannot be distributed to clients. Keep GitHub Actions on synthetic fixtures and never send supplier secrets to it for ordinary PR checks.
