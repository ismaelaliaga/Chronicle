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
        content_revision = "sha256:cdfd4d129e72eeac3985746aa52d842b47605ca81cf4e66dc39562459d2ad55c",
        counts = {
            available = 1,
            entities = 3,
            hints = 0,
            published = 3,
            retired = 0,
        },
        features = {
            persist_hints = false,
            persist_interaction_progress = false,
        },
        flavor = "era",
        generated_from = {
            editorial = "sha256:b1db56d613ed8a79add4753b6cb48bf224bd302f18ffd1d2cf34ecf0718258a7",
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
