################################################################################
# panels/panel-server-rarefaction.R — Rarefaction Server Logic
#
# Separated from Alpha Diversity. Stores the rarefied phyloseq object so
# the Alpha Diversity module can consume it.
################################################################################

rarefactionServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # Internal reactive to hold the rarefied data
    rarefied_rv <- reactiveVal(NULL)

    # ======================================================================
    # RAREFACTION CURVE — gated behind input$runRarefaction so it does NOT
    # auto-execute when the user simply clicks the Rarefaction tab. The
    # curve only renders after the user clicks "Run Rarefaction", and then
    # re-renders live as Plot Customization inputs change.
    # ======================================================================

    # eventReactive that captures the *Controls* settings at the moment
    # the user presses Run Rarefaction. Subsequent live Plot-Customization
    # changes (group color variable, etc.) do NOT re-trigger this — they
    # only restyle the existing curve via the renderPlot below.
    rarefaction_curve_inputs <- eventReactive(input$runRarefaction, {
      Abundance <- physeq_data()
      req(Abundance)
      pct <- if (is.null(input$rarefactionPct)) 90 else input$rarefactionPct
      list(Abundance = Abundance, pct = pct)
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    output$rarefactionCurve <- renderPlot({
      # Pre-run placeholder — keeps the panel quiet on first tab open.
      if (is.null(input$runRarefaction) || input$runRarefaction == 0) {
        plot.new()
        plot.window(xlim = c(0, 1), ylim = c(0, 1))
        text(0.5, 0.6,
             "Click 'Run Rarefaction' to generate the rarefaction curves",
             cex = 1.4, font = 2, col = "#3B82F6")
        text(0.5, 0.45,
             "Adjust the depth slider in Controls, then click the button.",
             cex = 1.0, col = "#7F8C8D")
        return(invisible(NULL))
      }

      withProgress(message = "Generating Rarefaction Curves...", value = 0, {
        ci <- rarefaction_curve_inputs()
        req(ci, ci$Abundance)
        Abundance <- ci$Abundance
        pct       <- ci$pct

        incProgress(0.1, detail = "Extracting ASV table...")
        otu_mat <- as(otu_table(Abundance), "matrix")
        if (taxa_are_rows(Abundance)) otu_mat <- t(otu_mat)
        mode(otu_mat) <- "numeric"
        otu_mat <- otu_mat[rowSums(otu_mat, na.rm = TRUE) >= 2, , drop = FALSE]
        req(nrow(otu_mat) > 0, "No samples with sufficient reads.")

        incProgress(0.3, detail = "Preparing sample data...")
        sample_meta <- data.frame(sample_data(Abundance))
        # Plot-Customization input — read live so colors update without
        # re-running the rarefaction.
        group_var <- if (!is.null(input$rarefactionGroupVar) &&
                         input$rarefactionGroupVar != "None") input$rarefactionGroupVar else NULL

        min_reads <- min(rowSums(otu_mat, na.rm = TRUE))
        rarefaction_depth <- round(pct / 100 * min_reads)
        step_size <- max(100, round(rarefaction_depth / 20))

        incProgress(0.5, detail = "Drawing curves...")

        n_samples <- nrow(otu_mat)
        if (!is.null(group_var)) {
          groups <- factor(sample_meta[rownames(otu_mat), group_var])
          group_colors <- RColorBrewer::brewer.pal(min(8, nlevels(groups)), "Set2")
          colors <- group_colors[as.numeric(groups)]
        } else {
          colors <- RColorBrewer::brewer.pal(min(8, n_samples), "Dark2")
          colors <- rep(colors, length.out = n_samples)
        }

        vegan::rarecurve(
          otu_mat,
          step = step_size,
          sample = rarefaction_depth,
          col = colors,
          label = FALSE,
          cex = 0.6,
          xlab = "Sequencing Depth (Reads per Sample)",
          ylab = "Observed ASVs",
          main = paste0(if (!is.null(group_var)) paste0("Rarefaction by ", group_var, "\n") else "",
                        "Rarefaction Curves — Depth = ", rarefaction_depth, " reads")
        )

        if (!is.null(group_var)) {
          legend("bottomright", legend = levels(groups), col = group_colors, lty = 1, cex = 0.7, bty = "n")
        } else {
          legend("bottomright", legend = rownames(otu_mat), col = colors, lty = 1, cex = 0.5, bty = "n")
        }

        incProgress(1)
      })
    })

    # Group variable selector for rarefaction coloring
    output$rarefactionGroupVarUI <- renderUI({
      Abundance <- physeq_data()
      req(Abundance)
      vars <- sample_variables(Abundance)
      selectInput(session$ns("rarefactionGroupVar"), "Color Rarefaction by:",
                  choices = c("None", vars), selected = "None")
    })

    # ======================================================================
    # RAREFACTION SUMMARY — also gated behind input$runRarefaction. The
    # previous implementation called rarefy_even_depth() inside a plain
    # reactive(), which auto-fired the moment the tab was opened (because
    # the depth output / summary card depend on it). That meant a user just
    # browsing to the Rarefaction tab triggered a full rarefaction, which
    # is exactly what we want to avoid.
    # ======================================================================
    rarefaction_summary_reactive <- eventReactive(input$runRarefaction, {
      Abundance <- physeq_data()
      req(Abundance)
      pct <- if (is.null(input$rarefactionPct)) 90 else input$rarefactionPct
      min_depth <- min(sample_sums(Abundance))
      rarefaction_depth <- round(pct / 100 * min_depth)
      rarefied_temp <- tryCatch({
        rarefy_even_depth(Abundance, rngseed = 1, sample.size = rarefaction_depth,
                          replace = FALSE, verbose = FALSE)
      }, error = function(e) NULL)
      samples_retained <- if (!is.null(rarefied_temp)) nsamples(rarefied_temp) else 0
      list(min_reads = min_depth, depth_used = rarefaction_depth,
           samples_retained = samples_retained, pct_used = pct)
    }, ignoreInit = TRUE, ignoreNULL = TRUE)

    output$rarefactionDepthOutput <- renderUI({
      # Pre-run placeholder — quick read of just sample sums (cheap) so the
      # user sees min/max info before clicking Run, without triggering a
      # rarefy_even_depth() call.
      if (is.null(input$runRarefaction) || input$runRarefaction == 0) {
        Abundance <- physeq_data()
        if (is.null(Abundance)) return(NULL)
        pct <- if (is.null(input$rarefactionPct)) 90 else input$rarefactionPct
        min_depth <- min(sample_sums(Abundance))
        depth_preview <- round(pct / 100 * min_depth)
        return(tags$div(
          style = "font-size: 12px; line-height: 1.6;",
          tags$p(style = "margin:2px 0;", tags$b("Min Reads:"), format(min_depth, big.mark = ",")),
          tags$p(style = "margin:2px 0;", tags$b("Depth Preview:"),
                 tags$span(format(depth_preview, big.mark = ","),
                           paste0(" (", pct, "%)"),
                           style = "color:#007bff; font-weight:bold;")),
          tags$p(style = "margin:2px 0; color:#9CA3AF; font-style:italic;",
                 "Click Run Rarefaction to compute samples retained.")
        ))
      }

      summary <- rarefaction_summary_reactive()
      req(summary)
      tags$div(
        style = "font-size: 12px; line-height: 1.6;",
        tags$p(style = "margin:2px 0;", tags$b("Min Reads:"), format(summary$min_reads, big.mark = ",")),
        tags$p(style = "margin:2px 0;", tags$b("Depth Used:"),
               tags$span(format(summary$depth_used, big.mark = ","),
                         paste0(" (", summary$pct_used, "%)"),
                         style = "color:#007bff; font-weight:bold;")),
        tags$p(style = "margin:2px 0;", tags$b("Samples Retained:"), summary$samples_retained)
      )
    })

    output$rarefactionSummaryCard <- renderUI({
      if (is.null(input$runRarefaction) || input$runRarefaction == 0) {
        return(div(style = "padding:8px; background:#fff3cd; border-left:4px solid #f0ad4e; border-radius:4px; font-size:12.5px;",
                   icon("exclamation-triangle"), " Click ", strong("Run Rarefaction"),
                   " to compute the rarefied table. Then proceed to Alpha Diversity."))
      }
      summary <- rarefaction_summary_reactive()
      req(summary)
      rarefied <- rarefied_rv()
      if (is.null(rarefied)) {
        return(div(style = "padding:8px; background:#fff3cd; border-left:4px solid #f0ad4e; border-radius:4px; font-size:12.5px;",
                   icon("exclamation-triangle"), " Rarefaction in progress…"))
      }
      div(style = "padding:8px; background:#f0faf0; border-left:4px solid #27ae60; border-radius:4px; font-size:12.5px;",
          icon("check-circle", style = "color:#27ae60;"),
          strong(" Rarefaction complete. "),
          paste0(nsamples(rarefied), " samples retained at depth ",
                 format(summary$depth_used, big.mark = ","), ". "),
          "You can now proceed to the ", strong("Alpha Diversity"), " tab.")
    })

    # Cheap stats — just sample_sums(); fine to show on tab open.
    output$rarefactionStatsText <- renderPrint({
      Abundance <- physeq_data()
      req(Abundance)
      sums <- sort(sample_sums(Abundance))
      cat("Sample read depths (sorted):\n")
      cat(paste0("  ", names(sums), ": ", format(sums, big.mark = ",")), sep = "\n")
      cat("\nMin:", format(min(sums), big.mark = ","),
          " Max:", format(max(sums), big.mark = ","),
          " Median:", format(median(sums), big.mark = ","), "\n")
    })

    # ======================================================================
    # RUN RAREFACTION (on button click)
    # ======================================================================
    observeEvent(input$runRarefaction, {
      withProgress(message = 'Rarefying samples...', value = 0, {
        Abundance <- physeq_data()
        req(Abundance)
        raref_depth <- rarefaction_summary_reactive()$depth_used
        sample_data_orig <- sample_data(Abundance)
        req(nsamples(sample_data_orig) > 0)

        incProgress(0.3, detail = "Subsampling to even depth...")
        rarefied_temp <- tryCatch({
          rarefy_even_depth(Abundance, rngseed = 1, sample.size = raref_depth,
                            replace = FALSE, verbose = FALSE)
        }, error = function(e) {
          showNotification(paste("Rarefaction failed:", e$message), type = "error", duration = 8)
          NULL
        })
        req(rarefied_temp)

        incProgress(0.7, detail = "Building rarefied phyloseq...")
        rarefied <- phyloseq(otu_table(rarefied_temp), tax_table(Abundance),
                             sample_data_orig, phy_tree(Abundance))
        sample_names_kept <- sample_names(rarefied_temp)
        rarefied <- prune_samples(sample_names_kept, rarefied)
        req(nsamples(rarefied) > 0)

        rarefied_rv(rarefied)
        incProgress(1, detail = "Done!")
        showNotification(paste0("Rarefaction complete: ", nsamples(rarefied),
                                " samples at depth ", format(raref_depth, big.mark = ",")),
                         type = "message", duration = 5)
      })
    })

    # ======================================================================
    # DOWNLOAD
    # ======================================================================
    output$downloadRarefactionPlot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "RarefactionCurve"),
      content = function(file) {
        png(file, width = 8, height = 6, units = "in", res = 300)
        Abundance <- physeq_data()
        req(Abundance)
        pct <- if (is.null(input$rarefactionPct)) 90 else input$rarefactionPct
        otu_mat <- as(otu_table(Abundance), "matrix")
        if (taxa_are_rows(Abundance)) otu_mat <- t(otu_mat)
        mode(otu_mat) <- "numeric"
        otu_mat <- otu_mat[rowSums(otu_mat, na.rm = TRUE) >= 2, , drop = FALSE]
        min_reads <- min(rowSums(otu_mat, na.rm = TRUE))
        rarefaction_depth <- round(pct / 100 * min_reads)
        vegan::rarecurve(otu_mat, step = 100, sample = rarefaction_depth, col = "blue", label = FALSE)
        dev.off()
      }
    )

    # Return the rarefied data as a reactive so Alpha Diversity can use it
    return(reactive({ rarefied_rv() }))
  })
}
