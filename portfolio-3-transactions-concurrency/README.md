# Portfolio 3: Transactions and Concurrency

## Case study
NaijaMart, a simulated e-commerce platform (see main README). Database: `naijamart` on PostgreSQL 16. The scenario is placing an order: insert the order, insert its item, and reduce the product's stock. These steps must succeed or fail together.

## Part A: Atomicity (COMMIT and ROLLBACK)
Script: `a_commit_rollback.sql`. Output: `a_commit_rollback_output.txt`. Screenshot: `a_commit_rollback.png`.

| Test | What was run | Result |
|---|---|---|
| A1 | Order for 2 units inside `BEGIN ... COMMIT` | Stock 10 to 8, orders 100,000 to 100,001 |
| A2 | Same steps, then `ROLLBACK` | Stock was 6 inside the transaction, 8 after rollback; order count unchanged |
| A3 | Order for 50 units (stock was 8) | The stock update failed on `products_stock_qty_check` (would have been -42); `ROLLBACK` removed the order and item already inserted |

**Analysis.** A transaction makes several statements behave as one unit (atomicity). In A2 the changes were visible inside the transaction but vanished on `ROLLBACK`. In A3 the failure came from the `CHECK (stock_qty >= 0)` constraint designed in Portfolio 1. The order and item were inserted before the stock update failed, and the rollback removed them, so no order exists without its stock being adjusted. The second error in the output (`current transaction is aborted`) is expected, because after a failure PostgreSQL ignores commands until `ROLLBACK`. Rolled-back inserts still consume `SERIAL` numbers, so order IDs have gaps.

## Part B: Concurrency (two sessions)
Step log: `b_concurrency_steps.md`. Each experiment started from stock = 10 (reset and checked first), with two sessions buying 3 and 4 units at the same time. The correct final stock is 3.

| Experiment | Mechanism | What happened | Final stock | Correct? |
|---|---|---|---|---|
| B1 | None (READ COMMITTED, read then write back) | B overwrote A's update | 6 | No (lost update) |
| B2 | `SELECT ... FOR UPDATE` | B waited for A, then read A's value | 3 | Yes |
| B3 | `REPEATABLE READ` | B's write was rejected with a serialization error | 7 (A's update kept) | Yes, after B retries |
| B4 | Atomic update: `stock_qty = stock_qty - n` | B's update waited for A's lock, then applied to the new value | 3 | Yes |

**Analysis.**
- **B1, the lost update.** Both sessions read 10 before either wrote. A wrote 7, then B wrote 6 from its stale value, wiping out A's sale. Seven units were sold but stock dropped by only 4. Nothing errored, which is what makes this bug dangerous.
- **B2, pessimistic locking.** `FOR UPDATE` locks the row when it is read. B's identical query blocked until A committed, then returned the up-to-date value 7, so the result was correct. The cost is that B waits, and under heavy load many sessions can queue on popular rows.
- **B3, snapshot isolation.** In `REPEATABLE READ` a transaction works from a snapshot taken at its first query. B still saw 10, and when it tried to update a row that A had changed and committed, PostgreSQL raised an error instead of overwriting it. No data was corrupted, but the application has to catch the error and retry the transaction (re-read 7, write 3).
- **B4, atomic update.** The lost update in B1 happened because the new value was calculated in the application from a stale read. In B4 the arithmetic is done by the database. B's update waited for A's row lock, and once A committed, PostgreSQL applied `- 4` to the latest value (7), giving 3. This needs no explicit locking and no retry, and it is the simplest fix when the change is a calculation on the existing value. It does not help when the application must read a value and make a decision before writing (for example, checking that stock is sufficient and then choosing what to do), which is where B2 or B3 is needed.
- **Trade-offs.** Locking (B2) blocks first and gives a correct result without retries. Snapshot isolation (B3) does not block but can fail and need a retry. The atomic update (B4) is the cheapest, but only suits simple arithmetic.

## Evidence
`a_commit_rollback.sql`, `a_commit_rollback_output.txt`, `a_commit_rollback.png`, `b_concurrency_steps.md`, `b1_lost_update.png`, `b2_for_update_blocking.png`, `b2_result.png`, `b3_serialization_error.png`, `b4_waiting.png`, `b4_atomic_update.png`.

## Reflection notes (for the final documentation)
- Typing a statement without `;` left psql waiting and produced a syntax error. I learned to watch the prompt: `*` means inside a transaction, `!` means aborted.
- Starting B3 with stock still at 3 from B2 showed me that each experiment needs a reset and a check first. My first B4 attempt began at 7 instead of 10 and ended at 0, which I checked against 7 - 3 - 4 = 0 before rerunning from a clean 10.