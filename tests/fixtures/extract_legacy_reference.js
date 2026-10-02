// Genera tests/fixtures/legacy_reference.lua: una copia literal de los datos del addon
// ORIGINAL (Zones, NPCs, Cities, Continents), obtenida EJECUTANDO sus ficheros .lua con
// fengari -- no copiando texto a mano --, para que las pruebas de la Fase 3 comparen lo
// migrado contra los valores originales sin normalizar nada.
//
// Solo LEE el addon original (no lo modifica). Uso, desde tests/:
//   node fixtures/extract_legacy_reference.js [ruta/al/Data/del/addon/original]
// La ruta por defecto es ../../Chronicle/Chronicle/Data (el addon original junto a este repo).

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const legacyData = path.resolve(process.argv[2] || path.join(__dirname, "..", "..", "..", "Chronicle", "Chronicle", "Data"));
const outFile = path.join(__dirname, "legacy_reference.lua");

// Mismo orden de carga que el .toc original (solo los ficheros con datos en alcance).
const files = [
    "Zones/DunMorogh.lua", "NPCs/DunMorogh.lua",
    "Zones/LochModan.lua", "NPCs/LochModan.lua",
    "Cities/Ironforge.lua", "NPCs/Ironforge.lua",
    "Continents.lua",
];

function longBracket(str) {
    let level = 0;
    while (str.includes("]" + "=".repeat(level) + "]")) level += 1;
    const eq = "=".repeat(level);
    return `[${eq}[\n${str}\n]${eq}]`;
}
const sources = files
    .map((rel) => `{ name = "${rel}", source = ${longBracket(fs.readFileSync(path.join(legacyData, rel), "utf8"))} }`)
    .join(",\n");

const driver = `
local files = {
${sources}
}
Chronicle = nil
for _, f in ipairs(files) do assert(load(f.source, "@" .. f.name))() end

local NL = string.char(10)
local function isIdentifier(k) return type(k) == "string" and k:match("^[%a_][%w_]*$") end
local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end
local function ser(v, indent)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then return string.format("%.14g", v) end
    if t == "boolean" then return tostring(v) end
    assert(t == "table", "tipo no serializable: " .. t)
    local pad, inner = string.rep("    ", indent), string.rep("    ", indent + 1)
    local out = {}
    if #v > 0 then
        for _, item in ipairs(v) do out[#out + 1] = inner .. ser(item, indent + 1) .. "," end
    else
        for _, k in ipairs(sortedKeys(v)) do
            local key = isIdentifier(k) and k or ("[" .. string.format("%q", k) .. "]")
            out[#out + 1] = inner .. key .. " = " .. ser(v[k], indent + 1) .. ","
        end
    end
    if #out == 0 then return "{}" end
    return "{" .. NL .. table.concat(out, NL) .. NL .. pad .. "}"
end

local ref = {
    continents = Chronicle.Data.Continents,
    zones = Chronicle.Data.Zones,
    cities = Chronicle.Data.Cities,
}
return "LegacyReference = " .. ser(ref, 0) .. NL
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_dostring(L, to_luastring(driver)) !== lua.LUA_OK) {
    console.error(lua.lua_tojsstring(L, -1));
    process.exit(1);
}
const body = lua.lua_tojsstring(L, -1);
const header = `-- GENERADO por tests/fixtures/extract_legacy_reference.js -- NO EDITAR A MANO.
-- Copia literal de los datos del addon original (Data/Zones, Data/NPCs, Data/Cities y
-- Data/Continents), obtenida ejecutando sus ficheros .lua. Es la referencia con la que las
-- pruebas de la Fase 3 comparan los datos migrados, sin normalizar ni alterar el contenido.
-- Estructura: continents[nombre], zones[nombre], cities[nombre]; cada zona/ciudad trae sus
-- subzones[nombre], y cada subzona su lista npcs.

`;
fs.writeFileSync(outFile, header + body, "utf8");
console.log("Escrito " + outFile + " (" + (header + body).length + " caracteres)");
