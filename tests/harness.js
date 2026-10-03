// Ejecuta el Lua REAL del addon Chronicle (V2) contra un mock mínimo de la API de WoW
// (mock.lua) usando fengari (una VM de Lua en JS), y corre los escenarios de core_tests.lua.
//
// El orden de carga se lee de Chronicle.toc, no de una lista duplicada: si el .toc está
// mal ordenado, estas pruebas lo detectan. NO sustituye probar en el cliente real.

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ADDON_DIR = path.join(__dirname, "..", "Chronicle");

const tocFiles = fs
    .readFileSync(path.join(ADDON_DIR, "Chronicle.toc"), "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== "" && !line.startsWith("#"));

function toLuaLongBracket(str) {
    let level = 0;
    while (str.includes("]" + "=".repeat(level) + "]")) {
        level += 1;
    }
    const eq = "=".repeat(level);
    return `[${eq}[\n${str}\n]${eq}]`;
}

// Cada fichero se carga como su propio chunk, igual que hace el cliente con el .toc.
const fileSources = tocFiles
    .map((rel) => {
        const src = fs.readFileSync(path.join(ADDON_DIR, rel), "utf8");
        return `{ name = "${rel}", source = ${toLuaLongBracket(src)} }`;
    })
    .join(",\n");

// Ficheros de pruebas, en orden. support.lua primero: define los helpers comunes.
const TEST_FILES = [
    "support.lua",
    "fixtures/legacy_reference.lua", // datos del addon original (referencia de la Fase 3)
    "core_tests.lua",
    "schema_tests.lua",
    "registry_tests.lua",
    "data_tests.lua",
    "localization_tests.lua",
    "resolver_tests.lua",
    "discovery_tests.lua",
    "mapposition_tests.lua",
    "proximity_tests.lua",
    "zonediscovery_tests.lua",
    "theme_tests.lua",
    "popup_tests.lua",
    "codex_tests.lua",
];
const testFileSources = TEST_FILES.map((name) => {
    const src = fs.readFileSync(path.join(__dirname, name), "utf8");
    return `{ name = "tests/${name}", source = ${toLuaLongBracket(src)} }`;
}).join(",\n");

const driverSource = `
${fs.readFileSync(path.join(__dirname, "mock.lua"), "utf8")}

ADDON_FILES = {
${fileSources}
}

-- Simula una carga del addon: ejecuta cada fichero del .toc en orden. NO dispara
-- ADDON_LOADED (eso lo hace cada prueba cuando quiere), y deja ChronicleCharDB como
-- esté, igual que el cliente real, que lo rellena antes de ejecutar ningún fichero.
--
-- exclude (opcional): patrón Lua, o lista de patrones, de ficheros del .toc que NO se
-- cargan. Lo usan las pruebas del Registry para trabajar sin los datos reales (Data/Entities
-- y Localization/esES) y comprobar el Registry con sus propias entidades de ejemplo.
function LoadAddon(exclude)
    local patterns = type(exclude) == "string" and { exclude } or exclude or {}
    Chronicle = nil
    ResetMockRuntime()
    for _, file in ipairs(ADDON_FILES) do
        local skip = false
        for _, pattern in ipairs(patterns) do
            if file.name:find(pattern) then skip = true end
        end
        if not skip then
            local chunk = assert(load(file.source, "@" .. file.name))
            chunk()
        end
    end
end

-- Cada fichero de pruebas se ejecuta como su propio chunk (sus "local" no se mezclan).
-- support.lua define check/contains/deepEqual/FinishTests como globales.
TEST_FILES = {
${testFileSources}
}
for _, file in ipairs(TEST_FILES) do
    assert(load(file.source, "@" .. file.name))()
end
FinishTests()
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const status = lauxlib.luaL_dostring(L, to_luastring(driverSource));
if (status !== lua.LUA_OK) {
    console.error("\n[HARNESS] La ejecución de Lua ha fallado:\n");
    console.error(lua.lua_tojsstring(L, -1));
    process.exit(1);
}
console.log("\n[HARNESS] Todos los escenarios se han ejecutado correctamente.");
