################################################################################
# panels/panel-ui-lefse.R — LEfSe (LDA Effect Size) Panel UI
#
# Identifies taxa that are significantly differentially abundant between groups
# using the LEfSe algorithm (Segata et al. 2011):
#   1. Kruskal-Wallis test for multi-group significance
#   2. Pairwise Wilcoxon tests for biological consistency
#   3. LDA (Linear Discriminant Analysis) for effect size ranking
# Produces bar plots and dot plots.
#
# Requires: lefser (Bioconductor)
#   BiocManager::install("lefser")
################################################################################

library(shinycssloaders)

lefseUI <- function(id, guide = NULL) {
    ns <- NS(id)

    # Easy mode info banner
    easy_banner <- conditionalPanel(
        condition = "input.analysis_mode == 'easy'",
        ns = shiny::NS(NULL),
        div(
            style = "background-color:#ECFDF5; border-left:4px solid #10B981; padding:12px; margin-bottom:15px; border-radius:4px;",
            tags$p(
                style = "margin:0; color:#047857; font-size:13px;",
                tags$b("Easy Mode: "),
                "LEfSe with LDA cutoff 2.0 at selected taxonomy level. ",
                "To customize, restart the app and select Expert mode."
            )
        )
    )

    controls <- tagList(
        dataset_selector_ui(ns),
        easy_banner,
        h5(strong("Analysis settings")),
        uiOutput(ns("group_variable_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "LEfSe compares two groups to find taxa that explain ",
                 "differences between them."),
        hr(),

        h5(strong("Comparison")),
        uiOutput(ns("reference_group_ui")),
        uiOutput(ns("comparison_group_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Select the two groups to compare. LEfSe will identify ",
                 "taxa enriched in either group using Kruskal-Wallis, ",
                 "Wilcoxon, and LDA effect size."),
        hr(),

        # Expert-only: Statistical thresholds section
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                h5(strong("Statistical thresholds")),
                numericInput(ns("alpha_kw"), "Kruskal-Wallis \u03B1:",
                             value = 0.05, min = 0.001, max = 0.2, step = 0.01),
                numericInput(ns("alpha_wilcox"), "Wilcoxon \u03B1:",
                             value = 0.05, min = 0.001, max = 0.2, step = 0.01),
                numericInput(ns("lda_cutoff"), "LDA score cutoff:",
                             value = 2.0, min = 0, max = 6, step = 0.5),
                helpText(style = "font-size:11px; color:#64748B;",
                         tags$b("Kruskal-Wallis \u03B1:"), " significance threshold for ",
                         "initial multi-group test.",
                         tags$br(),
                         tags$b("Wilcoxon \u03B1:"), " threshold for pairwise consistency ",
                         "checks between all group pairs.",
                         tags$br(),
                         tags$b("LDA cutoff:"), " minimum effect-size score (log10). ",
                         "Higher = stricter. 2.0 is the standard default."),
                hr()
            )
        ),

        h5(strong("Normalization")),
        selectInput(ns("norm_method"), "Normalization method:",
                    choices = c("CSS (cumulative sum scaling)" = "CSS",
                                "TSS (total sum scaling)"      = "TSS",
                                "CLR (centered log-ratio)"     = "CLR",
                                "CPM (counts per million)"     = "CPM",
                                "None"                         = "none"),
                    selected = "CSS"),
        helpText(style = "font-size:11px; color:#64748B;",
                 tags$b("CSS"), " is recommended for LEfSe (metagenomeSeq-style). ",
                 tags$b("TSS"), " = simple relative abundance. ",
                 tags$b("CLR"), " = compositional-aware log-ratio transform."),
        hr(),
        actionButton(ns("run_lefse"), "Run LEfSe",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Direction"),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
        h5(strong("Plot quality")),
        numericInput(ns("font_size"), "Font size:",
                     value = 11, min = 6, max = 18, step = 1),

        # ---- Bar plot styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (top-N display, palette, orientation) is available
        # to Easy-mode users so they can produce publication-ready
        # figures without leaving Easy. Statistical thresholds (LDA
        # cutoff, p-value cutoff) remain Expert-only in the Controls
        # column.
        hr(),
        h5(strong("Bar plot styling")),
        numericInput(ns("top_n"), "Top features:",
                     value = 30, min = 5, max = 200, step = 5),
        selectInput(ns("bar_palette"), "Color palette:",
                    choices = c("Set1", "Set2", "Dark2", "Paired",
                                "Accent", "Pastel1"),
                    selected = "Set1"),
        checkboxInput(ns("horizontal_bars"), "Horizontal bars", value = TRUE),

        # ---- Download (always visible) ----
        hr(),
        h5(strong("Download")),
        download_dim_ui(ns, def_width = 10, def_height = 8),
        downloadButton(ns("download_lefse_bar"),
                       "Bar plot (PNG)",
                       class = "btn-success w-100 mb-2 mt-2"),
        downloadButton(ns("download_lefse_table"),
                       "Results table (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        tabsetPanel(
            id = ns("lefse_tabs"),
            tabPanel("LDA Bar Plot",
                shinycssloaders::withSpinner(
                    plotOutput(ns("lefse_barplot"), height = "700px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Computing LDA effect sizes..."
                )
            ),
            tabPanel("Dot Plot",
                shinycssloaders::withSpinner(
                    plotOutput(ns("lefse_dotplot"), height = "700px"),
                    type = 6, color = "#3B82F6", size = 0.7
                )
            )
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Summary",
                h5(strong("LEfSe Summary")),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("lefse_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Results Table",
                h5(strong("Significant features")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("lefse_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "260px"
                )
            )
        )
    )

    tagList(
        h3("LEfSe \u2014 LDA Effect Size"),
        p(style = "color:#64748B;",
          "Identifies differentially abundant taxa between groups using the ",
          "LEfSe algorithm (Segata et al. 2011). Combines Kruskal-Wallis and ",
          "Wilcoxon tests with Linear Discriminant Analysis for effect-size ranking."),
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
