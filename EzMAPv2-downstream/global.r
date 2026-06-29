################################################################################
# global.R --Shared resources, libraries, and data definitions
# Loads all necessary packages and global options.
################################################################################

# ============================================================================
# Package Loading --core packages crash on failure, optional degrade gracefully
# ============================================================================

# Core packages (app cannot start without these)
library(shiny)
library(shinyjs)
library(ggplot2)
library(phyloseq)
library(biomformat)
library(plyr)
library(RColorBrewer)
library(dplyr)
library(vegan)
library(stringr)
library(shinycssloaders)

# Optional packages --loaded if available, features disabled if not
.load_optional <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    library(pkg, character.only = TRUE)
    TRUE
  } else {
    message("[EzMAP2] Optional package '", pkg, "' not available --related features disabled.")
    FALSE
  }
}

library(bslib)  # Core --ui.r requires bslib::page_navbar
.has_metagenomeSeq  <- .load_optional("metagenomeSeq")
.has_tidyverse      <- .load_optional("tidyverse")
.has_tidyr          <- .load_optional("tidyr")
.has_viridis        <- .load_optional("viridis")
.has_plotly         <- .load_optional("plotly")
.has_DT             <- .load_optional("DT")
.has_pairwiseAdonis <- .load_optional("pairwiseAdonis")
.has_DESeq2         <- .load_optional("DESeq2")
.has_EnhancedVolcano <- .load_optional("EnhancedVolcano")
.has_pheatmap       <- .load_optional("pheatmap")

# Convenience checker for use in panels
has_package <- function(pkg) requireNamespace(pkg, quietly = TRUE)

# Max Request Size Option (50MB)
options(shiny.maxRequestSize = 50 * 1024^2)

# Utility Function (kept for consistency)
find_hull <- function(df) df[chull(df$Axis.1, df$Axis.2), ]

# ============================================================================
# analysis_tab_layout() --Shared 3-column layout for every analysis tab.
#
#   ┌────────┬─────────────────────────┬──────────────────────┐
#   │        │                         │ Plot customization   │
#   │ Cntrls │  Results (tabs:         │  (+ Download)        │
#   │ + Run  │  Plot | Statistics)     ├──────────────────────┤
#   │        │                         │ Workflow Guide       │
#   │        │                         │  (← Back   Next ->)   │
#   └────────┴─────────────────────────┴──────────────────────┘
#
#   controls    : tagList placed in the LEFT card (inputs + Run button)
#   plot_area   : tagList placed inside the MIDDLE card, "Plot" tab
#   stats_area  : tagList placed inside the MIDDLE card, "Statistics" tab
#   aesthetics  : tagList placed in the RIGHT-TOP card (styling + Download)
#   guide       : tagList placed in the RIGHT-BOTTOM card (Workflow Guide)
#
# Any argument can be NULL and its card will be omitted.
# ============================================================================
analysis_tab_layout <- function(controls = NULL, aesthetics = NULL,
                                plot_area = NULL, stats_area = NULL,
                                guide = NULL) {

    # Card builder with optional accent class
    make_card <- function(header_icon, header_text, accent_class = NULL, ...) {
        bslib::card(
            class = accent_class,
            bslib::card_header(icon(header_icon), header_text),
            ...
        )
    }

    # -------- LEFT: Controls ---------------------------------------------
    left_col <- column(3,
        if (!is.null(controls)) {
            make_card("sliders-h", "Controls", "card-controls", controls)
        }
    )

    # -------- MIDDLE: Plot / Stats as tabs inside ONE card ---------------
    middle_tabs <- NULL
    has_plot  <- !is.null(plot_area)
    has_stats <- !is.null(stats_area)

    if (has_plot && has_stats) {
        middle_tabs <- tabsetPanel(
            type = "tabs",
            tabPanel(title = tagList(icon("chart-area"), "Plot"),       plot_area),
            tabPanel(title = tagList(icon("clipboard-list"), "Statistics"), stats_area)
        )
    } else if (has_plot) {
        middle_tabs <- tabsetPanel(
            type = "tabs",
            tabPanel(title = tagList(icon("chart-area"), "Plot"), plot_area)
        )
    } else if (has_stats) {
        middle_tabs <- tabsetPanel(
            type = "tabs",
            tabPanel(title = tagList(icon("clipboard-list"), "Statistics"), stats_area)
        )
    }

    middle_col <- column(6, class = "analysis-results-pane",
        if (!is.null(middle_tabs)) {
            make_card("chart-line", "Results", "card-results", middle_tabs)
        } else {
            make_card("chart-line", "Results", "card-results",
                      tags$em("No plot or statistics defined for this step."))
        }
    )

    # -------- RIGHT: Aesthetics on top + Workflow Guide below ------------
    right_col <- column(3,
        if (!is.null(aesthetics)) {
            make_card("palette", "Plot Customization", "card-aesthetics", aesthetics)
        },
        if (!is.null(guide)) {
            make_card("compass", "Workflow Guide", "card-guide", guide)
        }
    )

    fluidRow(left_col, middle_col, right_col)
}

