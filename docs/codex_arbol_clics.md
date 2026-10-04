# Árbol del Codex que no respondía al «+» (rama `correccion-codex-arbol`)

Base: candidata `c37260e41e5941a236c55551cb68d23324655adb`. **No se ha probado en WoW Classic Era**: lo que sigue es análisis del código y pruebas con el mock.

## Qué se descartó (con evidencia)
- **La política de `???`** no impide expandir: `CodexModel:Toggle` solo mira si la entidad existe y tiene hijos (`Registry:GetContained` + ancla), nunca si está descubierta. Probado con el addon real: la raíz bloqueada se expande, se contrae y sus hijos salen en orden (T3–T4).
- **El flujo lógico del clic** (OnClick → `model:Toggle(id)` → `onChange` → `RefreshViews` → `navigation:Refresh` → filas nuevas) funciona de punta a punta con el mock, también con filas reutilizadas (T5, T5b), hojas sin control (T7), navegación y breadcrumb (T8, T9). Las pruebas previas de la Fase 9 ya lo cubrían.
- No hay frames con `EnableMouse` ni niveles de frame explícitos sobre el árbol salvo la ventana (`Codex.lua`): ningún frame propio de la página cubre el árbol.

## Causa más probable (NO demostrada en el cliente)
Cada fila tiene dos botones hermanos del mismo padre (`child`): el de **selección**, que ocupa **toda** la fila (`SetWidth(contentWidth)`), y el **+/-**, colocado encima. Ambos tenían el **mismo nivel de frame**; el código suponía que «crearlo después lo deja por encima», pero el cliente no garantiza ese orden entre hermanos del mismo nivel. Si gana el botón de selección, el clic en «+» solo hace `Select` de la fila ya seleccionada: **no se ve ningún cambio**, que es lo observado. El mock no modela qué frame recibe un clic solapado; solo se puede comprobar que los niveles son distintos.

**Corrección** (`UI/CodexNavigation.lua`): `row.toggle:SetFrameLevel(row.select:GetFrameLevel() + 2)`. Las pruebas T2 y T3e fallaban en la candidata (mismo nivel) y pasan ahora.

## Traza temporal (commit aparte, retirable)
`UI/CodexTrace.lua` + 2 llamadas `Trace(...)` en `CodexNavigation.lua` + una línea en `Init.lua` y otra en el `.toc`. **Apagada por defecto**; máximo 40 líneas; sin temporizadores.

```
/chronicle debug codex on
(pulsa el «+» de la fila)
/chronicle debug codex off
```
- `[clic] +/- id=continent:eastern_kingdoms ... Toggle -> true, true | filas visibles ahora=N`: el botón +/- recibió el clic y el modelo expandió. Si aun así no se ve nada, el fallo está en el repintado.
- `[clic] SELECCIÓN id=... | ratón sobre el +/-: true`: el botón de selección se llevó el clic que iba al «+» (confirma la causa).
- Ninguna línea: ningún botón de la fila recibió el clic (otro frame lo cubre, o el botón está deshabilitado).
