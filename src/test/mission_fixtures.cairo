use traits::Into;
use influence::components::product_type::types as products;
use influence::components::processor::types as processors;
use influence::components::process_type::types as processes;
use influence::components::inventory_type::types as inventories;
use influence::components::building_type::types as buildings;
// Recipe and material fixtures from the installed @influenceth/sdk, using bin/lib update
// conversions.
use array::ArrayTrait;
use influence::components;
use influence::components::{ProcessType, ProductType, BuildingType, InventoryType};
use influence::types::InventoryItem;

fn configs() {
    components::set::<
        ProcessType
    >(
        array![processes::WATER_VACUUM_EVAPORATION_DESALINATION.into()].span(),
        ProcessType {
            setup_time: 57600,
            recipe_time: 4536,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![InventoryItem { product: products::WATER, amount: 20 }].span(),
            outputs: array![
                InventoryItem { product: products::DEIONIZED_WATER, amount: 19 },
                InventoryItem { product: products::RAW_SALTS, amount: 1 }
            ]
                .span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::WATER_ELECTROLYSIS.into()].span(),
        ProcessType {
            setup_time: 7200,
            recipe_time: 56160,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![InventoryItem { product: products::DEIONIZED_WATER, amount: 9 }].span(),
            outputs: array![
                InventoryItem { product: products::HYDROGEN, amount: 1 },
                InventoryItem { product: products::OXYGEN, amount: 8 }
            ]
                .span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::CALCITE_CALCINATION.into()].span(),
        ProcessType {
            setup_time: 7200,
            recipe_time: 7200,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![InventoryItem { product: products::CALCITE, amount: 100 }].span(),
            outputs: array![
                InventoryItem { product: products::CARBON_DIOXIDE, amount: 44 },
                InventoryItem { product: products::QUICKLIME, amount: 56 }
            ]
                .span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::SALTY_CEMENT_MIXING.into()].span(),
        ProcessType {
            setup_time: 21600,
            recipe_time: 297,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![
                InventoryItem { product: products::WATER, amount: 5 },
                InventoryItem { product: products::QUICKLIME, amount: 3 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::CEMENT, amount: 7 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::BITUMEN_HYDRO_CRACKING.into()].span(),
        ProcessType {
            setup_time: 43200,
            recipe_time: 37440,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![
                InventoryItem { product: products::HYDROGEN, amount: 7 },
                InventoryItem { product: products::BITUMEN, amount: 200 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::NAPHTHA, amount: 60 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::NAPHTHA_STEAM_CRACKING.into()].span(),
        ProcessType {
            setup_time: 36000,
            recipe_time: 720,
            batched: false,
            processor_type: processors::REFINERY,
            inputs: array![
                InventoryItem { product: products::DEIONIZED_WATER, amount: 4 },
                InventoryItem { product: products::NAPHTHA, amount: 16 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::PROPYLENE, amount: 3 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::SILICA_FUSING.into()].span(),
        ProcessType {
            setup_time: 43200,
            recipe_time: 479,
            batched: false,
            processor_type: processors::FACTORY,
            inputs: array![InventoryItem { product: products::SILICA, amount: 1 }].span(),
            outputs: array![InventoryItem { product: products::FUSED_QUARTZ, amount: 1 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::QUARTZ_FILAMENT_DRAWING_AND_WRAPPING.into()].span(),
        ProcessType {
            setup_time: 144000,
            recipe_time: 360000,
            batched: false,
            processor_type: processors::FACTORY,
            inputs: array![
                InventoryItem { product: products::FUSED_QUARTZ, amount: 1 },
                InventoryItem { product: products::POLYPROPYLENE, amount: 4 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::FIBER_OPTIC_CABLE, amount: 5 }]
                .span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::SOYBEAN_GROWING.into()].span(),
        ProcessType {
            setup_time: 115200,
            recipe_time: 6480000000,
            batched: true,
            processor_type: processors::BIOREACTOR,
            inputs: array![
                InventoryItem { product: products::AMMONIA, amount: 2600 },
                InventoryItem { product: products::CARBON_DIOXIDE, amount: 52000 },
                InventoryItem { product: products::DEIONIZED_WATER, amount: 2200 },
                InventoryItem { product: products::TRIPLE_SUPERPHOSPHATE, amount: 640 },
                InventoryItem { product: products::PHOSPHATE_AND_SULFATE_SALTS, amount: 400 },
                InventoryItem { product: products::POTASSIUM_CHLORIDE, amount: 840 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::SOYBEANS, amount: 26000 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::BASIC_FOOD_COOKING_AND_PACKAGING.into()].span(),
        ProcessType {
            setup_time: 144000,
            recipe_time: 86400,
            batched: false,
            processor_type: processors::FACTORY,
            inputs: array![
                InventoryItem { product: products::SODIUM_CHLORIDE, amount: 1 },
                InventoryItem { product: products::SPIRULINA_AND_CHLORELLA_ALGAE, amount: 120 },
                InventoryItem { product: products::SOYBEANS, amount: 160 },
                InventoryItem { product: products::POTATOES, amount: 160 },
                InventoryItem { product: products::NATURAL_FLAVORINGS, amount: 39 }
            ]
                .span(),
            outputs: array![InventoryItem { product: products::FOOD, amount: 480 }].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::WAREHOUSE_CONSTRUCTION.into()].span(),
        ProcessType {
            setup_time: 1728000,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![
                InventoryItem { product: products::CEMENT, amount: 400000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 350000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 200000 }
            ]
                .span(),
            outputs: array![].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::EXTRACTOR_CONSTRUCTION.into()].span(),
        ProcessType {
            setup_time: 2073600,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![
                InventoryItem { product: products::CEMENT, amount: 250000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 300000 },
                InventoryItem { product: products::POLYACRYLONITRILE_FABRIC, amount: 3000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 1 },
                InventoryItem { product: products::POWER_MODULE, amount: 6 }
            ]
                .span(),
            outputs: array![].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::REFINERY_CONSTRUCTION.into()].span(),
        ProcessType {
            setup_time: 4147200,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![
                InventoryItem { product: products::CEMENT, amount: 600000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 300000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 200000 },
                InventoryItem { product: products::PLATINUM, amount: 2 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 12 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 2 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 2 },
                InventoryItem { product: products::POWER_MODULE, amount: 16 },
                InventoryItem { product: products::THERMAL_MODULE, amount: 4 }
            ]
                .span(),
            outputs: array![].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::BIOREACTOR_CONSTRUCTION.into()].span(),
        ProcessType {
            setup_time: 3456000,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![
                InventoryItem { product: products::DEIONIZED_WATER, amount: 1400000 },
                InventoryItem { product: products::FUSED_QUARTZ, amount: 300000 },
                InventoryItem { product: products::CEMENT, amount: 500000 },
                InventoryItem { product: products::SOIL, amount: 300000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 100000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 300000 },
                InventoryItem { product: products::POLYPROPYLENE, amount: 25000 },
                InventoryItem { product: products::PURE_NITROGEN, amount: 125000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 16 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 12 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 3 },
                InventoryItem { product: products::POWER_MODULE, amount: 8 }
            ]
                .span(),
            outputs: array![].span()
        }
    );
    components::set::<
        ProcessType
    >(
        array![processes::FACTORY_CONSTRUCTION.into()].span(),
        ProcessType {
            setup_time: 5184000,
            recipe_time: 0,
            batched: false,
            processor_type: 0,
            inputs: array![
                InventoryItem { product: products::CEMENT, amount: 900000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 1100000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 700000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 4 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 40 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 8 },
                InventoryItem { product: products::POWER_MODULE, amount: 20 },
                InventoryItem { product: products::THERMAL_MODULE, amount: 6 }
            ]
                .span(),
            outputs: array![].span()
        }
    );
    components::set::<
        ProductType
    >(array![products::WATER.into()].span(), ProductType { mass: 1000, volume: 971 });
    components::set::<
        ProductType
    >(array![products::HYDROGEN.into()].span(), ProductType { mass: 1000, volume: 14100 });
    components::set::<
        ProductType
    >(array![products::AMMONIA.into()].span(), ProductType { mass: 1000, volume: 1370 });
    components::set::<
        ProductType
    >(array![products::CARBON_DIOXIDE.into()].span(), ProductType { mass: 1000, volume: 801 });
    components::set::<
        ProductType
    >(array![products::CARBON_MONOXIDE.into()].span(), ProductType { mass: 1000, volume: 1250 });
    components::set::<
        ProductType
    >(array![products::BITUMEN.into()].span(), ProductType { mass: 1000, volume: 1600 });
    components::set::<
        ProductType
    >(array![products::CALCITE.into()].span(), ProductType { mass: 1000, volume: 615 });
    components::set::<
        ProductType
    >(array![products::OXYGEN.into()].span(), ProductType { mass: 1000, volume: 876 });
    components::set::<
        ProductType
    >(array![products::DEIONIZED_WATER.into()].span(), ProductType { mass: 1000, volume: 1000 });
    components::set::<
        ProductType
    >(array![products::RAW_SALTS.into()].span(), ProductType { mass: 1000, volume: 775 });
    components::set::<
        ProductType
    >(array![products::SILICA.into()].span(), ProductType { mass: 1000, volume: 629 });
    components::set::<
        ProductType
    >(array![products::NAPHTHA.into()].span(), ProductType { mass: 1000, volume: 1300 });
    components::set::<
        ProductType
    >(array![products::QUICKLIME.into()].span(), ProductType { mass: 1000, volume: 599 });
    components::set::<
        ProductType
    >(
        array![products::TRIPLE_SUPERPHOSPHATE.into()].span(),
        ProductType { mass: 1000, volume: 870 }
    );
    components::set::<
        ProductType
    >(
        array![products::PHOSPHATE_AND_SULFATE_SALTS.into()].span(),
        ProductType { mass: 1000, volume: 595 }
    );
    components::set::<
        ProductType
    >(array![products::FUSED_QUARTZ.into()].span(), ProductType { mass: 1000, volume: 415 });
    components::set::<
        ProductType
    >(array![products::CEMENT.into()].span(), ProductType { mass: 1000, volume: 1130 });
    components::set::<
        ProductType
    >(array![products::SODIUM_CHLORIDE.into()].span(), ProductType { mass: 1000, volume: 1410 });
    components::set::<
        ProductType
    >(array![products::POTASSIUM_CHLORIDE.into()].span(), ProductType { mass: 1000, volume: 842 });
    components::set::<
        ProductType
    >(array![products::PROPYLENE.into()].span(), ProductType { mass: 1000, volume: 2040 });
    components::set::<
        ProductType
    >(array![products::SOIL.into()].span(), ProductType { mass: 1000, volume: 714 });
    components::set::<
        ProductType
    >(
        array![products::SPIRULINA_AND_CHLORELLA_ALGAE.into()].span(),
        ProductType { mass: 1000, volume: 2500 }
    );
    components::set::<
        ProductType
    >(array![products::FIBER_OPTIC_CABLE.into()].span(), ProductType { mass: 1000, volume: 886 });
    components::set::<
        ProductType
    >(array![products::STEEL_BEAM.into()].span(), ProductType { mass: 1000, volume: 1100 });
    components::set::<
        ProductType
    >(array![products::STEEL_SHEET.into()].span(), ProductType { mass: 1000, volume: 150 });
    components::set::<
        ProductType
    >(array![products::POLYPROPYLENE.into()].span(), ProductType { mass: 1000, volume: 1570 });
    components::set::<
        ProductType
    >(array![products::SOYBEANS.into()].span(), ProductType { mass: 1000, volume: 1530 });
    components::set::<
        ProductType
    >(array![products::POTATOES.into()].span(), ProductType { mass: 1000, volume: 1520 });
    components::set::<
        ProductType
    >(array![products::NATURAL_FLAVORINGS.into()].span(), ProductType { mass: 1000, volume: 1820 });
    components::set::<
        ProductType
    >(array![products::PLATINUM.into()].span(), ProductType { mass: 1000, volume: 58 });
    components::set::<
        ProductType
    >(
        array![products::POLYACRYLONITRILE_FABRIC.into()].span(),
        ProductType { mass: 1000, volume: 2820 }
    );
    components::set::<
        ProductType
    >(array![products::FOOD.into()].span(), ProductType { mass: 1000, volume: 1250 });
    components::set::<
        ProductType
    >(
        array![products::SMALL_PROPELLANT_TANK.into()].span(),
        ProductType { mass: 6000, volume: 87000 }
    );
    components::set::<
        ProductType
    >(array![products::PURE_NITROGEN.into()].span(), ProductType { mass: 1000, volume: 1240 });
    components::set::<
        ProductType
    >(
        array![products::FLUIDS_AUTOMATION_MODULE.into()].span(),
        ProductType { mass: 3600000, volume: 301320000 }
    );
    components::set::<
        ProductType
    >(
        array![products::SOLIDS_AUTOMATION_MODULE.into()].span(),
        ProductType { mass: 3600000, volume: 11736000 }
    );
    components::set::<
        ProductType
    >(
        array![products::AVIONICS_MODULE.into()].span(),
        ProductType { mass: 500000, volume: 12200000 }
    );
    components::set::<
        ProductType
    >(array![products::POWER_MODULE.into()].span(), ProductType { mass: 1000000, volume: 3800000 });
    components::set::<
        ProductType
    >(
        array![products::THERMAL_MODULE.into()].span(),
        ProductType { mass: 1000000, volume: 399000 }
    );
    components::set::<
        BuildingType
    >(
        array![buildings::WAREHOUSE.into()].span(),
        BuildingType {
            process_type: processes::WAREHOUSE_CONSTRUCTION,
            site_slot: 1,
            site_type: inventories::WAREHOUSE_SITE
        }
    );
    components::set::<
        InventoryType
    >(
        array![inventories::WAREHOUSE_SITE.into()].span(),
        InventoryType {
            mass: 1125899906842623,
            volume: 1125899906842623,
            modifiable: false,
            products: array![
                InventoryItem { product: products::CEMENT, amount: 400000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 350000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 200000 }
            ]
                .span()
        }
    );
    components::set::<
        BuildingType
    >(
        array![buildings::EXTRACTOR.into()].span(),
        BuildingType {
            process_type: processes::EXTRACTOR_CONSTRUCTION,
            site_slot: 1,
            site_type: inventories::EXTRACTOR_SITE
        }
    );
    components::set::<
        InventoryType
    >(
        array![inventories::EXTRACTOR_SITE.into()].span(),
        InventoryType {
            mass: 1125899906842623,
            volume: 1125899906842623,
            modifiable: false,
            products: array![
                InventoryItem { product: products::CEMENT, amount: 250000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 300000 },
                InventoryItem { product: products::POLYACRYLONITRILE_FABRIC, amount: 3000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 1 },
                InventoryItem { product: products::POWER_MODULE, amount: 6 }
            ]
                .span()
        }
    );
    components::set::<
        BuildingType
    >(
        array![buildings::REFINERY.into()].span(),
        BuildingType {
            process_type: processes::REFINERY_CONSTRUCTION,
            site_slot: 1,
            site_type: inventories::REFINERY_SITE
        }
    );
    components::set::<
        InventoryType
    >(
        array![inventories::REFINERY_SITE.into()].span(),
        InventoryType {
            mass: 1125899906842623,
            volume: 1125899906842623,
            modifiable: false,
            products: array![
                InventoryItem { product: products::CEMENT, amount: 600000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 300000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 200000 },
                InventoryItem { product: products::PLATINUM, amount: 2 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 12 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 2 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 2 },
                InventoryItem { product: products::POWER_MODULE, amount: 16 },
                InventoryItem { product: products::THERMAL_MODULE, amount: 4 }
            ]
                .span()
        }
    );
    components::set::<
        BuildingType
    >(
        array![buildings::BIOREACTOR.into()].span(),
        BuildingType {
            process_type: processes::BIOREACTOR_CONSTRUCTION,
            site_slot: 1,
            site_type: inventories::BIOREACTOR_SITE
        }
    );
    components::set::<
        InventoryType
    >(
        array![inventories::BIOREACTOR_SITE.into()].span(),
        InventoryType {
            mass: 1125899906842623,
            volume: 1125899906842623,
            modifiable: false,
            products: array![
                InventoryItem { product: products::DEIONIZED_WATER, amount: 1400000 },
                InventoryItem { product: products::FUSED_QUARTZ, amount: 300000 },
                InventoryItem { product: products::CEMENT, amount: 500000 },
                InventoryItem { product: products::SOIL, amount: 300000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 100000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 300000 },
                InventoryItem { product: products::POLYPROPYLENE, amount: 25000 },
                InventoryItem { product: products::PURE_NITROGEN, amount: 125000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 16 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 12 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 3 },
                InventoryItem { product: products::POWER_MODULE, amount: 8 }
            ]
                .span()
        }
    );
    components::set::<
        BuildingType
    >(
        array![buildings::FACTORY.into()].span(),
        BuildingType {
            process_type: processes::FACTORY_CONSTRUCTION,
            site_slot: 1,
            site_type: inventories::FACTORY_SITE
        }
    );
    components::set::<
        InventoryType
    >(
        array![inventories::FACTORY_SITE.into()].span(),
        InventoryType {
            mass: 1125899906842623,
            volume: 1125899906842623,
            modifiable: false,
            products: array![
                InventoryItem { product: products::CEMENT, amount: 900000 },
                InventoryItem { product: products::STEEL_BEAM, amount: 1100000 },
                InventoryItem { product: products::STEEL_SHEET, amount: 700000 },
                InventoryItem { product: products::FLUIDS_AUTOMATION_MODULE, amount: 4 },
                InventoryItem { product: products::SOLIDS_AUTOMATION_MODULE, amount: 40 },
                InventoryItem { product: products::AVIONICS_MODULE, amount: 8 },
                InventoryItem { product: products::POWER_MODULE, amount: 20 },
                InventoryItem { product: products::THERMAL_MODULE, amount: 6 }
            ]
                .span()
        }
    );
}
