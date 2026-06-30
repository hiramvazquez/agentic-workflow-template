#!/usr/bin/env bash
# Hook PostToolUse Read (Claude) / postToolUse (Cursor) — observe-only.
# Cuando el modelo lee una skill reference (o AGENTS.md / execution map),
# crea un marker. skill-reminder.sh los consulta para permitir ediciones.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"

hook_read_input
# Solo nos interesan los Read.
tool="$(hook_tool)"
case "$tool" in Read|read_file|view|cat) : ;; *) exit 0 ;; esac

file_path="$(hook_file_path)"
[ -z "$file_path" ] && exit 0
rel="$(hook_rel_path "$file_path")"

# Solo paths que la matriz consulta.
case "$rel" in
  .agents/skills/*/SKILL.md|.agents/skills/*/references/*.md) : ;;
  AGENTS.md|CLAUDE.md|docs/process/current_execution_map.md) : ;;
  *) exit 0 ;;
esac

marker_dir="$(hook_state_dir)/skills-read"
mkdir -p "$marker_dir"
touch "$marker_dir/${rel//\//__}.read"
exit 0
