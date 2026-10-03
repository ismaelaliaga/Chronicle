Chronicle = Chronicle or {}

-- CodexNpcModel: el visor 3D de un NPC dentro de la página del Codex (Fase 11). Interno de la UI del Codex; no forma parte de
-- ninguna API pública y su frame nunca sale de aquí.
--
-- QUÉ USA DEL CLIENTE (ninguna de estas APIs se ha podido ejecutar en un cliente real de Classic Era; se detectan antes de usarse):
--   · CreateFrame("PlayerModel", nil, padre): el widget del modelo del personaje. La wiki de la API documenta sus métodos pero no
--     indica si el tipo existe en la interfaz 11507, así que su creación va en pcall: si falla, el visor queda NO DISPONIBLE y la
--     página funciona igual, sin marco.
--   · Model:SetDisplayInfo(displayID): muestra el modelo de un Creature Display ID. Es la llamada correcta para el dato que
--     guarda Chronicle (`displayID`). Documentada para Classic Era (1.15.x) en la wiki de la API.
--   · Respaldo si el frame no tiene SetDisplayInfo: SetCreature(npcID, displayID) (documentada como SetCreature(creatureID
--     [, displayID])), solo si hay un `npcID` válido. NOTA: el addon original llamaba a SetCreature(displayID), que según esa
--     documentación pasa un display ID donde se espera un creature ID; NO se ha copiado.
--   · Model:ClearModel(), si existe: se usa para vaciar el visor al reutilizarlo.
--   Sin ninguna de las dos llamadas de modelo el visor no está disponible. No se usa OnUpdate, temporizadores, rotación ni
--   animaciones, ni se activa el ratón del frame: el visor no puede capturar la rueda ni los clics de la página.
--
-- UN SOLO WIDGET REUTILIZADO. Se crea una vez (Attach). Antes de mostrar otro modelo se oculta y se vacía; al ocultarse se vacía
-- también, de modo que nunca queda visible (ni cargado) el modelo del NPC anterior. No se le ponen scripts.
-- AISLAMIENTO. Ningún método lanza errores: cada llamada al cliente va en pcall, el fallo se comunica una vez por mensaje
-- (geterrorhandler) y el visor se oculta. Un fallo del visor no afecta al resto de la página.
--
-- API: Chronicle.CodexNpcModel.New({ theme, createFrame }) -> visor
--   visor:Attach(parent, maxWidth)        crea el widget (una vez); nunca lanza error
--   visor:IsAvailable()                   ¿hay un visor utilizable?
--   visor:Show(spec, x, y)                spec = { displayID, npcID }; lo coloca en (x, -y) del padre y lo muestra.
--                                         -> true | false (false: no disponible, datos inválidos o el cliente falló; queda oculto)
--   visor:Hide()                          lo oculta y lo vacía
--   visor:IsShown()                       lee el frame real
--   visor:GetSize()                       ancho, alto (de Theme, limitado al ancho disponible)
-- Colores y medidas salen de Theme (CODEX_MODEL_WIDTH / CODEX_MODEL_HEIGHT y el color BG_PANEL).

local function IsObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function IsPositiveInteger(value)
    return type(value) == "number" and value == value and value >= 1 and value < 4294967296 and value == math.floor(value)
end

local function NewNpcModel(deps)
    if type(deps) ~= "table" or type(deps.theme) ~= "table" or type(deps.createFrame) ~= "function" then
        error("Chronicle.CodexNpcModel.New: se esperaba una tabla { theme, createFrame }", 2)
    end
    local theme, createFrame = deps.theme, deps.createFrame
    local self = {}
    local frame, box, parentFrame
    local available = false
    local width, height = 0, 0
    local reported = {}

    local function Report(message)
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

    -- Vacía y oculta el visor. Cada paso va protegido: un fallo no puede dejar de ocultarlo.
    local function Reset()
        if not frame then
            return
        end
        local okHide, errHide = pcall(frame.Hide, frame)
        if not okHide then
            Report("Chronicle.CodexNpcModel: no se pudo ocultar el visor: " .. tostring(errHide))
        end
        if type(frame.ClearModel) == "function" then
            local okClear, errClear = pcall(frame.ClearModel, frame)
            if not okClear then
                Report("Chronicle.CodexNpcModel: no se pudo vaciar el visor: " .. tostring(errClear))
            end
        end
        if box then
            pcall(box.Hide, box)
        end
    end

    function self:Attach(parent, maxWidth)
        if frame or not IsObject(parent) then
            return
        end
        local okLayout, w, h = pcall(function()
            return theme:GetLayout("CODEX_MODEL_WIDTH"), theme:GetLayout("CODEX_MODEL_HEIGHT")
        end)
        if not okLayout or type(w) ~= "number" or type(h) ~= "number" then
            return
        end
        width = (type(maxWidth) == "number" and maxWidth > 0) and math.min(w, maxWidth) or w
        height = h
        local ok, created = pcall(createFrame, "PlayerModel", nil, parent)
        if not ok or not IsObject(created) then
            Report("Chronicle.CodexNpcModel: no se pudo crear el visor 3D (se muestra la página sin él): " .. tostring(created))
            return
        end
        if type(created.SetDisplayInfo) ~= "function" and type(created.SetCreature) ~= "function" then
            pcall(created.Hide, created) -- un frame sin API de modelo no sirve: se deja oculto
            Report("Chronicle.CodexNpcModel: el frame creado no tiene SetDisplayInfo ni SetCreature (se muestra la página sin visor)")
            return
        end
        frame, parentFrame = created, parent
        pcall(frame.Hide, frame) -- un frame recién creado es visible en el cliente
        -- Fondo del visor con el color de panel de Theme (detrás del frame; se muestra solo con un modelo).
        local okBox, texture = pcall(function()
            local t = parent:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(theme:GetTexture("SOLID"))
            local color = theme:GetColor("BG_PANEL")
            t:SetVertexColor(color[1], color[2], color[3], color[4])
            t:Hide()
            return t
        end)
        if okBox then box = texture end
        available = true
    end

    function self:IsAvailable()
        return available
    end

    function self:GetSize()
        return width, height
    end

    function self:IsShown()
        if not frame then
            return false
        end
        local ok, shown = pcall(frame.IsShown, frame)
        return ok and shown == true
    end

    function self:Hide()
        Reset()
    end

    function self:Show(spec, x, y)
        if not available or type(spec) ~= "table" or not IsPositiveInteger(spec.displayID)
            or type(x) ~= "number" or type(y) ~= "number" then
            Reset() -- nunca queda cargado el modelo anterior
            return false
        end
        Reset() -- se vacía el modelo anterior ANTES de cargar el nuevo
        local ok, err = pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", x, -y)
            frame:SetSize(width, height)
            if type(frame.SetDisplayInfo) == "function" then
                frame:SetDisplayInfo(spec.displayID)
            elseif type(frame.SetCreature) == "function" and IsPositiveInteger(spec.npcID) then
                frame:SetCreature(spec.npcID, spec.displayID)
            else
                error("no hay una llamada de modelo utilizable para estos datos", 0)
            end
            if box then
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", x, -y)
                box:SetSize(width, height)
                box:Show()
            end
            frame:Show()
        end)
        if not ok then
            Report("Chronicle.CodexNpcModel: no se pudo mostrar el modelo: " .. tostring(err))
            Reset()
            return false
        end
        if not self:IsShown() then
            Reset()
            return false
        end
        return true
    end

    return self
end

Chronicle.CodexNpcModel = { New = NewNpcModel }
