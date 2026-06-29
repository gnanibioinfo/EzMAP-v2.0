################################################################################
# panels/panel-ui-alpha.R -- Alpha Diversity UI (separated from Rarefaction)
#
# Rarefaction now lives in its own tab. This panel computes diversity metrics
# on the rarefied data and displays boxplots + statistical tests.
################################################################################

library(shinycssloaders)

alphaDiversityUI <- function(id, guide = NULL) {
    ns <- NS(id)

    controls <- tagList(
        # Easy Mode Info Banner
        conditionalPanel(
            condition = "input.analysis_mode == 'easy'",
            ns = shiny::NS(NULL),
            div(style = "background:#D1FAE5; border:1px solid #A7F3D0; border-radius:8px; padding:10px 14px; margin-bottom:12px;",
                tags$span(style = "font-weight:600; color:#065F46; font-size:13px;",
                          icon("check-circle"), " Easy Mode"),
                tags$p(style = "font-size:11px; color:#047857; margin:4px 0 0;",
                       "Shannon diversity by default -- switch the metric below to see Observed, Chao1, Simpson, etc. Statistical testing runs automatically. To customize colors and brackets, restart the app and select Expert mode.")
            )
        ),
        # Alert: rarefaction required (always visible)
        uiOutput(ns("rarefactionAlert")),
        hr(),
        h5(strong("Diversity Analysis")),
        # Group variable selector (always visible) -- this is the X-axis
        # variable. The optional Color/fill picker below lets the user
        # encode a SECOND metadata variable as fill color so the panel
        # can produce dodged-boxplot views like x = time, fill = condition
        # (the classic "diversity over time, by treatment group" plot).
        uiOutput(ns("groupVariableUI")),
        # Color/fill by -- separate from Group by. Server renders the
        # dropdown lazily so it can include all metadata columns
        # discovered after the data is loaded.
        uiOutput(ns("colorVariableUI")),
        helpText(style = "font-size:10.5px; color:#64748B; margin-top:-6px;",
                 "Leave \"Color by\" on ", tags$b("Same as Group"), " for the ",
                 "classic single-variable boxplot. Pick a different variable ",
                 "to get dodged boxplots -- e.g. ", tags$i("Group = time"),
                 ", ", tags$i("Color by = condition"),
                 " gives one cluster of condition-coloured boxes per timepoint."),
        # Alpha-diversity metric selector -- visible in BOTH Easy and Expert modes.
        # Lets the user switch between Shannon (default), Observed (richness),
        # Chao1, ACE, Simpson, and InvSimpson without restarting in Expert mode.
        selectInput(ns("alphaMeasure"), "Alpha Diversity Metric:",
                    choices = c(
                        "Shannon (default)"           = "Shannon",
                        "Observed (richness)"         = "Observed",
                        "Chao1 (rare-taxa richness)"  = "Chao1",
                        "ACE (abundance-based richness)" = "ACE",
                        "Simpson (dominance-weighted)" = "Simpson",
                        "Inverse Simpson"             = "InvSimpson"
                    ),
                    selected = "Shannon"),
        helpText(style = "font-size:11px; color:#64748B; margin-top:-6px;",
                 "Shannon balances richness and evenness. Observed counts unique ASVs only. ",
                 "Chao1 / ACE estimate rare-taxon-corrected richness. Simpson / InvSimpson emphasize dominant taxa."),
        # Group ordering on x-axis
        selectInput(ns("groupOrder"), "X-axis Group Order:",
                    choices = c("As in metadata"     = "default",
                                "Alphabetical"       = "alpha",
                                "By median diversity" = "median",
                                "Custom (drag)"      = "custom"),
                    selected = "default"),
        conditionalPanel(
            condition = paste0("input['", ns("groupOrder"), "'] == 'custom'"),
            uiOutput(ns("customGroupOrderUI"))
        ),
        # Facet variable
        uiOutput(ns("facetVariableUI")),
        # Expert-only: Comparison Mode and Significance Settings
        conditionalPanel(
            condition = "input.analysis_mode == 'expert'",
            ns = shiny::NS(NULL),
            tagList(
                h6(strong("Pairwise comparisons")),
                radioButtons(ns("comparisonMode"), NULL,
                             choices = c("Select specific comparisons" = "manual",
                                         "All pairwise (auto)"         = "auto"),
                             selected = "manual", inline = TRUE),
                uiOutput(ns("comparisonSelectorUI")),
                fluidRow(
                    column(6, checkboxInput(ns("showSigBrackets"),
                                            "Show brackets (significant only)",
                                            value = TRUE)),
                    column(6, numericInput(ns("sigAlpha"),
                                           "Significance cutoff (alpha):",
                                           value = 0.05, min = 0.001, max = 0.5, step = 0.01))
                ),
                checkboxInput(ns("showGlobalP"),
                              "Show overall (global) p-value on top of the plot",
                              value = TRUE),
                hr()
            )
        ),
        # Run button (always visible)
        actionButton(ns("runAlphaAnalysis"), "Run / Refresh Analysis",
                     icon = icon("play-circle"),
                     class = "btn-primary w-100"),
        helpText(style = "font-size:11px; color:#64748B; margin-top:6px;",
                 "Uses the rarefied data from the Rarefaction tab. ",
                 "Aesthetic and metric changes update the plot automatically.")
    )

    # Aesthetics column.
    # Basic plot-quality controls (font size, legend position, download
    # dimensions/DPI) are visible in BOTH Easy and Expert modes so users
    # can produce a publication-quality figure without leaving Easy mode.
    # Advanced styling (color palette, axis labels, jitter/boxplot width,
    # text axis titles) remains Expert-only.
    aesthetics <- tagList(
        # ---- Shared styling: titles, theme, grid, axis-title sizes ----
        # Adds plot title, legend title, ggplot theme picker, grid
        # toggles, and X/Y axis-title font-size controls. See
        # ezmap_plot_styling_ui()/ezmap_plot_styling() in global.r.
        ezmap_plot_styling_ui(ns,
                              default_legend_title = "Group"),
        hr(),

        # ---- Plot quality (Easy + Expert) ----
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
        # plot looks (palette, axis sizes/angles, boxplot width, jitter
        # size, custom labels) is available to Easy-mode users so they
        # can produce publication-ready figures without leaving Easy.
        # Statistical controls (pairwise comparisons, p-value method)
        # remain Expert-only in the Controls column.
        hr(),
        h5(strong("Advanced styling")),
        fluidRow(
            column(6, selectInput(ns("colorPalette"), "Color Palette:",
                                  choices = rownames(RColorBrewer::brewer.pal.info),
                                  selected = "Paired")),
            column(6, numericInput(ns("axisLabelSize"), "Axis Label Size:",
                                   value = 12, min = 8, max = 24, step = 1))
        ),
        fluidRow(
            column(6, numericInput(ns("xAngle"), "X-axis Label Angle:",
                                   value = 45, min = 0, max = 180, step = 5)),
            column(6, sliderInput(ns("boxplotWidth"), "Boxplot Width:",
                                  min = 0.1, max = 1.0, value = 0.6, step = 0.05))
        ),
        fluidRow(
            column(6, sliderInput(ns("jitterSize"), "Jitter Size:",
                                  min = 1, max = 5, value = 3, step = 0.5))
        ),
        fluidRow(
            column(6, textInput(ns("customXLabel"), "X-axis Label:",
                                value = "Sample Group")),
            column(6, textInput(ns("customYLabel"), "Y-axis Label (blank = metric):",
                                value = ""))
        ),

        # ---- Download (always visible -- including dimensions) ----
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
        downloadButton(ns("downloadAlphaPlot"),
                       "Boxplot (PNG)",
                       class = "btn-success w-100 mt-2")
    )

    plot_area <- tagList(
        shinycssloaders::withSpinner(
            plotOutput(ns("alphaBoxplot"), height = "500px"),
            type  = 6,
            color = "#3B82F6",
            size  = 0.9,
            caption = "Computing alpha-diversity metrics..."
        )
    )

    stats_area <- tagList(
        h5(strong("Statistics Summary")),
        shinycssloaders::withSpinner(
            verbatimTextOutput(ns("alphaStatsSummary")),
            type  = 6,
            color = "#3B82F6",
            size  = 0.7,
            proxy.height = "120px"
        )
    )

    tagList(
        h3("Alpha Diversity"),
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
