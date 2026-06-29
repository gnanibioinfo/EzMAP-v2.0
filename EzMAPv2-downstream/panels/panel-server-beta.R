# panels/panel-server-beta.R — Beta Diversity Server Logic (FINAL VERSION)
betaDiversityServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
    moduleServer(id, function(input, output, session) {

        # --- Dataset selector (Raw vs Filtered) ---
        physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

        # --- 1. FULL Preprocessing (Filtering & CSS Normalization) ---
        physeq_css_reactive <- reactive({
            Abundance_raw <- physeq_data() 
            req(Abundance_raw)

            Bacteria <- Abundance_raw

            # 1.1 Robustness Checks
            if (is.null(otu_table(Bacteria)) || is.null(tax_table(Bacteria))) {
                warning("Missing ASV or Tax table in the phyloseq object.")
                return(NULL)
            }

            # 1.2 Taxa naming
            # NOTE: Do NOT rename taxa here. Canonical "ASV1..ASV(N_raw)" IDs
            # are assigned once at upload (panel-server-data.R) and preserved
            # by the Filter tab. Local renames re-number the surviving taxa
            # to "ASV1..ASV(local_n)", silently desyncing beta-diversity IDs
            # from ANCOM-BC / DESeq2 / RF / LeFSe and breaking any
            # cross-panel comparison or overlap. Rename removed.

            # 1.3 Change the Taxonomy Ranks (defensive — central upload
            #     also does this, but if a custom phyloseq comes in with
            #     non-standard column names we still want them normalised.)
            if (ncol(tax_table(Bacteria)) >= 7) {
                 colnames(tax_table(Bacteria)) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")[1:ncol(tax_table(Bacteria))]
            }

            # 1.4 NOTE: NO local taxa filtering.
            # The central Filter tab is the single source of truth for
            # taxa filtering (chloroplast / mitochondria / Eukaryota /
            # Archaea / abundance / prevalence / custom exclusions).
            # Previously this panel re-ran subset_taxa() with hard-coded
            # exclusions:
            #     subset_taxa(!grepl("Eukaryota|Archaea", Kingdom))
            # which silently dropped every fungal ASV in ITS datasets
            # (fungi are Eukaryota), making Beta show zero taxa for all
            # ITS runs. It also duplicated the central Filter tab's
            # work for 16S, leading to "filtered data not loading"
            # confusion when the user's central thresholds didn't
            # match this panel's hard-coded ones. Whatever the user
            # configures in the Filter tab is now what Beta uses.

            # Strip taxonomy prefixes — defensive only. The central
            # upload step (panel-server-data.R) already strips D_x__
            # and [dkpcofgs]__ prefixes, so this is a no-op on standard
            # uploads but kicks in for custom-imported phyloseqs.
            tax_mat <- as(tax_table(Bacteria), "matrix")
            tax_mat[,] <- gsub("[Dd]_[0-9]+__", "", tax_mat[,])
            tax_mat[,] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_mat[,])
            tax_mat[,] <- trimws(tax_mat[,])
            tax_table(Bacteria) <- tax_table(tax_mat)

            # 1.5 NO local abundance filtering — already handled by the
            #     Filter tab. Use the data as-received.
            Abundance_filtered <- Bacteria
            req(Abundance_filtered)

            # --- 1.6 Normalization ---
            # NOTE: Previously this panel ran metagenomeSeq CSS log-
            # normalization (phyloseq_to_metagenomeSeq + MRcounts(norm=TRUE,
            # log=TRUE)). On some metagenomeSeq / phyloseq version pairs that
            # silently dropped taxa (we saw 4648 → 1765 in a real ITS run),
            # which made Beta diverge from the Filter tab's ASV count and
            # confused users.
            #
            # The methodologically standard practice for amplicon
            # beta-diversity is:
            #   • Bray-Curtis / Jaccard / Euclidean: vegan::vegdist
            #     normalizes internally (relative abundance), so passing
            #     raw counts is correct.
            #   • Weighted / Unweighted UniFrac: phyloseq::UniFrac handles
            #     its own normalization on the tree, raw counts are also
            #     fine; rarefied data (from the Rarefaction tab) is even
            #     better when sequencing depth varies a lot.
            #
            # So we now pass the centrally-filtered phyloseq through
            # unchanged. The ASV count Beta uses == the count the Filter
            # tab reports. If a user wants explicit CSS normalization,
            # they can rarefy in the Rarefaction tab first or run a
            # downstream-specific normalization themselves.
            n_taxa_in    <- ntaxa(Abundance_filtered)
            n_samples_in <- nsamples(Abundance_filtered)
            Bacteria_css <- Abundance_filtered

            # Surface the count clearly so any future regression is
            # visible at a glance — input vs. post-processing must match.
            showNotification(
                paste0("Beta data ready: ", ntaxa(Bacteria_css),
                       " ASVs / ", nsamples(Bacteria_css), " samples ",
                       "(matches Filter tab)."),
                type = "message", duration = 6
            )

            return(Bacteria_css)
        })

        # --- 2. Dynamic UI for Grouping Variables ---
        output$group_variable_ui <- renderUI({ 
            pseq <- physeq_css_reactive()
            req(pseq)
            metadata <- as(sample_data(pseq), "data.frame")
            
            group_vars <- names(metadata)[sapply(metadata, function(x) (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
            
            if (length(group_vars) == 0) {
                return(tagList(
                    p("No valid grouping variables (factors with > 1 unique level) found in metadata."),
                    selectInput(session$ns("group_variable"), "Select Grouping Variable:", choices = NULL)
                ))
            }
            
            selectInput(session$ns("group_variable"), "Select Grouping Variable:",
                        choices = group_vars,
                        selected = group_vars[1])
        })

        # ----- Color/Fill variable selector -----
        # Optional second metadata variable used for point fill color.
        # When "Same as Group" is selected (default), legacy behavior:
        # color = group_variable, the same one used for PERMANOVA and
        # ellipses. When a different variable is picked, color
        # decouples from the statistical group -- e.g. user can run
        # PERMANOVA by `condition` while coloring points by `time` to
        # visualize temporal drift within each condition.
        output$color_variable_ui <- renderUI({
            pseq <- physeq_css_reactive()
            req(pseq)
            metadata <- as(sample_data(pseq), "data.frame")
            # Allow numeric variables here too -- a continuous color
            # gradient (e.g. by time as integer or pH) is a useful
            # visualization that doesn't make sense for the Group var.
            color_vars <- names(metadata)[sapply(metadata,
                function(x) length(unique(x)) > 1)]
            selectInput(session$ns("color_variable"),
                        "Color/Fill by (optional):",
                        choices  = c("Same as Group" = "same", color_vars),
                        selected = "same")
        })

        # ----- Custom-drag UI for color-variable level order -----
        # When color = a categorical variable with values like T1..T13,
        # alphabetical sort puts T10 before T2. This lets the user drag
        # them into their preferred order, which then gets applied as
        # factor levels at plot time. Mirrors alpha's customGroupLevelOrder.
        output$custom_color_level_order_ui <- renderUI({
            pseq <- physeq_css_reactive()
            req(pseq, input$color_variable)
            # Resolve the variable that color is actually using --
            # "same" falls through to the group variable.
            cv <- input$color_variable
            if (is.null(cv) || cv == "same") cv <- input$group_variable
            req(cv)
            metadata <- as(sample_data(pseq), "data.frame")
            if (!cv %in% colnames(metadata)) return(NULL)
            lvls <- unique(as.character(metadata[[cv]]))
            # Try a "natural" sort first (T1 < T2 < T10) using gtools
            # if available; fall back to default sort.
            lvls_sorted <- if (requireNamespace("gtools", quietly = TRUE)) {
                gtools::mixedsort(lvls)
            } else {
                # Manual natural sort: extract trailing digits and sort
                # numerically. Works for "T1", "Day 5", "Sample10" patterns.
                num_part <- as.numeric(gsub("[^0-9]", "", lvls))
                lvls[order(ifelse(is.na(num_part), Inf, num_part), lvls)]
            }
            selectizeInput(
                session$ns("custom_color_level_order"),
                "Drag to reorder color legend:",
                choices  = lvls_sorted,
                selected = lvls_sorted,
                multiple = TRUE,
                options  = list(
                    plugins = list("drag_drop", "remove_button"),
                    placeholder = "Drag levels into desired order..."
                )
            )
        })
        
        # --- Placeholder UI for Status ---
        output$pcoa_plot_status <- renderUI({
             pseq <- physeq_css_reactive()
             if (is.null(pseq)) {
                 return(h4(strong("... Waiting for data upload and preprocessing ..."), style="color: grey;"))
             }
             if (is.null(input$group_variable)) {
                 return(h4(strong("... Select a grouping variable to enable the Run Analysis button ..."), style="color: orange;"))
             }
             return(NULL) 
        })
        
        # --- 2b. Dynamic UI for Facet Variable (within-group analysis) ---
        output$facet_variable_ui <- renderUI({
            pseq <- physeq_css_reactive()
            req(pseq, input$group_variable)

            metadata <- as(sample_data(pseq), "data.frame")
            all_vars <- names(metadata)[sapply(metadata, function(x)
                (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
            facet_choices <- setdiff(all_vars, input$group_variable)

            tagList(
                selectInput(session$ns("facet_variable"),
                            "Facet by (within-group comparison):",
                            choices = c("None" = "none", facet_choices),
                            selected = "none"),
                helpText(style = "font-size:10.5px; color:#64748B; margin-top:-4px;",
                         "Split the ordination into panels. E.g. facet by Condition, ",
                         "color by TimePoint to see how timepoints differ within each condition.")
            )
        })

        # --- 2c. Dynamic UI for Shape Variable (optional) ---
        output$shape_variable_ui <- renderUI({
            pseq <- physeq_css_reactive()
            req(pseq, input$group_variable)

            metadata <- as(sample_data(pseq), "data.frame")
            all_vars <- names(metadata)[sapply(metadata, function(x)
                (is.factor(x) || is.character(x)) && length(unique(x)) > 1 && length(unique(x)) <= 6)]
            shape_choices <- setdiff(all_vars, input$group_variable)

            selectInput(session$ns("shape_variable"),
                        "Shape by (optional):",
                        choices = c("None" = "none", shape_choices),
                        selected = "none")
        })

        # --- 3. Dynamic UI for Extra Variables ---
        output$extra_variables_ui <- renderUI({
             pseq <- physeq_css_reactive()
             req(pseq, input$group_variable) 
             
             metadata <- as(sample_data(pseq), "data.frame")
             all_vars <- names(metadata)[sapply(metadata, function(x) (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
             extra_vars_choices <- setdiff(all_vars, input$group_variable)
             
             selectInput(session$ns("extra_variables"), "Select Additional Variable(s) for Two-Way PERMANOVA (Optional):",
                         choices = extra_vars_choices,
                         multiple = TRUE)
        })

        # --- 3.5 Dynamic Ellipse Controls UI (New) ---
        output$ellipse_controls_ui <- renderUI({
            ns <- session$ns

            # Handle expert-only show_ellipses input with default TRUE
            show_ellipses_ui <- if (is.null(input$show_ellipses)) TRUE else input$show_ellipses
            if (isTRUE(show_ellipses_ui)) {
                tagList(
                    # Ellipse Type
                    selectInput(ns("ellipse_type"), "Ellipse Type:",
                                choices = c("Normal Distribution" = "norm",
                                            "T-Distribution" = "t",
                                            "Euclidean" = "euclid"),
                                selected = "norm"),
                    
                    # Ellipse Confidence Level
                    numericInput(ns("ellipse_level"), "Ellipse Confidence Level (0-1):", 0.95, min = 0, max = 1, step = 0.05),
                    
                    # Ellipse Line Thickness
                    sliderInput(ns("ellipse_size"), "Ellipse Line Thickness:", min = 0.5, max = 3, value = 1, step = 0.5)
                )
            }
        })
        
        # --- 4. Reactive Analysis Results (PCoA/NMDS, PERMANOVA) ---
        analysis_results <- eventReactive(input$run_analysis, {
            pseq <- physeq_css_reactive()
            req(pseq, input$group_variable)

            # Handle expert-only dist_method with default fallback
            dist_method <- if (is.null(input$dist_method)) "bray" else input$dist_method

            ord_method <- if (!is.null(input$ordination_method) &&
                              nzchar(input$ordination_method)) input$ordination_method else "PCoA"

            withProgress(message = 'Running Beta Diversity Analysis...', value = 0, {

                is_weighted <- (dist_method == "wunifrac")

                # --- Beta Diversity Distance Calculation ---
                incProgress(0.2, detail = paste("Calculating", dist_method, "distance..."))

                if (dist_method %in% c("unifrac", "wunifrac")) {
                    if (is.null(phy_tree(pseq))) {
                        stop("Phylogenetic tree is required for UniFrac methods.")
                    }
                    beta_dist <- tryCatch({
                        phyloseq::distance(pseq, method = dist_method, weighted = is_weighted)
                    }, error = function(e) {
                        showNotification(paste("Distance calculation failed:", e$message), type = "error")
                        stop("Distance calculation failed. Check data/tree integrity.")
                    })
                } else {
                    beta_dist <- phyloseq::distance(pseq, method = dist_method)
                }

                # --- Ordination (PCoA or NMDS) ---
                incProgress(0.4, detail = paste("Performing", ord_method, "ordination..."))
                ordination <- tryCatch({
                    if (ord_method == "NMDS") {
                        # Call vegan::metaMDS directly on the precomputed distance
                        # matrix. Phyloseq's ordinate() does this internally but
                        # some version combinations choke on trymax/autotransform
                        # args being relayed through. Using metaMDS directly with
                        # wascores=FALSE (no community matrix available) and
                        # trace=0 (quiet) is the most robust path.
                        if (!inherits(beta_dist, "dist")) beta_dist <- as.dist(beta_dist)
                        # Guard against degenerate distance matrices (duplicate
                        # samples → zero distances) that make NMDS non-converge.
                        n_samples <- attr(beta_dist, "Size")
                        if (is.null(n_samples) || n_samples < 4) {
                            stop("NMDS needs at least 4 samples; the current subset has ", n_samples, ".")
                        }
                        vegan::metaMDS(
                            beta_dist,
                            k        = 2,
                            try      = 20,
                            trymax   = 50,
                            wascores = FALSE,
                            trace    = 0
                        )
                    } else {
                        phyloseq::ordinate(pseq, method = "PCoA", distance = beta_dist)
                    }
                }, error = function(e) {
                    showNotification(paste0(ord_method, " ordination failed: ", e$message),
                                     type = "error", duration = 8)
                    NULL
                })
                req(!is.null(ordination))

                # --- PERMANOVA Setup and Run ---
                incProgress(0.6, detail = "Running PERMANOVA (Adonis2)...")
                metadata <- as(sample_data(pseq), "data.frame")

                # Ensure grouping variable is a factor
                metadata[[input$group_variable]] <- factor(metadata[[input$group_variable]])

                # Build formula variables list
                formula_vars <- c(input$group_variable, input$extra_variables)

                # FIX: Use " + " (additive model) to prevent model saturation (Df=0)
                formula_str <- paste("beta_dist ~", paste(formula_vars, collapse = " + "))

                for (var in formula_vars) {
                    if (!is.factor(metadata[[var]]) & !is.numeric(metadata[[var]])) {
                        metadata[[var]] <- factor(metadata[[var]])
                    }
                }

                permanova_result <- vegan::adonis2(as.formula(formula_str),
                                                   data = metadata,
                                                   permutations = 999,
                                                   method = dist_method,
                                                   by = "terms")

                # --- Per-facet (stratified) PERMANOVA when facet variable is set ---
                facet_var <- if (is.null(input$facet_variable)) "none" else input$facet_variable
                facet_permanova <- NULL
                if (facet_var != "none" && facet_var %in% colnames(metadata)) {
                    facet_levels <- unique(as.character(metadata[[facet_var]]))
                    facet_permanova <- lapply(facet_levels, function(lv) {
                        idx <- which(metadata[[facet_var]] == lv)
                        if (length(idx) < 4) return(NULL)  # need minimum samples
                        sub_dist <- as.dist(as.matrix(beta_dist)[idx, idx])
                        sub_meta <- metadata[idx, , drop = FALSE]
                        sub_formula <- paste("sub_dist ~", input$group_variable)
                        tryCatch(
                            vegan::adonis2(as.formula(sub_formula),
                                          data = sub_meta,
                                          permutations = 999,
                                          by = "terms"),
                            error = function(e) NULL
                        )
                    })
                    names(facet_permanova) <- facet_levels
                }

                # --- NMDS-specific extras (stress + stressplot input) ---
                nmds_stress <- if (ord_method == "NMDS" && !is.null(ordination$stress)) {
                    as.numeric(ordination$stress)
                } else NA_real_

                incProgress(1.0, detail = "Analysis complete!")
            })

            return(list(ordination       = ordination,
                        ord_method       = ord_method,
                        permanova        = permanova_result,
                        facet_permanova  = facet_permanova,
                        pseq             = pseq,
                        beta_dist        = beta_dist,
                        nmds_stress      = nmds_stress))
        }, ignoreInit = TRUE)
        
        # --- 5. Reactive PCoA Plot Generation (Fully Customizable) ---
pcoa_plot_reactive <- reactive({
  # Friendly pre-run placeholder so we don't dump a red error box on first load.
  if (is.null(input$run_analysis) || input$run_analysis == 0) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.55,
                 label = "Select a grouping variable and click 'Run Analysis'",
                 size = 5.5, fontface = "bold", color = "#3B82F6") +
        annotate("text", x = 0.5, y = 0.45,
                 label = "The ordination plot and PERMANOVA results will appear here.",
                 size = 4, color = "#7F8C8D") +
        theme_void() + xlim(0, 1) + ylim(0, 1)
    )
  }
  results <- analysis_results()
  validate(need(!is.null(results), "Analysis did not return results. Please check your inputs and try again."))

  pseq <- results$pseq
  ordination <- results$ordination
  validate(
    need(!is.null(pseq),       "Phyloseq object is empty after preprocessing."),
    need(!is.null(ordination), "Ordination failed. Try a different distance method or check sample counts.")
  )

  ord_method <- if (!is.null(results$ord_method)) results$ord_method else "PCoA"

  # --- Axis labels: % variance for PCoA, raw axis names for NMDS ---
  axis1_lab <- "Axis 1"; axis2_lab <- "Axis 2"
  if (ord_method == "PCoA" && !is.null(ordination$values$Relative_eig)) {
    eig <- ordination$values$Relative_eig
    axis1_var <- round(eig[1] * 100, 1)
    axis2_var <- round(eig[2] * 100, 1)
    axis1_lab <- paste0("PCoA 1 (", axis1_var, "%)")
    axis2_lab <- paste0("PCoA 2 (", axis2_var, "%)")
  } else if (ord_method == "NMDS") {
    axis1_lab <- "NMDS 1"
    axis2_lab <- "NMDS 2"
  }

  group_var <- input$group_variable
  group_count <- length(unique(sample_data(pseq)[[group_var]]))

  # Color/Fill variable resolution (moved up so the palette is sized
  # for the correct variable's level count -- otherwise picking
  # color = time on a 13-level time variable with a 4-level palette
  # causes recycled colors).
  raw_color_var <- if (is.null(input$color_variable)) "same" else input$color_variable
  use_separate_color <- !is.null(raw_color_var) &&
                        nzchar(raw_color_var) &&
                        raw_color_var != "same" &&
                        raw_color_var != group_var &&
                        raw_color_var %in% names(as(sample_data(pseq), "data.frame"))
  color_var   <- if (use_separate_color) raw_color_var else group_var

  # Apply user-chosen level order to the color variable. Without this,
  # categorical values like T1..T13 sort alphabetically in the legend
  # (T1, T10, T11, T12, T13, T2, T3...). Order options:
  #   default -- as in metadata (existing factor levels)
  #   alpha   -- alphabetical
  #   custom  -- user-dragged order (mirrors alpha-tab pattern)
  c_order <- if (is.null(input$color_level_order)) "default" else input$color_level_order
  if (c_order != "default") {
      sd <- sample_data(pseq)
      raw_levels <- as.character(sd[[color_var]])
      new_levels <- if (c_order == "alpha") {
          sort(unique(raw_levels))
      } else if (c_order == "custom" && !is.null(input$custom_color_level_order)) {
          custom <- input$custom_color_level_order
          c(custom, setdiff(unique(raw_levels), custom))
      } else {
          unique(raw_levels)
      }
      sd[[color_var]] <- factor(raw_levels, levels = new_levels)
      sample_data(pseq) <- sd
  }
  color_count <- length(unique(sample_data(pseq)[[color_var]]))

  # --- Color Palette (expert-only input with default) ---
  # Palette is sized to color_count, not group_count -- so a color
  # variable with more levels than the group variable gets enough
  # distinct colors to be readable.
  palette <- if (is.null(input$palette)) "Set1" else input$palette
  if (palette == "Viridis") {
    color_scale <- scale_color_viridis_d()
    fill_scale  <- scale_fill_viridis_d()
  } else {
    max_colors <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
    if (color_count <= max_colors) {
      palette_colors <- RColorBrewer::brewer.pal(max(color_count, 3),
                                                 palette)[seq_len(color_count)]
    } else {
      palette_colors <- colorRampPalette(RColorBrewer::brewer.pal(max_colors,
                                                                  palette))(color_count)
    }
    color_scale <- scale_color_manual(values = palette_colors)
    fill_scale  <- scale_fill_manual(values  = palette_colors)
  }

  # When color and group are different variables, the fill_scale built
  # above is sized for the color variable's levels -- but ellipses use
  # group_var as their fill aesthetic, so they need a scale sized for
  # group_count (otherwise ggplot warns about unmatched aesthetics).
  # Separate ellipse_fill_scale handles this.
  if (use_separate_color) {
      if (palette == "Viridis") {
          ellipse_fill_scale <- scale_fill_viridis_d(aesthetics = "fill",
                                                     guide = "none")
      } else {
          max_colors_g <- RColorBrewer::brewer.pal.info[palette, "maxcolors"]
          ellipse_palette <- if (group_count <= max_colors_g) {
              RColorBrewer::brewer.pal(max(group_count, 3),
                                       palette)[seq_len(group_count)]
          } else {
              colorRampPalette(RColorBrewer::brewer.pal(max_colors_g,
                                                        palette))(group_count)
          }
          ellipse_fill_scale <- scale_fill_manual(values = ellipse_palette,
                                                  guide  = "none")
      }
  } else {
      ellipse_fill_scale <- fill_scale
  }

  # --- Build the ordination plot (works for PCoA and NMDS via phyloseq) ---
  dist_method_title <- if (is.null(input$dist_method)) "bray" else input$dist_method
  # Auto-title acknowledges the dual encoding when color and group differ:
  # "PCoA (bray) by condition (coloured by time)" reads naturally.
  title_txt <- if (use_separate_color) {
    paste0(ord_method, " (", dist_method_title, " distance) by ",
           group_var, " (coloured by ", color_var, ")")
  } else {
    paste0(ord_method, " (", dist_method_title, " distance) by ", group_var)
  }
  if (ord_method == "NMDS" && isTRUE(is.finite(results$nmds_stress))) {
    title_txt <- paste0(title_txt,
                        "    (stress = ",
                        formatC(results$nmds_stress, format = "f", digits = 3), ")")
  }

  # --- Expert-only plot customization inputs with defaults ---
  point_size <- if (is.null(input$point_size)) 3 else input$point_size
  baseFontSize <- if (is.null(input$baseFontSize)) 14 else input$baseFontSize
  axisLabelSize <- if (is.null(input$axisLabelSize)) 12 else input$axisLabelSize
  xAngle <- if (is.null(input$xAngle)) 45 else input$xAngle
  legendPosition <- if (is.null(input$legendPosition)) "right" else input$legendPosition
  legendCols <- if (is.null(input$legendCols)) 1 else input$legendCols

  # NOTE: color/fill variable resolution is now done above (just after
  # group_var assignment) so the palette can be sized correctly. This
  # block previously duplicated that logic; removed.

  # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
  # legend title/text sizes). User-supplied plot title overrides the
  # auto-generated default. Default legend title now reflects which
  # variable is driving the COLOR aesthetic so legends read sensibly.
  styles <- ezmap_plot_styling(input,
                               default_legend_title = color_var,
                               base_size = baseFontSize)

  # --- Shape variable (expert-only, with default) ---
  shape_var <- if (is.null(input$shape_variable)) "none" else input$shape_variable

  # --- Build the ordination plot ---
  if (shape_var != "none" && shape_var %in% names(as(sample_data(pseq), "data.frame"))) {
    p <- phyloseq::plot_ordination(pseq, ordination, color = color_var, shape = shape_var) +
         geom_point(size = point_size)
  } else {
    p <- phyloseq::plot_ordination(pseq, ordination, color = color_var) +
         geom_point(size = point_size)
  }

  p <- p +
       styles$theme_fn(base_size = baseFontSize) +
       styles$grid_theme +
       theme(
         axis.text.x = element_text(size = axisLabelSize, angle = xAngle, hjust = 1),
         axis.text.y = element_text(size = axisLabelSize),
         legend.position = legendPosition,
         plot.title  = element_text(face = "bold", hjust = 0.5)
       ) +
       guides(color = guide_legend(ncol = legendCols),
              fill  = guide_legend(ncol = legendCols)) +
       color_scale +
       labs(title = if (is.null(styles$title)) title_txt else styles$title,
            x = axis1_lab, y = axis2_lab,
            color = styles$legend_title,
            fill = styles$legend_title)

  # --- Conditional Ellipses (guard against NULL inputs for expert-only parameters) ---
  show_ellipses <- if (is.null(input$show_ellipses)) TRUE else input$show_ellipses
  ellipse_type <- if (is.null(input$ellipse_type)) "t" else input$ellipse_type
  ellipse_level <- if (is.null(input$ellipse_level)) 0.95 else input$ellipse_level
  ellipse_size <- if (is.null(input$ellipse_size)) 0.5 else input$ellipse_size

  if (isTRUE(show_ellipses)) {
    p <- tryCatch({
      # NOTE: previously used aes_string(fill = group_var) which is
      # deprecated in ggplot2 >= 3.0 and could throw a lazy-evaluation
      # error on the FIRST render of the panel ("error in evaluating the
      # argument 'x' in selecting a method for function 'print'") —
      # forcing the user to click Run Analysis a second time. Switching
      # to aes(fill = .data[[group_var]]) evaluates the column name
      # eagerly against the layer's data and is the documented
      # replacement, so the plot renders correctly on the first click.
      p +
        stat_ellipse(
          geom    = "polygon",
          level   = ellipse_level,
          type    = ellipse_type,
          alpha   = 0.2,
          mapping = aes(fill = .data[[group_var]]),
          size    = ellipse_size
        ) +
        ellipse_fill_scale
    }, error = function(e) {
      # Ellipses can fail with too few points per group -- fall back to plain plot
      showNotification(paste("Ellipses skipped:", e$message), type = "warning", duration = 5)
      p + ellipse_fill_scale
    })
  }

  # --- Faceting (within-group comparison) ---
  facet_var <- if (is.null(input$facet_variable)) "none" else input$facet_variable
  if (facet_var != "none") {
    ord_df <- p$data
    if (facet_var %in% colnames(ord_df)) {
      p <- p + facet_wrap(as.formula(paste("~", facet_var)), scales = "free")
    }
  }

  p
})

# --- 5.1 Plot Output ---
# History: previously a single click on "Run Analysis" would render a plot
# error and a second click was needed before the plot appeared. Two issues
# combined to cause that:
#   (a) aes_string() was used inside stat_ellipse — deprecated and lazy
#       in ggplot2 >= 3.0, sometimes failing on first eval (fixed above).
#   (b) renderPlot called pcoa_plot_reactive() before analysis_results()
#       had finished settling, then displayed any error verbatim.
# We now (1) gate explicitly on input$run_analysis and on analysis_results()
# being non-null, and (2) any residual error during plot construction is
# shown as a friendly retry message instead of a red error box.
output$pcoa_plot <- renderPlot({
  if (is.null(input$run_analysis) || input$run_analysis == 0) {
    return(
      ggplot() + theme_void() +
        annotate("text", x = 0.5, y = 0.55,
                 label = "Click 'Run Analysis' to generate the ordination plot.",
                 size = 5.5, fontface = "bold", color = "#3B82F6") +
        annotate("text", x = 0.5, y = 0.45,
                 label = "PERMANOVA results will appear in the Statistics panel.",
                 size = 4, color = "#7F8C8D") +
        xlim(0, 1) + ylim(0, 1)
    )
  }

  # Wait for the eventReactive to settle. req() pauses this output (no
  # error frame shown) until analysis_results() returns a non-null list
  # with both pseq and ordination — eliminates the first-click race.
  results <- analysis_results()
  req(results, results$pseq, results$ordination)

  p <- tryCatch(pcoa_plot_reactive(), error = function(e) {
    msg <- e$message
    # Any lingering first-render glitch — fall through with a friendly
    # message rather than a red error block.
    ggplot() + theme_void() +
      annotate("text", x = 0.5, y = 0.55,
               label = "Rendering ordination…",
               size = 5, color = "#3B82F6") +
      annotate("text", x = 0.5, y = 0.45,
               label = paste("(", msg, " — click Run Analysis to retry)"),
               size = 3.5, color = "#7F8C8D") +
      xlim(0, 1) + ylim(0, 1)
  })
  req(p)
  p
}, res = 100)

# --- 5.1b Dynamic header above the plot ---
output$ordination_header <- renderUI({
  ord_method <- if (!is.null(input$ordination_method)) input$ordination_method else "PCoA"
  label <- if (ord_method == "NMDS") "Non-metric Multidimensional Scaling (NMDS)"
           else "Principal Coordinate Analysis (PCoA)"
  h5(label)
})

# --- 5.2 PCoA Plot Download Handler (with full customization) ---
output$downloadPcoaPlot <- downloadHandler(
  filename = function() {
    dist_for_filename <- if (is.null(input$dist_method)) "bray" else input$dist_method
    ezmap_download_filename(input, paste0("PCoA_", dist_for_filename))
  },
  content = function(file) {
    p <- pcoa_plot_reactive()
    req(p)

    # Expert-only download customization inputs with defaults
    width <- if (is.null(input$downloadWidth)) 10 else input$downloadWidth
    height <- if (is.null(input$downloadHeight)) 8 else input$downloadHeight
    units <- if (is.null(input$downloadUnits)) "in" else input$downloadUnits
    dpi <- if (is.null(input$downloadDPI)) 300 else input$downloadDPI

    ggplot2::ggsave(file, plot = p, width = width, height = height, units = units, dpi = dpi)
  }
)

        
        # --- 6. PERMANOVA Result Outputs ---
        output$permanova_result <- renderPrint({
            if (is.null(input$run_analysis) || input$run_analysis == 0) {
                cat("Ordination & PERMANOVA results will appear here after you click 'Run Analysis'.\n")
                return(invisible(NULL))
            }
            results <- analysis_results()
            validate(need(!is.null(results),
                          "Analysis did not return results. Please check your inputs."))

            ord_method <- if (!is.null(results$ord_method)) results$ord_method else "PCoA"

            # --- Ordination summary block ---
            dist_summary <- if (is.null(input$dist_method)) "bray" else input$dist_method
            cat("Ordination method: ", ord_method, "\n", sep = "")
            cat("Distance metric:   ", dist_summary, "\n", sep = "")
            if (ord_method == "NMDS") {
                stress <- results$nmds_stress
                if (isTRUE(is.finite(stress))) {
                    cat("NMDS stress:       ", formatC(stress, format = "f", digits = 4), "\n", sep = "")
                    interp <- if (stress < 0.05) "excellent fit"
                              else if (stress < 0.10) "good fit"
                              else if (stress < 0.20) "acceptable fit"
                              else                    "poor fit — interpret with caution"
                    cat("Interpretation:    ", interp, "\n", sep = "")
                }
            } else if (ord_method == "PCoA" && !is.null(results$ordination$values$Relative_eig)) {
                eig <- results$ordination$values$Relative_eig
                cat("Variance explained: Axis 1 = ",
                    formatC(eig[1] * 100, format = "f", digits = 1), "% ; Axis 2 = ",
                    formatC(eig[2] * 100, format = "f", digits = 1), "%\n", sep = "")
            }

            cat("\nPERMANOVA (Adonis2) Results — Overall:\n")
            cat("--------------------------------------\n")

            # Display the actual formula used
            formula_vars <- c(input$group_variable, input$extra_variables)
            formula_str <- paste("Distance ~", paste(formula_vars, collapse = " + "))

            cat("Formula:", formula_str, "\n\n")
            print(results$permanova)

            # --- Per-facet (stratified) PERMANOVA results ---
            if (!is.null(results$facet_permanova)) {
                facet_var <- if (is.null(input$facet_variable)) "none" else input$facet_variable
                cat("\n\n========================================\n")
                cat("Stratified PERMANOVA — within each level of '", facet_var, "':\n", sep = "")
                cat("========================================\n")
                cat("Testing: ", input$group_variable, " differences within each ", facet_var, " level\n\n", sep = "")

                for (lv in names(results$facet_permanova)) {
                    cat("--- ", facet_var, " = ", lv, " ---\n", sep = "")
                    res <- results$facet_permanova[[lv]]
                    if (is.null(res)) {
                        cat("  Skipped: too few samples in this group.\n\n")
                    } else {
                        print(res)
                        cat("\n")
                    }
                }
            }
        })

        # --- 7. AI-Style Interpretation ---
        output$beta_interpretation <- renderUI({
            if (is.null(input$run_analysis) || input$run_analysis == 0) {
                return(HTML(
                    "<div style='background:#fff3cd; border-left:5px solid #f0ad4e; padding:10px 14px; border-radius:4px; font-size:13px;'>",
                    "Run an analysis to see an interpretation of the PERMANOVA test here.",
                    "</div>"))
            }
            results <- analysis_results()
            validate(need(!is.null(results),
                          "Analysis did not return results. Please check your inputs."))

            ord_method <- if (!is.null(results$ord_method)) results$ord_method else "PCoA"
            eig <- if (ord_method == "PCoA") results$ordination$values$Relative_eig else NULL
            axis1 <- if (!is.null(eig)) round(eig[1] * 100, 1) else NA
            axis2 <- if (!is.null(eig)) round(eig[2] * 100, 1) else NA
            nmds_stress <- results$nmds_stress
            perm <- results$permanova

            # First row = the main grouping factor
            main_row <- perm[1, , drop = FALSE]
            r2 <- round(as.numeric(main_row$R2), 3)
            pval <- as.numeric(main_row$`Pr(>F)`)
            fval <- round(as.numeric(main_row$F), 2)

            sig_text <- if (is.na(pval)) {
                "<span style='color:#999;'>p-value not available</span>"
            } else if (pval < 0.001) {
                "<span style='color:#27ae60;font-weight:bold;'>highly significant (p &lt; 0.001)</span>"
            } else if (pval < 0.05) {
                paste0("<span style='color:#27ae60;font-weight:bold;'>significant (p = ", round(pval, 4), ")</span>")
            } else {
                paste0("<span style='color:#e67e22;font-weight:bold;'>not significant (p = ", round(pval, 4), ")</span>")
            }

            effect_text <- if (is.na(r2)) {
                "the effect size could not be estimated"
            } else if (r2 < 0.05) {
                paste0("a <b>very small</b> effect (R² = ", r2, " — the grouping explains only ", round(r2*100, 1), "% of the variation between samples)")
            } else if (r2 < 0.15) {
                paste0("a <b>modest</b> effect (R² = ", r2, ", explaining ", round(r2*100, 1), "% of the between-sample variation)")
            } else if (r2 < 0.30) {
                paste0("a <b>moderate</b> effect (R² = ", r2, ", explaining ", round(r2*100, 1), "% of the between-sample variation)")
            } else {
                paste0("a <b>strong</b> effect (R² = ", r2, ", explaining ", round(r2*100, 1), "% of the between-sample variation)")
            }

            dist_interp <- if (is.null(input$dist_method)) "bray" else input$dist_method
            ord_summary_html <- if (ord_method == "PCoA" && !is.na(axis1) && !is.na(axis2)) {
                paste0("<p>The first two PCoA axes together explain <b>", (axis1 + axis2),
                       "%</b> of the total variation in community composition ",
                       "(PCoA1 = ", axis1, "%, PCoA2 = ", axis2,
                       "%). Each point is one sample; samples that cluster together have similar microbial communities under the ",
                       "<b>", dist_interp, "</b> distance.</p>")
            } else if (ord_method == "NMDS") {
                stress_txt <- if (isTRUE(is.finite(nmds_stress)))
                    paste0(formatC(nmds_stress, format = "f", digits = 3)) else "n/a"
                stress_interp <- if (isTRUE(is.finite(nmds_stress))) {
                    if (nmds_stress < 0.05) " — <b>excellent</b> 2-D representation."
                    else if (nmds_stress < 0.10) " — <b>good</b> 2-D representation."
                    else if (nmds_stress < 0.20) " — <b>acceptable</b> 2-D representation."
                    else " — <b>poor</b> 2-D representation; interpret axis geometry with caution."
                } else ""
                paste0("<p>Non-metric MDS preserves <i>rank order</i> of sample dissimilarities under the ",
                       "<b>", dist_interp, "</b> distance rather than explained variance. ",
                       "The configuration's fit is summarised by the <b>stress</b> value: ",
                       "<b>", stress_txt, "</b>", stress_interp, "</p>")
            } else {
                "<p>Each point is one sample; samples that cluster together have similar microbial communities.</p>"
            }

            # --- Facet summary ---
            facet_html <- ""
            facet_var <- if (is.null(input$facet_variable)) "none" else input$facet_variable
            if (facet_var != "none" && !is.null(results$facet_permanova)) {
                facet_rows <- lapply(names(results$facet_permanova), function(lv) {
                    res <- results$facet_permanova[[lv]]
                    if (is.null(res)) {
                        return(paste0("<tr><td><b>", lv, "</b></td><td colspan='3'>Too few samples</td></tr>"))
                    }
                    frow <- res[1, , drop = FALSE]
                    fr2 <- round(as.numeric(frow$R2), 3)
                    fpv <- as.numeric(frow$`Pr(>F)`)
                    fF  <- round(as.numeric(frow$F), 2)
                    sig_class <- if (!is.na(fpv) && fpv < 0.05) "color:#27ae60;font-weight:bold;" else "color:#e67e22;"
                    fpv_txt <- if (is.na(fpv)) "N/A" else if (fpv < 0.001) "< 0.001" else round(fpv, 4)
                    paste0("<tr><td><b>", lv, "</b></td>",
                           "<td>", fr2, "</td>",
                           "<td>", fF, "</td>",
                           "<td style='", sig_class, "'>", fpv_txt, "</td></tr>")
                })
                facet_html <- paste0(
                    "<h5>Within-group PERMANOVA (", input$group_variable, " within each ", facet_var, ")</h5>",
                    "<table style='width:100%; border-collapse:collapse; margin:8px 0;'>",
                    "<tr style='border-bottom:2px solid #ddd;'>",
                    "<th style='text-align:left;padding:4px 8px;'>", facet_var, "</th>",
                    "<th style='padding:4px 8px;'>R²</th>",
                    "<th style='padding:4px 8px;'>F</th>",
                    "<th style='padding:4px 8px;'>p-value</th></tr>",
                    paste(facet_rows, collapse = ""),
                    "</table>",
                    "<p style='font-size:12px; color:#666;'>Each row tests whether <b>",
                    input$group_variable, "</b> explains variation within that ",
                    facet_var, " level.</p>"
                )
            }

            HTML(paste0(
                "<div style='background:#f8f9fa; border-left:5px solid #3498DB; padding:12px 16px; border-radius:4px; font-size:13.5px; line-height:1.6;'>",
                "<h5 style='margin-top:0;'>Ordination summary (", ord_method, ")</h5>",
                ord_summary_html,

                "<h5>Group separation test (PERMANOVA — overall)</h5>",
                "<p>Using the grouping variable <b>", input$group_variable, "</b>, PERMANOVA found ", effect_text, ", and the test is ", sig_text,
                " (F = ", fval, ", 999 permutations).</p>",

                facet_html,

                "<h5>How to read this</h5>",
                "<ul style='padding-left:20px; margin:0;'>",
                "<li><b>Do the ellipses overlap a lot?</b> → groups are compositionally similar, regardless of p-value.</li>",
                "<li><b>Do the ellipses separate cleanly?</b> → groups have distinct microbial signatures.</li>",
                "<li><b>Small p-value but tiny R²?</b> → the difference is detectable but practically minor; very common with large sample sizes.</li>",
                "<li><b>Always inspect homogeneity of dispersion</b> (betadisper) before concluding group means differ — PERMANOVA can be triggered by dispersion alone.</li>",
                if (facet_var != "none") "<li><b>Faceted panels:</b> Compare ellipse separation <i>within</i> each panel — that's where the stratified PERMANOVA applies.</li>" else "",
                "</ul>",
                "</div>"
            ))
        })
    })
}