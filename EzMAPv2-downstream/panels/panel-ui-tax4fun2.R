################################################################################
# panels/panel-ui-tax4fun2.R — Tax4Fun Panel UI (unified 2x2 layout)
#
# Tax4Fun predicts community-level KEGG-pathway functional profiles from 16S
# ASV tables using taxonomy-to-function mapping (via themetagenomics::t4f).
# Only requires an ASV table + taxonomy table — no representative sequences.
# Needs a local SILVA-KO reference (downloaded once via the panel).
################################################################################

library(shinycssloaders)

tax4fun2UI <- function(id, guide = NULL) {
    ns <- NS(id)

    # Easy mode info banner
    easy_banner <- tagList(
        div(style = "background-color: #D1FAE5; border-left: 4px solid #10B981; padding: 12px; margin-bottom: 15px; border-radius: 4px;",
            p(style = "margin: 0; color: #047857; font-size: 13px;",
              strong("Tax4Fun functional prediction with default settings. "),
              "To customize, restart the app and select Expert mode."))
    )

    controls <- tagList(
        # Easy mode banner
        conditionalPanel(condition = "input.analysis_mode == 'easy'", ns = shiny::NS(NULL),
                        easy_banner),

        dataset_selector_ui(ns),
        h5(strong("Reference database")),
        uiOutput(ns("db_status_ui")),
        textInput(ns("db_path"),
                  "Reference folder (leave blank = auto):",
                  value = "",
                  placeholder = "e.g. C:/tax4fun_ref"),
        actionButton(ns("download_db"),
                     "Download SILVA-KO Reference",
                     icon = icon("cloud-download-alt"),
                     class = "btn-outline-primary w-100"),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Downloads the SILVA-KO reference dataset via ",
                 "themetagenomics into the folder above (or into the app's ",
                 "working directory if left blank). You only need to do this ",
                 "once per machine."),
        hr(),

        h5(strong("Analysis settings")),
        uiOutput(ns("group_variable_ui")),

        # Aggregation level (visible in both Easy and Expert modes)
        selectInput(ns("agg_level"), "Functional level:",
                    choices  = c("KEGG KO"      = "ko",
                                 "KEGG Pathway"  = "pathway"),
                    selected = "pathway"),
        helpText(style = "font-size:11px; color:#64748B;",
                 tags$b("KEGG KO"), " (KEGG Orthology) shows individual gene ",
                 "functions (e.g. K00001 — alcohol dehydrogenase). Use this ",
                 "for fine-grained, gene-level functional profiles.",
                 tags$br(),
                 tags$b("KEGG Pathway"), " groups related KOs into biological ",
                 "pathways (e.g. glycolysis, amino acid metabolism). Use this ",
                 "for a broader, process-level overview."),

        # Expert-only: Top functions
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            numericInput(ns("top_n_functions"), "Top functions to display:",
                         value = 50, min = 10, max = 500, step = 10)
        ),

        hr(),

        # Expert-only: Normalization section
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            h5(strong("Normalization")),
            checkboxInput(ns("cn_normalize"),
                          "Copy-number normalize", value = TRUE),
            checkboxInput(ns("sample_normalize"),
                          "Sample normalize", value = TRUE),
            helpText(style = "font-size:11px; color:#64748B;",
                     "Copy-number normalization corrects for differences in 16S ",
                     "rRNA gene copy numbers. Sample normalization scales each ",
                     "sample to relative abundances.")
        ),

        hr(),
        actionButton(ns("run_tax4fun2"), "Run Tax4Fun",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Plot quality (Easy + Expert) ----
        h5(strong("Plot quality")),
        numericInput(ns("font_size"), "Font size:",
                     value = 9, min = 5, max = 18, step = 1),

        # ---- Heatmap styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # heatmap looks (palette, clustering, z-scoring, group annotation)
        # is available to Easy-mode users so they can produce
        # publication-ready figures without leaving Easy. Statistical /
        # analysis controls (top_n_functions, copy-number normalization)
        # remain Expert-only in the Controls column.
        hr(),
        h5(strong("Heatmap styling")),
        selectInput(ns("color_palette"),
                    "Color Palette:",
                    choices  = c("YlGnBu", "RdBu", "YlOrRd",
                                 "Blues", "Greens", "Reds",
                                 "Viridis", "Magma"),
                    selected = "YlGnBu"),
        fluidRow(
            column(6, checkboxInput(ns("cluster_rows"),
                                    "Cluster rows (functions)", TRUE)),
            column(6, checkboxInput(ns("cluster_cols"),
                                    "Cluster columns (samples)", TRUE))
        ),
        fluidRow(
            column(6, checkboxInput(ns("scale_rows"),
                                    "Z-score rows (recommended)", TRUE)),
            column(6, checkboxInput(ns("annotate_groups"),
                                    "Annotate group strip", TRUE))
        ),
        checkboxInput(ns("aggregate_groups"),
                      "Average replicates by group", value = TRUE),

        # ---- Download (always visible) ----
        hr(),
        h5(strong("Download")),
        downloadButton(ns("download_tax4fun2_heatmap"),
                       "Heatmap (PNG)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_tax4fun2_table"),
                       "Function table (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            plotOutput(ns("tax4fun2_heatmap"), height = "650px"),
            type = 6, color = "#3B82F6", size = 0.9,
            caption = "Predicting functions from taxa (Tax4Fun)..."
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Summary",
                h5(strong("Run Summary")),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("tax4fun2_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Top functions",
                h5(strong("Top predicted functions")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("tax4fun2_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "260px"
                )
            )
        )
    )

    tagList(
        h3("Tax4Fun — Functional Prediction"),
        p(style = "color:#64748B;",
          "Predicts KEGG functional profiles from 16S taxonomy using the Tax4Fun ",
          "algorithm (Aßhauer et al. 2015). Only requires ASV table + taxonomy ",
          "— no representative sequences needed."),
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
