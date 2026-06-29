################################################################################
# panels/panel-ui-ancombcrf.R — ANCOM-BC + RF Combined Panel UI
#
# Mirrors the DESeq2+RF panel but intersects ANCOM-BC results with RF.
# Addresses Reviewer 1's recommendation: overlap between RF-selected features
# and ANCOM-BC differential abundance for higher-confidence biomarker selection.
################################################################################

library(shinycssloaders)

ancombcrfUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        dataset_selector_ui(ns),

        # Easy mode info banner
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            tags$div(
                style = "background-color:#E8F5E9;border:1px solid #4CAF50;padding:12px;border-radius:6px;margin-bottom:12px;",
                tags$p(
                    style = "margin:0;color:#2E7D32;font-size:13px;",
                    icon("info-circle", style = "color:#4CAF50;margin-right:6px;"),
                    strong("Easy Mode: "),
                    "Using default ANCOM-BC and Random Forest cutoffs. To customize, restart the app and select Expert mode."
                )
            )
        ),

        # ----- Conditions to compare (mirrors the ANCOM-BC tab) -----
        h5(strong("Conditions to compare")),
        uiOutput(ns("group_variable_ui")),
        uiOutput(ns("reference_group_ui")),
        uiOutput(ns("comparison_group_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Pick the same two groups you used in the ANCOM-BC and ",
                 "Random Forest tabs (e.g. ", tags$i("control vs diseased"),
                 ", ", tags$i("control vs salt"), "). The intersection is ",
                 "computed only if the upstream runs match this comparison."),
        # Live status pulled from upstream ANCOM-BC / RF runs
        uiOutput(ns("upstream_status_ui")),
        hr(),

        h5(strong("Intersection Settings")),
        # Advanced parameters (Expert only)
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                numericInput(ns("padj_cutoff"),   "ANCOM-BC adjusted p-value cutoff:",
                             value = 0.05, min = 0, max = 1, step = 0.01),
                numericInput(ns("log2fc_cutoff"), "ANCOM-BC |log2 fold change| cutoff:",
                             value = 1,    min = 0, step = 0.25),
                numericInput(ns("rf_top_n"),      "Random Forest: top-N by Gini:",
                             value = 30,   min = 5, step = 5)
            )
        ),
        hr(),
        actionButton(ns("run_intersect"), "Compute Intersection",
                     icon = icon("code-branch"),
                     class = "btn-primary w-100"),
        tags$div(
            style = "margin-top:12px; padding:10px; background:#FFF8E1; border-left:4px solid #FFB300; border-radius:4px; font-size:12px; color:#6D4C00;",
            tags$b("Why ANCOM-BC + RF?"),
            tags$p(style = "margin:4px 0 0 0;",
                "ANCOM-BC identifies ", tags$i("statistically"), " differentially abundant taxa ",
                "with compositional bias correction. RF identifies ", tags$i("predictively"),
                " important taxa. Their overlap yields high-confidence biomarkers that are both ",
                "statistically significant AND predictive."
            )
        )
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Significance"),
        hr(),

        # ---- Scatter styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (not the underlying analysis) is available to
        # Easy-mode users so they can produce publication-ready figures
        # without leaving Easy. Statistical thresholds (padj, log2FC,
        # rf_top_n) remain Expert-only in the Controls column.
        h5(strong("Scatter Plot Colors")),
        fluidRow(
            column(6, tags$label("Non-Significant", style = "font-size:11px;"),
                      tags$input(id = ns("col_ns"), type = "color",
                                 value = "#7F8C8D",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Enriched (below Gini cut)", style = "font-size:11px;"),
                      tags$input(id = ns("col_enr"), type = "color",
                                 value = "#8E44AD",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),
        fluidRow(
            column(6, tags$label("Reference-enriched top", style = "font-size:11px;"),
                      tags$input(id = ns("col_ref"), type = "color",
                                 value = "#1f77b4",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Comparison-enriched top", style = "font-size:11px;"),
                      tags$input(id = ns("col_comp"), type = "color",
                                 value = "#E74C3C",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),
        hr(),
        h6(strong("Point & label styling")),
        fluidRow(
            column(6, numericInput(ns("point_size"), "Point size:",
                                   value = 2.4, min = 0.5, max = 10, step = 0.2)),
            column(6, numericInput(ns("label_size"), "Label font size:",
                                   value = 3.1, min = 1, max = 10, step = 0.1))
        ),
        fluidRow(
            column(6, numericInput(ns("label_opacity"),
                                   "Label opacity (0-1):",
                                   value = 1, min = 0.1, max = 1, step = 0.1)),
            column(6, checkboxInput(ns("show_labels"),
                                    "Show point labels",
                                    value = TRUE))
        ),
        hr(),
        h5(strong("Download")),
        download_dim_ui(ns, def_width = 10, def_height = 7),
        downloadButton(ns("download_intersection_csv"),
                       "Intersection Table (CSV)",
                       class = "btn-success w-100 mb-2 mt-2"),
        downloadButton(ns("download_scatter_png"),
                       "Scatter Plot (PNG)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_venn_png"),
                       "Venn Diagram (PNG)",
                       class = "btn-success w-100"),
        hr(),
        helpText(
            "Run ANCOM-BC and Random Forest in their own tabs first. ",
            "This panel only joins existing results — nothing is re-trained."
        )
    )

    plot_area <- tagList(
        tabsetPanel(
            tabPanel("Overview",
                h5(icon("bullseye"), "How many taxa overlap?"),
                uiOutput(ns("summary_boxes")),
                hr(),
                h5(icon("chart-pie"), "Venn-style overlap"),
                shinycssloaders::withSpinner(
                    plotOutput(ns("venn_plot"), height = "340px"),
                    type = 6, color = "#8E44AD", size = 0.8,
                    caption = "Computing overlap..."
                )
            ),
            tabPanel("Scatter: Log2FC vs. Gini",
                h5(icon("chart-area"), "ANCOM-BC effect size vs. RF importance"),
                p("Each dot is one ASV. Colored dots meet both the ANCOM-BC significance cutoff and appear in the top-N of the RF importance ranking."),
                shinycssloaders::withSpinner(
                    plotOutput(ns("scatter_plot"), height = "600px"),
                    type = 6, color = "#8E44AD", size = 0.9,
                    caption = "Joining ANCOM-BC & RF results..."
                )
            )
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Intersection Table",
                h5(icon("table"), "Taxa significant in BOTH analyses"),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("intersection_table")),
                    type = 6, color = "#8E44AD", size = 0.8,
                    proxy.height = "200px"
                )
            ),
            tabPanel("Interpretation",
                h5(icon("brain"), "What the overlap means"),
                uiOutput(ns("interpretation"))
            ),
            tabPanel("Method Comparison",
                h5(icon("balance-scale"), "DESeq2+RF vs ANCOM-BC+RF"),
                uiOutput(ns("method_comparison"))
            )
        )
    )

    tagList(
        h3("Combined ANCOM-BC + Random Forest Feature Selection"),
        p(style = "color:#64748B;",
          "This panel intersects the taxa flagged by ANCOM-BC (compositional differential abundance) ",
          "and Random Forest (classification importance). ",
          "ANCOM-BC accounts for compositionality bias, providing unbiased log fold change estimates."),
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
