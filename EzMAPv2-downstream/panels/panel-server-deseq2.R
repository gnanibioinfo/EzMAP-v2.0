# panels/panel-server-deseq2.R — DESeq2 Server Logic (FINAL FIXED)
deseq2Server <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # --- 1. Preprocessing Reactive Step ---
    physeq_filtered_processed <- reactive({
      Abundance_raw <- physeq_data()
      req(Abundance_raw)
      
      Bacteria <- Abundance_raw

      # NOTE: Do NOT rename taxa here. The upload server (panel-server-data.R)
      # already assigned canonical "ASV1..ASV(N_raw)" IDs at load time, and
      # the Filter tab preserves them via prune_taxa()/subset_taxa(). Renaming
      # locally would re-number the surviving taxa to "ASV1..ASV(local_n)",
      # which silently desyncs DESeq2's IDs from ANCOM-BC's / LeFSe's and
      # makes the DESeq2+RF / ANCOM-BC+RF overlap panels join on disjoint
      # ID spaces. The previous rename line has been removed for that reason.

      # --- Standard taxonomy column names (defensive) ---
      if (ncol(tax_table(Bacteria)) >= 7) {
        colnames(tax_table(Bacteria)) <- c("Kingdom","Phylum","Class","Order","Family","Genus","Species")[1:ncol(tax_table(Bacteria))]
      }

      # NOTE: NO local taxa filtering or count normalization.
      # The central Filter tab is the single source of truth for taxa
      # filtering (chloroplast / mitochondria / Eukaryota / Archaea /
      # abundance / prevalence / custom exclusions). DESeq2 itself
      # performs internal size-factor normalization (geometric-mean
      # method), so pre-normalising to median depth here is incorrect
      # — DESeq() expects raw integer counts.
      # Previously this reactive ran:
      #     subset_taxa(!grepl("Eukaryota|Archaea", Kingdom))   # kills fungi on ITS
      #     filter_taxa(sum(x > 3) > 0.2 * length(x))           # data-wide pre-filter
      #     transform_sample_counts(median-depth)               # wrong for DESeq2
      # The 20% prevalence pre-filter additionally suppressed
      # condition-specific signal (the same bug the Beta and Network
      # panels had — every condition's "filtered" data ended up with
      # the same set of universally-abundant ASVs).

      # --- Strip taxonomy prefixes (defensive — central upload also does this) ---
      tax_mat <- as(tax_table(Bacteria), "matrix")
      tax_mat[,] <- gsub("[Dd]_[0-9]+__", "", tax_mat[,])
      tax_mat[,] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_mat[,])
      tax_mat[,] <- trimws(tax_mat[,])
      tax_table(Bacteria) <- tax_table(tax_mat)

      showNotification(
        paste0("DESeq2 data ready: ", ntaxa(Bacteria), " ASVs / ",
               nsamples(Bacteria), " samples (matches Filter tab)."),
        type = "message", duration = 6
      )
      return(Bacteria)
    })
    
    # --- 2. UI: Grouping Variable Selection ---
    output$group_variable_ui <- renderUI({
      pseq <- physeq_filtered_processed()
      req(pseq)
      
      metadata <- as(sample_data(pseq), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x) (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
      
      selectInput(session$ns("group_variable"), "Select Grouping Variable:", choices = group_vars)
    })
    
    # --- 3. UI: Comparison Levels ---
    output$comparison_ui <- renderUI({
      req(input$group_variable)
      pseq <- physeq_filtered_processed()
      metadata <- as(sample_data(pseq), "data.frame")

      levels_group <- unique(as.character(metadata[[input$group_variable]]))

      tagList(
        selectInput(session$ns("group_1"), "Group 1 (Reference):", choices = levels_group, selected = levels_group[1]),
        selectInput(session$ns("group_2"), "Group 2 (Comparison):", choices = levels_group, selected = levels_group[2])
      )
    })

    # --- 3b. Per-group ASV / sample breakdown card ---
    # Same shared card the Network / ANCOM-BC / RF panels use. Lets the
    # user see how condition-specific each level is BEFORE running the
    # comparison, and confirm both selected groups have enough samples
    # / features for DESeq2's negative-binomial fit.
    output$group_asv_counts_ui <- renderUI({
      req(input$group_variable)
      group_asv_count_card(
        pseq            = physeq_filtered_processed(),
        category        = input$group_variable,
        selected_groups = c(input$group_1, input$group_2)
      )
    })
    
    # --- 4. Run DESeq2 Analysis ---
    deseq2_results <- eventReactive(input$run_deseq2, {
      if (!has_package("DESeq2")) {
        showNotification("DESeq2 is not installed. Install via BiocManager::install('DESeq2').", type = "error")
        return(NULL)
      }
      pseq <- physeq_filtered_processed()
      req(pseq, input$group_variable, input$group_1, input$group_2)

      withProgress(message = "Running DESeq2 Analysis...", value = 0, {
        incProgress(0.2, detail = "Setting up DESeq2 dataset...")
        
        # --- FIXED GROUP SUBSETTING ---
        meta_df <- as(sample_data(pseq), "data.frame")
        group_var <- input$group_variable
        grp1 <- input$group_1
        grp2 <- input$group_2
        
        # Defensive check
        if (!group_var %in% colnames(meta_df)) {
          showNotification(paste("Grouping variable", group_var, "not found in metadata."), type = "error")
          return(NULL)
        }
        
        samples_keep <- rownames(meta_df)[meta_df[[group_var]] %in% c(grp1, grp2)]
        subdata <- prune_samples(samples_keep, pseq)
        subdata <- prune_taxa(taxa_sums(subdata) > 0, subdata)

        # --- Optional taxonomy-rank aggregation (same logic as RF panel) ---
        # Lets the user run DESeq2 at Genus / Family / Order / Class /
        # Phylum level. Required to share feature IDs with the Random
        # Forest and ANCOM-BC panels when those are also aggregated to
        # the same rank — otherwise the DESeq2+RF / ANCOM-BC+RF overlap
        # panels join on disjoint ID spaces.
        tax_rank_val <- if (is.null(input$tax_rank)) "ASV" else input$tax_rank
        if (tax_rank_val != "ASV" && tax_rank_val %in% colnames(tax_table(subdata))) {
            incProgress(0.1, detail = paste0("Aggregating at ", tax_rank_val, " level..."))
            subdata <- tryCatch({
                glom <- tax_glom(subdata, taxrank = tax_rank_val, NArm = FALSE)
                tax_labels <- as.character(tax_table(glom)[, tax_rank_val])
                tax_labels[is.na(tax_labels) | tax_labels == ""] <-
                    paste0("Unclassified_", taxa_names(glom)[is.na(tax_labels) | tax_labels == ""])
                tax_labels <- make.unique(tax_labels, sep = "_")
                taxa_names(glom) <- tax_labels
                glom
            }, error = function(e) {
                showNotification(paste0("tax_glom at ", tax_rank_val, " failed: ",
                                        e$message, ". Falling back to ASV level."),
                                 type = "warning", duration = 8)
                subdata
            })
        }

        # --- Run DESeq2 ---
        dds <- phyloseq_to_deseq2(subdata, as.formula(paste("~", group_var)))
        dds <- DESeq(dds, test = "Wald", fitType = "parametric")
        
        incProgress(0.6, detail = "Extracting results...")
        res <- results(dds, cooksCutoff = FALSE)
		res_df <- as(res, "data.frame")
		res_df <- cbind(res_df, as(tax_table(subdata)[rownames(res_df), ], "matrix"))

		# Add comparison info
		res_df$comparison <- paste(grp2, "vs", grp1)

		# --- NEW: Enriched group column ---
		enrich_colname <- paste0(group_var, "_Enriched")
		res_df[[enrich_colname]] <- ifelse(
		  is.na(res_df$log2FoldChange), NA,
		  ifelse(res_df$log2FoldChange > 0, grp2, grp1)
		)

		# Add volcano plot helper columns
		res_df$Species <- rownames(res_df)
		res_df$lab <- rownames(res_df)
		res_df$xvals <- res_df$log2FoldChange
		res_df$yvals <- -log10(res_df$padj)

		# Define significance category
		res_df$Sig <- ifelse(
		  is.na(res_df$padj), "NS",
		  ifelse(abs(res_df$log2FoldChange) > 2 & res_df$padj < 0.05, "Log2FC > |2|", "NS")
		)

		# Reorder columns for clarity
		res_df <- res_df[, c("comparison", enrich_colname, "Species", "Sig", "lab", "xvals", "yvals",
							 setdiff(colnames(res_df), c("comparison", enrich_colname, "Species", "Sig", "lab", "xvals", "yvals")))]

		res <- res_df
        
        incProgress(1.0, detail = "Analysis complete.")
        showNotification("DESeq2 analysis completed successfully.", type = "message")
        
        return(res)
      })
    })
    
    # --- 5. Volcano Plot ---
    # ggrepel is loaded lazily; fall back silently if not installed.
    has_ggrepel <- requireNamespace("ggrepel", quietly = TRUE)

    volcano_reactive <- reactive({
      res <- deseq2_results()
      req(res)

      grp1 <- input$group_1   # reference
      grp2 <- input$group_2   # comparison

      col_ref  <- if (!is.null(input$color_ref)  && nzchar(input$color_ref))  input$color_ref  else "#1f77b4"
      col_comp <- if (!is.null(input$color_comp) && nzchar(input$color_comp)) input$color_comp else "#d62728"
      col_ns   <- if (!is.null(input$color_ns)   && nzchar(input$color_ns))   input$color_ns   else "#BFC4C9"

      # Fallback defaults for expert-only parameters
      lfc_cut <- if (is.null(input$log2fc_cutoff)) 1 else input$log2fc_cutoff
      padj_cut <- if (is.null(input$padj_cutoff)) 0.05 else input$padj_cutoff
      pt_size <- if (is.null(input$point_size)) 3 else input$point_size
      plt_title <- if (is.null(input$plot_title)) "DESeq2 Volcano Plot" else input$plot_title
      show_dir_arrows <- if (is.null(input$show_direction_arrows)) FALSE else input$show_direction_arrows
      show_lbl <- if (is.null(input$show_labels)) TRUE else input$show_labels
      lbl_top <- if (is.null(input$label_top_n)) 10 else input$label_top_n

      # Classify each ASV: significant & which side of 0 it falls on
      res$.sig <- with(res, !is.na(padj) & padj < padj_cut &
                              !is.na(log2FoldChange) &
                              abs(log2FoldChange) > lfc_cut)
      res$Direction <- ifelse(
        !res$.sig, "Not significant",
        ifelse(res$log2FoldChange > 0,
               paste0("Enriched in ", grp2),
               paste0("Enriched in ", grp1))
      )

      color_vec <- setNames(
        c(col_ref, col_comp, col_ns),
        c(paste0("Enriched in ", grp1),
          paste0("Enriched in ", grp2),
          "Not significant")
      )

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes). User-supplied plot title overrides the
      # auto-generated default.
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = "Direction",
                                   base_size = 12)

      p <- ggplot(res, aes(x = log2FoldChange, y = -log10(padj),
                           color = Direction)) +
        geom_point(alpha = 0.75, size = pt_size) +
        geom_vline(xintercept = c(-lfc_cut, lfc_cut),
                   linetype = "dashed", color = "grey40") +
        geom_hline(yintercept = -log10(padj_cut),
                   linetype = "dashed", color = "grey40") +
        scale_color_manual(values = color_vec, name = NULL) +
        styles$theme_fn(base_size = 12) +
        styles$grid_theme +
        theme(plot.title = element_text(hjust = 0.5, face = "bold"),
              plot.subtitle = element_text(hjust = 0.5, color = "#555555"),
              legend.position = "top") +
        labs(title = if (is.null(styles$title)) plt_title else styles$title,
             subtitle = paste0("Comparison: ", grp2, " vs ", grp1,
                               "   |   Reference = ", grp1),
             x = paste0("Log2 Fold Change  (\u2190 ", grp1, "   |   ", grp2, " \u2192)"),
             y = "-Log10 Adjusted p-value")

      # Directional annotation arrows on top of plot area
      if (isTRUE(show_dir_arrows)) {
        xr <- range(res$log2FoldChange[is.finite(res$log2FoldChange)], na.rm = TRUE)
        yr <- range(-log10(res$padj[is.finite(res$padj) & res$padj > 0]), na.rm = TRUE)
        if (all(is.finite(xr)) && all(is.finite(yr))) {
          y_top <- yr[2] * 0.98 + 0.01
          p <- p +
            annotate("segment", x = 0, xend = xr[1],
                     y = y_top, yend = y_top,
                     arrow = arrow(length = unit(0.12, "inches")),
                     color = col_ref, linewidth = 0.8) +
            annotate("segment", x = 0, xend = xr[2],
                     y = y_top, yend = y_top,
                     arrow = arrow(length = unit(0.12, "inches")),
                     color = col_comp, linewidth = 0.8) +
            annotate("text", x = xr[1], y = y_top,
                     label = paste0("  Enriched in ", grp1),
                     hjust = 0, vjust = -0.6, color = col_ref,
                     fontface = "bold", size = 4) +
            annotate("text", x = xr[2], y = y_top,
                     label = paste0("Enriched in ", grp2, "  "),
                     hjust = 1, vjust = -0.6, color = col_comp,
                     fontface = "bold", size = 4)
        }
      }

      # Label top-N significant ASVs
      if (isTRUE(show_lbl) && lbl_top > 0) {
        sig_res <- res[res$.sig & !is.na(res$padj), , drop = FALSE]
        if (nrow(sig_res) > 0) {
          sig_res <- sig_res[order(sig_res$padj), , drop = FALSE]
          top_lab <- head(sig_res, lbl_top)

          # Strip SILVA ("D_5__Lactobacillus") and Greengenes ("g__Lactobacillus")
          # prefixes so only the bare taxon name is shown next to the point.
          .clean_taxon <- function(x) {
            x <- as.character(x)
            x[is.na(x)] <- ""
            x <- sub("^D_[0-9]+__", "", x, perl = TRUE)
            x <- sub("^[kpcofgsKPCOFGS]__", "", x, perl = TRUE)
            trimws(x)
          }
          top_lab$.genus_clean  <- .clean_taxon(top_lab$Genus)
          top_lab$.family_clean <- .clean_taxon(top_lab$Family)
          # Append the ASV id in parentheses so each point remains uniquely identifiable.
          otu_ids <- rownames(top_lab)
          top_lab$.label <- ifelse(
            nzchar(top_lab$.genus_clean),
            paste0(top_lab$.genus_clean, " (", otu_ids, ")"),
            ifelse(
              nzchar(top_lab$.family_clean),
              paste0(top_lab$.family_clean, " (", otu_ids, ")"),
              otu_ids))
          lbl_size <- if (is.null(input$label_size) ||
                          !is.finite(input$label_size)) 3.2 else input$label_size
          lbl_alpha <- if (is.null(input$label_color_opacity) ||
                           !is.finite(input$label_color_opacity)) 1 else input$label_color_opacity
          if (has_ggrepel) {
            p <- p + ggrepel::geom_text_repel(
              data = top_lab,
              aes(x = log2FoldChange, y = -log10(padj), label = .label),
              size = lbl_size, color = "black", alpha = lbl_alpha,
              box.padding = 0.3, point.padding = 0.2, max.overlaps = 25,
              min.segment.length = 0, show.legend = FALSE)
          } else {
            p <- p + geom_text(
              data = top_lab,
              aes(x = log2FoldChange, y = -log10(padj), label = .label),
              size = lbl_size, color = "black", alpha = lbl_alpha,
              vjust = -0.6, show.legend = FALSE)
          }
        }
      }
      p
    })

    output$volcano_plot <- renderPlot({
      # Friendly pre-run placeholder (no red error on initial page load)
      if (is.null(input$run_deseq2) || input$run_deseq2 == 0) {
        return(
          ggplot() +
            annotate("text", x = 0.5, y = 0.58,
                     label = "Configure groups and click 'Run DESeq2 Analysis'",
                     size = 5.5, fontface = "bold", color = "#3B82F6") +
            annotate("text", x = 0.5, y = 0.45,
                     label = "The volcano plot will appear here.",
                     size = 4, color = "#7F8C8D") +
            theme_void() + xlim(0, 1) + ylim(0, 1)
        )
      }
      print(volcano_reactive())
    }, res = 120)
    
    # --- 6. Downloads ---
    output$download_volcano_plot <- downloadHandler(
      filename = function() {
        ezmap_download_filename(input, paste0("DESeq2_Volcano_", input$group_1, "_vs_", input$group_2))
      },
      content = function(file) {
        d <- download_dims(input, def_width = 9, def_height = 7)
        ggsave(file, plot = volcano_reactive(),
               width = d$width, height = d$height, units = d$units, dpi = d$dpi)
      }
    )
    
    output$download_deseq2_table <- downloadHandler(
      filename = function() {
        ezmap_filename(paste0("DESeq2_Results_", input$group_1, "_vs_", input$group_2), "csv")
      },
      content = function(file) {
        write.csv(deseq2_results(), file, row.names = TRUE)
      }
    )
    
    # --- 7. Summary Output ---
    output$deseq2_summary <- renderPrint({
      if (is.null(input$run_deseq2) || input$run_deseq2 == 0) {
        cat("Click 'Run DESeq2 Analysis' to compute differential abundance.\n")
        cat("A summary of significant features will appear here.\n")
        return(invisible(NULL))
      }
      res <- deseq2_results()
      validate(need(!is.null(res),
                    "DESeq2 did not return results. Check your group selection and data."))
      cat("DESeq2 Differential Abundance Results\n")
      cat("----------------------------------\n")
      cat("Comparison:       ", unique(res$comparison), "\n")
      cat("Reference group:  ", input$group_1, "\n")
      cat("Comparison group: ", input$group_2, "\n\n")

      # Fallback defaults for expert-only parameters in summary
      padj_cut_sum <- if (is.null(input$padj_cutoff)) 0.05 else input$padj_cutoff
      lfc_cut_sum <- if (is.null(input$log2fc_cutoff)) 1 else input$log2fc_cutoff

      sig_mask <- !is.na(res$padj) & res$padj < padj_cut_sum &
                  abs(res$log2FoldChange) > lfc_cut_sum
      n_up   <- sum(sig_mask & res$log2FoldChange > 0, na.rm = TRUE)
      n_down <- sum(sig_mask & res$log2FoldChange < 0, na.rm = TRUE)
      cat("Significant ASVs at padj <", padj_cut_sum,
          "& |log2FC| >", lfc_cut_sum, ":", n_up + n_down, "\n")
      cat("  Enriched in ", input$group_2, ": ", n_up,   "\n", sep = "")
      cat("  Enriched in ", input$group_1, ": ", n_down, "\n", sep = "")
      cat("Mean log2FoldChange:",
          round(mean(res$log2FoldChange, na.rm = TRUE), 3), "\n")
    })
	
	# At the end of deseq2Server
	# Also expose log2fc_used / padj_used so the DESeq2+RF combined
	# panel inherits the SAME cutoffs the user picked here, instead
	# of falling back to its own defaults (caused the "DESeq2 = 13
	# hits, DESeq2+RF = 52 hits" mismatch).
	return(list(
	  deseq2_results    = deseq2_results,
	  normalized_physeq = physeq_filtered_processed,
	  grp_var           = reactive(input$group_variable),
	  group_1           = reactive(input$group_1),
	  group_2           = reactive(input$group_2),
	  log2fc_used       = reactive({
	      if (is.null(input$log2fc_cutoff) || !is.finite(input$log2fc_cutoff)) 1
	      else as.numeric(input$log2fc_cutoff)
	  }),
	  padj_used         = reactive({
	      if (is.null(input$padj_cutoff) || !is.finite(input$padj_cutoff)) 0.05
	      else as.numeric(input$padj_cutoff)
	  })
	))
	
  })
}
