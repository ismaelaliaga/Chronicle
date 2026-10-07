-- GENERADO por chronicle-pipeline 0.1.0. NO EDITAR A MANO: se regenera con `npm run data:generate` (carpeta pipeline/).
-- flavor: era | pack_schema: 1
-- FIXTURE SINTETICO: todos los datos son inventados. No son datos de WoW.
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
        ["npc:fixture_example_keeper"] = {
            interaction = {
                any = {
                    {
                        type = "gossip",
                    },
                    {
                        type = "quest",
                    },
                },
            },
            method = "interaction",
            required_capabilities = {
                "interaction.gossip",
                "interaction.quest",
                "place.subzone_text",
            },
            requirements = {
                all = {
                    {
                        place_discovered = {
                            id = "subzone:fixture_hollow",
                            strict = true,
                        },
                    },
                    {
                        entity_discovered = {
                            id = "npc:fixture_example_elder",
                        },
                    },
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
        ["npc:fixture_conflicted_example"] = {
            importance = "standard",
            located_in = "subzone:fixture_hollow",
            status = "published",
            type = "npc",
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
        ["npc:fixture_unauthorized_example"] = {
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
            interface = {
                11507,
            },
        },
        content_revision = "sha256:4a640326192e6bf211bba13ba40dd75ef5ab9cd3867db406d85115567752b95a",
        counts = {
            available = 5,
            entities = 7,
            hints = 2,
            published = 7,
            retired = 1,
        },
        features = {
            persist_hints = false,
            persist_interaction_progress = false,
        },
        flavor = "era",
        generated_from = {
            editorial = "sha256:ec2905f31d0459c6e173865a4a19eb7d84168d905505ba8d191c09530d2fe080",
            generator = "0.1.0",
            world = "sha256:9d2cadafa4aa0f88c53852ecdb20f816a60b83f5c0c826b7fddc1591d4eb98ac",
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
        ["hint:fixture_keeper_1"] = {
            depends_on = {
                "hint:fixture_elder_1",
            },
            kind = "contextual",
            necessity = "optional",
            related_to = {
                "npc:fixture_example_elder",
            },
            reveals_when = {
                entity_discovered = {
                    id = "npc:fixture_example_elder",
                },
            },
            target = "npc:fixture_example_keeper",
            text = "hint:fixture_keeper_1",
            tier = 2,
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
        ["npc:fixture_conflicted_example"] = {
            available = false,
            reason = "blocked_by_conflict",
            tech = {},
        },
        ["npc:fixture_example_elder"] = {
            available = true,
            tech = {
                {
                    id = 90004,
                    kind = "creature",
                },
            },
        },
        ["npc:fixture_example_keeper"] = {
            attributes = {
                display_id = 99001,
            },
            available = true,
            tech = {
                {
                    id = 90001,
                    kind = "creature",
                },
            },
        },
        ["npc:fixture_unauthorized_example"] = {
            available = false,
            reason = "source_not_authorized_for_pack",
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
            ["hint:fixture_keeper_1"] = {
                description = "TEXTO_EDITORIAL_PENDIENTE (fixture)",
            },
            ["npc:fixture_conflicted_example"] = {
                title = "En conflicto Fixture",
            },
            ["npc:fixture_example_elder"] = {
                title = "Anciano Fixture",
            },
            ["npc:fixture_example_keeper"] = {
                title = "Guardian Fixture",
            },
            ["npc:fixture_unauthorized_example"] = {
                title = "Sin autorizar Fixture",
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
