-- GENERADO por chronicle-pipeline 0.1.0. NO EDITAR A MANO: se regenera con `npm run data:generate` (carpeta pipeline/).
-- flavor: era | pack_schema: 1
-- Classic Era. Interface informativo (el del .toc actual); D11 pendiente de verificacion en cliente. capability_policy=block: politica estricta (P10 pendiente).
Chronicle = Chronicle or {}

Chronicle.Pack = {
    discovery = {
        ["continent:eastern_kingdoms"] = {
            method = "none",
        },
    },
    entities = {
        ["continent:eastern_kingdoms"] = {
            importance = "standard",
            status = "published",
            type = "continent",
        },
        ["npc:grelin_whitebeard"] = {
            importance = "standard",
            located_in = "subzone:coldridge_valley",
            status = "published",
            type = "npc",
        },
        ["npc:sten_stoutarm"] = {
            importance = "standard",
            located_in = "subzone:coldridge_valley",
            status = "published",
            type = "npc",
        },
        ["subzone:coldridge_valley"] = {
            importance = "standard",
            parent = "zone:dun_morogh",
            status = "published",
            type = "subzone",
        },
        ["zone:dun_morogh"] = {
            importance = "standard",
            parent = "continent:eastern_kingdoms",
            status = "published",
            type = "zone",
        },
    },
    header = {
        client = {
            interface = {
                11507,
            },
        },
        content_revision = "sha256:ec9239e17730d65db2a54be303c39df54d33d4eee29c10d7f00a0da2feebe782",
        counts = {
            available = 1,
            entities = 5,
            hints = 0,
            published = 5,
            retired = 0,
        },
        features = {
            persist_hints = false,
            persist_interaction_progress = false,
        },
        flavor = "era",
        generated_from = {
            editorial = "sha256:3823ac8f1c971d01ee7d57abc04556ee3e2c655a45d363f55d7a17d4ca58b26d",
            generator = "0.1.0",
            world = "sha256:0bfbe30806727a28c4fd07b8b3159ffcaa81eb3a61d73ab1063b4685dd7cd94b",
        },
        locales = {
            "esES",
        },
        pack_schema = 1,
    },
    hints = {},
    names = {},
    presence = {
        ["continent:eastern_kingdoms"] = {
            available = true,
            tech = {},
        },
        ["npc:grelin_whitebeard"] = {
            available = false,
            reason = "source_not_authorized_for_pack",
            tech = {},
        },
        ["npc:sten_stoutarm"] = {
            available = false,
            reason = "source_not_authorized_for_pack",
            tech = {},
        },
        ["subzone:coldridge_valley"] = {
            available = false,
            reason = "source_not_authorized_for_pack",
            tech = {},
        },
        ["zone:dun_morogh"] = {
            available = false,
            reason = "no_binding",
            tech = {},
        },
    },
    texts = {
        esES = {
            ["continent:eastern_kingdoms"] = {
                title = "Reinos del Este",
            },
            ["npc:grelin_whitebeard"] = {
                title = "Grelin Whitebeard",
            },
            ["npc:sten_stoutarm"] = {
                title = "Sten Stoutarm",
            },
            ["subzone:coldridge_valley"] = {
                title = "Coldridge Valley",
            },
            ["zone:dun_morogh"] = {
                title = "Dun Morogh",
            },
        },
    },
    tombstones = {},
}