# ============================================================================
# Dataset selector helper --adds a "Raw / Filtered" toggle to each panel
# ============================================================================

#' UI: dropdown for choosing raw vs filtered data
#' @param ns  the module's NS function
dataset_selector_ui <- function(ns) {
    tagList(
        selectInput(ns("dataset_choice"), "Input dataset:",
                    choices = c("Filtered (recommended)" = "filtered",
                                "Raw (unfiltered)"       = "raw"),
                    selected = "filtered"),
        helpText(style = "font-size:11px; color:#64748B;",
                 tags$b("Filtered:"), " uses your Filtering-tab settings ",
                 "(taxonomy cleanup, chloroplast/mitochondria removal, ",
                 "abundance thresholds).",
                 tags$br(),
                 tags$b("Raw:"), " uses the original uploaded data with ",
                 "no filtering applied."),
        hr()
    )
}

#' Server: reactive that returns the selected phyloseq object
#' @param input      module input
#' @param physeq_raw reactive returning raw phyloseq
#' @param physeq_filtered reactive returning filtered phyloseq (from filter module)
dataset_selector_reactive <- function(input, physeq_raw, physeq_filtered) {
    reactive({
        choice <- input$dataset_choice
        if (!is.null(choice) && choice == "raw") {
            pseq <- physeq_raw()
        } else {
            # Default to filtered; fall back to raw if filter not yet run
            pseq <- tryCatch(physeq_filtered(), error = function(e) NULL)
            if (is.null(pseq)) pseq <- physeq_raw()
        }
        req(pseq)
        pseq
    })
}

# ============================================================================
# Mode-aware download filename helper
# ============================================================================

#' Read the active Easy/Expert mode from the root Shiny session.
#'
#' Panels are namespaced Shiny modules and so their `input` object does
#' NOT contain `analysis_mode` --that input lives at the root session.
#' We walk up the reactive domain via `rootScope()` to read it. Returns
#' "easy" if the input isn't set or the call fails (e.g. the function
#' is invoked outside a reactive context during package check).
ezmap_get_mode <- function() {
    sess <- shiny::getDefaultReactiveDomain()
    if (is.null(sess)) return("easy")
    root <- tryCatch(sess$rootScope(), error = function(e) sess)
    val  <- tryCatch(root$input$analysis_mode, error = function(e) NULL)
    if (is.null(val) || !is.character(val) || !nzchar(val)) "easy" else val
}

#' Build a download filename of the form
#'   "EzMAP_<mode>_<base>_<YYYY-MM-DD>.<ext>"
#' so users can later distinguish Easy- vs Expert-mode artefacts at a
#' glance --important for reproducibility and reviewer transparency.
#'
#' @param base_name short, file-safe identifier (e.g. "Alpha_Boxplot")
#' @param ext       file extension without a dot (e.g. "png", "csv", "tsv")
ezmap_filename <- function(base_name, ext = "png") {
    paste0("EzMAP_", ezmap_get_mode(), "_", base_name, "_", Sys.Date(), ".", ext)
}

