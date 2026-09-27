"""Falha se algum requisito não está rastreado ou se há condicionais pendentes em modo release."""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
REQ = (ROOT / "requisitos.md").read_text(encoding="utf-8")
TRACE = (ROOT / "docs/traceability.md").read_text(encoding="utf-8")
LIMITS = (ROOT / "docs/api-limitations.md").read_text(encoding="utf-8")
EXPECTED = (ROOT / "tools/trace_expected.txt").read_text(encoding="utf-8")
ID = re.compile(r"\b(RF|RNF|RMH)-\d{3}\b")
EXPECTED_ID = re.compile(r"\b(AC|QM|DOD|DEL|PR|REF)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)?\b")


def ids(text):
    return {m.group(0) for m in ID.finditer(text)}


def rows(text):
    out = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and re.match(r"^(RF|RNF|RMH|AC|QM|DOD|DEL|PR|REF)-", cells[0]):
            out[cells[0]] = cells
    return out


errors = []
trace = rows(TRACE)

for rid in sorted(ids(REQ)):
    if rid not in trace:
        errors.append(f"{rid} ausente em docs/traceability.md")

for rid, cells in trace.items():
    if not cells[2] or cells[2] == "-":
        errors.append(f"{rid} sem verificação")

expected_ids = {m.group(0) for m in EXPECTED_ID.finditer(EXPECTED)}
for eid in sorted(expected_ids):
    if eid not in trace:
        errors.append(f"{eid} ausente em docs/traceability.md (esperado por tools/trace_expected.txt)")

if "--release" in sys.argv:
    for line in LIMITS.splitlines():
        c = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(c) >= 4 and c[2] == "pending":
            errors.append(f"{c[0]} ainda pending em api-limitations.md")
        if len(c) >= 4 and c[2] == "unavailable" and not c[3]:
            errors.append(f"{c[0]} unavailable sem evidência")

print("\n".join(errors) or "traceability OK")
sys.exit(1 if errors else 0)
