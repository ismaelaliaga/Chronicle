-- GENERADO por chronicle-pipeline 0.1.0. NO EDITAR A MANO: se regenera con `npm run data:generate` (carpeta pipeline/).
-- flavor: fixture_alt | pack_schema: 1
-- FIXTURE SINTETICO: segundo flavor ficticio (NO es Forever). Todos los datos son inventados.
Chronicle = Chronicle or {}

Chronicle.Pack = {
    discovery = {
        ["continent:fixture_world"] = {
            method = "none",
        },
        ["npc:fixture_example_elder"] = {
            interaction = {
                type = "gossip",
            },
            method = "interaction",
            required_capabilities = {
                "interaction.gossip",
                "place.zone_text",
            },
            requirements = {
                place_discovered = {
                    derived = true,
                    id = "zone:fixture_land",
                    strict = false,
                },
            },
        },
        ["subzone:fixture_hollow"] = {
            method = "place_enter",
            required_capabilities = {
                "place.subzone_text",
            },
        },
        ["zone:fixture_land"] = {
            method = "place_enter",
            required_capabilities = {
                "place.zone_text",
            },
        },
    },
    entities = {
        ["continent:fixture_world"] = {
            importance = "standard",
            status = "published",
            type = "continent",
        },
        ["npc:fixture_example_elder"] = {
            importance = "major",
            located_in = "subzone:fixture_hollow",
            status = "published",
            type = "npc",
        },
        ["npc:fixture_example_keeper"] = {
            importance = "standard",
            located_in = "subzone:fixture_hollow",
            status = "published",
            type = "npc",
        },
        ["subzone:fixture_hollow"] = {
            importance = "standard",
            parent = "zone:fixture_land",
            status = "published",
            type = "subzone",
        },
        ["zone:fixture_land"] = {
            importance = "standard",
            parent = "continent:fixture_world",
            status = "published",
            type = "zone",
        },
    },
    header = {
        client = {
            interface = {},
        },
        content_revision = "sha256:3b8508f3b6734f28e2d77894c67329a05fd20e0828739d00b05dadc2c2d7da20",
        counts = {
            available = 4,
            entities = 5,
            hints = 1,
            published = 5,
            retired = 1,
        },
        features = {
            persist_hints = false,
            persist_interaction_progress = false,
        },
        flavor = "fixture_alt",
        generated_from = {
            editorial = "sha256:8ff2f80cff107ea1fe0840d27a569ef9254f87d4e91fe2914d305f3a104a36b3",
            generator = "0.1.0",
            world = "sha256:08b52cabf559d64f64d9de578105ad87d32aaf822ae069148d8a8b293b01fdd0",
        },
        locales = {
            "esES",
        },
        pack_schema = 1,
    },
    hints = {
        ["hint:fixture_elder_1"] = {
            kind = "narrative",
            necessity = "required",
            reveals_when = {
                place_discovered = {
                    id = "zone:fixture_land",
                },
            },
            target = "npc:fixture_example_elder",
            text = "hint:fixture_elder_1",
            tier = 1,
        },
    },
    names = {
        esES = {
            subzone_text = {
                ["fixture hollow"] = "subzone:fixture_hollow",
            },
            zone_text = {
                ["fixture land"] = "zone:fixture_land",
            },
        },
    },
    presence = {
        ["continent:fixture_world"] = {
            available = true,
            tech = {},
        },
        ["npc:fixture_example_elder"] = {
            available = true,
            tech = {
                {
                    id = 90008,
                    kind = "creature",
                },
            },
        },
        ["npc:fixture_example_keeper"] = {
            available = false,
            reason = "capability_unverified:interaction.quest",
            tech = {},
        },
        ["subzone:fixture_hollow"] = {
            available = true,
            tech = {},
        },
        ["zone:fixture_land"] = {
            available = true,
            tech = {},
        },
    },
    texts = {
        esES = {
            ["continent:fixture_world"] = {
                title = "Mundo Fixture",
            },
            ["hint:fixture_elder_1"] = {
                description = "TEXTO_EDITORIAL_PENDIENTE (fixture)",
            },
            ["npc:fixture_example_elder"] = {
                title = "Anciano Fixture",
            },
            ["npc:fixture_example_keeper"] = {
                title = "Guardian Fixture",
            },
            ["subzone:fixture_hollow"] = {
                title = "Hondonada Fixture",
            },
            ["zone:fixture_land"] = {
                title = "Tierra Fixture",
            },
        },
    },
    tombstones = {
        ["npc:fixture_retired_example"] = {
            located_in = "subzone:fixture_hollow",
            status = "retired",
            superseded_by = "npc:fixture_example_keeper",
            type = "npc",
        },
    },
}