#' Read the user-chosen download image format from the panel's
#' `download_format` input. Falls back to "png" if the input doesn't
#' exist yet (panel not rendered, or non-image download).
#'
#' Walks up to the panel session via the namespace prefix because
#' the format selector lives inside each panel's aesthetics block.
ezmap_get_format <- function(input = NULL) {
    if (!is.null(input)) {
        fmt <- tryCatch(input$download_format, error = function(e) NULL)
        if (!is.null(fmt) && is.character(fmt) && nzchar(fmt)) return(fmt)
    }
    "png"
}

#' Build a download filename whose extension matches the user's
#' selected image format (PNG / PDF / SVG / TIFF / JPEG).
#'
#' Pass the panel's `input` object so the helper can read the format
#' from the namespaced selector. Use `ezmap_filename(base, "csv")`
#' instead for tables.
ezmap_download_filename <- function(input, base_name) {
    fmt <- ezmap_get_format(input)
    ezmap_filename(base_name, fmt)
}

#' Open the correct graphics device based on a file's extension.
#'
#' Used by panels (e.g. BugBase, complex heatmaps) that draw to a
#' device directly instead of going through ggsave(). Mirrors what
#' ggsave does internally --picks png() / pdf() / svg() / tiff() /
#' jpeg() based on the file extension. Caller is responsible for
#' calling dev.off() when done.
#'
#' Width / height units: PDF and SVG always use inches; PNG / TIFF /
#' JPEG honour the user's chosen units.
ezmap_open_device <- function(file, width = 9, height = 7,
                              units = "in", dpi = 300) {
    ext <- tolower(tools::file_ext(file))
    if (ext == "pdf") {
        # PDF size is always in inches.
        if (units == "cm") { width <- width / 2.54; height <- height / 2.54 }
        if (units == "px") { width <- width / dpi;  height <- height / dpi  }
        grDevices::pdf(file, width = width, height = height)
    } else if (ext == "svg") {
        if (units == "cm") { width <- width / 2.54; height <- height / 2.54 }
        if (units == "px") { width <- width / dpi;  height <- height / dpi  }
        grDevices::svg(file, width = width, height = height)
    } else if (ext == "tiff" || ext == "tif") {
        grDevices::tiff(file, width = width, height = height,
                        units = units, res = dpi, compression = "lzw")
    } else if (ext == "jpeg" || ext == "jpg") {
        grDevices::jpeg(file, width = width, height = height,
                        units = units, res = dpi, quality = 95)
    } else {
        # Default: PNG
        grDevices::png(file, width = width, height = height,
                       units = units, res = dpi)
    }
}

# ============================================================================
# Per-group ASV count card (used by Network / DESeq2 / ANCOM-BC / RF)
# ============================================================================

