################################################################################
# panels/panel-server-ancombcrf.R — Combined ANCOM-BC + Random Forest Server
#
# Inputs (pre-computed by other modules, passed in as reactives):
#   ancombc_out : list from ancombcServer()
#                   - ancombc_results() : list with $full_res data.frame
#                       columns: taxon, log2FC, se, W_stat, pvalue, padj,
#                                asv_ids, n_asvs, enriched_in, comparison
#   rf_out      : list from randomForestServer()
#                   - rf_results() : list with $importance (ASV, MeanDecreaseGini, Rank)
#
# Addresses Reviewer 1: "Taking the overlap between RF-selected features and
# features identified as significant by ANCOM-BC may lead to a more stringent
# and higher-confidence feature selection."
#
# No upstream recomputation — the panel just joins, filters, and visualises.
################################################################################

ancombcrfServer <- function(id, ancombc_out, rf_out,
                            physeq_raw = NULL, physeq_filtered = NULL,
                            deseq2rf_intersection = NULL,
                            global_state_rv) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns
    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # ------------------------------------------------------------------
    # Dataset selector (Raw vs Filtered) — used to populate condition
    # pickers from the same metadata the user chose upstream.
    # ------------------------------------------------------------------
    physeq_data <- if (!is.null(physeq_raw)) {
      dataset_selector_reactive(input, physeq_raw, physeq_filtered)
    } else {
      reactive(NULL)
    }

    # Helper: pull the metadata frame from the chosen phyloseq, falling
    # back to whatever upstream ANCOM-BC saw if the user has not yet
    # picked a dataset on this tab.
    .meta_df <- reactive({
      pseq <- tryCatch(physeq_data(), error = function(e) NULL)
      if (is.null(pseq)) return(NULL)
      as(sample_data(pseq), "data.frame")
    })

    # ------------------------------------------------------------------
    # Condition pickers — mirror the ANCOM-BC tab so the user can SEE
    # which two groups the overlap is being computed for.
    # Pre-populated with whatever the upstream ANCOM-BC run actually used.
    # ------------------------------------------------------------------
    output$group_variable_ui <- renderUI({
      meta <- .meta_df()
      if (is.null(meta)) {
        return(helpText(style = "color:#B45309;",
          "Load a dataset first, then run ANCOM-BC and Random Forest."))
      }
      group_vars <- names(meta)[sapply(meta, function(x)
        (is.factor(x) || is.character(x)) && length(unique(x)) > 1 &&
          length(unique(x)) < length(x))]
      # Default to whatever ANCOM-BC was last run with, if available.
      abc_res <- tryCatch(ancombc_out$ancombc_results(), error = function(e) NULL)
      sel <- if (!is.null(abc_res) && !is.null(abc_res$grp_var) &&
                 abc_res$grp_var %in% group_vars) abc_res$grp_var else group_vars[1]
      selectInput(ns("group_variable"), "Group by:",
                  choices = group_vars, selected = sel)
    })

    output$reference_group_ui <- renderUI({
      req(input$group_variable)
      meta <- .meta_df()
      req(meta)
      lvls <- sort(unique(as.character(meta[[input$group_variable]])))
      abc_res <- tryCatch(ancombc_out$ancombc_results(), error = function(e) NULL)
      sel <- if (!is.null(abc_res) && !is.null(abc_res$ref_group) &&
                 abc_res$ref_group %in% lvls) abc_res$ref_group else lvls[1]
      selectInput(ns("ref_group"), "Reference group:",
                  choices = lvls, selected = sel)
    })

    output$comparison_group_ui <- renderUI({
      req(input$group_variable, input$ref_group)
      meta <- .meta_df()
      req(meta)
      lvls <- sort(unique(as.character(meta[[input$group_variable]])))
      comp_choices <- setdiff(lvls, input$ref_group)
      abc_res <- tryCatch(ancombc_out$ancombc_results(), error = function(e) NULL)
      sel <- if (!is.null(abc_res) && !is.null(abc_res$comp_group) &&
                 abc_res$comp_group %in% comp_choices) abc_res$comp_group
             else comp_choices[1]
      selectInput(ns("comp_group"), "Comparison group:",
                  choices = comp_choices, selected = sel)
    })

    # ------------------------------------------------------------------
    # Live status banner: shows what ANCOM-BC and RF were ACTUALLY run
    # with, and whether they match the user's current picker selection.
    # ------------------------------------------------------------------
    output$upstream_status_ui <- renderUI({
      abc_res <- tryCatch(ancombc_out$ancombc_results(), error = function(e) NULL)
      rf_g1   <- tryCatch(rf_out$group_1(),               error = function(e) NULL)
      rf_g2   <- tryCatch(rf_out$group_2(),               error = function(e) NULL)

      abc_txt <- if (!is.null(abc_res) && !is.null(abc_res$comparison)) {
        abc_res$comparison
      } else "(not run yet)"
      rf_txt <- if (!is.null(rf_g1) && !is.null(rf_g2) &&
                    nzchar(rf_g1) && nzchar(rf_g2)) {
        paste0(rf_g2, " vs ", rf_g1)
      } else "(not run yet)"

      picked_ref  <- input$ref_group
      picked_comp <- input$comp_group
      picked_txt  <- if (!is.null(picked_ref) && !is.null(picked_comp) &&
                         nzchar(picked_ref) && nzchar(picked_comp)) {
        paste0(picked_comp, " vs ", picked_ref)
      } else "(pick groups above)"

      # Match check
      abc_match <- !is.null(abc_res) &&
                   identical(abc_res$ref_group,  picked_ref) &&
                   identical(abc_res$comp_group, picked_comp)
      rf_match  <- !is.null(rf_g1) && !is.null(rf_g2) &&
                   ((rf_g1 == picked_ref  && rf_g2 == picked_comp) ||
                    (rf_g1 == picked_comp && rf_g2 == picked_ref))

      status_color <- if (abc_match && rf_match) "#16A34A"
                      else if (is.null(abc_res) && (is.null(rf_g1) || is.null(rf_g2))) "#64748B"
                      else "#D97706"
      status_bg    <- if (abc_match && rf_match) "#ECFDF5"
                      else if (is.null(abc_res) && (is.null(rf_g1) || is.null(rf_g2))) "#F1F5F9"
                      else "#FFFBEB"
      status_msg <- if (abc_match && rf_match) {
        "✅ Upstream ANCOM-BC and RF were run with these conditions."
      } else if (is.null(abc_res) || is.null(rf_g1) || is.null(rf_g2)) {
        "⚠️ Run ANCOM-BC and Random Forest in their tabs first."
      } else {
        "⚠️ Upstream comparison does NOT match your selection — re-run ANCOM-BC and/or RF with these groups, or change the pickers above."
      }

      tags$div(
        style = paste0("margin-top:8px; padding:10px; background:", status_bg,
                       "; border-left:4px solid ", status_color,
                       "; border-radius:4px; font-size:12px; color:#1F2937;"),
        tags$div(tags$b("Selected: "), picked_txt),
        tags$div(tags$b("ANCOM-BC tab ran: "), abc_txt),
        tags$div(tags$b("Random Forest tab ran: "), rf_txt),
        tags$div(style = paste0("margin-top:6px; color:", status_color, ";"),
                 status_msg)
      )
    })

    # ------------------------------------------------------------------
    # Core reactive: intersect ANCOM-BC + RF results
    # ------------------------------------------------------------------
    intersection <- eventReactive(input$run_intersect, {
      # Guard: both upstream analyses must have been run
      abc_res <- tryCatch(ancombc_out$ancombc_results(), error = function(e) NULL)
      rf_res  <- tryCatch(rf_out$rf_results(),           error = function(e) NULL)

      if (is.null(abc_res) || is.null(abc_res$full_res)) {
        showNotification(
          "Run ANCOM-BC first (in the ANCOM-BC tab) before computing the intersection.",
          type = "error", duration = 6)
        return(NULL)
      }
      if (is.null(rf_res) || is.null(rf_res$importance)) {
        showNotification(
          "Run Random Forest first (in the Random Forest tab) before computing the intersection.",
          type = "error", duration = 6)
        return(NULL)
      }

      # ----- Validate: do upstream runs match the user-picked comparison? -----
      picked_var  <- input$group_variable
      picked_ref  <- input$ref_group
      picked_comp <- input$comp_group
      if (!is.null(picked_ref) && !is.null(picked_comp) &&
          nzchar(picked_ref) && nzchar(picked_comp)) {

        abc_match <- identical(abc_res$grp_var,    picked_var)  &&
                     identical(abc_res$ref_group,  picked_ref)  &&
                     identical(abc_res$comp_group, picked_comp)
        rf_g1 <- tryCatch(rf_out$group_1(), error = function(e) NULL)
        rf_g2 <- tryCatch(rf_out$group_2(), error = function(e) NULL)
        rf_match <- !is.null(rf_g1) && !is.null(rf_g2) &&
                    ((rf_g1 == picked_ref  && rf_g2 == picked_comp) ||
                     (rf_g1 == picked_comp && rf_g2 == picked_ref))

        if (!abc_match) {
          showNotification(
            paste0("ANCOM-BC was run on '", abc_res$comparison,
                   "', but you selected '", picked_comp, " vs ", picked_ref,
                   "'. Re-run ANCOM-BC with the matching groups, or change the pickers."),
            type = "error", duration = 12)
          return(NULL)
        }
        if (!rf_match) {
          rf_txt <- if (!is.null(rf_g1) && !is.null(rf_g2))
                      paste0(rf_g2, " vs ", rf_g1) else "(unknown)"
          showNotification(
            paste0("Random Forest was run on '", rf_txt,
                   "', but you selected '", picked_comp, " vs ", picked_ref,
                   "'. Re-run RF with the matching groups, or change the pickers."),
            type = "error", duration = 12)
          return(NULL)
        }
      }

      # --- Prepare ANCOM-BC results ---
      # ANCOM-BC uses "taxon" as display name (e.g. "ASV1 - Genus [Family]")
      # and "asv_ids" as the actual ASV identifier
      abc_df <- as.data.frame(abc_res$full_res, stringsAsFactors = FALSE)

      # Extract the ASV ID for merging. asv_ids column has the original ASV id.
      # For single-ASV rows: "ASV1"; for multi (if aggregated): "ASV1, ASV2"
      # We expand multi-ASV entries so each ASV gets its own row for merging.
      abc_expanded <- do.call(rbind, lapply(seq_len(nrow(abc_df)), function(i) {
        ids <- trimws(strsplit(as.character(abc_df$asv_ids[i]), ",")[[1]])
        if (length(ids) == 0 || all(ids == "")) ids <- abc_df$taxon[i]
        data.frame(
          ASV        = ids,
          taxon      = abc_df$taxon[i],
          log2FC     = abc_df$log2FC[i],
          se         = abc_df$se[i],
          W_stat     = abc_df$W_stat[i],
          padj       = abc_df$padj[i],
          enriched_in = abc_df$enriched_in[i],
          stringsAsFactors = FALSE
        )
      }))

      # --- Prepare RF importance ---
      rf_imp <- rf_res$importance
      if (!"ASV" %in% colnames(rf_imp)) rf_imp$ASV <- rownames(rf_imp)

      # ------------------------------------------------------------------
      # Compute Set A (ANCOM-BC significant) and Set B (RF top-N) FROM
      # EACH UPSTREAM TABLE INDEPENDENTLY. This guarantees the panel's
      # counts match what the standalone ANCOM-BC and Random Forest tabs
      # report, even when the two tables don't share every ASV ID
      # (e.g. ANCOM-BC's 10% prevalence filter drops some, or RF's
      # randomForest() mangles names via make.names()).
      # ------------------------------------------------------------------
      # Cutoff resolution: use the user's local override IF the Expert
      # input was actually filled in (mode = expert AND value valid),
      # otherwise inherit the values the user already picked in the
      # standalone ANCOM-BC and Random Forest tabs. This fixes the
      # "ANCOM-BC says 13 hits but ANCOM-BC+RF reports 52" confusion
      # caused by the local defaults silently overriding upstream.
      mode_now <- ezmap_get_mode()
      upstream_log2f <- tryCatch(ancombc_out$log2fc_used(), error = function(e) NULL)
      upstream_padj  <- tryCatch(ancombc_out$alpha_used(),  error = function(e) NULL)
      upstream_top_n <- tryCatch(rf_out$top_n_used(),       error = function(e) NULL)

      padj_cut  <- if (mode_now == "expert" &&
                       !is.null(input$padj_cutoff) &&
                       is.finite(input$padj_cutoff)) {
                       as.numeric(input$padj_cutoff)
                   } else if (!is.null(upstream_padj) && is.finite(upstream_padj)) {
                       as.numeric(upstream_padj)
                   } else { 0.05 }
      log2f_cut <- if (mode_now == "expert" &&
                       !is.null(input$log2fc_cutoff) &&
                       is.finite(input$log2fc_cutoff)) {
                       as.numeric(input$log2fc_cutoff)
                   } else if (!is.null(upstream_log2f) && is.finite(upstream_log2f)) {
                       as.numeric(upstream_log2f)
                   } else { 1 }
      top_n     <- if (mode_now == "expert" &&
                       !is.null(input$rf_top_n) &&
                       is.finite(input$rf_top_n)) {
                       as.numeric(input$rf_top_n)
                   } else if (!is.null(upstream_top_n) && is.finite(upstream_top_n)) {
                       as.numeric(upstream_top_n)
                   } else { 30 }

      # Set A: ANCOM-BC significant ASVs (full table, NOT post-merge)
      abc_sig_mask <- !is.na(abc_expanded$padj) &
                      abc_expanded$padj < padj_cut &
                      !is.na(abc_expanded$log2FC) &
                      abs(abc_expanded$log2FC) > log2f_cut
      abc_sig_asvs <- unique(abc_expanded$ASV[abc_sig_mask])

      # Set B: RF top-N important ASVs (full importance, NOT post-merge)
      rf_top_asvs <- character(0)
      if ("Rank" %in% colnames(rf_imp)) {
        rf_top_asvs <- rf_imp$ASV[!is.na(rf_imp$Rank) & rf_imp$Rank <= top_n]
      }
      if (length(rf_top_asvs) == 0 && "MeanDecreaseGini" %in% colnames(rf_imp)) {
        ord <- order(rf_imp$MeanDecreaseGini, decreasing = TRUE,
                     na.last = NA)
        rf_top_asvs <- rf_imp$ASV[ord[seq_len(min(top_n, length(ord)))]]
      }
      rf_top_asvs <- unique(rf_top_asvs)

      # Overlap between the two standalone sets
      both_asvs <- intersect(abc_sig_asvs, rf_top_asvs)

      # --- Full OUTER join for the display data.frame ---
      # Inner join would silently drop ASVs present in only one table and
      # cause the same under-count bug we just fixed.
      merged <- merge(
        abc_expanded,
        rf_imp[, c("ASV", "MeanDecreaseGini", "Rank")],
        by = "ASV",
        all = TRUE
      )

      # Add taxonomy columns from RF if available
      tax_cols <- intersect(
        c("Kingdom","Phylum","Class","Order","Family","Genus","Species"),
        colnames(rf_res$tax_df))
      if (length(tax_cols) > 0 && !is.null(rf_res$tax_df)) {
        tax_df <- rf_res$tax_df
        if (!"ASV" %in% colnames(tax_df)) tax_df$ASV <- rownames(tax_df)
        tax_subset <- tax_df[, c("ASV", tax_cols), drop = FALSE]
        merged <- merge(merged, tax_subset, by = "ASV", all.x = TRUE)
      }

      # Flag membership using the SET-based definitions (so counts match
      # the standalone tabs even when an ASV is missing from one table).
      merged$ANCOMBC_sig <- merged$ASV %in% abc_sig_asvs
      merged$RF_top      <- merged$ASV %in% rf_top_asvs
      merged$Both        <- merged$ASV %in% both_asvs

      # Diagnostics: how well did the ASV IDs line up?
      n_id_overlap <- length(intersect(abc_expanded$ASV, rf_imp$ASV))
      if (n_id_overlap < min(nrow(abc_expanded), nrow(rf_imp)) * 0.5) {
        showNotification(
          paste0("Heads-up: only ", n_id_overlap, " ASV IDs are shared ",
                 "between ANCOM-BC (", length(unique(abc_expanded$ASV)),
                 ") and RF (", length(unique(rf_imp$ASV)), "). ",
                 "Counts on the cards reflect each method's standalone ",
                 "result; the scatter plot only shows ASVs in both tables."),
          type = "warning", duration = 10)
      }

      # Expose standalone counts via attributes so summary_boxes / venn
      # never recompute them off the (merged) frame.
      attr(merged, "n_abc_sig")   <- length(abc_sig_asvs)
      attr(merged, "n_rf_top")    <- length(rf_top_asvs)
      attr(merged, "n_both")      <- length(both_asvs)
      attr(merged, "n_universe")  <- length(unique(c(abc_expanded$ASV,
                                                     rf_imp$ASV)))
      attr(merged, "n_id_overlap")<- n_id_overlap

      # Sort: overlaps first, then RF rank, then ANCOM-BC sig
      merged <- merged[order(-merged$Both,
                             -merged$RF_top,
                             merged$Rank,
                             -merged$ANCOMBC_sig), ]
      merged
    })

    # ------------------------------------------------------------------
    # Summary boxes
    # ------------------------------------------------------------------
    output$summary_boxes <- renderUI({
      if (is.null(input$run_intersect) || input$run_intersect == 0) {
        return(HTML(paste0(
          "<div style='background:#fff3cd; border-left:5px solid #f0ad4e; padding:10px 14px; border-radius:4px; font-size:13px;'>",
          "Click <b>Compute Intersection</b> to combine the ANCOM-BC and Random Forest results.",
          "</div>")))
      }
      df <- intersection()
      validate(need(!is.null(df),
        "Run ANCOM-BC and Random Forest first, then click Compute Intersection."))

      # Use the standalone counts attached as attributes so the boxes
      # match the ANCOM-BC and RF tabs even when ASV IDs don't fully
      # align between the two upstream tables.
      n_total <- attr(df, "n_universe") %||% nrow(df)
      n_abc   <- attr(df, "n_abc_sig")  %||% sum(df$ANCOMBC_sig, na.rm = TRUE)
      n_rf    <- attr(df, "n_rf_top")   %||% sum(df$RF_top,      na.rm = TRUE)
      n_both  <- attr(df, "n_both")     %||% sum(df$Both,        na.rm = TRUE)

      box <- function(label, value, color) {
        div(style = paste0(
              "display:inline-block; min-width:150px; margin:4px 8px 4px 0;",
              "padding:12px 16px; border-radius:6px; background:", color, "; color:white;"),
            tags$div(style = "font-size:12px; opacity:0.85;", label),
            tags$div(style = "font-size:24px; font-weight:bold;", value))
      }

      div(
        box("ASVs examined",         n_total, "#34495E"),
        box("ANCOM-BC significant",  n_abc,   "#8E44AD"),
        box("RF top-N important",    n_rf,    "#27AE60"),
        box("Overlap (both)",        n_both,  "#E74C3C")
      )
    })

    # ------------------------------------------------------------------
    # Venn plot (two-set: ANCOM-BC vs. RF)
    # ------------------------------------------------------------------
    # ------------------------------------------------------------------
    # Venn plot (publication-quality ggplot version).
    # Was previously base R plot() which:
    #   - rendered jagged at typical screen DPI,
    #   - had no downloadHandler attached (couldn't be saved),
    #   - used non-color-blind-safe greens/purples.
    # Replaced with a ggplot reactive so we can ggsave() it from a
    # download button. Colors switched to a color-blind-safe pair
    # (Okabe-Ito teal + vermillion) per published-figure best practice.
    # ------------------------------------------------------------------
    venn_plot_reactive <- reactive({
      if (is.null(input$run_intersect) || input$run_intersect == 0) {
        return(
          ggplot() + annotate("text", x = 0.5, y = 0.5,
            label = "Venn overlap appears after 'Compute Intersection'.",
            size = 4.5, color = "#7F8C8D") +
          theme_void() + xlim(0,1) + ylim(0,1))
      }
      df <- intersection()
      validate(need(!is.null(df),
        "Run ANCOM-BC and Random Forest first, then click Compute Intersection."))

      n_abc <- attr(df, "n_abc_sig") %||% sum(df$ANCOMBC_sig, na.rm = TRUE)
      n_rf  <- attr(df, "n_rf_top")  %||% sum(df$RF_top,      na.rm = TRUE)
      ab    <- attr(df, "n_both")    %||% sum(df$Both,        na.rm = TRUE)
      a     <- max(0, n_abc - ab)
      b     <- max(0, n_rf  - ab)
      total <- a + b + ab
      pct_overlap <- if (total > 0) round(100 * ab / total, 1) else 0

      # Build circle polygons in long format for ggplot.
      theta <- seq(0, 2 * pi, length.out = 200)
      r     <- 2.2
      circles <- rbind(
          data.frame(x = 3 + r * cos(theta),
                     y = 3 + r * sin(theta),
                     set = "ANCOM-BC"),
          data.frame(x = 6 + r * cos(theta),
                     y = 3 + r * sin(theta),
                     set = "Random Forest")
      )
      # Color-blind-safe Okabe-Ito-ish: teal + vermillion.
      fill_palette <- c("ANCOM-BC" = "#0072B2", "Random Forest" = "#D55E00")
      # Label positions (geometry):
      #   ANCOM-BC circle: center=(3,3) r=2.2 -> spans x in [0.8, 5.2]
      #   RF circle:       center=(6,3) r=2.2 -> spans x in [3.8, 8.2]
      #   ANCOM-BC-only region: x in [0.8, 3.8] -> midpoint 2.3
      #   RF-only region:       x in [5.2, 8.2] -> midpoint 6.7
      #   Overlap region:       x in [3.8, 5.2] -> midpoint 4.5
      # Old positions (1.9 and 8.1) sat near the OUTER edge of each
      # circle instead of in the center of the crescent, so the
      # numbers looked off-center. Now use the true midpoints.
      labels_df <- data.frame(
          x     = c(2.3,             6.7,             4.5),
          y     = c(3.0,             3.0,             3.0),
          label = c(as.character(a), as.character(b), as.character(ab)),
          color = c("#0072B2",       "#D55E00",       "#222222")
      )
      titles_df <- data.frame(
          x     = c(2.3, 6.7),
          y     = c(5.6, 5.6),
          label = c(paste0("ANCOM-BC (", a + ab, ")"),
                    paste0("Random Forest (", b + ab, ")")),
          color = c("#0072B2", "#D55E00")
      )

      ggplot() +
        geom_polygon(data = circles,
                     aes(x = x, y = y, group = set, fill = set),
                     alpha = 0.45, color = NA) +
        geom_polygon(data = circles,
                     aes(x = x, y = y, group = set, color = set),
                     fill = NA, linewidth = 0.9) +
        scale_fill_manual(values = fill_palette,  guide = "none") +
        scale_color_manual(values = fill_palette, guide = "none") +
        geom_text(data = labels_df,
                  aes(x = x, y = y, label = label),
                  color = labels_df$color,
                  size = 7, fontface = "bold") +
        geom_text(data = titles_df,
                  aes(x = x, y = y, label = label),
                  color = titles_df$color,
                  size = 5, fontface = "bold") +
        coord_fixed(xlim = c(0, 10), ylim = c(0, 7), expand = FALSE) +
        labs(title    = "Overlap of ANCOM-BC-significant and RF-important ASVs",
             subtitle = paste0("Overlap = ", ab, " ASVs (",
                               pct_overlap, "% of all flagged taxa)")) +
        theme_void(base_size = 13) +
        # NOTE: ggplot2::margin() must be qualified -- BiocGenerics /
        # base R have a margin() generic that dispatches to
        # margin.default(x, observed, ...). When that wins the
        # namespace contest (which it does once phyloseq's
        # dependencies load), `margin = margin(b = 4)` triggers
        # "argument 'observed' is missing" instead of computing the
        # element_text spacing.
        theme(plot.title    = element_text(face = "bold", hjust = 0.5,
                                           margin = ggplot2::margin(b = 4)),
              plot.subtitle = element_text(hjust = 0.5, color = "#475569",
                                           margin = ggplot2::margin(b = 8)),
              plot.margin   = ggplot2::margin(10, 14, 10, 14))
    })

    output$venn_plot <- renderPlot({ venn_plot_reactive() })

    # Download handler for the Venn plot. Uses the shared
    # ezmap_download_filename helper so the file gets the EzMAP_easy /
    # EzMAP_expert prefix consistent with every other download.
    output$download_venn_png <- downloadHandler(
      filename = function() {
        ezmap_download_filename(input, "ANCOMBC_RF_Venn")
      },
      content = function(file) {
        args  <- download_dims(input, def_width = 8, def_height = 6)
        ggsave(file, plot = venn_plot_reactive(),
               width  = args$width,
               height = args$height,
               units  = args$units,
               dpi    = args$dpi)
      }
    )

    # ------------------------------------------------------------------
    # Scatter: log2FC vs. Mean Decrease Gini
    # ------------------------------------------------------------------
    .clean_taxon_abc <- function(x) {
      x <- as.character(x)
      x[is.na(x)] <- ""
      x <- sub("^D_[0-9]+__", "", x, perl = TRUE)
      x <- sub("^[kpcofgsKPCOFGS]__", "", x, perl = TRUE)
      trimws(x)
    }
    has_ggrepel_abc <- requireNamespace("ggrepel", quietly = TRUE)

    scatter_reactive <- reactive({
      df <- intersection()
      req(df)

      # The merged frame is now a FULL OUTER join — rows that exist in
      # only one of ANCOM-BC / RF have NA for the other side's columns
      # and can't be plotted on a 2-D scatter. Drop those here so the
      # plot stays readable; the summary boxes / Venn / table still see
      # the full set.
      df <- df[!is.na(df$log2FC) & !is.na(df$MeanDecreaseGini), , drop = FALSE]
      validate(need(nrow(df) > 0,
        "No ASVs have both ANCOM-BC and RF values. Make sure the two tabs were run on the same dataset."))

      # -- Cutoff resolution: prefer Expert local override, otherwise
      #    inherit the user's choices from the upstream ANCOM-BC and RF
      #    tabs (so the scatter dashed lines match what those tabs are
      #    showing). See the matching block in the intersection reactive.
      mode_now <- ezmap_get_mode()
      upstream_log2f <- tryCatch(ancombc_out$log2fc_used(), error = function(e) NULL)
      upstream_padj  <- tryCatch(ancombc_out$alpha_used(),  error = function(e) NULL)
      upstream_top_n <- tryCatch(rf_out$top_n_used(),       error = function(e) NULL)
      top_n    <- if (mode_now == "expert" &&
                      !is.null(input$rf_top_n) && is.finite(input$rf_top_n)) {
                      as.numeric(input$rf_top_n)
                  } else if (!is.null(upstream_top_n) && is.finite(upstream_top_n)) {
                      as.numeric(upstream_top_n)
                  } else { 30 }
      padj_cut <- if (mode_now == "expert" &&
                      !is.null(input$padj_cutoff) && is.finite(input$padj_cutoff)) {
                      as.numeric(input$padj_cutoff)
                  } else if (!is.null(upstream_padj) && is.finite(upstream_padj)) {
                      as.numeric(upstream_padj)
                  } else { 0.05 }
      fc_cut   <- if (mode_now == "expert" &&
                      !is.null(input$log2fc_cutoff) && is.finite(input$log2fc_cutoff)) {
                      as.numeric(input$log2fc_cutoff)
                  } else if (!is.null(upstream_log2f) && is.finite(upstream_log2f)) {
                      as.numeric(upstream_log2f)
                  } else { 1 }

      # Gini cutoff = MeanDecreaseGini value of the N-th ranked ASV.
      gini_cut <- NA_real_
      rf_vals  <- sort(df$MeanDecreaseGini[!is.na(df$MeanDecreaseGini)],
                       decreasing = TRUE)
      if (length(rf_vals) > 0 && !is.null(top_n) && is.finite(top_n) && top_n > 0) {
        gini_cut <- rf_vals[min(length(rf_vals), as.integer(top_n))]
      }

      # -- Pull group labels from the ANCOM-BC module -----------------------
      # CRITICAL: the labels MUST match the source whose log2FC sign we
      # are plotting. ANCOM-BC defines log2FC as log2(comp_group / ref_group),
      # so positive log2FC = "comp_group enriched" and negative log2FC
      # = "ref_group enriched". If we instead read group_1 / group_2
      # from the RF module, and the user picked the two groups in a
      # different order on the RF tab (e.g. RF group_1 = Disease while
      # ANCOM-BC ref_group = Control), the legend ends up labelling
      # positive log2FC as "Control-Enriched" — exactly inverting the
      # ANCOM-BC main volcano plot. Sourcing the labels from
      # ancombc_out (whose convention defines the sign) keeps the
      # overlap scatter consistent with the main ANCOM-BC plot.
      abc_res_for_labels <- tryCatch(ancombc_out$ancombc_results(),
                                     error = function(e) NULL)
      grp_ref  <- if (!is.null(abc_res_for_labels) &&
                       !is.null(abc_res_for_labels$ref_group) &&
                       nzchar(abc_res_for_labels$ref_group)) {
                    abc_res_for_labels$ref_group
                  } else "Reference"
      grp_comp <- if (!is.null(abc_res_for_labels) &&
                       !is.null(abc_res_for_labels$comp_group) &&
                       nzchar(abc_res_for_labels$comp_group)) {
                    abc_res_for_labels$comp_group
                  } else "Comparison"

      # -- Classify each ASV -------------------------------------------------
      abc_sig <- !is.na(df$padj) & df$padj < padj_cut &
                 !is.na(df$log2FC) & abs(df$log2FC) > fc_cut
      rf_top  <- !is.na(df$MeanDecreaseGini) &
                 !is.na(gini_cut) & df$MeanDecreaseGini >= gini_cut

      gini_fmt <- if (is.na(gini_cut)) "NA" else signif(gini_cut, 4)
      lbl_ns   <- "Non-Significant"
      lbl_enr  <- paste0("Enriched (MDG < ",  gini_fmt,
                         ", |Log2FC| > ", fc_cut,
                         ", p < ",        padj_cut, ")")
      lbl_ref  <- paste0(grp_ref, "-Enriched (MDG > ", gini_fmt,
                         ", Log2FC < -", fc_cut,
                         ", p < ",       padj_cut, ")")
      lbl_comp <- paste0(grp_comp, "-Enriched (MDG > ", gini_fmt,
                         ", Log2FC > ", fc_cut,
                         ", p < ",      padj_cut, ")")

      df$Category <- ifelse(!abc_sig,                            lbl_ns,
                     ifelse(!rf_top,                              lbl_enr,
                     ifelse(df$log2FC < 0,                        lbl_ref,
                                                                   lbl_comp)))
      df$Category <- factor(df$Category,
                            levels = c(lbl_enr, lbl_ref, lbl_comp, lbl_ns))

      # -- Colors (with user overrides) -------------------------------------
      col_enr  <- if (!is.null(input$col_enr)  && nzchar(input$col_enr))  input$col_enr  else "#8E44AD"
      col_ref  <- if (!is.null(input$col_ref)  && nzchar(input$col_ref))  input$col_ref  else "#1f77b4"
      col_comp <- if (!is.null(input$col_comp) && nzchar(input$col_comp)) input$col_comp else "#E74C3C"
      col_ns   <- if (!is.null(input$col_ns)   && nzchar(input$col_ns))   input$col_ns   else "#7F8C8D"
      pal <- setNames(c(col_enr, col_ref, col_comp, col_ns),
                      c(lbl_enr, lbl_ref, lbl_comp, lbl_ns))

      # -- Display labels for the two top-quadrant categories ---------------
      genus_clean  <- if ("Genus"  %in% colnames(df)) .clean_taxon_abc(df$Genus)  else rep("", nrow(df))
      family_clean <- if ("Family" %in% colnames(df)) .clean_taxon_abc(df$Family) else rep("", nrow(df))
      # Also try the taxon column from ANCOM-BC (contains "ASV1 - Genus [Family]")
      df$.display <- ifelse(
        nzchar(genus_clean),  paste0(genus_clean,  " (", df$ASV, ")"),
        ifelse(
        nzchar(family_clean), paste0(family_clean, " (", df$ASV, ")"),
                              df$ASV))

      lab_df <- df[df$Category %in% c(lbl_ref, lbl_comp), , drop = FALSE]
      n_total <- nrow(df)

      # -- Resolve styling controls (with defaults for Easy mode) -----------
      pt_size   <- as.numeric(input$point_size %||% 2.4)
      lbl_size  <- as.numeric(input$label_size %||% 3.1)
      lbl_alpha <- as.numeric(input$label_opacity %||% 1)
      show_lab  <- isTRUE(input$show_labels %||% TRUE)

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes).
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = "Significance",
                                   base_size = 13)

      # -- Build plot -------------------------------------------------------
      p <- ggplot(df, aes(x = log2FC,
                          y = MeanDecreaseGini,
                          color = Category)) +
        geom_point(alpha = 0.85, size = pt_size) +
        scale_color_manual(values = pal, drop = FALSE, name = NULL) +
        geom_vline(xintercept = c(-fc_cut, fc_cut),
                   linetype = "dashed", color = "grey20") +
        styles$theme_fn(base_size = 13) +
        styles$grid_theme +
        theme(legend.position   = "bottom",
              legend.direction  = "vertical",
              legend.title      = element_blank(),
              legend.text       = element_text(size = 11),
              plot.title        = element_text(face = "bold")) +
        labs(x = expression(Log[2]~Fold~change~(ANCOM-BC)),
             y = "MeanDecreaseGini (RF)",
             title = if (is.null(styles$title)) "ANCOM-BC effect size vs. RF importance" else styles$title)

      if (is.finite(gini_cut)) {
        p <- p + geom_hline(yintercept = gini_cut,
                            linetype = "dashed", color = "grey20")
      }

      if (show_lab && nrow(lab_df) > 0) {
        if (has_ggrepel_abc) {
          p <- p + ggrepel::geom_text_repel(
            data = lab_df,
            aes(x = log2FC, y = MeanDecreaseGini, label = .display),
            size = lbl_size, alpha = lbl_alpha, color = "black",
            box.padding = 0.35, point.padding = 0.25, max.overlaps = 30,
            min.segment.length = 0, show.legend = FALSE,
            inherit.aes = FALSE)
        } else {
          p <- p + geom_text(
            data = lab_df,
            aes(x = log2FC, y = MeanDecreaseGini, label = .display),
            size = lbl_size, alpha = lbl_alpha, color = "black",
            vjust = -0.7, show.legend = FALSE, inherit.aes = FALSE)
        }
      }

      # Bottom-right annotation
      p <- p + annotate("text",
                        x = Inf, y = -Inf,
                        label = paste0("Total = ", n_total, " ASVs"),
                        hjust = 1.05, vjust = -0.8,
                        size = 3.6, color = "grey20",
                        fontface = "italic")
      p
    })

    output$scatter_plot <- renderPlot({
      if (is.null(input$run_intersect) || input$run_intersect == 0) {
        return(
          ggplot() +
            annotate("text", x = 0.5, y = 0.58,
                     label = "Click 'Compute Intersection' to build the Log2FC vs. Gini plot",
                     size = 5.5, fontface = "bold", color = "#8E44AD") +
            annotate("text", x = 0.5, y = 0.45,
                     label = "Run ANCOM-BC and Random Forest in their own tabs first.",
                     size = 4, color = "#7F8C8D") +
            theme_void() + xlim(0, 1) + ylim(0, 1))
      }
      print(scatter_reactive())
    })

    # ------------------------------------------------------------------
    # Intersection table
    # ------------------------------------------------------------------
    output$intersection_table <- DT::renderDataTable({
      if (is.null(input$run_intersect) || input$run_intersect == 0) {
        return(DT::datatable(
          data.frame(Note = "Click 'Compute Intersection' to populate this table."),
          options = list(dom = "t")))
      }
      df <- intersection()
      validate(need(!is.null(df),
        "No intersection available. Ensure ANCOM-BC and Random Forest have been run."))
      show <- df[df$Both, , drop = FALSE]
      if (nrow(show) == 0) {
        return(DT::datatable(
          data.frame(
            Note = "No ASVs are significant in both ANCOM-BC AND in the RF top-N. Try loosening the cutoffs."
          ),
          options = list(dom = "t")))
      }
      # Select display columns
      display_cols <- intersect(
        c("ASV", "taxon", "log2FC", "padj", "enriched_in",
          "MeanDecreaseGini", "Rank",
          "Phylum", "Class", "Order", "Family", "Genus", "Species"),
        colnames(show))
      DT::datatable(
        show[, display_cols, drop = FALSE],
        rownames = FALSE,
        options = list(pageLength = 15, scrollX = TRUE, autoWidth = TRUE),
        caption = "ASVs significant in BOTH ANCOM-BC and Random Forest"
      ) %>%
        DT::formatRound(
          columns = intersect(c("log2FC", "padj", "MeanDecreaseGini"), display_cols),
          digits = 4)
    })

    # ------------------------------------------------------------------
    # Interpretation block
    # ------------------------------------------------------------------
    output$interpretation <- renderUI({
      if (is.null(input$run_intersect) || input$run_intersect == 0) {
        return(HTML(paste0(
          "<div style='background:#fff3cd; border-left:5px solid #f0ad4e; padding:10px 14px; border-radius:4px; font-size:13px;'>",
          "Interpretation appears after 'Compute Intersection'.",
          "</div>")))
      }
      df <- intersection()
      validate(need(!is.null(df), "Intersection not available."))
      n_both <- sum(df$Both, na.rm = TRUE)
      n_abc  <- sum(df$ANCOMBC_sig, na.rm = TRUE)
      n_rf   <- sum(df$RF_top, na.rm = TRUE)

      verdict <- if (n_both == 0) {
        "<span style='color:#E67E22;'><b>No ASV passes both filters</b> at the current cut-offs. Try relaxing the padj or log2FC threshold, or increasing the RF top-N.</span>"
      } else if (n_both < 5) {
        paste0("<span style='color:#27AE60;'><b>A small, high-confidence core of ", n_both,
               " ASVs</b> is flagged by <i>both</i> methods. These are strong biomarker candidates.</span>")
      } else {
        paste0("<span style='color:#27AE60;'><b>", n_both,
               " ASVs</b> are jointly supported by ANCOM-BC and RF — a robust biomarker panel.</span>")
      }

      HTML(paste0(
        "<div style='background:#f8f9fa; border-left:5px solid #8E44AD; padding:12px 16px; border-radius:4px; font-size:13.5px; line-height:1.6;'>",
        "<p>", verdict, "</p>",
        "<ul style='padding-left:20px; margin:0;'>",
        "<li><b>ANCOM-BC</b> tests each taxon for <i>compositional</i> differential abundance, ",
        "correcting for sampling fraction bias. It provides unbiased log2 fold-change estimates ",
        "(Lin &amp; Peddada, 2020).</li>",
        "<li><b>Random Forest</b> ranks ASVs by how much they help classify samples into groups ",
        "(Mean Decrease Gini). Features are <i>predictively</i> associated, not statistically.</li>",
        "<li>The <b>intersection</b> captures taxa that are both statistically differentially ",
        "abundant AND predictively important — far more reliable than either list alone.</li>",
        "<li>RF-selected features may classify groups well but do not necessarily guarantee ",
        "biological relevance. The ANCOM-BC filter adds statistical rigor.</li>",
        "<li>Use these ASVs for downstream validation (qPCR, culture, literature check).</li>",
        "</ul>",
        "</div>"
      ))
    })

    # ------------------------------------------------------------------
    # Method Comparison tab (DESeq2+RF vs ANCOM-BC+RF)
    # ------------------------------------------------------------------
    output$method_comparison <- renderUI({
      HTML(paste0(
        "<div style='padding:12px; font-size:13.5px; line-height:1.7;'>",
        "<h5 style='color:#2C3E50;'>DESeq2 + RF vs ANCOM-BC + RF</h5>",
        "<table style='width:100%; border-collapse:collapse; margin-top:8px;'>",
        "<tr style='background:#F1F5F9;'>",
        "<th style='padding:8px; border:1px solid #E2E8F0; text-align:left;'>Aspect</th>",
        "<th style='padding:8px; border:1px solid #E2E8F0; text-align:left;'>DESeq2 + RF</th>",
        "<th style='padding:8px; border:1px solid #E2E8F0; text-align:left;'>ANCOM-BC + RF</th>",
        "</tr>",

        "<tr>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>Statistical model</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>Negative binomial (Wald test)</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>Bias-corrected linear model on log-counts</td>",
        "</tr>",

        "<tr style='background:#FAFBFC;'>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>Compositionality</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>Not explicitly modeled; relies on library-size normalization</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'><b>Explicitly corrected</b> via sampling fraction estimation</td>",
        "</tr>",

        "<tr>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>Log fold change</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>May be biased by compositionality</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'><b>Unbiased</b> (bias-corrected)</td>",
        "</tr>",

        "<tr style='background:#FAFBFC;'>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>Best for</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>Well-established; widely cited; good for balanced designs</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;'>Microbiome-specific; handles uneven sampling; compositionally aware</td>",
        "</tr>",

        "<tr>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>RF role</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;' colspan='2'>Identical in both — predictive feature ranking by Mean Decrease Gini</td>",
        "</tr>",

        "<tr style='background:#FAFBFC;'>",
        "<td style='padding:8px; border:1px solid #E2E8F0; font-weight:bold;'>Recommendation</td>",
        "<td style='padding:8px; border:1px solid #E2E8F0;' colspan='2'>",
        "Use <b>both</b> and compare: taxa appearing in the overlap of <i>both</i> combined panels ",
        "(DESeq2+RF ∩ ANCOM-BC+RF) are the highest-confidence biomarker candidates.</td>",
        "</tr>",

        "</table>",
        "</div>"
      ))
    })

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    output$download_intersection_csv <- downloadHandler(
      filename = function() ezmap_filename("ANCOMBC_RF_Intersection", "csv"),
      content = function(file) {
        df <- intersection()
        req(df)
        write.csv(df, file, row.names = FALSE)
      }
    )

    output$download_scatter_png <- downloadHandler(
      filename = function() ezmap_download_filename(input, "ANCOMBC_RF_Scatter"),
      content = function(file) {
        p <- scatter_reactive()
        req(p)
        d <- download_dims(input, def_width = 10, def_height = 7)
        ggsave(file, plot = p,
               width = d$width, height = d$height, units = d$units, dpi = d$dpi)
      }
    )
  })
}
