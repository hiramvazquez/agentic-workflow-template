#!/usr/bin/env -S deno run --allow-read --allow-write
// ════════════════════════════════════════════════════════════════════
// findings.ts — CLI del Findings Ledger (inventario único de hallazgos)
// ════════════════════════════════════════════════════════════════════
// Portable: usa solo imports `node:` → corre igual con Deno o Node ≥18.
//   Deno:  deno run --allow-read --allow-write tools/findings/findings.ts <cmd>
//   Node:  node --experimental-strip-types tools/findings/findings.ts <cmd>   (o compila)
//
// Fuente de verdad: tools/findings/ledger.jsonl (1 hallazgo = 1 línea JSON).
// Vista humana: docs/process/findings-ledger.md (generada con `render`, NO editar a mano).
//
// INVARIANTE CLAVE: add/import (detección) NUNCA resucitan un estado terminal
// (fixed/accepted/wontfix); solo refrescan updatedAt. Cerrar es explícito.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { argv } from "node:process";

const LEDGER = "tools/findings/ledger.jsonl";
const VIEW = "docs/process/findings-ledger.md";
const TERMINAL = new Set(["fixed", "accepted", "wontfix", "duplicate"]);
const today = () => new Date().toISOString().slice(0, 10);

type Finding = {
  id: string; title: string; area: string;
  severity: "high" | "medium" | "low" | "info";
  tier: "auto-fix" | "owner-decision" | "accepted" | null;
  status: "open" | "triaged" | "in-progress" | "fixed" | "accepted" | "wontfix" | "duplicate";
  source: string; detail: string; effort: "S" | "M" | "L" | null;
  resolution: string | null; links: string[]; createdAt: string; updatedAt: string;
};

function load(): Finding[] {
  if (!existsSync(LEDGER)) return [];
  return readFileSync(LEDGER, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}
function save(items: Finding[]) {
  mkdirSync("tools/findings", { recursive: true });
  writeFileSync(LEDGER, items.map((i) => JSON.stringify(i)).join("\n") + (items.length ? "\n" : ""));
}
function hash(s: string) { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) | 0; return "f-" + (h >>> 0).toString(16); }

function upsert(items: Finding[], f: Partial<Finding>): Finding[] {
  const id = f.id || hash((f.area || "") + (f.title || ""));
  const ex = items.find((i) => i.id === id);
  if (ex) {
    ex.updatedAt = today();
    ex.source = ex.source.includes(f.source || "") ? ex.source : `${ex.source}, ${f.source || ""}`;
    if (!TERMINAL.has(ex.status)) Object.assign(ex, { detail: f.detail ?? ex.detail, severity: f.severity ?? ex.severity });
    return items;
  }
  items.push({
    id, title: f.title || "(sin título)", area: f.area || "?", severity: f.severity || "medium",
    tier: f.tier ?? null, status: "open", source: f.source || "manual", detail: f.detail || "",
    effort: f.effort ?? null, resolution: null, links: f.links || [], createdAt: today(), updatedAt: today(),
  });
  return items;
}

function render(items: Finding[]) {
  const open = items.filter((i) => !TERMINAL.has(i.status));
  const ownerDec = open.filter((i) => i.tier === "owner-decision");
  const row = (i: Finding) => `| \`${i.id}\` | ${i.severity} | ${i.tier ?? "—"} | ${i.status} | ${i.title} | ${i.area} |`;
  const md = `# Findings Ledger (vista generada — NO editar a mano)

> Regenera con: \`findings.ts render\`. Fuente: \`tools/findings/ledger.jsonl\`.
> Total: ${items.length} · abiertos: ${open.length} · cerrados: ${items.length - open.length}

## 🔴 Requieren TU decisión (owner-decision, abiertos)

| id | sev | tier | status | título | área |
|---|---|---|---|---|---|
${ownerDec.map(row).join("\n") || "| — | | | | (ninguno) | |"}

## Todos los abiertos

| id | sev | tier | status | título | área |
|---|---|---|---|---|---|
${open.map(row).join("\n") || "| — | | | | (ninguno) | |"}
`;
  mkdirSync("docs/process", { recursive: true });
  writeFileSync(VIEW, md);
  console.log(`✅ render → ${VIEW} (${items.length} hallazgos)`);
}

// ── CLI ─────────────────────────────────────────────────────────────
const [cmd, ...rest] = argv.slice(2);
const flag = (n: string) => { const i = rest.indexOf(`--${n}`); return i >= 0 ? rest[i + 1] : undefined; };
let items = load();

switch (cmd) {
  case "add":
    items = upsert(items, {
      id: flag("id"), title: flag("title"), area: flag("area"),
      severity: flag("severity") as Finding["severity"], tier: flag("tier") as Finding["tier"],
      source: flag("source"), detail: flag("detail"), effort: flag("effort") as Finding["effort"],
      links: flag("links")?.split(","),
    });
    save(items); render(items); break;
  case "import": {
    const batch: Partial<Finding>[] = JSON.parse(readFileSync(rest[0], "utf8"));
    for (const f of batch) items = upsert(items, f);
    save(items); render(items); break;
  }
  case "list": {
    let r = items;
    if (flag("status")) r = r.filter((i) => i.status === flag("status"));
    if (flag("tier")) r = r.filter((i) => i.tier === flag("tier"));
    if (flag("severity")) r = r.filter((i) => i.severity === flag("severity"));
    console.log(rest.includes("--json") ? JSON.stringify(r, null, 2) : r.map((i) => `${i.id} [${i.status}/${i.severity}] ${i.title}`).join("\n"));
    break;
  }
  case "triage": { const i = items.find((x) => x.id === rest[0]); if (i) { i.tier = flag("tier") as Finding["tier"]; i.status = "triaged"; i.updatedAt = today(); } save(items); render(items); break; }
  case "close": { const i = items.find((x) => x.id === rest[0]); if (i) { i.status = "fixed"; i.resolution = flag("resolution") || "fixed"; i.updatedAt = today(); } save(items); render(items); break; }
  case "accept": { const i = items.find((x) => x.id === rest[0]); if (i) { i.status = "accepted"; i.tier = "accepted"; i.resolution = flag("reason") || "aceptado"; i.updatedAt = today(); } save(items); render(items); break; }
  case "stats": {
    const by = (k: keyof Finding) => items.reduce<Record<string, number>>((a, i) => { const v = String(i[k]); a[v] = (a[v] || 0) + 1; return a; }, {});
    console.log("status:", by("status")); console.log("severity:", by("severity")); console.log("tier:", by("tier")); break;
  }
  case "render": render(items); break;
  default:
    console.log(`findings.ts — comandos:
  add --title T --area "file:line" --severity high|medium|low --tier auto-fix|owner-decision [--id ID] [--detail D] [--source S] [--effort S|M|L] [--links a,b]
  import batch.json        list [--status open] [--tier owner-decision] [--json]
  triage ID --tier T       close ID --resolution "commit X"      accept ID --reason "..."
  stats                    render`);
}
