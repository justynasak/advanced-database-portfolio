-- Query 1: order history for one customer
EXPLAIN ANALYZE SELECT o.order_id, o.order_date, o.status
FROM orders o WHERE o.customer_id = 4521;

-- Index added after the baseline run
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
