# Fase 3: migración de datos al nuevo modelo

Alcance: Dun Morogh, Loch Modan y Forjaz (Ironforge). Solo datos: nada de localización,
descubrimiento, interfaz ni navegación.

## Fuentes

Addon original (solo lectura; idéntico a su ZIP de auditoría, 35 ficheros comparados byte a byte):

| Fichero original | Contenido |
|---|---|
| `Data/Zones/DunMorogh.lua`, `Data/Zones/LochModan.lua` | zona, `relatedPlaces`, `nestedCities` y 21 + 12 subzonas |
| `Data/Cities/Ironforge.lua` | ciudad y 7 subzonas |
| `Data/NPCs/DunMorogh.lua`, `LochModan.lua`, `Ironforge.lua` | 5 + 2 + 2 NPC, colgados de su subzona |
| `Data/Continents.lua` | continentes y los lugares de cada uno |

Los ficheros de datos nuevos se generaron con un script a partir de una referencia obtenida
**ejecutando** los ficheros originales (`tests/fixtures/extract_legacy_reference.js` →
`tests/fixtures/legacy_reference.lua`), no copiando texto a mano. Las pruebas comparan lo
migrado contra esa referencia con `==`, sin normalizar.

## Qué se ha migrado

| Tipo | Cantidad | Detalle |
|---|---|---|
| continent | 1 | `continent:eastern_kingdoms` |
| zone | 2 | `zone:dun_morogh`, `zone:loch_modan` |
| city | 1 | `city:ironforge` (parent = continente, located_in = `zone:dun_morogh`) |
| subzone | 40 | 21 Dun Morogh, 12 Loch Modan, 7 Forjaz (`parent` = su zona o ciudad) |
| npc | 9 | 5 Dun Morogh, 2 Loch Modan, 2 Forjaz (`located_in` = su subzona) |
| lore | 0 | ver más abajo |

Ficheros: `Data/Entities/{Geography,Subzones,Npcs}.lua` (canónico) y
`Data/Text/{EasternKingdoms,DunMorogh,LochModan,Ironforge}.lua` (presentación).

### Relaciones, y por qué

- `parent` de zonas y ciudad = continente: `Continents.lua` los lista en Reinos del Este.
- `city:ironforge` `located_in` `zone:dun_morogh`: la fuente la declara en `nestedCities`.
- `related_to`: salen de `relatedPlaces`. Es simétrico, así que se declara una vez por pareja
  (en `zone:dun_morogh`); `Registry:GetRelated()` lo ve desde los dos lados.
- `npc:senir_whitebeard` `related_to` `npc:grelin_whitebeard`: el texto original dice
  literalmente que son familia. Es la única relación entre personajes; no se ha deducido
  ninguna otra de lo que mencionan los textos.
- No se declara `contains` (derivado por el Registry).

### IDs

`tipo:slug`, con el slug sacado del nombre original en inglés: minúsculas, sin apóstrofos,
palabras separadas por `_` (`Gol'Bolar Quarry` → `subzone:golbolar_quarry`). Los antiguos
`key` del addon original (p. ej. `DunMorogh:ColdridgeValley`) no se conservan: el progreso
guardado no se migra (decisión de la Fase 0).

## Dónde viven los textos

Los textos están en `Chronicle.LegacyText[id]`, un contenedor **pasivo**: ningún módulo lo
lee, no tiene API y no es el sistema de localización (Fase 4). Campos por entrada: `name`,
`description` (el `text` original), `hint`, y `race`/`role` en los NPC. Las entidades no
llevan `nameKey`, `descriptionKey` ni `textKey`: la clave por defecto es su ID.

Preservados literalmente (sin reescribir, resumir, corregir ni traducir): nombre, descripción,
pista, raza y rol de las 53 entidades.

## Pendiente o no migrado

- **Coordenadas de NPC (`x`, `y`, `radius`)**: el esquema no tiene dónde ponerlas. La propia
  fuente las marca como sin verificar en cliente real, y Magni y Mekkatorque no tienen.
  Decisión pendiente para la Fase 6.
- **`race` y `role`**: están como texto en `LegacyText`. Queda por decidir si son un dato
  canónico o solo presentación.
- **`hint`** (pista mientras la entidad está sin descubrir): igual, vive en `LegacyText`.
- **Lore**: la fuente no tiene entradas de lore independientes; el «lore» es el `text` de cada
  zona, subzona y NPC. No se ha creado ninguna entidad `lore`.
- **Trivia (8 curiosidades)**, misiones, `TextLinker`, alias de localización español/inglés
  (`Localization.lua`): fuera de alcance de esta fase.
- **Fuera del alcance geográfico**: Kalimdor, y las 5 capitales vacías de `OtherCapitals.lua`
  (Ventormenta, Entrañas, Orgrimmar, Cima del Trueno, Darnassus).
- **Candidatos sin datos** (TODO de la fuente, sin `npcID` ni coordenadas): Rejold Barleybrew,
  Beldin Steelgrill, Prospector Ironband. No se han creado.

## Incertidumbres

- Los `npcID` y `displayID` están tal cual en la fuente, que los declara de Wowhead Classic. Aquí
  **no se han podido contrastar** de forma independiente. Ningún NPC tiene el mismo valor en los
  dos campos.
- La lista de subzonas, y su pertenencia a cada zona, se toma de lo que la fuente dice haber
  verificado contra Classic Era; esta migración no lo ha vuelto a verificar.
- El texto del continente es, según la fuente, lore general de Azeroth sin esa verificación.
- Los nombres en la fuente están en inglés, salvo el del continente («Reinos del Este»), en español.
  La ciudad se llama `Ironforge` en los datos y «Forjaz» en los textos. Cómo se resuelven los
  nombres por idioma es cosa de la Fase 4.
- Todo se ha ejecutado contra un mock de la API de WoW: falta probarlo en el cliente real.
