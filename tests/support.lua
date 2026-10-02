-- Utilidades comunes a todos los ficheros de pruebas. Las definen como globales para que
-- cada fichero (cargado como su propio chunk) las use sin repetirlas, y el recuento final
-- sume todos los escenarios.

local passed, failed = 0, 0

function check(name, condition, detail)
    if condition then
        passed = passed + 1
        print(string.format("[OK]   %s", name))
    else
        failed = failed + 1
        print(string.format("[FAIL] %s -- %s", name, detail or ""))
    end
end

-- true si algún string de la lista contiene `text` (búsqueda literal).
function contains(list, text)
    for _, s in ipairs(list) do
        if s:find(text, 1, true) then return true end
    end
    return false
end

-- Igualdad profunda de tablas (valores simples y tablas anidadas).
function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Al terminar todos los ficheros: imprime el recuento y falla si hubo algún FAIL (o si no
-- se ejecutó ninguna comprobación, para no dar por buena una batería vacía).
function FinishTests()
    print(string.format("\nResultado: %d OK, %d FAIL", passed, failed))
    if passed + failed == 0 then error("no se ejecutó ninguna prueba") end
    if failed > 0 then error("hay pruebas fallidas") end
end
