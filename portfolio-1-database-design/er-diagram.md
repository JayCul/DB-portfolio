# ER diagram — Deeva's Designs

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
    garment_type ||--o{ garment_style : "has designs"
    garment_style ||--o{ product_variant : "is stocked as"

    customer_order ||--|{ order_item : contains
    product_variant |o--o{ order_item : "sold as"
    material |o--o{ order_item : "sold as"
    order_item ||--o| garment_job : "is produced by"
    wearer ||--o{ garment_job : "is made for"
    garment_type ||--o{ garment_job : "is a"
    garment_style |o--o{ garment_job : follows
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

    customer {
        int customer_id PK
        varchar phone UK
        varchar customer_type
    }

    wearer {
        int wearer_id PK
        int customer_id FK
        varchar relationship
    }

    staff {
        int staff_id PK
        varchar role
        varchar phone UK
    }

    garment_type {
        int garment_type_id PK
        varchar name UK
    }

    garment_style {
        int style_id PK
        int garment_type_id FK
        numeric base_price
    }

    product_variant {
        int variant_id PK
        int style_id FK
        varchar sku UK
        int qty_on_hand
    }

    supplier {
        int supplier_id PK
        varchar name UK
    }

    material {
        int material_id PK
        varchar name UK
        numeric qty_on_hand
    }

    measurement_type {
        int measurement_type_id PK
        varchar code UK
    }

    garment_type_measurement {
        int garment_type_id PK, FK
        int measurement_type_id PK, FK
    }

    measurement_set {
        int measurement_set_id PK
        int wearer_id FK
        int taken_by FK
        date taken_on
    }

    measurement_value {
        int measurement_set_id PK, FK
        int measurement_type_id PK, FK
        numeric value_in
    }

    customer_order {
        int order_id PK
        int customer_id FK
        int taken_by FK
        varchar status
    }

    order_item {
        int order_item_id PK
        int order_id FK
        varchar item_kind
        int variant_id FK
        int material_id FK
        numeric quantity
        numeric unit_price
    }

    stock_movement {
        int movement_id PK
        int material_id FK
        int variant_id FK
        int supplier_id FK
        int order_item_id FK
        numeric quantity
    }

    garment_job {
        int job_id PK
        int order_item_id FK, UK
        int wearer_id FK
        int garment_type_id FK
        int style_id FK
        int measurement_set_id FK
        varchar job_status
    }

    job_assignment {
        int job_id PK, FK
        varchar task PK
        int staff_id FK
    }

    fitting {
        int fitting_id PK
        int job_id FK
        int staff_id FK
        timestamptz starts_at
        timestamptz ends_at
    }

    account {
        int account_id PK
        varchar code UK
        varchar account_type
    }

    journal_entry {
        int entry_id PK
        int posted_by FK
        date entry_date
    }

    journal_line {
        int line_id PK
        int entry_id FK
        int account_id FK
        numeric debit
        numeric credit
    }

    payment {
        int payment_id PK
        int order_id FK
        int journal_entry_id FK, UK
        numeric amount
    }

    expense {
        int expense_id PK
        int supplier_id FK
        int journal_entry_id FK, UK
        numeric amount
    }
```

## Reading the notation

| Symbol | Meaning |
|---|---|
| `||` | Exactly one |
| `o|` | Zero or one |
| `o{` | Zero or many |
| `|{` | One or many |

For example, `customer ||--o{ wearer` means each wearer belongs to exactly one customer, while a customer can have zero or many wearers.


## Reading the notation

| Symbol | Meaning |
|---|---|
| `\|\|` | exactly one |
| `\|o` | zero or one |
| `o{` | zero or many |
| `\|{` | one or many |

For example, `customer ||--o{ wearer` reads: each wearer belongs to exactly one customer, and a customer has zero or many wearers.