#' Build the "ASV count by <category>" info card.
#'
#' Computes, for every level of the chosen metadata column, the number
#' of samples and non-zero ASVs after `prune_samples` + `prune_taxa(>0)`
#' (i.e. exactly what the analysis panels see for that group). Returns
#' a styled HTML div ready to drop into a renderUI.
#'
#' Used by Network, DESeq2, ANCOM-BC, and Random Forest panels so users
#' can see at a glance how condition-specific each group is BEFORE
#' running the analysis. Highlights the row(s) currently selected for
#' the comparison.
#'
#' @param pseq            phyloseq object (centrally filtered)
#' @param category        name of the metadata column (e.g. "Condition")
#' @param selected_groups character vector of currently selected groups
#'                        (length 1 or 2 typically; can be longer for
#'                        multi-group methods like Network)
#' @return shiny tag (or NULL if inputs invalid)
group_asv_count_card <- function(pseq, category, selected_groups = character(0)) {
    if (is.null(pseq) || is.null(category) || !nzchar(category)) return(NULL)
    metadata <- as(sample_data(pseq), "data.frame")
    if (!category %in% colnames(metadata)) return(NULL)

    levels_group <- sort(unique(stats::na.omit(as.character(metadata[[category]]))))
    if (length(levels_group) == 0) return(NULL)

    rows <- lapply(levels_group, function(g) {
        keep <- rownames(metadata)[as.character(metadata[[category]]) == g]
        sub  <- prune_samples(keep, pseq)
        sub  <- prune_taxa(taxa_sums(sub) > 0, sub)
        data.frame(
            Group   = g,
            Samples = nsamples(sub),
            ASVs    = ntaxa(sub),
            stringsAsFactors = FALSE
        )
    })
    df <- do.call(rbind, rows)
    selected <- as.character(selected_groups)
    df$Selected <- ifelse(df$Group %in% selected, "✓", "")

    tags$div(
        style = "margin-top:6px; margin-bottom:10px; padding:10px;
                 background:#F0F9FF; border-left:4px solid #3B82F6;
                 border-radius:4px; font-size:12px; color:#1F2937;",
        tags$div(style = "font-weight:600; margin-bottom:4px; color:#1E40AF;",
                 icon("info-circle"),
                 paste0(" ASV count by ", category, " --total ",
                        ntaxa(pseq), " ASVs in the filtered dataset")),
        tags$table(
            style = "width:100%; border-collapse:collapse; font-size:12px;",
            tags$thead(
                tags$tr(
                    tags$th(style = "text-align:left;  padding:3px 6px; border-bottom:1px solid #93C5FD; width:14%;", "Sel."),
                    tags$th(style = "text-align:left;  padding:3px 6px; border-bottom:1px solid #93C5FD;",          category),
                    tags$th(style = "text-align:right; padding:3px 6px; border-bottom:1px solid #93C5FD; width:22%;", "Samples"),
                    tags$th(style = "text-align:right; padding:3px 6px; border-bottom:1px solid #93C5FD; width:22%;", "Non-zero ASVs")
                )
            ),
            tags$tbody(lapply(seq_len(nrow(df)), function(i) {
                row_bg <- if (df$Selected[i] == "✓") "background:#DBEAFE;" else ""
                tags$tr(style = row_bg,
                    tags$td(style = paste0("padding:3px 6px; color:#1E40AF; font-weight:600;", row_bg),
                            df$Selected[i]),
                    tags$td(style = paste0("padding:3px 6px;", row_bg), df$Group[i]),
                    tags$td(style = paste0("padding:3px 6px; text-align:right;", row_bg),
                            format(df$Samples[i], big.mark = ",")),
                    tags$td(style = paste0("padding:3px 6px; text-align:right;", row_bg),
                            format(df$ASVs[i], big.mark = ","))
                )
            }))
        ),
        tags$div(style = "margin-top:6px; font-style:italic; color:#475569; font-size:11px;",
                 "Different ASV counts per group reflect condition-specific presence/absence. ",
                 "Highlighted row(s) are the group(s) currently selected for the analysis.")
    )
}

# ============================================================================
# Reusable download dimension UI + helper
# ============================================================================

#' UI: Width / Height / Units / DPI controls.
#'
#' Add this to any panel's aesthetics column right above its
#' downloadButton(s) so users can choose publication-ready dimensions
#' (visible in BOTH Easy and Expert modes --consistent across panels).
#' The matching server-side helper is `download_dims()`.
#'
#' @param ns          the module's NS function
#' @param def_width   default width (default 9)
#' @param def_height  default height (default 7)
#' @param def_units   default units (default "in")
#' @param def_dpi     default DPI  (default 300)
download_dim_ui <- function(ns, def_width = 9, def_height = 7,
                            def_units = "in", def_dpi = 300,
                            def_format = "png") {
    tagList(
        fluidRow(
            column(4, numericInput(ns("downloadWidth"),  "Width:",  value = def_width, min = 1)),
            column(4, numericInput(ns("downloadHeight"), "Height:", value = def_height, min = 1)),
            column(4, selectInput(ns("downloadUnits"), "Units:",
                                  choices = c("in", "cm", "px"),
                                  selected = def_units))
        ),
        fluidRow(
            column(6, numericInput(ns("downloadDPI"), "DPI:",
                                   value = def_dpi, min = 100, max = 1200, step = 50)),
            # File format selector --visible in BOTH modes so users can
            # produce vector outputs for journal submissions without
            # leaving Easy mode. ggsave detects the format from the
            # output filename extension, so changing this updates both
            # the saved file's content type and its filename suffix.
            column(6, selectInput(ns("download_format"), "File format:",
                                  choices = c("PNG"  = "png",
                                              "PDF (vector)" = "pdf",
                                              "SVG (vector)" = "svg",
                                              "TIFF" = "tiff",
                                              "JPEG" = "jpeg"),
                                  selected = def_format))
        )
    )
}

