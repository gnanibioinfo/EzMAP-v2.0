################################################################################
# panels/panel-ui-bugbase.R — BugBase Phenotype Prediction Panel UI
#
# BugBase predicts organism-level phenotypes (e.g. Gram staining, oxygen
# tolerance, pathogenicity, biofilm formation, mobile element content,
# oxidative stress tolerance) from 16S ASV tables by mapping taxonomy
# to pre-computed phenotype trait tables.
################################################################################

library(shinycssloaders)

bugbaseUI <- function(id, guide = NULL) {
    ns <- NS(id)

    # Easy mode info banner
    easy_banner <- tagList(
        div(style = "background-color: #D1FAE5; border-left: 4px solid #10B981; padding: 12px; margin-bottom: 15px; border-radius: 4px;",
            p(style = "margin: 0; color: #047857; font-size: 13px;",
              strong("BugBase phenotype prediction with default settings. "),
              "To customize, restart the app and select Expert mode."))
    )

    controls <- tagList(
        # Easy mode banner
        conditionalPanel(condition = "input.analysis_mode == 'easy'", ns = shiny::NS(NULL),
                        easy_banner),

        dataset_selector_ui(ns),
        h5(strong("Analysis settings")),
        uiOutput(ns("group_variable_ui")),

        # Expert-only: Phenotypes
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            checkboxGroupInput(
                ns("phenotypes"),
                "Phenotypes to predict:",
                choices = c(
                    "Gram Positive"             = "gram_positive",
                    "Gram Negative"             = "gram_negative",
                    "Aerobic"                   = "aerobic",
                    "Anaerobic"                 = "anaerobic",
                    "Facultatively Anaerobic"   = "facultatively_anaerobic",
                    "Contains Mobile Elements"  = "mobile_elements",
                    "Biofilm Forming"           = "biofilm_forming",
                    "Pathogenic"                = "pathogenic",
                    "Oxidative Stress Tolerant" = "stress_tolerant"
                ),
                selected = c("gram_positive", "gram_negative",
                             "aerobic", "anaerobic",
                             "biofilm_forming", "pathogenic")
            ),
            helpText(style = "font-size:11px; color:#64748B;",
                     "Phenotypes are predicted by mapping ASV taxonomy to ",
                     "organism-level trait databases. Select the traits most ",
                     "relevant to your study.")
        ),

        hr(),
        h5(strong("Threshold")),

        # Expert-only: Min coverage
        conditionalPanel(condition = "input.analysis_mode == 'expert'", ns = shiny::NS(NULL),
            numericInput(ns("min_coverage"), "Min. trait coverage (%):",
                         value = 10, min = 0, max = 100, step = 5),
            helpText(style = "font-size:11px; color:#64748B;",
                     "Minimum percentage of taxa in a sample that must have ",
                     "trait annotations. Samples below this threshold are flagged.")
        ),

        hr(),
        actionButton(ns("run_bugbase"), "Run BugBase",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Phenotype"),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
        h5(strong("Plot quality")),
        fluidRow(
            column(6, numericInput(ns("font_size"), "Font size:",
                                   value = 12, min = 6, max = 20, step = 1)),
            column(6, numericInput(ns("plot_height"), "Plot height (px):",
                                   value = 550, min = 300, max = 1200, step = 50))
        ),
        selectInput(ns("legend_position"), "Legend position:",
                    choices = c("Bottom" = "bottom",
                                "Top"    = "top",
                                "Right"  = "right",
                                "Left"   = "left",
                                "None"   = "none"),
                    selected = "bottom"),

        # ---- Plot styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (plot type, palette, point/p-value display, heatmap
        # clustering/scaling) is available to Easy-mode users so they
        # can produce publication-ready figures without leaving Easy.
        # Statistical / analysis controls (phenotype list, min coverage)
        # remain Expert-only in the Controls column.
        hr(),
        h5(strong("Plot styling")),
        selectInput(ns("plot_type"), "Plot type:",
                    choices = c("Box plot"  = "boxplot",
                                "Bar plot"  = "barplot",
                                "Heatmap"   = "heatmap"),
                    selected = "boxplot"),
        selectInput(ns("color_palette"), "Color palette:",
                    choices = c("Set2", "Dark2", "Paired",
                                "Set1", "Set3", "Pastel1"),
                    selected = "Set2"),
        conditionalPanel(
            condition = sprintf("input['%s'] == 'boxplot'", ns("plot_type")),
            checkboxInput(ns("show_points"), "Show data points", value = TRUE),
            checkboxInput(ns("show_pvalues"), "Show p-values", value = TRUE)
        ),
        conditionalPanel(
            condition = sprintf("input['%s'] == 'heatmap'", ns("plot_type")),
            checkboxInput(ns("scale_heatmap"), "Z-score scale rows", value = TRUE),
            checkboxInput(ns("cluster_samples"), "Cluster samples", value = TRUE),
            checkboxInput(ns("aggregate_groups_hm"),
                          "Average replicates by group", value = TRUE)
        ),

        # ---- Download (always visible) ----
        hr(),
        h5(strong("Download")),
        downloadButton(ns("download_bugbase_plot"),
                       "Plot (PNG)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_bugbase_table"),
                       "Phenotype table (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        tabsetPanel(
            id = ns("bugbase_tabs"),
            tabPanel("Phenotype Plot",
                shinycssloaders::withSpinner(
                    plotOutput(ns("bugbase_plot"), height = "650px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Predicting phenotypes from taxonomy..."
                )
            ),
            tabPanel("Phenotype Proportions",
                h5("Relative phenotype contributions per sample"),
                shinycssloaders::withSpinner(
                    plotOutput(ns("bugbase_stacked"), height = "550px"),
                    type = 6, color = "#3B82F6", size = 0.7
                )
            )
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Summary",
                h5(strong("Run Summary")),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("bugbase_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Phenotype Table",
                h5(strong("Predicted phenotype scores")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("bugbase_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "260px"
                )
            )
        )
    )

    tagList(
        h3("BugBase — Phenotype Prediction"),
        p(style = "color:#64748B;",
          "Predicts organism-level microbiome phenotypes (Gram staining, oxygen ",
          "tolerance, pathogenicity, biofilm formation, etc.) from 16S taxonomy. ",
          "Based on the BugBase algorithm (Ward et al. 2017)."),
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
