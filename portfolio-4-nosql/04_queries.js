// Deeva's Designs: reading and writing the document model
//
//   docker compose exec -T mongo mongosh --quiet deevas /work/04_queries.js
//
// Part 1 shows what a document looks like.
// Part 2 asks the Portfolio 2 questions again, before and after indexes.
// Part 3 shows writes: an atomic update, a guarded stock change, and a
//        field added to some documents without altering any schema.

// The questions below assume the generated data from Portfolio 2.
const loaded = db.orders.countDocuments();
if (loaded < 1000) {
  print(`Only ${loaded} orders are loaded. Run portfolio-2-query-optimisation/01_generate_data.sql,`);
  print("then 01_export_from_postgres.sql and 02_load.cmd again.");
  quit(1);
}

// ---------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------

// Collect the stage names of a query plan, e.g. LIMIT <- FETCH <- IXSCAN(name).
function stages(node, found = []) {
  if (!node) return found;
  if (node.stage) found.push(node.stage + (node.indexName ? `(${node.indexName})` : ""));
  ["queryPlan", "inputStage", "outerStage", "innerStage"].forEach((key) => stages(node[key], found));
  (node.inputStages || []).forEach((child) => stages(child, found));
  return found;
}

// Run a query with explain and print what it cost.
function measure(label, cursor) {
  const explained = cursor.explain("executionStats");
  const s = explained.executionStats;
  print(`   ${label}: returned ${s.nReturned}, examined ${s.totalDocsExamined} documents ` +
        `and ${s.totalKeysExamined} index keys, ${s.executionTimeMillis} ms`);
  print(`      plan: ${stages(explained.queryPlanner.winningPlan).join(" <- ")}`);
}

function heading(text) {
  print(`\n${"=".repeat(72)}\n${text}\n${"=".repeat(72)}`);
}

const naira = (value) => Number(value.toString()).toLocaleString("en-NG", { minimumFractionDigits: 2 });
const day = (date) => date.toISOString().slice(0, 10);


// ---------------------------------------------------------------------
heading("PART 1. What the documents look like");
// ---------------------------------------------------------------------

print("\nCollections:");
["orders", "wearers", "styles"].forEach((name) => {
  const s = db[name].stats();
  print(`   ${name.padEnd(8)} ${String(s.count).padStart(7)} documents, average ${s.avgObjSize} bytes, ` +
        `${(s.size / 1048576).toFixed(1)} MB of data, ${(s.storageSize / 1048576).toFixed(1)} MB on disk`);
});

print("\nOne order. In PostgreSQL this is rows from more than a dozen tables.\n");
printjson(db.orders.findOne({ _id: 1 }));

print("\nOne wearer who has been measured twice. Both sets are in the document.\n");
printjson(db.wearers.findOne({ "measurements.1": { $exists: true } }));


// ---------------------------------------------------------------------
heading("PART 2. The Portfolio 2 questions");
// ---------------------------------------------------------------------

const tailor = "Bola Akinwale";

// Each question is a function, so the same query can be run twice.
const q1 = () => db.orders.find({ "customer.id": 1100 }, { orderDate: 1, status: 1, total: 1 })
                          .sort({ orderDate: -1 });

const q2 = () => db.orders.find(
    { status: "in_production",
      items: { $elemMatch: { tasks: { $elemMatch: {
          task: "sewing", staff: tailor, completedAt: { $exists: false } } } } } },
    { dueDate: 1, "customer.name": 1 })
  .sort({ dueDate: 1 });

const q3 = () => db.wearers.find({ _id: 5004 }, { name: 1, measurements: { $slice: 1 } });

const q4 = [
  { $match: { status: "collected",
              dueDate: { $gte: ISODate("2026-09-01"), $lt: ISODate("2026-10-01") } } },
  { $unwind: "$items" },
  { $group: { _id: "$items.kind",
              revenue: { $sum: { $multiply: ["$items.quantity", "$items.unitPrice"] } } } },
  { $sort: { _id: 1 } }
];

const q5 = () => db.orders.find({ status: "ready", balance: { $gt: 0 } },
                                { "customer.name": 1, "customer.phone": 1, balance: 1 })
                          .sort({ balance: -1 }).limit(20);

function runAll(when) {
  print(`\n-- ${when} --`);
  measure("Q1 one customer's orders        ", q1());
  measure("Q2 a tailor's unfinished sewing ", q2());
  measure("Q3 a wearer's latest measurements", q3());
  const started = Date.now();
  const revenue = db.orders.aggregate(q4).toArray();
  print(`   Q4 revenue for one month         : ${Date.now() - started} ms`);
  measure("Q5 finished orders owing money  ", q5());
  return revenue;
}

db.orders.dropIndexes();      // keeps only the index on _id
runAll("Without indexes");

