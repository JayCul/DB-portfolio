-- Deeva's Designs: relational schema (PostgreSQL 18)
--
-- Run against an empty database:
--   createdb -U postgres deevas_designs
--   psql -U postgres -d deevas_designs -f 01_schema.sql
--
-- Money is in naira, numeric(12,2). Body measurements are in inches.
-- Foreign-key columns are deliberately left unindexed here; Portfolio 2
-- adds those indexes and measures the difference.

-- Lets the fitting table mix "=" on an integer with "&&" on a time range
-- inside one exclusion constraint.
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- ---------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------

-- The customer is whoever places and pays for the order.
CREATE TABLE customer (
    customer_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     varchar(120) NOT NULL,
    phone         varchar(20)  NOT NULL UNIQUE,
    email         varchar(254) UNIQUE,
    address       text,
    customer_type varchar(10)  NOT NULL DEFAULT 'individual'
                  CHECK (customer_type IN ('individual', 'trade')),
    created_at    timestamptz  NOT NULL DEFAULT now()
);

-- The wearer is whoever the garment is made for. One customer can order
-- for several wearers (family, or a group outfit for an event).
CREATE TABLE wearer (
    wearer_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  integer      NOT NULL REFERENCES customer,
    full_name    varchar(120) NOT NULL,
    relationship varchar(15)  NOT NULL DEFAULT 'self'
                 CHECK (relationship IN ('self', 'spouse', 'child', 'relative',
                                         'group_member', 'other')),
    notes        text
);

-- A customer can be their own wearer at most once.
CREATE UNIQUE INDEX wearer_one_self_per_customer
    ON wearer (customer_id) WHERE relationship = 'self';

CREATE TABLE staff (
    staff_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name varchar(120) NOT NULL,
    role      varchar(15)  NOT NULL
              CHECK (role IN ('manager', 'front_desk', 'cutter', 'tailor', 'finisher')),
    phone     varchar(20)  NOT NULL UNIQUE,
    hired_on  date         NOT NULL DEFAULT CURRENT_DATE,
    is_active boolean      NOT NULL DEFAULT true
);


-- ---------------------------------------------------------------------
-- Clothing catalogue
-- ---------------------------------------------------------------------

CREATE TABLE garment_type (
    garment_type_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            varchar(60) NOT NULL UNIQUE
);

-- A named design in the lookbook. Bespoke jobs can follow a style, and
-- ready-to-wear stock is a style made up in standard sizes.
CREATE TABLE style (
    style_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    garment_type_id integer       NOT NULL REFERENCES garment_type,
    name            varchar(80)   NOT NULL,
    description     text,
    base_price      numeric(12,2) NOT NULL CHECK (base_price >= 0),
    UNIQUE (garment_type_id, name)
);

CREATE TABLE product_variant (
    variant_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    style_id      integer       NOT NULL REFERENCES style,
    sku           varchar(30)   NOT NULL UNIQUE,
    size_label    varchar(10)   NOT NULL,
    colour        varchar(30)   NOT NULL,
    unit_price    numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    qty_on_hand   integer       NOT NULL DEFAULT 0 CHECK (qty_on_hand >= 0),
    reorder_level integer       NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    UNIQUE (style_id, size_label, colour)
);

CREATE TABLE supplier (
    supplier_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        varchar(120) NOT NULL UNIQUE,
    phone       varchar(20),
    location    varchar(120)
);

-- Fabric and other materials, used in jobs and also sold directly.
-- Quantity is fractional because fabric is cut by the yard.
CREATE TABLE material (
    material_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          varchar(120)  NOT NULL UNIQUE,
    category      varchar(10)   NOT NULL
                  CHECK (category IN ('fabric', 'lining', 'trim', 'thread', 'notion')),
    unit          varchar(10)   NOT NULL CHECK (unit IN ('yard', 'metre', 'piece', 'roll')),
    sell_price    numeric(12,2) NOT NULL CHECK (sell_price >= 0),
    qty_on_hand   numeric(10,2) NOT NULL DEFAULT 0 CHECK (qty_on_hand >= 0),
    reorder_level numeric(10,2) NOT NULL DEFAULT 0 CHECK (reorder_level >= 0)
);


-- ---------------------------------------------------------------------
-- Measurements
-- ---------------------------------------------------------------------

CREATE TABLE measurement_type (
    measurement_type_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                varchar(20) NOT NULL UNIQUE,
    name                varchar(60) NOT NULL
);

