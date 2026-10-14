"""Run the two-session transaction scenarios and record what happens.

    python run_scenarios.py              run every scenario
    python run_scenarios.py 03 07        run only the scenarios whose file names start 03 or 07

Each scenario in scenarios/ is a script for two database sessions, A and B.
This program opens two psql connections, sends each statement to the session
it is written for, in the order written, and logs the reply. When a session
gives no reply because it is waiting for a lock, the log says so and the
script moves on, exactly as two people at two terminals would.

Output is printed and saved to results/<scenario>.txt.

The connection uses the usual PostgreSQL environment variables. psql is
started with -w, so it never stops to ask for a password: set PGPASSWORD in
the terminal first (Command Prompt:  set PGPASSWORD=...).
"""
import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCENARIOS = HERE / "scenarios"
RESULTS = HERE / "results"

# A statement that has not replied after this many seconds is waiting on a
# lock. It must be longer than deadlock_timeout (1 s by default), so that a
# deadlock is reported by PostgreSQL before this program gives up waiting.
BLOCKED_AFTER = 2.5

PSQL = [
    "psql", "--no-psqlrc", "-w", "-P", "pager=off",
    "-U", os.environ.get("PGUSER", "postgres"),
    "-d", os.environ.get("PGDATABASE", "deevas_designs"),
]

# psql variables that session_vars.sql sets, so a scenario can say :velvet.
VARIABLES = ["velvet", "lining", "staff", "customer"]


class Session:
    """One psql process, fed statements through its standard input."""

    def __init__(self, name):
        self.name = name
        self.sent = 0
        self.marker = None          # set while a statement has not replied yet
        self.lines = queue.Queue()
        env = dict(os.environ, PGCLIENTENCODING="UTF8")
        self.proc = subprocess.Popen(
            PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", bufsize=1, env=env)
        threading.Thread(target=self._read, daemon=True).start()
        self.send(f"\\i '{(HERE / 'session_vars.sql').as_posix()}'")
        self.reply(10)
        for variable in VARIABLES:
            # psql leaves :name untouched when the variable was never set
            self.send(f"\\echo :{variable}")
            value, _ = self.reply(10)
            if not value or not value[0].strip().isdigit():
                sys.exit(f"session_vars.sql could not set :{variable}. "
                         "Load the Portfolio 1 sample data first.")

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line.rstrip("\r\n"))

    def send(self, sql):
        """Send a statement, followed by a marker that psql echoes when it is done."""
        self.sent += 1
        self.marker = f"__done_{self.sent}__"
        self.proc.stdin.write(f"{sql}\n\\echo {self.marker}\n")
        self.proc.stdin.flush()

    def reply(self, timeout):
        """Collect output until the marker arrives. Returns (lines, finished)."""
        out, deadline = [], time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return out, False
            try:
                line = self.lines.get(timeout=remaining)
            except queue.Empty:
                return out, False
            if line == self.marker:
                self.marker = None
                return out, True
            out.append(line)

    def close(self):
        try:
            self.proc.stdin.write("\\q\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def parse(path):
    """Read a scenario file into a title and a list of steps.

    title: ...      the heading
    # text          a note, copied into the log
    A: statement    a statement for session A (B: for session B)
       more         indented lines continue the statement above
    """
    title, steps = path.stem, []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("title:"):
            title = raw[6:].strip()
        elif not raw.strip():
            steps.append(("gap", ""))
        elif raw.startswith("#"):
            steps.append(("note", raw[1:].strip()))
        elif raw[:2] in ("A:", "B:"):
            steps.append((raw[0], raw[2:].strip()))
        elif raw.startswith((" ", "\t")) and raw.strip() and steps and steps[-1][0] in "AB":
            who, sql = steps[-1]
            steps[-1] = (who, sql + "\n" + raw.strip())
    return title, steps


def run(path):
    title, steps = parse(path)
    log_lines = []

    def log(text=""):
        print(text)
        log_lines.append(text)

    def show(lines):
        for line in lines:
            if line.strip():
                log("        " + line)

    # every scenario starts from the same stock levels
    setup = subprocess.run(PSQL + ["-q", "-v", "ON_ERROR_STOP=1", "-f", str(HERE / "setup.sql")],
                           capture_output=True, text=True)
    if setup.returncode != 0:
        sys.exit(f"setup.sql failed:\n{setup.stdout}{setup.stderr}")

    sessions = {"A": Session("A"), "B": Session("B")}
    log("=" * 78)
    log(f"{path.stem}: {title}")
    log("=" * 78)

    gap = False
    for who, text in steps:
        if who == "gap":
            gap = True
            continue
        if gap and log_lines[-1] != "":
            log()        # a blank line in the scenario is a blank line in the log
        gap = False
        if who == "note":
            log(f"-- {text}")
            continue

        session = sessions[who]
        if session.marker:
            sys.exit(f"{path.name}: session {who} is still waiting and cannot take: {text}")

        first, *rest = text.split("\n")
        log(f"[{who}] {first}")
        for line in rest:
            log(f"    {line}")
        session.send(text)
        lines, finished = session.reply(BLOCKED_AFTER)
        show(lines)
        if not finished:
            log("        ... no reply: waiting for a lock held by the other session")

        # this step may have released a lock the other session was waiting for
        other = sessions["B" if who == "A" else "A"]
        if other.marker:
            lines, finished = other.reply(1.0)
            if finished:
                log(f"[{other.name}] (its waiting statement now completes)")
                show(lines)

    for session in sessions.values():
        if session.marker:
            log(f"[{session.name}] was still waiting when the scenario ended")
        session.close()

    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{path.stem}.txt").write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    log()


def main():
    check = subprocess.run(PSQL + ["-Atc", "SELECT 1"], capture_output=True, text=True)
    if check.returncode != 0:
        sys.exit("Cannot connect without a password prompt:\n"
                 f"{check.stderr.strip()}\n\n"
                 "Set PGPASSWORD in this terminal first, then run again.\n"
                 "  Command Prompt:  set PGPASSWORD=your-postgres-password\n"
                 "  PowerShell:      $env:PGPASSWORD = 'your-postgres-password'")

    wanted = sys.argv[1:]
    paths = [p for p in sorted(SCENARIOS.glob("*.txt"))
             if not wanted or any(p.name.startswith(w) for w in wanted)]
    if not paths:
        sys.exit("No matching scenario files in scenarios/")
    for path in paths:
        run(path)


if __name__ == "__main__":
    main()
