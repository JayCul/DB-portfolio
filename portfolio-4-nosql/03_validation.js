// Deeva's Designs: the rules MongoDB enforces on order documents
//
//   docker compose exec -T mongo mongosh --quiet deevas /work/03_validation.js
//
// A collection has no fixed columns, but it can carry a JSON Schema that
// every insert and update must satisfy. This script attaches one to
// orders, checks the loaded data against it, and then tries four writes
// that must be refused.

const money = { bsonType: "decimal" };

const orderSchema = {
  bsonType: "object",
  required: ["orderDate", "status", "customer", "items", "payments", "total", "paid", "balance"],
  properties: {
    orderDate: { bsonType: "date" },
    dueDate:   { bsonType: "date" },
    status:    { enum: ["draft", "confirmed", "in_production", "ready", "collected", "cancelled"] },
    customer:  { bsonType: "object", required: ["id", "name", "phone"] },
    total: money, paid: money, balance: money,
    payments:  { bsonType: "array" },
    items: {
      bsonType: "array",
      items: {
        bsonType: "object",
        required: ["kind", "quantity", "unitPrice"],
        properties: {
          kind:      { enum: ["bespoke", "alteration", "ready_made", "material"] },
          quantity:  { bsonType: ["double", "int", "decimal"], minimum: 0, exclusiveMinimum: true },
          unitPrice: money
        },
        // The document form of the CHECK constraint on order_item in
        // Portfolio 1: each kind of line must carry its own reference.
        oneOf: [
          { properties: { kind: { enum: ["bespoke", "alteration"] } }, required: ["wearer", "garment"] },
          { properties: { kind: { enum: ["ready_made"] } },            required: ["sku"] },
          { properties: { kind: { enum: ["material"] } },              required: ["material"] }
        ]
      }
    }
  }
};

db.runCommand({ collMod: "orders", validator: { $jsonSchema: orderSchema }, validationLevel: "strict" });
print("Schema attached to orders.");

// collMod does not check documents that are already stored, so count
// the ones that would fail.
const failing = db.orders.countDocuments({ $nor: [{ $jsonSchema: orderSchema }] });
print(`Stored orders that break the schema: ${failing} of ${db.orders.countDocuments()}`);

// ---------------------------------------------------------------------

function validOrder() {
  return {
    _id: "validation-test",
    orderDate: new Date(),
    status: "confirmed",
    customer: { id: 1, name: "Test Customer", phone: "08000000000" },
    items: [{ kind: "material", material: "Indigo adire", unit: "yard",
              quantity: 3, unitPrice: Decimal128("5200.00") }],
    payments: [],
    total: Decimal128("15600.00"), paid: Decimal128("0"), balance: Decimal128("15600.00")
  };
}

// Reduce MongoDB's validation report to the path of rules that failed,
// e.g. "items > item 0 > quantity > minimum".
function describe(rule) {
  if (rule.missingProperties) return `required: ${rule.missingProperties.join(", ")}`;
  if (rule.propertiesNotSatisfied) {
    return rule.propertiesNotSatisfied
      .map((p) => `${p.propertyName} > ${p.details.map(describe).join(", ")}`).join("; ");
  }
  if (rule.operatorName === "items") return `item ${rule.itemIndex} > ${rule.details.map(describe).join(", ")}`;
  return rule.operatorName;
}

function reason(error) {
  const details = error.errInfo && error.errInfo.details;
  return details ? details.schemaRulesNotSatisfied.map(describe).join("; ") : error.message;
}

function attempt(label, change) {
  const order = validOrder();
  change(order);
  try {
    db.orders.insertOne(order);
    db.orders.deleteOne({ _id: order._id });
    print(`\n${label}\n   ACCEPTED`);
  } catch (error) {
    print(`\n${label}\n   refused: ${reason(error)}`);
  }
}

attempt("0. A correct order (should be accepted)", () => {});
attempt("1. A status that is not in the list", (o) => { o.status = "lost"; });
attempt("2. A ready-made line with no SKU", (o) => { o.items[0] = { kind: "ready_made", quantity: 1, unitPrice: Decimal128("40000.00") }; });
attempt("3. A quantity of zero", (o) => { o.items[0].quantity = 0; });
attempt("4. A total stored as text", (o) => { o.total = "15600"; });
