-- Portfolio 3, Part A: atomicity (COMMIT / ROLLBACK)
\echo === Setup: known starting state ===
UPDATE products SET stock_qty = 10 WHERE product_id = 1;
SELECT product_id, stock_qty FROM products WHERE product_id = 1;
SELECT count(*) AS orders_count FROM orders;

\echo === A1: successful order, COMMIT (stock 10 -> 8, orders +1) ===
BEGIN;
INSERT INTO orders(customer_id, address_id) VALUES (1, 1);
INSERT INTO order_items(order_id, product_id, quantity, unit_price)
  SELECT currval(pg_get_serial_sequence('orders','order_id')), product_id, 2, price
  FROM products WHERE product_id = 1;
UPDATE products SET stock_qty = stock_qty - 2 WHERE product_id = 1;
COMMIT;
SELECT stock_qty FROM products WHERE product_id = 1;
SELECT count(*) AS orders_count FROM orders;

\echo === A2: same steps, then ROLLBACK (nothing should change) ===
BEGIN;
INSERT INTO orders(customer_id, address_id) VALUES (1, 1);
INSERT INTO order_items(order_id, product_id, quantity, unit_price)
  SELECT currval(pg_get_serial_sequence('orders','order_id')), product_id, 2, price
  FROM products WHERE product_id = 1;
UPDATE products SET stock_qty = stock_qty - 2 WHERE product_id = 1;
SELECT stock_qty AS stock_inside_transaction FROM products WHERE product_id = 1;
ROLLBACK;
SELECT stock_qty AS stock_after_rollback FROM products WHERE product_id = 1;
SELECT count(*) AS orders_count FROM orders;

\echo === A3: order for 50 units, CHECK constraint fails mid-transaction ===
BEGIN;
INSERT INTO orders(customer_id, address_id) VALUES (1, 1);
INSERT INTO order_items(order_id, product_id, quantity, unit_price)
  SELECT currval(pg_get_serial_sequence('orders','order_id')), product_id, 50, price
  FROM products WHERE product_id = 1;
UPDATE products SET stock_qty = stock_qty - 50 WHERE product_id = 1;
SELECT 'this statement is skipped because the transaction is aborted' AS note;
ROLLBACK;
SELECT stock_qty AS stock_after_failed_order FROM products WHERE product_id = 1;
SELECT count(*) AS orders_count FROM orders;