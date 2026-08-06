#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# findings.sh — CLI PORTABLE del Findings Ledger (bash + python3)
# ════════════════════════════════════════════════════════════════════
# Equivalente operativo de findings.ts para máquinas SIN Deno/Node. Ese fue
# el fallo real: el ledger exigía un runtime que no estaba, así que era
# inoperable — 9 findings esperaron días en un pending-import.json porque
# "la herramienta oficial no corre aquí". Un inventario al que no se puede
# escribir no es un inventario.
#
# Mismo JSONL, mismos campos y MISMO INVARIANTE que findings.ts:
#   add/import (detección) NUNCA resucitan un estado terminal
#   (fixed/accepted/wontfix/duplicate); solo refrescan updatedAt.
#   Cerrar es explícito (close/accept).
#
#   bash tools/findings/findings.sh add --title T --area A [--id I] [--severity s]
#        [--tier t] [--source s] [--detail d] [--effort e] [--links a,b]
#   bash tools/findings/findings.sh close ID --resolution "..."
#   bash tools/findings/findings.sh accept ID --reason "..."
#   bash tools/findings/findings.sh import batch.json
#   bash tools/findings/findings.sh list [--status open] [--json]
#   bash tools/findings/findings.sh render
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ findings.sh necesita python3 (o usa findings.ts con Deno/Node)." >&2
  exit 1
fi

# Todo el trabajo lo hace python3 (JSON de verdad, no sed sobre JSON).
exec python3 - "$@" <<'PYEOF'
import json, sys, os, datetime

LEDGER = "tools/findings/ledger.jsonl"
VIEW   = "docs/process/findings-ledger.md"
TERMINAL = {"fixed", "accepted", "wontfix", "duplicate"}
today = datetime.date.today().isoformat()

def load():
    if not os.path.exists(LEDGER): return []
    with open(LEDGER, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]

def save(items):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "w", encoding="utf-8") as f:
        for i in items:
            f.write(json.dumps(i, ensure_ascii=False) + "\n")

def fhash(s):
    # Mismo hash que findings.ts (h*31+ord, int32, unsigned hex) para que los
    # ids generados por ambos CLIs coincidan sobre el mismo título+área.
    h = 0
    for c in s:
        h = (h * 31 + ord(c)) & 0xFFFFFFFF
        if h >= 0x80000000: h -= 0x100000000
        h &= 0xFFFFFFFF
    return "f-" + format(h & 0xFFFFFFFF, "x")

def upsert(items, f):
    fid = f.get("id") or fhash((f.get("area") or "") + (f.get("title") or ""))
    for ex in items:
        if ex["id"] == fid:
            ex["updatedAt"] = today
            src = f.get("source") or ""
            if src and src not in ex.get("source", ""):
                ex["source"] = f"{ex.get('source','')}, {src}".strip(", ")
            if ex.get("status") not in TERMINAL:
                # No-terminal: refresca campos informativos (y estado si viene).
                for k in ("detail", "severity", "tier", "status", "resolution", "effort"):
                    if f.get(k) is not None: ex[k] = f[k]
            # TERMINAL: no se resucita. Solo updatedAt/source arriba.
            return items
    items.append({
        "id": fid, "title": f.get("title") or "(sin título)", "area": f.get("area") or "?",
        "severity": f.get("severity") or "medium", "tier": f.get("tier"),
        "status": f.get("status") or "open", "source": f.get("source") or "manual",
        "detail": f.get("detail") or "", "effort": f.get("effort"),
        "resolution": f.get("resolution"), "links": f.get("links") or [],
        "createdAt": f.get("createdAt") or today, "updatedAt": today,
    })
    return items

def render(items):
    open_ = [i for i in items if i["status"] not in TERMINAL]
    closed = [i for i in items if i["status"] in TERMINAL]
    lines = [
        "# Findings Ledger — vista humana",
        "",
        "> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.",
        "> Regenerar: `bash tools/findings/findings.sh render`.",
        "",
        f"Abiertos: **{len(open_)}** · Cerrados: {len(closed)} · Total: {len(items)}",
        "",
        "## Abiertos",
        "",
        "| id | sev | tier | área | título |",
        "|---|---|---|---|---|",
    ]
    for i in sorted(open_, key=lambda x: ({"high":0,"medium":1,"low":2,"info":3}.get(x["severity"],9), x["id"])):
        lines.append(f"| `{i['id']}` | {i['severity']} | {i.get('tier') or '—'} | `{i['area']}` | {i['title']} |")
    if not open_: lines.append("| — | | | | (ninguno) |")
    lines += ["", "## Cerrados", "", "| id | estado | resolución |", "|---|---|---|"]
    for i in closed:
        res = (i.get("resolution") or "")[:100]
        lines.append(f"| `{i['id']}` | {i['status']} | {res} |")
    os.makedirs(os.path.dirname(VIEW), exist_ok=True)
    with open(VIEW, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"✅ render → {VIEW} ({len(items)} hallazgos, {len(open_)} abiertos)")

def flag(rest, name):
    try:
        i = rest.index(f"--{name}"); return rest[i + 1]
    except (ValueError, IndexError):
        return None

args = sys.argv[1:]
cmd = args[0] if args else ""
rest = args[1:]
items = load()

if cmd == "add":
    items = upsert(items, {k: flag(rest, k) for k in
        ("id","title","area","severity","tier","source","detail","effort","status")} |
        ({"links": flag(rest,"links").split(",")} if flag(rest,"links") else {}))
    save(items); render(items)
elif cmd == "import":
    with open(rest[0], encoding="utf-8") as f: batch = json.load(f)
    for b in batch: items = upsert(items, b)
    save(items); render(items)
elif cmd == "close":
    for i in items:
        if i["id"] == rest[0]:
            i["status"] = "fixed"; i["resolution"] = flag(rest,"resolution") or "fixed"; i["updatedAt"] = today
    save(items); render(items)
elif cmd == "accept":
    for i in items:
        if i["id"] == rest[0]:
            i["status"] = "accepted"; i["tier"] = "accepted"
            i["resolution"] = flag(rest,"reason") or "aceptado"; i["updatedAt"] = today
    save(items); render(items)
elif cmd == "list":
    r = items
    if flag(rest,"status") == "open": r = [i for i in r if i["status"] not in TERMINAL]
    elif flag(rest,"status"): r = [i for i in r if i["status"] == flag(rest,"status")]
    if flag(rest,"tier"): r = [i for i in r if i.get("tier") == flag(rest,"tier")]
    if "--json" in rest: print(json.dumps(r, ensure_ascii=False, indent=2))
    else:
        for i in r: print(f"{i['id']} [{i['status']}/{i['severity']}] {i['title']}")
elif cmd == "render":
    render(items)
else:
    print("""findings.sh — CLI portable del ledger (mismo esquema que findings.ts):
  add --title T --area A [--id I] [--severity high|medium|low] [--tier auto-fix|owner-decision]
      [--source S] [--detail D] [--effort S|M|L] [--links a,b]
  close ID --resolution "..."      accept ID --reason "..."
  import batch.json                list [--status open] [--tier T] [--json]
  render""")
PYEOF
