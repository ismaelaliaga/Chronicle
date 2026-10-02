Chronicle = Chronicle or {}

-- Estado persistente de Chronicle. Este módulo es el ÚNICO dueño de ChronicleCharDB (la
-- SavedVariablesPerCharacter declarada en el .toc): ningún otro módulo debe leerla ni
-- escribirla directamente, solo a través de State:Get / State:Set.
--
-- Responsabilidades: crear el estado inicial, completar claves que falten, guardar
-- `schemaVersion` y ejecutar migraciones cuando haya más de una versión. El "guardado"
-- en sí lo hace el cliente al cerrar sesión: State solo garantiza que lo que hay en
-- ChronicleCharDB está bien formado.
--
-- La estructura de `discovery` es provisional (solo existe el contenedor `entries`):
-- la fija la Fase 5 y, si hace falta cambiarla, será con una migración.
--
-- El progreso es POR PERSONAJE (SavedVariablesPerCharacter). No se migra nada de
-- versiones anteriores del addon: si el fichero guardado trae claves que State no
-- conoce, se respetan sin tocarlas.

local Utils = Chronicle.Utils

local State = {}
Chronicle.State = State

local CURRENT_SCHEMA = 1

local function BuildDefaults()
    return {
        schemaVersion = CURRENT_SCHEMA,
        discovery = {
            entries = {},
        },
    }
end

-- MIGRATIONS[n] convierte un estado de la versión n a la n+1. Vacío mientras solo
-- exista la versión 1.
local MIGRATIONS = {}

local ready = false
local readOnly = false

local function Warn(msg)
    Utils.Print("State: " .. msg)
end

-- Prepara ChronicleCharDB. Se llama desde Init cuando el cliente ya ha cargado las
-- SavedVariables (ADDON_LOADED); es seguro llamarlo más de una vez.
function State:Init()
    if type(ChronicleCharDB) ~= "table" then
        ChronicleCharDB = {}
    end
    local db = ChronicleCharDB

    local version = db.schemaVersion
    if version == nil then
        -- Primera vez (o tabla sin versión): se parte de la versión actual.
        readOnly = false
    elseif type(version) ~= "number" or version > CURRENT_SCHEMA then
        -- Guardado por una versión más nueva (o corrupto): no se toca para no
        -- estropearlo, y State se queda en solo lectura.
        readOnly = true
        ready = true
        Warn("el estado guardado tiene schemaVersion " .. tostring(version)
            .. " y este Chronicle solo entiende hasta " .. CURRENT_SCHEMA
            .. "; se deja intacto y no se podrá escribir.")
        return
    else
        readOnly = false
        while db.schemaVersion < CURRENT_SCHEMA do
            local migrate = MIGRATIONS[db.schemaVersion]
            if not migrate then
                readOnly = true
                ready = true
                Warn("falta la migración desde schemaVersion " .. db.schemaVersion
                    .. "; solo lectura.")
                return
            end
            migrate(db)
            db.schemaVersion = db.schemaVersion + 1
        end
    end

    Utils.FillDefaults(db, BuildDefaults())
    ready = true
end

function State:IsReady()
    return ready
end

function State:IsReadOnly()
    return readOnly
end

function State:GetSchemaVersion()
    return ready and ChronicleCharDB.schemaVersion or nil
end

-- Lee ChronicleCharDB[k1][k2]...: State:Get("discovery", "entries"). Devuelve nil si
-- el camino no existe o State aún no está listo. Si el valor es una tabla es la propia
-- tabla guardada: quien la reciba debe tratarla como SOLO LECTURA y escribir por Set.
function State:Get(...)
    if not ready then
        return nil
    end
    local node = ChronicleCharDB
    for i = 1, select("#", ...) do
        if type(node) ~= "table" then
            return nil
        end
        node = node[select(i, ...)]
    end
    return node
end

-- Escribe `value` en ChronicleCharDB[k1]...[kn], creando las tablas intermedias que
-- falten: State:Set(true, "discovery", "entries", id). `value = nil` borra la clave.
-- Devuelve true si se ha escrito. No permite tocar schemaVersion (solo las migraciones).
function State:Set(value, ...)
    if not ready or readOnly then
        return false
    end
    local n = select("#", ...)
    if n == 0 then
        error("Chronicle.State:Set: falta la ruta", 2)
    end
    if select(1, ...) == "schemaVersion" then
        -- Cualquier ruta que empiece por schemaVersion: también "schemaVersion", "x"
        -- la machacaría convirtiéndola en tabla.
        error("Chronicle.State:Set: schemaVersion no se modifica desde fuera de State", 2)
    end

    local node = ChronicleCharDB
    for i = 1, n - 1 do
        local key = select(i, ...)
        if type(node[key]) ~= "table" then
            if value == nil then
                return true -- borrar algo que no existe: nada que hacer
            end
            node[key] = {}
        end
        node = node[key]
    end
    node[select(n, ...)] = value
    return true
end
