################################################################################
# panels/panel-ui-random.R — Random Forest Panel UI (unified 2x2 layout)
################################################################################

library(shinycssloaders)

randomForestUI <- function(id, guide = NULL) {
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
                  "Random Forest with 500 trees, top 20 features by Gini importance. To customize, restart the app and select Expert mode.")
            )
        ),

        h5(strong("Analysis settings")),
        selectInput(ns("tax_rank"), "Taxonomy Level:",
                    choices = c("ASV (no aggregation)" = "ASV",
                                "Genus"   = "Genus",
                                "Family"  = "Family",
                                "Order"   = "Order",
                                "Class"   = "Class",
                                "Phylum"  = "Phylum"),
                    selected = "ASV"),
        helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                 "ASV uses individual sequence variants. Higher ranks aggregate ",
                 "counts (e.g. Genus sums all ASVs in each genus). Higher ranks ",
                 "reduce noise but lose resolution."),
        uiOutput(ns("group_variable_ui")),
        uiOutput(ns("comparison_ui")),
        # Per-group ASV count card — confirms each selected group has
        # enough samples and features for stable RF training, and
        # highlights condition-specific richness across all groups.
        uiOutput(ns("group_asv_counts_ui")),
        hr(),

        # Expert-only: Tree and feature parameters
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                # NOTE: default ntree = 500 here so Easy mode (which
                # hides this input but still sees its default value)
                # matches the Easy-mode banner ("Random Forest with 500
                # trees, top 20 features by Gini importance"). Expert
                # users can raise it to 1000+ for more stable importance
                # at the cost of training time.
                numericInput(ns("ntree"), "Number of Trees (ntree):",
                             value = 500, min = 100, step = 100),
                numericInput(ns("mtry"),  "Features per split (mtry, 0 = auto = √p):",
                             value = 0, min = 0, step = 1),
                helpText(style = "font-size:11px; color:#64748B; margin-top:-8px;",
                         "0 lets randomForest choose the default (√p for classification). ",
                         "Set a positive integer to override — common sweep: around ",
                         "√p / 2, √p, 2√p."),
                numericInput(ns("top_n"), "Number of Top Features to Display:",
                             value = 20, min = 5, step = 5),
                hr()
            )
        ),

        actionButton(ns("run_randomforest"), "Run Random Forest",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        hr(),

        # Expert-only: Validation section
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                h5(strong("Expert-grade validation")),
                helpText(style = "font-size:11px; color:#64748B;",
                         "After training, configure these and click 'Run Expert-grade Validation' ",
                         "to generate a held-out test score, repeated cross-validation, ",
                         "and bootstrap feature-importance stability."),
                numericInput(ns("test_frac"), "Held-out test fraction:",
                             value = 0.25, min = 0.1, max = 0.5, step = 0.05),
                numericInput(ns("cv_folds"), "CV folds (k):",
                             value = 5, min = 2, max = 10, step = 1),
                numericInput(ns("cv_repeats"), "CV repeats:",
                             value = 10, min = 1, max = 50, step = 1),
                numericInput(ns("n_bootstrap"), "Feature-stability bootstraps:",
                             value = 50, min = 10, max = 500, step = 10),
                actionButton(ns("run_validation"), "Run Expert-grade Validation",
                             icon = icon("vial"),
                             class = "btn-warning w-100"),
                hr()
            )
        )
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Importance"),
        hr(),

        # ---- Plot Customization (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (not the underlying analysis) is available to
        # Easy-mode users so they can produce publication-ready figures
        # without leaving Easy. Statistical / validation parameters
        # (ntree, mtry, top_n, CV folds, bootstraps) remain Expert-only
        # in the Controls column.
        h5(strong("Plot Customization")),
        selectInput(ns("ra_palette"), "Relative-Abundance Palette:",
                    choices  = c("Set1", "Set2", "Set3", "Paired", "Dark2", "Accent"),
                    selected = "Set1"),
        # Importance-axis label: separate from the shared "Y-axis Label"
        # because importance bars are coord_flipped, which means the
        # shared y-axis input applies to taxa names instead of the Gini
        # metric. Using a dedicated input so users can write a clean
        # publication label (e.g. "Mean Decrease in Gini Impurity").
        textInput(ns("customXLabel"),
                  "Importance metric label (x-axis after flip):",
                  value = "Mean Decrease Gini"),
        hr(),
        h6(strong("Importance plot: color by enriched group")),
        fluidRow(
            column(6, tags$label("Reference-enriched", style = "font-size:11px;"),
                      tags$input(id = ns("imp_color_ref"), type = "color",
                                 value = "#1f77b4",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Comparison-enriched", style = "font-size:11px;"),
                      tags$input(id = ns("imp_color_comp"), type = "color",
                                 value = "#d62728",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),
        hr(),

        h5(strong("Download")),
        download_dim_ui(ns, def_width = 9, def_height = 7),
        downloadButton(ns("download_rf_plot"),
                       "Importance Plot (PNG)",
                       class = "btn-success w-100 mb-2 mt-2"),
        downloadButton(ns("download_rf_roc_plot"),
                       "ROC Plot (PNG)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_rf_table"),
                       "Feature Importance (CSV)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_ra_plot"),
                       "Rel. Abundance Plot (PNG)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        tabsetPanel(
            tabPanel("Feature Importance",
                h5(icon("chart-bar"), "Top Important Features"),
                shinycssloaders::withSpinner(
                    plotOutput(ns("rf_plot"), height = "500px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Training Random Forest & ranking features..."
                )
            ),
            tabPanel("Performance Metrics",
                h5(icon("line-chart"), "ROC Curve and Model Accuracy"),
                shinycssloaders::withSpinner(
                    plotOutput(ns("rf_roc_plot"), height = "400px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Computing ROC / accuracy metrics..."
                )
            ),
            tabPanel("Relative Abundance",
                h5(icon("chart-bar"), "Relative Abundance of Top Taxa"),
                p("Visualise the abundance of the top discriminatory taxa across the two comparison groups."),
                shinycssloaders::withSpinner(
                    plotOutput(ns("rf_abundance_plot"), height = "500px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Building abundance plot for top features..."
                )
            ),
            # Expert mode only: Validation CV tab
            conditionalPanel(
                condition = "input.analysis_mode == 'expert'",
                ns = shiny::NS(NULL),
                tabPanel("Validation: CV",
                    h5(icon("retweet"), "Repeated k-fold cross-validation"),
                    p(style = "color:#64748B; font-size:12px;",
                      "Each point is one hold-out fold. Boxplots summarise ",
                      "Accuracy, Kappa, and AUC across all folds × repeats."),
                    shinycssloaders::withSpinner(
                        plotOutput(ns("cv_plot"), height = "480px"),
                        type = 6, color = "#3B82F6", size = 0.9,
                        caption = "Running repeated cross-validation..."
                    )
                )
            ),
            # Expert mode only: Feature Stability tab
            conditionalPanel(
                condition = "input.analysis_mode == 'expert'",
                ns = shiny::NS(NULL),
                tabPanel("Validation: Feature Stability",
                    h5(icon("sync"), "Bootstrap feature-importance stability"),
                    p(style = "color:#64748B; font-size:12px;",
                      "How often each taxon re-appears in the top-N ranking across ",
                      "bootstrap resamples. High selection-frequency = stable biomarker."),
                    shinycssloaders::withSpinner(
                        plotOutput(ns("stability_plot"), height = "520px"),
                        type = 6, color = "#3B82F6", size = 0.9,
                        caption = "Resampling & re-ranking features..."
                    )
                )
            )
        )
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("Performance Summary",
                h5(icon("table"), "Performance Summary"),
                shinycssloaders::withSpinner(
                    tableOutput(ns("rf_metrics_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "80px"
                ),
                hr(),
                h5(icon("clipboard-list"), "Confusion Matrix"),
                shinycssloaders::withSpinner(
                    verbatimTextOutput(ns("rf_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "120px"
                )
            ),
            tabPanel("Interpretation",
                h5(icon("brain"), "Interpretation"),
                uiOutput(ns("rf_interpretation"))
            ),
            tabPanel("Expert-grade Validation",
                h5(icon("user-check"), "Independent held-out test set"),
                shinycssloaders::withSpinner(
                    uiOutput(ns("heldout_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "140px"
                ),
                hr(),
                h5(icon("retweet"), "Repeated k-fold cross-validation"),
                shinycssloaders::withSpinner(
                    uiOutput(ns("cv_summary")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "140px"
                ),
                hr(),
                h5(icon("sync"), "Feature-importance stability (bootstrap)"),
                shinycssloaders::withSpinner(
                    DT::dataTableOutput(ns("stability_table")),
                    type = 6, color = "#3B82F6", size = 0.7,
                    proxy.height = "200px"
                ),
                hr(),
                downloadButton(ns("download_validation_csv"),
                               "Validation summary (CSV)",
                               class = "btn-success w-100")
            )
        )
    )

    tagList(
        h3("Random Forest Classification Analysis"),
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
