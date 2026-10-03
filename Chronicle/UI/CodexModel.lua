Chronicle = Chronicle or {}

-- CodexModel: la LÓGICA de navegación del Codex, sin ningún frame. (Fase 10: además decide QUÉ puede verse de cada entidad.) Construye el árbol, las páginas, los breadcrumbs y el
-- historial a partir de Chronicle.Registry (qué existe y cómo se relaciona) y Chronicle.Localization (cómo se llama y qué
-- dice). No guarda ni duplica entidades ni jerarquías: lo único que guarda es estado de la interfaz en memoria (qué nodos
-- están expandidos, la página actual y el historial). Nada se escribe en SavedVariables ni se toca ChronicleCharDB.
--
-- DESCUBRIMIENTO (Fase 10). El modelo NO guarda ni duplica el estado de descubrimiento: lo CONSULTA cada vez a
-- `deps.discovery` (el objeto o una función que lo devuelve; en el addon, Chronicle.Discovery). Una entidad se considera
-- descubierta si y solo si el servicio está listo (IsReady() == true) y IsDiscovered(id) == true. En CUALQUIER otro caso
-- (sin servicio, sin esos métodos, no listo, un error al consultar, un valor que no es `true`) la entidad está BLOQUEADA:
-- nunca se supone descubierta. Un error al consultar se comunica una vez por mensaje (geterrorhandler) y no se propaga.
-- Consultar, seleccionar, expandir o mostrar NO descubre nada: el modelo no llama nunca a Discover.
-- Una entidad bloqueada:
--   · se llama «???» (LOCKED_LABEL) en TODOS los sitios donde el modelo da un nombre (filas, breadcrumbs, ubicación
--     contextual de otras páginas). Nunca se devuelve su nombre real ni su ID como nombre de reserva.
--   · su página es { locked = true, name = "???" } y NADA más: sin ID, tipo, ubicación, descripción, cuerpo, raza ni rol.
--   · sigue en el árbol, se puede seleccionar y expandir, y conserva su sitio en el orden (que sale de su ID y su tipo).
-- Cada entidad se evalúa POR SÍ SOLA: descubrir un lugar no descubre lo que hay en él, ni un NPC sus artículos, ni nada es
-- recursivo. Un descendiente descubierto bajo un ancestro bloqueado se ve con su nombre; el ancestro sigue siendo «???» en su
-- breadcrumb y en su ubicación. El árbol (profundidad, número de hijos y orden) sí es visible aunque haya bloqueos: ver
-- docs/fase10_discovery_codex.md.
--
-- API (Chronicle.CodexModel.New({ registry, localization, discovery, onChange }) -> modelo; todo devuelve copias):
--   m:GetRows()                 -> lista de filas visibles del árbol, en orden: { id, depth, name, nameIsFallback, type,
--                                  hasChildren, expanded, selected, locked }
--   m:IsDiscovered(id)          -> true | false (ver «Descubrimiento»); false para un ID desconocido
--   m:AffectsPage(id)           -> true si la página actual cambia al descubrirse `id` (ella misma o su ubicación)
--   m:GetChildren(id)           -> IDs de los hijos del nodo, ordenados (ver «Árbol»)
--   m:Select(id)                -> true | false, "invalid_id" | "unknown_id"      muestra la página y la anota en el historial
--   m:Toggle(id)                -> true, expandido | false, "unknown_id" | "no_children"      NO cambia la página actual
--   m:SetExpanded(id, bool)     -> igual que Toggle pero con el estado pedido
--   m:IsExpanded(id) / m:GetCurrent()
--   m:GetPage(id)               -> tabla de página (ver «Páginas») | nil si el ID no existe
--   m:GetBreadcrumbs(id)        -> { { id, name, nameIsFallback }, ... } de la raíz a `id` (incluido) por la cadena `parent`
--   m:Back() / m:Forward()      -> true | false, "no_history"                  cambian la página sin tocar el historial
--   m:CanBack() / m:CanForward() / m:GetHistory() -> { ids = {...}, index = n }
--   m:GetName(id)               -> nombre, esFallback, bloqueada | nil si el ID no existe («???», false, true si está bloqueada)
--   `onChange` (opcional) se llama sin argumentos tras cualquier cambio de estado visible. Si lanza error, se ignora.
--
-- ÁRBOL. Cada nodo cuelga de su «ancla»: su `parent` si lo tiene (la jerarquía geográfica) y, si no tiene `parent`, su
-- `located_in` (un NPC o una entrada de lore, que solo ESTÁN en un lugar, no son parte de la geografía). El `located_in` de
-- una entidad que SÍ tiene `parent` (Forjaz está en Dun Morogh pero es una ciudad del continente) NO la cuelga de ese
-- lugar: no se crea ninguna jerarquía falsa; esa ubicación se muestra como dato contextual en su página. Los hijos de un nodo
-- salen de Registry:GetContained (la relación derivada `contains`), sin mantener una copia de la jerarquía. Raíces: las
-- entidades sin ancla, o cuyo ancla no está registrado (así nada desaparece en silencio).
-- ORDEN (determinista, no depende del idioma): primero por tipo (continente, zona, ciudad, subzona, personaje, lore; los
-- tipos futuros al final) y dentro del tipo por ID.
-- Al seleccionar una página se expanden sus ancestros para que su fila sea visible; expandir o contraer nunca la cambia.
--
-- NOMBRES Y TEXTOS. Siempre de Localization (Get, con su fallback de idioma). Para `name` y `description` se prueba primero
-- la clave de presentación de la entidad (`nameKey`/`descriptionKey`, si la declara) y luego su propio ID. Si no hay
-- nombre, el FALLBACK es el propio ID canónico (p. ej. «subzone:foo»), marcado con nameIsFallback = true para que la
-- interfaz lo atenúe; la entidad nunca se oculta ni se lanza un error. Una cadena vacía cuenta como ausente a efectos de
-- mostrar (Localization la avisa como advertencia).
--
-- PÁGINAS. GetPage(id) devuelve { id, type, typeLabel, name, nameIsFallback, description, body, bodyUnresolved,
-- location, details }:
--   description    texto corto de Localization (descriptionKey o ID) | nil
--   body           cuerpo del artículo de lore | nil. Solo existe si la entidad declara `textKey`. DECISIÓN DE DISEÑO ABIERTA:
--                  Localization no tiene un campo de artículo (sus campos son name, description, hint, race, role) y solo
--                  responde por IDs del Registry, así que el ÚNICO canal que el contrato actual permite es
--                  Localization:Get(textKey, "description"). Si no responde, bodyUnresolved = true y no se muestra nada: la
--                  descripción NUNCA se usa como cuerpo ni al revés. Hoy ninguna entidad declara textKey.
--   location       { id, name, nameIsFallback } del `located_in`, si lo hay y está registrado | nil (dato contextual)
--   details        { { label = "Raza", value = ... }, { label = "Rol", value = ... } } con lo que Localization tenga | {}
--   `hint` (la pista de descubrimiento) NO se muestra: pertenece a la integración con Discovery, que no existe aún.
--
-- HISTORIAL (como el de un navegador, en memoria, máximo MAX_HISTORY entradas; al llenarse se descarta la más antigua):
--   * Select(id) de la página actual no hace nada (sin entradas duplicadas).
--   * Select(otro) añade una entrada tras la posición actual y DESCARTA todo lo que había «por delante» (el futuro).
--   * Back/Forward mueven la posición sin modificar la lista; saltan las entradas cuyo ID ya no existe en el Registry.
--   * Los breadcrumbs (ruta geográfica de UNA página) y el historial (páginas visitadas, en orden) son cosas distintas.

