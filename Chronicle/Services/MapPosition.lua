Chronicle = Chronicle or {}

-- MapPosition: dónde está el jugador ahora mismo, según el cliente, SIN fiarse de lo que devuelva.
-- Responsabilidad única: leer y VALIDAR la ubicación (posición en el mapa, nombre de zona, nombre de
-- subzona). No decide nada con ella (eso es de Proximity y ZoneDiscovery), no crea frames ni
-- temporizadores, no guarda nada y no depende de la interfaz. Es un servicio sin estado.
--
-- TRES CONCEPTOS DISTINTOS (no son intercambiables)
--   posición   coordenadas del jugador DENTRO de un mapa concreto (mapID, x, y), de C_Map.
--   zona       nombre de la zona o ciudad actual (GetRealZoneText): "Dun Morogh", "Ciudad de Forjaz".
--   subzona    nombre del lugar concreto dentro de la zona (GetSubZoneText): "Kharanos". Puede no haber.
--   Ninguno de los tres se deduce de otro: el mapID no dice la zona ni la subzona, y un nombre no
--   dice en qué mapa ni en qué coordenadas está el jugador.
--
-- APIs DE WOW QUE USA (todas con comprobación de existencia y dentro de pcall)
--   C_Map.GetBestMapForUnit("player")      -> mapID numérico, o nil si el cliente aún no lo resuelve
--   C_Map.GetPlayerMapPosition(mapID, "player") -> objeto con :GetXY() -> x, y; nil en instancias o
--                                              mientras no hay dato
--   GetRealZoneText()                      -> nombre localizado de la zona/ciudad
--   GetSubZoneText()                       -> nombre localizado de la subzona; "" si no hay
--   NO usa las funciones antiguas SetMapToCurrentZone()/GetPlayerMapPosition("player"): el addon
--   original dejó anotado que no existen en el cliente actual de Classic Era.
--   Ver docs/fase6_mapposition_proximity.md para qué se ha contrastado y qué NO se ha podido verificar
--   (ningún cliente real se ha ejecutado en el desarrollo de esta fase).
--
-- DEPENDENCIA INYECTABLE: MapPosition.New(api) recibe una tabla (o una función que la devuelve) con las
-- mismas claves que las APIs: { C_Map = {GetBestMapForUnit=, GetPlayerMapPosition=}, GetRealZoneText=,
-- GetSubZoneText= }. La instancia por defecto la lee de los globales del cliente en cada llamada. Así
-- las pruebas simulan cualquier respuesta del cliente sin ejecutarlo.
--
-- CONTRATO: cada consulta devuelve  estado, valor_o_motivo
--   "available"    hay dato fiable; el segundo valor es el dato.
--   "unavailable"  el cliente no tiene el dato AHORA (p. ej. justo tras cargar, o en una instancia):
--                  vale la pena volver a preguntar más tarde. El segundo valor es el motivo.
--   "unknown"      no se puede saber con este cliente o este dato: falta una API, falló, o devolvió algo
--                  que no es creíble (no es un número, no es finito, está fuera de rango). Reintentar no
--                  tiene por qué arreglarlo. El segundo valor es el motivo.
--   Motivos de "unavailable": "no_map", "no_position", "incomplete", "empty".
--   Motivos de "unknown":     "api_missing", "api_error", "invalid_map", "invalid_coordinates",
--                             "invalid_value".
--
--   GetPosition()   -> "available", { mapID, x, y }   (tabla nueva en cada llamada)
--     * mapID: entero positivo. x e y: números finitos en [0, 1], coordenadas NORMALIZADAS del mapa
--       (0 = borde izquierdo/superior, 1 = borde derecho/inferior). Son comparables SOLO entre
--       posiciones del mismo mapID; este servicio nunca convierte entre mapas.
--     * (0, 0) NO es un caso especial: si la API entrega dos números finitos en [0, 1], son una posición
--       válida aunque sean ambos 0 (la esquina del mapa). No se ha encontrado evidencia fiable y específica
--       de Classic Era de que el cliente use (0, 0) para decir "sin dato": la documentación pública de
--       C_Map.GetPlayerMapPosition dice que devuelve nil en áreas restringidas y no menciona ceros. La
--       ausencia de dato llega como nil (ver "unavailable"), nunca se rellena con coordenadas inventadas.
--       Esto está SIN verificar en un cliente real: si allí se viera que (0, 0) significa "sin dato", habría
--       que revisar esta decisión (ver docs/fase6_mapposition_proximity.md).
--   GetZoneName()    -> "available", nombre   | "unavailable", "empty" (nil, "" o solo espacios)
--   GetSubzoneName() -> "available", nombre   | "unavailable", "empty" (aquí "" es lo normal fuera de
--                       una subzona, y no se distingue de "aún no cargado": en ambos casos no hay nada
--                       que usar)

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsMapId(value)
    return IsFiniteNumber(value) and value >= 1 and value == math.floor(value)