-- Which measurements each garment type needs.
CREATE TABLE garment_type_measurement (
    garment_type_id     integer NOT NULL REFERENCES garment_type,
    measurement_type_id integer NOT NULL REFERENCES measurement_type,
    PRIMARY KEY (garment_type_id, measurement_type_id)
);

-- One measuring session. Old sets are kept, so a job always points at
-- the measurements it was actually cut from.
CREATE TABLE measurement_set (
    measurement_set_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wearer_id          integer NOT NULL REFERENCES wearer,
    taken_on           date    NOT NULL DEFAULT CURRENT_DATE,
    taken_by           integer NOT NULL REFERENCES staff,
    notes              text,
    -- target for the composite foreign key on garment_job
    UNIQUE (measurement_set_id, wearer_id)
);

CREATE TABLE measurement_value (
    measurement_set_id  integer      NOT NULL REFERENCES measurement_set ON DELETE CASCADE,
    measurement_type_id integer      NOT NULL REFERENCES measurement_type,
    value_in            numeric(5,2) NOT NULL CHECK (value_in > 0 AND value_in < 100),
    PRIMARY KEY (measurement_set_id, measurement_type_id)
);


-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------

CREATE TABLE customer_order (
    order_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id integer     NOT NULL REFERENCES customer,
    order_date  date        NOT NULL DEFAULT CURRENT_DATE,
    due_date    date,
    status      varchar(15) NOT NULL DEFAULT 'confirmed'
                CHECK (status IN ('draft', 'confirmed', 'in_production', 'ready',
                                  'collected', 'cancelled')),
    taken_by    integer     NOT NULL REFERENCES staff,
    notes       text,
    CHECK (due_date IS NULL OR due_date >= order_date)
);

-- One line of an order. The four kinds share price and quantity but
-- point at different things, so the CHECK makes each kind carry exactly
-- the reference it needs and no other.
CREATE TABLE order_item (
    order_item_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      integer       NOT NULL REFERENCES customer_order ON DELETE CASCADE,
    item_kind     varchar(12)   NOT NULL
                  CHECK (item_kind IN ('bespoke', 'alteration', 'ready_made', 'material')),
    variant_id    integer       REFERENCES product_variant,
    material_id   integer       REFERENCES material,
    description   varchar(200),
    quantity      numeric(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price    numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    CHECK (
        (item_kind = 'ready_made' AND variant_id IS NOT NULL AND material_id IS NULL)
     OR (item_kind = 'material'   AND material_id IS NOT NULL AND variant_id IS NULL)
     OR (item_kind IN ('bespoke', 'alteration')
         AND variant_id IS NULL AND material_id IS NULL)
    )
);

-- Every change in stock, for materials and for ready-to-wear. Positive
-- quantity is stock coming in, negative is stock going out.
CREATE TABLE stock_movement (
    movement_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id   integer       REFERENCES material,
    variant_id    integer       REFERENCES product_variant,
    movement_type varchar(12)   NOT NULL
                  CHECK (movement_type IN ('purchase', 'production', 'job_use',
                                           'sale', 'adjustment')),
    quantity      numeric(10,2) NOT NULL CHECK (quantity <> 0),
    unit_cost     numeric(12,2) CHECK (unit_cost >= 0),
    supplier_id   integer       REFERENCES supplier,
    order_item_id integer       REFERENCES order_item,
    recorded_by   integer       NOT NULL REFERENCES staff,
    moved_at      timestamptz   NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(material_id, variant_id) = 1)
);


-- ---------------------------------------------------------------------
-- Production
-- ---------------------------------------------------------------------

-- The workshop side of a bespoke or alteration line.
CREATE TABLE garment_job (
    job_id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id      integer     NOT NULL UNIQUE REFERENCES order_item ON DELETE CASCADE,
    wearer_id          integer     NOT NULL REFERENCES wearer,
    garment_type_id    integer     NOT NULL REFERENCES garment_type,
    style_id           integer     REFERENCES style,
    measurement_set_id integer,
    job_status         varchar(12) NOT NULL DEFAULT 'queued'
                       CHECK (job_status IN ('queued', 'cutting', 'sewing', 'fitting',
                                             'finishing', 'done', 'cancelled')),
    instructions       text,
    -- the measurement set used must belong to this job's wearer
    FOREIGN KEY (measurement_set_id, wearer_id)
        REFERENCES measurement_set (measurement_set_id, wearer_id)
);

