################################################################################
# panels/panel-ui-beta.R — Beta Diversity Panel UI (unified 2x2 layout)
#
# Single entry point `betaDiversityUI()` now renders the whole panel (Controls
# + Aesthetics + Plot + Stats/Interpretation). `betaDiversityControlsUI()` is
# kept for compatibility but no longer used by ui.r.
################################################################################

library(shinycssloaders)

betaDiversityUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        dataset_selector_ui(ns),
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            div(style = "background:#D1FAE5; border:1px solid #A7F3D0; border-radius:8px; padding:10px 14px; margin-bottom:12px;",
                tags$span(style = "font-weight:600; color:#065F46; font-size:13px;",
                          icon("check-circle"), " Easy Mode"),
                tags$p(style = "font-size:11px; color:#047857; margin:4px 0 0;",
                       "Bray-Curtis PCoA with PERMANOVA. To customize, restart the app and select Expert mode.")
            )
        ),
        h5(strong("Ordination & PERMANOVA")),
        selectInput(ns("ordination_method"), "Ordination Method:",
                    choices = c("PCoA (metric MDS)" = "PCoA",
                                "NMDS (non-metric)" = "NMDS"),
                    selected = "PCoA"),
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            selectInput(ns("dist_method"), "Distance Method:",
                        choices = c("Bray-Curtis (bray)" = "bray",
                                    "Weighted UniFrac"   = "wunifrac",
                                    "Unweighted UniFrac" = "unifrac",
                                    "Jaccard"            = "jaccard",
                                    "Euclidean"          = "euclidean"),
                        selected = "bray")
        ),
        # Group by drives PERMANOVA + ellipses + the default color
        # encoding (when "Color by" is "Same as Group"). It is the
        # *statistical* grouping variable -- so the test and CIs reflect
        # whatever the user picks here.
        uiOutput(ns("group_variable_ui")),

        # Color/Fill by lets the user encode a SECOND variable as the
        # point color (e.g. "Group = condition" for PERMANOVA + ellipses,
        # but "Color = time" to see temporal drift within each
        # condition). When set to "Same as Group" the legacy behavior
        # is preserved -- one color per group.
        uiOutput(ns("color_variable_ui")),
        helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                 "Leave \"Color by\" on ", tags$b("Same as Group"),
                 " for the classic PCoA. Pick a different variable to ",
                 "decouple visual color from the statistical group ",
                 "(e.g. ", tags$i("Group = condition"), " for the ",
                 "PERMANOVA test, ", tags$i("Color = time"), " to see ",
                 "temporal drift within each condition)."),

        # Custom legend / level order (same pattern as alpha panel).
        # When the color variable has values like T1...T13, alphabetical
        # sort puts T10 before T2 -- this lets the user drag levels into
        # the natural numeric order instead.
        selectInput(ns("color_level_order"), "Color legend order:",
                    choices = c("As in metadata"     = "default",
                                "Alphabetical"       = "alpha",
                                "Custom (drag)"      = "custom"),
                    selected = "default"),
        conditionalPanel(
            condition = paste0("input['", ns("color_level_order"), "'] == 'custom'"),
            uiOutput(ns("custom_color_level_order_ui"))
        ),

        # Within-group faceting: split plot by one variable, color by another
        uiOutput(ns("facet_variable_ui")),
        # Shape variable + ellipses are visualization choices -- visible
        # in BOTH modes so Easy users can encode a second variable and
        # toggle confidence ellipses without leaving Easy. Statistical /
        # analysis controls (distance method) remain Expert-only above.
        uiOutput(ns("shape_variable_ui")),
        uiOutput(ns("extra_variables_ui")),
        hr(),
        checkboxInput(ns("show_ellipses"), "Show Confidence Ellipses", value = TRUE),
        uiOutput(ns("ellipse_controls_ui")),
        hr(),
        actionButton(ns("run_analysis"), "Run Analysis",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        helpText(style = "font-size:11px; color:#64748B; margin-top:6px;",
                 "NMDS also reports a stress value — values < 0.2 indicate a ",
                 "reasonable 2-D representation of the distance matrix.")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Group"),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
        h5(strong("Plot quality")),
        fluidRow(
            column(6, numericInput(ns("baseFontSize"), "Font Size:",
                                   value = 14, min = 8, max = 24)),
            column(6, selectInput(ns("legendPosition"), "Legend Position:",
                                  choices = c("right", "left", "top", "bottom", "none"),
                                  selected = "right"))
        ),

        # ---- Advanced styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (point size, palette, axis sizes/angles, legend
        # columns) is available to Easy-mode users so they can produce
        # publication-ready figures without leaving Easy. Statistical
        # controls (distance method) remain Expert-only in the Controls
        # column.
        hr(),
        h5(strong("Advanced styling")),
        fluidRow(
            column(6, sliderInput(ns("point_size"), "Point Size:",
                                  min = 1, max = 5, value = 3, step = 0.5)),
            column(6, selectInput(ns("palette"), "Color Palette:",
                                  choices = c("Set1", "Dark2", "Paired", "Spectral", "Viridis"),
                                  selected = "Set1"))
        ),
        fluidRow(
            column(6, numericInput(ns("axisLabelSize"), "Axis Label Size:",
                                   value = 12, min = 8, max = 24)),
            column(6, numericInput(ns("legendCols"), "Legend Columns:",
                                   value = 1, min = 1, max = 6))
        ),
        fluidRow(
            column(6, numericInput(ns("xAngle"), "X-axis Angle (°):",
                                   value = 45, min = 0, max = 180, step = 5)),
            column(6, numericInput(ns("yAngle"), "Y-axis Angle (°):",
                                   value = 0, min = 0, max = 180, step = 5))
        ),

        # ---- Download (always visible — including dimensions) ----
        hr(),
        h5(strong("Download")),
        fluidRow(
            column(4, numericInput(ns("downloadWidth"),  "Width:",  value = 10, min = 1)),
            column(4, numericInput(ns("downloadHeight"), "Height:", value = 6,  min = 1)),
            column(4, selectInput(ns("downloadUnits"), "Units:",
                                  choices = c("in", "cm", "px"), selected = "in"))
        ),
        fluidRow(
            column(6, numericInput(ns("downloadDPI"), "DPI:",
                                   value = 300, min = 100, max = 1200, step = 50))
        ),
        downloadButton(ns("downloadPcoaPlot"),
                       "Download Plot (PNG)",
                       class = "btn-success w-100 mt-2")
    )

    plot_area <- tagList(
        uiOutput(ns("ordination_header")),
        plotOutput(ns("pcoa_plot"), height = "600px") %>%
            withSpinner(type = 6, color = "#007bff"),
        uiOutput(ns("pcoa_plot_status"))
    )

    stats_area <- tagList(
        tabsetPanel(
            tabPanel("PERMANOVA Results",
                verbatimTextOutput(ns("permanova_result")) %>%
                    withSpinner(type = 5, color = "#28a745")
            ),
            tabPanel("Interpretation",
                uiOutput(ns("beta_interpretation"))
            )
        )
    )

    tagList(
        h3("Beta Diversity — Ordination and PERMANOVA"),
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

# Legacy wrapper (kept to avoid breaking any import). Returns the same UI,
# so callers still using betaDiversityControlsUI() get the full panel.
betaDiversityControlsUI <- function(id, guide = NULL) betaDiversityUI(id, guide = guide)
