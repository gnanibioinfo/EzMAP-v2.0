################################################################################
# panels/panel-ui-filter.R — Filtering Panel UI (unified layout)
#
# Dynamically switches between Bacteria (16S) and Fungi (ITS) filter criteria
# based on the dataset type selected on the Data Upload tab.
#
# Easy mode:   Sensible defaults auto-applied; user just clicks "Apply Filters"
# Expert mode: Full control over every filter parameter
#
# Bacteria filters:  Chloroplast, Mitochondria, Eukaryota, Archaea, D_x__ prefixes
# Fungi filters:     Chromista, Rhizaria, unidentified phyla, k__/p__/c__/o__/f__/g__/s__ prefixes
# Shared filters:    Phylum = NA, abundance thresholds, normalization
# Custom exclusion:  User picks any rank, sees unique taxa, selects which to remove
################################################################################

library(shinycssloaders)

filterUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        # =====================================================================
        # EXPERT ONLY: Sample Subsetting
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            h5(strong(icon("users"), " Sample Subsetting"),
               tags$small(style = "font-weight:400; color:#94A3B8;", " (optional — applied first)")),
            helpText(style = "font-size:11px; color:#64748B; margin-top:-2px;",
                     "Select a metadata column and choose which sample groups to keep. ",
                     "Only selected groups will be used for all downstream analysis."),
            uiOutput(ns("subset_column_ui")),
            uiOutput(ns("subset_groups_ui")),
            uiOutput(ns("subset_preview_ui")),
            hr()
        ),

        # --- Dataset type indicator (always visible) ---
        uiOutput(ns("dataset_type_badge")),
        hr(),

        # =====================================================================
        # EASY MODE: Locked info banner (dynamic per dataset type)
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            uiOutput(ns("easy_mode_banner"))
        ),

        # =====================================================================
        # EXPERT ONLY: Taxonomic Filters
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            h5(strong("Taxonomic filters")),
            uiOutput(ns("taxonomic_filters_ui")),
            hr()
        ),

        # =====================================================================
        # EXPERT ONLY: Custom taxa exclusion
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            h5(strong("Custom taxa exclusion"),
               tags$small(style = "font-weight:400; color:#94A3B8;", " (optional)")),
            helpText(style = "font-size:11px; color:#64748B; margin-top:-2px;",
                     "Browse your data by taxonomic rank and select specific taxa to remove."),
            selectInput(ns("custom_tax_rank"), "Select taxonomy rank:",
                        choices = c("Kingdom", "Phylum", "Class",
                                    "Order", "Family", "Genus"),
                        selected = "Genus"),
            uiOutput(ns("custom_taxa_selector_ui")),
            uiOutput(ns("exclusion_list_display")),
            hr()
        ),

        # =====================================================================
        # EXPERT ONLY: Abundance filters
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            h5(strong("Abundance filters")),
            numericInput(ns("minCounts"),       "Min Reads/Counts (x >):", 3, min = 1),
            sliderInput(ns("minSamplePercent"), "Min % of Samples:",       0, 100, 20, step = 5),
            hr()
        ),

        # =====================================================================
        # EXPERT ONLY: Normalization
        # =====================================================================
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            h5(strong("Normalization")),
            checkboxInput(ns("normalizeAbundance"),
                          "Normalize to Median Sequencing Depth", FALSE),
            hr()
        ),

        # --- Apply button (always visible) ---
        actionButton(ns("applyFilter"), "Apply Filters",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        helpText(style = "font-size:11px; color:#64748B; margin-top:6px;",
                 "Applies all selected filters to your phyloseq object. ",
                 "Filtered data is used by all downstream modules.")
    )

    aesthetics <- NULL

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            verbatimTextOutput(ns("summaryText")),
            type  = 6,
            color = "#3B82F6",
            size  = 0.9,
            proxy.height = "300px",
            caption = "Applying filters..."
        )
    )

    stats_area <- NULL

    tagList(
        h3("Data Filtering"),
        p(style = "color:#64748B;",
          "Remove unwanted taxa, filter low-abundance features, and optionally ",
          "normalize your data before downstream analysis."),
        hr(),
        analysis_tab_layout(
            controls   = controls,
            aesthetics = aesthetics,
            plot_area  = plot_area,
            stats_area = stats_area,
            guide      = guide
        )
    )
}
