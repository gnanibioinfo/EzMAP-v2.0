################################################################################
# panels/panel-ui-deseq2.R -- DESeq2 Panel UI (unified 2x2 layout)
################################################################################

library(shinycssloaders)

deseq2UI <- function(id, guide = NULL) {
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
                "DESeq2 with padj < 0.05. The |log2FC| effect-size cutoff ",
                "is adjustable below (default 1 = 2-fold change). For full ",
                "control of the statistical threshold, restart the app and ",
                "select Expert mode."
            )
        )
    )

    controls <- tagList(
        dataset_selector_ui(ns),
        easy_banner,
        h5(strong("Analysis settings")),
        # Taxonomy aggregation level -- visible in BOTH modes so users
        # can run DESeq2 at the same level as Random Forest / ANCOM-BC
        # for a consistent consensus (ANCOM-BC+RF, DESeq2+RF panels join
        # by feature ID, so all three methods must agree on the level).
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
                 "ANCOM-BC tabs if you plan to use the ANCOM-BC+RF or ",
                 "DESeq2+RF overlap panels."),
        uiOutput(ns("group_variable_ui")),
        uiOutput(ns("comparison_ui")),
        # Per-group ASV count card -- shows samples + non-zero ASVs per
        # level of the chosen grouping variable, with the two selected
        # groups highlighted.
        uiOutput(ns("group_asv_counts_ui")),
        hr(),

        # ---- Effect-size cutoff (visible in BOTH modes) ----
        # Log2 fold-change is a *biological-relevance* threshold (how
        # large an effect counts as meaningful), so the user can tune
        # it without leaving Easy mode. The *statistical* threshold
        # (padj) is FDR-corrected and stays Expert-only -- its 0.05
        # default is a well-established convention.
        h5(strong("Effect-size cutoff")),
        numericInput(ns("log2fc_cutoff"),
                     "|Log2 Fold Change| cutoff:",
                     value = 1, min = 0, max = 8, step = 0.5),
        helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                 "Minimum absolute log2 fold change for a taxon to ",
                 "be considered biologically meaningful. ",
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
                numericInput(ns("padj_cutoff"), "Adjusted p-value Cutoff:",
                             value = 0.05, min = 0, max = 1, step = 0.01),
                helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                         "Benjamini-Hochberg FDR-corrected p-value threshold. ",
                         "0.05 (default) is the standard. Lower = stricter."),
                hr()
            )
        ),

        actionButton(ns("run_deseq2"), "Run DESeq2 Analysis",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Direction"),
        hr(),

        # ---- Volcano Plot Customization (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (not the underlying analysis) is available to
        # Easy-mode users so they can produce publication-ready figures
        # without leaving Easy. Statistical thresholds (padj, log2FC)
        # remain Expert-only in the Controls column.
        h5(strong("Volcano Plot Customization")),
        textInput(ns("plot_title"), "Plot Title:",
                  value = "DESeq2 Volcano Plot"),
        fluidRow(
            column(6, numericInput(ns("point_size"), "Point Size:",
                                   value = 3, min = 0.5, max = 5, step = 0.5)),
            column(6, numericInput(ns("label_top_n"), "Labels: top N by p:",
                                   value = 10, min = 0, max = 100, step = 1))
        ),
        fluidRow(
            column(6, numericInput(ns("label_size"), "Label font size:",
                                   value = 3.2, min = 1, max = 10, step = 0.2)),
            column(6, numericInput(ns("label_color_opacity"),
                                   "Label opacity (0-1):",
                                   value = 1, min = 0.1, max = 1, step = 0.1))
        ),
        checkboxInput(ns("show_labels"), "Label significant ASVs", TRUE),
        checkboxInput(ns("show_direction_arrows"),
                      "Show reference \u2194 comparison arrows", TRUE),
        hr(),
        h6(strong("Significance colors (one color per direction)")),
        fluidRow(
            column(6, tags$label("Reference-enriched", style = "font-size:11px;"),
                      tags$input(id = ns("color_ref"), type = "color",
                                 value = "#1f77b4",
                                 style = "width:100%;height:32px;padding:2px;")),
            column(6, tags$label("Comparison-enriched", style = "font-size:11px;"),
                      tags$input(id = ns("color_comp"), type = "color",
                                 value = "#d62728",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),
        fluidRow(
            column(6, tags$label("Not significant", style = "font-size:11px;"),
                      tags$input(id = ns("color_ns"), type = "color",
                                 value = "#BFC4C9",
                                 style = "width:100%;height:32px;padding:2px;"))
        ),
        hr(),

        h5(strong("Download")),
        download_dim_ui(ns, def_width = 9, def_height = 7),
        downloadButton(ns("download_volcano_plot"),
                       "Download Volcano Plot (PNG)",
                       class = "btn-success w-100 mb-2 mt-2"),
        downloadButton(ns("download_deseq2_table"),
                       "Download DESeq2 Results (CSV)",
                       class = "btn-success w-100")
    )

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            plotOutput(ns("volcano_plot"), height = "650px"),
            type    = 6,
            color   = "#1E293B",
            size    = 0.9,
            caption = "Running DESeq2 (this can take a minute)..."
        )
    )

    stats_area <- tagList(
        h5(strong("Result Summary")),
        shinycssloaders::withSpinner(
            verbatimTextOutput(ns("deseq2_summary")),
            type         = 6,
            color        = "#1E293B",
            size         = 0.7,
            proxy.height = "120px"
        )
    )

    tagList(
        h3("Differential Abundance Analysis (DESeq2)"),
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
