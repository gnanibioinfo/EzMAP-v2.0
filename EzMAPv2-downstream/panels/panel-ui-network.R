################################################################################
# panels/panel-ui-network.R — Network Analysis Panel UI (unified 2x2 layout)
################################################################################

library(shiny)
if (requireNamespace("igraph", quietly = TRUE)) library(igraph)
library(shinycssloaders)

networkUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
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
                    "Adjust the |r| threshold below (0.6 default) and ",
                    "bootstrap iterations (100 default). Edges kept when ",
                    "the bootstrap 95% CI excludes zero -- the ",
                    "Friedman & Alm 2012 SparCC approach used by most ",
                    "published microbiome co-occurrence networks. ",
                    "For Permutation+FDR, |r|-only filtering, or other ",
                    "advanced controls, switch to Expert mode."
                )
            )
        ),
        dataset_selector_ui(ns),
        h5(strong("Network construction")),
        # Correlation method (visible in both Easy and Expert)
        selectInput(ns("method"), "Network Method:",
                    choices = c("Pearson"                = "Pearson",
                                "Spearman"               = "Spearman",
                                "SparCC (compositional)" = "SparCC"),
                    selected = "Spearman"),
        uiOutput(ns("category_ui")),
        uiOutput(ns("sample_group_ui")),
        # Per-group ASV count table (Samples + non-zero ASVs per level
        # of the chosen metadata category). Lets the user see at a
        # glance how condition-specific each group is BEFORE running
        # the network.
        uiOutput(ns("group_asv_counts_ui")),

        # =====================================================
        # Network-specific pre-filter (visible in BOTH modes)
        # -----------------------------------------------------
        # Co-occurrence networks need aggressive prevalence /
        # abundance filtering for the FDR-corrected significance
        # test to ever find edges. With 1000+ taxa, BH correction
        # over n*(n-1)/2 simultaneous tests inflates every q-value
        # to 1.0, no matter how strong the underlying correlations.
        # 50-500 taxa is the empirical sweet spot.
        #
        # This filter STACKS on top of the global Filtering tab --
        # the global filter still applies first. The reason for a
        # separate per-panel filter: differential-abundance panels
        # (DESeq2, ANCOM-BC, LEfSe) DELIBERATELY keep rare taxa as
        # candidate biomarkers, while networks need them gone.
        # =====================================================
        hr(),
        h5(strong("Network pre-filter"),
           tags$small(style = "font-weight:400; color:#94A3B8; font-size:10px;",
                      " (network-only, stacks on top of Filtering tab)")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Differential-abundance tabs keep rare taxa on purpose ",
                 "(they may be biomarkers). Networks need them removed ",
                 "for FDR correction to find edges. ",
                 tags$b("Recommended: 30% prevalence + 50 reads."),
                 " Aim for ", tags$b("50-500 taxa post-filter"), "."),
        fluidRow(
            column(6, numericInput(ns("net_min_prevalence"),
                                   "Min % samples:",
                                   value = 30, min = 0, max = 100, step = 5)),
            column(6, numericInput(ns("net_min_reads"),
                                   "Min total reads:",
                                   value = 50, min = 0, step = 10))
        ),
        # Live count card: shows how many ASVs survive these
        # network-specific thresholds before the user clicks Run.
        uiOutput(ns("net_filter_preview")),

        # ---- |r| threshold (visible in BOTH Easy and Expert) ----
        # Pulled out of the Expert-only block per user feedback: this
        # is THE knob that controls network density (1-3% edge density
        # is typical for microbiome co-occurrence networks; 0.6 default
        # gets you there on most datasets). Hiding it from Easy users
        # forces them into a 21%-density blob -- the |r| dial is the
        # most consequential parameter and belongs in front.
        hr(),
        h5(strong("Correlation strength threshold")),
        uiOutput(ns("method_specific_ui")),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Edges below this |r| are dropped before the ",
                 "significance test. ",
                 tags$b("0.6 default"),
                 " gives ~1-3% edge density on typical microbiome ",
                 "data (publication-quality). ",
                 tags$b("0.5"), " is denser; ", tags$b("0.7+"),
                 " is sparser and lets hubs stand out."),

        # ---- Easy-mode bootstrap quick-picker ----
        # Default = 100 (matches Friedman & Alm 2012, the SparCC paper).
        # Slider exposes 20-200 so impatient users can drop to 20 for a
        # fast preview and rigorous users can push to 200 for tighter
        # p-values. The label warns about the trade-off so casual users
        # don't accidentally publish noisy 20-bootstrap p-values.
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            tagList(
                hr(),
                h5(strong("Bootstrap iterations")),
                sliderInput(ns("n_bootstrap_easy"),
                            label = NULL,
                            min = 20, max = 200, value = 100, step = 10,
                            ticks = TRUE),
                helpText(style = "font-size:11px; color:#64748B;",
                         tags$b("100"), " (default) matches the SparCC ",
                         "paper. ", tags$b("20"),
                         " gives wider CIs (more edges pass) -- use ",
                         "only for a quick preview. ", tags$b("200"),
                         " gives tighter CIs (fewer borderline edges) ",
                         "at ~2x the time. Switch to Expert mode for ",
                         "Permutation/FDR controls and CI level tuning.")
            )
        ),

        # ---- Expert-mode full controls ----
        # Edge significance testing has THREE distinct modes now:
        #   permutation  -- shuffle taxa to destroy associations,
        #                   compute null distribution, p = empirical
        #                   tail probability. FDR-corrected after.
        #                   BROKEN on large networks (smallest p =
        #                   1/(B+1) cannot survive BH x n*(n-1)/2).
        #   bootstrap_ci -- resample SAMPLES with replacement,
        #                   recompute correlation each time, keep
        #                   edge if 1-alpha CI does NOT contain 0.
        #                   No FDR needed (test is per-edge robustness,
        #                   not joint hypothesis). This is the
        #                   Friedman & Alm 2012 SparCC approach.
        #                   Recommended for publication.
        #   none         -- |r| filter only (skip bootstrap entirely).
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                # Note: |r| threshold (method_specific_ui) is now
                # rendered above this block so Easy mode users can see
                # and tune it. Don't re-render here or the same input
                # binding gets the value from whichever copy renders
                # last.
                h5(strong("Edge significance test")),
                selectInput(ns("edge_test"),
                            label = NULL,
                            choices = c(
                                "Bootstrap CI (recommended; Friedman & Alm 2012)" = "bootstrap_ci",
                                "Permutation p-value (with FDR correction)"      = "permutation",
                                "None -- |r| filter only"                         = "none"
                            ),
                            selected = "bootstrap_ci"),
                helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                         tags$b("Bootstrap CI"), ": resample samples with ",
                         "replacement, compute the (1 - alpha) CI of each ",
                         "correlation. Edge kept if CI does not include 0. ",
                         "Per-edge robustness test, no joint-hypothesis ",
                         "correction needed. ",
                         tags$b("Permutation"), ": tests against a ",
                         "no-association null with FDR correction across all ",
                         "n*(n-1)/2 edges -- mathematically empty on > ~50 ",
                         "taxa. ",
                         tags$b("None"), ": filter on |r| only (fast, no ",
                         "statistical test)."),
                hr(),

                # ---- Bootstrap iterations + CI level (used by both
                #      bootstrap CI and permutation paths) ----
                fluidRow(
                    column(6, numericInput(ns("n_bootstrap"),
                                           "Bootstrap iterations:",
                                           value = 100, min = 0, max = 2000,
                                           step = 50)),
                    column(6,
                        # Hide CI level if user picks Permutation; still
                        # in DOM but irrelevant. Keep simple: show always.
                        numericInput(ns("ci_level"),
                                     "Bootstrap CI level:",
                                     value = 0.95, min = 0.5, max = 0.999,
                                     step = 0.01))
                ),

                # ---- Permutation-only controls (collapsible) ----
                conditionalPanel(
                    condition = sprintf("input['%s'] == 'permutation'", ns("edge_test")),
                    fluidRow(
                        column(6, numericInput(ns("pval_threshold"),
                                               "P-value threshold:",
                                               value = 0.05, min = 0.001,
                                               max = 0.2, step = 0.01)),
                        column(6, selectInput(ns("fdr_method"),
                                              "FDR / multiple-testing correction:",
                                              choices = c(
                                                  "None (raw p)"           = "none",
                                                  "Benjamini-Hochberg (BH)"= "BH",
                                                  "Bonferroni"             = "bonferroni",
                                                  "BY (Benjamini-Yekutieli)" = "BY",
                                                  "Holm"                   = "holm"),
                                              selected = "none"))
                    )
                ),

                # ---- SparCC inner-iteration controls (only when method
                # = SparCC). Friedman & Alm 2012 use 20 iterations of
                # the iterative log-ratio variance decomposition; that's
                # enough for convergence on most datasets. Exposed for
                # reviewer-defensibility ("did you check convergence?")
                # and for users who want a faster preview at 10 or a
                # tighter fit at 50. The exclude_threshold is the
                # sparsification cutoff inside SparCC -- pairs with
                # implied |rho| below this get zeroed during the iterative
                # fit. 0.1 is the literature default.
                conditionalPanel(
                    condition = sprintf("input['%s'] == 'SparCC'", ns("method")),
                    hr(),
                    h6(strong("SparCC inner solver")),
                    fluidRow(
                        column(6, numericInput(ns("sparcc_n_iter"),
                                               "SparCC iterations:",
                                               value = 20, min = 5, max = 100,
                                               step = 5)),
                        column(6, numericInput(ns("sparcc_exclude_threshold"),
                                               "Exclude |rho| below:",
                                               value = 0.1, min = 0, max = 0.5,
                                               step = 0.05))
                    ),
                    helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                             tags$b("SparCC iterations"), ": Friedman & Alm 2012 ",
                             "default = 20. Convergence is typically reached by ",
                             "10-15; 20 is a comfortable margin. 50 for a more ",
                             "conservative fit. ",
                             tags$b("Exclude |rho|"), ": sparsification cutoff ",
                             "inside the iterative fit; 0.1 (default) matches ",
                             "the original paper. Lower = denser intermediate ",
                             "estimate, higher = sparser.")
                ),

                helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                         "100 bootstraps takes ~5 min on a 500-taxon network. ",
                         "Set bootstrap iterations to 0 + edge_test = None to ",
                         "skip the test entirely.")
            )
        ),
        hr(),
        actionButton(ns("run_network"), "Run Network",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        hr(),
        actionButton(ns("run_comparison"), "Run Group Comparison",
                     icon = icon("code-branch"),
                     class = "btn-outline-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Layout + appearance (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (not the underlying analysis) is available to
        # Easy-mode users so they can produce publication-ready figures
        # without leaving Easy. Statistical controls (correlation method,
        # bootstrap iterations, p-value threshold, FDR method) remain
        # Expert-only in the Controls column.
        h5(strong("Layout")),
        selectInput(ns("layout_method"), "Network Layout:",
                    choices = list(
                        "Fast (recommended)" = c(
                            "Nicely (auto-pick, fast)" = "layout_nicely",
                            "Graphopt (fast)"          = "layout_with_graphopt",
                            "DrL (fast, medium-large)" = "layout_with_drl",
                            "Circle (instant)"         = "layout_in_circle",
                            "Grid (instant)"           = "layout_on_grid"
                        ),
                        "Force-directed (slower)" = c(
                            "Fruchterman-Reingold" = "layout_with_fr",
                            "Kamada-Kawai"        = "layout_with_kk",
                            "LGL"                 = "layout_with_lgl",
                            "DH"                  = "layout_with_dh",
                            "GEM"                 = "layout_with_gem"
                        ),
                        "Specialized" = c(
                            "Sphere"      = "layout_on_sphere",
                            "Star"        = "layout_as_star",
                            "MDS"         = "layout_with_mds",
                            "Components"  = "layout_components"
                        )
                    ),
                    selected = "layout_nicely"),
        helpText(style = "font-size:10.5px; color:#64748B; margin-top:-4px;",
                 tags$b("Nicely"), " auto-selects the best algorithm for your network size. ",
                 tags$b("Graphopt"), " / ", tags$b("DrL"),
                 " are fast force-directed layouts. ",
                 tags$b("Fruchterman-Reingold"),
                 " is prettier but several seconds slower on networks > ~200 nodes."),

        conditionalPanel(
            condition = sprintf("input['%s'] == 'layout_with_fr'", ns("layout_method")),
            tags$div(style = "margin-top:8px; border:1px solid #E5E8EC; padding:8px; border-radius:6px; background:#FAFBFC;",
                numericInput(ns("fr_niter"), "FR iterations:",
                             value = 200, min = 50, max = 5000, step = 50),
                helpText(style = "font-size:10px;",
                         "Higher = better spread but slower. 200 is a faster default; raise to 500+ for prettier layouts on small networks.")
            )
        ),

        hr(),
        h5(strong("Node appearance")),
        # ---- Node sizing mode ----
        # "fixed"          -- every node the same radius (legacy default)
        # "degree"         -- linear scaling by degree (most intuitive for hubs)
        # "log_degree"     -- log scaling, useful when one super-hub dwarfs others
        # "betweenness"    -- bridges between communities pop out
        # "closeness"      -- centrally located taxa pop out
        # "eigen"          -- nodes connected to other well-connected taxa
        # The min/max sliders bound the rendered range so a 311-degree
        # super-hub doesn't render at vertex.size = 100.
        selectInput(ns("node_size_by"),
                    "Size nodes by:",
                    choices = c("Fixed size"          = "fixed",
                                "Degree (hub size)"   = "degree",
                                "Log(degree+1)"       = "log_degree",
                                "Betweenness"         = "betweenness",
                                "Closeness"           = "closeness",
                                "Eigenvector"         = "eigen"),
                    selected = "degree"),
        fluidRow(
            column(6, numericInput(ns("node_size"), "Min node size:",
                                   value = 3, min = 1, max = 20, step = 0.5)),
            column(6, numericInput(ns("node_size_max"), "Max node size:",
                                   value = 14, min = 1, max = 40, step = 0.5))
        ),
        helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                 "Min/Max set the range when sizing by a centrality metric. ",
                 "When ", tags$b("Fixed size"), " is selected only Min is used."),
        fluidRow(
            column(6, numericInput(ns("node_border"), "Border width:",
                                   value = 1.5, min = 0, max = 5, step = 0.5))
        ),
        fluidRow(
            column(6, tags$label("Node fill", style = "font-size:11px;"),
                      tags$input(id = ns("node_fill_color"), type = "color",
                                 value = "#DAA520",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Border color", style = "font-size:11px;"),
                      tags$input(id = ns("node_border_color"), type = "color",
                                 value = "#333333",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),

        hr(),
        h5(strong("Edge appearance")),
        fluidRow(
            column(6, numericInput(ns("edge_width"), "Edge width:",
                                   value = 0.6, min = 0.1, max = 5, step = 0.1)),
            column(6, numericInput(ns("edge_curved"), "Curvature:",
                                   value = 0.2, min = 0, max = 0.8, step = 0.05))
        ),
        fluidRow(
            column(6, tags$label("Positive edge", style = "font-size:11px;"),
                      tags$input(id = ns("edge_pos_color"), type = "color",
                                 value = "#27AE60",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Negative edge", style = "font-size:11px;"),
                      tags$input(id = ns("edge_neg_color"), type = "color",
                                 value = "#E74C3C",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),

        hr(),
        h5(strong("Download")),
        downloadButton(ns("download_network_graphml"),
                       "Graph (GraphML)",
                       class = "btn-success w-100 mb-2"),
        downloadButton(ns("download_node_stats"),
                       "Node Statistics (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        tabsetPanel(
            id = ns("network_tabs"),
            tabPanel("Network Visualization",
                uiOutput(ns("detailed_instructions")),
                shinycssloaders::withSpinner(
                    plotOutput(ns("network_plot"), height = "650px"),
                    type = 6, color = "#3B82F6", size = 0.9,
                    caption = "Constructing network (correlations + layout)..."
                )
            ),
            tabPanel("Centrality Distributions",
                h5("Node Centrality Metrics Distribution"),
                fluidRow(
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("plot_degree"),      height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7)),
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("plot_betweenness"), height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7))
                ),
                fluidRow(
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("plot_closeness"),   height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7)),
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("plot_eigen"),       height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7))
                ),
                hr(),
                h5("Edge Interactions Summary"),
                fluidRow(column(6, shinycssloaders::withSpinner(
                    plotOutput(ns("plot_edge_proportions"), height = "300px"),
                    type = 6, color = "#3B82F6", size = 0.7)))
            ),
            tabPanel("Network Statistics",
                h5(icon("chart-bar"), "Quantitative network descriptors"),
                p(style = "font-size:12.5px; color:#475569;",
                  "Standard graph-theoretic metrics for the constructed network. ",
                  "Use the CSV download to paste these numbers into the manuscript ",
                  "for a reviewer-defensible quantitative comparison ",
                  "(e.g. modularity, clustering coefficient, degree distribution)."),
                uiOutput(ns("network_metrics_caption")),
                shinycssloaders::withSpinner(
                    tableOutput(ns("network_metrics_table")),
                    type = 6, color = "#3B82F6", size = 0.7
                ),
                hr(),
                downloadButton(ns("download_network_metrics"),
                               "Network metrics (CSV)",
                               class = "btn-success")
            ),
            tabPanel("Group Comparison",
                p("Runs the selected network method for every level of the chosen metadata category and compares per-group centrality."),
                hr(),
                h5("Comparison of Node Centrality Metrics by Group"),
                fluidRow(
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("comparison_plot_degree"),      height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7,
                        caption = "Building per-group networks...")),
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("comparison_plot_betweenness"), height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7))
                ),
                fluidRow(
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("comparison_plot_closeness"),   height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7)),
                    column(6, shinycssloaders::withSpinner(
                        plotOutput(ns("comparison_plot_eigen"),       height = "300px"),
                        type = 6, color = "#3B82F6", size = 0.7))
                ),
                hr(),
                h5("Edge Interactions Summary by Group"),
                shinycssloaders::withSpinner(
                    plotOutput(ns("comparison_plot_edge_props"), height = "350px"),
                    type = 6, color = "#3B82F6", size = 0.7)
            )
        )
    )

    tagList(
        h3("Network Analysis"),
        hr(),
        analysis_tab_layout(
            controls   = controls,
            aesthetics = aesthetics,
            plot_area  = plot_area,
            stats_area = NULL,
            guide      = guide
        )
    )
}
