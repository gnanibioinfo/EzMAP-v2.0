################################################################################
# panels/panel-ui-funguild.R — FunGuild Panel UI
#
# FunGuild assigns ecological guild annotations (e.g. saprotroph, pathotroph,
# symbiotroph) to fungal taxa based on taxonomy-to-guild mapping.
# Reference: Nguyen et al. (2016) FUNGuild: An open annotation tool for
# parsing fungal community datasets by ecological guild.
#
# Works with ITS amplicon data processed through QIIME2 / EzMAP v2.0.
################################################################################

library(shinycssloaders)

funguildUI <- function(id, guide = NULL) {
    ns <- NS(id)

    # Easy mode info banner
    easy_banner <- tagList(
        div(style = "background-color: #D1FAE5; border-left: 4px solid #10B981; padding: 12px; margin-bottom: 15px; border-radius: 4px;",
            p(style = "margin: 0; color: #047857; font-size: 13px;",
              strong("FunGuild with default matching at Genus level. "),
              "To customize, restart the app and select Expert mode."))
    )

    controls <- tagList(
        # Easy mode banner
        conditionalPanel(condition = "input.analysis_mode == 'easy'", ns = shiny::NS(NULL),
                        easy_banner),

        dataset_selector_ui(ns),

        h5(strong("Analysis settings")),
        uiOutput(ns("group_variable_ui")),

        # Expert-only: Taxonomy level
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            selectInput(ns("tax_level"), "Taxonomy level for matching:",
                        choices = c("Genus"   = "Genus",
                                    "Species" = "Species",
                                    "Family"  = "Family"),
                        selected = "Genus"),
            helpText(style = "font-size:11px; color:#64748B;",
                     "FunGuild matches your taxa against a curated database to ",
                     "assign trophic modes and ecological guilds. Genus-level ",
                     "matching is recommended for best coverage.")
        ),

        hr(),

        h5(strong("Guild filtering")),

        # Expert-only: Trophic modes
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            selectInput(ns("trophic_filter"), "Trophic mode filter:",
                        choices = c("All trophic modes" = "all",
                                    "Saprotroph"   = "Saprotroph",
                                    "Pathotroph"   = "Pathotroph",
                                    "Symbiotroph"  = "Symbiotroph"),
                        selected = "all")
        ),

        # Expert-only: Confidence filter
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            selectInput(ns("confidence"), "Minimum confidence rank:",
                        choices = c("Possible"       = "Possible",
                                    "Probable"       = "Probable",
                                    "Highly Probable" = "Highly Probable"),
                        selected = "Possible"),
            helpText(style = "font-size:11px; color:#64748B;",
                     tags$b("Possible:"), " taxonomy matched at higher rank. ",
                     tags$b("Probable:"), " genus-level match. ",
                     tags$b("Highly Probable:"), " species-level match.")
        ),

        hr(),

        h5(strong("Statistical test")),
        selectInput(ns("stat_test"), "Group comparison test:",
                    choices = c("Kruskal-Wallis"  = "kruskal",
                                "Wilcoxon (2 groups)" = "wilcoxon",
                                "None"            = "none"),
                    selected = "kruskal"),
        numericInput(ns("pval_cutoff"), "P-value threshold:",
                     value = 0.05, min = 0.001, max = 0.1, step = 0.01),
        hr(),

        actionButton(ns("run_funguild"), "Run FunGuild",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Guild"),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
        h5(strong("Plot quality")),
        numericInput(ns("font_size"), "Font size:",
                     value = 12, min = 8, max = 20, step = 1),

        # ---- Plot styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (plot type, palette, top-N, point/p-value display,
        # heatmap clustering/scaling) is available to Easy-mode users
        # so they can produce publication-ready figures without leaving
        # Easy. Statistical / matching controls (taxonomy level, trophic
        # filter, confidence rank) remain Expert-only in the Controls
        # column.
        hr(),
        h5(strong("Plot styling")),
        selectInput(ns("plot_type"), "Plot type:",
                    choices = c("Stacked bar" = "stacked_bar",
                                "Grouped bar" = "grouped_bar",
                                "Box plot"    = "boxplot",
                                "Heatmap"     = "heatmap"),
                    selected = "stacked_bar"),
        selectInput(ns("palette"), "Color palette:",
                    choices = c("Set2", "Set3", "Dark2", "Set1",
                                "Paired", "Accent", "Pastel1"),
                    selected = "Set2"),
        numericInput(ns("top_n"), "Top guilds shown:",
                     value = 15, min = 3, max = 50, step = 1),
        conditionalPanel(
            condition = sprintf("input['%s'] == 'boxplot'", ns("plot_type")),
            checkboxInput(ns("show_points"), "Show data points", value = TRUE),
            checkboxInput(ns("show_pvalues"), "Show p-values", value = TRUE)
        ),
        conditionalPanel(
            condition = sprintf("input['%s'] == 'heatmap'", ns("plot_type")),
            checkboxInput(ns("scale_heatmap"), "Z-score scale rows", value = TRUE),
            checkboxInput(ns("cluster_samples"), "Cluster samples", value = TRUE),
            checkboxInput(ns("aggregate_hm"), "Average by group", value = TRUE)
        ),

        # ---- Download (always visible) ----
        hr(),
        h5(strong("Download")),
        downloadButton(ns("download_plot"),
                       "Plot (PNG)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_table"),
                       "Results table (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        tabsetPanel(
            id = ns("funguild_plot_tabs"),
            tabPanel("Trophic Mode",
                shinycssloaders::withSpinner(
                    plotOutput(ns("trophic_plot"), height = "650px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Generating trophic mode plot..."
                )
            ),
            tabPanel("Guild Composition",
                shinycssloaders::withSpinner(
                    plotOutput(ns("guild_barplot"), height = "650px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Generating guild composition..."
                )
            ),
            tabPanel("Guild Heatmap",
                shinycssloaders::withSpinner(
                    plotOutput(ns("guild_heatmap"), height = "650px"),
                    type = 6, color = "#3B82F6", size = 0.7
                )
            )
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Summary",
                h5(strong("FunGuild Run Summary")),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("funguild_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Results Table",
                h5(strong("Guild assignments per taxon")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("results_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "260px"
                )
            ),
            tabPanel("Statistical Tests",
                h5(strong("Group comparisons (trophic mode proportions)")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("stats_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "200px"
                )
            )
        )
    )

    tagList(
        h3("FunGuild — Fungal Ecological Guild Assignment"),
        p(style = "color:#64748B;",
          "Assigns ecological guild annotations (saprotroph, pathotroph, ",
          "symbiotroph) to fungal taxa using the FunGuild database ",
          "(Nguyen et al. 2016). Designed for ITS amplicon sequencing data."),
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
