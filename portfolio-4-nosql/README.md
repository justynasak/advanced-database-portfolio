# Portfolio 4: NoSQL and Advanced Data Models

## Case study
NaijaMart, a simulated e-commerce platform (see main README). This portfolio models part of the same system in a **document database** (MongoDB), hosted on a free MongoDB Atlas cluster in the cloud and accessed with `mongosh`.

## 1. Data model
Two collections hold the data. A collection is the document-database equivalent of a table, and a document is the equivalent of a row, except that it can contain nested objects and lists.

| Collection | What a document holds | Design choice |
|---|---|---|
| `products` | SKU, name, category, price, stock, tags, and an `attributes` object that differs by category | Variable attributes: phones store RAM and storage, clothing stores material and sizes, groceries store weight |
| `orders` | Order reference, status, date, total, plus the customer, shipping address and all line items **embedded** | One order is read in a single query, with no joins |

Sample data: 6 products across 4 categories (phones, clothing, groceries, electronics) and 4 orders from 3 customers, prices in naira. The data is deliberately small, because this portfolio is about the shape of the data, not volume (volume was Portfolio 2). Customer IDs 1 to 3 match IDs used in the PostgreSQL database, but the two databases are separate copies and not connected.

## 2. Implementation
- Created a free (M0) cluster in MongoDB Atlas, added a database user and allowed my IP address under Network Access.
- Connected with `mongosh` using a connection string held in an environment variable. The string contains a password, so it is **not** stored anywhere in this repository.
- `naijamart_mongo.js` contains the sample data and all queries. It drops and recreates both collections, so it can be rerun from scratch.
- Run command: `mongosh "$env:MONGO_URI" --file naijamart_mongo.js`. Output is saved in `mongo_output.txt`.

## 3. Operations and results

| Part | Operation | Result |
|---|---|---|
| 1 and 2 | `insertMany` for products and orders | 6 products and 4 orders loaded |
| 3 | Phones with at least 8 GB RAM: `{ category: "Phones", "attributes.ram_gb": { $gte: 8 } }` | Both phones (PH-001, PH-002) |
| 4 | Products available in size XL (matches a value inside an array) | Ankara Shirt only |
| 5 | Read one whole order, `findOne({ order_ref: "ORD-1001" })` | One document containing customer, address and both items |
| 6 | All orders for customer 1, filtering on the nested field `customer.customer_id` | ORD-1001 (PAID, 170,000) and ORD-1003 (DELIVERED, 54,000) |
| 7 | Aggregation: units sold and revenue per product (`$unwind`, `$group`, `$sort`) | PH-001 145,000; PH-002 132,000; GR-001 78,000; CL-001 62,500 (5 units); EL-001 36,000; CL-002 18,000 |
| 8 | Guarded atomic stock update: `updateOne({ sku, stock_qty: { $gte: n } }, { $inc: { stock_qty: -n } })` | Phone stock 40 to 39. A request for 1,000 units matched nothing, so stock stayed 39 |
| 9 | `createIndex` on `customer.customer_id` | Index `customer.customer_id_1` created, alongside the default `_id_` index |
| 10 | Stock per size for the sandals, using the `variants` list | Stock by size 10, 20, 20, 10; selling one size 42 changed it to 19; a request for 25 of size 40 (only 10 in stock) was rejected |

Evidence: `mongo_output.txt`, `mongo_output_1.png` to `mongo_output_4.png`, `atlas_cluster_overview.png`, `atlas_collections_products.png`, `atlas_collections_orders.png`.

## 4. Why a document model suits this part of NaijaMart
- **Products have different attributes.** A phone has RAM and storage, a shirt has sizes and material, rice has weight. A relational `products` table needs many mostly-empty columns or a separate attribute table. In a document each product stores only its own fields, and a new category needs no schema change.
- **An order is read as a unit.** In PostgreSQL (Portfolio 1) one order is spread across `orders`, `order_items`, `addresses` and `customers`. Here it is a single document, so showing an order needs one read and no joins. The embedded customer and address are a snapshot of what was true at purchase time, the same reason `order_items` stores `unit_price` in Portfolio 1.
- **Single-document updates are atomic.** The guarded stock update in part 8 either applies completely or not at all, with the stock check in the same operation. This is the same idea as the atomic update in Portfolio 3 (B4).

## 5. A design decision: stock per size
My first version stored one `stock_qty` for the sandals, next to a list of sizes. That number is a total for the whole product, so the model could not say how many of each size were left. I changed the sandals to a `variants` list where each size has its own `stock_qty`, and a size-specific sale uses `$elemMatch` to find the right variant and `$inc` on `variants.$.stock_qty` to reduce it (part 10). The order line item now records which size was bought. The shirt keeps the simpler model, so the data holds two modelling styles side by side.

The relational design in Portfolio 1 has the same weakness (one `stock_qty` per product). The relational fix would be a `product_variants` table with one row per size and its own stock.

## 6. Trade-offs and limitations
- **Duplication.** Embedding means customer details are copied into every order. If a customer changes email, old orders keep the old copy unless every one is updated. PostgreSQL stores it once.
- **Integrity is mostly the application's job.** There are no foreign keys or CHECK constraints here. I enforced the stock rule inside the update filter instead.
- **Reports across collections are harder.** Part 7 works well because the items are embedded in orders, but combining data from several collections needs `$lookup`, which is more awkward than a SQL join.
- **Small sample.** With 6 products and 4 orders, the index in part 9 makes no measurable difference. It shows how to create one, not a performance gain. The measured effect of indexes is in Portfolio 2.
- **Hybrid design.** For NaijaMart I would keep payments and stock in PostgreSQL, where multi-table constraints and transactions are strongest, and use MongoDB for the product catalogue and for reading order history.

## 7. Reproduce
1. Create a free Atlas cluster, a database user, and a Network Access entry for your IP.
2. Install `mongosh` and set `MONGO_URI` to your connection string, ending in `/naijamart`.
3. Run `mongosh "$env:MONGO_URI" --file naijamart_mongo.js`.

## 8. Files
`naijamart_mongo.js`, `mongo_output.txt`, `mongo_output_1.png`, `mongo_output_2.png`, `mongo_output_3.png`, `mongo_output_4.png`, `atlas_cluster_overview.png`, `atlas_collections_products.png`, `atlas_collections_orders.png`

## 9. Reflection notes (for the final documentation)
- My first connection attempt failed because I typed the variable assignment twice, which left an unclosed quote. Then `mongosh` was not installed, so PowerShell did not recognise the command. I learned to read the prompt and the error text before retrying.
- I discovered the stock-per-size flaw by asking what the number actually meant, and fixed it with variants.