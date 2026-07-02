################################################################################
# panels/panel-ui-rarefaction.R — Rarefaction Panel UI
# Updated with Easy/Expert mode
#
# Separated from Alpha Diversity so users rarefy first, then proceed to alpha.
################################################################################

library(shinycssloaders)

rarefactionUI <- function(id, guide = NULL) {
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
                "Auto rarefaction to minimum sample depth. To customize, restart the app and select Expert mode."
            )
        ),
        dataset_selector_ui(ns),
        h5(strong("Rarefaction Settings")),
        # Rarefaction depth slider - hidden in Easy mode
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            sliderInput(ns("rarefactionPct"), "Rarefaction Depth (% of Min Reads):",
                        min = 10, max = 100, value = 90, step = 5, post = "%")
        ),
        uiOutput(ns("rarefactionDepthOutput")),
        uiOutput(ns("rarefactionGroupVarUI")),
        hr(),
        # Run button - always visible
        actionButton(ns("runRarefaction"), "Run Rarefaction",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        helpText(style = "font-size:11px; color:#64748B; margin-top:6px;",
                 "Rarefaction subsamples each sample to the chosen depth. ",
                 "After rarefying, proceed to the Alpha Diversity tab for ",
                 "richness and evenness analysis.")
    )

    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # See ezmap_plot_styling_ui() / ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Sample"),
        hr(),

        # ---- Download (visible in BOTH modes — full controls) ----
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
        downloadButton(ns("downloadRarefactionPlot"),
                       "Download (PNG)",
                       class = "btn-success w-100 mt-2")
    )

    plot_area <- tagList(
        div(class = "text-muted small mb-1",
            icon("info-circle"),
            " Rarefying can take a moment for deep samples; please wait for the curve to render."),
        shinycssloaders::withSpinner(
            plotOutput(ns("rarefactionCurve"), height = "500px"),
            type  = 6,
            color = "#3B82F6",
            size  = 0.9,
            caption = "Rarefying samples & computing curves..."
        )
    )

    stats_area <- tagList(
        h5(strong("Rarefaction Summary")),
        uiOutput(ns("rarefactionSummaryCard")),
        hr(),
        h5(strong("Sample Depth Table")),
        shinycssloaders::withSpinner(
            verbatimTextOutput(ns("rarefactionStatsText")),
            type = 6, color = "#3B82F6", size = 0.7,
            proxy.height = "80px"
        )
    )

    tagList(
        h3("Rarefaction"),
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