local LOCKED_LABEL = "???"
local MAX_HISTORY = 100
local MAX_DEPTH = 64 -- tope de seguridad al subir por anclas

local TYPE_LABELS = {
    continent = "Continente", zone = "Zona", city = "Ciudad", subzone = "Subzona", npc = "Personaje", lore = "Lore",
}
local TYPE_RANK = { continent = 1, zone = 2, city = 3, subzone = 4, npc = 5, lore = 6 }
local UNKNOWN_RANK = 99
local DETAIL_FIELDS = { { field = "race", label = "Raza" }, { field = "role", label = "Rol" } }

local function NewModel(deps)
    if type(deps) ~= "table" or type(deps.registry) ~= "table" or type(deps.localization) ~= "table" then
        error("Chronicle.CodexModel.New: se esperaba una tabla { registry, localization [, onChange] }", 2)
    end
    local registry, localization = deps.registry, deps.localization

    -- Estado de la interfaz (en memoria)
    local expanded = {} -- id -> true
    local history, index = {}, 0
    local self = {}
    local reported = {} -- mensajes de error de Discovery ya comunicados (sin repetirlos en cada repintado)

    local function ReportOnce(message)
        if reported[message] then
            return
        end
        reported[message] = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            handler(message)
        else
            print(message)
        end
    end

    local function Notify()
        if type(deps.onChange) == "function" then
            pcall(deps.onChange)
        end
    end

    local function Known(id)
        return type(id) == "string" and registry:Has(id)
    end

    local function Anchor(entity)
        if type(entity.parent) == "string" then
            return entity.parent
        end
        if type(entity.located_in) == "string" then
            return entity.located_in
        end
        return nil
    end

    local function Rank(entity)
        return TYPE_RANK[entity.type] or UNKNOWN_RANK
    end

    local function SortEntities(list)
        table.sort(list, function(a, b)
            local ra, rb = Rank(a), Rank(b)
            if ra ~= rb then return ra < rb end
            return a.id < b.id
        end)
        local ids = {}
        for i, entity in ipairs(list) do ids[i] = entity.id end
        return ids
    end

    -- Texto de Localization probando las claves en orden; nil si no hay (la cadena vacía cuenta como ausente).
    local function Text(entity, field, keyField)
        local keys = {}
        if type(entity[keyField]) == "string" then keys[#keys + 1] = entity[keyField] end
        keys[#keys + 1] = entity.id
        for _, key in ipairs(keys) do
            local ok, value = pcall(localization.Get, localization, key, field)
            if ok and type(value) == "string" and value ~= "" then
                return value
            end
        end
        return nil
    end

    -- Una entidad solo está descubierta si el servicio lo confirma; cualquier duda es «bloqueada».
    function self:IsDiscovered(id)
        if not Known(id) then
            return false
        end
        local service = deps.discovery
        if type(service) == "function" then
            local ok, resolved = pcall(service)
            if not ok then
                ReportOnce("Chronicle.CodexModel: no se pudo obtener Discovery: " .. tostring(resolved))
                return false
            end
            service = resolved
        end
        if type(service) ~= "table" or type(service.IsReady) ~= "function" or type(service.IsDiscovered) ~= "function" then
            return false
        end
        local okReady, ready = pcall(service.IsReady, service)
        if not okReady then
            ReportOnce("Chronicle.CodexModel: error al consultar Discovery:IsReady: " .. tostring(ready))
            return false
        end
        if ready ~= true then
            return false
        end
        local ok, discovered = pcall(service.IsDiscovered, service, id)
        if not ok then
            ReportOnce("Chronicle.CodexModel: error al consultar Discovery:IsDiscovered: " .. tostring(discovered))
            return false
        end
        return discovered == true
    end

    function self:GetName(id)
        if not Known(id) then
            return nil
        end
        if not self:IsDiscovered(id) then
            return LOCKED_LABEL, false, true
        end
        local name = Text(registry:Get(id), "name", "nameKey")
        if name then
            return name, false
        end
        return id, true
    end

    function self:GetChildren(id)
        if not Known(id) then
            return {}
        end
        local children = {}
        for _, childId in ipairs(registry:GetContained(id)) do
            local child = registry:Get(childId)
            if child and Anchor(child) == id then
                children[#children + 1] = child
            end
        end
        return SortEntities(children)
    end

    local function Roots()
        local roots = {}
        for _, entity in ipairs(registry:GetAll()) do
            local anchor = Anchor(entity)
            if not anchor or not registry:Has(anchor) then
                roots[#roots + 1] = entity
            end
        end
        return SortEntities(roots)
    end

    function self:GetRows()
        local rows, seen = {}, {}
        local function Visit(id, depth)
            if seen[id] or depth > MAX_DEPTH then
                return
            end
            seen[id] = true
            local entity = registry:Get(id)
            if not entity then
                return
            end
            local children = self:GetChildren(id)
            local name, fallback, locked = self:GetName(id)
            local isOpen = expanded[id] == true and #children > 0
            rows[#rows + 1] = {
                id = id, depth = depth, name = name, nameIsFallback = fallback, type = entity.type,
                hasChildren = #children > 0, expanded = isOpen, selected = (history[index] == id), locked = locked == true,
            }
            if isOpen then
                for _, childId in ipairs(children) do
                    Visit(childId, depth + 1)
                end
            end
        end
        for _, id in ipairs(Roots()) do
            Visit(id, 0)
        end
        return rows
    end

    -- Expande los ancestros (por ancla) de `id` para que su fila sea visible.
    local function Reveal(id)
        local seen = {}
        local entity = registry:Get(id)
        local depth = 0
        while entity and depth < MAX_DEPTH do
            local anchor = Anchor(entity)
            if not anchor or not registry:Has(anchor) or seen[anchor] then
                break
            end
            seen[anchor] = true
            expanded[anchor] = true
            entity = registry:Get(anchor)
            depth = depth + 1
        end
    end

    function self:IsExpanded(id)
        return expanded[id] == true and #self:GetChildren(id) > 0
    end

    function self:SetExpanded(id, open)
        if not Known(id) then
            return false, "unknown_id"
        end
        if #self:GetChildren(id) == 0 then
            return false, "no_children"
        end
        expanded[id] = open and true or nil
        Notify()
        return true, open and true or false
    end

    function self:Toggle(id)
        if not Known(id) then
            return false, "unknown_id"
        end
        return self:SetExpanded(id, not self:IsExpanded(id))
    end

    function self:GetCurrent()
        return history[index]
    end

    function self:Select(id)
        if type(id) ~= "string" or id == "" then
            return false, "invalid_id"
        end
        if not registry:Has(id) then
            return false, "unknown_id"
        end
        if history[index] == id then
            return true -- misma página: ni entrada nueva ni cambios
        end
        for i = #history, index + 1, -1 do
            history[i] = nil -- lo que había «por delante» se descarta
        end
        history[#history + 1] = id
        if #history > MAX_HISTORY then
            table.remove(history, 1)
        end
        index = #history
        Reveal(id)
        Notify()
        return true
    end

    -- Posición de la entrada más cercana, en la dirección dada, cuyo ID sigue existiendo (las demás se saltan).
    local function Step(direction)
        local i = index + direction
        while i >= 1 and i <= #history do
            if registry:Has(history[i]) then
                return i
            end
            i = i + direction
        end
        return nil
    end

    function self:CanBack() return Step(-1) ~= nil end
    function self:CanForward() return Step(1) ~= nil end

    local function Move(direction)
        local target = Step(direction)
        if not target then
            return false, "no_history"
        end
        index = target
        Reveal(history[index])
        Notify()
        return true
    end

    function self:Back() return Move(-1) end
    function self:Forward() return Move(1) end

    function self:GetHistory()
        local ids = {}
        for i, id in ipairs(history) do ids[i] = id end
        return { ids = ids, index = index }
    end

    function self:GetBreadcrumbs(id)
        if not Known(id) then
            return {}
        end
        local chain, seen = {}, {}
        local current = id
        while current and not seen[current] and #chain < MAX_DEPTH and registry:Has(current) do
            seen[current] = true
            local name, fallback, locked = self:GetName(current)
            table.insert(chain, 1, { id = current, name = name, nameIsFallback = fallback, locked = locked == true })
            local entity = registry:Get(current)
            current = type(entity.parent) == "string" and entity.parent or nil -- SOLO `parent`: nunca located_in
        end
        return chain
    end

    -- ¿Cambia la página actual si se descubre `id`? Sí si es ella misma o el lugar de su ubicación contextual. (Los
    -- breadcrumbs y el árbol se repintan siempre; esto decide solo si hay que rehacer la página, que vuelve arriba.)
    function self:AffectsPage(id)
        local current = history[index]
        if not current or not Known(id) then
            return false
        end
        if id == current then
            return true
        end
        local entity = registry:Get(current)
        return entity ~= nil and entity.located_in == id
    end

    function self:GetPage(id)
        if not Known(id) then
            return nil
        end
        if not self:IsDiscovered(id) then
            -- Página bloqueada: solo «???». Ni el ID, ni el tipo, ni la ubicación, ni ningún texto.
            return { locked = true, name = LOCKED_LABEL, nameIsFallback = false, bodyUnresolved = false, details = {} }
        end
        local entity = registry:Get(id)
        local name, fallback = self:GetName(id)
        local page = {
            id = id, type = entity.type, typeLabel = TYPE_LABELS[entity.type] or entity.type,
            name = name, nameIsFallback = fallback,
            description = Text(entity, "description", "descriptionKey"),
            bodyUnresolved = false, details = {},
        }
        if type(entity.textKey) == "string" then
            local ok, value = pcall(localization.Get, localization, entity.textKey, "description")
            if ok and type(value) == "string" and value ~= "" then
                page.body = value
            else
                page.bodyUnresolved = true
            end
        end
        if type(entity.located_in) == "string" and registry:Has(entity.located_in) then
            local locName, locFallback, locLocked = self:GetName(entity.located_in)
            page.location = { id = entity.located_in, name = locName, nameIsFallback = locFallback, locked = locLocked == true }
        end
        for _, item in ipairs(DETAIL_FIELDS) do
            local ok, value = pcall(localization.Get, localization, id, item.field)
            if ok and type(value) == "string" and value ~= "" then
                page.details[#page.details + 1] = { label = item.label, value = value }
            end
        end
        return page
    end

    return self
end

Chronicle.CodexModel = { New = NewModel }
