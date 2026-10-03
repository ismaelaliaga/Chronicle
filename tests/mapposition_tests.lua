-- Escenarios de prueba de MapPosition (Fase 6). El servicio recibe las APIs del cliente como una
-- dependencia inyectable (NewWith(api)), así que aquí se simula CUALQUIER respuesta del
-- cliente. Esto prueba la lógica de validación, NO que las APIs reales funcionen en Classic Era.

LoadAddon()
local MapPosition = Chronicle.MapPosition

-- API simulada válida: mapa 1000, posición (0.5, 0.25), zona y subzona. `over` cambia lo que haga falta.
local calls
local function Api(over)
    over = over or {}
    calls = { map = {}, pos = {}, getxy = 0, zone = 0, subzone = 0 }
    local api = {
        C_Map = {
            GetBestMapForUnit = function(...)
                calls.map[#calls.map + 1] = { ... }
                if over.mapError then error("fallo de mapa") end
                if over.mapId ~= nil then return over.mapId ~= "NIL" and over.mapId or nil end
                return 1000
            end,
            GetPlayerMapPosition = function(...)
                calls.pos[#calls.pos + 1] = { ... }
                if over.posError then error("fallo de posición") end
                if over.position ~= nil then return over.position ~= "NIL" and over.position or nil end
                local x, y = 0.5, 0.25
                if over.x ~= nil then x = over.x ~= "NIL" and over.x or nil end
                if over.y ~= nil then y = over.y ~= "NIL" and over.y or nil end
                return { GetXY = function(self)
                    calls.getxy = calls.getxy + 1
                    if over.xyError then error("fallo de GetXY") end
                    return x, y
                end }
            end,
        },
        GetRealZoneText = function()
            calls.zone = calls.zone + 1
            if over.zoneError then error("fallo de zona") end
            if over.zone ~= nil then return over.zone ~= "NIL" and over.zone or nil end
            return "Dun Morogh"
        end,
        GetSubZoneText = function()
            calls.subzone = calls.subzone + 1
            if over.subzoneError then error("fallo de subzona") end
            if over.subzone ~= nil then return over.subzone ~= "NIL" and over.subzone or nil end
            return "Kharanos"
        end,
    }
    return api
end
-- Los métodos del servicio bajo prueba se llaman envueltos en pcall: si lanzaran una excepción, el resultado es
-- "THROWS" y salta una aserción clara en vez de interrumpir todo el arnés.
local function Guarded(service)
    return setmetatable({}, { __index = function(_, name)
        return function(_, ...)
            local ok, a, b = pcall(service[name], service, ...)
            if ok then return a, b end
            return "THROWS", a
        end
    end })
end
local function NewWith(api) return Guarded(MapPosition.New(api)) end
local function New(over) return NewWith(Api(over)) end
-- Una llamada que lanzara un error se convierte en un resultado "THROWS", para que una regresión salga como FAIL
-- limpio y no como excepción que interrumpe el arnés.
local function try(fn)
    local ok, a, b = pcall(fn)
    if ok then return a, b end
    return "THROWS", a
end
local function pos(over) return try(function() return New(over):GetPosition() end) end

-- ===================== Posición válida =====================
local status, p = pos()
check("una posición válida devuelve 'available' y { mapID, x, y }",
    status == "available" and type(p) == "table" and p.mapID == 1000 and p.x == 0.5 and p.y == 0.25)
check("la posición devuelta solo tiene mapID, x e y",
    (function() local n = 0 for _ in pairs(p) do n = n + 1 end return n == 3 end)())
check("cada llamada devuelve una tabla nueva (modificarla no afecta a la siguiente)",
    (function()
        local svc = New()
        local _, a = svc:GetPosition()
        a.x = 0.9; a.mapID = 5
        local _, b = svc:GetPosition()
        return b.x == 0.5 and b.mapID == 1000 and a ~= b
    end)())
check("se llama a las APIs con 'player' y con el mapID obtenido, y GetXY recibe el objeto",
    (function()
        local svc = New()
        svc:GetPosition()
        return calls.map[1][1] == "player" and calls.pos[1][1] == 1000 and calls.pos[1][2] == "player" and calls.getxy == 1
    end)())
check("los límites del rango son válidos: x o y en 0 o en 1 (si no son ambos 0)",
    select(1, pos({ x = 1, y = 1 })) == "available" and select(1, pos({ x = 0, y = 1 })) == "available"
        and select(1, pos({ x = 1, y = 0 })) == "available" and select(1, pos({ x = 0, y = 0.5 })) == "available"
        and select(1, pos({ x = 0.000001, y = 0 })) == "available")

-- ===================== Coordenadas inválidas =====================
local function expect(over, wantStatus, wantReason)
    local s, r = pos(over)
    return s == wantStatus and r == wantReason, tostring(s) .. "/" .. tostring(r)
end
-- (0, 0) NO es un valor especial: no hay evidencia fiable y específica de Classic Era de que el cliente lo use para
-- decir "sin dato" (la documentación pública habla de nil en áreas restringidas). Dos números válidos son una posición.
do
    local s0, v0 = pos({ x = 0, y = 0 })
    check("1. dos coordenadas válidas (0, 0) son una posición válida: 'available' con { mapID, x = 0, y = 0 }",
        s0 == "available" and type(v0) == "table" and v0.mapID == 1000 and v0.x == 0 and v0.y == 0)
    check("1b. la posición (0, 0) tiene exactamente mapID, x e y (nada inventado) y los ceros son números",
        type(v0) == "table" and (function() local n = 0 for _ in pairs(v0) do n = n + 1 end return n == 3 and type(v0.x) == "number" and type(v0.y) == "number" end)())
    local sn, vn = pos({ x = -0.0, y = 0 })
    check("1c. el cero negativo (-0) también es una coordenada válida", sn == "available" and type(vn) == "table" and vn.x == 0 and vn.y == 0)
    check("1d. (0, 0) ya no tiene motivo propio: ni 'no_data' ni 'unavailable'",
        select(1, pos({ x = 0, y = 0 })) ~= "unavailable" and select(2, pos({ x = 0, y = 0 })) ~= "no_data")
    check("1e. una esquina cualquiera es válida: (0,0), (1,1), (0,1), (1,0)",
        select(1, pos({ x = 0, y = 0 })) == "available" and select(1, pos({ x = 1, y = 1 })) == "available"
            and select(1, pos({ x = 0, y = 1 })) == "available" and select(1, pos({ x = 1, y = 0 })) == "available")
    check("1f. un cero solo vale si el OTRO valor también es válido: (0, 1.5) y (-1, 0) siguen siendo inválidos",
        expect({ x = 0, y = 1.5 }, "unknown", "invalid_coordinates") and expect({ x = -1, y = 0 }, "unknown", "invalid_coordinates"))
    check("2. un valor ausente NO se convierte en cero: (0, nil) y (nil, 0) son 'incomplete', y 'nil, nil' también",
        expect({ x = 0, y = "NIL" }, "unavailable", "incomplete") and expect({ x = "NIL", y = 0 }, "unavailable", "incomplete")
            and expect({ x = "NIL", y = "NIL" }, "unavailable", "incomplete"))
    check("2b. un cero escrito como cadena o como booleano NO se acepta como número: '0' -> invalid_coordinates",
        expect({ x = "0", y = 0 }, "unknown", "invalid_coordinates") and expect({ x = 0, y = "0" }, "unknown", "invalid_coordinates")
            and expect({ x = true, y = 0 }, "unknown", "invalid_coordinates"))
    check("2c. NaN e infinitos siguen rechazándose junto a un cero",
        expect({ x = 0, y = 0 / 0 }, "unknown", "invalid_coordinates") and expect({ x = 1 / 0, y = 0 }, "unknown", "invalid_coordinates")
            and expect({ x = 0, y = -1 / 0 }, "unknown", "invalid_coordinates"))
end
-- Ningún fallo produce una posición: el segundo valor es siempre un motivo (cadena), nunca una tabla ficticia.
do
    local scenarios = {
        { "sin C_Map", function() return NewWith({}) end }, { "api nil", function() return NewWith(nil) end },
        { "GetBestMapForUnit lanza error", function() return New({ mapError = true }) end },
        { "GetPlayerMapPosition lanza error", function() return New({ posError = true }) end },
        { "GetXY lanza error", function() return New({ xyError = true }) end },
        { "mapID nil", function() return New({ mapId = "NIL" }) end }, { "mapID inválido", function() return New({ mapId = "x" }) end },
        { "posición nil", function() return New({ position = "NIL" }) end }, { "posición sin GetXY", function() return New({ position = {} }) end },
        { "x nil", function() return New({ x = "NIL" }) end }, { "y nil", function() return New({ y = "NIL" }) end },
        { "x NaN", function() return New({ x = 0 / 0 }) end }, { "y infinita", function() return New({ y = 1 / 0 }) end },
        { "x fuera de rango", function() return New({ x = 2 }) end }, { "y negativa", function() return New({ y = -1 }) end },
        { "x cadena", function() return New({ x = "0.5" }) end },
    }
    local bad
    for _, scenario in ipairs(scenarios) do
        local st, value = try(function() return scenario[2]():GetPosition() end)
        if st == "available" or st == "THROWS" or type(value) ~= "string" then bad = scenario[1] break end
    end
    check("3. una API inexistente, que lanza error, o con datos ausentes/inválidos NUNCA genera una posición: estado distinto de 'available' y el valor es un motivo",
        bad == nil, tostring(bad))
    check("3b. sin API de mapas el estado es 'unknown' ('api_missing') y no hay coordenadas",
        select(1, try(function() return NewWith({}):GetPosition() end)) == "unknown"
            and select(2, try(function() return NewWith({}):GetPosition() end)) == "api_missing")
    check("3c. si una API lanza un error el estado es 'unknown' ('api_error') y el error no se propaga",
        select(1, pos({ mapError = true })) == "unknown" and select(2, pos({ mapError = true })) == "api_error"
            and select(2, pos({ posError = true })) == "api_error" and select(2, pos({ xyError = true })) == "api_error")
end
check("fuera de rango (x o y mayores que 1, menores que 0) -> 'unknown', 'invalid_coordinates'",
    expect({ x = 1.0000001 }, "unknown", "invalid_coordinates") and expect({ y = 1.5 }, "unknown", "invalid_coordinates")
        and expect({ x = -0.0000001 }, "unknown", "invalid_coordinates") and expect({ y = -3 }, "unknown", "invalid_coordinates")
        and expect({ x = 100, y = 100 }, "unknown", "invalid_coordinates"))
check("no finitas (NaN, +inf, -inf) -> 'unknown', 'invalid_coordinates'",
    expect({ x = 0 / 0 }, "unknown", "invalid_coordinates") and expect({ y = 0 / 0 }, "unknown", "invalid_coordinates")
        and expect({ x = 1 / 0 }, "unknown", "invalid_coordinates") and expect({ y = -1 / 0 }, "unknown", "invalid_coordinates"))
check("que no son números (cadena, booleano, tabla) -> 'unknown', 'invalid_coordinates'",
    expect({ x = "0.5" }, "unknown", "invalid_coordinates") and expect({ y = true }, "unknown", "invalid_coordinates")
        and expect({ x = {} }, "unknown", "invalid_coordinates"))
check("resultado incompleto (x o y nil, o ambos) -> 'unavailable', 'incomplete'",
    expect({ x = "NIL" }, "unavailable", "incomplete") and expect({ y = "NIL" }, "unavailable", "incomplete")
        and expect({ x = "NIL", y = "NIL" }, "unavailable", "incomplete"))
check("un objeto de posición sin GetXY, o que no es tabla, -> 'unknown', 'invalid_coordinates'",
    expect({ position = {} }, "unknown", "invalid_coordinates") and expect({ position = 5 }, "unknown", "invalid_coordinates")
        and expect({ position = "x" }, "unknown", "invalid_coordinates") and expect({ position = { GetXY = 5 } }, "unknown", "invalid_coordinates"))
check("el mensaje de un valor inválido nunca devuelve una posición", select(2, pos({ x = 2 })) == "invalid_coordinates")

-- ===================== Mapa ausente o inválido; posición ausente =====================
check("sin mapID (nil) -> 'unavailable', 'no_map' y NO se pide la posición",
    expect({ mapId = "NIL" }, "unavailable", "no_map")
        and (function() local svc = New({ mapId = "NIL" }); svc:GetPosition(); return #calls.pos == 0 end)())
check("mapID que no es un entero positivo -> 'unknown', 'invalid_map'",
    expect({ mapId = 0 }, "unknown", "invalid_map") and expect({ mapId = -5 }, "unknown", "invalid_map")
        and expect({ mapId = 1.5 }, "unknown", "invalid_map") and expect({ mapId = "1426" }, "unknown", "invalid_map")
        and expect({ mapId = 0 / 0 }, "unknown", "invalid_map") and expect({ mapId = 1 / 0 }, "unknown", "invalid_map")
        and expect({ mapId = true }, "unknown", "invalid_map") and expect({ mapId = {} }, "unknown", "invalid_map"))
check("sin objeto de posición (nil: p. ej. en una instancia) -> 'unavailable', 'no_position'",
    expect({ position = "NIL" }, "unavailable", "no_position"))

-- ===================== APIs que fallan o no existen =====================
check("una API que lanza error -> 'unknown', 'api_error' (el error no se propaga)",
    expect({ mapError = true }, "unknown", "api_error") and expect({ posError = true }, "unknown", "api_error")
        and expect({ xyError = true }, "unknown", "api_error"))
check("sin API de mapas (api vacía, nil, función que devuelve nil, o valor que no es tabla) -> 'unknown', 'api_missing'",
    (function()
        for _, source in ipairs({ {}, function() return nil end, function() return {} end, function() return 5 end }) do
            local s, r = NewWith(source):GetPosition()
            if s ~= "unknown" or r ~= "api_missing" then return false end
        end
        local s, r = NewWith(nil):GetPosition()
        return s == "unknown" and r == "api_missing"
    end)())
check("C_Map incompleta (falta una de las dos funciones, o no es tabla) -> 'unknown', 'api_missing', sin llamar a lo que falta",
    (function()
        local a = Api(); a.C_Map.GetPlayerMapPosition = nil
        local s1, r1 = NewWith(a):GetPosition()
        local b = Api(); b.C_Map.GetBestMapForUnit = nil
        local s2, r2 = NewWith(b):GetPosition()
        local c = Api(); c.C_Map = "no soy una tabla"
        local s3, r3 = NewWith(c):GetPosition()
        return s1 == "unknown" and r1 == "api_missing" and s2 == "unknown" and r2 == "api_missing"
            and s3 == "unknown" and r3 == "api_missing"
    end)())
check("las funciones antiguas inexistentes (SetMapToCurrentZone, GetPlayerMapPosition global) nunca se usan",
    (function()
        for _, file in ipairs(ADDON_FILES) do
            if file.name == "Services/MapPosition.lua" then
                for line in file.source:gmatch("[^\n]+") do
                    if not line:match("^%s*%-%-") and (line:find("SetMapToCurrentZone", 1, true)
                        or line:find("api.GetPlayerMapPosition", 1, true) or line:find("_G.GetPlayerMapPosition", 1, true)) then
                        return false
                    end
                end
            end
        end
        return true
    end)())

-- ===================== Zona y subzona =====================
local zs, zn = New():GetZoneName()
local ss, sn = New():GetSubzoneName()
check("nombres válidos: 'available' y el nombre tal cual lo da el cliente",
    zs == "available" and zn == "Dun Morogh" and ss == "available" and sn == "Kharanos")
check("zona vacía, nil o solo espacios -> 'unavailable', 'empty'",
    select(1, New({ zone = "" }):GetZoneName()) == "unavailable" and select(2, New({ zone = "" }):GetZoneName()) == "empty"
        and select(2, New({ zone = "NIL" }):GetZoneName()) == "empty" and select(2, New({ zone = "  \t " }):GetZoneName()) == "empty")
check("subzona vacía (lo normal fuera de una subzona), nil o solo espacios -> 'unavailable', 'empty'",
    select(1, New({ subzone = "" }):GetSubzoneName()) == "unavailable" and select(2, New({ subzone = "" }):GetSubzoneName()) == "empty"
        and select(2, New({ subzone = "NIL" }):GetSubzoneName()) == "empty" and select(2, New({ subzone = " " }):GetSubzoneName()) == "empty")
check("un nombre que no es cadena -> 'unknown', 'invalid_value'",
    select(1, New({ zone = 5 }):GetZoneName()) == "unknown" and select(2, New({ zone = 5 }):GetZoneName()) == "invalid_value"
        and select(2, New({ subzone = true }):GetSubzoneName()) == "invalid_value" and select(2, New({ zone = {} }):GetZoneName()) == "invalid_value")
check("una API de nombres que lanza error -> 'unknown', 'api_error'",
    select(2, try(function() return New({ zoneError = true }):GetZoneName() end)) == "api_error"
        and select(2, try(function() return New({ subzoneError = true }):GetSubzoneName() end)) == "api_error")
check("sin las funciones de nombres -> 'unknown', 'api_missing'",
    select(2, NewWith({}):GetZoneName()) == "api_missing" and select(2, NewWith({}):GetSubzoneName()) == "api_missing"
        and select(2, NewWith(nil):GetZoneName()) == "api_missing")

-- ===================== Zona, subzona y mapa son conceptos independientes =====================
check("la zona, la subzona y la posición se consultan por separado y no se deducen unas de otras",
    (function()
        local svc = New({ zone = "Dun Morogh", subzone = "", mapId = "NIL" })
        local zStatus = svc:GetZoneName()
        local sStatus = svc:GetSubzoneName()
        local pStatus = svc:GetPosition()
        return zStatus == "available" and sStatus == "unavailable" and pStatus == "unavailable"
    end)())
check("tener posición no implica tener nombres, ni al revés",
    select(1, New({ zone = "", subzone = "" }):GetPosition()) == "available"
        and select(1, New({ zone = "", subzone = "" }):GetZoneName()) == "unavailable"
        and select(1, New({ mapId = "NIL" }):GetZoneName()) == "available"
        and select(1, New({ mapId = "NIL" }):GetSubzoneName()) == "available")
check("consultar nombres no llama a las APIs de posición, y consultar la posición no llama a las de nombres",
    (function()
        local svc = New()
        svc:GetZoneName(); svc:GetSubzoneName()
        local noPos = #calls.map == 0 and #calls.pos == 0
        svc = New()
        svc:GetPosition()
        return noPos and calls.zone == 0 and calls.subzone == 0
    end)())

-- ===================== La instancia por defecto lee los globales del cliente =====================
local savedCMap, savedZone, savedSub = C_Map, GetRealZoneText, GetSubZoneText
C_Map, GetRealZoneText, GetSubZoneText = nil, nil, nil
check("sin APIs del cliente (el entorno de pruebas no las tiene) la instancia por defecto devuelve 'unknown', 'api_missing'",
    select(2, Chronicle.MapPosition:GetPosition()) == "api_missing" and select(2, Chronicle.MapPosition:GetZoneName()) == "api_missing"
        and select(2, Chronicle.MapPosition:GetSubzoneName()) == "api_missing")
C_Map = { GetBestMapForUnit = function() return 7 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.125, 0.75 end } end }
GetRealZoneText = function() return "Loch Modan" end
GetSubZoneText = function() return "Thelsamar" end
local dp, dv = Chronicle.MapPosition:GetPosition()
check("la instancia por defecto lee los globales EN CADA LLAMADA (si cambian, cambia el resultado)",
    dp == "available" and dv.mapID == 7 and dv.x == 0.125 and dv.y == 0.75
        and select(2, Chronicle.MapPosition:GetZoneName()) == "Loch Modan" and select(2, Chronicle.MapPosition:GetSubzoneName()) == "Thelsamar")
GetRealZoneText = function() return "Dun Morogh" end
check("... incluido un cambio de zona", select(2, Chronicle.MapPosition:GetZoneName()) == "Dun Morogh")
C_Map, GetRealZoneText, GetSubZoneText = savedCMap, savedZone, savedSub

-- ===================== Alcance del servicio =====================
local function sourceOf(name)
    for _, file in ipairs(ADDON_FILES) do if file.name == name then return file.source end end
end
local function codeLines(name)
    local lines = {}
    for line in sourceOf(name):gmatch("[^\n]+") do
        if not line:match("^%s*%-%-") then lines[#lines + 1] = line end
    end
    return lines
end
check("MapPosition no crea frames, temporizadores, sonidos ni elementos de interfaz, ni escucha eventos",
    (function()
        local forbidden = { "CreateFrame", "C_Timer", "OnUpdate", "PlaySound", "UIParent", "RegisterEvent", "SetScript",
            "StaticPopup", "CreateTexture", "CreateFontString", "DEFAULT_CHAT_FRAME", ":Show(" }
        for _, line in ipairs(codeLines("Services/MapPosition.lua")) do
            for _, word in ipairs(forbidden) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("MapPosition no usa State ni ChronicleCharDB, ni Discovery, Resolver o Registry (solo lee el cliente)",
    (function()
        for _, line in ipairs(codeLines("Services/MapPosition.lua")) do
            for _, word in ipairs({ "ChronicleCharDB", "Chronicle.State", "Chronicle.Discovery", "Chronicle.Resolver", "Chronicle.Registry" }) do
                if line:find(word, 1, true) then return false, word end
            end
        end
        return true
    end)())
check("la API pública de MapPosition es mínima: GetPosition, GetZoneName, GetSubzoneName (y New en la instancia por defecto)",
    (function()
        local keys = {}
        for key in pairs(Chronicle.MapPosition) do keys[#keys + 1] = key end
        table.sort(keys)
        return table.concat(keys, ",") == "GetPosition,GetSubzoneName,GetZoneName,New"
    end)())
check("MapPosition no tiene Init (no tiene estado): Core/Init lo da por inicializado si el módulo existe",
    Chronicle.MapPosition.Init == nil)