#' Server: read W/H/Units/DPI from input with safe defaults.
#'
#' Returns a 4-element list ready to splat into ggsave():
#'   args <- download_dims(input)
#'   ggsave(file, plot = p, width = args$width, height = args$height,
#'          units = args$units, dpi = args$dpi)
download_dims <- function(input,
                          def_width = 9, def_height = 7,
                          def_units = "in", def_dpi = 300) {
    w <- if (is.null(input$downloadWidth)  || !is.finite(input$downloadWidth))  def_width  else input$downloadWidth
    h <- if (is.null(input$downloadHeight) || !is.finite(input$downloadHeight)) def_height else input$downloadHeight
    u <- if (is.null(input$downloadUnits)  || !nzchar(input$downloadUnits))     def_units  else input$downloadUnits
    d <- if (is.null(input$downloadDPI)    || !is.finite(input$downloadDPI))    def_dpi    else input$downloadDPI
    list(width = w, height = h, units = u, dpi = d)
}

# ============================================================================
# Shared plot-styling controls (visible in BOTH modes)
# ----------------------------------------------------------------------------
# These four controls --plot title, legend title, ggplot theme, grid lines --
# were missing from most panels. They are now centralized so each panel can
# add them with one helper call instead of duplicating the same fluidRows.
#
# UI side:
#   ezmap_plot_styling_ui(ns)  -> returns a tagList of inputs with namespaced
#                                IDs: plotTitle / legendTitle / plotTheme /
#                                showMajorGrid / showMinorGrid
#
# Server side:
#   styles <- ezmap_plot_styling(input, default_legend_title = "Group")
#   p <- p + styles$theme(base_size = 14) + styles$grid_theme + styles$labs
#   # `styles$labs` is a labs() with title= (and fill= if provided)
#
# Use this helper anywhere we'd otherwise write theme_bw() + theme()
# inline. Keeps the look consistent across every panel.
# ============================================================================

