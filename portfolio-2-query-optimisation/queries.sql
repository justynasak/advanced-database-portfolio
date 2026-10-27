-- MIT 8103 Portfolio 2: Query Processing and Optimisation
-- Database: naijamart (PostgreSQL 16)
-- Run each statement with: psql -U postgres -h localhost -d naijamart -f queries.sql
-- Data is synthetic (see seed_data.sql).

-- Reset: remove the experiment indexes so every baseline below is a true "before"
DROP INDEX IF EXISTS idx_orders_customer_id;
DROP INDEX IF EXISTS idx_orders_order_date;
DROP INDEX IF EXISTS idx_orders_status;

-- ============================================================
-- Q1: Order history for one customer
-- Baseline: Seq Scan on orders, ~12.5 ms
-- ============================================================
EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, o.status
FROM orders o
WHERE o.customer_id = 4521;

-- Index added after baseline: Bitmap Index Scan, ~0.23 ms
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
ANALYZE orders;

-- ============================================================
-- Q2: Top 10 products by revenue in the last 30 days
-- Baseline: Seq Scan on orders, ~140 ms
-- ============================================================
EXPLAIN ANALYZE
SELECT p.product_id, p.name, SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN orders o   ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_date >= now() - interval '30 days'
  AND o.status <> 'CANCELLED'
GROUP BY p.product_id, p.name
ORDER BY revenue DESC
LIMIT 10;

-- Index added: Bitmap Index Scan on orders, ~113 ms
CREATE INDEX idx_orders_order_date ON orders(order_date);
ANALYZE orders;

-- ============================================================
-- Q3: Count of delivered orders (index-only scan candidate)
-- Baseline: Seq Scan, ~19.6 ms
-- ============================================================
EXPLAIN ANALYZE
SELECT count(*) FROM orders WHERE status = 'DELIVERED';

-- Experimental index (later dropped, see decision below)
CREATE INDEX idx_orders_status ON orders(status);
ANALYZE orders;

-- With index: Index Only Scan, ~5.0 ms
EXPLAIN ANALYZE
SELECT count(*) FROM orders WHERE status = 'DELIVERED';

-- ============================================================
-- Q3b: Delivered orders with extra columns (index cannot cover)
-- With index: Bitmap Heap Scan, ~10 ms (planner chose it unforced)
-- ============================================================
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date
FROM orders
WHERE status = 'DELIVERED';

-- Experiment only: forcing the planner away from sequential scans
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date
FROM orders
WHERE status = 'DELIVERED';
RESET enable_seqscan;

-- ============================================================
-- Decision: idx_orders_status dropped.
-- Order status is updated constantly (PENDING -> PAID -> SHIPPED ->
-- DELIVERED), so every update would also have to maintain this index.
-- The column has only 5 distinct values, so the benefit is limited.
-- ============================================================
DROP INDEX IF EXISTS idx_orders_status;

-- Q3b baseline without the index (for comparison)
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date
FROM orders
WHERE status = 'DELIVERED';