# Portfolio 2: Query Processing and Optimisation

## Case study
NaijaMart, a simulated e-commerce platform (see main README). Database: `naijamart` on PostgreSQL 16.

## 1. Test data
A realistic dataset was generated with SQL (`seed_data.sql`) using `generate_series()` and `random()`. The data is synthetic. Optimisation effects only show on large tables, so volume was needed.

| Table | Rows |
|---|---|
| customers | 20,000 |
| addresses | 20,000 |
| categories | 10 |
| products | 2,000 |
| orders | 100,000 |
| order_items | 300,000 |
| payments | 75,115 |
| deliveries | 50,143 |

Evidence: `row_counts.png`.

Note: the first load of the seed script failed. A hidden byte-order mark in the file stopped the `TRUNCATE` from running, so ID counters did not reset and the products insert violated a foreign key. I removed the BOM and reloaded. This also showed the foreign key constraint rejecting invalid data.

## 2. Method
For each query I ran `EXPLAIN ANALYZE` before and after adding an index and compared the scan type, estimated cost and actual execution time. PostgreSQL only creates indexes automatically for primary keys and UNIQUE columns, so the foreign key columns used in these queries had no index at the start. All statements are in `queries.sql`, which can be rerun from the top because it first drops the experiment indexes. Plans are saved in the `q*.txt` files and `full_run_log.txt`.

## 3. Results

| Query | Purpose | Before | Index added | After |
|---|---|---|---|---|
| Q1 | One customer's orders | Seq Scan, 12.517 ms (cost 2025.00) | `orders(customer_id)` | Bitmap Index Scan, 0.234 ms (cost 23.19) |
| Q2 | Top 10 products by revenue, last 30 days | Seq Scan on orders, 140.428 ms | `orders(order_date)` | Bitmap Index Scan, 113.031 ms |
| Q3 | Count of delivered orders | Seq Scan, 19.642 ms | `orders(status)` | Index Only Scan, 5.007 ms |
| Q3b | Delivered orders with several columns | Seq Scan, 20.963 ms | `orders(status)` | Bitmap Heap Scan, 9.824 ms |

Timings vary slightly between runs. For example, two runs of the same Q3b plan gave 9.8 ms and 11.0 ms.

## 4. Analysis

**Q1 (about 53 times faster).** The query wants 5 rows out of 100,000. Without an index PostgreSQL read every row and discarded 99,995. With the index it went straight to 5 table pages (`Heap Blocks: exact=5`). This is the ideal case for an index: a highly selective filter.

**Q2 (about 20% faster).** The date index worked. The scan of `orders` fell from about 52 ms to about 7.5 ms, because only about 8% of orders fall in the 30-day window. But `orders` was only one step of the query. `order_items` was still read in full (300,000 rows), and the joins and aggregation still had to process about 21,000 rows, so the total improved only modestly. Optimising one step helps in proportion to that step's share of the total time. The primary key on `order_items` already starts with `order_id`, and the planner still chose a hash join, because it estimated that cheaper than index lookups for roughly 7% of the table.

**Q3 and Q3b.** I expected an index on `status` (only 5 distinct values) to be of little use, but it helped. For Q3 the query only needs a count, so PostgreSQL answered it from the index alone (`Index Only Scan`, `Heap Fetches: 0`) without touching the table, and it ran about 4 times faster. For Q3b the index could not cover the query because it needs other columns, so PostgreSQL still had to visit all 775 table pages, since delivered orders are spread across the whole table, and the difference was smaller. My prediction was wrong, and the results showed that whether an index can cover a query matters as much as how selective it is.

**Decision on the status index, and its write cost.** I dropped `idx_orders_status`. Order status changes constantly (PENDING, PAID, SHIPPED, DELIVERED), and every update to an indexed column must also add an entry to that index. To measure this, I updated about 20,000 `PENDING` orders to `PAID` inside a transaction and rolled it back (`write_cost_test.sql`), running it three times each way with a `VACUUM` before each batch. The median execution time was 680.769 ms without the status index and 236.871 ms with it (`write_cost_results.txt`). The `orders` table already had two other indexes, so this difference is the cost of one extra index. The index only helps reporting queries, not core operations such as placing and paying for orders, so I decided the read gains did not justify the write cost. These timings are rough, because they come from a single machine and repeated rollbacks leave dead rows behind.

**Trade-offs of indexing.** Indexes use extra storage and slow down INSERT, UPDATE and DELETE on the table. They should be added for queries that need them, not on every column. The indexes kept are `idx_orders_customer_id` and `idx_orders_order_date`.

## 5. Reproduce
1. Load `portfolio-1-database-design/schema.sql`, then `seed_data.sql`.
2. Run `queries.sql` with `psql -U postgres -h localhost -d naijamart -f queries.sql`. It drops the experiment indexes first, so each baseline is a true "before".
3. `full_run_log.txt` is a later rerun of this file, so its timings differ slightly from the table above, which uses my original runs.
4. The write-cost test is `write_cost_test.sql`, run with and without `idx_orders_status`.

## 6. Files
- `seed_data.sql`, `queries.sql`, `full_run_log.txt`
- Plan outputs: `q1_before_index.txt`, `q1_after_index.txt`, `q2_before_index.txt`, `q2_after_index.txt`, `q3_before_index.txt`, `q3_after_index.txt`, `q3b_no_index.txt`, `q3b_with_status_index.txt`, `q3b_forced_index.txt`
- Write-cost test: `write_cost_test.sql`, `write_cost_results.txt`
- Screenshot: `row_counts.png`