#' UI: shared "Titles & theme + grid + axis title sizes" block.
#'
#' Adds plot title, legend title, ggplot theme picker, major/minor grid
#' toggles, and **separate font-size controls for the X-axis title and
#' the Y-axis title** (these are the axis labels themselves --distinct
#' from the per-panel "Axis Label Size" / "axisLabelSize" input which
#' controls tick-text size). Pass the module's `ns` so the input IDs
#' are namespaced.
ezmap_plot_styling_ui <- function(ns,
                                  default_title = "",
                                  default_legend_title = "",
                                  default_theme = "bw",
                                  default_axis_title_size = 13,
                                  default_legend_title_size = 12,
                                  default_legend_text_size  = 11,
                                  default_plot_title_size   = 16) {
    tagList(
        h5(strong("Titles & theme")),
        textInput(ns("plotTitle"), "Plot title:", value = default_title),
        fluidRow(
            column(6, textInput(ns("legendTitle"), "Legend title:",
                                value = default_legend_title)),
            column(6, selectInput(ns("plotTheme"), "ggplot theme:",
                                  choices  = c("Black/white grid" = "bw",
                                               "Classic (no grid)" = "classic",
                                               "Minimal"           = "minimal",
                                               "Light"             = "light",
                                               "Dark"              = "dark",
                                               "Linedraw"          = "linedraw",
                                               "Void (no axes)"    = "void"),
                                  selected = default_theme))
        ),
        fluidRow(
            column(6, checkboxInput(ns("showMajorGrid"),
                                    "Show major grid lines", value = TRUE)),
            column(6, checkboxInput(ns("showMinorGrid"),
                                    "Show minor grid lines", value = FALSE))
        ),

        # ---- Axis-title + legend font sizes ----
        # These are SEPARATE from the per-panel tick-text size control
        # ("Axis Label Size" / axisLabelSize). The user asked for X- and
        # Y-axis title sizes specifically --the "Sample Group" /
        # "Relative Abundance" labels themselves rather than the tick
        # numbers --and for those to be available in BOTH Easy and
        # Expert modes across every plotting panel.
        h6(strong("Axis-title & legend font sizes")),
        fluidRow(
            column(6, numericInput(ns("xAxisTitleSize"),
                                   "X-axis label size:",
                                   value = default_axis_title_size,
                                   min = 6, max = 36, step = 1)),
            column(6, numericInput(ns("yAxisTitleSize"),
                                   "Y-axis label size:",
                                   value = default_axis_title_size,
                                   min = 6, max = 36, step = 1))
        ),
        fluidRow(
            column(6, numericInput(ns("legendTitleSize"),
                                   "Legend title size:",
                                   value = default_legend_title_size,
                                   min = 6, max = 30, step = 1)),
            column(6, numericInput(ns("legendTextSize"),
                                   "Legend item size:",
                                   value = default_legend_text_size,
                                   min = 6, max = 30, step = 1))
        ),
        numericInput(ns("plotTitleSize"),
                     "Plot title size:",
                     value = default_plot_title_size,
                     min = 8, max = 40, step = 1,
                     width = "50%"),
        helpText(style = "font-size:11px; color:#64748B;",
                 "Leave Plot title / Legend title blank to suppress them. ",
                 "Axis-title sizes set the font of the axis labels themselves ",
                 "(e.g. \"Sample Group\"); the per-panel \"Axis Label Size\" ",
                 "controls tick-text size separately.")
    )
}

