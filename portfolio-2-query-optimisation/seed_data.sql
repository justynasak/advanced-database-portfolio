TRUNCATE customers, categories, products RESTART IDENTITY CASCADE;

INSERT INTO categories(name)
SELECT 'Category ' || g FROM generate_series(1,10) g;

INSERT INTO customers(full_name, email, phone)
SELECT 'Customer ' || g, 'user' || g || '@naijamart.test',
       '080' || lpad((random()*99999999)::int::text, 8, '0')
FROM generate_series(1,20000) g;

INSERT INTO addresses(customer_id, street, city, state)
SELECT customer_id, (customer_id % 200 + 1) || ' Main Street',
       (ARRAY['Port Harcourt','Lagos','Abuja','Kano','Enugu'])[1 + customer_id % 5],
       (ARRAY['Rivers','Lagos','FCT','Kano','Enugu'])[1 + customer_id % 5]
FROM customers;

INSERT INTO products(category_id, name, price, stock_qty)
SELECT 1 + (g % 10), 'Product ' || g,
       round((random()*100000 + 500)::numeric, 2), (random()*500)::int
FROM generate_series(1,2000) g;

INSERT INTO orders(customer_id, address_id, order_date, status)
SELECT a.customer_id, a.address_id,
       now() - (random()*365)::int * interval '1 day',
       (ARRAY['PENDING','PAID','SHIPPED','DELIVERED','CANCELLED'])[1 + (random()*4)::int]
FROM generate_series(1,100000) g
JOIN addresses a ON a.customer_id = 1 + (g % 20000);

INSERT INTO order_items(order_id, product_id, quantity, unit_price)
SELECT o.order_id, p.product_id, 1 + (random()*4)::int, p.price
FROM orders o
CROSS JOIN generate_series(1,3) k
JOIN products p ON p.product_id = 1 + ((o.order_id*7 + k*131) % 2000);

INSERT INTO payments(order_id, amount, method, paid_at)
SELECT o.order_id, sum(oi.quantity * oi.unit_price), 'CARD', o.order_date
FROM orders o JOIN order_items oi USING (order_id)
WHERE o.status IN ('PAID','SHIPPED','DELIVERED')
GROUP BY o.order_id, o.order_date;

INSERT INTO deliveries(order_id, status, dispatched_at, delivered_at)
SELECT order_id, CASE status WHEN 'DELIVERED' THEN 'DELIVERED' ELSE 'IN_TRANSIT' END,
       order_date + interval '1 day',
       CASE status WHEN 'DELIVERED' THEN order_date + interval '4 days' END
FROM orders WHERE status IN ('SHIPPED','DELIVERED');
