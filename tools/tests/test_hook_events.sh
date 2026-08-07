#!/usr/bin/env bash
# Los hooks solo existen si su EVENTO existe. La lección más cara del harness:
# 'PostCompact' y 'PostToolUseFailure' estuvieron registrados durante semanas
# sobre eventos que Claude Code NO tiene — dos gates anunciados que jamás
# dispararon, y en Cursor tres más (sessionStart/preToolUse/postToolUse).
# Un hook sobre un evento fantasma falla hacia el SILENCIO: nadie lo nota.
#
# Estos tests fijan: (1) cada config usa SOLO eventos del esquema real de su
# cliente; (2) cada script referenciado existe y parsea. Si Claude/Cursor/Codex
# renombran eventos en el futuro, actualiza la lista AQUÍ y en
# tools/validate-harness.sh en el mismo commit (están duplicadas a propósito:
# el test fija el contrato, el validador lo explica al humano).

_events_of() { # _events_of <config> → claves de "hooks" sin _comment_*
  python3 -c "
import json,sys
cfg=json.load(open('$1'))
print('\n'.join(k for k in cfg.get('hooks',{}) if not k.startswith('_')))
" 2>/dev/null
}

test_claude_solo_eventos_reales() {
  local valid=" SessionStart UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStop SessionEnd PreCompact "
  local e; while IFS= read -r e; do
    [ -z "$e" ] && continue
    case "$valid" in *" $e "*) : ;; *)
      echo "    .claude/settings.json registra el evento INEXISTENTE '$e'"; return 1 ;;
    esac
  done < <(_events_of .claude/settings.json)
}

test_claude_no_usa_los_eventos_fantasma_conocidos() {
  # Regresión explícita del bug original: estos DOS nombres no deben volver.
  local e; while IFS= read -r e; do
    case "$e" in PostCompact|PostToolUseFailure)
      echo "    '$e' volvió a settings.json — ese evento NO existe en Claude Code"; return 1 ;;
    esac
  done < <(_events_of .claude/settings.json)
  return 0
}

test_cursor_solo_eventos_reales() {
  [ -f .cursor/hooks.json ] || return 0
  local valid=" beforeSubmitPrompt beforeShellExecution beforeMCPExecution beforeReadFile afterFileEdit stop "
  local e; while IFS= read -r e; do
    [ -z "$e" ] && continue
    case "$valid" in *" $e "*) : ;; *)
      echo "    .cursor/hooks.json registra el evento INEXISTENTE '$e'"; return 1 ;;
    esac
  done < <(_events_of .cursor/hooks.json)
}

test_codex_solo_eventos_reales() {
  [ -f .codex/hooks.json ] || return 0
  local valid=" PreToolUse PostToolUse "
  local e; while IFS= read -r e; do
    [ -z "$e" ] && continue
    case "$valid" in *" $e "*) : ;; *)
      echo "    .codex/hooks.json registra el evento INEXISTENTE '$e'"; return 1 ;;
    esac
  done < <(_events_of .codex/hooks.json)
}

test_todo_script_de_hook_existe_y_parsea() {
  local f s bad=0
  for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
    [ -f "$f" ] || continue
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      [ -f "$s" ] || { echo "    $f referencia $s que NO existe"; bad=1; continue; }
      bash -n "$s" 2>/dev/null || { echo "    $s no parsea (bash -n)"; bad=1; }
    done < <(grep -oE 'scripts/agent-hooks/[A-Za-z0-9_./-]+\.sh' "$f" | sort -u)
  done
  return "$bad"
}

# El matcher de SessionStart debe separar startup|clear (reset) de compact
# (reinyección SIN reset): si alguien unifica los matchers, la compactación
# volvería a borrar el baseline de drift a mitad de sesión.
test_sessionstart_compact_va_a_post_compact() {
  python3 -c "
import json,sys
cfg=json.load(open('.claude/settings.json'))
entries=cfg['hooks']['SessionStart']
by_matcher={e.get('matcher','(none)'): [h['command'] for h in e['hooks']] for e in entries}
compact=[m for m in by_matcher if 'compact' in m]
assert compact, 'no hay matcher para compact en SessionStart'
for m in compact:
    cmds=' '.join(by_matcher[m])
    assert 'post-compact' in cmds, f'matcher {m} no invoca post-compact.sh: {cmds}'
    assert 'session-start.sh' not in cmds or '--report' in cmds, \
        f'matcher {m} invoca session-start SIN --report: reset en plena sesion'
" 2>&1 | grep -q Error && { echo "    ver arriba"; return 1; } || return 0
}
