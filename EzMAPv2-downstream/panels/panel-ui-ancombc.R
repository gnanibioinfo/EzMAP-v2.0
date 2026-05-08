################################################################################
# panels/panel-ui-ancombc.R -- ANCOM-BC Panel UI
#
# Analysis of Compositions of Microbiomes with Bias Correction (ANCOM-BC)
# (Mandal et al. 2015 / Lin & Peddada 2020)
#
# Compositional-aware differential abundance testing that explicitly models
# the sampling fraction to correct for bias inherent in sequencing data.
# Provides proper statistical inference (p-values, confidence intervals).
#
# Native implementation -- no external packages needed beyond base R.
################################################################################

library(shinycssloaders)

ancombcUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        dataset_selector_ui(ns),

        # Easy mode info banner
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            div(
                style = "background-color:#DCFCE7;border-left:4px solid #22C55E;padding:12px;margin-bottom:16px;border-radius:4px;",
                p(style = "margin:0;color:#166534;font-size:13px;",
                  icon("info-circle"),
                  strong(" Easy Mode: "),
                  "ANCOM-BC with FDR correction (alpha = 0.05). The |log2FC| ",
                  "effect-size cutoff is adjustable below (default 1 = ",
                  "2-fold change). For full control of the statistical ",
                  "threshold, restart the app and select Expert mode.")
            )
        ),

        h5(strong("Analysis settings")),
        # Taxonomy aggregation level -- visible in BOTH modes so users
        # can run ANCOM-BC at the same level as Random Forest / DESeq2
        # for a consistent consensus (the ANCOM-BC+RF overlap panel
        # joins by feature ID, so both methods must agree on the level).
        selectInput(ns("tax_rank"), "Taxonomy Level:",
                    choices = c("ASV (no aggregation)" = "ASV",
                                "Genus"   = "Genus",
                                "Family"  = "Family",
                                "Order"   = "Order",
                                "Class"   = "Class",
                                "Phylum"  = "Phylum"),
                    selected = "ASV"),
        helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                 "Set the same level here as in the Random Forest and ",
                 "DESeq2 tabs if you plan to use the ANCOM-BC+RF overlap ",
                 "panel."),
        uiOutput(ns("group_variable_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "ANCOM-BC tests which taxa differ in abundance between two ",
                 "selected groups while correcting for compositional bias."),
        hr(),

        h5(strong("Comparison")),
        uiOutput(ns("reference_group_ui")),
        uiOutput(ns("comparison_group_ui")),
        # Per-group ASV count card (samples + non-zero ASVs per level
        # of the chosen grouping variable; ref + comparison highlighted)
        uiOutput(ns("group_asv_counts_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Select the two groups to compare. ANCOM-BC reports log2 ",
                 "fold changes of the comparison group relative to the ",
                 "reference group."),
        hr(),

        # ---- Effect-size cutoff (visible in BOTH modes) ----
        # Log2 fold-change is a *biological-relevance* threshold (how
        # large an effect counts as meaningful), so the user can tune
        # it without leaving Easy mode. The FDR significance level (alpha)
        # stays Expert-only -- its 0.05 default is a well-established
        # convention.
        h5(strong("Effect-size cutoff")),
        numericInput(ns("log2fc_cutoff"),
                     "|Log2 Fold Change| cutoff:",
                     value = 1.0, min = 0, max = 6, step = 0.5),
        helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                 "Minimum absolute log2 fold change for a taxon to be ",
                 "considered biologically meaningful. ",
                 tags$b("1.0"), " (default) = 2-fold change, ",
                 tags$b("2.0"), " = 4-fold change. Lower = more lenient ",
                 "(more hits, including small effects)."),
        hr(),

        # ---- Statistical threshold (Expert only) ----
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                h5(strong("Statistical threshold")),
                numericInput(ns("alpha"), "Significance level (alpha):",
                             value = 0.05, min = 0.001, max = 0.2, step = 0.01),
                helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                         tags$b("alpha:"), " FDR-adjusted significance threshold. ",
                         "0.05 (default) is the standard."),
                hr()
            )
        ),

        # Expert-only: Structural zero detection
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                h5(strong("Structural Zero Detection")),
                checkboxInput(ns("detect_zeros"), "Detect structural zeros", FALSE),
                helpText(style = "font-size:11px; color:#64748B;",
                         "Identify and handle potential structural zeros in the data."),
                hr()
            )
        ),

        helpText(style = "font-size:11px; color:#64748B;",
                 "ANCOM-BC tests each ASV individually (no taxonomic aggregation). ",
                 "Normalization and bias correction are handled internally."),
        hr(),

        actionButton(ns("run_ancombc"), "Run ANCOM-BC",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Direction"),
        hr(),

        # ---- Plot quality + styling (visible in BOTH modes) ----
        # All plot styling is exposed to Easy-mode users so they can
        # produce publication-ready figures without leaving Easy.
        # Statistical controls (alpha, log2FC cutoff, structural-zero
        # detection) remain Expert-only in the Controls column.
        h5(strong("Volcano plot styling")),
        fluidRow(
            column(6, numericInput(ns("font_size"), "Base font size:",
                                   value = 12, min = 8, max = 18, step = 1)),
            column(6, numericInput(ns("point_size"), "Point size:",
                                   value = 3, min = 0.5, max = 6, step = 0.5))
        ),
        textInput(ns("plot_title"), "Plot Title:",
                  value = "ANCOM-BC Differential Abundance"),
        fluidRow(
            column(6, numericInput(ns("label_top_n"), "Labels: top N by p:",
                                   value = 15, min = 0, max = 100, step = 1)),
            column(6, numericInput(ns("label_size"), "Label font size:",
                                   value = 3.2, min = 1, max = 10, step = 0.2))
        ),
        checkboxInput(ns("show_labels"), "Label significant taxa", TRUE),

        # ---- Download (always visible) ----
        hr(),
        h5(strong("Download")),
        download_dim_ui(ns, def_width = 10, def_height = 8),
        downloadButton(ns("download_volcano"),
                       "Volcano plot (PNG)",
                       class = "btn-success w-100 mb-2 mt-2"),
        downloadButton(ns("download_table"),
                       "Results table (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            plotOutput(ns("volcano_plot"), height = "700px"),
            type = 6, color = "#3B82F6", size = 0.9,
            caption = "Running ANCOM-BC analysis..."
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Summary",
                h5(strong("ANCOM-BC Summary")),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("ancombc_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Results Table",
                h5(strong("Differentially abundant taxa")),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("results_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "260px"
                )
            )
        )
    )

    tagList(
        h3("ANCOM-BC -- Compositional Differential Abundance"),
        p(style = "color:#64748B;",
          "Tests for differentially abundant taxa using ANCOM-BC (Lin & Peddada 2020). ",
          "Unlike standard methods, ANCOM-BC explicitly models the unknown sampling ",
          "fraction to provide unbiased estimates and valid statistical inference for ",
          "compositional microbiome data."),
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
