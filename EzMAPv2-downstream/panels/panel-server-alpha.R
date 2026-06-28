################################################################################
# panels/panel-server-alpha.R -- Alpha Diversity Server (uses rarefied data)
#
# Receives the rarefied phyloseq object from the Rarefaction module.
# If rarefaction hasn't been run yet, shows an alert.
################################################################################

alphaDiversityServer <- function(id, rarefied_data, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {

    # --- Dataset selector (used only for group variable list) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # ======================================================================
    # RAREFACTION ALERT
    # ======================================================================
    output$rarefactionAlert <- renderUI({
      rarefied <- rarefied_data()
      if (is.null(rarefied)) {
        div(style = "padding:10px 14px; background:#fff3cd; border-left:4px solid #f0ad4e; border-radius:4px; font-size:12.5px; margin-bottom:6px;",
            icon("exclamation-triangle", style = "color:#f0ad4e;"),
            strong(" Rarefaction required. "),
            "Please go to the ", strong("Rarefaction"), " tab first and click ",
            strong("Run Rarefaction"), " before computing alpha diversity metrics.")
      } else {
        div(style = "padding:10px 14px; background:#f0faf0; border-left:4px solid #27ae60; border-radius:4px; font-size:12.5px; margin-bottom:6px;",
            icon("check-circle", style = "color:#27ae60;"),
            strong(" Rarefied data loaded. "),
            paste0(nsamples(rarefied), " samples, ", ntaxa(rarefied), " ASVs. "),
            "Select a metric and click Run.")
      }
    })

    # ======================================================================
    # Group Variable UI
    # ======================================================================
    output$groupVariableUI <- renderUI({
      # Use raw/filtered data for the variable list (always available)
      Abundance <- physeq_data()
      req(Abundance)
      vars <- make.names(sample_variables(Abundance))
      selectInput(session$ns("groupVariable"), "Group by Sample Variable:",
                  choices = vars, selected = vars[1])
    })

    # ======================================================================
    # COLOR / FILL VARIABLE UI
    # ----------------------------------------------------------------------
    # Optional second metadata variable used for fill color. When "Same as
    # Group" is selected (default), the panel falls back to the original
    # behaviour where x-axis and fill are the same variable. Picking a
    # different variable triggers dodged boxplots so users can produce
    # the classic "diversity over time, by treatment group" view
    # (x = time, fill = condition).
    # ======================================================================
    output$colorVariableUI <- renderUI({
      Abundance <- physeq_data()
      req(Abundance)
      vars <- make.names(sample_variables(Abundance))
      selectInput(session$ns("colorVariable"),
                  "Color/Fill by (optional):",
                  choices  = c("Same as Group" = "same", vars),
                  selected = "same")
    })

    # ======================================================================
    # FACET VARIABLE UI
    # ======================================================================
    output$facetVariableUI <- renderUI({
      Abundance <- physeq_data()
      req(Abundance)
      vars <- make.names(sample_variables(Abundance))
      selectInput(session$ns("facetVariable"), "Facet by (optional):",
                  choices = c("None" = "none", vars), selected = "none")
    })

    # ======================================================================
    # CUSTOM GROUP ORDER UI
    # ======================================================================
    output$customGroupOrderUI <- renderUI({
      rarefied <- rarefied_data()
      Abundance <- physeq_data()
      pseq <- if (!is.null(rarefied)) rarefied else Abundance
      req(pseq, input$groupVariable)
      metadata <- as(sample_data(pseq), "data.frame")
      grp_col <- input$groupVariable
      if (!grp_col %in% colnames(metadata)) grp_col <- make.names(grp_col)
      if (!grp_col %in% colnames(metadata)) return(NULL)
      lvls <- sort(unique(as.character(metadata[[grp_col]])))
      selectizeInput(
        session$ns("customGroupLevelOrder"),
        "Drag to reorder groups:",
        choices = lvls,
        selected = lvls,
        multiple = TRUE,
        options = list(
          plugins = list("drag_drop", "remove_button"),
          placeholder = "Drag groups into desired order..."
        )
      )
    })

    # ======================================================================
    # GROUP COMPARISON SELECTOR
    # ======================================================================
    output$comparisonSelectorUI <- renderUI({
      # Only show when "manual" mode is selected
      mode <- if (is.null(input$comparisonMode)) "auto" else input$comparisonMode
      if (is.null(mode) || mode != "manual") return(NULL)

      rarefied <- rarefied_data()
      Abundance <- physeq_data()
      # Use whichever is available for group levels
      pseq <- if (!is.null(rarefied)) rarefied else Abundance
      req(pseq, input$groupVariable)

      metadata <- as(sample_data(pseq), "data.frame")
      grp_col <- input$groupVariable
      if (!grp_col %in% colnames(metadata)) {
        grp_col <- make.names(grp_col)
        if (!grp_col %in% colnames(metadata)) return(NULL)
      }

      group_levels <- sort(unique(as.character(metadata[[grp_col]])))
      group_levels <- group_levels[!is.na(group_levels) & nzchar(group_levels)]

      if (length(group_levels) < 2) {
        return(helpText(style = "font-size:11px; color:#e74c3c;",
                        "Need at least 2 groups for comparisons."))
      }

      # Generate all possible pairs
      all_pairs <- utils::combn(group_levels, 2, simplify = FALSE)
      pair_labels <- sapply(all_pairs, function(pr) paste(pr[1], "vs", pr[2]))
      pair_values <- sapply(all_pairs, function(pr) paste(pr, collapse = "::"))
      names(pair_values) <- pair_labels

      tagList(
        selectizeInput(session$ns("selectedComparisons"),
          label = "Select comparisons to show:",
          choices  = pair_values,
          selected = NULL,
          multiple = TRUE,
          options  = list(
            placeholder = "Pick group pairs to compare...",
            plugins     = list("remove_button")
          )
        ),
        helpText(style = "font-size:11px; color:#64748B; margin-top:-4px;",
                 "Only selected pairs will have brackets and stats on the plot. ",
                 "Leave empty to show no brackets.")
      )
    })

    # ======================================================================
    # DATA PREPARATION (uses rarefied data from Rarefaction module)
    # ======================================================================
    alpha_data_prepared <- eventReactive(input$runAlphaAnalysis, {
      rarefied <- rarefied_data()
      if (is.null(rarefied)) {
        showNotification(
          "Please run Rarefaction first (Rarefaction tab) before computing alpha diversity.",
          type = "error", duration = 8)
        return(NULL)
      }
      rarefied
    })

    # ======================================================================
    # ALPHA DIVERSITY PLOT
    # ======================================================================
    finalize_richness_plot <- reactive({
      rarefied <- alpha_data_prepared()
      measure <- if (is.null(input$alphaMeasure)) "Shannon" else input$alphaMeasure
      req(rarefied, measure, input$groupVariable)

      alpha_indices <- estimate_richness(
        rarefied,
        measures = c("Observed","Chao1","ACE","Shannon","Simpson","InvSimpson")
      )
      metric <- measure
      if (!metric %in% colnames(alpha_indices)) {
        metric_cols <- intersect(metric, colnames(alpha_indices))
        req(length(metric_cols) > 0)
      }

      metadata <- as(sample_data(rarefied), "data.frame")
      metadata$SampleID <- rownames(metadata)
      alpha_df <- data.frame(SampleID = rownames(alpha_indices),
                             alpha_indices, check.names = FALSE)
      plot_df <- merge(alpha_df, metadata, by = "SampleID")

      raw_group_var <- input$groupVariable
      group_var <- if (raw_group_var %in% colnames(plot_df)) {
        raw_group_var
      } else if (make.names(raw_group_var) %in% colnames(plot_df)) {
        make.names(raw_group_var)
      } else {
        stop("Selected grouping variable not found in sample metadata.")
      }

      plot_df[[group_var]] <- as.factor(as.character(plot_df[[group_var]]))
      plot_df$.y <- as.numeric(plot_df[[metric]])
      plot_df <- plot_df[is.finite(plot_df$.y), , drop = FALSE]
      req(nrow(plot_df) > 0)

      # --- X-axis group reordering ---
      grp_order <- if (is.null(input$groupOrder)) "default" else input$groupOrder
      if (grp_order == "alpha") {
        lvls <- sort(levels(plot_df[[group_var]]))
        plot_df[[group_var]] <- factor(plot_df[[group_var]], levels = lvls)
      } else if (grp_order == "median") {
        med_vals <- tapply(plot_df$.y, plot_df[[group_var]], median, na.rm = TRUE)
        lvls <- names(sort(med_vals, decreasing = TRUE))
        plot_df[[group_var]] <- factor(plot_df[[group_var]], levels = lvls)
      } else if (grp_order == "custom" && !is.null(input$customGroupLevelOrder)) {
        custom_lvls <- input$customGroupLevelOrder
        all_lvls <- unique(as.character(plot_df[[group_var]]))
        lvls <- c(custom_lvls, setdiff(all_lvls, custom_lvls))
        plot_df[[group_var]] <- factor(plot_df[[group_var]], levels = lvls)
      }

      group_levels <- levels(plot_df[[group_var]])
      group_count  <- length(group_levels)

      # ----------------------------------------------------------------
      # Color/fill variable resolution.
      # If the user picked "Same as Group" (default) or didn't pick at
      # all, fill = group_var (one box per x-axis tick, the legacy view).
      # If they picked a different variable, that variable becomes the
      # fill aesthetic and the boxplot is dodged within each x-axis
      # tick -- producing the x = time, fill = condition layout.
      # ----------------------------------------------------------------
      raw_color_var <- if (is.null(input$colorVariable)) "same" else input$colorVariable
      use_separate_color <- !is.null(raw_color_var) &&
                            nzchar(raw_color_var) &&
                            raw_color_var != "same" &&
                            raw_color_var != raw_group_var
      if (use_separate_color) {
        color_var <- if (raw_color_var %in% colnames(plot_df)) {
          raw_color_var
        } else if (make.names(raw_color_var) %in% colnames(plot_df)) {
          make.names(raw_color_var)
        } else {
          NULL
        }
        if (is.null(color_var)) use_separate_color <- FALSE
      }
      if (!use_separate_color) color_var <- group_var

      # Force factor so palette draws correctly regardless of input type.
      plot_df[[color_var]] <- as.factor(as.character(plot_df[[color_var]]))
      color_levels <- levels(plot_df[[color_var]])
      color_count  <- length(color_levels)

      # Colour palette -- sized to whichever variable drives the fill
      # (color_var when separate, otherwise group_var).
      palette <- if (is.null(input$colorPalette)) "Paired" else input$colorPalette
      if (palette == "Viridis") {
        color_scale <- scale_fill_viridis_d()
      } else {
        max_colors <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
        palette_colors <- if (color_count <= max_colors) {
          RColorBrewer::brewer.pal(max(color_count, 3), palette)[seq_len(color_count)]
        } else {
          colorRampPalette(
            RColorBrewer::brewer.pal(max_colors, palette)
          )(color_count)
        }
        color_scale <- scale_fill_manual(values = palette_colors)
      }

      y_label <- if (is.null(input$customYLabel) || !nzchar(input$customYLabel)) {
        paste0(metric, " diversity")
      } else {
        input$customYLabel
      }

      box_width <- if (is.null(input$boxplotWidth)) 0.7 else input$boxplotWidth
      jitter_sz <- if (is.null(input$jitterSize)) 1.5 else input$jitterSize
      base_size <- if (is.null(input$baseFontSize)) 14 else input$baseFontSize
      x_ang <- if (is.null(input$xAngle)) 45 else input$xAngle
      ax_size <- if (is.null(input$axisLabelSize)) 12 else input$axisLabelSize
      leg_pos <- if (is.null(input$legendPosition)) "right" else input$legendPosition

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes). User-supplied plot title overrides the
      # auto-generated "Shannon diversity by Treatment" default.
      # Default legend label is the COLOR variable's name when it
      # differs from the group variable -- so legend title reads
      # "condition" instead of "time" in the dodged-boxplot view.
      raw_legend_default <- if (use_separate_color) raw_color_var else raw_group_var
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = raw_legend_default,
                                   base_size = base_size)
      auto_title <- if (use_separate_color) {
        paste0(metric, " diversity by ", raw_group_var,
               " (coloured by ", raw_color_var, ")")
      } else {
        paste0(metric, " diversity by ", raw_group_var)
      }
      title_text <- if (is.null(styles$title)) auto_title else styles$title
      fill_label <- if (is.null(styles$legend_title)) raw_legend_default else styles$legend_title

      # When color_var differs from group_var, dodge boxplots & jitter
      # so each colored box sits side-by-side within an x-axis tick.
      box_pos <- if (use_separate_color) {
        position_dodge(width = 0.85)
      } else {
        "identity"
      }
      jitter_pos <- if (use_separate_color) {
        position_jitterdodge(jitter.width = 0.15, dodge.width = 0.85)
      } else {
        position_jitter(width = 0.2)
      }

      p <- ggplot(plot_df, aes(x = .data[[group_var]], y = .y,
                               fill = .data[[color_var]])) +
        geom_boxplot(outlier.shape = NA, width = box_width,
                     position = box_pos) +
        geom_jitter(size = jitter_sz, alpha = 0.85,
                    shape = 21, color = "black",
                    position = jitter_pos) +
        styles$theme_fn(base_size = base_size) +
        styles$grid_theme +
        theme(
          axis.text.x = element_text(angle = x_ang, hjust = 1,
                                     size = ax_size),
          axis.text.y = element_text(size = ax_size),
          legend.position = leg_pos
        ) +
        color_scale +
        labs(
          title = title_text,
          x     = if (is.null(input$customXLabel)) "" else input$customXLabel,
          y     = y_label,
          fill  = fill_label
        )

      # Sig-only pairwise brackets
      alpha_cutoff <- if (is.null(input$sigAlpha) || !is.finite(input$sigAlpha)) 0.05 else input$sigAlpha
      grp_formula <- stats::reformulate(termlabels = paste0("`", group_var, "`"),
                                        response    = ".y")
      show_brackets <- if (is.null(input$showSigBrackets)) FALSE else input$showSigBrackets

      if (isTRUE(show_brackets) && group_count >= 2 &&
          requireNamespace("ggsignif", quietly = TRUE)) {

        # Determine which pairs to test based on comparison mode
        comp_mode <- if (is.null(input$comparisonMode)) "auto" else input$comparisonMode
        if (comp_mode == "manual") {
          # Manual mode: only test user-selected pairs
          sel <- input$selectedComparisons
          if (is.null(sel) || length(sel) == 0) {
            pairs <- list()  # no comparisons selected
          } else {
            pairs <- lapply(sel, function(s) strsplit(s, "::", fixed = TRUE)[[1]])
            # Validate that both groups exist in the data
            pairs <- Filter(function(pr) all(pr %in% group_levels), pairs)
          }
        } else {
          # Auto mode: all pairwise
          pairs <- utils::combn(group_levels, 2, simplify = FALSE)
        }

        if (length(pairs) > 0) {
          pvals <- vapply(pairs, function(pr) {
            sub_df <- plot_df[plot_df[[group_var]] %in% pr, , drop = FALSE]
            if (length(unique(sub_df[[group_var]])) < 2) return(NA_real_)
            tryCatch(
              stats::wilcox.test(grp_formula, data = sub_df, exact = FALSE)$p.value,
              error = function(e) NA_real_
            )
          }, numeric(1))

          sig_idx <- which(is.finite(pvals) & pvals < alpha_cutoff)
          if (length(sig_idx) > 0) {
            sig_pairs  <- pairs[sig_idx]
            sig_labels <- ifelse(pvals[sig_idx] < 0.001,
                                 "p < 0.001",
                                 paste0("p = ", formatC(pvals[sig_idx], format = "f", digits = 3)))
            p <- p + ggsignif::geom_signif(
              comparisons = sig_pairs,
              annotations = sig_labels,
              step_increase = 0.09,
              tip_length    = 0.01,
              textsize      = 3.4,
              vjust         = 0
            )
          }
        }
      }

      # Global p-value -- now matches the auto-selected test in the
      # Stats panel so the plot subtitle and the printed statistics
      # never disagree. Decision tree:
      #   2 groups, normal + homog       -> t-test
      #   2 groups, normal + heterosc    -> Welch's t-test
      #   2 groups, not normal           -> Wilcoxon
      #   3+ groups, normal + homog      -> ANOVA
      #   3+ groups, normal + heterosc   -> Welch's ANOVA
      #   3+ groups, not normal          -> Kruskal-Wallis
      # Earlier versions hard-coded Wilcoxon/KW for the subtitle even
      # when ANOVA was running in the Stats panel, which produced
      # contradictory p-values in the plot vs the printed output.
      if (isTRUE(input$showGlobalP) && group_count >= 2) {
        # Reuse the same data the Stats panel uses for assumption checks.
        # plot_df has columns (group_var, .y); we project to (Group, value)
        # so the helper calls below match standard column names.
        adata <- data.frame(
            Group = factor(plot_df[[group_var]]),
            value = as.numeric(plot_df$.y)
        )
        adata <- adata[is.finite(adata$value) & !is.na(adata$Group), , drop = FALSE]

        n_total_p <- nrow(adata)
        sw_p <- tryCatch({
          if (n_total_p < 3 || n_total_p > 5000) 0
          else shapiro.test(adata$value)$p.value
        }, error = function(e) 0)
        lev_p <- tryCatch({
          car::leveneTest(value ~ Group, adata)$`Pr(>F)`[1]
        }, error = function(e) 0)
        if (is.na(lev_p)) lev_p <- 0

        global_p <- NA_real_
        sub_test_name <- ""
        tryCatch({
          if (group_count == 2) {
            if (sw_p < 0.05) {
              global_p      <- stats::wilcox.test(grp_formula, data = plot_df,
                                                  exact = FALSE)$p.value
              sub_test_name <- "Wilcoxon"
            } else if (lev_p < 0.05) {
              global_p      <- stats::t.test(grp_formula, data = plot_df,
                                             var.equal = FALSE)$p.value
              sub_test_name <- "Welch's t-test"
            } else {
              global_p      <- stats::t.test(grp_formula, data = plot_df,
                                             var.equal = TRUE)$p.value
              sub_test_name <- "t-test"
            }
          } else {
            if (sw_p < 0.05) {
              global_p      <- stats::kruskal.test(grp_formula, data = plot_df)$p.value
              sub_test_name <- "Kruskal-Wallis"
            } else if (lev_p < 0.05) {
              global_p      <- stats::oneway.test(grp_formula, data = plot_df,
                                                  var.equal = FALSE)$p.value
              sub_test_name <- "Welch's ANOVA"
            } else {
              fit           <- stats::aov(grp_formula, data = plot_df)
              global_p      <- summary(fit)[[1]][["Pr(>F)"]][1]
              sub_test_name <- "ANOVA"
            }
          }
        }, error = function(e) {})

        if (is.finite(global_p) && nzchar(sub_test_name)) {
          lbl <- paste0(sub_test_name, ": ",
                        ifelse(global_p < 0.001,
                               "p < 0.001",
                               paste0("p = ", formatC(global_p, format = "f", digits = 4))))
          p <- p + labs(subtitle = lbl) +
               theme(plot.subtitle = element_text(hjust = 0.5,
                                                  face  = "italic",
                                                  color = "#3B82F6"))
        }
      }

      # --- Faceting ---
      facet_var <- if (is.null(input$facetVariable)) "none" else input$facetVariable
      if (facet_var != "none" && facet_var %in% colnames(plot_df)) {
        p <- p + facet_wrap(as.formula(paste("~", facet_var)),
                            scales = "free_x")
      }

      p
    })

    output$alphaBoxplot <- renderPlot({
      p <- finalize_richness_plot()
      req(p)
      p
    })

    # ======================================================================
    # STATISTICS
    # ======================================================================
    alpha_stats_data <- reactive({
      rarefied <- alpha_data_prepared()
      req(rarefied, input$groupVariable)
      group_var <- input$groupVariable
      measure <- if (is.null(input$alphaMeasure)) "Shannon" else input$alphaMeasure
      alpha_indices <- estimate_richness(rarefied, measures = c("Observed","Chao1","ACE","Shannon","Simpson","InvSimpson"))
      metadata <- as(sample_data(rarefied), "data.frame")
      metadata$SampleID <- rownames(metadata)
      alpha_df <- cbind(SampleID = rownames(alpha_indices), alpha_indices)
      merged <- merge(alpha_df, metadata, by.x = "SampleID", by.y = "SampleID")
      selected <- merged[, c("SampleID", group_var, measure)]
      colnames(selected) <- c("SampleID","Group","value")
      selected$Group <- as.factor(as.character(selected$Group))
      selected$value <- as.numeric(as.character(selected$value))
      selected <- selected[!is.na(selected$value), ]

      # Validate sample sizes for statistical tests
      group_sizes <- table(selected$Group)
      if (any(group_sizes < 2)) {
        stop("Some groups have fewer than 2 samples. Cannot run statistical tests. ",
             "Groups: ", paste(names(group_sizes[group_sizes < 2]), collapse = ", "))
      }
      if (nrow(selected) < 3) {
        stop("Need at least 3 total samples for statistical testing. Found: ", nrow(selected))
      }
      selected
    })

    output$alphaStatsSummary <- renderPrint({
      rarefied <- rarefied_data()
      if (is.null(rarefied)) {
        cat("Run Rarefaction first (Rarefaction tab), then come back and click 'Run / Refresh Analysis'.\n")
        return(invisible(NULL))
      }
      if (is.null(input$runAlphaAnalysis) || input$runAlphaAnalysis == 0) {
        cat("Click 'Run / Refresh Analysis' to compute alpha diversity statistics.\n")
        return(invisible(NULL))
      }

      data <- tryCatch(alpha_stats_data(), error = function(e) {
        cat("Error:", e$message, "\n")
        return(NULL)
      })
      req(data)

      n_total <- nrow(data)
      n_groups <- nlevels(data$Group)

      # Step 1: Normality (guard against too few or too many samples)
      shapiro_p <- tryCatch({
        if (n_total < 3 || n_total > 5000) {
          cat("\nNote: Shapiro-Wilk requires 3-5000 samples. Using Kruskal-Wallis (non-parametric) path.\n")
          0  # Force non-parametric path
        } else {
          shapiro <- shapiro.test(data$value)
          cat("\nShapiro-Wilk Test for Normality:\n")
          cat("p-value =", shapiro$p.value, "\n")
          shapiro$p.value
        }
      }, error = function(e) {
        cat("\nShapiro-Wilk failed:", e$message, "\n")
        cat("Falling back to non-parametric tests.\n")
        0
      })

      # Step 2: Homogeneity test (informational; only deciding when
      # data is normal). Levene's test is robust to non-normality, so
      # we use it in both branches for consistency, and it is also
      # printed when data is non-normal so the user has the full
      # diagnostic, even though it does not change the test choice.
      hom_p <- NA
      cat("\nLevene's Test for homogeneity of variance:\n")
      levene <- tryCatch(car::leveneTest(value ~ Group, data),
                         error = function(e) NULL)
      if (!is.null(levene)) {
        hom_p <- levene$`Pr(>F)`[1]
        print(levene)
      } else {
        cat("Levene's test failed; assuming heteroscedastic.\n")
        hom_p <- 0
      }
      if (is.na(hom_p)) hom_p <- 0

      # Step 3: Primary test selection.
      # CORRECT decision tree (was buggy in earlier versions which
      # routed non-normal data to ANOVA whenever Levene passed --
      # ANOVA assumes BOTH normality and homogeneity):
      #
      #   not normal           -> Kruskal-Wallis  (Dunn post-hoc)
      #   normal + homogeneous -> ANOVA           (Tukey HSD)
      #   normal + heteroscedastic -> Welch's ANOVA (Games-Howell)
      if (shapiro_p < 0.05) {
        cat("\nData not normal -> Kruskal-Wallis (non-parametric)\n")
        primary <- kruskal.test(value ~ Group, data)
        print(primary)
        if (requireNamespace("FSA", quietly = TRUE)) {
          cat("\nPost-hoc Dunn Test (Bonferroni):\n")
          posthoc <- FSA::dunnTest(value ~ Group, data, method = "bonferroni")
          print(posthoc)
        }
        selected_test <- "Kruskal-Wallis"
      } else if (hom_p < 0.05) {
        cat("\nData normal but variances heteroscedastic -> Welch's ANOVA\n")
        primary <- oneway.test(value ~ Group, data, var.equal = FALSE)
        print(primary)
        if (requireNamespace("rstatix", quietly = TRUE)) {
          cat("\nPost-hoc Games-Howell:\n")
          posthoc <- tryCatch(
            rstatix::games_howell_test(data, value ~ Group),
            error = function(e) NULL)
          if (!is.null(posthoc)) print(posthoc)
        }
        selected_test <- "Welch's ANOVA"
      } else {
        cat("\nData normal AND variances homogeneous -> One-way ANOVA\n")
        primary <- aov(value ~ Group, data)
        print(summary(primary))
        cat("\nPost-hoc Tukey HSD:\n")
        tukey_res <- TukeyHSD(primary)
        print(tukey_res)
        selected_test <- "ANOVA"
      }

      # Step 3b: Selected pairwise comparisons (Wilcoxon)
      comp_mode <- if (is.null(input$comparisonMode)) "auto" else input$comparisonMode
      sel_comps <- input$selectedComparisons
      if (comp_mode == "manual" &&
          !is.null(sel_comps) && length(sel_comps) > 0) {
        cat("\n--- Selected Pairwise Comparisons (Wilcoxon) ---\n")
        sel_pairs <- lapply(sel_comps, function(s) strsplit(s, "::", fixed = TRUE)[[1]])
        for (pr in sel_pairs) {
          if (!all(pr %in% levels(data$Group))) next
          sub <- data[data$Group %in% pr, ]
          sub$Group <- droplevels(sub$Group)
          wt <- tryCatch(
            stats::wilcox.test(value ~ Group, data = sub, exact = FALSE),
            error = function(e) NULL
          )
          if (!is.null(wt)) {
            sig_marker <- ifelse(wt$p.value < 0.001, "***",
                           ifelse(wt$p.value < 0.01, "**",
                             ifelse(wt$p.value < 0.05, "*", "ns")))
            cat(sprintf("  %s vs %s:  W = %.1f,  p = %.4f  %s\n",
                        pr[1], pr[2], wt$statistic, wt$p.value, sig_marker))
          }
        }
      }

      # Summary -- reflects the corrected decision tree:
      # not-normal -> KW;  normal+heterosc -> Welch's;  normal+homog -> ANOVA.
      cat("\n------------------------------------------------------------\n")
      cat("Alpha Diversity Statistics Logic (Summary)\n")
      cat("Step 1 - Shapiro-Wilk normality: p =", round(shapiro_p, 4),
          ifelse(shapiro_p > 0.05,
                 " -> Data approximately normal.\n",
                 " -> Data deviates from normality.\n"))
      cat("Step 2 - Levene homogeneity: p =", round(hom_p, 4),
          ifelse(hom_p > 0.05,
                 " -> Variances homogeneous.\n",
                 " -> Variances heteroscedastic.\n"))
      cat("Step 3 - Primary test selected: ", selected_test, "\n", sep = "")
      cat("  Reason: ")
      if (selected_test == "Kruskal-Wallis") {
        cat("data not normal; ANOVA's parametric assumption violated, so the ",
            "non-parametric rank-based test is used regardless of the Levene ",
            "result. Post-hoc: Dunn test with Bonferroni correction.\n", sep = "")
      } else if (selected_test == "Welch's ANOVA") {
        cat("data normal but variances unequal; standard ANOVA's homogeneity ",
            "assumption is violated, so Welch's correction is applied. ",
            "Post-hoc: Games-Howell.\n", sep = "")
      } else {
        cat("data normal and variances homogeneous; both ANOVA assumptions ",
            "met. Post-hoc: Tukey HSD.\n", sep = "")
      }
      cat("------------------------------------------------------------\n")
    })

    # ======================================================================
    # DOWNLOAD PLOT
    # ======================================================================
    output$downloadAlphaPlot <- downloadHandler(
      filename = function() {
        measure <- if (is.null(input$alphaMeasure)) "Shannon" else input$alphaMeasure
        ezmap_download_filename(input, paste0("Alpha_Diversity_", measure))
      },
      content = function(file) {
        p <- finalize_richness_plot()
        req(p)
        ggplot2::ggsave(
          file, plot = p,
          width = input$downloadWidth, height = input$downloadHeight,
          units = input$downloadUnits, dpi = input$downloadDPI
        )
      }
    )
  })
}
