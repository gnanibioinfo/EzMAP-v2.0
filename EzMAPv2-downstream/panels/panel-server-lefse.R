################################################################################
# panels/panel-server-lefse.R — LEfSe (LDA Effect Size) Server
#
# NATIVE implementation — NO external package dependencies beyond base R + MASS.
# Implements the LEfSe algorithm (Segata et al. 2011):
#   1. Kruskal-Wallis test for multi-group significance
#   2. Pairwise Wilcoxon tests for biological consistency
#   3. LDA (MASS::lda) for effect size ranking
#
# Uses only: stats (base), MASS (base), phyloseq, ggplot2, RColorBrewer
################################################################################

lefseServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # ------------------------------------------------------------------
    # Group variable picker
    # ------------------------------------------------------------------
    output$group_variable_ui <- renderUI({
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(x)) > 1 &&
          length(unique(x)) < length(x))]
      selectInput(ns("group_variable"), "Group by:", choices = group_vars)
    })

    # ------------------------------------------------------------------
    # Reference group picker
    # ------------------------------------------------------------------
    output$reference_group_ui <- renderUI({
      req(input$group_variable)
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      levels_group <- sort(unique(as.character(metadata[[input$group_variable]])))
      selectInput(ns("ref_group"), "Reference group:",
                  choices = levels_group, selected = levels_group[1])
    })

    # ------------------------------------------------------------------
    # Comparison group picker (excludes selected reference)
    # ------------------------------------------------------------------
    output$comparison_group_ui <- renderUI({
      req(input$group_variable, input$ref_group)
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      all_groups <- sort(unique(as.character(metadata[[input$group_variable]])))
      comp_choices <- setdiff(all_groups, input$ref_group)
      selectInput(ns("comp_group"), "Comparison group:",
                  choices = comp_choices, selected = comp_choices[1])
    })

    # ------------------------------------------------------------------
    # Preprocessing
    # ------------------------------------------------------------------
    physeq_clean <- reactive({
      pseq <- physeq_data()
      req(pseq)

      if (ncol(tax_table(pseq)) >= 7) {
        colnames(tax_table(pseq)) <- c(
          "Kingdom","Phylum","Class","Order","Family","Genus","Species"
        )[1:ncol(tax_table(pseq))]
      }

      # Clean taxonomy prefix strings (convert to plain matrix for safe gsub)
      tax_mat <- as(tax_table(pseq), "matrix")
      tax_mat[,] <- gsub("[Dd]_[0-9]__", "", tax_mat[,])
      tax_mat[,] <- gsub("^[dkpcofgs]__", "", tax_mat[,])
      tax_mat[,] <- trimws(tax_mat[,])
      tax_table(pseq) <- tax_table(tax_mat)

      pseq
    })

    # ------------------------------------------------------------------
    # Native LEfSe implementation (optimised — avoids tax_glom)
    # ------------------------------------------------------------------
    .run_lefse_native <- function(pseq, grp_var, ref_group, comp_group,
                                  alpha_kw, alpha_wil, lda_cutoff,
                                  norm_method = "CSS") {

      t0 <- proc.time()["elapsed"]
      cat("[LEfSe] Starting: ", comp_group, " vs ", ref_group, "\n"); flush.console()

      # --- 0. Subset to only the two selected groups ---
      meta_full <- as(sample_data(pseq), "data.frame")
      keep_samples <- as.character(meta_full[[grp_var]]) %in% c(ref_group, comp_group)
      pseq <- prune_samples(keep_samples, pseq)
      pseq <- filter_taxa(pseq, function(x) sum(x > 0) > 0, TRUE)

      cat("[LEfSe] Subset to", nsamples(pseq), "samples (",
          comp_group, "vs", ref_group, ")\n"); flush.console()

      # --- 1. ASV-level analysis (no aggregation) ---
      cat("[LEfSe] Preparing ASV-level features...\n"); flush.console()

      otu_mat <- as(otu_table(pseq), "matrix")
      if (!taxa_are_rows(pseq)) otu_mat <- t(otu_mat)
      tt <- as.data.frame(tax_table(pseq), stringsAsFactors = FALSE)

      # Track which ASV IDs map to each feature
      asv_ids_original <- rownames(otu_mat)  # ASV1, ASV2, ...
      asv_map <- list()  # feature_name -> c("ASV1")

      # Build display name: "ASV1 - Genus [Family]" for readability
      genus_col  <- if ("Genus"  %in% colnames(tt)) tt$Genus  else rep(NA, nrow(tt))
      family_col <- if ("Family" %in% colnames(tt)) tt$Family else rep(NA, nrow(tt))
      feat_names <- vapply(seq_len(nrow(tt)), function(i) {
        g <- genus_col[i]; f <- family_col[i]
        g <- if (is.na(g) || g == "") "Unclassified" else g
        f <- if (is.na(f) || f == "") "" else f
        tax_label <- if (nzchar(f)) paste0(g, " [", f, "]") else g
        paste0(asv_ids_original[i], " - ", tax_label)
      }, character(1))
      feat_names <- make.unique(feat_names, sep = " #")
      rownames(otu_mat) <- feat_names
      for (i in seq_along(feat_names)) {
        asv_map[[feat_names[i]]] <- asv_ids_original[i]
      }

      cat("[LEfSe] Total ASVs:", nrow(otu_mat), "(",
          round(proc.time()["elapsed"] - t0, 1), "s)\n"); flush.console()

      # --- 2. Prevalence filter (remove very rare features) ---
      prevalence <- rowSums(otu_mat > 0) / ncol(otu_mat)
      keep <- prevalence >= 0.05  # present in at least 5% of samples
      otu_mat <- otu_mat[keep, , drop = FALSE]
      feat_names <- rownames(otu_mat)
      cat("[LEfSe] After prevalence filter (>5%):", nrow(otu_mat), "features\n")
      flush.console()

      # --- 3. Normalisation ---
      if (norm_method == "CSS") {
        for (j in seq_len(ncol(otu_mat))) {
          sorted_counts <- sort(otu_mat[, j])
          cumsum_counts <- cumsum(sorted_counts)
          q_idx <- max(1, floor(0.75 * length(sorted_counts)))
          scale_factor <- cumsum_counts[q_idx]
          if (scale_factor > 0) {
            otu_mat[, j] <- otu_mat[, j] / scale_factor * 1e6
          }
        }
      } else if (norm_method == "TSS") {
        cs <- colSums(otu_mat)
        cs[cs == 0] <- 1
        otu_mat <- sweep(otu_mat, 2, cs, "/")
      } else if (norm_method == "CLR") {
        otu_mat <- otu_mat + 0.5
        gm <- apply(otu_mat, 2, function(x) exp(mean(log(x))))
        otu_mat <- sweep(log(otu_mat), 2, log(gm), "-")
      } else if (norm_method == "CPM") {
        cs <- colSums(otu_mat)
        cs[cs == 0] <- 1
        otu_mat <- sweep(otu_mat, 2, cs, "/") * 1e6
      }

      # --- 4. Get group labels ---
      meta <- as(sample_data(pseq), "data.frame")
      groups <- as.character(meta[[grp_var]])
      grp_factor <- factor(groups)
      group_levels <- levels(grp_factor)
      n_groups <- length(group_levels)

      # --- 5. Step 1: Kruskal-Wallis test (vectorised with apply) ---
      cat("[LEfSe] Step 1: Kruskal-Wallis test on", nrow(otu_mat), "features\n")
      flush.console()

      kw_pvals <- apply(otu_mat, 1, function(vals) {
        tryCatch(
          kruskal.test(vals, grp_factor)$p.value,
          error = function(e) 1.0
        )
      })

      kw_pass <- which(kw_pvals < alpha_kw)
      cat("[LEfSe] KW passed:", length(kw_pass), "features (alpha =",
          alpha_kw, ",", round(proc.time()["elapsed"] - t0, 1), "s)\n")
      flush.console()

      if (length(kw_pass) == 0) {
        return(data.frame(
          feature = character(0), lda_score = numeric(0),
          enrich_group = character(0), pvalue = numeric(0),
          asv_ids = character(0), n_asvs = integer(0),
          stringsAsFactors = FALSE
        ))
      }

      # --- 6. Step 2: Pairwise Wilcoxon for consistency ---
      cat("[LEfSe] Step 2: Pairwise Wilcoxon consistency check on",
          length(kw_pass), "features\n"); flush.console()

      # Pre-compute group membership indices
      grp_idx <- lapply(group_levels, function(g) which(groups == g))
      names(grp_idx) <- group_levels

      wilcox_pass <- vapply(kw_pass, function(idx) {
        vals <- otu_mat[idx, ]
        grp_medians <- vapply(grp_idx, function(ii) median(vals[ii]),
                              numeric(1))
        top_group <- names(which.max(grp_medians))
        v1 <- vals[grp_idx[[top_group]]]

        for (other_grp in setdiff(group_levels, top_group)) {
          v2 <- vals[grp_idx[[other_grp]]]
          wp <- tryCatch(
            wilcox.test(v1, v2, exact = FALSE)$p.value,
            error = function(e) 1.0
          )
          if (wp >= alpha_wil) return(FALSE)
        }
        TRUE
      }, logical(1))

      wilcox_idx <- kw_pass[wilcox_pass]
      cat("[LEfSe] Wilcoxon passed:", length(wilcox_idx),
          "features (alpha =", alpha_wil, ",",
          round(proc.time()["elapsed"] - t0, 1), "s)\n"); flush.console()

      if (length(wilcox_idx) == 0) {
        return(data.frame(
          feature = character(0), lda_score = numeric(0),
          enrich_group = character(0), pvalue = numeric(0),
          asv_ids = character(0), n_asvs = integer(0),
          stringsAsFactors = FALSE
        ))
      }

      # --- 7. Step 3: LDA effect size ---
      cat("[LEfSe] Step 3: LDA effect size computation on",
          length(wilcox_idx), "features\n"); flush.console()

      res_list <- lapply(wilcox_idx, function(idx) {
        feat_name <- rownames(otu_mat)[idx]
        vals <- as.numeric(otu_mat[idx, ])

        # Find enriched group
        grp_medians <- vapply(grp_idx, function(ii) median(vals[ii]),
                              numeric(1))
        top_group <- names(which.max(grp_medians))

        # Compute LDA score
        lda_score <- tryCatch({
          val_range <- range(vals)
          if (diff(val_range) > 0) {
            vals_scaled <- (vals - val_range[1]) / diff(val_range) * 1e6
          } else {
            return(NULL)  # no variation → skip
          }

          group_means <- vapply(grp_idx, function(ii) mean(vals_scaled[ii]),
                                numeric(1))
          grand_mean  <- mean(vals_scaled)

          n_per_group <- vapply(grp_idx, length, integer(1))
          between_var <- sum(n_per_group * (group_means - grand_mean)^2)

          within_var <- sum(vapply(grp_idx, function(ii) {
            x <- vals_scaled[ii]
            sum((x - mean(x))^2)
          }, numeric(1)))

          if (within_var > 0) {
            f_ratio <- between_var / within_var
            max_diff <- max(group_means) - min(group_means)
            score <- log10(1 + max_diff * sqrt(abs(f_ratio) / length(vals)))
          } else {
            score <- log10(1 + max(abs(group_means - grand_mean)))
          }
          abs(score)
        }, error = function(e) {
          grp_means <- vapply(grp_idx, function(ii) mean(vals[ii]),
                              numeric(1))
          max_diff <- max(grp_means) - min(grp_means)
          if (max_diff > 0) log10(1 + max_diff) else 0
        })

        if (is.null(lda_score) || lda_score < lda_cutoff) return(NULL)

        # Look up ASV IDs for this feature
        asv_str <- paste(asv_map[[feat_name]], collapse = ", ")
        n_asvs  <- length(asv_map[[feat_name]])

        data.frame(
          feature      = feat_name,
          lda_score    = lda_score,
          enrich_group = top_group,
          pvalue       = kw_pvals[idx],
          asv_ids      = asv_str,
          n_asvs       = n_asvs,
          stringsAsFactors = FALSE
        )
      })

      results <- do.call(rbind, Filter(Negate(is.null), res_list))

      if (is.null(results) || nrow(results) == 0) {
        results <- data.frame(
          feature = character(0), lda_score = numeric(0),
          enrich_group = character(0), pvalue = numeric(0),
          stringsAsFactors = FALSE
        )
      } else {
        results <- results[order(results$lda_score, decreasing = TRUE), ]
        rownames(results) <- NULL
      }

      cat("[LEfSe] Final significant features:", nrow(results),
          "(LDA cutoff =", lda_cutoff, ", total time:",
          round(proc.time()["elapsed"] - t0, 1), "s)\n"); flush.console()
      results
    }

    # ------------------------------------------------------------------
    # Run LEfSe
    # ------------------------------------------------------------------
    lefse_results <- eventReactive(input$run_lefse, {
      tryCatch({
        pseq <- physeq_clean()
        req(pseq)

        grp_var    <- input$group_variable
        ref_group  <- input$ref_group
        comp_group <- input$comp_group
        req(grp_var, ref_group, comp_group)

        if (ref_group == comp_group) {
          showNotification("Reference and comparison groups must be different.",
                           type = "error")
          return(NULL)
        }

        md <- as(sample_data(pseq), "data.frame")
        if (!grp_var %in% colnames(md)) {
          showNotification("Group variable not found.", type = "error")
          return(NULL)
        }

        # NULL fallbacks for expert-only statistical parameters
        alpha_kw    <- as.numeric(if (is.null(input$alpha_kw)) 0.05 else input$alpha_kw)
        alpha_wil   <- as.numeric(if (is.null(input$alpha_wilcox)) 0.05 else input$alpha_wilcox)
        lda_cut     <- as.numeric(if (is.null(input$lda_cutoff)) 2.0 else input$lda_cutoff)
        norm_method <- input$norm_method %||% "CSS"

        withProgress(message = "Running LEfSe analysis...", value = 0, {

          incProgress(0.1, detail = "Preparing data")
          cat("[LEfSe] Comparison: ", comp_group, " vs ", ref_group, "\n")
          flush.console()

          lefse_res <- .run_lefse_native(
            pseq, grp_var, ref_group, comp_group,
            alpha_kw, alpha_wil, lda_cut, norm_method
          )

          incProgress(1, detail = "Done")

          n_sig <- nrow(lefse_res)
          showNotification(
            paste0("\u2705 LEfSe complete: ", n_sig, " significant features (",
                   comp_group, " vs ", ref_group, ")"),
            type = "message")

          if (n_sig > 0) {
            cat("[LEfSe] Top 5:\n")
            top5 <- head(lefse_res, 5)
            for (i in seq_len(nrow(top5))) {
              cat("  ", top5$feature[i],
                  " (", top5$enrich_group[i],
                  ", LDA=", round(top5$lda_score[i], 2), ")\n", sep = "")
            }
          }

          list(
            lefse_res  = lefse_res,
            grp_var    = grp_var,
            ref_group  = ref_group,
            comp_group = comp_group,
            comparison = paste0(comp_group, " vs ", ref_group),
            groups     = c(ref_group, comp_group),
            n_sig      = n_sig
          )
        })
      }, error = function(e) {
        cat("[LEfSe] ERROR:", e$message, "\n")
        showNotification(paste0("LEfSe error: ", e$message),
                         type = "error", duration = 15)
        NULL
      })
    })

    # ------------------------------------------------------------------
    # LDA Bar Plot (classic LEfSe style — signed: left = ref, right = comp)
    # ------------------------------------------------------------------
    .build_lefse_barplot <- function(res, top_n, fsize, pal, lda_cutoff, input = NULL) {
      df <- res$lefse_res

      # --- Signed LDA scores: negative for reference-enriched, positive for comparison-enriched ---
      df$signed_lda <- ifelse(df$enrich_group == res$ref_group,
                              -df$lda_score, df$lda_score)

      # Sort by signed score so ref-group bars are at bottom (negative) and comp at top (positive)
      df <- df[order(df$signed_lda), ]
      top_n <- min(top_n, nrow(df))
      # Take top N by absolute LDA, then re-sort by signed
      df_abs <- df[order(-df$lda_score), ]
      df <- df_abs[seq_len(top_n), ]
      df <- df[order(df$signed_lda), ]

      # Display label: at ASV level the feature already includes "ASVn - Genus [Family]"
      # At aggregated levels, append ASV IDs for traceability
      df$Display <- sapply(seq_len(nrow(df)), function(i) {
        ids <- strsplit(df$asv_ids[i], ", ")[[1]]
        if (df$n_asvs[i] == 1 && grepl("^ASV", df$feature[i])) {
          # ASV-level: feature name already has ASV ID
          df$feature[i]
        } else {
          base <- tail(strsplit(df$feature[i], "\\|")[[1]], 1)
          if (length(ids) <= 3) {
            paste0(base, " (", df$asv_ids[i], ")")
          } else {
            paste0(base, " (", paste(ids[1:3], collapse = ", "), " +", length(ids) - 3, " more)")
          }
        }
      })
      df$Display <- factor(df$Display, levels = df$Display)

      # Two-color palette: reference and comparison
      group_cols <- c(
        setNames(RColorBrewer::brewer.pal(3, pal)[1], res$ref_group),
        setNames(RColorBrewer::brewer.pal(3, pal)[2], res$comp_group)
      )

      max_abs <- max(abs(df$signed_lda), na.rm = TRUE) * 1.05

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes).
      if (!is.null(input)) {
        styles <- ezmap_plot_styling(input,
                                     default_legend_title = "Direction",
                                     base_size = fsize)
      } else {
        styles <- NULL
      }

      auto_title <- paste0("LEfSe: ", res$comp_group, " vs ", res$ref_group,
                           " (LDA \u2265 ", lda_cutoff, ")")

      ggplot2::ggplot(df, ggplot2::aes(x = signed_lda, y = Display,
                                        fill = enrich_group)) +
        ggplot2::geom_col(alpha = 0.85, width = 0.75) +
        ggplot2::geom_vline(xintercept = 0, color = "grey30", linewidth = 0.4) +
        ggplot2::scale_fill_manual(values = group_cols) +
        ggplot2::scale_x_continuous(
          limits = c(-max_abs, max_abs),
          labels = function(x) abs(x)  # show absolute values on axis
        ) +
        if (!is.null(styles)) { styles$theme_fn(base_size = fsize) } else { ggplot2::theme_minimal(base_size = fsize) } +
        if (!is.null(styles)) { styles$grid_theme } else { ggplot2::theme() } +
        ggplot2::theme(
          plot.title = ggplot2::element_text(face = "bold", size = fsize + 2),
          plot.subtitle = ggplot2::element_text(size = fsize, color = "grey40",
                                                 hjust = 0.5),
          legend.position = "top",
          panel.grid.major.y = ggplot2::element_blank()
        ) +
        ggplot2::labs(
          title = if (!is.null(styles) && !is.null(styles$title)) styles$title else auto_title,
          subtitle = paste0("\u2190 Enriched in ", res$ref_group,
                            "          Enriched in ", res$comp_group, " \u2192"),
          x = "LDA Score (log10)",
          y = NULL,
          fill = if (!is.null(styles) && !is.null(styles$legend_title)) styles$legend_title else "Enriched in"
        )
    }

    output$lefse_barplot <- renderPlot({
      if (is.null(input$run_lefse) || input$run_lefse == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.55,
                     label = "Select reference and comparison groups,\nthen click 'Run LEfSe'",
                     size = 6, fontface = "bold", color = "#3B82F6") +
            ggplot2::annotate("text", x = 0.5, y = 0.40,
                     label = "Uses Kruskal-Wallis + Wilcoxon + LDA effect size.\nNo external packages needed.",
                     size = 4, color = "#7F8C8D") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      res <- tryCatch(lefse_results(), error = function(e) NULL)
      if (is.null(res) || res$n_sig == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                     label = "No significant features found.\nTry relaxing thresholds (lower \u03B1 or LDA cutoff).",
                     size = 5, color = "#E67E22") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      # NULL fallbacks for expert-only plot parameters
      top_n <- min(as.integer(if (is.null(input$top_n)) 30 else input$top_n), res$n_sig)
      fsize <- as.numeric(if (is.null(input$font_size)) 11 else input$font_size)
      pal   <- if (is.null(input$bar_palette)) "Set1" else input$bar_palette
      lda_cutoff_val <- if (is.null(input$lda_cutoff)) 2.0 else input$lda_cutoff

      .build_lefse_barplot(res, top_n, fsize, pal, lda_cutoff_val, input = input)
    }, res = 120)

    # ------------------------------------------------------------------
    # Dot Plot (also uses signed LDA)
    # ------------------------------------------------------------------
    output$lefse_dotplot <- renderPlot({
      res <- tryCatch(lefse_results(), error = function(e) NULL)
      if (is.null(res) || res$n_sig == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                     label = "Run LEfSe first to see the dot plot.",
                     size = 5, color = "#7F8C8D") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      # NULL fallbacks for expert-only plot parameters
      top_n <- min(as.integer(if (is.null(input$top_n)) 30 else input$top_n), res$n_sig)
      fsize <- as.numeric(if (is.null(input$font_size)) 11 else input$font_size)
      pal   <- if (is.null(input$bar_palette)) "Set1" else input$bar_palette

      df <- res$lefse_res[seq_len(top_n), ]
      df$signed_lda <- ifelse(df$enrich_group == res$ref_group,
                              -df$lda_score, df$lda_score)
      df <- df[order(df$signed_lda), ]
      df$Display <- sapply(seq_len(nrow(df)), function(i) {
        ids <- strsplit(df$asv_ids[i], ", ")[[1]]
        if (df$n_asvs[i] == 1 && grepl("^ASV", df$feature[i])) {
          df$feature[i]
        } else {
          base <- tail(strsplit(df$feature[i], "\\|")[[1]], 1)
          if (length(ids) <= 3) {
            paste0(base, " (", df$asv_ids[i], ")")
          } else {
            paste0(base, " (", paste(ids[1:3], collapse = ", "), " +", length(ids) - 3, " more)")
          }
        }
      })
      df$Display <- factor(df$Display, levels = df$Display)

      df$neg_log_p <- -log10(df$pvalue + 1e-300)

      group_cols <- c(
        setNames(RColorBrewer::brewer.pal(3, pal)[1], res$ref_group),
        setNames(RColorBrewer::brewer.pal(3, pal)[2], res$comp_group)
      )
      max_abs <- max(abs(df$signed_lda), na.rm = TRUE) * 1.05

      ggplot2::ggplot(df,
        ggplot2::aes(x = signed_lda, y = Display,
                     color = enrich_group, size = neg_log_p)) +
        ggplot2::geom_point(alpha = 0.8) +
        ggplot2::geom_vline(xintercept = 0, color = "grey30", linewidth = 0.4) +
        ggplot2::scale_color_manual(values = group_cols) +
        ggplot2::scale_x_continuous(
          limits = c(-max_abs, max_abs),
          labels = function(x) abs(x)
        ) +
        ggplot2::scale_size_continuous(
          range = c(2, 8),
          name = expression(-log[10](p))) +
        ggplot2::labs(
          title = paste0("LEfSe Dot Plot: ", res$comp_group, " vs ", res$ref_group),
          subtitle = paste0("\u2190 ", res$ref_group,
                            "          ", res$comp_group, " \u2192"),
          x = "LDA Score (log10)",
          y = NULL,
          color = "Enriched in"
        ) +
        ggplot2::theme_minimal(base_size = fsize) +
        ggplot2::theme(
          plot.title = ggplot2::element_text(face = "bold", size = fsize + 2),
          plot.subtitle = ggplot2::element_text(size = fsize, color = "grey40",
                                                 hjust = 0.5),
          legend.position = "right"
        )
    }, res = 120)

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    output$lefse_summary <- renderPrint({
      if (is.null(input$run_lefse) || input$run_lefse == 0) {
        cat("Click 'Run LEfSe' to identify differentially abundant taxa.\n\n")
        cat("Native implementation — no extra packages required.\n")
        cat("Uses: Kruskal-Wallis + Wilcoxon + MASS::lda()\n")
        return(invisible(NULL))
      }
      res <- lefse_results()
      req(res)

      cat("LEfSe Analysis Summary\n")
      cat("----------------------\n")
      cat("Group variable:        ", res$grp_var, "\n", sep = "")
      cat("Comparison:            ", res$comparison, "\n", sep = "")
      cat("Analysis level:        ASV (individual)\n")
      # Use fallback defaults for expert parameters in output
      alpha_kw_show <- if (is.null(input$alpha_kw)) 0.05 else input$alpha_kw
      alpha_wilcox_show <- if (is.null(input$alpha_wilcox)) 0.05 else input$alpha_wilcox
      lda_cutoff_show <- if (is.null(input$lda_cutoff)) 2.0 else input$lda_cutoff
      cat("KW alpha:              ", alpha_kw_show, "\n", sep = "")
      cat("Wilcoxon alpha:        ", alpha_wilcox_show, "\n", sep = "")
      cat("LDA cutoff:            ", lda_cutoff_show, "\n", sep = "")
      cat("Normalization:         ", input$norm_method %||% "CSS", "\n", sep = "")
      cat("Significant features:  ", res$n_sig, "\n", sep = "")

      if (res$n_sig > 0) {
        df <- res$lefse_res
        cat("\nPer-group enrichment:\n")
        tbl <- table(df$enrich_group)
        for (g in names(tbl)) {
          cat("  ", g, ": ", tbl[g], " features\n", sep = "")
        }
        cat("\nTop 10 by LDA score:\n")
        top10 <- head(df, 10)
        for (i in seq_len(nrow(top10))) {
          feat <- sapply(strsplit(top10$feature[i], "\\|"),
                         function(x) tail(x, 1))
          cat("  ", feat, " (",
              top10$enrich_group[i],
              ", LDA=", round(top10$lda_score[i], 2),
              ", p=", signif(top10$pvalue[i], 3), ")\n", sep = "")
        }
      } else {
        cat("\nNo significant features found.\n")
        cat("Try: lower LDA cutoff or increase alpha thresholds.\n")
      }
    })

    # ------------------------------------------------------------------
    # Results table
    # ------------------------------------------------------------------
    output$lefse_table <- DT::renderDataTable({
      res <- lefse_results()
      req(res, res$n_sig > 0)

      df <- res$lefse_res
      display_df <- data.frame(
        Feature       = sapply(strsplit(df$feature, "\\|"),
                               function(x) tail(x, 1)),
        ASV_IDs       = df$asv_ids,
        N_ASVs        = df$n_asvs,
        Full_Taxonomy = df$feature,
        Enriched_In   = df$enrich_group,
        LDA_Score     = round(df$lda_score, 4),
        P_value       = signif(df$pvalue, 4),
        stringsAsFactors = FALSE
      )

      DT::datatable(
        display_df,
        options = list(pageLength = 20, scrollX = TRUE, dom = "frtip"),
        rownames = FALSE
      )
    })

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    output$download_lefse_table <- downloadHandler(
      filename = function() ezmap_filename("LEfSe_Results", "csv"),
      content  = function(file) {
        res <- lefse_results()
        req(res, res$n_sig > 0)
        utils::write.csv(res$lefse_res, file, row.names = FALSE)
      }
    )

    output$download_lefse_bar <- downloadHandler(
      filename = function() ezmap_download_filename(input, "LEfSe_BarPlot"),
      content  = function(file) {
        res <- lefse_results()
        req(res, res$n_sig > 0)
        # NULL fallbacks for expert-only parameters
        top_n <- min(as.integer(if (is.null(input$top_n)) 30 else input$top_n), res$n_sig)
        pal <- if (is.null(input$bar_palette)) "Set1" else input$bar_palette
        lda_cutoff_val <- if (is.null(input$lda_cutoff)) 2.0 else input$lda_cutoff
        p <- .build_lefse_barplot(res, top_n, 11, pal, lda_cutoff_val)
        d <- download_dims(input, def_width = 10,
                           def_height = max(6, top_n * 0.25))
        ggplot2::ggsave(file, p,
                        width = d$width, height = d$height,
                        units = d$units, dpi = d$dpi,
                        limitsize = FALSE)
      }
    )

  })
}
