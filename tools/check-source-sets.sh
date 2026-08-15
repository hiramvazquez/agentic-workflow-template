#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-source-sets.sh — EL invariante de KMP: commonMain no ve plataforma
# ════════════════════════════════════════════════════════════════════
# `check-layers.sh` modela un grafo por DIRECTORIO: dominio no importa UI, UI no
# importa infraestructura. En Kotlin Multiplatform eso no basta, porque hay un
# SEGUNDO eje que el grafo por directorio no ve: el de source sets.
#
#   commonMain/   código que compila para TODAS las plataformas
#   androidMain/  · iosMain/ · jvmMain/ · jsMain/   implementaciones por target
#
# El invariante que sostiene el modelo entero es uno solo:
#
#   **commonMain no importa nada específico de plataforma.**
#
# Y es EL invariante de KMP porque su violación no se manifiesta donde se comete:
# un `import android.net.Uri` en commonMain compila perfectamente mientras solo
# construyas el target Android, y revienta el día que alguien añade el target iOS
# —semanas después, en el CI de otro— con un error del compilador de Kotlin/Native
# que no apunta al import culpable. El coste de detectarlo tarde es exactamente el
# ~10× por nivel de §14.1, y aquí se paga entero.
#
# Kotlin ya tiene la respuesta correcta para esto: `expect`/`actual`. Este gate no
# la sustituye; hace que no usarla se note el mismo día.
#
#   bash tools/check-source-sets.sh
#
# Contrato de salida:  SOURCE_SETS estado=<...> violaciones=<N>
# Exit: 0 limpio o no aplica · 1 commonMain importa plataforma · 3 no pude mirar
#
# ── "No aplica" NO es exit 3, y la diferencia importa ───────────────
# Un repo sin `commonMain` no es un detector que no pudo mirar: es un detector
# que miró y no había nada de lo suyo. Decir 3 ahí lo convertiría en un aviso
# permanente para todo adoptante que no use KMP —la mitad de ellos— y un gate
# que siempre avisa se aprende a ignorar (ley del 10%, §14.2). Se declara el
# estado, que es lo que la fase 2 de este harness ya hace con las capacidades:
# `no-aplica` y `operational` son hechos distintos y se dicen distinto.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

CONF="${SOURCE_SETS_CONF:-tools/source-sets.conf}"

# Prefijos de import prohibidos en commonMain. Se pueden ampliar en el conf, y
# NO se pueden reducir desde ahí: una lista que el proyecto puede recortar deja
# de ser un invariante y pasa a ser una sugerencia (§9, misma lógica que los
# trinquetes).
PROHIBIDOS='android\.|androidx\.|java\.|javax\.|dalvik\.|platform\.(UIKit|Foundation|darwin)|kotlinx\.cinterop|org\.robolectric|okhttp3\.|com\.google\.android'
if [ -f "$CONF" ]; then
  _extra="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
  [ -n "$_extra" ] && PROHIBIDOS="${PROHIBIDOS}|${_extra}"
fi

COMMON="$(find . -type d -name commonMain -not -path './.git/*' 2>/dev/null | head -20)"
if [ -z "$COMMON" ]; then
  echo "SOURCE_SETS estado=no-aplica violaciones=0"
  echo "ℹ️  check-source-sets: este repo no tiene source sets de KMP (sin commonMain/)."
  exit 0
fi

# Solo la SINTAXIS de import, anclada a inicio de línea. Un comentario o una
# cadena que NOMBRE `android.net.Uri` no es un import — quien dictamina eso no
# es nuestro criterio, es la gramática de Kotlin: un import solo es válido al
# principio de la línea y del archivo. Sin ese anclaje, el detector se dispara
# con el texto que HABLA de la cosa, que es la mina que este repo ya ha pisado
# siete veces.
HITS=""
while IFS= read -r dir; do
  [ -d "$dir" ] || continue
  _h="$(grep -rnE "^[[:space:]]*import[[:space:]]+(${PROHIBIDOS})" "$dir" \
        --include='*.kt' --include='*.kts' 2>/dev/null || true)"
  [ -n "$_h" ] && HITS="${HITS}${_h}"$'\n'
done <<< "$COMMON"

HITS="$(printf '%s' "$HITS" | grep -v '^$' || true)"
N="$(printf '%s' "$HITS" | grep -c . || true)"; : "${N:=0}"
echo "SOURCE_SETS estado=operational violaciones=$N"

if [ "$N" -gt 0 ]; then
  echo ""
  echo "❌ commonMain importa código de plataforma ($N):"
  printf '%s\n' "$HITS" | sed 's/^/  /'
  cat <<'MSG'

commonMain compila para TODAS las plataformas. Esto compila hoy porque solo
estás construyendo un target; el día que se añada otro, revienta en el CI de
alguien más con un error que no apunta aquí.

La respuesta de Kotlin es `expect`/`actual`:

  // commonMain
  expect class Reloj() { fun ahora(): Long }
  // androidMain
  actual class Reloj { actual fun ahora() = System.currentTimeMillis() }

Y si de verdad es común, busca la alternativa multiplataforma
(kotlinx-datetime, okio, ktor) antes de mover el archivo de source set.
MSG
  exit 1
fi
echo "✅ check-source-sets: commonMain no importa plataforma."
