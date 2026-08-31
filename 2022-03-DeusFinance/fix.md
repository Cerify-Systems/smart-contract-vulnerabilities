# Fix

The correct remediation for this class of vulnerability is to remove the lending protocol's dependence on an immediately manipulable DEX spot state.

A lending protocol should not determine collateral value from a single AMM reserve snapshot when a borrower can influence those reserves during the same transaction. Instead, the price source should be resistant to short-term manipulation.

One approach is a time-weighted average price. A TWAP makes a one-block reserve manipulation much less useful because the attacker must sustain the abnormal market state for a meaningful period rather than merely create it temporarily.

Another approach is to use multiple independent price sources. The lending contract can compare prices from independent markets and reject values that deviate beyond an acceptable threshold. This makes it substantially harder for an attacker to manipulate every input simultaneously.

The oracle should also enforce freshness. A price should not be accepted indefinitely simply because it was previously signed or produced. Timestamp and validity-window checks should ensure that stale data cannot be used for current lending decisions.

The lending contract should additionally impose conservative collateralization parameters. Even a robust oracle can experience temporary deviations, so collateral factors should leave sufficient safety margin between the liquidation threshold and the maximum amount that can be borrowed.

For the Deus architecture, the key improvement is to separate the lending system from direct dependence on the instantaneous state of the USDC/DEI pool. The oracle should produce a manipulation-resistant valuation, and `DeiLenderSolidex` should consume that valuation only after validating freshness and acceptable deviation.

## Security Testing

A regression test for this vulnerability should perform the following conceptual test. Create a normal USDC/DEI pool state, record the oracle price, then make a large temporary reserve change inside one transaction. Query the oracle while the manipulation is active and verify that the price used for lending cannot be moved sufficiently to create an unsafe borrowing or liquidation condition.

Additional tests should cover extreme reserve ratios, low-liquidity markets, same-block price changes, stale oracle responses, and disagreement between independent price sources.

The main security lesson is that oracle correctness must be evaluated economically, not only mathematically. A formula can be perfectly correct for its inputs and still be unsafe if an attacker can control those inputs.
