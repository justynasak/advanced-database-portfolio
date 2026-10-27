CREATE TABLE customers (
  customer_id SERIAL PRIMARY KEY,
  full_name   VARCHAR(100) NOT NULL,
  email       VARCHAR(120) NOT NULL UNIQUE,
  phone       VARCHAR(20),
  created_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE addresses (
  address_id  SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers ON DELETE CASCADE,
  street      VARCHAR(150) NOT NULL,
  city        VARCHAR(60)  NOT NULL,
  state       VARCHAR(60)  NOT NULL
);

CREATE TABLE categories (
  category_id SERIAL PRIMARY KEY,
  name        VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE products (
  product_id  SERIAL PRIMARY KEY,
  category_id INT NOT NULL REFERENCES categories,
  name        VARCHAR(150) NOT NULL,
  price       NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  stock_qty   INT NOT NULL CHECK (stock_qty >= 0)
);

CREATE TABLE orders (
  order_id    SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers,
  address_id  INT NOT NULL REFERENCES addresses,
  order_date  TIMESTAMP NOT NULL DEFAULT now(),
  status      VARCHAR(20) NOT NULL DEFAULT 'PENDING'
              CHECK (status IN ('PENDING','PAID','SHIPPED','DELIVERED','CANCELLED'))
);

CREATE TABLE order_items (
  order_id   INT REFERENCES orders ON DELETE CASCADE,
  product_id INT REFERENCES products,
  quantity   INT NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL,
  PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
  payment_id SERIAL PRIMARY KEY,
  order_id   INT NOT NULL UNIQUE REFERENCES orders,
  amount     NUMERIC(12,2) NOT NULL,
  method     VARCHAR(20) NOT NULL,
  paid_at    TIMESTAMP
);

CREATE TABLE deliveries (
  delivery_id SERIAL PRIMARY KEY,
  order_id    INT NOT NULL UNIQUE REFERENCES orders,
  status      VARCHAR(20) NOT NULL DEFAULT 'PROCESSING',
  dispatched_at TIMESTAMP,
  delivered_at  TIMESTAMP
);