#' Server: resolve the shared styling inputs into ready-to-use ggplot
#' building blocks. Safe against NULL inputs (returns sensible defaults
#' if the panel hasn't yet wired the helper UI).
ezmap_plot_styling <- function(input,
                               default_legend_title = "",
                               base_size = 14) {
    plot_title   <- if (is.null(input$plotTitle))   "" else input$plotTitle
    legend_title <- if (is.null(input$legendTitle)) default_legend_title else input$legendTitle
    plot_theme   <- if (is.null(input$plotTheme))   "bw" else input$plotTheme
    show_major   <- if (is.null(input$showMajorGrid)) TRUE  else isTRUE(input$showMajorGrid)
    show_minor   <- if (is.null(input$showMinorGrid)) FALSE else isTRUE(input$showMinorGrid)

    # Font sizes for axis titles + legend (with safe defaults).
    x_title_size   <- if (is.null(input$xAxisTitleSize)  || !is.finite(input$xAxisTitleSize))  13 else input$xAxisTitleSize
    y_title_size   <- if (is.null(input$yAxisTitleSize)  || !is.finite(input$yAxisTitleSize))  13 else input$yAxisTitleSize
    legend_t_size  <- if (is.null(input$legendTitleSize) || !is.finite(input$legendTitleSize)) 12 else input$legendTitleSize
    legend_x_size  <- if (is.null(input$legendTextSize)  || !is.finite(input$legendTextSize))  11 else input$legendTextSize
    plot_t_size    <- if (is.null(input$plotTitleSize)   || !is.finite(input$plotTitleSize))   16 else input$plotTitleSize

    theme_fn <- switch(plot_theme,
        "classic"  = ggplot2::theme_classic,
        "minimal"  = ggplot2::theme_minimal,
        "light"    = ggplot2::theme_light,
        "dark"     = ggplot2::theme_dark,
        "linedraw" = ggplot2::theme_linedraw,
        "void"     = ggplot2::theme_void,
        ggplot2::theme_bw)

    # Theme overrides: title styling + grid line toggles + axis-title and
    # legend font sizes. axis.title.x / axis.title.y target the labels
    # themselves (e.g. "Sample Group"), independent of axis.text which
    # is the tick-text and is set per-panel by the existing
    # axisLabelSize input.
    grid_theme <- ggplot2::theme(
        plot.title       = ggplot2::element_text(face = "bold",
                                                 size = plot_t_size,
                                                 hjust = 0.5),
        axis.title.x     = ggplot2::element_text(size = x_title_size),
        axis.title.y     = ggplot2::element_text(size = y_title_size),
        legend.title     = ggplot2::element_text(size = legend_t_size),
        legend.text      = ggplot2::element_text(size = legend_x_size),
        panel.grid.major = if (show_major) ggplot2::element_line() else ggplot2::element_blank(),
        panel.grid.minor = if (show_minor) ggplot2::element_line() else ggplot2::element_blank()
    )

    list(
        title        = if (nzchar(plot_title)) plot_title else NULL,
        legend_title = if (nzchar(legend_title)) legend_title else NULL,
        theme_fn     = theme_fn,
        grid_theme   = grid_theme,
        # Convenience labs(): pass `extra_labs = list(x="...", y="...")`
        # to merge with x/y labels the panel already builds.
        labs         = ggplot2::labs(
            title = if (nzchar(plot_title))   plot_title   else NULL,
            fill  = if (nzchar(legend_title)) legend_title else NULL,
            color = if (nzchar(legend_title)) legend_title else NULL
        )
    )
}

# ============================================================================
# Branding placeholder --shown in empty result panes before analysis is run
# ============================================================================
ezmap_placeholder <- function(module_name = "this module") {
    div(style = "text-align:center; padding:36px 20px;",
        tags$i(class = "fa fa-flask",
               style = "font-size:40px; color:#CBD5E1; margin-bottom:12px;"),
        tags$h4(style = "color:#64748B; font-weight:600; font-size:15px; margin-bottom:8px;",
                "EzMAP v2.0"),
        tags$p(style = "font-size:12.5px; color:#94A3B8; max-width:380px; margin:0 auto;",
               "Configure parameters and click ",
               tags$b(style = "color:#64748B;", "Run Analysis"),
               paste0(" to generate results for ", module_name, ".")),
        tags$p(style = "font-size:10px; color:#CBD5E1; margin-top:10px; letter-spacing:0.5px;",
               "Easy Microbiome Analysis Pipeline v2.0")
    )
}

# --- Source Module Server Files ---
# IMPORTANT: These files MUST exist in the 'panels/' directory
source("panels/panel-server-data.R", local = TRUE)
source("panels/panel-server-filter.R", local = TRUE)
source("panels/panel-server-ra.R", local = TRUE)
source("panels/panel-server-rarefaction.R", local = TRUE)
source("panels/panel-server-alpha.R", local = TRUE)
source("panels/panel-server-beta.R", local = TRUE)
source("panels/panel-server-deseq2.R", local = TRUE)
source("panels/panel-server-random.R", local = TRUE)
source("panels/panel-server-network.R", local = TRUE)
source("panels/panel-server-tax4fun2.R", local = TRUE)
source("panels/panel-server-bugbase.R", local = TRUE)
source("panels/panel-server-lefse.R", local = TRUE)
source("panels/panel-server-ancombc.R", local = TRUE)
# Combined DESeq2 + Random Forest panel (added 2026-04-16)
source("panels/panel-server-deseq2rf.R", local = TRUE)
# Combined ANCOM-BC + Random Forest panel (added 2026-04-29)
source("panels/panel-server-ancombcrf.R", local = TRUE)
source("panels/panel-server-funguild.R", local = TRUE)
