################################################################################
# panels/panel-server-tax4fun2.R — Tax4Fun (v1 via themetagenomics) Server
#
# Predicts community-level KEGG-pathway functional profiles from 16S ASV
# tables using taxonomy-to-function mapping (Tax4Fun algorithm, Aßhauer et al.
# 2015). Implemented via `themetagenomics::t4f()` which only requires:
#   1. An ASV abundance table
#   2. A taxonomy table (Kingdom → Species)
#   3. A local SILVA-KO reference (downloaded once via download_ref())
#
# No representative sequences (refseq) are needed — this is purely
# taxonomy-based functional prediction.
################################################################################

tax4fun2Server <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # small null-coalescing helper
    `%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a))) b else a

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # ------------------------------------------------------------------
    # Reference-database resolution / download
    # ------------------------------------------------------------------

    # Resolve the reference-DB path from user input or a sensible default.
    resolve_db_path <- function() {
      raw <- input$db_path
      if (!is.null(raw) && nzchar(raw)) {
        return(normalizePath(raw, mustWork = FALSE))
      }
      # Default: cache next to the app
      file.path(getwd(), "tax4fun_ref")
    }

    # Does the DB look installed?
    db_installed <- reactive({
      invalidate <- input$download_db
      path <- resolve_db_path()
      if (!dir.exists(path)) return(FALSE)
      # download_ref() places t4f_silva_to_kegg.rds and t4f_ref_profiles.rds
      # directly in the target folder (no sub-folder)
      file.exists(file.path(path, "t4f_silva_to_kegg.rds")) &&
        file.exists(file.path(path, "t4f_ref_profiles.rds"))
    })

    output$db_status_ui <- renderUI({
      path <- resolve_db_path()
      if (isTRUE(db_installed())) {
        tags$div(
          style = "background:#E8F5E9; border-left:4px solid #27AE60; padding:8px 10px; border-radius:4px; font-size:12px; margin-bottom:8px;",
          tags$b(icon("check-circle"), " SILVA-KO reference found"),
          tags$br(),
          tags$code(path)
        )
      } else {
        tags$div(
          style = "background:#FFF3E0; border-left:4px solid #E67E22; padding:8px 10px; border-radius:4px; font-size:12px; margin-bottom:8px;",
          tags$b(icon("exclamation-triangle"), " SILVA-KO reference not found"),
          tags$br(),
          "Expected path: ", tags$code(path),
          tags$br(),
          "Click ", tags$b("Download SILVA-KO Reference"), " below."
        )
      }
    })

    # Group variable picker
    output$group_variable_ui <- renderUI({
      pseq <- physeq_data()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(x)) > 1)]
      selectInput(ns("group_variable"), "Group by:", choices = group_vars)
    })

    # ------------------------------------------------------------------
    # DB download  (themetagenomics::download_ref)
    # ------------------------------------------------------------------
    observeEvent(input$download_db, {
      # Auto-install themetagenomics if needed (required for download_ref)
      if (!requireNamespace("themetagenomics", quietly = TRUE)) {
        showNotification("Installing 'themetagenomics' package first...", type = "message", duration = 8)
        tryCatch({
          if (!requireNamespace("remotes", quietly = TRUE))
            install.packages("remotes", repos = "https://cloud.r-project.org", quiet = TRUE)
          remotes::install_github("EESI/themetagenomics", upgrade = "never", quiet = TRUE)
        }, error = function(e) {
          showNotification(paste0("Failed to install themetagenomics: ", e$message), type = "error", duration = 15)
          return()
        })
        if (!requireNamespace("themetagenomics", quietly = TRUE)) {
          showNotification("themetagenomics could not be installed. Install manually in R.", type = "error")
          return()
        }
      }

      dest_dir <- resolve_db_path()
      showNotification(
        paste0("Downloading SILVA-KO reference to ", dest_dir,
               " \u2014 this may take a few minutes."),
        type = "message", duration = 10)

      withProgress(message = "Downloading SILVA-KO reference...", value = 0, {
        tryCatch({
          incProgress(0.05, detail = "Preparing target folder")
          dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)

          incProgress(0.10, detail = "Downloading SILVA-KO data...")
          themetagenomics::download_ref(
            dest_dir,
            reference = "silva_ko",
            overwrite = FALSE
          )

          incProgress(1, detail = "Done")
          showNotification(
            "\u2705 SILVA-KO reference downloaded successfully.",
            type = "message")
        }, error = function(e) {
          showNotification(
            paste0("Download failed: ", e$message),
            type = "error", duration = 15)
        })
      })
    })

    # ------------------------------------------------------------------
    # Preprocessing
    # ------------------------------------------------------------------
    physeq_cleaned <- reactive({
      Abundance_raw <- physeq_data()
      req(Abundance_raw)
      Bacteria <- Abundance_raw

      if (ncol(tax_table(Bacteria)) >= 7) {
        colnames(tax_table(Bacteria)) <- c(
          "Kingdom","Phylum","Class","Order","Family","Genus","Species"
        )[1:ncol(tax_table(Bacteria))]
      }

      # Clean taxonomy prefix strings — handle ALL known QIIME2 formats:
      #   D_0__ / D_1__ / ...  (old QIIME2)
      #   d__ / k__ / p__ / c__ / o__ / f__ / g__ / s__  (new QIIME2)
      # Convert S4 tax_table to plain matrix for safe gsub
      tax_mat <- as(tax_table(Bacteria), "matrix")
      tax_mat[,] <- gsub("^[Dd]_[0-9]__", "", tax_mat[,])
      tax_mat[,] <- gsub("^[dkpcofgs]__",  "", tax_mat[,])
      # Trim whitespace and convert empty/placeholder strings to NA
      tax_mat[,] <- trimws(tax_mat[,])
      tax_mat[tax_mat == "" | tax_mat == "unidentified" |
              tax_mat == "uncultured" | tax_mat == "Unassigned" |
              tax_mat == "__"] <- NA
      tax_table(Bacteria) <- tax_table(tax_mat)

      # NOTE: NO data-wide subset_taxa or filter_taxa here.
      # The central Filter tab is the single source of truth for taxa
      # filtering. Previously this reactive ran a contaminant filter
      # (Chloroplast / Mitochondria / Rickettsiales / Eukaryota /
      # Archaea) and a 20% prevalence filter — both duplicated the
      # Filter tab's job, and the 20% prevalence filter masked
      # condition-specific signal (same bug Beta and Network had —
      # only universally-prevalent taxa survived, so per-condition
      # functional profiles ended up nearly identical).
      Abundance <- Bacteria

      cat("[Tax4Fun] Using Filter-tab data: ", ntaxa(Abundance), " taxa, ",
          nsamples(Abundance), " samples\n", sep = "")

      # Show first few cleaned taxonomy entries
      if (ntaxa(Abundance) > 0) {
        tax_peek <- as(tax_table(Abundance), "matrix")[1:min(3, ntaxa(Abundance)), , drop = FALSE]
        cat("[Tax4Fun] Cleaned taxonomy sample:\n")
        for (i in seq_len(nrow(tax_peek))) {
          cat("  ", rownames(tax_peek)[i], ": ",
              paste(colnames(tax_peek), "=", tax_peek[i,], collapse = " | "), "\n")
        }
      } else {
        cat("[Tax4Fun] WARNING: No taxa survived filtering!\n")
      }

      req(Abundance)
      Abundance
    })

    # ------------------------------------------------------------------
    # Run Tax4Fun via themetagenomics::t4f()
    # ------------------------------------------------------------------
    tax4fun_results <- eventReactive(input$run_tax4fun2, {
      if (!requireNamespace("themetagenomics", quietly = TRUE)) {
        # Auto-install themetagenomics from GitHub on first use
        showNotification("Installing 'themetagenomics' package (one-time setup)...",
                         type = "message", duration = 10)
        install_ok <- tryCatch({
          if (!requireNamespace("remotes", quietly = TRUE))
            install.packages("remotes", repos = "https://cloud.r-project.org", quiet = TRUE)
          remotes::install_github("EESI/themetagenomics", upgrade = "never", quiet = TRUE)
          requireNamespace("themetagenomics", quietly = TRUE)
        }, error = function(e) {
          showNotification(
            paste0("Auto-install failed: ", e$message,
                   "\nInstall manually in R: remotes::install_github('EESI/themetagenomics')"),
            type = "error", duration = 20)
          FALSE
        })
        if (!isTRUE(install_ok)) return(NULL)
        showNotification("themetagenomics installed successfully!", type = "message", duration = 5)
      }
      if (!isTRUE(db_installed())) {
        showNotification("SILVA-KO reference not found. Download it first.",
                         type = "error", duration = 8)
        return(NULL)
      }

      # Wrap entire pipeline in tryCatch so errors surface cleanly
      result <- tryCatch({
        pseq <- physeq_cleaned()
        req(pseq)
        cat("[Tax4Fun] Filtered phyloseq:", ntaxa(pseq), "taxa,",
            nsamples(pseq), "samples\n")

        ref_path <- resolve_db_path()

        withProgress(message = "Running Tax4Fun prediction...", value = 0, {

          incProgress(0.1, detail = "Extracting ASV and taxonomy tables")

          # Extract ASV table (samples x taxa for t4f with rows_are_taxa=FALSE)
          otu_mat <- as(otu_table(pseq), "matrix")
          if (isTRUE(taxa_are_rows(pseq))) {
            otu_mat <- t(otu_mat)   # now samples (rows) x taxa (cols)
          }

          # Extract taxonomy table as character matrix
          tax_mat <- as(tax_table(pseq), "matrix")
          storage.mode(tax_mat) <- "character"

          cat("[Tax4Fun] ASV matrix:", nrow(otu_mat), "samples x",
              ncol(otu_mat), "taxa\n")
          cat("[Tax4Fun] Tax table:", nrow(tax_mat), "taxa x",
              ncol(tax_mat), "ranks\n")
          cat("[Tax4Fun] Tax columns:", paste(colnames(tax_mat), collapse = ", "), "\n")
          cat("[Tax4Fun] Reference path:", ref_path, "\n")

          # --- Diagnostic: show first 5 taxa after cleaning ---
          cat("[Tax4Fun] === TAXONOMY SAMPLE (first 5 rows) ===\n")
          n_show <- min(5, nrow(tax_mat))
          for (i in seq_len(n_show)) {
            cat("  ", rownames(tax_mat)[i], ": ",
                paste(colnames(tax_mat), "=", tax_mat[i,], collapse = " | "), "\n")
          }
          # Count NAs per rank
          cat("[Tax4Fun] NA counts per rank:\n")
          for (col in colnames(tax_mat)) {
            n_na <- sum(is.na(tax_mat[, col]) | !nzchar(tax_mat[, col]))
            cat("  ", col, ":", n_na, "/", nrow(tax_mat), "NA\n")
          }
          # Check reference files
          cat("[Tax4Fun] Reference directory contents:\n")
          if (dir.exists(ref_path)) {
            ref_files <- list.files(ref_path, recursive = TRUE)
            for (rf in ref_files) {
              fsize <- file.size(file.path(ref_path, rf))
              cat("  ", rf, "(", format(fsize, big.mark = ","), "bytes)\n")
            }
          } else {
            cat("  DIRECTORY NOT FOUND:", ref_path, "\n")
          }

          # --- Diagnostic: simulate t4f() taxa_id construction ---
          cat("[Tax4Fun] === SIMULATED TAXA IDs (first 5) ===\n")
          n_sim <- min(5, nrow(tax_mat))
          for (i in seq_len(n_sim)) {
            row_vals <- tax_mat[i, ]
            row_vals <- row_vals[!is.na(row_vals) & nzchar(row_vals)]
            taxa_id <- paste0(paste0(row_vals, collapse = ";"), ";")
            cat("  ", rownames(tax_mat)[i], " -> ", taxa_id, "\n")
          }

          # Load reference to check what SILVA IDs look like
          tryCatch({
            silva_ref <- readRDS(file.path(ref_path, "t4f_silva_to_kegg.rds"))
            silva_ids <- rownames(silva_ref)
            cat("[Tax4Fun] SILVA reference has", length(silva_ids), "entries\n")
            cat("[Tax4Fun] First 5 SILVA IDs:\n")
            for (sid in head(silva_ids, 5)) cat("  ", sid, "\n")

            # Check how many of our taxa match
            our_ids <- apply(tax_mat, 1, function(l) {
              paste0(paste0(l[!is.na(l) & l != ""], collapse = ";"), ";")
            })
            n_match <- sum(our_ids %in% silva_ids)
            cat("[Tax4Fun] Taxa matching SILVA reference:", n_match, "of",
                length(our_ids), "\n")
            if (n_match == 0 && length(our_ids) > 0) {
              cat("[Tax4Fun] WARNING: ZERO MATCHES! Showing comparison:\n")
              cat("[Tax4Fun]   Our first ID:   '", our_ids[1], "'\n")
              cat("[Tax4Fun]   SILVA first ID: '", silva_ids[1], "'\n")
              # Try partial matching
              our_kingdoms <- unique(tax_mat[, 1][!is.na(tax_mat[, 1])])
              silva_kingdoms <- unique(sub(";.*", "", silva_ids))
              cat("[Tax4Fun]   Our Kingdom values:", paste(head(our_kingdoms, 5), collapse=", "), "\n")
              cat("[Tax4Fun]   SILVA Kingdom values:", paste(head(silva_kingdoms, 5), collapse=", "), "\n")
            }
          }, error = function(e) {
            cat("[Tax4Fun] Could not inspect SILVA ref:", e$message, "\n")
          })

          # --- Run t4f() ---
          incProgress(0.3, detail = "Predicting KEGG functions (t4f)...")

          cn_norm     <- isTRUE(input$cn_normalize %||% TRUE)
          sample_norm <- isTRUE(input$sample_normalize %||% TRUE)

          predicted <- themetagenomics::t4f(
            otu_table        = otu_mat,
            rows_are_taxa    = FALSE,
            tax_table        = tax_mat,
            reference_path   = ref_path,
            type             = "uproc",
            short            = TRUE,
            cn_normalize     = cn_norm,
            sample_normalize = sample_norm,
            drop             = TRUE
          )

          incProgress(0.9, detail = "Processing results")

          # --- Diagnostic: inspect raw t4f() return ---
          cat("[Tax4Fun] t4f() returned class:", paste(class(predicted), collapse = "/"), "\n")
          cat("[Tax4Fun] t4f() names:", paste(names(predicted), collapse = ", "), "\n")
          if (!is.null(predicted$fxn_table)) {
            cat("[Tax4Fun] fxn_table class:", paste(class(predicted$fxn_table), collapse = "/"), "\n")
            cat("[Tax4Fun] fxn_table dim:", paste(dim(predicted$fxn_table), collapse = " x "), "\n")
            if (prod(dim(predicted$fxn_table)) > 0) {
              cat("[Tax4Fun] fxn_table range:", range(predicted$fxn_table, na.rm = TRUE), "\n")
            }
          } else {
            cat("[Tax4Fun] WARNING: fxn_table is NULL!\n")
          }

          # t4f() returns:
          #   $fxn_table = matrix with SAMPLES as rows, KOs as columns
          #   $fxn_meta  = data.frame with metadata per KO
          # We transpose so functions are rows (for heatmap: Y = functions, X = samples)
          fxn_table <- t(predicted$fxn_table)   # now: functions (rows) x samples (cols)
          fxn_meta_raw <- predicted$fxn_meta

          cat("[Tax4Fun] Predicted KOs:", nrow(fxn_table), "\n")
          cat("[Tax4Fun] Samples in result:", ncol(fxn_table), "\n")
          cat("[Tax4Fun] fxn_meta class:", paste(class(fxn_meta_raw), collapse = "/"), "\n")
          cat("[Tax4Fun] fxn_meta names:", paste(names(fxn_meta_raw), collapse = ", "), "\n")

          # ----------------------------------------------------------
          # Build fxn_meta data.frame aligned to predicted KOs
          # ----------------------------------------------------------
          # t4f() returns fxn_meta as a list with:
          #   $KEGG_Description : named chr vector (length = ALL ref KOs, e.g. 9339)
          #                       names are KO IDs → use as lookup
          #   $KEGG_Pathways    : named list of lists (one per predicted KO)
          #                       each element = list of pathway strings
          # We build a tidy data.frame with one row per predicted KO.
          fxn_meta <- NULL
          ko_ids   <- rownames(fxn_table)   # predicted KO IDs

          tryCatch({
            if (is.data.frame(fxn_meta_raw)) {
              # Already a data.frame — use directly
              fxn_meta <- fxn_meta_raw
              cat("[Tax4Fun] fxn_meta already a data.frame:",
                  nrow(fxn_meta), "rows\n")

            } else if (is.list(fxn_meta_raw)) {
              # --- KEGG_Description: named char vector (lookup) ---
              desc_vec <- fxn_meta_raw[["KEGG_Description"]]
              desc_col <- rep(NA_character_, length(ko_ids))
              if (!is.null(desc_vec) && is.character(desc_vec)) {
                desc_col <- unname(desc_vec[ko_ids])
                n_found  <- sum(!is.na(desc_col))
                cat("[Tax4Fun] KEGG_Description lookup:", n_found,
                    "of", length(ko_ids), "KOs matched\n")
              }

              # --- KEGG_Pathways: named list of lists (flatten) ---
              pw_raw   <- fxn_meta_raw[["KEGG_Pathways"]]
              pw_col   <- rep(NA_character_, length(ko_ids))
              if (!is.null(pw_raw) && is.list(pw_raw)) {
                for (i in seq_along(ko_ids)) {
                  kid <- ko_ids[i]
                  pw_entry <- pw_raw[[kid]]
                  if (!is.null(pw_entry)) {
                    # Each entry is a list of pathway strings — unlist & paste
                    paths <- unlist(pw_entry, use.names = FALSE)
                    paths <- paths[!is.na(paths) & nzchar(paths)]
                    if (length(paths) > 0)
                      pw_col[i] <- paste(paths, collapse = "; ")
                  }
                }
                n_pw <- sum(!is.na(pw_col))
                cat("[Tax4Fun] KEGG_Pathways flattened:", n_pw,
                    "of", length(ko_ids), "KOs have pathway info\n")
              }

              fxn_meta <- data.frame(
                KEGG_Description = desc_col,
                KEGG_Pathways    = pw_col,
                stringsAsFactors = FALSE
              )
              rownames(fxn_meta) <- ko_ids
              cat("[Tax4Fun] Built fxn_meta:", nrow(fxn_meta), "rows,",
                  ncol(fxn_meta), "cols\n")
            }
          }, error = function(e) {
            cat("[Tax4Fun] fxn_meta conversion error:", e$message, "\n")
            fxn_meta <<- NULL
          })

          if (is.null(fxn_meta))
            cat("[Tax4Fun] No usable fxn_meta -- KO descriptions unavailable\n")

          incProgress(1, detail = "Done")
          showNotification("\u2705 Tax4Fun prediction completed.", type = "message")

          list(
            fxn_table = fxn_table,
            fxn_meta  = fxn_meta,
            pseq      = pseq
          )
        })
      }, error = function(e) {
        cat("[Tax4Fun] PIPELINE ERROR:", conditionMessage(e), "\n")
        cat("[Tax4Fun] Call:", deparse(conditionCall(e)), "\n")
        showNotification(paste0("Tax4Fun error: ", e$message),
                         type = "error", duration = 15)
        NULL
      })
      result
    })

    # ------------------------------------------------------------------
    # Build display table based on selected aggregation level
    # ------------------------------------------------------------------
    # Helper: build a KO -> description lookup from fxn_meta
    .ko_description_map <- function(fxn_meta, ko_ids) {
      if (is.null(fxn_meta) || !is.data.frame(fxn_meta) || NROW(fxn_meta) == 0)
        return(setNames(ko_ids, ko_ids))

      # Try every plausible column name for descriptions
      desc_candidates <- c("KEGG_Description", "Description", "description",
                           "ko_description", "KO_Description", "desc", "name")
      desc_col <- NULL
      for (cand in desc_candidates) {
        if (cand %in% colnames(fxn_meta)) { desc_col <- cand; break }
      }

      if (is.null(desc_col)) {
        # If no obvious description column, check if any text column exists
        text_cols <- colnames(fxn_meta)[sapply(fxn_meta, is.character)]
        text_cols <- setdiff(text_cols, c("KEGG_Pathways", "Pathways", "pathway"))
        if (length(text_cols) > 0) desc_col <- text_cols[1]
      }

      if (is.null(desc_col)) return(setNames(ko_ids, ko_ids))

      descs <- as.character(fxn_meta[[desc_col]])
      # Match by row index (fxn_meta rows correspond to fxn_table rows)
      if (length(descs) == length(ko_ids)) {
        labels <- ifelse(nzchar(descs) & !is.na(descs),
                         paste0(ko_ids, " - ", descs), ko_ids)
      } else {
        labels <- ko_ids
      }
      setNames(labels, ko_ids)
    }

    display_table <- reactive({
      res <- tax4fun_results()
      req(res)

      fxn_table <- res$fxn_table
      fxn_meta  <- res$fxn_meta
      agg       <- input$agg_level %||% "ko"

      # Build KO description lookup
      ko_ids   <- rownames(fxn_table)
      ko_descs <- .ko_description_map(fxn_meta, ko_ids)

      if (agg == "ko") {
        # KO-level table: rows = KOs, cols = samples
        mat <- as.data.frame(fxn_table)
        mat$Function <- unname(ko_descs[rownames(mat)])
        mat <- mat[, c("Function", setdiff(colnames(mat), "Function")), drop = FALSE]
        mat

      } else if (agg == "pathway") {
        # Aggregate to KEGG pathway level
        # Detect the pathway column flexibly
        pw_candidates <- c("KEGG_Pathways", "Pathways", "pathway",
                           "KEGG_Pathway", "Pathway", "kegg_pathways")
        pw_col_name <- NULL
        if (!is.null(fxn_meta) && is.data.frame(fxn_meta) && ncol(fxn_meta) > 0) {
          for (cand in pw_candidates) {
            if (cand %in% colnames(fxn_meta)) { pw_col_name <- cand; break }
          }
        }

        if (is.null(pw_col_name)) {
          meta_cols <- if (!is.null(fxn_meta) && is.data.frame(fxn_meta))
            paste(colnames(fxn_meta), collapse = ", ") else "(none)"
          cat("[Tax4Fun] No pathway column found. fxn_meta columns:", meta_cols, "\n")
          showNotification(
            paste0("No pathway column found. Showing KO-level with descriptions. ",
                   "Available meta columns: ", meta_cols),
            type = "warning", duration = 10)
          # Fallback to KO-level with descriptions
          mat <- as.data.frame(fxn_table)
          mat$Function <- unname(ko_descs[rownames(mat)])
          mat <- mat[, c("Function", setdiff(colnames(mat), "Function")), drop = FALSE]
          return(mat)
        }

        # Each KO can map to multiple pathways (semicolon-separated)
        pathway_col <- as.character(fxn_meta[[pw_col_name]])
        ko_names    <- rownames(fxn_table)

        # Generic KEGG top-level categories to exclude — these are
        # umbrella terms, not real pathways
        generic_pw <- tolower(c(
          "metabolism", "overview", "genetic information processing",
          "environmental information processing", "cellular processes",
          "organismal systems", "human diseases",
          "drug development", "not included in regular maps",
          "brite hierarchies", "poorly characterized",
          "cell growth and death", "cell motility",
          "transport and catabolism",
          "membrane transport", "signal transduction",
          "transcription", "translation",
          "replication and repair",
          "folding, sorting and degradation"
        ))

        # Build long-form: KO -> pathway mapping
        pathway_list <- list()
        for (i in seq_along(pathway_col)) {
          if (is.na(pathway_col[i])) next
          paths <- trimws(unlist(strsplit(pathway_col[i], ";")))
          paths <- paths[nzchar(paths) & !paths %in% c("NA", "")]
          # Remove generic top-level categories
          paths <- paths[!tolower(paths) %in% generic_pw]
          if (length(paths) > 0) {
            for (p in paths) {
              pathway_list[[length(pathway_list) + 1]] <- list(
                pathway = p, idx = i
              )
            }
          }
        }

        if (length(pathway_list) == 0) {
          showNotification("No pathway annotations found. Showing KO-level.",
                           type = "warning")
          mat <- as.data.frame(fxn_table)
          mat$Function <- unname(ko_descs[rownames(mat)])
          mat <- mat[, c("Function", setdiff(colnames(mat), "Function")), drop = FALSE]
          return(mat)
        }

        # Aggregate abundances per pathway
        pathway_names <- unique(sapply(pathway_list, `[[`, "pathway"))
        agg_mat <- matrix(0, nrow = length(pathway_names), ncol = ncol(fxn_table))
        rownames(agg_mat) <- pathway_names
        colnames(agg_mat) <- colnames(fxn_table)

        for (item in pathway_list) {
          agg_mat[item$pathway, ] <- agg_mat[item$pathway, ] +
            as.numeric(fxn_table[item$idx, ])
        }

        mat <- as.data.frame(agg_mat)
        mat$Function <- rownames(mat)   # pathway names are already descriptive
        mat <- mat[, c("Function", setdiff(colnames(mat), "Function")), drop = FALSE]
        mat
      } else {
        # Fallback: KO-level with descriptions
        mat <- as.data.frame(fxn_table)
        mat$Function <- unname(ko_descs[rownames(mat)])
        mat <- mat[, c("Function", setdiff(colnames(mat), "Function")), drop = FALSE]
        mat
      }
    })

    # ------------------------------------------------------------------
    # Heatmap
    # ------------------------------------------------------------------
    tax4fun_heatmap <- reactive({
      res <- display_table()
      req(res, nrow(res) > 0, ncol(res) > 1)

      mat <- as.matrix(res[, -1, drop = FALSE])
      rownames(mat) <- res$Function
      mode(mat) <- "numeric"
      mat[is.na(mat)] <- 0

      # --- Aggregate samples by group mean (if requested) ---
      annot_col <- NULL
      if (isTRUE(input$aggregate_groups) && !is.null(input$group_variable)) {
        md <- tryCatch(as(sample_data(physeq_cleaned()), "data.frame"),
                       error = function(e) NULL)
        if (!is.null(md) && input$group_variable %in% colnames(md)) {
          grp_vec <- as.character(md[[input$group_variable]])
          names(grp_vec) <- rownames(md)
          # Keep only samples present in mat
          common <- intersect(colnames(mat), names(grp_vec))
          if (length(common) > 1) {
            mat <- mat[, common, drop = FALSE]
            grp_factor <- grp_vec[common]
            # Average within each group
            groups_unique <- sort(unique(grp_factor))
            mat_agg <- sapply(groups_unique, function(g) {
              cols <- which(grp_factor == g)
              if (length(cols) == 1) mat[, cols] else rowMeans(mat[, cols, drop = FALSE], na.rm = TRUE)
            })
            rownames(mat_agg) <- rownames(mat)
            colnames(mat_agg) <- groups_unique
            mat <- mat_agg
          }
        }
      } else if (isTRUE(input$annotate_groups) && !is.null(input$group_variable)) {
        # Not aggregating — show individual samples with group annotation strip
        md <- tryCatch(as(sample_data(physeq_cleaned()), "data.frame"),
                       error = function(e) NULL)
        if (!is.null(md) && input$group_variable %in% colnames(md)) {
          ann_df <- data.frame(Group = as.character(md[[input$group_variable]]),
                               row.names = rownames(md))
          common <- intersect(colnames(mat), rownames(ann_df))
          if (length(common) > 0) {
            annot_col <- ann_df[common, , drop = FALSE]
          }
        }
      }

      # pick top-N rows by variance
      top_n <- min(as.integer(input$top_n_functions %||% 50), nrow(mat))
      row_var <- apply(mat, 1, function(x) stats::var(x, na.rm = TRUE))
      row_var[is.na(row_var)] <- 0
      top_idx <- order(row_var, decreasing = TRUE)[seq_len(top_n)]
      mat_top <- mat[top_idx, , drop = FALSE]

      # optional z-scoring
      if (isTRUE(input$scale_rows)) {
        mat_top <- t(scale(t(mat_top)))
        mat_top[!is.finite(mat_top)] <- 0
      }

      # palette
      color_pal <- input$color_palette %||% "YlGnBu"
      pal <- switch(
        color_pal,
        "YlGnBu" = colorRampPalette(RColorBrewer::brewer.pal(9, "YlGnBu"))(100),
        "RdBu"   = colorRampPalette(rev(RColorBrewer::brewer.pal(9, "RdBu")))(100),
        "YlOrRd" = colorRampPalette(RColorBrewer::brewer.pal(9, "YlOrRd"))(100),
        "Blues"   = colorRampPalette(RColorBrewer::brewer.pal(9, "Blues"))(100),
        "Greens"  = colorRampPalette(RColorBrewer::brewer.pal(9, "Greens"))(100),
        "Reds"    = colorRampPalette(RColorBrewer::brewer.pal(9, "Reds"))(100),
        "Viridis" = viridisLite::viridis(100),
        "Magma"   = viridisLite::magma(100),
        colorRampPalette(RColorBrewer::brewer.pal(9, "YlGnBu"))(100)
      )

      agg_level <- input$agg_level %||% "ko"
      agg_label <- switch(agg_level,
                           "ko" = "KO", "pathway" = "Pathway", "module" = "Module")

      fontsize_val <- as.numeric(input$font_size %||% 9)
      pheatmap::pheatmap(
        mat_top,
        color            = pal,
        cluster_rows     = isTRUE(input$cluster_rows %||% TRUE),
        cluster_cols     = isTRUE(input$cluster_cols %||% TRUE),
        clustering_distance_rows = "euclidean",
        clustering_distance_cols = "euclidean",
        clustering_method = "complete",
        fontsize         = fontsize_val,
        fontsize_row     = fontsize_val - 1,
        annotation_col   = annot_col,
        main = paste0("Top ", nrow(mat_top),
                      " predicted functions (Tax4Fun \u2014 ", agg_label, ")"),
        silent = TRUE
      )
    })

    # --- render heatmap ---
    output$tax4fun2_heatmap <- renderPlot({
      if (is.null(input$run_tax4fun2) || input$run_tax4fun2 == 0) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.55,
                     label = "Click 'Run Tax4Fun' to start",
                     size = 6, fontface = "bold", color = "#3B82F6") +
            ggplot2::annotate("text", x = 0.5, y = 0.43,
                     label = "Requires the SILVA-KO reference (downloadable above).",
                     size = 4, color = "#7F8C8D") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }
      hm <- tryCatch(tax4fun_heatmap(), error = function(e) {
        cat("[Tax4Fun] Heatmap error:", e$message, "\n")
        NULL
      })
      if (is.null(hm)) {
        return(
          ggplot2::ggplot() + ggplot2::theme_void() +
            ggplot2::annotate("text", x = 0.5, y = 0.5,
                     label = "Tax4Fun ran but heatmap could not be generated.\nCheck R console for details.",
                     size = 5, color = "#E74C3C") +
            ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1)
        )
      }
      grid::grid.newpage()
      grid::grid.draw(hm$gtable)
    }, res = 120)

    # ------------------------------------------------------------------
    # Stats / table
    # ------------------------------------------------------------------
    output$tax4fun2_summary <- renderPrint({
      if (is.null(input$run_tax4fun2) || input$run_tax4fun2 == 0) {
        cat("Click 'Run Tax4Fun' to predict functional profiles.\n")
        cat("If the SILVA-KO reference is missing, use the download button.\n")
        return(invisible(NULL))
      }
      res <- tax4fun_results()
      req(res)
      dtable <- display_table()
      agg_lev <- input$agg_level %||% "ko"
      cat("Tax4Fun Functional Prediction Summary\n")
      cat("-------------------------------------\n")
      cat("Reference:           ", resolve_db_path(), "\n", sep = "")
      cat("Functional level:    ", toupper(agg_lev), "\n", sep = "")
      cat("Total KOs predicted: ", nrow(res$fxn_table), "\n", sep = "")
      if (!is.null(dtable)) {
        cat("Display functions:   ", nrow(dtable), " (", agg_lev, ")\n", sep = "")
      }
      cat("Samples:             ", ncol(res$fxn_table), "\n", sep = "")
      cat("Copy-number norm:    ", ifelse(isTRUE(input$cn_normalize %||% TRUE), "Yes", "No"), "\n", sep = "")
      cat("Sample norm:         ", ifelse(isTRUE(input$sample_normalize %||% TRUE), "Yes", "No"), "\n", sep = "")
    })

    output$tax4fun2_table <- DT::renderDataTable({
      dtable <- display_table()
      req(dtable)
      DT::datatable(
        dtable,
        options = list(pageLength = 15, scrollX = TRUE, dom = "frtip"),
        rownames = FALSE
      )
    })

    # ------------------------------------------------------------------
    # Downloads
    # ------------------------------------------------------------------
    output$download_tax4fun2_table <- downloadHandler(
      filename = function() ezmap_filename(
                                paste0("Tax4Fun_", input$agg_level %||% "ko"),
                                "csv"),
      content  = function(file) {
        dtable <- display_table()
        req(dtable)
        utils::write.csv(dtable, file, row.names = FALSE)
      }
    )

    output$download_tax4fun2_heatmap <- downloadHandler(
      filename = function() ezmap_download_filename(input, "Tax4Fun_Heatmap"),
      content  = function(file) {
        hm <- tax4fun_heatmap()
        req(hm)
        grDevices::png(file, width = 10, height = 8, units = "in", res = 300)
        grid::grid.newpage(); grid::grid.draw(hm$gtable)
        grDevices::dev.off()
      }
    )
  })
}
