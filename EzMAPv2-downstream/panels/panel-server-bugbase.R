################################################################################
# panels/panel-server-bugbase.R — BugBase Phenotype Prediction Server
#
# Predicts organism-level microbiome phenotypes from 16S ASV taxonomy
# using a built-in genus-to-trait mapping table derived from:
#   - ProTraits database (Brbić et al. 2016)
#   - BugBase default traits (Ward et al. 2017)
#   - FAPROTAX-style annotations
#
# Phenotypes predicted:
#   gram_positive, gram_negative, aerobic, anaerobic,
#   facultatively_anaerobic, mobile_elements, biofilm_forming,
#   pathogenic, stress_tolerant
#
# Algorithm:
#   1. Collapse ASV table to genus level
#   2. Map genera to trait probabilities (0-1)
#   3. For each sample, compute weighted trait proportions:
#        trait_score = sum(genus_abundance * trait_probability) / total_abundance
#   4. Normalize per sample to get relative phenotype contributions
################################################################################

bugbaseServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # ------------------------------------------------------------------
    # Built-in genus -> phenotype trait table
    # ------------------------------------------------------------------
    # Each genus has a probability (0-1) for each trait.
    # This is a curated subset covering the most common 16S genera.
    # Genera not in this table are treated as "unknown" (NA).
    .build_trait_table <- function() {
      # Trait columns:
      #   gp = gram_positive, gn = gram_negative,
      #   ae = aerobic, an = anaerobic, fa = facultatively_anaerobic,
      #   me = mobile_elements, bf = biofilm_forming,
      #   pa = pathogenic, st = stress_tolerant

      traits <- list(
        # Genus = c(gp, gn, ae, an, fa, me, bf, pa, st)

        # --- Firmicutes (mostly Gram+) ---
        "Lactobacillus"     = c(1, 0, 0, 0, 1, 0.2, 0.6, 0, 0.4),
        "Bacillus"          = c(1, 0, 1, 0, 0.5, 0.4, 0.7, 0.3, 0.7),
        "Clostridium"       = c(1, 0, 0, 1, 0, 0.3, 0.3, 0.5, 0.3),
        "Staphylococcus"    = c(1, 0, 0, 0, 1, 0.3, 0.8, 0.6, 0.5),
        "Streptococcus"     = c(1, 0, 0, 0, 1, 0.3, 0.8, 0.5, 0.3),
        "Enterococcus"      = c(1, 0, 0, 0, 1, 0.5, 0.7, 0.4, 0.6),
        "Listeria"          = c(1, 0, 0, 0, 1, 0.2, 0.6, 0.9, 0.4),
        "Ruminococcus"      = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Faecalibacterium"  = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Blautia"           = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Roseburia"         = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.2),
        "Coprococcus"       = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Dorea"             = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.2),
        "Lachnospira"       = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Eubacterium"       = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Megamonas"         = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.1),
        "Dialister"         = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Veillonella"       = c(1, 0, 0, 1, 0, 0.2, 0.3, 0, 0.2),
        "Acidaminococcus"   = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Phascolarctobacterium" = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Oscillospira"      = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Turicibacter"      = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Christensenella"   = c(1, 0, 0, 1, 0, 0.1, 0.1, 0, 0.1),
        "Erysipelothrix"    = c(1, 0, 0, 0, 1, 0.2, 0.3, 0.5, 0.2),
        "Mycoplasma"        = c(0, 0, 0, 0, 1, 0.3, 0.2, 0.4, 0.2),

        # --- Proteobacteria (Gram-) ---
        "Escherichia"       = c(0, 1, 0, 0, 1, 0.6, 0.7, 0.5, 0.4),
        "Shigella"          = c(0, 1, 0, 0, 1, 0.5, 0.4, 0.9, 0.3),
        "Salmonella"        = c(0, 1, 0, 0, 1, 0.6, 0.7, 0.9, 0.5),
        "Klebsiella"        = c(0, 1, 0, 0, 1, 0.7, 0.8, 0.6, 0.5),
        "Enterobacter"      = c(0, 1, 0, 0, 1, 0.5, 0.6, 0.3, 0.4),
        "Citrobacter"       = c(0, 1, 0, 0, 1, 0.5, 0.5, 0.3, 0.3),
        "Proteus"           = c(0, 1, 0, 0, 1, 0.4, 0.5, 0.4, 0.3),
        "Serratia"          = c(0, 1, 0, 0, 1, 0.5, 0.6, 0.3, 0.4),
        "Pseudomonas"       = c(0, 1, 1, 0, 0, 0.6, 0.9, 0.5, 0.8),
        "Acinetobacter"     = c(0, 1, 1, 0, 0, 0.5, 0.8, 0.4, 0.6),
        "Moraxella"         = c(0, 1, 1, 0, 0, 0.3, 0.5, 0.3, 0.3),
        "Stenotrophomonas"  = c(0, 1, 1, 0, 0, 0.5, 0.7, 0.3, 0.6),
        "Burkholderia"      = c(0, 1, 1, 0, 0, 0.6, 0.7, 0.4, 0.7),
        "Ralstonia"         = c(0, 1, 1, 0, 0, 0.4, 0.5, 0.2, 0.5),
        "Sphingomonas"      = c(0, 1, 1, 0, 0, 0.3, 0.4, 0, 0.5),
        "Caulobacter"       = c(0, 1, 1, 0, 0, 0.2, 0.3, 0, 0.4),
        "Rhizobium"         = c(0, 1, 1, 0, 0, 0.5, 0.4, 0, 0.5),
        "Bradyrhizobium"    = c(0, 1, 1, 0, 0, 0.3, 0.3, 0, 0.4),
        "Agrobacterium"     = c(0, 1, 1, 0, 0, 0.7, 0.4, 0.2, 0.4),
        "Brucella"          = c(0, 1, 1, 0, 0, 0.3, 0.4, 0.8, 0.5),
        "Vibrio"            = c(0, 1, 0, 0, 1, 0.5, 0.6, 0.6, 0.4),
        "Aeromonas"         = c(0, 1, 0, 0, 1, 0.5, 0.6, 0.5, 0.4),
        "Campylobacter"     = c(0, 1, 0, 0, 0, 0.3, 0.4, 0.7, 0.3),
        "Helicobacter"      = c(0, 1, 0, 0, 0, 0.4, 0.5, 0.7, 0.4),
        "Neisseria"         = c(0, 1, 1, 0, 0, 0.4, 0.5, 0.4, 0.3),
        "Haemophilus"       = c(0, 1, 0, 0, 1, 0.4, 0.5, 0.4, 0.3),
        "Pasteurella"       = c(0, 1, 0, 0, 1, 0.3, 0.3, 0.4, 0.3),
        "Legionella"        = c(0, 1, 1, 0, 0, 0.4, 0.7, 0.8, 0.5),
        "Desulfovibrio"     = c(0, 1, 0, 1, 0, 0.2, 0.3, 0, 0.4),
        "Geobacter"         = c(0, 1, 0, 1, 0, 0.3, 0.5, 0, 0.4),
        "Bilophila"         = c(0, 1, 0, 1, 0, 0.2, 0.2, 0.2, 0.3),
        "Sutterella"        = c(0, 1, 0, 0, 0, 0.1, 0.2, 0, 0.2),
        "Parasutterella"    = c(0, 1, 0, 1, 0, 0.1, 0.1, 0, 0.2),
        "Oxalobacter"       = c(0, 1, 0, 1, 0, 0.1, 0.1, 0, 0.2),

        # --- Bacteroidetes (Gram-) ---
        "Bacteroides"       = c(0, 1, 0, 1, 0, 0.4, 0.5, 0.2, 0.3),
        "Prevotella"        = c(0, 1, 0, 1, 0, 0.3, 0.4, 0.2, 0.3),
        "Parabacteroides"   = c(0, 1, 0, 1, 0, 0.3, 0.3, 0.1, 0.2),
        "Alistipes"         = c(0, 1, 0, 1, 0, 0.2, 0.2, 0, 0.2),
        "Porphyromonas"     = c(0, 1, 0, 1, 0, 0.3, 0.6, 0.5, 0.3),
        "Tannerella"        = c(0, 1, 0, 1, 0, 0.2, 0.5, 0.4, 0.2),
        "Flavobacterium"    = c(0, 1, 1, 0, 0, 0.2, 0.4, 0, 0.3),
        "Chryseobacterium"  = c(0, 1, 1, 0, 0, 0.3, 0.5, 0.2, 0.4),
        "Sphingobacterium"  = c(0, 1, 1, 0, 0, 0.2, 0.4, 0, 0.3),

        # --- Actinobacteria (Gram+) ---
        "Bifidobacterium"   = c(1, 0, 0, 1, 0, 0.1, 0.4, 0, 0.3),
        "Collinsella"       = c(1, 0, 0, 1, 0, 0.1, 0.2, 0, 0.2),
        "Corynebacterium"   = c(1, 0, 0, 0, 1, 0.2, 0.5, 0.3, 0.4),
        "Propionibacterium" = c(1, 0, 0, 1, 0, 0.2, 0.5, 0.2, 0.3),
        "Cutibacterium"     = c(1, 0, 0, 1, 0, 0.2, 0.5, 0.2, 0.3),
        "Actinomyces"       = c(1, 0, 0, 0, 1, 0.2, 0.6, 0.2, 0.3),
        "Gardnerella"       = c(1, 0, 0, 0, 1, 0.2, 0.7, 0.4, 0.3),
        "Mycobacterium"     = c(1, 0, 1, 0, 0, 0.3, 0.5, 0.6, 0.8),
        "Rhodococcus"       = c(1, 0, 1, 0, 0, 0.4, 0.4, 0.1, 0.6),
        "Streptomyces"      = c(1, 0, 1, 0, 0, 0.5, 0.4, 0, 0.6),
        "Micrococcus"       = c(1, 0, 1, 0, 0, 0.2, 0.3, 0, 0.4),
        "Arthrobacter"      = c(1, 0, 1, 0, 0, 0.3, 0.3, 0, 0.5),
        "Nocardia"          = c(1, 0, 1, 0, 0, 0.3, 0.4, 0.3, 0.5),

        # --- Verrucomicrobia ---
        "Akkermansia"       = c(0, 1, 0, 1, 0, 0.1, 0.3, 0, 0.3),

        # --- Fusobacteria (Gram-) ---
        "Fusobacterium"     = c(0, 1, 0, 1, 0, 0.2, 0.6, 0.6, 0.2),
        "Leptotrichia"      = c(0, 1, 0, 1, 0, 0.1, 0.4, 0.2, 0.2),

        # --- Cyanobacteria ---
        "Synechococcus"     = c(0, 1, 1, 0, 0, 0.1, 0.2, 0, 0.5),
        "Prochlorococcus"   = c(0, 1, 1, 0, 0, 0.1, 0.1, 0, 0.4),

        # --- Spirochaetes ---
        "Treponema"         = c(0, 1, 0, 1, 0, 0.2, 0.3, 0.5, 0.3),
        "Borrelia"          = c(0, 1, 0, 0, 0, 0.3, 0.2, 0.9, 0.3),
        "Leptospira"        = c(0, 1, 1, 0, 0, 0.2, 0.4, 0.7, 0.4),

        # --- Tenericutes (Mycoplasma already listed under Firmicutes) ---

        # --- Deinococcus-Thermus ---
        "Deinococcus"       = c(1, 0, 1, 0, 0, 0.2, 0.3, 0, 0.9),
        "Thermus"           = c(0, 1, 1, 0, 0, 0.2, 0.4, 0, 0.8)
      )

      # Build data.frame
      trait_names <- c("gram_positive", "gram_negative",
                       "aerobic", "anaerobic", "facultatively_anaerobic",
                       "mobile_elements", "biofilm_forming",
                       "pathogenic", "stress_tolerant")
      df <- as.data.frame(do.call(rbind, traits), stringsAsFactors = FALSE)
      colnames(df) <- trait_names
      df$Genus <- names(traits)
      rownames(df) <- df$Genus
      df
    }

    # Pretty labels for phenotype display
    .phenotype_labels <- c(
      gram_positive           = "Gram Positive",
      gram_negative           = "Gram Negative",
      aerobic                 = "Aerobic",
      anaerobic               = "Anaerobic",
      facultatively_anaerobic = "Facultatively Anaerobic",
      mobile_elements         = "Contains Mobile Elements",
      biofilm_forming         = "Biofilm Forming",
      pathogenic              = "Potentially Pathogenic",
      stress_tolerant         = "Oxidative Stress Tolerant"
    )

    # Helper: generate enough distinct colors for any number of phenotypes
    # Combines multiple RColorBrewer palettes to guarantee 10+ colors
    .get_phenotype_colors <- function(n, pal_name = "Set2") {
      max_pal <- tryCatch(
        RColorBrewer::brewer.pal(RColorBrewer::brewer.pal.info[pal_name, "maxcolors"], pal_name),
        error = function(e) RColorBrewer::brewer.pal(8, "Set2")
      )
      if (n <= length(max_pal)) {
        return(max_pal[seq_len(n)])
      }
      # Extend with colors from other palettes if needed
      extra <- c("#E41A1C", "#377EB8", "#4DAF4A", "#984EA3", "#FF7F00",
                 "#FFFF33", "#A65628", "#F781BF", "#66C2A5", "#FC8D62",
                 "#8DA0CB", "#E78AC3", "#A6D854", "#FFD92F", "#E5C494")
      all_cols <- unique(c(max_pal, extra))
      colorRampPalette(all_cols)(n)
    }

    # ------------------------------------------------------------------
    # Group variable picker
    # ------------------------------------------------------------------
    output$group_variable_ui <- renderUI({
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
      selectInput(ns("group_variable"), "Group by:", choices = group_vars)
    })

    # ------------------------------------------------------------------
    # Preprocessing: clean taxonomy
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
    # Run BugBase prediction
    # ------------------------------------------------------------------
    bugbase_results <- eventReactive(input$run_bugbase, {
      tryCatch({
        pseq <- physeq_clean()
        req(pseq)

        selected_phenotypes <- input$phenotypes
        # In Easy mode (NULL input), default to common phenotypes
        if (length(selected_phenotypes) == 0) {
          selected_phenotypes <- c("gram_positive", "gram_negative",
                                   "aerobic", "anaerobic",
                                   "biofilm_forming", "pathogenic")
        }

        withProgress(message = "Running BugBase phenotype prediction...", value = 0, {

          incProgress(0.1, detail = "Loading trait database")
          trait_db <- .build_trait_table()
          cat("[BugBase] Trait database:", nrow(trait_db), "genera\n")

          incProgress(0.2, detail = "Collapsing to genus level")

          # Get ASV + taxonomy
          otu_mat <- as(otu_table(pseq), "matrix")
          if (isTRUE(taxa_are_rows(pseq))) {
            otu_mat <- otu_mat   # taxa as rows
          } else {
            otu_mat <- t(otu_mat)
          }
          # otu_mat is now taxa (rows) x samples (cols)

          tax_df <- as.data.frame(tax_table(pseq), stringsAsFactors = FALSE)

          # Extract genus for each taxon
          genus_col <- if ("Genus" %in% colnames(tax_df)) "Genus" else {
            gc <- grep("genus", colnames(tax_df), ignore.case = TRUE, value = TRUE)
            if (length(gc) > 0) gc[1] else colnames(tax_df)[min(6, ncol(tax_df))]
          }

          genera <- as.character(tax_df[[genus_col]])
          genera[is.na(genera) | !nzchar(genera)] <- "Unknown"
          # Remove any residual prefixes
          genera <- gsub("^g__", "", genera, ignore.case = TRUE)

          cat("[BugBase] Unique genera in data:", length(unique(genera)), "\n")

          # Aggregate ASV counts by genus
          incProgress(0.3, detail = "Aggregating by genus")
          genus_unique <- unique(genera)
          genus_mat <- matrix(0, nrow = length(genus_unique),
                              ncol = ncol(otu_mat))
          rownames(genus_mat) <- genus_unique
          colnames(genus_mat) <- colnames(otu_mat)

          for (g in genus_unique) {
            idx <- which(genera == g)
            if (length(idx) == 1) {
              genus_mat[g, ] <- otu_mat[idx, ]
            } else {
              genus_mat[g, ] <- colSums(otu_mat[idx, , drop = FALSE])
            }
          }

          incProgress(0.5, detail = "Mapping genera to phenotypes")

          # Match genera to trait database
          matched_genera <- intersect(rownames(genus_mat), rownames(trait_db))
          unmatched_genera <- setdiff(rownames(genus_mat), rownames(trait_db))
          unmatched_genera <- setdiff(unmatched_genera, "Unknown")

          cat("[BugBase] Genera matched to trait DB:", length(matched_genera), "\n")
          cat("[BugBase] Genera not in trait DB:", length(unmatched_genera), "\n")
          if (length(unmatched_genera) > 0 && length(unmatched_genera) <= 20)
            cat("[BugBase] Unmatched:", paste(head(unmatched_genera, 20),
                                              collapse = ", "), "\n")

          # Compute per-sample trait scores
          # For each phenotype: weighted sum of (genus_abundance * trait_probability)
          incProgress(0.7, detail = "Computing phenotype scores")

          sample_names <- colnames(genus_mat)
          phenotype_mat <- matrix(0, nrow = length(sample_names),
                                  ncol = length(selected_phenotypes))
          rownames(phenotype_mat) <- sample_names
          colnames(phenotype_mat) <- selected_phenotypes

          coverage <- numeric(length(sample_names))
          names(coverage) <- sample_names

          for (s in seq_along(sample_names)) {
            samp <- sample_names[s]
            abund <- genus_mat[, samp]
            total <- sum(abund)
            if (total == 0) next

            # Coverage: fraction of abundance from annotated genera
            annotated_abund <- sum(abund[names(abund) %in% matched_genera])
            coverage[s] <- annotated_abund / total * 100

            for (ph in selected_phenotypes) {
              score <- 0
              for (g in matched_genera) {
                if (abund[g] > 0 && ph %in% colnames(trait_db)) {
                  score <- score + abund[g] * trait_db[g, ph]
                }
              }
              phenotype_mat[s, ph] <- score / total
            }
          }

          incProgress(0.9, detail = "Finalizing")

          # Get group info
          md <- as(sample_data(pseq), "data.frame")
          grp_var <- input$group_variable
          if (!is.null(grp_var) && grp_var %in% colnames(md)) {
            groups <- as.character(md[[grp_var]])
          } else {
            groups <- rep("All", nrow(md))
          }
          names(groups) <- rownames(md)

          incProgress(1, detail = "Done")
          showNotification("\u2705 BugBase phenotype prediction completed.",
                           type = "message")

          list(
            phenotype_mat = phenotype_mat,
            coverage      = coverage,
            groups        = groups[sample_names],
            grp_var       = grp_var,
            matched       = length(matched_genera),
            unmatched     = length(unmatched_genera),
            total_genera  = length(genus_unique) - 1,  # minus "Unknown"
            trait_db      = trait_db
          )
        })
      }, error = function(e) {
        cat("[BugBase] ERROR:", e$message, "\n")
        showNotification(paste0("BugBase error: ", e$message),
                         type = "error", duration = 15)
        NULL
      })
    })

    # ------------------------------------------------------------------
    # Main phenotype plot (box/bar/heatmap)
    # ------------------------------------------------------------------
    output$bugbase_plot <- renderPlot({
      if (is.null(input$run_bugbase) || input$run_bugbase == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.55,
                     label = "Click 'Run BugBase' to predict phenotypes",
                     size = 6, fontface = "bold", color = "#3B82F6") +
            ggplot2::annotate("text", x = 0.5, y = 0.43,
                     label = "Maps 16S taxonomy to organism-level phenotype traits.",
                     size = 4, color = "#7F8C8D") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      res <- tryCatch(bugbase_results(), error = function(e) {
        cat("[BugBase] Plot error:", e$message, "\n")
        NULL
      })
      if (is.null(res)) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                     label = "BugBase ran but plot could not be generated.\nCheck R console for details.",
                     size = 5, color = "#E74C3C") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }

      plot_type <- input$plot_type %||% "boxplot"
      pheno_mat <- res$phenotype_mat
      groups    <- res$groups
      pal_name  <- input$color_palette %||% "Set2"
      fsize     <- as.numeric(input$font_size %||% 12)

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes).
      styles <- ezmap_plot_styling(input,
                                   default_legend_title = "Phenotype",
                                   base_size = fsize)

      # Build long-form data for ggplot
      df_long <- data.frame(
        Sample    = rep(rownames(pheno_mat), ncol(pheno_mat)),
        Phenotype = rep(colnames(pheno_mat), each = nrow(pheno_mat)),
        Score     = as.vector(pheno_mat),
        Group     = rep(groups[rownames(pheno_mat)], ncol(pheno_mat)),
        stringsAsFactors = FALSE
      )
      # Use pretty labels
      df_long$Phenotype_label <- .phenotype_labels[df_long$Phenotype]
      df_long$Phenotype_label[is.na(df_long$Phenotype_label)] <- df_long$Phenotype[is.na(df_long$Phenotype_label)]

      if (plot_type == "boxplot") {
        p <- ggplot2::ggplot(df_long,
               ggplot2::aes(x = Phenotype_label, y = Score, fill = Group)) +
          ggplot2::geom_boxplot(outlier.shape = NA, alpha = 0.7,
                                position = ggplot2::position_dodge(0.8))

        if (isTRUE(input$show_points %||% TRUE)) {
          p <- p + ggplot2::geom_jitter(
            ggplot2::aes(group = Group),
            position = ggplot2::position_jitterdodge(
              jitter.width = 0.15, dodge.width = 0.8),
            size = 1.3, alpha = 0.5)
        }

        if (isTRUE(input$show_pvalues %||% TRUE) && length(unique(groups)) >= 2) {
          # Add Kruskal-Wallis p-values
          pvals <- sapply(unique(df_long$Phenotype_label), function(ph) {
            sub <- df_long[df_long$Phenotype_label == ph, ]
            if (length(unique(sub$Group)) < 2) return(NA)
            tryCatch(
              stats::kruskal.test(Score ~ Group, data = sub)$p.value,
              error = function(e) NA
            )
          })
          pval_df <- data.frame(
            Phenotype_label = names(pvals),
            pval = pvals,
            label = ifelse(pvals < 0.001, "***",
                    ifelse(pvals < 0.01, "**",
                    ifelse(pvals < 0.05, "*", "ns"))),
            stringsAsFactors = FALSE
          )
          pval_df <- pval_df[!is.na(pval_df$pval), ]
          if (nrow(pval_df) > 0) {
            max_scores <- tapply(df_long$Score, df_long$Phenotype_label, max,
                                 na.rm = TRUE)
            pval_df$y <- max_scores[pval_df$Phenotype_label] * 1.08
            p <- p + ggplot2::geom_text(
              data = pval_df,
              ggplot2::aes(x = Phenotype_label, y = y, label = label),
              inherit.aes = FALSE, size = fsize / 3, color = "#E74C3C"
            )
          }
        }

        p <- p +
          ggplot2::scale_fill_brewer(palette = pal_name) +
          styles$theme_fn(base_size = fsize) +
          styles$grid_theme +
          ggplot2::theme(
            axis.text.x = ggplot2::element_text(angle = 35, hjust = 1,
                                                 size = fsize - 1),
            plot.title = ggplot2::element_text(face = "bold", size = fsize + 2),
            legend.position = input$legend_position %||% "bottom"
          ) +
          ggplot2::labs(
            title = if (is.null(styles$title)) "BugBase Phenotype Predictions" else styles$title,
            x = NULL, y = "Relative Trait Score",
            fill = if (is.null(styles$legend_title)) res$grp_var else styles$legend_title
          )
        p

      } else if (plot_type == "barplot") {
        # Mean +/- SE per group
        agg <- stats::aggregate(Score ~ Group + Phenotype_label,
                                data = df_long, FUN = function(x) {
          c(mean = mean(x, na.rm = TRUE), se = stats::sd(x, na.rm = TRUE) / sqrt(length(x)))
        })
        agg_df <- data.frame(
          Group             = agg$Group,
          Phenotype_label   = agg$Phenotype_label,
          mean              = agg$Score[, "mean"],
          se                = agg$Score[, "se"],
          stringsAsFactors  = FALSE
        )

        p <- ggplot2::ggplot(agg_df,
               ggplot2::aes(x = Phenotype_label, y = mean, fill = Group)) +
          ggplot2::geom_col(position = ggplot2::position_dodge(0.8),
                             width = 0.7, alpha = 0.85) +
          ggplot2::geom_errorbar(
            ggplot2::aes(ymin = mean - se, ymax = mean + se),
            position = ggplot2::position_dodge(0.8), width = 0.25) +
          ggplot2::scale_fill_brewer(palette = pal_name) +
          ggplot2::labs(
            title = "BugBase Phenotype Predictions (Mean \u00B1 SE)",
            x = NULL, y = "Relative Trait Score",
            fill = res$grp_var
          ) +
          ggplot2::theme_minimal(base_size = fsize) +
          ggplot2::theme(
            axis.text.x = ggplot2::element_text(angle = 35, hjust = 1,
                                                 size = fsize - 1),
            plot.title = ggplot2::element_text(face = "bold", size = fsize + 2),
            legend.position = input$legend_position %||% "bottom"
          )
        p

      } else if (plot_type == "heatmap") {
        # Heatmap
        mat <- t(pheno_mat)   # phenotypes (rows) x samples (cols)
        rownames(mat) <- .phenotype_labels[rownames(mat)]

        annot_col <- NULL
        if (isTRUE(input$aggregate_groups_hm %||% TRUE)) {
          grp_unique <- sort(unique(groups))
          mat_agg <- sapply(grp_unique, function(g) {
            cols <- which(groups == g)
            if (length(cols) == 1) mat[, cols] else rowMeans(mat[, cols, drop = FALSE], na.rm = TRUE)
          })
          rownames(mat_agg) <- rownames(mat)
          colnames(mat_agg) <- grp_unique
          mat <- mat_agg
        } else {
          ann_df <- data.frame(Group = groups, row.names = names(groups))
          common <- intersect(colnames(mat), rownames(ann_df))
          if (length(common) > 0) annot_col <- ann_df[common, , drop = FALSE]
        }

        if (isTRUE(input$scale_heatmap %||% TRUE)) {
          mat <- t(scale(t(mat)))
          mat[!is.finite(mat)] <- 0
        }

        pal <- colorRampPalette(RColorBrewer::brewer.pal(9, "YlGnBu"))(100)

        hm <- pheatmap::pheatmap(
          mat,
          color            = pal,
          cluster_rows     = TRUE,
          cluster_cols     = isTRUE(input$cluster_samples %||% TRUE),
          fontsize         = fsize,
          fontsize_row     = fsize - 1,
          annotation_col   = annot_col,
          main             = "BugBase Phenotype Heatmap",
          silent           = TRUE
        )
        grid::grid.newpage()
        grid::grid.draw(hm$gtable)
      }
    }, res = 120, height = function() {
      h <- input$plot_height
      if (is.null(h) || !is.finite(as.numeric(h))) 550 else as.numeric(h)
    })

    # ------------------------------------------------------------------
    # Stacked phenotype proportions plot
    # ------------------------------------------------------------------
    output$bugbase_stacked <- renderPlot({
      res <- bugbase_results()
      req(res)

      pheno_mat <- res$phenotype_mat
      groups    <- res$groups
      fsize     <- as.numeric(input$font_size %||% 12)
      pal_name  <- input$color_palette %||% "Set2"

      # Normalize each sample to sum to 1 across selected phenotypes
      row_sums <- rowSums(pheno_mat)
      row_sums[row_sums == 0] <- 1
      pheno_norm <- pheno_mat / row_sums

      df_long <- data.frame(
        Sample    = rep(rownames(pheno_norm), ncol(pheno_norm)),
        Phenotype = rep(colnames(pheno_norm), each = nrow(pheno_norm)),
        Score     = as.vector(pheno_norm),
        Group     = rep(groups[rownames(pheno_norm)], ncol(pheno_norm)),
        stringsAsFactors = FALSE
      )
      df_long$Phenotype_label <- .phenotype_labels[df_long$Phenotype]
      df_long$Phenotype_label[is.na(df_long$Phenotype_label)] <- df_long$Phenotype[is.na(df_long$Phenotype_label)]

      # Order samples by group
      sample_order <- names(sort(groups))
      df_long$Sample <- factor(df_long$Sample, levels = sample_order)

      n_phenotypes <- length(unique(df_long$Phenotype_label))
      pheno_colors <- .get_phenotype_colors(n_phenotypes, pal_name)

      ggplot2::ggplot(df_long,
        ggplot2::aes(x = Sample, y = Score, fill = Phenotype_label)) +
        ggplot2::geom_bar(stat = "identity", width = 0.9) +
        ggplot2::scale_fill_manual(values = pheno_colors) +
        ggplot2::labs(
          title = "Relative Phenotype Proportions per Sample",
          x = NULL, y = "Relative Proportion", fill = "Phenotype"
        ) +
        ggplot2::facet_grid(. ~ Group, scales = "free_x", space = "free_x") +
        ggplot2::theme_minimal(base_size = fsize) +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = 60, hjust = 1,
                                               size = fsize - 3),
          plot.title = ggplot2::element_text(face = "bold", size = fsize + 2),
          legend.position = input$legend_position %||% "bottom",
          strip.text = ggplot2::element_text(face = "bold")
        )
    }, res = 120)

    # ------------------------------------------------------------------
    # Summary + table
    # ------------------------------------------------------------------
    output$bugbase_summary <- renderPrint({
      if (is.null(input$run_bugbase) || input$run_bugbase == 0) {
        cat("Click 'Run BugBase' to predict organism-level phenotypes.\n")
        cat("BugBase maps genus-level taxonomy to phenotype trait databases.\n")
        return(invisible(NULL))
      }
      res <- bugbase_results()
      req(res)
      cat("BugBase Phenotype Prediction Summary\n")
      cat("------------------------------------\n")
      cat("Genera in data:          ", res$total_genera, "\n", sep = "")
      cat("Genera with trait info:  ", res$matched, "\n", sep = "")
      cat("Genera without traits:   ", res$unmatched, "\n", sep = "")
      cat("Trait DB coverage:       ",
          round(res$matched / max(res$total_genera, 1) * 100, 1), "%\n", sep = "")
      cat("Phenotypes predicted:    ", ncol(res$phenotype_mat), "\n", sep = "")
      cat("Samples:                 ", nrow(res$phenotype_mat), "\n", sep = "")
      cat("\nPer-sample trait coverage (% annotated abundance):\n")
      cov <- res$coverage
      cat("  Min:    ", round(min(cov), 1), "%\n", sep = "")
      cat("  Median: ", round(median(cov), 1), "%\n", sep = "")
      cat("  Mean:   ", round(mean(cov), 1), "%\n", sep = "")
      cat("  Max:    ", round(max(cov), 1), "%\n", sep = "")

      min_cov <- as.numeric(input$min_coverage %||% 10)
      low_cov <- sum(cov < min_cov)
      if (low_cov > 0) {
        cat("\n\u26A0 ", low_cov, " sample(s) below ", min_cov,
            "% coverage threshold.\n", sep = "")
      }
    })

    output$bugbase_table <- DT::renderDataTable({
      res <- bugbase_results()
      req(res)
      mat <- res$phenotype_mat
      # Add group column
      df <- data.frame(
        Sample = rownames(mat),
        Group  = res$groups[rownames(mat)],
        Coverage_pct = round(res$coverage[rownames(mat)], 1),
        stringsAsFactors = FALSE
      )
      for (ph in colnames(mat)) {
        label <- .phenotype_labels[ph]
        if (is.na(label)) label <- ph
        df[[label]] <- round(mat[, ph], 4)
      }
      DT::datatable(
        df,
        options = list(pageLength = 15, scrollX = TRUE, dom = "frtip"),
        rownames = FALSE
      )
    })

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    output$download_bugbase_table <- downloadHandler(
      filename = function() ezmap_filename("BugBase_Phenotypes", "csv"),
      content  = function(file) {
        res <- bugbase_results()
        req(res)
        mat <- res$phenotype_mat
        df <- data.frame(
          Sample = rownames(mat),
          Group = res$groups[rownames(mat)],
          Coverage_pct = round(res$coverage[rownames(mat)], 1),
          stringsAsFactors = FALSE
        )
        for (ph in colnames(mat)) {
          df[[.phenotype_labels[ph]]] <- round(mat[, ph], 4)
        }
        utils::write.csv(df, file, row.names = FALSE)
      }
    )

    output$download_bugbase_plot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "BugBase_Plot"),
      content  = function(file) {
        # Re-render current plot type. ezmap_open_device picks the right
        # graphics device based on the file extension (PNG / PDF / SVG /
        # TIFF / JPEG) and honours the user-chosen Width / Height /
        # Units / DPI from the download_dim_ui controls.
        d <- download_dims(input, def_width = 12, def_height = 8)
        ezmap_open_device(file,
                          width = d$width, height = d$height,
                          units = d$units, dpi = d$dpi)
        tryCatch({
          res <- bugbase_results()
          req(res)
          plot_type <- input$plot_type %||% "boxplot"
          pheno_mat <- res$phenotype_mat
          groups <- res$groups
          fsize <- as.numeric(input$font_size %||% 12)
          pal_name <- input$color_palette %||% "Set2"

          df_long <- data.frame(
            Sample    = rep(rownames(pheno_mat), ncol(pheno_mat)),
            Phenotype = rep(colnames(pheno_mat), each = nrow(pheno_mat)),
            Score     = as.vector(pheno_mat),
            Group     = rep(groups[rownames(pheno_mat)], ncol(pheno_mat)),
            stringsAsFactors = FALSE
          )
          df_long$Phenotype_label <- .phenotype_labels[df_long$Phenotype]

          if (plot_type == "boxplot") {
            p <- ggplot2::ggplot(df_long,
                   ggplot2::aes(x = Phenotype_label, y = Score, fill = Group)) +
              ggplot2::geom_boxplot(alpha = 0.7) +
              ggplot2::scale_fill_brewer(palette = pal_name) +
              ggplot2::labs(title = "BugBase Phenotype Predictions",
                           x = NULL, y = "Relative Trait Score") +
              ggplot2::theme_minimal(base_size = fsize) +
              ggplot2::theme(axis.text.x = ggplot2::element_text(
                angle = 35, hjust = 1))
            print(p)
          } else if (plot_type == "heatmap") {
            mat <- t(pheno_mat)
            rownames(mat) <- .phenotype_labels[rownames(mat)]
            pal <- colorRampPalette(RColorBrewer::brewer.pal(9, "YlGnBu"))(100)
            hm <- pheatmap::pheatmap(mat, color = pal, fontsize = fsize,
                                     main = "BugBase Phenotype Heatmap",
                                     silent = TRUE)
            grid::grid.newpage(); grid::grid.draw(hm$gtable)
          } else {
            agg <- stats::aggregate(Score ~ Group + Phenotype_label,
                                    data = df_long, FUN = mean)
            p <- ggplot2::ggplot(agg,
                   ggplot2::aes(x = Phenotype_label, y = Score, fill = Group)) +
              ggplot2::geom_col(position = ggplot2::position_dodge(0.8), width = 0.7) +
              ggplot2::scale_fill_brewer(palette = pal_name) +
              ggplot2::labs(title = "BugBase Phenotype Predictions (Mean)",
                           x = NULL, y = "Relative Trait Score") +
              ggplot2::theme_minimal(base_size = fsize) +
              ggplot2::theme(axis.text.x = ggplot2::element_text(
                angle = 35, hjust = 1))
            print(p)
          }
        }, error = function(e) {
          cat("[BugBase] Download plot error:", e$message, "\n")
        })
        grDevices::dev.off()
      }
    )
  })
}
