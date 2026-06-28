################################################################################
# panels/panel-server-ancombc.R — ANCOM-BC Server Logic
#
# NATIVE implementation — NO external package dependencies beyond base R.
#
# Implements the ANCOM-BC approach (Lin & Peddada 2020):
#   1. Log-transform counts (with pseudo-count)
#   2. Estimate per-sample sampling fraction bias
#   3. Bias-corrected per-taxon linear models (two-group comparison)
#   4. FDR-corrected p-values
#
# Uses: stats (base), phyloseq, ggplot2
################################################################################

ancombcServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

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

      # Convert to plain matrix for safe gsub — strip ALL known prefix formats
      # (defensive — the central upload step also does this)
      tax_mat <- as(tax_table(pseq), "matrix")
      tax_mat[,] <- gsub("[Dd]_[0-9]+__", "", tax_mat[,])
      tax_mat[,] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_mat[,])
      tax_mat[,] <- trimws(tax_mat[,])
      tax_table(pseq) <- tax_table(tax_mat)

      # NOTE: NO data-wide subset_taxa or filter_taxa here.
      # The central Filter tab is the single source of truth for taxa
      # filtering. Previously this reactive ran:
      #     subset_taxa(!is.na(Phylum))
      #     subset_taxa(! ... Chloroplast / Mitochondria ... )
      #     filter_taxa(sum(x > 0) > 0.1 * length(x))           # 10% data-wide
      # The 10% data-wide prevalence filter (applied across ALL samples,
      # before any per-comparison subset) silently suppressed
      # condition-specific signal — every per-condition ANCOM-BC run
      # ended up testing the same set of universally-prevalent taxa.
      # The published ANCOM-BC method does recommend a 10% prevalence
      # filter, but that filter belongs to the per-comparison subset
      # (after sample subsetting to the two groups under test); it
      # already runs inside .run_ancombc_native() at the per-comparison
      # level, so removing the data-wide one here doesn't drop
      # methodological rigour — it just defers the decision to the
      # right scope.
      pseq
    })

    # ------------------------------------------------------------------
    # Group variable picker
    # ------------------------------------------------------------------
    output$group_variable_ui <- renderUI({
      pseq <- physeq_clean()
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
      pseq <- physeq_clean()
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
      pseq <- physeq_clean()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      all_groups <- sort(unique(as.character(metadata[[input$group_variable]])))
      comp_choices <- setdiff(all_groups, input$ref_group)
      selectInput(ns("comp_group"), "Comparison group:",
                  choices = comp_choices, selected = comp_choices[1])
    })

    # ------------------------------------------------------------------
    # Per-group ASV / sample breakdown card (shared with Network /
    # DESeq2 / RF panels via group_asv_count_card() in global.r).
    # ------------------------------------------------------------------
    output$group_asv_counts_ui <- renderUI({
      req(input$group_variable)
      group_asv_count_card(
        pseq            = physeq_clean(),
        category        = input$group_variable,
        selected_groups = c(input$ref_group, input$comp_group)
      )
    })

    # ------------------------------------------------------------------
    # Native ANCOM-BC implementation (two-group)
    # ------------------------------------------------------------------
    .run_ancombc_native <- function(pseq, grp_var, ref_group, comp_group) {

      t0 <- proc.time()["elapsed"]
      cat("[ANCOM-BC] Starting: ", comp_group, " vs ", ref_group, "\n"); flush.console()

      # --- 1. Subset to only the two selected groups ---
      meta <- as(sample_data(pseq), "data.frame")
      keep_samples <- as.character(meta[[grp_var]]) %in% c(ref_group, comp_group)
      pseq <- prune_samples(keep_samples, pseq)
      # Remove taxa absent in this subset
      pseq <- filter_taxa(pseq, function(x) sum(x > 0) > 0, TRUE)

      cat("[ANCOM-BC] Subset to", nsamples(pseq), "samples (",
          comp_group, "vs", ref_group, ")\n"); flush.console()

      # --- 2. ASV-level analysis (no aggregation) ---
      cat("[ANCOM-BC] Preparing ASV-level features...\n"); flush.console()

      otu_mat <- as(otu_table(pseq), "matrix")
      if (!taxa_are_rows(pseq)) otu_mat <- t(otu_mat)
      tt <- as.data.frame(tax_table(pseq), stringsAsFactors = FALSE)

      asv_ids_original <- rownames(otu_mat)  # ASV1, ASV2, ...
      asv_map <- list()

      # Build display name: "ASV1 - Genus [Family]" for readability
      genus_col  <- if ("Genus"  %in% colnames(tt)) tt$Genus  else rep(NA, nrow(tt))
      family_col <- if ("Family" %in% colnames(tt)) tt$Family else rep(NA, nrow(tt))
      new_names <- vapply(seq_len(nrow(tt)), function(i) {
        g <- genus_col[i]; f <- family_col[i]
        g <- if (is.na(g) || g == "") "Unclassified" else g
        f <- if (is.na(f) || f == "") "" else f
        tax_label <- if (nzchar(f)) paste0(g, " [", f, "]") else g
        paste0(asv_ids_original[i], " - ", tax_label)
      }, character(1))
      new_names <- make.unique(new_names, sep = " #")
      rownames(otu_mat) <- new_names
      for (i in seq_along(new_names)) {
        asv_map[[new_names[i]]] <- asv_ids_original[i]
      }

      taxa_ids  <- rownames(otu_mat)
      n_taxa    <- nrow(otu_mat)
      n_samples <- ncol(otu_mat)

      cat("[ANCOM-BC] Total ASVs:", n_taxa, "(",
          round(proc.time()["elapsed"] - t0, 1), "s)\n"); flush.console()

      # --- 3. Prevalence filter ---
      prev <- rowSums(otu_mat > 0) / n_samples
      keep <- prev >= 0.10
      otu_mat  <- otu_mat[keep, , drop = FALSE]
      taxa_ids <- rownames(otu_mat)
      n_taxa   <- nrow(otu_mat)

      cat("[ANCOM-BC] After prevalence filter (>10%):", n_taxa, "taxa\n")
      flush.console()

      # --- 4. Log-transform ---
      log_otu <- log(otu_mat + 1)

      # --- 5. Estimate sampling fraction bias ---
      sample_bias <- apply(log_otu, 2, median)

      # --- 6. Bias-corrected linear models (two-group) ---
      cat("[ANCOM-BC] Fitting bias-corrected linear models...\n"); flush.console()

      bc_mat <- sweep(log_otu, 2, sample_bias, "-")

      meta_sub <- as(sample_data(pseq), "data.frame")
      groups <- factor(
        as.character(meta_sub[[grp_var]]),
        levels = c(ref_group, comp_group)
      )

      # Vectorised: apply lm per taxon
      model_results <- t(apply(bc_mat, 1, function(y) {
        tryCatch({
          fit <- lm(y ~ groups)
          coefs <- summary(fit)$coefficients
          if (nrow(coefs) >= 2) {
            c(coefs[2, "Estimate"] / log(2),
              coefs[2, "Std. Error"] / log(2),
              coefs[2, "t value"],
              coefs[2, "Pr(>|t|)"])
          } else {
            c(NA_real_, NA_real_, NA_real_, NA_real_)
          }
        }, error = function(e) {
          c(NA_real_, NA_real_, NA_real_, NA_real_)
        })
      }))

      # Build ASV info for each taxon
      asv_ids_col <- vapply(taxa_ids, function(tid) {
        ids <- asv_map[[tid]]
        if (is.null(ids)) "" else paste(ids, collapse = ", ")
      }, character(1))
      n_asvs_col <- vapply(taxa_ids, function(tid) {
        ids <- asv_map[[tid]]
        if (is.null(ids)) 0L else length(ids)
      }, integer(1))

      results <- data.frame(
        taxon   = taxa_ids,
        log2FC  = model_results[, 1],
        se      = model_results[, 2],
        W_stat  = model_results[, 3],
        pvalue  = model_results[, 4],
        asv_ids = asv_ids_col,
        n_asvs  = n_asvs_col,
        stringsAsFactors = FALSE
      )

      cat("[ANCOM-BC] Models fitted (",
          round(proc.time()["elapsed"] - t0, 1), "s)\n"); flush.console()

      # --- 7. FDR correction ---
      results <- results[!is.na(results$pvalue), ]
      results$padj <- p.adjust(results$pvalue, method = "fdr")

      # --- 8. Enrichment direction ---
      results$enriched_in <- ifelse(results$log2FC > 0, comp_group, ref_group)
      results$comparison  <- paste0(comp_group, " vs ", ref_group)

      cat("[ANCOM-BC] Total tested:", nrow(results), "| Total time:",
          round(proc.time()["elapsed"] - t0, 1), "s\n"); flush.console()
      results
    }

    # ------------------------------------------------------------------
    # Run ANCOM-BC
    # ------------------------------------------------------------------
    ancombc_results <- eventReactive(input$run_ancombc, {
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

        # NULL fallbacks for expert-only parameters
        alpha     <- as.numeric(if (is.null(input$alpha)) 0.05 else input$alpha)
        lfc_cut   <- as.numeric(if (is.null(input$log2fc_cutoff)) 1.0 else input$log2fc_cutoff)

        # Taxonomy rank — same convention as the RF and DESeq2 panels.
        # When != "ASV", we tax_glom() the phyloseq BEFORE the native
        # ANCOM-BC fit so the resulting features map to the same
        # human-readable taxonomy labels (e.g. "Lactobacillus") that the
        # other DA panels produce — required for the ANCOM-BC+RF
        # overlap to join correctly at higher ranks.
        tax_rank_val <- if (is.null(input$tax_rank)) "ASV" else input$tax_rank
        if (tax_rank_val != "ASV" &&
            tax_rank_val %in% colnames(tax_table(pseq))) {
          pseq <- tryCatch({
            glom <- tax_glom(pseq, taxrank = tax_rank_val, NArm = FALSE)
            tax_labels <- as.character(tax_table(glom)[, tax_rank_val])
            tax_labels[is.na(tax_labels) | tax_labels == ""] <-
              paste0("Unclassified_",
                     taxa_names(glom)[is.na(tax_labels) | tax_labels == ""])
            tax_labels <- make.unique(tax_labels, sep = "_")
            taxa_names(glom) <- tax_labels
            glom
          }, error = function(e) {
            showNotification(paste0("tax_glom at ", tax_rank_val,
                                    " failed: ", e$message,
                                    ". Falling back to ASV level."),
                             type = "warning", duration = 8)
            pseq
          })
        }

        withProgress(message = "Running ANCOM-BC analysis...", value = 0, {

          incProgress(0.1, detail = "Preparing data")
          cat("[ANCOM-BC] Native implementation (bias-corrected linear models)\n")
          cat("[ANCOM-BC] Comparison: ", comp_group, " vs ", ref_group, "\n")
          cat("[ANCOM-BC] Analysis level:", tax_rank_val,
              "| Alpha:", alpha, "\n")
          flush.console()

          incProgress(0.3, detail = "Fitting models")

          full_res <- .run_ancombc_native(
            pseq, grp_var, ref_group, comp_group
          )

          incProgress(0.8, detail = "Processing results")

          # Identify significant features
          sig_mask <- !is.na(full_res$padj) &
                      full_res$padj < alpha &
                      abs(full_res$log2FC) > lfc_cut
          n_sig <- sum(sig_mask, na.rm = TRUE)

          sig_features <- full_res[sig_mask, , drop = FALSE]
          if (nrow(sig_features) > 0) {
            sig_features <- sig_features[order(abs(sig_features$log2FC),
                                               decreasing = TRUE), ]
          }

          cat("[ANCOM-BC] Significant (padj <", alpha,
              "& |log2FC| >", lfc_cut, "):", n_sig, "\n"); flush.console()

          incProgress(1, detail = "Done")
          showNotification(
            paste0("\u2705 ANCOM-BC complete: ", n_sig,
                   " significant features (", comp_group, " vs ", ref_group, ")"),
            type = "message")

          list(
            full_res     = full_res,
            sig_features = sig_features,
            grp_var      = grp_var,
            ref_group    = ref_group,
            comp_group   = comp_group,
            comparison   = paste0(comp_group, " vs ", ref_group),
            n_sig        = n_sig
          )
        })
      }, error = function(e) {
        cat("[ANCOM-BC] ERROR:", e$message, "\n"); flush.console()
        showNotification(paste0("ANCOM-BC error: ", e$message),
                         type = "error", duration = 15)
        NULL
      })
    })

    # ------------------------------------------------------------------
    # Volcano Plot
    # ------------------------------------------------------------------
    volcano_reactive <- reactive({
      res <- ancombc_results()
      req(res)

      full_res <- res$full_res
      if (is.null(full_res) || nrow(full_res) == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                     label = "No results available.", size = 5, color = "#E67E22") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      # NULL fallbacks for expert-only plot parameters
      alpha_cut <- as.numeric(if (is.null(input$alpha)) 0.05 else input$alpha)
      lfc_cut   <- as.numeric(if (is.null(input$log2fc_cutoff)) 1.0 else input$log2fc_cutoff)
      fsize     <- as.numeric(if (is.null(input$font_size)) 12 else input$font_size)
      pt_size   <- as.numeric(if (is.null(input$point_size)) 3 else input$point_size)

      df <- full_res
      df$neg_log10_padj <- -log10(df$padj + 1e-300)

      df$Significance <- ifelse(
        is.na(df$padj), "NS",
        ifelse(df$padj < alpha_cut & abs(df$log2FC) > lfc_cut,
               ifelse(df$log2FC > 0, "Up", "Down"), "NS")
      )

      up_label   <- paste0("Enriched in ", res$comp_group)
      down_label <- paste0("Enriched in ", res$ref_group)

      df$Direction <- ifelse(
        df$Significance == "Up", up_label,
        ifelse(df$Significance == "Down", down_label, "Not significant")
      )

      dir_colors <- setNames(
        c("#1F77B4", "#D62728", "#BFC4C9"),
        c(down_label, up_label, "Not significant")
      )

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes). User-supplied plot title overrides the
      # auto-generated default.
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = "Direction",
                                   base_size = fsize)

      p <- ggplot2::ggplot(df, ggplot2::aes(x = log2FC, y = neg_log10_padj,
                                              color = Direction)) +
        ggplot2::geom_point(alpha = 0.75, size = pt_size) +
        ggplot2::geom_vline(xintercept = c(-lfc_cut, lfc_cut),
                            linetype = "dashed", color = "grey40") +
        ggplot2::geom_hline(yintercept = -log10(alpha_cut),
                            linetype = "dashed", color = "grey40") +
        ggplot2::scale_color_manual(values = dir_colors, name = NULL) +
        styles$theme_fn(base_size = fsize) +
        styles$grid_theme +
        ggplot2::theme(
          plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
          plot.subtitle = ggplot2::element_text(hjust = 0.5, color = "#555555"),
          legend.position = "top"
        ) +
        ggplot2::labs(
          title = if (is.null(styles$title)) paste0("ANCOM-BC: ", res$comp_group, " vs ", res$ref_group) else styles$title,
          subtitle = paste0("\u03B1 = ", alpha_cut, "  |  |log2FC| > ", lfc_cut,
                           "  |  ", res$n_sig, " significant"),
          x = paste0("Log2 Fold Change (\u2190 ", res$ref_group,
                     "  |  ", res$comp_group, " \u2192)"),
          y = "-Log10 Adjusted p-value"
        )

      # Label significant taxa
      show_labels_val <- if (is.null(input$show_labels)) TRUE else input$show_labels
      # Easy mode defaults to top 10; Expert mode defaults to 15
      easy_mode <- identical(input$analysis_mode, "easy")
      default_top_n <- if (easy_mode) 10 else 15
      label_top_n_val <- if (is.null(input$label_top_n)) default_top_n else input$label_top_n
      if (isTRUE(show_labels_val) &&
          !is.null(label_top_n_val) && label_top_n_val > 0) {
        sig_df <- df[df$Significance != "NS" & !is.na(df$padj), , drop = FALSE]
        if (nrow(sig_df) > 0) {
          sig_df <- sig_df[order(sig_df$padj), , drop = FALSE]
          top_lab <- head(sig_df, label_top_n_val)
          # Use short name for labels with ASV IDs
          top_lab$.label <- sapply(seq_len(nrow(top_lab)), function(i) {
            base <- gsub(" \\[.*\\]$", "", top_lab$taxon[i])
            ids <- strsplit(as.character(top_lab$asv_ids[i]), ", ")[[1]]
            if (length(ids) == 0 || (length(ids) == 1 && ids[1] == "")) {
              base
            } else if (length(ids) <= 2) {
              paste0(base, " (", paste(ids, collapse = ", "), ")")
            } else {
              paste0(base, " (", paste(ids[1:2], collapse = ", "), " +", length(ids) - 2, ")")
            }
          })

          lbl_size <- as.numeric(if (is.null(input$label_size)) 3.2 else input$label_size)

          if (requireNamespace("ggrepel", quietly = TRUE)) {
            p <- p + ggrepel::geom_text_repel(
              data = top_lab,
              ggplot2::aes(x = log2FC, y = neg_log10_padj, label = .label),
              size = lbl_size, color = "black",
              box.padding = 0.3, point.padding = 0.2, max.overlaps = 25,
              min.segment.length = 0, show.legend = FALSE)
          } else {
            p <- p + ggplot2::geom_text(
              data = top_lab,
              ggplot2::aes(x = log2FC, y = neg_log10_padj, label = .label),
              size = lbl_size, color = "black",
              vjust = -0.6, show.legend = FALSE)
          }
        }

        # Notify user in Easy mode about label limitation
        if (easy_mode && isTRUE(show_labels_val)) {
          showNotification(
            "Showing top 10 labels. For full label control, use Expert mode.",
            type = "message",
            duration = 5
          )
        }
      }
      p
    })

    output$volcano_plot <- renderPlot({
      if (is.null(input$run_ancombc) || input$run_ancombc == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.58,
                     label = "Select reference and comparison groups,\nthen click 'Run ANCOM-BC'",
                     size = 5.5, fontface = "bold", color = "#3B82F6") +
            ggplot2::annotate("text", x = 0.5, y = 0.40,
                     label = "The volcano plot will appear here.",
                     size = 4, color = "#7F8C8D") +
            ggplot2::annotate("text", x = 0.5, y = 0.30,
                     label = "Native implementation — no extra packages needed.",
                     size = 3.5, color = "#95A5A6") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }
      print(volcano_reactive())
    }, res = 120)

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    output$ancombc_summary <- renderPrint({
      if (is.null(input$run_ancombc) || input$run_ancombc == 0) {
        cat("Click 'Run ANCOM-BC' to test for differentially abundant taxa.\n\n")
        cat("Native implementation — no extra packages required.\n")
        cat("Uses bias-corrected linear models on log-transformed counts.\n\n")
        cat("ANCOM-BC advantages over DESeq2 for microbiome data:\n")
        cat("  - Explicitly models sampling fraction (compositional bias)\n")
        cat("  - Provides unbiased log fold change estimates\n")
        cat("  - Controls FDR while accounting for compositionality\n")
        return(invisible(NULL))
      }
      res <- ancombc_results()
      validate(need(!is.null(res),
                    "ANCOM-BC did not return results. Check your settings."))

      cat("ANCOM-BC Differential Abundance Results\n")
      cat("---------------------------------------\n")
      cat("Group variable:        ", res$grp_var, "\n", sep = "")
      cat("Comparison:            ", res$comp_group, " vs ", res$ref_group, "\n",
          sep = "")
      cat("Analysis level:        ASV (individual)\n")
      # Use fallback defaults for expert parameters in output
      alpha_show <- if (is.null(input$alpha)) 0.05 else input$alpha
      lfc_show <- if (is.null(input$log2fc_cutoff)) 1.0 else input$log2fc_cutoff
      cat("Significance (\u03B1):     ", alpha_show, "\n", sep = "")
      cat("Log2FC cutoff:         ", lfc_show, "\n", sep = "")
      cat("Total taxa tested:     ", nrow(res$full_res), "\n", sep = "")
      cat("Significant features:  ", res$n_sig, "\n\n", sep = "")

      if (res$n_sig > 0) {
        sig_df <- res$sig_features
        cat("Per-group enrichment:\n")
        tbl <- table(sig_df$enriched_in)
        for (g in names(tbl)) {
          cat("  ", g, ": ", tbl[g], " features\n", sep = "")
        }
        cat("\nTop 10 by absolute effect size:\n")
        top10 <- head(sig_df, 10)
        for (i in seq_len(nrow(top10))) {
          nm <- gsub(" \\[.*\\]$", "", top10$taxon[i])
          asv_tag <- if (nzchar(top10$asv_ids[i])) paste0(" [", top10$asv_ids[i], "]") else ""
          cat("  ", nm, asv_tag, " (",
              top10$enriched_in[i],
              ", log2FC=", round(top10$log2FC[i], 3),
              ", padj=", signif(top10$padj[i], 3), ")\n", sep = "")
        }
      } else {
        cat("No significant features found.\n")
        cat("Try: lower significance threshold or reduce log2FC cutoff.\n")
      }
    })

    # ------------------------------------------------------------------
    # Results Table
    # ------------------------------------------------------------------
    output$results_table <- DT::renderDataTable({
      res <- ancombc_results()
      req(res, res$n_sig > 0)

      sig_df <- res$sig_features
      display_df <- data.frame(
        Taxon       = sig_df$taxon,
        ASV_IDs     = sig_df$asv_ids,
        N_ASVs      = sig_df$n_asvs,
        Enriched_In = sig_df$enriched_in,
        Log2FC      = round(sig_df$log2FC, 4),
        SE          = round(sig_df$se, 4),
        P_value     = signif(sig_df$pvalue, 4),
        FDR_padj    = signif(sig_df$padj, 4),
        stringsAsFactors = FALSE
      )

      DT::datatable(display_df,
        options = list(pageLength = 20, scrollX = TRUE, dom = "frtip"),
        rownames = FALSE)
    })

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    output$download_table <- downloadHandler(
      filename = function() {
        res <- tryCatch(ancombc_results(), error = function(e) NULL)
        comp_tag <- if (!is.null(res))
          paste0(res$comp_group, "_vs_", res$ref_group) else "results"
        ezmap_filename(paste0("ANCOMBC_", comp_tag), "csv")
      },
      content  = function(file) {
        res <- ancombc_results()
        req(res)
        utils::write.csv(res$full_res, file, row.names = FALSE)
      }
    )

    output$download_volcano <- downloadHandler(
      filename = function() ezmap_download_filename(input, "ANCOMBC_Volcano"),
      content  = function(file) {
        p <- volcano_reactive()
        d <- download_dims(input, def_width = 10, def_height = 8)
        ggplot2::ggsave(file, p,
                        width = d$width, height = d$height,
                        units = d$units, dpi = d$dpi)
      }
    )

    # ------------------------------------------------------------------
    # Return results
    # ------------------------------------------------------------------
    # ancombc_results : the actual ANCOM-BC fit
    # log2fc_used / alpha_used : reactives that report what cutoffs the
    # user picked in THIS panel. The combined ANCOM-BC + RF panel reads
    # these so its overlap logic uses the SAME thresholds the user
    # chose here, instead of falling back to its own defaults (which
    # caused the "ANCOM-BC = 13 hits, ANCOM-BC+RF = 52 hits" confusion).
    return(list(
      ancombc_results = ancombc_results,
      log2fc_used     = reactive({
          if (is.null(input$log2fc_cutoff) || !is.finite(input$log2fc_cutoff)) 1
          else as.numeric(input$log2fc_cutoff)
      }),
      alpha_used      = reactive({
          if (is.null(input$alpha) || !is.finite(input$alpha)) 0.05
          else as.numeric(input$alpha)
      })
    ))
  })
}
