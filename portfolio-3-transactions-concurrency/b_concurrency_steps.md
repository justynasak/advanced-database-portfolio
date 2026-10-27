# Portfolio 3, Part B: Concurrency Experiments (step log)

Two `psql` sessions (A and B) were open at the same time against the `naijamart` database. The tested row was `products.product_id = 1`. Before each experiment the stock was reset to 10 and checked with a SELECT.

## B1: Lost update (no protection)
Default isolation level (READ COMMITTED). Both sessions read the stock, compute the new value in their head, and write it back.

| Step | Session A | Session B |
|---|---|---|
| 1 | `BEGIN;` `SELECT stock_qty ...;` returned 10 | |
| 2 | | `BEGIN;` `SELECT stock_qty ...;` returned 10 |
| 3 | `UPDATE ... SET stock_qty = 7;` `COMMIT;` (10 - 3) | |
| 4 | | `UPDATE ... SET stock_qty = 6;` `COMMIT;` (10 - 4) |
| 5 | `SELECT stock_qty ...;` returned **6** | |

Result: 7 units were sold, so stock should be 3. It was 6, because B overwrote A's update using a stale value. Evidence: `b1_lost_update.png`.

## B2: Row locking with SELECT ... FOR UPDATE
| Step | Session A | Session B |
|---|---|---|
| 1 | `BEGIN;` `SELECT ... FOR UPDATE;` returned 10 | |
| 2 | | `BEGIN;` `SELECT ... FOR UPDATE;` **waited** (blocked on A's lock) |
| 3 | `UPDATE ... SET stock_qty = 7;` `COMMIT;` | B's query unblocked and returned 7 |
| 4 | | `UPDATE ... SET stock_qty = 3;` `COMMIT;` (7 - 4) |
| 5 | `SELECT stock_qty ...;` returned **3** | |

Result: correct (10 - 3 - 4 = 3). B had to wait for A. Evidence: `b2_for_update_blocking.png`, `b2_result.png`.

## B3: REPEATABLE READ (snapshot isolation)
| Step | Session A | Session B |
|---|---|---|
| 1 | | `BEGIN ISOLATION LEVEL REPEATABLE READ;` `SELECT ...;` returned 10 |
| 2 | `BEGIN;` `UPDATE ... SET stock_qty = 7;` `COMMIT;` | |
| 3 | | `UPDATE ... SET stock_qty = 6;` failed: `ERROR: could not serialize access due to concurrent update`, then `ROLLBACK;` |
| 4 | `SELECT stock_qty ...;` returned **7** | |

Result: PostgreSQL refused B's write instead of overwriting A's. A's update was preserved, and the application would retry B's purchase. Evidence: `b3_serialization_error.png`.

## Practical notes
- A statement without a final `;` is not executed. The prompt changes to `naijamart-*#` while psql waits for the rest of it.
- After an error inside a transaction (prompt `B!>`), only `ROLLBACK;` works.
- Stock must be reset and confirmed before each experiment. Otherwise a session reads the previous experiment's result.

## B4: Atomic update (arithmetic done inside the database)
| Step | Session A | Session B |
|---|---|---|
| 1 | `BEGIN;` `UPDATE products SET stock_qty = stock_qty - 3 WHERE product_id = 1;` | |
| 2 | | `BEGIN;` `UPDATE ... SET stock_qty = stock_qty - 4 ...;` **waited** for A's lock |
| 3 | `COMMIT;` | B's update completed |
| 4 | | `COMMIT;` `SELECT stock_qty ...;` returned **3** |

Result: correct (10 - 3 - 4 = 3), with no `FOR UPDATE` and no lost update. Evidence: `b4_waiting.png`, `b4_atomic_update.png`.