db.orders.createIndex({ "customer.id": 1, orderDate: -1 }, { name: "customer_orders" });
// A multikey index: one entry per task of every line of every order still
// in production. Finished orders are left out of it.
db.orders.createIndex({ "items.tasks.staff": 1 },
                      { name: "open_work_by_staff", partialFilterExpression: { status: "in_production" } });
db.orders.createIndex({ status: 1, dueDate: 1 }, { name: "status_due" });
db.orders.createIndex({ status: 1, balance: -1 }, { name: "status_balance" });
const revenue = runAll("With indexes");

print("\nAnswers:");
print(`   Q1: ${q1().count()} orders for customer 1100, newest ${day(q1().next().orderDate)}`);
print(`   Q2: ${q2().toArray().length} orders with unfinished sewing for ${tailor}, most urgent due ${day(q2().next().dueDate)}`);
const latest = q3().next();
print(`   Q3: ${latest.name}, measured ${day(latest.measurements[0].takenOn)}: ` +
      Object.entries(latest.measurements[0].values).map(([k, v]) => `${k} ${v}`).join(", "));
print("   Q4: revenue for September 2026 by kind of line");
revenue.forEach((row) => print(`         ${row._id.padEnd(11)} ${naira(row.revenue).padStart(18)}`));
print("   Q5: the three largest balances on finished orders");
q5().limit(3).forEach((o) => print(`         order ${o._id}  ${o.customer.name.padEnd(18)} ${naira(o.balance).padStart(14)}`));

print("\nIndex sizes on orders (kB):");
const sizes = db.orders.stats().indexSizes;
Object.keys(sizes).forEach((name) => print(`   ${name.padEnd(20)} ${Math.round(sizes[name] / 1024)}`));


// ---------------------------------------------------------------------
heading("PART 3. Writing");
// ---------------------------------------------------------------------

print("\nA. Take the balance on a finished order.");
print("   The payment is added, the totals change and the status moves on,");
print("   all in one update of one document. No transaction is needed.\n");
const owing = db.orders.findOne({ status: "ready", balance: { $gt: 0 } },
                                { status: 1, total: 1, paid: 1, balance: 1 }, { sort: { _id: 1 } });
print(`   before: order ${owing._id}  status ${owing.status}  paid ${naira(owing.paid)}  balance ${naira(owing.balance)}`);
db.orders.updateOne(
  { _id: owing._id, balance: owing.balance },
  [{ $set: {
      payments: { $concatArrays: ["$payments",
                  [{ paidAt: "$$NOW", amount: owing.balance, method: "cash", kind: "balance" }]] },
      paid:     { $add: ["$paid", owing.balance] },
      balance:  { $subtract: ["$balance", owing.balance] },
      status:   "collected" } }]);
const settled = db.orders.findOne({ _id: owing._id }, { status: 1, paid: 1, balance: 1, payments: 1 });
print(`   after:  order ${settled._id}  status ${settled.status}  paid ${naira(settled.paid)}  ` +
      `balance ${naira(settled.balance)}  payments ${settled.payments.length}`);

print("\nB. Sell ready-to-wear stock, but only if there is enough.");
print("   The stock test is part of the update's filter, so checking and");
print("   changing cannot be separated by another session.\n");
const style = db.styles.findOne({ "variants.stock": { $gte: 1 } });
const variant = style.variants.find((v) => v.stock >= 1);
const sell = (quantity) => db.styles.updateOne(
  { _id: style._id, variants: { $elemMatch: { sku: variant.sku, stock: { $gte: quantity } } } },
  { $inc: { "variants.$.stock": -quantity } }).modifiedCount;
print(`   ${variant.sku} has ${variant.stock} in stock.`);
print(`   Sell ${variant.stock}: ${sell(variant.stock) ? "done" : "refused"}`);
print(`   Sell 1 more: ${sell(1) ? "done" : "refused, nothing changed"}`);

print("\nC. Record details that only some garments have.");
print("   Two styles gain an 'attributes' object with different fields,");
print("   and a list of tags. The other styles are not touched.\n");
db.styles.updateOne({ garmentType: "Agbada" },
  { $set: { attributes: { pieces: 3, embroidery: "hand, chest and sleeves", cap: true },
            tags: ["ceremonial", "wedding", "embroidered"] } });
db.styles.updateOne({ garmentType: "Dress" },
  { $set: { attributes: { neckline: "V", length: "knee", lined: true },
            tags: ["office", "wedding"] } });
db.styles.createIndex({ tags: 1 }, { name: "tags" });
db.styles.find({ tags: "wedding" }, { name: 1, attributes: 1 }).forEach((s) =>
  print(`   ${s.name.padEnd(20)} ${JSON.stringify(s.attributes)}`));
print(`   Styles with attributes: ${db.styles.countDocuments({ attributes: { $exists: true } })} of ${db.styles.countDocuments()}`);
