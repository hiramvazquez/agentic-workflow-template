---
description: Redacta una historia de backlog lista para el runner — entrevista corta, criterios verificables, y el archivo en backlog/NNNN-slug.md con status ready.
---

# /historia — de idea suelta a historia trabajable

Idea del owner:

$ARGUMENTS

## Qué hacer

La calidad del run desatendido es proporcional a la historia (backlog/README.md): tu trabajo
aquí es convertir la idea de arriba en un contrato verificable, no en prosa bonita.

1. **Lee `backlog/_template.md`** — ese es el formato, campo a campo.
2. **Entrevista corta (solo lo que NO puedas deducir del código).** Pregunta de una vez, en
   un solo mensaje, lo que falte de: rol/valor (¿para quién y para qué?), estado inicial y
   resultado observable de cada escenario, casos de error que importan, qué queda FUERA de
   scope, qué archivos/módulos puede tocar, y dependencias de otras historias. Si la idea ya
   lo trae, no preguntes por preguntar.
3. **Redacta los criterios de aceptación en Dado/cuando/entonces VERIFICABLES.** La prueba de
   cada criterio: ¿un test puede fallar por él? Mínimo 1 happy path + 2 ramas de error/borde
   (AGENTS.md §5). Un criterio que no se puede convertir en test que falla NO es un criterio —
   reformúlalo o pregunta.
4. **Escribe el archivo** `backlog/NNNN-<slug>.md`: NNNN = siguiente número libre (mira
   `backlog/`), slug corto en kebab-case. Frontmatter completo: `status: ready`, `base`,
   `scope` (rutas explícitas — es la defensa contra el scope creep §8), `depends_on` si aplica.
5. **Autovalida antes de terminar** (los mismos guards del runner, para no descubrirlos en
   `blocked`): el archivo contiene "Criterios de aceptación" y al menos un "Dado ";
   el frontmatter parsea; el scope no está vacío.
6. Termina mostrando la historia completa y recuerda: se dispara con
   `bash tools/backlog/run.sh` (o queda en cola para el próximo ciclo), y el merge de la rama
   `story/NNNN-<slug>` resultante es SIEMPRE del owner.

> No inventes contexto de negocio que el owner no dio — Open Question > suposición silenciosa
> (§1.4). Una historia con un hueco inventado produce una rama entera que hay que tirar.
