# ER diagram for Deeva's Designs

GitHub renders the diagram below directly. Only key columns are shown; the full column list is in [01_schema.sql](01_schema.sql).

```mermaid
erDiagram
    customer ||--o{ wearer : "orders for"
    customer ||--o{ customer_order : places
    wearer ||--o{ measurement_set : "is measured in"
    measurement_set ||--|{ measurement_value : contains
    measurement_type ||--o{ measurement_value : "is recorded as"
    garment_type ||--o{ garment_type_measurement : requires
    measurement_type ||--o{ garment_type_measurement : "is needed by"
    garment_type ||--o{ style : "has designs"
    style ||--o{ product_variant : "is stocked as"

    customer_order ||--|{ order_item : contains
    product_variant |o--o{ order_item : "sold as"
    material |o--o{ order_item : "sold as"
    order_item ||--o| garment_job : "is produced by"
    wearer ||--o{ garment_job : "is made for"
    garment_type ||--o{ garment_job : "is a"
    style |o--o{ garment_job : follows
    measurement_set |o--o{ garment_job : "is cut from"
    garment_job ||--o{ job_assignment : "is split into"
    garment_job ||--o{ fitting : "is checked at"
    staff ||--o{ job_assignment : performs
    staff ||--o{ fitting : conducts
    staff ||--o{ measurement_set : takes
    staff ||--o{ customer_order : takes

    material |o--o{ stock_movement : "moves in"
    product_variant |o--o{ stock_movement : "moves in"
    supplier |o--o{ stock_movement : supplies
    order_item |o--o{ stock_movement : causes

    customer_order ||--o{ payment : "is paid by"
    journal_entry ||--o| payment : posts
    journal_entry ||--o| expense : posts
    supplier |o--o{ expense : "is paid in"
    journal_entry ||--|{ journal_line : contains
    account ||--o{ journal_line : "is posted to"
```

## Reading the notation

| Symbol | Meaning |
|---|---|
| `\|\|` | exactly one |
| `\|o` | zero or one |
| `o{` | zero or many |
| `\|{` | one or many |

For example, `customer ||--o{ wearer` reads: each wearer belongs to exactly one customer, and a customer has zero or many wearers.
