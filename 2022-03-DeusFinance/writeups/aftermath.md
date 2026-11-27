# Aftermath

Following the March 15, 2022 exploit, Deus Finance paused the affected DEI lending functionality. Contemporary reporting stated that the protocol intended to compensate users whose positions were liquidated during the incident.

The incident resulted in approximately $3 million in extracted value and demonstrated that the lending protocol's oracle design was a critical security dependency. The project subsequently worked on changes to its oracle and lending architecture.

The incident also became an important example of the difference between a protocol's internal accounting and its external data dependencies. The lending contract could enforce its collateral rules correctly and still be exploitable when those rules relied on a manipulable price source.

A particularly important lesson from the incident is that flash loans should not be treated as the root cause. Flash loans merely make large temporary capital available. The underlying weakness was that the protocol accepted a price derived from a market state that an attacker could manipulate within the same transaction.

Future lending systems should therefore treat oracle design as a first-class security component. Price feeds should be resistant to temporary market manipulation, should use appropriate time windows or multiple independent sources, and should include freshness and deviation protections before their values are used for borrowing or liquidation decisions.
