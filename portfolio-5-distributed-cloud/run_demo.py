"""Portfolio 5: replication, consistency, availability, partitioning and failover.

    python run_demo.py

Rebuilds the primary and the replica from nothing, runs seven steps
against them, and writes everything it does and sees to results/demo.txt.
Docker Desktop must be running. No password is needed: every statement is
run inside a container with docker exec.
"""
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIMARY = "deevas-pg-primary"
REPLICA = "deevas-pg-replica"
NAMES = {PRIMARY: "primary", REPLICA: "replica"}

log_lines = []


def log(text=""):
    print(text, flush=True)
    log_lines.append(text)


def heading(title, *notes):
    log()
    log("=" * 76)
    log(title)
    log("=" * 76)
    for note in notes:
        log(f"-- {note}")


def note(text):
    log(f"-- {text}")


def run(args, timeout=180):
    return subprocess.run(args, cwd=HERE, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def psql(container, statement, timeout=60):
    """Run SQL in a container. Returns (finished, output)."""
    args = ["docker", "exec", container, "psql", "-X", "-U", "postgres",
            "-d", "deevas_designs", "-c", statement]
    try:
        result = run(args, timeout)
        return True, (result.stdout + result.stderr).rstrip()
    except subprocess.TimeoutExpired:
        return False, ""


def show(container, statement, timeout=60):
    """Run SQL, log the statement and its output, and return the output."""
    lines = statement.strip().split("\n")
    log(f"[{NAMES[container]}] {lines[0]}")
    for line in lines[1:]:
        log(f"          {line}")
    started = time.monotonic()
    finished, output = psql(container, statement, timeout)
    for line in output.splitlines():
        if line.strip():
            log(f"          {line}")
    if not finished:
        log(f"          ... no reply after {timeout} s")
    return output, time.monotonic() - started


def value(container, statement):
    """Run SQL and return its single value as text, without logging."""
    result = run(["docker", "exec", container, "psql", "-X", "-At", "-U", "postgres",
                  "-d", "deevas_designs", "-c", statement])
    return result.stdout.strip()


def wait_for(test, timeout, interval=0.05):
    """Call test() until it returns true. Returns seconds taken, or None."""
    started = time.monotonic()
    while time.monotonic() - started < timeout:
        try:
            if test():
                return time.monotonic() - started
        except Exception:
            pass
        time.sleep(interval)
    return None


def streaming():
    return value(PRIMARY, "SELECT state FROM pg_stat_replication "
                          "WHERE application_name = 'replica1'") == "streaming"


def on_replica(phone):
    return value(REPLICA, f"SELECT count(*) FROM customer WHERE phone = '{phone}'") == "1"


def add_customer(container, name, phone, timeout=60):
    return show(container, f"INSERT INTO customer (full_name, phone) VALUES ('{name}', '{phone}');",
                timeout)


# ---------------------------------------------------------------------

def build():
    heading("STEP 0. Build both servers from nothing")
    run(["docker", "compose", "down", "-v"])
    started = time.monotonic()
    result = run(["docker", "compose", "up", "-d"], timeout=600)
    if result.returncode != 0:
        sys.exit(f"docker compose up failed:\n{result.stderr}")
    took = wait_for(streaming, timeout=240, interval=1)
    if took is None:
        sys.exit("The replica did not start streaming within 4 minutes. "
                 "See: docker compose logs replica")
    note(f"Primary created and loaded with the Portfolio 1 data, replica copied from it with")
    note(f"pg_basebackup and streaming changes, {time.monotonic() - started:.0f} seconds after starting.")


def step1():
    heading("STEP 1. One primary, one replica",
            "Each server reports whether it is in recovery, which is how PostgreSQL",
            "describes a replica that is replaying changes from somewhere else.")
    for container in (PRIMARY, REPLICA):
        show(container, "SELECT current_setting('cluster_name') AS server, "
                        "pg_is_in_recovery() AS is_replica;")
    log()
    note("The primary's view of the replica:")
    show(PRIMARY, "SELECT application_name, client_addr, state, sync_state, replay_lag\n"
                  "FROM pg_stat_replication;")
    note("The replica's view of the primary:")
    show(REPLICA, "SELECT status, sender_host, slot_name FROM pg_stat_wal_receiver;")


def step2():
    heading("STEP 2. A write on the primary appears on the replica")
    add_customer(PRIMARY, "Replication Test", "08070000001")
    took = wait_for(lambda: on_replica("08070000001"), timeout=10)
    show(REPLICA, "SELECT customer_id, full_name, phone FROM customer WHERE phone = '08070000001';")
    note(f"Visible on the replica {took * 1000:.0f} ms after the insert returned. Much of that is")
    note("the time each docker exec takes; the server's own measure of the delay is below.")
    show(PRIMARY, "SELECT application_name, write_lag, flush_lag, replay_lag FROM pg_stat_replication;")


def step3():
    heading("STEP 3. The replica refuses writes",
            "It is a read-only copy. Every change must go through the primary.")
    add_customer(REPLICA, "Written To Replica", "08070000002")


def step4():
    heading("STEP 4. Asynchronous replication allows stale reads",
            "The primary confirms a commit without waiting for the replica. On a",
            "quiet local network the gap is a fraction of a second. Pausing the",
            "replica's replay stretches it, as a slow network or a busy replica would.")
    show(REPLICA, "SELECT pg_wal_replay_pause();")
    show(PRIMARY, "UPDATE customer SET full_name = 'Replication Test Renamed' WHERE phone = '08070000001';")
    show(PRIMARY, "SELECT full_name FROM customer WHERE phone = '08070000001';")
    show(REPLICA, "SELECT full_name FROM customer WHERE phone = '08070000001';")
    note("The two servers give different answers to the same question.")
    log()
    show(REPLICA, "SELECT pg_wal_replay_resume();")
    wait_for(lambda: value(REPLICA, "SELECT full_name FROM customer WHERE phone = '08070000001'")
             == "Replication Test Renamed", timeout=10)
    show(REPLICA, "SELECT full_name FROM customer WHERE phone = '08070000001';")
    note("Once replay resumes the replica catches up: it is eventually consistent.")


def step5():
    heading("STEP 5. Synchronous replication: consistency at the cost of availability",
            "The primary is told to wait for replica1 to confirm every commit.")
    show(PRIMARY, "ALTER SYSTEM SET synchronous_standby_names = 'replica1';")
    show(PRIMARY, "SELECT pg_reload_conf();")
    wait_for(lambda: value(PRIMARY, "SELECT sync_state FROM pg_stat_replication") == "sync", timeout=10)
    show(PRIMARY, "SELECT application_name, state, sync_state FROM pg_stat_replication;")
    _, took = add_customer(PRIMARY, "Synchronous Write", "08070000003")
    note(f"Committed and confirmed by the replica in {took * 1000:.0f} ms.")
    log()
    note("Now the replica goes down, and a member of staff records a new customer.")
    log("[docker] docker stop deevas-pg-replica")
    run(["docker", "stop", REPLICA])
    statement = "INSERT INTO customer (full_name, phone) VALUES ('Unconfirmed Write', '08070000004');"
    log(f"[primary] {statement}")
    started = time.monotonic()
    waiting = subprocess.Popen(
        ["docker", "exec", PRIMARY, "psql", "-X", "-U", "postgres", "-d", "deevas_designs",
         "-c", statement],
        cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(5)
    log("          ... no reply after 5 s")
    log()
    note("A second session on the primary shows why: the insert is waiting for the replica.")
    show(PRIMARY, "SELECT pid, wait_event_type, wait_event, now() - query_start AS waiting_for\n"
                  "FROM pg_stat_activity WHERE wait_event = 'SyncRep';")
    show(PRIMARY, "SELECT full_name FROM customer WHERE phone = '08070000004';")
    note("The row is already written to the primary's disk, but nobody else can see it,")
    note("and the person who typed it has not been told it is saved. Every write will")
    note("stall like this for as long as the replica is down.")
    log()
    log("[docker] docker start deevas-pg-replica")
    run(["docker", "start", REPLICA])
    output, _ = waiting.communicate(timeout=120)
    took = time.monotonic() - started
    log(f"[primary] (the waiting insert now completes, {took:.1f} s after it was sent)")
    for line in output.splitlines():
        if line.strip():
            log(f"          {line}")
    show(PRIMARY, "SELECT full_name FROM customer WHERE phone = '08070000004';")
    wait_for(lambda: on_replica("08070000004"), timeout=30)
    show(REPLICA, "SELECT full_name FROM customer WHERE phone = '08070000004';")
    log()
    note("Back to asynchronous replication for the rest of the demonstration.")
    show(PRIMARY, "ALTER SYSTEM RESET synchronous_standby_names;")
    show(PRIMARY, "SELECT pg_reload_conf();")


def step6():
    heading("STEP 6. Partitioning: how a shard key divides the data",
            "Sharding spreads one table across several servers by a key. A partitioned",
            "table does the same within one server, so it shows the effect of the choice.",
            "Here 100,000 order records are split into four parts by customer_id.")
    show(PRIMARY, """CREATE TABLE order_history (
    order_id    integer,
    customer_id integer,
    order_date  date,
    total       numeric(12,2)
) PARTITION BY HASH (customer_id);""")
    show(PRIMARY, """DO $$
BEGIN
    FOR i IN 0..3 LOOP
        EXECUTE format('CREATE TABLE order_history_p%s PARTITION OF order_history
                        FOR VALUES WITH (MODULUS 4, REMAINDER %s)', i, i);
    END LOOP;
END $$;""")
    show(PRIMARY, """INSERT INTO order_history
SELECT n, 1001 + (n * 7919) % 20000, DATE '2023-10-01' + n % 1100, 5000 + (n % 60) * 1000
FROM generate_series(1, 100000) AS n;""")
    show(PRIMARY, "ANALYZE order_history;")
    show(PRIMARY, "SELECT tableoid::regclass AS part, count(*) AS orders\n"
                  "FROM order_history GROUP BY 1 ORDER BY 1;")
    note("The rows are spread evenly. A question about one customer goes to one part:")
    show(PRIMARY, "EXPLAIN (COSTS OFF) SELECT * FROM order_history WHERE customer_id = 1100;")
    note("A question about dates has to ask every part and combine the answers:")
    show(PRIMARY, "EXPLAIN (COSTS OFF) SELECT sum(total) FROM order_history\n"
                  "WHERE order_date >= DATE '2026-09-01';")
    note("The new table and its rows were copied to the replica like any other change:")
    wait_for(lambda: value(REPLICA, "SELECT count(*) FROM order_history") == "100000", timeout=20)
    show(REPLICA, "SELECT count(*) FROM order_history;")


def step7():
    heading("STEP 7. Failover: the primary crashes and the replica takes over")
    add_customer(PRIMARY, "Before Failover", "08070000005")
    wait_for(lambda: on_replica("08070000005"), timeout=10)
    log()
    log("[docker] docker kill deevas-pg-primary")
    crashed = time.monotonic()
    run(["docker", "kill", PRIMARY])
    note("The primary is gone, as if the machine had lost power.")
    show(REPLICA, "SELECT count(*) AS customers FROM customer;")
    note("The replica still answers reads, but it cannot take orders:")
    add_customer(REPLICA, "During Outage", "08070000006")
    log()
    note("Promote the replica to be the new primary.")
    show(REPLICA, "SELECT pg_promote();")
    show(REPLICA, "SELECT pg_is_in_recovery() AS is_replica;")
    add_customer(REPLICA, "After Failover", "08070000007")
    writable_again = time.monotonic() - crashed
    show(REPLICA, "SELECT full_name, phone FROM customer\n"
                  "WHERE phone LIKE '0807000000%' ORDER BY phone;")
    note(f"Writes were impossible for {writable_again:.1f} s, from the crash to the first")
    note("successful insert on the new primary. Most of that is this script's own pace;")
    note("an automatic failover tool would act within seconds of noticing the crash.")
    note("Every write that reached the replica before the crash survived.")


def main():
    if run(["docker", "info", "--format", "{{.ServerVersion}}"]).returncode != 0:
        sys.exit("Docker is not running. Start Docker Desktop and try again.")
    build()
    for step in (step1, step2, step3, step4, step5, step6, step7):
        step()
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / "demo.txt").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    log()
    log(f"Written to {RESULTS / 'demo.txt'}")
    log("The replica is now the primary. Run this script again to start afresh.")


if __name__ == "__main__":
    main()
