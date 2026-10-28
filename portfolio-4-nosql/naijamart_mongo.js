db = db.getSiblingDB("naijamart");
db.products.drop();
db.orders.drop();
function h(t) { print("\n=== " + t + " ==="); }

h("1. Load products (attributes vary by category)");
db.products.insertMany([
  { sku: "PH-001", name: "Tecno Spark 20", category: "Phones", price: 145000, stock_qty: 40,
    attributes: { brand: "Tecno", ram_gb: 8, storage_gb: 128, colour: "Black" }, tags: ["android", "budget"] },
  { sku: "PH-002", name: "Infinix Hot 40", category: "Phones", price: 132000, stock_qty: 25,
    attributes: { brand: "Infinix", ram_gb: 8, storage_gb: 256, colour: "Blue" }, tags: ["android"] },
  { sku: "CL-001", name: "Ankara Shirt", category: "Clothing", price: 12500, stock_qty: 100,
    attributes: { size: ["S", "M", "L", "XL"], colour: "Green", material: "Cotton" }, tags: ["fashion"] },
  { sku: "CL-002", name: "Leather Sandals", category: "Clothing", price: 18000,
    attributes: { colour: "Brown", material: "Leather" }, variants: [ { size: 40, stock_qty: 10 }, { size: 41, stock_qty: 20 }, { size: 42, stock_qty: 20 }, { size: 43, stock_qty: 10 } ], tags: ["footwear"] },
  { sku: "GR-001", name: "Bag of Rice 50kg", category: "Groceries", price: 78000, stock_qty: 30,
    attributes: { weight_kg: 50, origin: "Nigeria", perishable: false }, tags: ["staple"] },
  { sku: "EL-001", name: "Blender 1.5L", category: "Electronics", price: 36000, stock_qty: 45,
    attributes: { wattage: 500, warranty_months: 12, colour: "White" }, tags: ["kitchen"] }
]);
print("products loaded: " + db.products.countDocuments());

h("2. Load orders (customer, address and items embedded)");
db.orders.insertMany([
  { order_ref: "ORD-1001", customer: { customer_id: 1, name: "Customer 1", email: "user1@naijamart.test" },
    shipping_address: { street: "1 Main Street", city: "Port Harcourt", state: "Rivers" },
    items: [ { sku: "PH-001", name: "Tecno Spark 20", quantity: 1, unit_price: 145000 },
             { sku: "CL-001", name: "Ankara Shirt", quantity: 2, unit_price: 12500 } ],
    status: "PAID", order_date: new Date("2026-10-20"), total: 170000 },
  { order_ref: "ORD-1002", customer: { customer_id: 2, name: "Customer 2", email: "user2@naijamart.test" },
    shipping_address: { street: "2 Main Street", city: "Lagos", state: "Lagos" },
    items: [ { sku: "PH-002", name: "Infinix Hot 40", quantity: 1, unit_price: 132000 },
             { sku: "GR-001", name: "Bag of Rice 50kg", quantity: 1, unit_price: 78000 } ],
    status: "SHIPPED", order_date: new Date("2026-10-22"), total: 210000 },
  { order_ref: "ORD-1003", customer: { customer_id: 1, name: "Customer 1", email: "user1@naijamart.test" },
    shipping_address: { street: "1 Main Street", city: "Port Harcourt", state: "Rivers" },
    items: [ { sku: "EL-001", name: "Blender 1.5L", quantity: 1, unit_price: 36000 },
             { sku: "CL-002", name: "Leather Sandals", size: 42, quantity: 1, unit_price: 18000 } ],
    status: "DELIVERED", order_date: new Date("2026-10-24"), total: 54000 },
  { order_ref: "ORD-1004", customer: { customer_id: 3, name: "Customer 3", email: "user3@naijamart.test" },
    shipping_address: { street: "3 Main Street", city: "Abuja", state: "FCT" },
    items: [ { sku: "CL-001", name: "Ankara Shirt", quantity: 3, unit_price: 12500 } ],
    status: "PENDING", order_date: new Date("2026-10-26"), total: 37500 }
]);
print("orders loaded: " + db.orders.countDocuments());

h("3. Query by a category-specific attribute: phones with at least 8 GB RAM");
printjson(db.products.find({ category: "Phones", "attributes.ram_gb": { $gte: 8 } },
  { _id: 0, sku: 1, name: 1, price: 1, "attributes.ram_gb": 1, "attributes.storage_gb": 1 }).toArray());

h("4. Array attribute: products available in size XL");
printjson(db.products.find({ "attributes.size": "XL" }, { _id: 0, sku: 1, name: 1, "attributes.size": 1 }).toArray());

h("5. Whole order in ONE read, no joins");
printjson(db.orders.findOne({ order_ref: "ORD-1001" }, { _id: 0 }));

h("6. All orders for customer 1");
printjson(db.orders.find({ "customer.customer_id": 1 }, { _id: 0, order_ref: 1, status: 1, total: 1 }).toArray());

h("7. Aggregation: units sold and revenue per product");
printjson(db.orders.aggregate([
  { $unwind: "$items" },
  { $group: { _id: "$items.sku", units: { $sum: "$items.quantity" },
              revenue: { $sum: { $multiply: ["$items.quantity", "$items.unit_price"] } } } },
  { $sort: { revenue: -1 } }
]).toArray());

h("8. Atomic stock update with a guard (single-document operation)");
var before = db.products.findOne({ sku: "PH-001" }).stock_qty;
var ok = db.products.updateOne({ sku: "PH-001", stock_qty: { $gte: 1 } }, { $inc: { stock_qty: -1 } });
print("stock before: " + before + " | matched: " + ok.matchedCount + " | modified: " + ok.modifiedCount);
print("stock after: " + db.products.findOne({ sku: "PH-001" }).stock_qty);
var bad = db.products.updateOne({ sku: "PH-001", stock_qty: { $gte: 1000 } }, { $inc: { stock_qty: -1000 } });
print("order for 1000 units | matched: " + bad.matchedCount + " | modified: " + bad.modifiedCount + " (rejected, insufficient stock)");
print("stock still: " + db.products.findOne({ sku: "PH-001" }).stock_qty);

h("9. Index on the customer lookup used in query 6");
db.orders.createIndex({ "customer.customer_id": 1 });
printjson(db.orders.getIndexes().map(function (i) { return i.name; }));
h("10. Stock per size: variant-level atomic updates on the sandals");
function sandalStock() {
  return db.products.findOne({ sku: "CL-002" }).variants.map(function (v) { return v.size + ": " + v.stock_qty; }).join(" | ");
}
print("stock by size before: " + sandalStock());
var s1 = db.products.updateOne(
  { sku: "CL-002", variants: { $elemMatch: { size: 42, stock_qty: { $gte: 1 } } } },
  { $inc: { "variants.$.stock_qty": -1 } });
print("sell 1 x size 42 | matched: " + s1.matchedCount + " | modified: " + s1.modifiedCount);
var s2 = db.products.updateOne(
  { sku: "CL-002", variants: { $elemMatch: { size: 40, stock_qty: { $gte: 25 } } } },
  { $inc: { "variants.$.stock_qty": -25 } });
print("sell 25 x size 40 (only 10 in stock) | matched: " + s2.matchedCount + " | modified: " + s2.modifiedCount + " (rejected)");
print("stock by size after: " + sandalStock());