CREATE TABLE job_assignment (
    job_id       integer     NOT NULL REFERENCES garment_job ON DELETE CASCADE,
    task         varchar(12) NOT NULL
                 CHECK (task IN ('cutting', 'sewing', 'embroidery', 'finishing')),
    staff_id     integer     NOT NULL REFERENCES staff,
    assigned_at  timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    PRIMARY KEY (job_id, task),
    CHECK (completed_at IS NULL OR completed_at >= assigned_at)
);

CREATE TABLE fitting (
    fitting_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id     integer     NOT NULL REFERENCES garment_job ON DELETE CASCADE,
    staff_id   integer     NOT NULL REFERENCES staff,
    starts_at  timestamptz NOT NULL,
    ends_at    timestamptz NOT NULL,
    outcome    varchar(10) NOT NULL DEFAULT 'scheduled'
               CHECK (outcome IN ('scheduled', 'approved', 'adjust', 'no_show')),
    notes      text,
    CHECK (ends_at > starts_at),
    -- one member of staff cannot hold two fittings at overlapping times
    CONSTRAINT fitting_no_double_booking
        EXCLUDE USING gist (staff_id WITH =, tstzrange(starts_at, ends_at) WITH &&)
);


-- ---------------------------------------------------------------------
-- Accounting (double entry)
-- ---------------------------------------------------------------------

CREATE TABLE account (
    account_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         varchar(6)  NOT NULL UNIQUE,
    name         varchar(80) NOT NULL UNIQUE,
    account_type varchar(10) NOT NULL
                 CHECK (account_type IN ('asset', 'liability', 'equity',
                                         'revenue', 'expense')),
    is_active    boolean     NOT NULL DEFAULT true
);

CREATE TABLE journal_entry (
    entry_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entry_date  date         NOT NULL DEFAULT CURRENT_DATE,
    description varchar(200) NOT NULL,
    posted_by   integer      NOT NULL REFERENCES staff,
    created_at  timestamptz  NOT NULL DEFAULT now()
);

-- Each line is either a debit or a credit, never both and never neither.
CREATE TABLE journal_line (
    line_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entry_id   integer       NOT NULL REFERENCES journal_entry ON DELETE CASCADE,
    account_id integer       NOT NULL REFERENCES account,
    debit      numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit     numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    CHECK ((debit = 0) <> (credit = 0))
);

-- Debits must equal credits within an entry. A CHECK cannot see other
-- rows, and the lines of an entry are inserted one at a time, so the
-- rule is tested by a trigger that waits until COMMIT.
CREATE FUNCTION check_entry_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_entry_id integer;
    v_diff     numeric;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_entry_id := OLD.entry_id;
    ELSE
        v_entry_id := NEW.entry_id;
    END IF;

    SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0)
      INTO v_diff
      FROM journal_line
     WHERE entry_id = v_entry_id;

    IF v_diff <> 0 THEN
        RAISE EXCEPTION 'journal entry % is not balanced (debits - credits = %)',
                        v_entry_id, v_diff;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER journal_line_balanced
    AFTER INSERT OR UPDATE OR DELETE ON journal_line
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_entry_balanced();

-- Money received from (or refunded to) a customer against an order.
-- journal_entry_id is NOT NULL, so a payment cannot exist without its
-- ledger posting: both are written in one transaction.
CREATE TABLE payment (
    payment_id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         integer       NOT NULL REFERENCES customer_order,
    paid_at          timestamptz   NOT NULL DEFAULT now(),
    amount           numeric(12,2) NOT NULL CHECK (amount > 0),
    method           varchar(15)   NOT NULL
                     CHECK (method IN ('cash', 'bank_transfer', 'pos', 'mobile_money')),
    payment_kind     varchar(10)   NOT NULL
                     CHECK (payment_kind IN ('deposit', 'balance', 'refund')),
    reference        varchar(60),
    received_by      integer       NOT NULL REFERENCES staff,
    journal_entry_id integer       NOT NULL UNIQUE REFERENCES journal_entry
);

CREATE TABLE expense (
    expense_id       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incurred_on      date          NOT NULL DEFAULT CURRENT_DATE,
    payee            varchar(120)  NOT NULL,
    description      varchar(200)  NOT NULL,
    amount           numeric(12,2) NOT NULL CHECK (amount > 0),
    supplier_id      integer       REFERENCES supplier,
    recorded_by      integer       NOT NULL REFERENCES staff,
    journal_entry_id integer       NOT NULL UNIQUE REFERENCES journal_entry
);