end

local function InUnitRange(value)
    return IsFiniteNumber(value) and value >= 0 and value <= 1
end

local function NewMapPosition(apiSource)
    -- Las APIs actuales; una tabla vacía si la fuente no devuelve una tabla.
    local function Api()
        local api = apiSource
        if type(apiSource) == "function" then
            api = apiSource()
        end
        if type(api) ~= "table" then
            return {}
        end
        return api
    end

    local self = {}

    -- Llama a fn(...) de forma segura. Devuelve true, resultados... o false.
    local function Safe(fn, ...)
        return pcall(fn, ...)
    end

    function self:GetPosition()
        local api = Api()
        local cMap = api.C_Map
        if type(cMap) ~= "table" or type(cMap.GetBestMapForUnit) ~= "function"
            or type(cMap.GetPlayerMapPosition) ~= "function" then
            return "unknown", "api_missing"
        end

        local ok, mapId = Safe(cMap.GetBestMapForUnit, "player")
        if not ok then
            return "unknown", "api_error"
        end
        if mapId == nil then
            return "unavailable", "no_map"
        end
        if not IsMapId(mapId) then
            return "unknown", "invalid_map"
        end

        local okPos, position = Safe(cMap.GetPlayerMapPosition, mapId, "player")
        if not okPos then
            return "unknown", "api_error"
        end
        if position == nil then
            return "unavailable", "no_position"
        end
        local positionType = type(position)
        if positionType ~= "table" and positionType ~= "userdata" then
            return "unknown", "invalid_coordinates"
        end

        local okGet, getXY = Safe(function() return position.GetXY end)
        if not okGet or type(getXY) ~= "function" then
            return "unknown", "invalid_coordinates"
        end
        local okXY, x, y = Safe(getXY, position)
        if not okXY then
            return "unknown", "api_error"
        end
        if x == nil or y == nil then
            return "unavailable", "incomplete"
        end
        if not InUnitRange(x) or not InUnitRange(y) then
            return "unknown", "invalid_coordinates"
        end
        return "available", { mapID = mapId, x = x, y = y }
    end

    local function ReadName(functionName)
        local fn = Api()[functionName]
        if type(fn) ~= "function" then
            return "unknown", "api_missing"
        end
        local ok, name = Safe(fn)
        if not ok then
            return "unknown", "api_error"
        end
        if name == nil then
            return "unavailable", "empty"
        end
        if type(name) ~= "string" then
            return "unknown", "invalid_value"
        end
        if name:match("^%s*$") then
            return "unavailable", "empty"
        end
        return "available", name
    end

    function self:GetZoneName()
        return ReadName("GetRealZoneText")
    end

    function self:GetSubzoneName()
        return ReadName("GetSubZoneText")
    end

    return self
end

-- Instancia por defecto: lee las APIs del cliente (globales) en cada llamada.
-- Chronicle.MapPosition.New(api) crea otras con APIs simuladas.
Chronicle.MapPosition = NewMapPosition(function()
    return { C_Map = C_Map, GetRealZoneText = GetRealZoneText, GetSubZoneText = GetSubZoneText }
end)
Chronicle.MapPosition.New = NewMapPosition
