################################################################################
# panels/panel-ui-ra.R — Relative Abundance Panel UI (unified 2x2 layout)
# Updated with Easy/Expert mode
################################################################################

library(shinycssloaders)

raPlotUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        # Easy mode info banner
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            div(
                class = "alert alert-info",
                style = "border-left: 4px solid #10B981; background-color: #ECFDF5; color: #065F46;",
                icon("info-circle"),
                " ",
                strong("Easy Mode: "),
                "Stacked bar at selected taxonomy level. To customize, restart the app and select Expert mode."
            )
        ),
        h5(strong("Data Source")),
        radioButtons(ns("data_source"), NULL,
                     choices = list("Normalized" = "normalized",
                                    "Filtered (Counts)" = "filtered"),
                     selected = "normalized",
                     inline = TRUE),
        hr(),
        h5(strong("Plot Controls")),
        # Taxonomy level selector - always visible
        selectInput(ns("taxaRank"), "Taxonomic Level:",
                    choices = c("Phylum", "Class", "Order", "Family", "Genus"),
                    selected = "Phylum"),
        # Group variable - always visible
        uiOutput(ns("groupVariableUI")),
        # Sample / group ordering
        selectInput(ns("sampleOrder"), "X-axis Order:",
                    choices = c("As in metadata"    = "default",
                                "Alphabetical"      = "alpha",
                                "By total abundance" = "abundance",
                                "Custom (drag)"     = "custom"),
                    selected = "default"),
        conditionalPanel(
            condition = paste0("input['", ns("sampleOrder"), "'] == 'custom'"),
            uiOutput(ns("customOrderUI"))
        ),
        # Facet variable
        uiOutput(ns("facetVariableUI")),
        # Minimum Abundance - hidden in Easy mode
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            numericInput(ns("minAbundance"), "Minimum Relative Abundance (%):",
                         value = 1, min = 0, max = 100, step = 0.5)
        ),
        hr(),
        h5(strong("Sample Filtering")),
        helpText("Select metadata variables, then choose the levels to include."),
        uiOutput(ns("filterVariableSelector")),
        uiOutput(ns("filterValueSelectors")),
        hr(),
        # Run button - always visible
        actionButton(ns("updatePlot"), "Generate Plot",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # Single helper replaces what used to be hand-rolled per-panel.
        # See ezmap_plot_styling_ui()/ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = ""),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
        # Note: baseFontSize sets the ggplot theme base_size (affects
        # everything globally); axisLabelSize controls TICK text
        # specifically. Axis-TITLE sizes live in the helper above.
        h5(strong("Plot quality")),
        fluidRow(
            column(6, numericInput(ns("baseFontSize"), "Font Size:",
                                   value = 14, min = 8, max = 24, step = 1)),
            column(6, selectInput(ns("legendPosition"), "Legend Position:",
                                  choices = c("right", "left", "top", "bottom", "none"),
                                  selected = "right"))
        ),

        # ---- Advanced styling (visible in BOTH modes) ----
        # Per the design contract: anything that affects ONLY how the
        # plot looks (palette, axis size/angle, legend columns, custom
        # labels) is available to Easy-mode users so they can produce
        # publication-ready figures without leaving Easy. The minimum
        # abundance cutoff remains Expert-only in the Controls column.
        hr(),
        h5(strong("Advanced styling")),
        fluidRow(
            column(6, selectInput(ns("colorPalette"), "Color Palette:",
                                  choices = rownames(brewer.pal.info),
                                  selected = "Paired")),
            column(6, numericInput(ns("axisLabelSize"), "Axis Label Size:",
                                   value = 12, min = 8, max = 24, step = 1))
        ),
        fluidRow(
            column(6, numericInput(ns("xAngle"), "X-axis Label Angle (\u00B0):",
                                   value = 90, min = 0, max = 180, step = 5)),
            column(6, numericInput(ns("legendCols"), "Legend Columns:",
                                   value = 1, min = 1, max = 6, step = 1))
        ),
        fluidRow(
            column(6, textInput(ns("customXLabel"), "X-axis Label:",
                                value = "Sample Group")),
            column(6, textInput(ns("customYLabel"), "Y-axis Label:",
                                value = "Relative Abundance"))
        ),

        # ---- Download (always visible \u2014 full controls) ----
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
        downloadButton(ns("downloadRAplot"),
                       "Download (PNG)",
                       class = "btn-success w-100 mt-2")
    )

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            plotOutput(ns("raPlot"), height = "600px"),
            type    = 6,
            color   = "#1E293B",
            size    = 0.9,
            caption = "Aggregating taxa & building plot..."
        )
    )

    tagList(
        h3("Relative Abundance Plots"),
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
