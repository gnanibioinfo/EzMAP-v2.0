################################################################################
# panels/panel-server-funguild.R — FunGuild Ecological Guild Assignment Server
#
# Assigns ecological guild annotations to fungal taxa using a built-in
# genus-to-guild mapping table derived from the FunGuild database
# (Nguyen et al. 2016, Fungal Ecology 20:241-248).
#
# Algorithm:
#   1. Extract taxonomy from the phyloseq object
#   2. Match taxa (Genus or Species) against the FunGuild database
#   3. Assign trophic mode, guild, and growth morphology
#   4. Compute per-sample guild/trophic proportions (abundance-weighted)
#   5. Compare groups with Kruskal-Wallis or Wilcoxon tests
#
# Trophic modes: Saprotroph, Pathotroph, Symbiotroph (and combinations)
# Confidence ranks: Highly Probable (species match), Probable (genus match),
#                   Possible (family/higher match)
#
# Cross-platform: No external API calls — database is fully embedded.
################################################################################

funguildServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # ==================================================================
    # Built-in FunGuild database: Genus -> Guild mapping
    # Covers ~180 common fungal genera found in ITS amplicon studies.
    # Fields: Genus, Trophic_Mode, Guild, Growth_Morphology, Confidence
    # ==================================================================
    .build_funguild_db <- function() {
      entries <- list(
        # --- Saprotrophs (decomposers) ---
        list("Aspergillus",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Penicillium",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Trichoderma",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Mucor",            "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Rhizopus",         "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Mortierella",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Highly Probable"),
        list("Umbelopsis",       "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Cladosporium",     "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Alternaria",       "Saprotroph-Pathotroph", "Plant Saprotroph-Plant Pathogen", "Microfungus", "Probable"),
        list("Epicoccum",        "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Probable"),
        list("Aureobasidium",    "Saprotroph-Pathotroph", "Undefined Saprotroph-Plant Pathogen", "Microfungus", "Probable"),
        list("Chaetomium",       "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Humicola",         "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Stachybotrys",     "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Scopulariopsis",   "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Talaromyces",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Paecilomyces",     "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Thermomyces",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Myceliophthora",   "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),

        # Wood / Litter saprotrophs
        list("Trametes",         "Saprotroph",  "Wood Saprotroph",                "Agaricomycetes",  "Highly Probable"),
        list("Ganoderma",        "Saprotroph-Pathotroph", "Wood Saprotroph-Plant Pathogen", "Agaricomycetes", "Probable"),
        list("Schizophyllum",    "Saprotroph",  "Wood Saprotroph",                "Agaricomycetes",  "Highly Probable"),
        list("Stereum",          "Saprotroph",  "Wood Saprotroph",                "Agaricomycetes",  "Highly Probable"),
        list("Phanerochaete",    "Saprotroph",  "Wood Saprotroph",                "Agaricomycetes",  "Highly Probable"),
        list("Hypholoma",        "Saprotroph",  "Wood Saprotroph",                "Agaricomycetes",  "Probable"),
        list("Coprinellus",      "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Coprinopsis",      "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Mycena",           "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Marasmius",        "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Gymnopus",         "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Stropharia",       "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Clitocybe",        "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),
        list("Lycoperdon",       "Saprotroph",  "Litter Saprotroph",              "Agaricomycetes",  "Probable"),

        # Dung saprotrophs
        list("Podospora",        "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Highly Probable"),
        list("Sordaria",         "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Highly Probable"),
        list("Sporormiella",     "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Highly Probable"),
        list("Pilobolus",        "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Highly Probable"),
        list("Ascobolus",        "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Probable"),
        list("Preussia",         "Saprotroph",  "Dung Saprotroph",                "Microfungus",     "Probable"),

        # Aquatic / undefined saprotrophs
        list("Articulospora",    "Saprotroph",  "Aquatic Saprotroph",             "Microfungus",     "Probable"),
        list("Tetracladium",     "Saprotroph",  "Aquatic Saprotroph",             "Microfungus",     "Probable"),
        list("Lemonniera",       "Saprotroph",  "Aquatic Saprotroph",             "Microfungus",     "Probable"),

        # Yeasts (saprotrophic)
        list("Saccharomyces",    "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Pichia",           "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Wickerhamomyces",  "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Debaryomyces",     "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Meyerozyma",       "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Kazachstania",     "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Torulaspora",      "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Kluyveromyces",    "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Yarrowia",         "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Rhodotorula",      "Saprotroph",  "Undefined Saprotroph",           "Yeast",           "Probable"),
        list("Cryptococcus",     "Saprotroph-Pathotroph", "Undefined Saprotroph-Animal Pathogen", "Yeast", "Probable"),
        list("Trichosporon",     "Saprotroph-Pathotroph", "Undefined Saprotroph-Animal Pathogen", "Yeast", "Probable"),
        list("Malassezia",       "Saprotroph-Pathotroph", "Undefined Saprotroph-Animal Pathogen", "Yeast", "Probable"),
        list("Wallemia",         "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),

        # --- Pathotrophs ---
        list("Fusarium",         "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Botrytis",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Verticillium",     "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Colletotrichum",   "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Magnaporthe",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Phytophthora",     "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Pythium",          "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Rhizoctonia",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Sclerotinia",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Phoma",            "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Didymella",        "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Neonectria",       "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Diaporthe",        "Pathotroph-Saprotroph", "Plant Pathogen-Wood Saprotroph", "Microfungus", "Probable"),
        list("Gibberella",       "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Cylindrocarpon",   "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Ilyonectria",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Armillaria",       "Pathotroph-Saprotroph", "Plant Pathogen-Wood Saprotroph", "Agaricomycetes", "Probable"),
        list("Heterobasidion",   "Pathotroph",  "Plant Pathogen",                  "Agaricomycetes",  "Highly Probable"),
        list("Ustilago",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Tilletia",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Puccinia",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Melampsora",       "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Erysiphe",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Blumeria",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Cercospora",       "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Septoria",         "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Bipolaris",        "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Curvularia",       "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Exserohilum",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Calonectria",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),

        # Animal pathogens
        list("Candida",          "Pathotroph-Saprotroph", "Animal Pathogen-Undefined Saprotroph", "Yeast", "Probable"),
        list("Aspergillus",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Microsporum",      "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Trichophyton",     "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Epidermophyton",   "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Histoplasma",      "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Coccidioides",     "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Blastomyces",      "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),
        list("Sporothrix",       "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Probable"),
        list("Pneumocystis",     "Pathotroph",  "Animal Pathogen",                 "Microfungus",     "Highly Probable"),

        # Mycoparasites / fungicolous
        list("Trichoderma",      "Saprotroph",  "Soil Saprotroph",                "Microfungus",     "Probable"),
        list("Clonostachys",     "Saprotroph-Pathotroph", "Mycoparasite-Soil Saprotroph", "Microfungus", "Probable"),
        list("Hypomyces",        "Pathotroph",  "Mycoparasite",                    "Microfungus",     "Probable"),

        # Insect pathogens (Entomopathogen)
        list("Beauveria",        "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Highly Probable"),
        list("Metarhizium",      "Pathotroph-Saprotroph", "Animal Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Cordyceps",        "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Highly Probable"),
        list("Isaria",           "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Probable"),
        list("Ophiocordyceps",   "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Highly Probable"),

        # --- Symbiotrophs ---
        # Ectomycorrhizal (ECM)
        list("Amanita",          "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Boletus",          "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Suillus",          "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Russula",          "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Lactarius",        "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Cortinarius",      "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Inocybe",          "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Hebeloma",         "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Laccaria",         "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Pisolithus",       "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Scleroderma",      "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Tomentella",       "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Thelephora",       "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Rhizopogon",       "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Cenococcum",       "Symbiotroph", "Ectomycorrhizal",                 "Microfungus",     "Highly Probable"),
        list("Tuber",            "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Elaphomyces",      "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Probable"),
        list("Tricholoma",       "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Cantharellus",     "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Craterellus",      "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Hydnum",           "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Xerocomus",        "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Leccinum",         "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Tylospora",        "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Probable"),
        list("Amphinema",        "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Probable"),
        list("Piloderma",        "Symbiotroph", "Ectomycorrhizal",                 "Agaricomycetes",  "Highly Probable"),
        list("Wilcoxina",        "Symbiotroph", "Ectomycorrhizal",                 "Microfungus",     "Probable"),

        # Arbuscular Mycorrhizal (AM / Glomeromycota)
        list("Glomus",           "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Rhizophagus",      "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Funneliformis",    "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Claroideoglomus",  "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Diversispora",     "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Acaulospora",      "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Gigaspora",        "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Scutellospora",    "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Paraglomus",       "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Highly Probable"),
        list("Ambispora",        "Symbiotroph", "Arbuscular Mycorrhizal",          "Microfungus",     "Probable"),

        # Ericoid mycorrhizal
        list("Oidiodendron",     "Symbiotroph", "Ericoid Mycorrhizal",             "Microfungus",     "Probable"),
        list("Hymenoscyphus",    "Symbiotroph-Saprotroph", "Ericoid Mycorrhizal-Litter Saprotroph", "Microfungus", "Probable"),
        list("Rhizoscyphus",     "Symbiotroph", "Ericoid Mycorrhizal",             "Microfungus",     "Probable"),

        # Orchid mycorrhizal
        list("Tulasnella",       "Symbiotroph", "Orchid Mycorrhizal",              "Microfungus",     "Highly Probable"),
        list("Ceratobasidium",   "Symbiotroph-Pathotroph", "Orchid Mycorrhizal-Plant Pathogen", "Microfungus", "Probable"),
        list("Sebacina",         "Symbiotroph", "Orchid Mycorrhizal",              "Microfungus",     "Probable"),

        # Lichen
        list("Cladonia",         "Symbiotroph", "Lichenized",                      "Microfungus",     "Highly Probable"),
        list("Peltigera",        "Symbiotroph", "Lichenized",                      "Microfungus",     "Highly Probable"),
        list("Usnea",            "Symbiotroph", "Lichenized",                      "Microfungus",     "Highly Probable"),
        list("Lecanora",         "Symbiotroph", "Lichenized",                      "Microfungus",     "Probable"),
        list("Xanthoria",        "Symbiotroph", "Lichenized",                      "Microfungus",     "Probable"),

        # Endophytes
        list("Epichloe",         "Symbiotroph", "Endophyte",                       "Microfungus",     "Highly Probable"),
        list("Neotyphodium",     "Symbiotroph", "Endophyte",                       "Microfungus",     "Probable"),
        list("Piriformospora",   "Symbiotroph", "Endophyte",                       "Microfungus",     "Probable"),
        list("Serendipita",      "Symbiotroph", "Endophyte",                       "Microfungus",     "Probable"),
        list("Phialocephala",    "Symbiotroph-Saprotroph", "Dark Septate Endophyte-Soil Saprotroph", "Microfungus", "Probable"),
        list("Cadophora",        "Symbiotroph-Saprotroph", "Dark Septate Endophyte-Soil Saprotroph", "Microfungus", "Probable"),

        # --- Mixed / multi-modal genera ---
        list("Coniochaeta",      "Saprotroph",  "Wood Saprotroph",                "Microfungus",     "Probable"),
        list("Arthrinium",       "Saprotroph-Pathotroph", "Plant Saprotroph-Plant Pathogen", "Microfungus", "Probable"),
        list("Nigrospora",       "Saprotroph-Pathotroph", "Plant Saprotroph-Plant Pathogen", "Microfungus", "Probable"),
        list("Exophiala",        "Saprotroph-Pathotroph", "Undefined Saprotroph-Animal Pathogen", "Microfungus", "Probable"),
        list("Cyphellophora",    "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Possible"),
        list("Dothideomycetes",  "Saprotroph-Pathotroph", "Undefined Saprotroph-Plant Pathogen", "Microfungus", "Possible"),
        list("Sordariomycetes",  "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Possible"),
        list("Eurotiomycetes",   "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Possible"),
        list("Leotiomycetes",    "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Possible"),
        list("Agaricomycetes",   "Saprotroph-Symbiotroph", "Undefined Saprotroph-Ectomycorrhizal", "Agaricomycetes", "Possible"),

        # --- Additional common genera ---
        list("Phaeosphaeria",    "Pathotroph-Saprotroph", "Plant Pathogen-Litter Saprotroph", "Microfungus", "Probable"),
        list("Pleosporales",     "Saprotroph-Pathotroph", "Undefined Saprotroph-Plant Pathogen", "Microfungus", "Possible"),
        list("Nectria",          "Pathotroph-Saprotroph", "Plant Pathogen-Wood Saprotroph", "Microfungus", "Probable"),
        list("Acremonium",       "Saprotroph",  "Undefined Saprotroph",           "Microfungus",     "Probable"),
        list("Simplicillium",    "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Probable"),
        list("Lecanicillium",    "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Probable"),
        list("Purpureocillium",  "Pathotroph",  "Animal Pathogen-Insect Pathogen", "Microfungus",     "Probable"),
        list("Pochonia",         "Pathotroph",  "Animal Pathogen-Nematophagous",   "Microfungus",     "Probable"),
        list("Dactylellina",     "Pathotroph",  "Animal Pathogen-Nematophagous",   "Microfungus",     "Probable"),
        list("Arthrobotrys",     "Pathotroph",  "Animal Pathogen-Nematophagous",   "Microfungus",     "Probable"),
        list("Orbilia",          "Pathotroph-Saprotroph", "Animal Pathogen-Undefined Saprotroph", "Microfungus", "Probable"),
        list("Plectosphaerella", "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Gibellulopsis",    "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Myrothecium",      "Pathotroph-Saprotroph", "Plant Pathogen-Soil Saprotroph", "Microfungus", "Probable"),
        list("Setophoma",        "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Leptosphaeria",    "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Pyrenophora",      "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Cochliobolus",     "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Gaeumannomyces",   "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Highly Probable"),
        list("Monographella",    "Pathotroph",  "Plant Pathogen",                  "Microfungus",     "Probable"),
        list("Microdochium",     "Pathotroph-Saprotroph", "Plant Pathogen-Litter Saprotroph", "Microfungus", "Probable")
      )

      # Build data.frame — de-duplicate by keeping first occurrence of each genus
      df <- data.frame(
        Genus            = vapply(entries, `[[`, character(1), 1),
        Trophic_Mode     = vapply(entries, `[[`, character(1), 2),
        Guild            = vapply(entries, `[[`, character(1), 3),
        Growth_Morphology = vapply(entries, `[[`, character(1), 4),
        Confidence_Rank  = vapply(entries, `[[`, character(1), 5),
        stringsAsFactors = FALSE
      )
      df <- df[!duplicated(df$Genus), ]
      rownames(df) <- df$Genus
      df
    }

    # Confidence hierarchy for filtering
    .confidence_rank <- c("Possible" = 1, "Probable" = 2, "Highly Probable" = 3)

    # Helper: generate enough distinct colors
    .get_colors <- function(n, pal_name = "Set2") {
      max_pal <- tryCatch(
        RColorBrewer::brewer.pal(
          RColorBrewer::brewer.pal.info[pal_name, "maxcolors"], pal_name),
        error = function(e) RColorBrewer::brewer.pal(8, "Set2")
      )
      if (n <= length(max_pal)) return(max_pal[seq_len(n)])
      colorRampPalette(max_pal)(n)
    }

    # ------------------------------------------------------------------
    # Group variable picker
    # ------------------------------------------------------------------
    output$group_variable_ui <- renderUI({
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(x)) > 1 &&
          length(unique(x)) < length(x))]
      selectInput(ns("group_variable"), "Group by:", choices = group_vars)
    })

    # ------------------------------------------------------------------
    # Clean taxonomy
    # ------------------------------------------------------------------
    physeq_clean <- reactive({
      pseq <- physeq_data()
      req(pseq)
      ncols <- ncol(tax_table(pseq))
      if (ncols >= 7) {
        colnames(tax_table(pseq)) <- c(
          "Kingdom","Phylum","Class","Order","Family","Genus","Species"
        )[seq_len(min(7, ncols))]
      } else if (ncols >= 6) {
        colnames(tax_table(pseq)) <- c(
          "Kingdom","Phylum","Class","Order","Family","Genus"
        )[seq_len(ncols)]
      }
      tax_mat <- as(tax_table(pseq), "matrix")
      tax_mat[,] <- gsub("[Dd]_[0-9]__", "", tax_mat[,])
      tax_mat[,] <- gsub("^[dkpcofgs]__", "", tax_mat[,])
      tax_mat[,] <- trimws(tax_mat[,])
      tax_table(pseq) <- tax_table(tax_mat)
      pseq
    })

    # ------------------------------------------------------------------
    # Run FunGuild analysis
    # ------------------------------------------------------------------
    funguild_results <- eventReactive(input$run_funguild, {
      tryCatch({
        pseq <- physeq_clean()
        req(pseq)

        withProgress(message = "Running FunGuild analysis...", value = 0, {

          incProgress(0.1, detail = "Loading FunGuild database")
          guild_db <- .build_funguild_db()
          cat("[FunGuild] Database loaded:", nrow(guild_db), "genera\n")

          incProgress(0.2, detail = "Extracting taxonomy")
          # Get OTU/ASV matrix (taxa x samples)
          otu_mat <- as(otu_table(pseq), "matrix")
          if (!taxa_are_rows(pseq)) otu_mat <- t(otu_mat)

          tax_df <- as.data.frame(tax_table(pseq), stringsAsFactors = FALSE)

          # Determine matching level (default to Genus)
          match_col <- input$tax_level %||% "Genus"
          if (!match_col %in% colnames(tax_df)) {
            match_col <- "Genus"
            if (!"Genus" %in% colnames(tax_df)) {
              # Fallback to 6th column
              match_col <- colnames(tax_df)[min(6, ncol(tax_df))]
            }
          }

          taxa_names_vec <- as.character(tax_df[[match_col]])
          taxa_names_vec[is.na(taxa_names_vec) | !nzchar(taxa_names_vec)] <- "Unidentified"

          incProgress(0.3, detail = "Matching taxa to FunGuild database")

          # Match each taxon
          matched    <- taxa_names_vec %in% guild_db$Genus
          n_matched  <- sum(matched)
          n_total    <- length(taxa_names_vec)
          coverage   <- round(100 * n_matched / n_total, 1)

          cat("[FunGuild] Matched:", n_matched, "of", n_total,
              "taxa (", coverage, "% coverage)\n")

          # Build per-taxon assignment table
          assign_df <- data.frame(
            Taxon           = rownames(tax_df),
            Match_Name      = taxa_names_vec,
            Matched         = matched,
            stringsAsFactors = FALSE
          )

          # Merge guild info
          assign_df$Trophic_Mode      <- NA_character_
          assign_df$Guild             <- NA_character_
          assign_df$Growth_Morphology <- NA_character_
          assign_df$Confidence_Rank   <- NA_character_

          idx_match <- match(assign_df$Match_Name[matched], guild_db$Genus)
          assign_df$Trophic_Mode[matched]      <- guild_db$Trophic_Mode[idx_match]
          assign_df$Guild[matched]             <- guild_db$Guild[idx_match]
          assign_df$Growth_Morphology[matched] <- guild_db$Growth_Morphology[idx_match]
          assign_df$Confidence_Rank[matched]   <- guild_db$Confidence_Rank[idx_match]

          # Apply confidence filter
          min_conf <- input$confidence %||% "Possible"
          min_rank <- .confidence_rank[min_conf] %||% 1
          assign_df$Conf_Num <- .confidence_rank[assign_df$Confidence_Rank]
          assign_df$Pass_Confidence <- !is.na(assign_df$Conf_Num) &
                                        assign_df$Conf_Num >= min_rank

          # Apply trophic filter
          troph_filter <- input$trophic_filter %||% "all"
          if (troph_filter != "all") {
            assign_df$Pass_Trophic <- grepl(troph_filter,
                                            assign_df$Trophic_Mode,
                                            ignore.case = TRUE)
          } else {
            assign_df$Pass_Trophic <- TRUE
          }

          assign_df$Pass_All <- assign_df$Matched &
                                assign_df$Pass_Confidence &
                                assign_df$Pass_Trophic

          incProgress(0.5, detail = "Computing guild proportions per sample")

          # Extract primary trophic mode (first listed)
          assign_df$Primary_Trophic <- sapply(
            strsplit(assign_df$Trophic_Mode, "-"),
            function(x) if (length(x) > 0 && !is.na(x[1])) x[1] else NA_character_
          )

          # Compute per-sample trophic mode proportions
          pass_idx   <- which(assign_df$Pass_All)
          trophic_modes <- unique(na.omit(assign_df$Trophic_Mode[pass_idx]))
          guilds_unique <- unique(na.omit(assign_df$Guild[pass_idx]))

          sample_names <- colnames(otu_mat)

          # Trophic mode matrix (samples x trophic modes)
          troph_mat <- matrix(0, nrow = length(sample_names),
                              ncol = length(trophic_modes))
          rownames(troph_mat) <- sample_names
          colnames(troph_mat) <- trophic_modes

          # Guild matrix (samples x guilds)
          guild_mat <- matrix(0, nrow = length(sample_names),
                              ncol = length(guilds_unique))
          rownames(guild_mat) <- sample_names
          colnames(guild_mat) <- guilds_unique

          for (i in pass_idx) {
            abund <- otu_mat[i, ]
            tm    <- assign_df$Trophic_Mode[i]
            gu    <- assign_df$Guild[i]
            if (!is.na(tm) && tm %in% trophic_modes) {
              troph_mat[, tm] <- troph_mat[, tm] + abund
            }
            if (!is.na(gu) && gu %in% guilds_unique) {
              guild_mat[, gu] <- guild_mat[, gu] + abund
            }
          }

          # Normalize to proportions per sample
          troph_totals <- rowSums(troph_mat)
          troph_totals[troph_totals == 0] <- 1
          troph_prop <- troph_mat / troph_totals

          guild_totals <- rowSums(guild_mat)
          guild_totals[guild_totals == 0] <- 1
          guild_prop <- guild_mat / guild_totals

          incProgress(0.7, detail = "Building metadata")

          # Get group variable
          grp_var <- input$group_variable
          metadata <- as(sample_data(pseq), "data.frame")
          groups <- if (!is.null(grp_var) && grp_var %in% names(metadata)) {
            as.character(metadata[[grp_var]])
          } else {
            rep("All", nrow(metadata))
          }

          incProgress(0.9, detail = "Running statistical tests")

          # Statistical tests on trophic mode proportions
          stat_results <- NULL
          stat_test_type <- input$stat_test %||% "kruskal"
          pval_cut <- as.numeric(input$pval_cutoff %||% 0.05)

          if (stat_test_type != "none" && length(unique(groups)) >= 2) {
            stat_list <- list()
            for (mode_name in colnames(troph_prop)) {
              vals <- troph_prop[, mode_name]
              if (stat_test_type == "kruskal") {
                test_res <- tryCatch({
                  kt <- kruskal.test(vals ~ factor(groups))
                  data.frame(
                    Trophic_Mode = mode_name,
                    Test         = "Kruskal-Wallis",
                    Statistic    = round(kt$statistic, 3),
                    P_value      = signif(kt$p.value, 4),
                    Significant  = ifelse(kt$p.value < pval_cut,
                                          "Yes", "No"),
                    stringsAsFactors = FALSE
                  )
                }, error = function(e) NULL)
              } else {
                test_res <- tryCatch({
                  wt <- wilcox.test(vals ~ factor(groups))
                  data.frame(
                    Trophic_Mode = mode_name,
                    Test         = "Wilcoxon",
                    Statistic    = round(wt$statistic, 3),
                    P_value      = signif(wt$p.value, 4),
                    Significant  = ifelse(wt$p.value < pval_cut,
                                          "Yes", "No"),
                    stringsAsFactors = FALSE
                  )
                }, error = function(e) NULL)
              }
              if (!is.null(test_res)) stat_list[[mode_name]] <- test_res
            }
            if (length(stat_list) > 0) {
              stat_results <- do.call(rbind, stat_list)
              rownames(stat_results) <- NULL
              # FDR correction
              stat_results$P_adjusted <- signif(
                p.adjust(stat_results$P_value, method = "BH"), 4)
              stat_results$Significant <- ifelse(
                stat_results$P_adjusted < pval_cut,
                "Yes", "No")
            }
          }

          incProgress(1.0, detail = "Done!")

          list(
            assign_df     = assign_df,
            troph_prop    = troph_prop,
            guild_prop    = guild_prop,
            troph_mat     = troph_mat,
            guild_mat     = guild_mat,
            groups        = groups,
            group_var     = grp_var,
            n_matched     = n_matched,
            n_total       = n_total,
            coverage      = coverage,
            stat_results  = stat_results,
            n_passing     = sum(assign_df$Pass_All),
            db_size       = nrow(guild_db)
          )
        })
      }, error = function(e) {
        showNotification(paste("FunGuild error:", e$message),
                         type = "error", duration = 10)
        cat("[FunGuild] ERROR:", e$message, "\n")
        NULL
      })
    })

    # ------------------------------------------------------------------
    # OUTPUTS
    # ------------------------------------------------------------------

    # --- Summary ---
    output$funguild_summary <- renderPrint({
      res <- funguild_results()
      req(res)

      cat("FunGuild Analysis Summary\n")
      cat("=========================\n\n")
      cat("Database size:       ", res$db_size, "genera\n")
      cat("Total taxa in data:  ", res$n_total, "\n")
      cat("Taxa matched:        ", res$n_matched,
          sprintf("(%.1f%% coverage)\n", res$coverage))
      cat("Taxa passing filters:", res$n_passing, "\n\n")

      cat("Trophic mode breakdown (passing taxa):\n")
      assign_pass <- res$assign_df[res$assign_df$Pass_All, ]
      if (nrow(assign_pass) > 0) {
        tm_tab <- sort(table(assign_pass$Trophic_Mode), decreasing = TRUE)
        for (i in seq_along(tm_tab)) {
          cat(sprintf("  %-35s %d taxa\n", names(tm_tab)[i], tm_tab[i]))
        }
      } else {
        cat("  No taxa passed current filters.\n")
      }

      cat("\nGuild breakdown (top 10):\n")
      if (nrow(assign_pass) > 0) {
        gu_tab <- sort(table(assign_pass$Guild), decreasing = TRUE)
        for (i in seq_len(min(10, length(gu_tab)))) {
          cat(sprintf("  %-40s %d taxa\n", names(gu_tab)[i], gu_tab[i]))
        }
      }

      cat("\nConfidence distribution:\n")
      if (nrow(assign_pass) > 0) {
        conf_tab <- table(assign_pass$Confidence_Rank)
        for (nm in names(conf_tab)) {
          cat(sprintf("  %-20s %d\n", nm, conf_tab[nm]))
        }
      }
    })

    # --- Results Table ---
    output$results_table <- DT::renderDataTable({
      res <- funguild_results()
      req(res)

      show_df <- res$assign_df[res$assign_df$Pass_All, ,drop = FALSE]
      show_df <- show_df[, c("Taxon", "Match_Name", "Trophic_Mode", "Guild",
                             "Growth_Morphology", "Confidence_Rank")]
      colnames(show_df) <- c("ASV/OTU", "Matched Name", "Trophic Mode",
                             "Guild", "Growth Morphology", "Confidence")

      DT::datatable(show_df,
        options = list(
          pageLength = 20,
          scrollX = TRUE,
          dom = "lftipr",
          order = list(list(2, "asc"))
        ),
        rownames = FALSE,
        filter = "top"
      )
    })

    # --- Statistical Tests Table ---
    output$stats_table <- DT::renderDataTable({
      res <- funguild_results()
      req(res, res$stat_results)

      DT::datatable(res$stat_results,
        options = list(pageLength = 20, scrollX = TRUE, dom = "t"),
        rownames = FALSE
      ) |> DT::formatStyle(
        "Significant",
        backgroundColor = DT::styleEqual(c("Yes", "No"),
                                         c("#d4edda", "#f8f9fa"))
      )
    })

    # --- Trophic Mode Plot ---
    output$trophic_plot <- renderPlot({
      res <- funguild_results()
      req(res)

      plot_type <- input$plot_type %||% "stacked_bar"
      font_sz   <- as.numeric(input$font_size %||% 12)
      pal_name  <- input$palette   %||% "Set2"

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes).
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = "Guild",
                                   base_size = font_sz)

      troph_prop <- as.data.frame(res$troph_prop)
      troph_prop$Sample <- rownames(troph_prop)
      troph_prop$Group  <- res$groups

      # Reshape to long
      long_df <- tidyr::pivot_longer(
        troph_prop,
        cols = -c(Sample, Group),
        names_to = "Trophic_Mode",
        values_to = "Proportion"
      )

      n_modes <- length(unique(long_df$Trophic_Mode))
      colors  <- .get_colors(n_modes, pal_name)

      if (plot_type == "stacked_bar") {
        # Order samples by group
        long_df$Sample <- factor(long_df$Sample,
          levels = unique(long_df$Sample[order(long_df$Group)]))

        p <- ggplot(long_df, aes(x = Sample, y = Proportion,
                                 fill = Trophic_Mode)) +
          geom_bar(stat = "identity", width = 0.85) +
          scale_fill_manual(values = colors) +
          styles$theme_fn(base_size = font_sz) +
          styles$grid_theme +
          theme(axis.text.x = element_text(angle = 45, hjust = 1, size = font_sz - 2),
                legend.position = "bottom",
                legend.text = element_text(size = font_sz - 1),
                plot.title = element_text(face = "bold", size = font_sz + 2)) +
          labs(title = if (is.null(styles$title)) "Trophic Mode Composition per Sample" else styles$title,
               x = NULL, y = "Relative Proportion",
               fill = if (is.null(styles$legend_title)) "Trophic Mode" else styles$legend_title)

        if (length(unique(long_df$Group)) > 1) {
          p <- p + facet_grid(~ Group, scales = "free_x", space = "free_x")
        }
        p

      } else if (plot_type == "grouped_bar") {
        # Aggregate by group
        grp_df <- long_df %>%
          dplyr::group_by(Group, Trophic_Mode) %>%
          dplyr::summarise(Mean = mean(Proportion),
                           SE = sd(Proportion) / sqrt(dplyr::n()),
                           .groups = "drop")

        ggplot(grp_df, aes(x = Trophic_Mode, y = Mean, fill = Group)) +
          geom_bar(stat = "identity", position = position_dodge(0.8),
                   width = 0.7) +
          geom_errorbar(aes(ymin = pmax(Mean - SE, 0), ymax = Mean + SE),
                        position = position_dodge(0.8), width = 0.25) +
          scale_fill_manual(values = colors) +
          labs(title = "Mean Trophic Mode Proportions by Group",
               x = NULL, y = "Mean Proportion", fill = "Group") +
          theme_minimal(base_size = font_sz) +
          theme(axis.text.x = element_text(angle = 30, hjust = 1,
                                           size = font_sz - 1),
                plot.title = element_text(face = "bold", size = font_sz + 2))

      } else if (plot_type == "boxplot") {
        p <- ggplot(long_df, aes(x = Trophic_Mode, y = Proportion,
                                 fill = Group)) +
          geom_boxplot(outlier.shape = NA, alpha = 0.8) +
          scale_fill_manual(values = colors) +
          labs(title = "Trophic Mode Distribution by Group",
               x = NULL, y = "Proportion", fill = "Group") +
          theme_minimal(base_size = font_sz) +
          theme(axis.text.x = element_text(angle = 30, hjust = 1),
                plot.title = element_text(face = "bold", size = font_sz + 2))

        if (isTRUE(input$show_points %||% TRUE)) {
          p <- p + geom_jitter(aes(color = Group), width = 0.15,
                               alpha = 0.5, size = 1.5) +
            scale_color_manual(values = colors)
        }

        # Add p-values if requested
        if (isTRUE(input$show_pvalues %||% TRUE) && !is.null(res$stat_results)) {
          for (i in seq_len(nrow(res$stat_results))) {
            pval  <- res$stat_results$P_adjusted[i]
            label <- if (pval < 0.001) "***"
                     else if (pval < 0.01) "**"
                     else if (pval < 0.05) "*"
                     else "ns"
            max_y <- max(long_df$Proportion[
              long_df$Trophic_Mode == res$stat_results$Trophic_Mode[i]],
              na.rm = TRUE)
            p <- p + annotate("text",
              x = res$stat_results$Trophic_Mode[i],
              y = max_y + 0.05,
              label = label,
              size = font_sz / 3, fontface = "bold")
          }
        }
        p

      } else if (plot_type == "heatmap") {
        # Group-averaged heatmap
        if (isTRUE(input$aggregate_hm)) {
          agg_list <- split(as.data.frame(res$troph_prop), res$groups)
          agg_mat <- do.call(rbind, lapply(agg_list, colMeans))
        } else {
          agg_mat <- res$troph_prop
        }

        if (isTRUE(input$scale_heatmap) && nrow(agg_mat) > 1) {
          agg_mat <- t(scale(t(agg_mat)))
          agg_mat[is.nan(agg_mat)] <- 0
        }

        hm_df <- as.data.frame(as.table(as.matrix(agg_mat)))
        colnames(hm_df) <- c("Sample", "Trophic_Mode", "Value")

        ggplot(hm_df, aes(x = Sample, y = Trophic_Mode, fill = Value)) +
          geom_tile(color = "white", linewidth = 0.5) +
          scale_fill_viridis_c(option = "D") +
          labs(title = "Trophic Mode Heatmap",
               x = NULL, y = NULL, fill = "Score") +
          theme_minimal(base_size = font_sz) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1),
                plot.title = element_text(face = "bold", size = font_sz + 2))
      }
    }, res = 120)

    # --- Guild Composition Plot ---
    output$guild_barplot <- renderPlot({
      res <- funguild_results()
      req(res)

      font_sz  <- as.numeric(input$font_size %||% 12)
      pal_name <- input$palette   %||% "Set2"
      top_n    <- as.numeric(input$top_n %||% 15)

      guild_prop <- as.data.frame(res$guild_prop)

      # Select top N guilds by mean proportion
      guild_means <- colMeans(guild_prop)
      top_guilds  <- names(sort(guild_means, decreasing = TRUE))[
        seq_len(min(top_n, length(guild_means)))]

      # Collapse others
      guild_sub <- guild_prop[, top_guilds, drop = FALSE]
      other_prop <- 1 - rowSums(guild_sub)
      guild_sub$Other <- pmax(other_prop, 0)

      guild_sub$Sample <- rownames(guild_sub)
      guild_sub$Group  <- res$groups

      long_df <- tidyr::pivot_longer(
        guild_sub,
        cols = -c(Sample, Group),
        names_to = "Guild",
        values_to = "Proportion"
      )

      # Order samples by group
      long_df$Sample <- factor(long_df$Sample,
        levels = unique(long_df$Sample[order(long_df$Group)]))

      n_guilds <- length(unique(long_df$Guild))
      colors   <- .get_colors(n_guilds, pal_name)

      p <- ggplot(long_df, aes(x = Sample, y = Proportion, fill = Guild)) +
        geom_bar(stat = "identity", width = 0.85) +
        scale_fill_manual(values = colors) +
        labs(title = paste0("Guild Composition (Top ", top_n, ")"),
             x = NULL, y = "Relative Proportion", fill = "Guild") +
        theme_minimal(base_size = font_sz) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1,
                                         size = font_sz - 2),
              legend.position = "bottom",
              legend.text = element_text(size = max(font_sz - 3, 7)),
              legend.key.size = unit(0.4, "cm"),
              plot.title = element_text(face = "bold", size = font_sz + 2)) +
        guides(fill = guide_legend(ncol = 2))

      if (length(unique(long_df$Group)) > 1) {
        p <- p + facet_grid(~ Group, scales = "free_x", space = "free_x")
      }
      p
    }, res = 120)

    # --- Guild Heatmap ---
    output$guild_heatmap <- renderPlot({
      res <- funguild_results()
      req(res)

      font_sz  <- as.numeric(input$font_size %||% 12)
      top_n    <- as.numeric(input$top_n %||% 15)

      guild_prop <- as.data.frame(res$guild_prop)
      guild_means <- colMeans(guild_prop)
      top_guilds <- names(sort(guild_means, decreasing = TRUE))[
        seq_len(min(top_n, length(guild_means)))]

      hm_mat <- as.matrix(guild_prop[, top_guilds, drop = FALSE])

      if (isTRUE(input$aggregate_hm %||% TRUE)) {
        agg_list <- split(as.data.frame(hm_mat), res$groups)
        hm_mat <- do.call(rbind, lapply(agg_list, colMeans))
      }

      if (isTRUE(input$scale_heatmap %||% TRUE) && nrow(hm_mat) > 1 && ncol(hm_mat) > 1) {
        hm_mat <- t(scale(t(hm_mat)))
        hm_mat[is.nan(hm_mat)] <- 0
      }

      # Optional hierarchical clustering of samples
      if (isTRUE(input$cluster_samples %||% TRUE) && nrow(hm_mat) > 2) {
        d <- dist(hm_mat)
        hc <- hclust(d, method = "ward.D2")
        row_order <- hc$order
        hm_mat <- hm_mat[row_order, , drop = FALSE]
      }

      hm_df <- as.data.frame(as.table(hm_mat))
      colnames(hm_df) <- c("Sample", "Guild", "Value")
      # Preserve clustered sample order
      hm_df$Sample <- factor(hm_df$Sample, levels = unique(hm_df$Sample))

      ggplot(hm_df, aes(x = Sample, y = Guild, fill = Value)) +
        geom_tile(color = "white", linewidth = 0.5) +
        scale_fill_viridis_c(option = "C") +
        labs(title = paste0("Guild Heatmap (Top ", top_n, ")"),
             x = NULL, y = NULL, fill = "Score") +
        theme_minimal(base_size = font_sz) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1,
                                         size = font_sz - 2),
              axis.text.y = element_text(size = font_sz - 1),
              plot.title = element_text(face = "bold", size = font_sz + 2))
    }, res = 120)

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    .current_plot <- reactive({
      res <- funguild_results()
      req(res)
      # Re-render the trophic plot for download
      troph_prop <- as.data.frame(res$troph_prop)
      troph_prop$Sample <- rownames(troph_prop)
      troph_prop$Group  <- res$groups
      long_df <- tidyr::pivot_longer(
        troph_prop, cols = -c(Sample, Group),
        names_to = "Trophic_Mode", values_to = "Proportion")
      long_df$Sample <- factor(long_df$Sample,
        levels = unique(long_df$Sample[order(long_df$Group)]))
      n_modes <- length(unique(long_df$Trophic_Mode))
      colors <- .get_colors(n_modes, input$palette %||% "Set2")
      font_sz <- as.numeric(input$font_size %||% 12)

      p <- ggplot(long_df, aes(x = Sample, y = Proportion,
                               fill = Trophic_Mode)) +
        geom_bar(stat = "identity", width = 0.85) +
        scale_fill_manual(values = colors) +
        labs(title = "FunGuild: Trophic Mode Composition",
             x = NULL, y = "Relative Proportion", fill = "Trophic Mode") +
        theme_minimal(base_size = font_sz) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              legend.position = "bottom",
              plot.title = element_text(face = "bold"))
      if (length(unique(long_df$Group)) > 1) {
        p <- p + facet_grid(~ Group, scales = "free_x", space = "free_x")
      }
      p
    })

    output$download_plot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "FunGuild_Trophic"),
      content = function(file) {
        ggsave(file, plot = .current_plot(), width = 14, height = 8,
               dpi = 300, bg = "white")
      }
    )

    output$download_table <- downloadHandler(
      filename = function() ezmap_filename("FunGuild_Results", "csv"),
      content = function(file) {
        res <- funguild_results()
        req(res)
        out <- res$assign_df[res$assign_df$Pass_All, ]
        out <- out[, c("Taxon", "Match_Name", "Trophic_Mode", "Guild",
                        "Growth_Morphology", "Confidence_Rank")]
        write.csv(out, file, row.names = FALSE)
      }
    )

  })
}
