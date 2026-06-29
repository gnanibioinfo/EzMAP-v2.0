randomForestServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    # Guard optional packages — show notification and return early if missing
    .rf_deps_ok <- TRUE
    for (.pkg in c("randomForest", "caret", "pROC", "tidyr")) {
      if (!requireNamespace(.pkg, quietly = TRUE)) {
        showNotification(
          paste0("Package '", .pkg, "' is not installed. Random Forest analysis is disabled. ",
                 "Install it with: install.packages('", .pkg, "')"),
          type = "error", duration = NULL
        )
        .rf_deps_ok <- FALSE
      }
    }

    if (.rf_deps_ok) {
      library(randomForest)
      library(caret)
      library(pROC)
      library(tidyr)
    }

    library(dplyr)
    library(ggplot2)
    library(phyloseq)
    library(RColorBrewer)

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # --- 1. Preprocessing + Filtering ---
    physeq_normalized <- reactive({
      req(.rf_deps_ok)  # Block analysis if required packages are missing
      # Start progress bar for data loading and preprocessing
      withProgress(message = "Preparing Data...", value = 0, {

        req(physeq_data())
        Bacteria <- physeq_data()
        
        incProgress(0.1, detail = "Standardizing taxonomy")

        # NOTE: Do NOT rename taxa here. The upload server already assigned
        # canonical "ASV1..ASV(N_raw)" IDs and the Filter tab preserves them.
        # Renaming locally would re-number the surviving taxa to
        # "ASV1..ASV(local_n)", silently desyncing RF's IDs from ANCOM-BC's
        # and breaking the DESeq2+RF / ANCOM-BC+RF overlap panels (they
        # would join on disjoint ID spaces). Rename removed.

        # --- Taxonomy ranks (defensive) ---
        if (ncol(tax_table(Bacteria)) >= 7) {
            colnames(tax_table(Bacteria)) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")[1:ncol(tax_table(Bacteria))]
        }

        # NOTE: NO local taxa filtering or count normalization.
        # The central Filter tab is the single source of truth for taxa
        # filtering. Previously this reactive ran:
        #     subset_taxa(!grepl("Eukaryota|Archaea", Kingdom))   # kills fungi on ITS
        #     filter_taxa(sum(x > 3) > 0.2 * length(x))           # 20% data-wide
        #     transform_sample_counts(median-depth)               # not needed for RF
        # The 20% data-wide prevalence filter masked condition-specific
        # signal (same bug Beta and Network had — every per-group RF
        # run ended up training on the same fixed taxa set). Random
        # Forest classifies on raw abundance values; it does not
        # require pre-normalized counts.

        incProgress(0.3, detail = "Cleaning taxonomy strings")

        # --- Strip taxonomy prefixes (defensive — central upload also does this) ---
        tax_df <- as.data.frame(tax_table(Bacteria))
        for (col in colnames(tax_df)) {
            tax_df[[col]] <- gsub("[Dd]_[0-9]+__", "", tax_df[[col]])
            tax_df[[col]] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_df[[col]])
            tax_df[[col]] <- trimws(tax_df[[col]])
        }
        tax_table(Bacteria) <- tax_table(as.matrix(tax_df))

        incProgress(1, detail = "Finished.")

        showNotification(
          paste0("RF data ready: ", ntaxa(Bacteria), " ASVs / ",
                 nsamples(Bacteria), " samples (matches Filter tab)."),
          type = "message", duration = 6
        )

        return(Bacteria)
      })
    })
    
    # --- Dynamic taxonomic level selection ---
    output$rel_abund_level_ui <- renderUI({
      pseq <- physeq_normalized()
      req(pseq)
      
      tax_cols <- colnames(tax_table(pseq))
      
      # Only show levels with >0 non-NA taxa
      valid_levels <- tax_cols[sapply(tax_cols, function(x) sum(!is.na(tax_table(pseq)[, x])) > 0)]
      selectInput(session$ns("rel_abund_level"), "Group by Taxonomic Level:", 
                  choices = valid_levels, selected = tail(valid_levels, 1))
    })
    
    
    # --- 2. Group Variable Selection ---
    output$group_variable_ui <- renderUI({
      pseq <- physeq_normalized()
      req(pseq)
      metadata <- as(sample_data(pseq), "data.frame")
      # Filter for factors/chars with > 1 unique non-NA level
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(na.omit(x))) > 1)]
      selectInput(session$ns("group_variable"), "Select Classification Variable:", choices = group_vars)
    })
    
    # --- 3. Select two groups ---
    output$comparison_ui <- renderUI({
      req(input$group_variable)
      pseq <- physeq_normalized()
      metadata <- as(sample_data(pseq), "data.frame")
      levels_group <- unique(as.character(na.omit(metadata[[input$group_variable]])))

      req(length(levels_group) >= 2, "Selected group variable must have at least two levels.")

      tagList(
        selectInput(session$ns("group_1"), "Group 1 (Reference):", choices = levels_group, selected = levels_group[1]),
        selectInput(session$ns("group_2"), "Group 2 (Comparison):", choices = levels_group, selected = levels_group[2])
      )
    })

    # Per-group ASV / sample breakdown card (shared with Network /
    # DESeq2 / ANCOM-BC panels via group_asv_count_card() in global.r).
    output$group_asv_counts_ui <- renderUI({
      req(input$group_variable)
      group_asv_count_card(
        pseq            = physeq_normalized(),
        category        = input$group_variable,
        selected_groups = c(input$group_1, input$group_2)
      )
    })
    
    # --- 4. Run Random Forest ---
    rf_results <- eventReactive(input$run_randomforest, {
      req(input$group_variable, input$group_1, input$group_2)
      pseq <- physeq_normalized()
      
      # Start progress bar for model training
      withProgress(message = "Training Random Forest...", value = 0, {
        
        # Subset samples
        metadata <- as(sample_data(pseq), "data.frame")
        keep_samples <- rownames(metadata)[metadata[[input$group_variable]] %in% c(input$group_1, input$group_2)]
        sub_pseq <- prune_samples(keep_samples, pseq)

        # Remove taxa that are zero after subsetting
        sub_pseq <- prune_taxa(taxa_sums(sub_pseq) > 0, sub_pseq)

        # --- Taxonomy-level aggregation ---
        tax_rank_val <- if (is.null(input$tax_rank)) "ASV" else input$tax_rank
        if (tax_rank_val != "ASV" && tax_rank_val %in% colnames(tax_table(sub_pseq))) {
            incProgress(0.15, detail = paste0("Aggregating at ", tax_rank_val, " level..."))
            sub_pseq <- tryCatch({
                glom <- tax_glom(sub_pseq, taxrank = tax_rank_val, NArm = FALSE)
                # Rename taxa to their taxonomy label for interpretable feature names
                tax_labels <- as.character(tax_table(glom)[, tax_rank_val])
                tax_labels[is.na(tax_labels) | tax_labels == ""] <- paste0("Unclassified_", taxa_names(glom)[is.na(tax_labels) | tax_labels == ""])
                tax_labels <- make.unique(tax_labels, sep = "_")
                taxa_names(glom) <- tax_labels
                glom
            }, error = function(e) {
                showNotification(paste0("tax_glom at ", tax_rank_val, " failed: ", e$message,
                                        ". Falling back to ASV level."),
                                 type = "warning", duration = 8)
                sub_pseq
            })
        }

        # Prepare data
        # CRITICAL: check.names = FALSE preserves original taxonomy names
        # (e.g. "4C0d-2") so they match taxa_names(sub_pseq) when indexing
        # back into the otu_table for enrichment and abundance calculations.
        predictors <- as.data.frame(t(otu_table(sub_pseq)), check.names = FALSE)
        # Ensure the response variable is only the two selected levels
        response <- factor(sample_data(sub_pseq)[[input$group_variable]])
        response <- droplevels(response[response %in% c(input$group_1, input$group_2)])

        # Filter predictors to the rows that match the kept response.
        keep_rows <- !is.na(response)
        predictors <- predictors[keep_rows, , drop = FALSE]
        response   <- response[keep_rows]

        # --- NULL fallbacks for expert-only parameters ---
        # Default ntree = 500 here AND in the UI numericInput so Easy mode
        # (which hides the input but still receives its default value)
        # matches the Easy-mode banner ("Random Forest with 500 trees…").
        n_trees_val <- if (is.null(input$ntree)) 500 else input$ntree
        top_n_val   <- if (is.null(input$top_n)) 20 else input$top_n

        # --- mtry handling: 0 / NA => use randomForest's default (sqrt p) ---
        n_predictors <- ncol(predictors)
        mtry_user <- suppressWarnings(as.integer(input$mtry))
        if (is.na(mtry_user) || mtry_user < 1L) {
          mtry_val <- max(1L, floor(sqrt(n_predictors)))
        } else {
          mtry_val <- min(mtry_user, n_predictors)  # clamp to p
        }

        incProgress(0.3, detail = paste0("Training with ntree = ", n_trees_val,
                                         ", mtry = ", mtry_val))

        # Train model.
        # NOTE: We deliberately use the MATRIX/x-y interface here instead
        # of the formula interface randomForest(Group ~ ., data = data_rf).
        # The formula interface parses every column name as an R symbol,
        # so taxonomy labels with parentheses, hyphens, or slashes
        # (e.g. "SAR324_clade(Marine_group_B)" produced by tax_glom at
        # Class / Order / Family levels) raise
        #   "object 'SAR324_clade(Marine_group_B)' not found"
        # because R tries to evaluate them as function calls. The matrix
        # interface treats column names as opaque labels — no parsing —
        # so any taxonomy string survives unchanged.
        set.seed(123)
        model_rf <- suppressWarnings(suppressMessages(
            randomForest(x = predictors,
                         y = response,
                         ntree = n_trees_val,
                         mtry  = mtry_val,
                         importance = TRUE)
        ))

        # Build a small data_rf for downstream code (predict() + abundance
        # plots) that still want a single data frame. data_rf must NEVER
        # be passed to randomForest()'s formula interface.
        data_rf <- data.frame(Group = response, predictors, check.names = FALSE)
        
        incProgress(0.7, detail = "Calculating metrics...")
        
        # Feature importance
        imp <- importance(model_rf)
        imp_df <- data.frame(ASV = rownames(imp), MeanDecreaseGini = imp[, "MeanDecreaseGini"]) %>%
          arrange(desc(MeanDecreaseGini))
        imp_df$Rank <- seq_len(nrow(imp_df))

        tax_df <- as.data.frame(tax_table(sub_pseq))
        tax_df$ASV <- rownames(tax_df)
        top_features <- left_join(head(imp_df, top_n_val), tax_df, by = "ASV")

        # --- Determine enriched group per top ASV ------------------------
        # Using relative abundances computed per-sample, then group means.
        sub_pseq_prop_imp <- transform_sample_counts(sub_pseq, function(x) {
          s <- sum(x); if (s > 0) x / s else x
        })
        # Safety: only index features that actually exist in the otu_table
        valid_top_asvs <- intersect(top_features$ASV, taxa_names(sub_pseq_prop_imp))
        if (length(valid_top_asvs) > 0) {
          abund_imp <- as.data.frame(t(otu_table(sub_pseq_prop_imp)[valid_top_asvs, , drop = FALSE]),
                                     check.names = FALSE)
          abund_imp$.Group <- as.character(sample_data(sub_pseq_prop_imp)[[input$group_variable]])
          mean_by_group <- aggregate(. ~ .Group, data = abund_imp, FUN = mean)
          # Rows = groups, columns = ASVs
          rownames(mean_by_group) <- mean_by_group$.Group
          mean_by_group$.Group <- NULL
          grp1_row <- as.numeric(mean_by_group[input$group_1, , drop = TRUE])
          grp2_row <- as.numeric(mean_by_group[input$group_2, , drop = TRUE])
          enriched <- ifelse(is.na(grp1_row) | is.na(grp2_row), NA_character_,
                             ifelse(grp2_row > grp1_row,
                                    input$group_2, input$group_1))
          top_features$Enriched <- enriched[match(top_features$ASV, colnames(mean_by_group))]
        } else {
          top_features$Enriched <- NA_character_
        }
        
        # Confusion matrix
        pred <- predict(model_rf, data_rf)
        conf_mat <- confusionMatrix(pred, data_rf$Group)
        
        # ROC (binary only)
        is_binary <- length(unique(data_rf$Group)) == 2
        roc_data <- NULL
        auc_val <- NA
        if (is_binary) {
          prob_pred <- predict(model_rf, data_rf, type = "prob")
          # The positive class is the second group (Group 2) for standard ROC curve visualization
          pos_class <- input$group_2 
          # Ensure the response levels are in the same order as prob_pred columns
          roc_obj <- roc(data_rf$Group, prob_pred[, pos_class])
          auc_val <- auc(roc_obj)
          roc_data <- data.frame(FPR = 1 - roc_obj$specificities, TPR = roc_obj$sensitivities)
        }
        
        incProgress(1, detail = "Model complete.")
        showNotification("Random Forest training completed.", type = "message")
        
        list(
          model = model_rf,
          predictions = pred,
          confusion = conf_mat,
          importance = imp_df,
          top_features = top_features,
          roc_data = roc_data,
          auc = auc_val,
          is_binary = is_binary,
          data_rf = data_rf,
          ntree = n_trees_val,
          mtry = mtry_val,
          top_n = top_n_val,
          group_1 = input$group_1,
          group_2 = input$group_2,
          tax_df = tax_df,
          tax_rank = tax_rank_val
        )
      })
    })
    
    # ------------------------------------------------------------------
    # 4b. Expert-grade validation (held-out + repeated CV + bootstrap)
    # Added 2026-04-16 to answer expert / peer-review requests for
    # independent validation and feature-importance stability without
    # relying only on OOB error.
    # ------------------------------------------------------------------
    rf_validation <- eventReactive(input$run_validation, {
      res <- rf_results()
      validate(need(!is.null(res),
                    "Run 'Random Forest' first \u2014 the validation reuses the trained configuration."))
      data_rf   <- res$data_rf
      ntree     <- if (!is.null(res$ntree)) res$ntree else 500
      mtry_val  <- if (!is.null(res$mtry))  res$mtry  else NULL
      top_n     <- if (!is.null(res$top_n)) res$top_n else 20
      grp1      <- res$group_1
      grp2      <- res$group_2

      # NULL fallbacks for expert-only validation parameters
      test_frac <- as.numeric(if (is.null(input$test_frac)) 0.25 else input$test_frac)
      cv_folds  <- as.integer(if (is.null(input$cv_folds)) 5 else input$cv_folds)
      cv_reps   <- as.integer(if (is.null(input$cv_repeats)) 10 else input$cv_repeats)
      n_boot    <- as.integer(if (is.null(input$n_bootstrap)) 50 else input$n_bootstrap)

      # Safety bounds
      if (is.na(test_frac) || test_frac <= 0 || test_frac >= 1) test_frac <- 0.25
      if (is.na(cv_folds) || cv_folds < 2) cv_folds <- 2
      if (is.na(cv_reps)  || cv_reps  < 1) cv_reps  <- 1
      if (is.na(n_boot)   || n_boot   < 5) n_boot   <- 5

      y <- data_rf$Group
      X_all <- data_rf
      class_tab <- table(y)
      min_class <- min(class_tab)

      # If a class is too small for k folds, shrink k
      if (min_class < cv_folds) {
        cv_folds <- max(2L, as.integer(min_class))
      }

      withProgress(message = "Running expert-grade validation...", value = 0, {

        # ------------------------------------------------------------
        # 1. Independent held-out test set (stratified split)
        # ------------------------------------------------------------
        incProgress(0.02, detail = "Stratified train/test split...")
        set.seed(2026)
        train_idx <- unlist(lapply(levels(y), function(lv) {
          ids <- which(y == lv)
          n_tr <- max(1L, ceiling(length(ids) * (1 - test_frac)))
          sample(ids, n_tr)
        }))
        test_idx <- setdiff(seq_along(y), train_idx)

        heldout <- list(
          n_train = length(train_idx),
          n_test  = length(test_idx),
          feasible = length(test_idx) >= 2 && length(unique(y[test_idx])) >= 2
        )

        if (heldout$feasible) {
          train_df <- X_all[train_idx, , drop = FALSE]
          test_df  <- X_all[test_idx,  , drop = FALSE]
          train_df$Group <- droplevels(train_df$Group)
          test_df$Group  <- factor(test_df$Group, levels = levels(train_df$Group))

          set.seed(2026)
          mt_h <- if (!is.null(mtry_val))
                    min(mtry_val, ncol(train_df) - 1L)
                  else max(1L, floor(sqrt(ncol(train_df) - 1L)))
          # Matrix interface to survive non-syntactic taxonomy names.
          mh <- suppressWarnings(suppressMessages(
            randomForest(x = train_df[, setdiff(colnames(train_df), "Group"), drop = FALSE],
                         y = train_df$Group,
                         ntree = ntree, mtry = mt_h, importance = FALSE)
          ))
          pred_h <- predict(mh, test_df)
          cm_h   <- tryCatch(
            caret::confusionMatrix(pred_h, test_df$Group),
            error = function(e) NULL)
          auc_h  <- NA_real_
          if (length(levels(train_df$Group)) == 2) {
            prob_h <- predict(mh, test_df, type = "prob")
            pos <- grp2
            if (!pos %in% colnames(prob_h)) pos <- colnames(prob_h)[2]
            auc_h <- tryCatch(
              as.numeric(pROC::auc(pROC::roc(test_df$Group, prob_h[, pos],
                                             levels = levels(train_df$Group), quiet = TRUE))),
              error = function(e) NA_real_)
          }
          heldout$accuracy   <- if (!is.null(cm_h)) as.numeric(cm_h$overall["Accuracy"]) else NA_real_
          heldout$kappa      <- if (!is.null(cm_h)) as.numeric(cm_h$overall["Kappa"])    else NA_real_
          heldout$auc        <- auc_h
          heldout$confusion  <- if (!is.null(cm_h)) cm_h$table else NULL
        }

        # ------------------------------------------------------------
        # 2. Repeated k-fold cross-validation
        # ------------------------------------------------------------
        incProgress(0.03, detail = "Repeated cross-validation...")
        cv_list <- list()
        total_folds <- cv_reps * cv_folds
        fold_counter <- 0L
        cv_budget <- 0.45  # share of the progress bar for CV
        for (rep_i in seq_len(cv_reps)) {
          set.seed(2026 + rep_i)
          folds <- caret::createFolds(y, k = cv_folds, list = TRUE, returnTrain = FALSE)
          for (f_i in seq_along(folds)) {
            fold_counter <- fold_counter + 1L
            test_i <- folds[[f_i]]
            train_i <- setdiff(seq_along(y), test_i)
            tr <- X_all[train_i, , drop = FALSE]
            te <- X_all[test_i,  , drop = FALSE]
            tr$Group <- droplevels(tr$Group)
            te$Group <- factor(te$Group, levels = levels(tr$Group))
            if (length(levels(tr$Group)) < 2 || length(unique(te$Group)) < 1) next
            mt_cv <- if (!is.null(mtry_val))
                       min(mtry_val, ncol(tr) - 1L)
                     else max(1L, floor(sqrt(ncol(tr) - 1L)))
            m <- tryCatch(
              suppressWarnings(suppressMessages(
                # Matrix interface — see comment on the main model fit.
                randomForest(x = tr[, setdiff(colnames(tr), "Group"), drop = FALSE],
                             y = tr$Group,
                             ntree = ntree, mtry = mt_cv, importance = FALSE))),
              error = function(e) NULL)
            if (is.null(m)) next
            p <- predict(m, te)
            acc <- mean(p == te$Group)
            cm <- tryCatch(caret::confusionMatrix(p, te$Group), error = function(e) NULL)
            kp <- if (!is.null(cm)) as.numeric(cm$overall["Kappa"]) else NA_real_
            au <- NA_real_
            if (length(levels(tr$Group)) == 2) {
              pr <- tryCatch(predict(m, te, type = "prob"),
                             error = function(e) NULL)
              if (!is.null(pr)) {
                pos <- grp2
                if (!pos %in% colnames(pr)) pos <- colnames(pr)[2]
                au <- tryCatch(
                  as.numeric(pROC::auc(pROC::roc(te$Group, pr[, pos],
                                                 levels = levels(tr$Group), quiet = TRUE))),
                  error = function(e) NA_real_)
              }
            }
            cv_list[[length(cv_list) + 1L]] <- data.frame(
              Repeat = rep_i, Fold = f_i,
              Accuracy = acc, Kappa = kp, AUC = au)
            if (fold_counter %% max(1L, floor(total_folds / 10)) == 0) {
              incProgress(cv_budget / 10,
                          detail = paste0("CV fold ", fold_counter, " / ", total_folds))
            }
          }
        }
        cv_df <- if (length(cv_list)) do.call(rbind, cv_list) else
                 data.frame(Repeat = integer(0), Fold = integer(0),
                            Accuracy = numeric(0), Kappa = numeric(0), AUC = numeric(0))

        # ------------------------------------------------------------
        # 3. Bootstrap feature-importance stability
        # ------------------------------------------------------------
        incProgress(0.05, detail = "Bootstrap feature stability...")
        feat_cols <- setdiff(colnames(X_all), "Group")
        # Selection count & rank accumulator
        sel_count <- setNames(rep(0L, length(feat_cols)), feat_cols)
        rank_sum  <- setNames(rep(0, length(feat_cols)), feat_cols)
        rank_n    <- setNames(rep(0L, length(feat_cols)), feat_cols)
        boot_budget <- 0.40

        n_rows <- nrow(X_all)
        for (b in seq_len(n_boot)) {
          set.seed(3000 + b)
          idx <- sample.int(n_rows, n_rows, replace = TRUE)
          bdf <- X_all[idx, , drop = FALSE]
          bdf$Group <- droplevels(bdf$Group)
          if (length(levels(bdf$Group)) < 2) next
          mt_b <- if (!is.null(mtry_val))
                    min(mtry_val, ncol(bdf) - 1L)
                  else max(1L, floor(sqrt(ncol(bdf) - 1L)))
          mb <- tryCatch(
            suppressWarnings(suppressMessages(
              # Matrix interface — see comment on the main model fit.
              randomForest(x = bdf[, setdiff(colnames(bdf), "Group"), drop = FALSE],
                           y = bdf$Group,
                           ntree = ntree, mtry = mt_b, importance = FALSE))),
            error = function(e) NULL)
          if (is.null(mb)) next
          imp_b <- importance(mb)
          if (!"MeanDecreaseGini" %in% colnames(imp_b)) next
          gini <- imp_b[, "MeanDecreaseGini"]
          gini <- gini[names(gini) %in% feat_cols]
          ord  <- order(gini, decreasing = TRUE)
          feats_sorted <- names(gini)[ord]
          topN <- head(feats_sorted, top_n)
          sel_count[topN] <- sel_count[topN] + 1L
          ranks <- setNames(seq_along(feats_sorted), feats_sorted)
          rank_sum[names(ranks)] <- rank_sum[names(ranks)] + ranks
          rank_n[names(ranks)]   <- rank_n[names(ranks)]   + 1L
          if (b %% max(1L, floor(n_boot / 10)) == 0) {
            incProgress(boot_budget / 10,
                        detail = paste0("Bootstrap ", b, " / ", n_boot))
          }
        }

        # Build stability dataframe
        mean_rank <- ifelse(rank_n > 0, rank_sum / rank_n, NA_real_)
        sel_freq  <- sel_count / max(1L, n_boot)
        stab_df <- data.frame(
          ASV = feat_cols,
          SelectionFreq = as.numeric(sel_freq[feat_cols]),
          SelectionCount = as.integer(sel_count[feat_cols]),
          MeanRank = as.numeric(mean_rank[feat_cols]),
          stringsAsFactors = FALSE
        )
        stab_df <- stab_df[order(-stab_df$SelectionFreq, stab_df$MeanRank), , drop = FALSE]

        # Attach taxonomy (cleaned genus/family) for display labels
        tax_df <- res$tax_df
        if (!is.null(tax_df)) {
          tax_df$ASV <- rownames(tax_df)
          stab_df <- merge(stab_df, tax_df, by = "ASV", all.x = TRUE, sort = FALSE)
          stab_df <- stab_df[order(-stab_df$SelectionFreq, stab_df$MeanRank), , drop = FALSE]
        }

        incProgress(1, detail = "Finishing up...")
        showNotification("Expert-grade validation complete.", type = "message")

        list(
          heldout = heldout,
          cv = cv_df,
          stability = stab_df,
          top_n = top_n,
          n_boot = n_boot,
          cv_folds = cv_folds,
          cv_repeats = cv_reps,
          test_frac = test_frac
        )
      })
    })

    # --- 5. Plots, metrics, interpretation ---
    # Shared helper: strip SILVA ("D_5__") and Greengenes ("g__") prefixes.
    .clean_taxon_rf <- function(x) {
      x <- as.character(x)
      x[is.na(x)] <- ""
      x <- sub("^D_[0-9]+__", "", x, perl = TRUE)
      x <- sub("^[kpcofgsKPCOFGS]__", "", x, perl = TRUE)
      trimws(x)
    }

    # Helper builds the importance ggplot so render + download stay in sync.
    build_rf_importance_plot <- function(res, grp1, grp2, col_ref, col_comp, top_n, input = NULL) {
      df <- res$top_features
      tax_rank <- if (!is.null(res$tax_rank)) res$tax_rank else "ASV"
      feature_label <- if (tax_rank == "ASV") "ASV" else tax_rank

      # Fallback if Enriched column is missing (backwards-compat)
      if (!"Enriched" %in% colnames(df)) df$Enriched <- NA_character_
      df$Enriched <- factor(df$Enriched, levels = c(grp1, grp2))
      fill_vec <- setNames(c(col_ref, col_comp), c(grp1, grp2))

      # Build display label depending on taxonomy level
      if (tax_rank != "ASV") {
        # At aggregated level, the feature name IS the taxon name
        df$.display <- as.character(df$ASV)
        df$.display[is.na(df$.display) | df$.display == ""] <- "Unclassified"
      } else {
        # At ASV level: cleaned Genus > Family, then ASV id in parentheses.
        genus_clean  <- if ("Genus"  %in% colnames(df)) .clean_taxon_rf(df$Genus)  else rep("", nrow(df))
        family_clean <- if ("Family" %in% colnames(df)) .clean_taxon_rf(df$Family) else rep("", nrow(df))
        df$.display <- ifelse(
          nzchar(genus_clean),
          paste0(genus_clean, " (", df$ASV, ")"),
          ifelse(
            nzchar(family_clean),
            paste0(family_clean, " (", df$ASV, ")"),
            df$ASV))
      }
      # Ensure uniqueness (two features can share a name)
      df$.display <- make.unique(df$.display, sep = " #")

      # Shared styling block (plot title, theme, grid, X/Y axis-title sizes,
      # legend title/text sizes).
      if (!is.null(input)) {
        styles <- ezmap_plot_styling(input,
                                     default_legend_title = "Importance",
                                     base_size = 14)
      } else {
        styles <- NULL
      }

      auto_title <- paste("Top", top_n, "Important Features (", feature_label, "level )")

      # CRITICAL: wrap each if/else branch in PARENTHESES.
      # Without parens, R parses `+ if (cond) A else B + C` as
      # `+ (if (cond) A else (B + C))` because `else` is greedy on its
      # right-hand operand. Result: when cond is TRUE, the entire tail
      # of the pipeline (theme + labs) gets silently absorbed into the
      # else branch and never applied -- so ggplot's auto-label
      # `reorder(.display, MeanDecreaseGini)` shows up on the x-axis
      # instead of the publication-ready `Mean Decrease Gini`.
      ggplot(df, aes(x = reorder(.display, MeanDecreaseGini),
                     y = MeanDecreaseGini, fill = Enriched)) +
        geom_bar(stat = "identity") +
        coord_flip() +
        scale_fill_manual(values = fill_vec, drop = FALSE,
                          name = "Enriched in",
                          na.value = "#95A5A6") +
        (if (!is.null(styles)) styles$theme_fn(base_size = 14) else theme_bw(base_size = 14)) +
        (if (!is.null(styles)) styles$grid_theme else theme()) +
        theme(legend.position = "top",
              plot.title = element_text(face = "bold")) +
        labs(title    = if (!is.null(styles) && !is.null(styles$title)) styles$title else auto_title,
             subtitle = paste0("Bars are colored by which group has higher mean relative abundance (",
                               grp1, " vs ", grp2, ")"),
             x = feature_label,
             y = if (!is.null(input$customXLabel) && nzchar(input$customXLabel)) input$customXLabel
                 else "Mean Decrease Gini")
    }

    output$rf_plot <- renderPlot({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) {
        return(
          ggplot() +
            annotate("text", x = 0.5, y = 0.58,
                     label = "Configure groups and click 'Run Random Forest'",
                     size = 5.5, fontface = "bold", color = "#3B82F6") +
            annotate("text", x = 0.5, y = 0.45,
                     label = "Top important ASVs will appear here, colored by enriched group.",
                     size = 4, color = "#7F8C8D") +
            theme_void() + xlim(0, 1) + ylim(0, 1)
        )
      }
      res <- rf_results()
      validate(need(!is.null(res), "Random Forest did not return results."))
      # NULL fallbacks for expert-only color parameters
      col_ref  <- if (!is.null(input$imp_color_ref)  && nzchar(input$imp_color_ref))  input$imp_color_ref  else "#1f77b4"
      col_comp <- if (!is.null(input$imp_color_comp) && nzchar(input$imp_color_comp)) input$imp_color_comp else "#d62728"
      top_n_plot <- if (is.null(input$top_n)) 20 else input$top_n
      build_rf_importance_plot(res, input$group_1, input$group_2,
                               col_ref, col_comp, top_n_plot, input = input)
    })
    
    output$rf_roc_plot <- renderPlot({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) {
        return(
          ggplot() + annotate("text", x = 0.5, y = 0.5,
            label = "ROC curve appears after 'Run Random Forest'.",
            size = 4.5, color = "#7F8C8D") +
          theme_void() + xlim(0,1) + ylim(0,1))
      }
      res <- rf_results()
      validate(
        need(!is.null(res), "Random Forest did not return results."),
        need(isTRUE(res$is_binary), "ROC curve is only available for binary classification."),
        need(!is.null(res$roc_data), "ROC data is empty.")
      )
      ggplot(res$roc_data, aes(x = FPR, y = TPR)) +
        geom_line(color = "darkred", size = 1.2) +
        geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray") +
        theme_minimal(base_size = 15) +
        labs(title = paste0("ROC Curve (AUC = ", round(res$auc, 3), ")"),
             x = "False Positive Rate", y = "True Positive Rate")
    })
    
    # --- Relative Abundance Plot (Top OTUs by Gini Importance)
    output$rf_abundance_plot <- renderPlot({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) {
        return(
          ggplot() + annotate("text", x = 0.5, y = 0.5,
            label = "Relative abundance of top ASVs appears after 'Run Random Forest'.",
            size = 4.5, color = "#7F8C8D") +
          theme_void() + xlim(0,1) + ylim(0,1))
      }
      res <- rf_results()
      validate(need(!is.null(res), "Random Forest did not return results."))
      # NULL fallback for expert-only palette
      ra_palette <- if (is.null(input$ra_palette)) "Set1" else input$ra_palette
      req(input$group_variable, input$group_1, input$group_2, ra_palette)

      pseq <- physeq_normalized()
      metadata <- as(sample_data(pseq), "data.frame")

      # Keep only selected groups
      keep_samples <- rownames(metadata)[metadata[[input$group_variable]] %in% c(input$group_1, input$group_2)]
      sub_pseq <- prune_samples(keep_samples, pseq)
      sub_pseq <- prune_taxa(taxa_sums(sub_pseq) > 0, sub_pseq)

      # Apply the same taxonomy-level aggregation used during training
      tax_rank <- if (!is.null(res$tax_rank)) res$tax_rank else "ASV"
      if (tax_rank != "ASV" && tax_rank %in% colnames(tax_table(sub_pseq))) {
          sub_pseq <- tryCatch({
              glom <- tax_glom(sub_pseq, taxrank = tax_rank, NArm = FALSE)
              tax_labels <- as.character(tax_table(glom)[, tax_rank])
              tax_labels[is.na(tax_labels) | tax_labels == ""] <- paste0("Unclassified_", taxa_names(glom)[is.na(tax_labels) | tax_labels == ""])
              tax_labels <- make.unique(tax_labels, sep = "_")
              taxa_names(glom) <- tax_labels
              glom
          }, error = function(e) sub_pseq)
      }

      # Ensure top features exist in the subsetted phyloseq object
      top_asvs <- intersect(res$top_features$ASV, taxa_names(sub_pseq))
      if(length(top_asvs) == 0) return(NULL)

      # Abundance data (proportions)
      sub_pseq_prop <- transform_sample_counts(sub_pseq, function(x) x / sum(x))
      abund_mat <- as.data.frame(t(otu_table(sub_pseq_prop)[top_asvs, ]),
                                 check.names = FALSE)
      abund_mat$SampleID <- rownames(abund_mat)
      abund_mat$Group <- sample_data(sub_pseq_prop)[[input$group_variable]]

      # Pivot to long format — use backtick-safe column selection
      abund_long <- abund_mat %>%
        pivot_longer(cols = all_of(top_asvs), names_to = "ASV", values_to = "Abundance") %>%
        group_by(Group, ASV) %>%
        summarise(MeanAbundance = mean(Abundance), .groups = "drop")

      # --- CRITICAL: Set the order for plotting based on Gini Importance ---
      # 1. Filter the sorted ASV list to only include ASVs present in the abundance data.
      sorted_top_asvs <- res$top_features$ASV[res$top_features$ASV %in% abund_long$ASV]
      # 2. Reverse the factor levels so that the most important ASV (first in sorted_top_asvs)
      #    appears at the top when coord_flip() is applied.
      abund_long$ASV <- factor(abund_long$ASV, levels = rev(sorted_top_asvs))

      # Colors from palette
      n_groups <- length(unique(abund_long$Group))
      colors <- RColorBrewer::brewer.pal(min(8, n_groups), ra_palette)
      names(colors) <- unique(abund_long$Group)

      # NULL fallback for expert-only top_n parameter
      top_n_plot <- if (is.null(input$top_n)) 20 else input$top_n
      tax_rank <- if (!is.null(res$tax_rank)) res$tax_rank else "ASV"
      feature_label <- if (tax_rank == "ASV") "ASV" else tax_rank

      # Plot
      ggplot(abund_long, aes(x = ASV, y = MeanAbundance, fill = Group)) +
        geom_bar(stat = "identity", position = position_dodge(width = 0.8)) +
        coord_flip() +
        scale_fill_manual(values = colors) +
        scale_y_continuous(labels = scales::percent) +
        theme_bw(base_size = 14) +
        labs(x = feature_label, y = "Mean Relative Abundance",
             title = paste("Mean Relative Abundance of Top", top_n_plot, "Features (", feature_label, ")")) +
        guides(fill = guide_legend(reverse = TRUE)) +
        theme(legend.title = element_blank())
    })
    
    output$rf_metrics_table <- renderTable({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) return(NULL)
      res <- rf_results()
      validate(need(!is.null(res), "Random Forest did not return results."))
      data.frame(
        Metric = c("Accuracy", "Kappa", if (res$is_binary) "AUC" else NULL),
        Value = round(c(
          res$confusion$overall["Accuracy"],
          res$confusion$overall["Kappa"],
          if (res$is_binary) res$auc else NULL
        ), 3)
      )
    })
    
    output$rf_summary <- renderPrint({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) {
        cat("Click 'Run Random Forest' to train the model.\n")
        cat("Model summary and confusion matrix will appear here.\n")
        return(invisible(NULL))
      }
      res <- rf_results()
      validate(need(!is.null(res), "Random Forest did not return results."))
      cat("Random Forest Model Summary\n")
      cat("----------------------------------\n")
      print(res$model)
      cat("\nConfusion Matrix:\n")
      print(res$confusion$table)
    })
    
    output$rf_interpretation <- renderUI({
      if (is.null(input$run_randomforest) || input$run_randomforest == 0) {
        return(HTML(paste0(
          "<div style='background:#fff3cd; border-left:5px solid #f0ad4e; padding:10px 14px; border-radius:4px; font-size:13px;'>",
          "Interpretation will appear here once you click 'Run Random Forest'.",
          "</div>")))
      }
      res <- rf_results()
      validate(need(!is.null(res), "Random Forest did not return results."))

      # Model Performance Metrics
      accuracy <- round(as.numeric(res$confusion$overall["Accuracy"]), 3)
      kappa    <- round(as.numeric(res$confusion$overall["Kappa"]),    3)
      auc_val  <- if (isTRUE(res$is_binary)) round(as.numeric(res$auc), 3) else NULL

      # OOB error, mtry, ntree, sample counts -- pulled from the randomForest
      # model object so the interpretation stays in sync with the actual fit.
      model_rf   <- res$model
      n_trees    <- if (!is.null(model_rf$ntree)) as.integer(model_rf$ntree) else NA_integer_
      mtry_val   <- if (!is.null(model_rf$mtry))  as.integer(model_rf$mtry)  else NA_integer_
      conf_tbl   <- tryCatch(model_rf$confusion, error = function(e) NULL)
      oob_err    <- NA_real_
      if (!is.null(conf_tbl) && "class.error" %in% colnames(conf_tbl)) {
        counts <- rowSums(conf_tbl[, setdiff(colnames(conf_tbl), "class.error"), drop = FALSE])
        errs   <- as.numeric(conf_tbl[, "class.error"])
        if (sum(counts) > 0) oob_err <- round(sum(counts * errs) / sum(counts), 3)
      }
      n_classes   <- length(unique(as.character(model_rf$y)))
      n_samples   <- length(model_rf$y)
      n_features  <- if (!is.null(model_rf$importance)) nrow(model_rf$importance) else NA_integer_
      class_bal   <- paste(paste0(names(table(model_rf$y)), "=", as.integer(table(model_rf$y))), collapse = ", ")

      # --- Feature importance list --------------------------------------
      top_taxa_items <- apply(res$top_features, 1, function(row) {
        phylum <- .clean_taxon_rf(row["Phylum"])
        genus  <- .clean_taxon_rf(row["Genus"])
        family <- if ("Family" %in% names(row)) .clean_taxon_rf(row["Family"]) else ""
        gini_val <- round(as.numeric(row["MeanDecreaseGini"]), 3)
        asv_id   <- as.character(row["ASV"])
        enr      <- if ("Enriched" %in% names(row)) as.character(row["Enriched"]) else NA_character_

        parts <- character(0)
        if (nzchar(phylum)) parts <- c(parts, phylum)
        if (nzchar(genus))  parts <- c(parts, genus)
        else if (nzchar(family)) parts <- c(parts, family)
        tax_display <- if (length(parts) == 0) "Taxonomy unavailable" else paste(parts, collapse = "; ")

        enr_html <- if (!is.na(enr) && nzchar(enr))
          paste0(" &mdash; <em>enriched in ", enr, "</em>") else ""

        paste0("<li><b>", tax_display, "</b> [", asv_id,
               "] (Gini: ", gini_val, ")", enr_html, "</li>")
      })
      top_taxa_html <- paste0(
        "<ul style='padding-left:20px; margin-top:5px;'>",
        paste(top_taxa_items, collapse = ""),
        "</ul>")

      # --- Performance interpretation & caveats -------------------------
      perf_msg <- if (!is.na(accuracy) && accuracy >= 0.99) {
        paste0("<b style='color:#C0392B;'>Near-perfect accuracy (",
               accuracy, ") on ", n_samples, " samples.</b> ",
               "With small sample sizes this is usually a sign that the model ",
               "memorised the training data. OOB error (",
               ifelse(is.na(oob_err), "NA", oob_err),
               ") partially mitigates this but does not replace an independent ",
               "held-out test set or repeated cross-validation.")
      } else if (!is.na(accuracy) && accuracy >= 0.8) {
        paste0("Accuracy = ", accuracy, " with Kappa = ", kappa,
               " indicates strong agreement beyond chance.")
      } else if (!is.na(accuracy) && accuracy >= 0.6) {
        paste0("Accuracy = ", accuracy, " with Kappa = ", kappa,
               " shows moderate discrimination; the taxa list below should be ",
               "interpreted as suggestive rather than confirmatory.")
      } else {
        paste0("Accuracy = ", accuracy, " with Kappa = ", kappa,
               " is close to chance; the groups may not be separable with ",
               "these features at the current sample size.")
      }

      kappa_msg <- if (is.na(kappa)) "" else if (kappa >= 0.8) {
        "Kappa &ge; 0.8 denotes almost-perfect agreement. "
      } else if (kappa >= 0.6) {
        "Kappa in 0.6\u20130.8 denotes substantial agreement. "
      } else if (kappa >= 0.4) {
        "Kappa in 0.4\u20130.6 denotes moderate agreement. "
      } else if (kappa >= 0.2) {
        "Kappa in 0.2\u20130.4 denotes fair agreement. "
      } else {
        "Kappa &lt; 0.2 denotes poor agreement beyond chance. "
      }

      auc_msg <- if (is.null(auc_val)) {
        "AUC is not reported because this is a multi-class problem."
      } else if (auc_val >= 0.9) {
        "AUC &ge; 0.9 denotes excellent separability of the two classes."
      } else if (auc_val >= 0.8) {
        "AUC in 0.8\u20130.9 denotes good separability."
      } else if (auc_val >= 0.7) {
        "AUC in 0.7\u20130.8 denotes acceptable separability."
      } else {
        "AUC &lt; 0.7 indicates limited discriminatory power."
      }

      # --- Expert-grade validation checklist ----------------------------
      # Pull in the most recent expert-grade validation run, if any, so
      # the three "Not shown here" rows flip to green once the user
      # clicks 'Run Expert-grade Validation'. The call is wrapped in
      # tryCatch so the checklist still renders even if validation has
      # not run.
      val_state <- tryCatch(
        if (!is.null(input$run_validation) && input$run_validation > 0) rf_validation() else NULL,
        error = function(e) NULL)
      has_heldout  <- !is.null(val_state) && isTRUE(val_state$heldout$feasible)
      has_cv       <- !is.null(val_state) && !is.null(val_state$cv) && nrow(val_state$cv) > 0
      has_boot     <- !is.null(val_state) && !is.null(val_state$stability) && nrow(val_state$stability) > 0

      heldout_detail <- if (has_heldout) {
        acc_h <- if (is.na(val_state$heldout$accuracy)) "NA" else round(val_state$heldout$accuracy, 3)
        auc_h <- if (is.na(val_state$heldout$auc))      "NA" else round(val_state$heldout$auc, 3)
        paste0("Stratified ", round((1 - val_state$test_frac) * 100), "/",
               round(val_state$test_frac * 100),
               " split: held-out accuracy = ", acc_h,
               ", held-out AUC = ", auc_h,
               " (n_test = ", val_state$heldout$n_test, ")")
      } else {
        paste0("All ", n_samples, " samples are used for training; no external validation cohort is scored")
      }

      cv_detail <- if (has_cv) {
        acc_mean <- round(mean(val_state$cv$Accuracy, na.rm = TRUE), 3)
        acc_sd   <- round(sd(val_state$cv$Accuracy, na.rm = TRUE), 3)
        auc_mean <- round(mean(val_state$cv$AUC, na.rm = TRUE), 3)
        paste0(val_state$cv_repeats, " \u00d7 ", val_state$cv_folds,
               "-fold stratified CV: Accuracy = ", acc_mean, " \u00b1 ", acc_sd,
               ", mean AUC = ", auc_mean)
      } else {
        "OOB acts as a built-in validation set, but k-fold or repeated CV is not performed here"
      }

      boot_detail <- if (has_boot) {
        topN_freq <- head(val_state$stability$SelectionFreq, val_state$top_n)
        pct_stable <- round(mean(topN_freq >= 0.8) * 100, 1)
        paste0(val_state$n_boot, " bootstrap resamples: ", pct_stable,
               "% of the top-", val_state$top_n,
               " taxa are re-selected in \u2265 80% of bootstraps")
      } else {
        "Run multiple seeds to verify that the top-N ranking is stable"
      }

      chk <- function(ok, label, detail = "") {
        mark <- if (isTRUE(ok)) "<span style='color:#27AE60;font-weight:bold;'>Provided</span>"
                else            "<span style='color:#E67E22;font-weight:bold;'>Not shown here</span>"
        det  <- if (nzchar(detail)) paste0(" &mdash; ", detail) else ""
        paste0("<li><b>", label, ":</b> ", mark, det, "</li>")
      }
      validation_items <- paste0(
        chk(TRUE,  "Classifier and hyperparameters",
            paste0("Random Forest, ntree = ", n_trees,
                   ", mtry = ", mtry_val,
                   ", features = ", n_features)),
        chk(TRUE,  "Sample size and class balance",
            paste0("n = ", n_samples, " samples across ", n_classes,
                   " classes (", class_bal, ")")),
        chk(TRUE,  "Accuracy + Kappa + confusion matrix",
            "Reported above; raw counts available in the Performance Summary tab"),
        chk(!is.null(auc_val), "AUC / ROC",
            if (!is.null(auc_val)) "Binary ROC curve and AUC are computed"
            else "Requires exactly two classes"),
        chk(TRUE,  "OOB error estimate",
            paste0("Overall OOB error = ", ifelse(is.na(oob_err), "NA", oob_err))),
        chk(has_heldout, "Independent held-out test set", heldout_detail),
        chk(has_cv,      "Repeated / nested cross-validation", cv_detail),
        chk(has_boot,    "Feature-importance stability (bootstrap / permutation)", boot_detail),
        chk(TRUE,  "Taxonomic provenance of top features",
            "Phylum / Genus resolved from the supplied taxonomy table and listed below"),
        chk(TRUE,  "Group-direction of each top feature",
            "Per-ASV mean relative abundance is computed to tag each taxon as enriched in the reference or comparison group"),
        chk(FALSE, "Reproducibility seed in exported artefacts",
            "If required by the journal, add set.seed(...) to the model call and record it in the methods")
      )
      validation_html <- paste0(
        "<ul style='padding-left:20px; margin:4px 0 0 0;'>",
        validation_items,
        "</ul>")

      HTML(paste0(
        "<div style='border:1px solid #e0e0e0; padding:15px; border-radius:8px; background-color:#f9f9f9; font-family:Arial, sans-serif; font-size:13.5px; line-height:1.55;'>",

        "<h4 style='margin-top:0; color:#1e88e5;'>Classification Model Summary</h4>",
        "<p>The <b>Random Forest</b> classifier was trained to discriminate <b>",
          input$group_1, "</b> from <b>", input$group_2,
          "</b> using ", n_features, " filtered taxa from ",
          n_samples, " samples (", class_bal, "). ",
          "Hyperparameters: <code>ntree = ", n_trees,
          "</code>, <code>mtry = ", mtry_val, "</code>.</p>",

        "<p style='font-weight:bold; margin-bottom:5px;'>Internal Performance Metrics:</p>",
        "<ul style='list-style-type:disc; padding-left:20px; margin-top:0; margin-bottom:10px;'>",
          "<li>Classification Accuracy: <b>", accuracy, "</b></li>",
          "<li>Cohen's Kappa: <b>", kappa, "</b></li>",
          if (!is.null(auc_val)) paste0("<li>Area Under the ROC Curve (AUC): <b>", auc_val, "</b></li>") else "",
          if (!is.na(oob_err)) paste0("<li>Out-of-bag (OOB) error: <b>", oob_err, "</b></li>") else "",
        "</ul>",

        "<h4 style='color:#1e88e5;'>Performance Interpretation</h4>",
        "<p>", perf_msg, "</p>",
        "<p>", kappa_msg, auc_msg, "</p>",
        if (n_samples > 0 && n_samples <= 30) paste0(
          "<p style='background:#fff3cd; border-left:4px solid #f0ad4e; padding:8px 12px; border-radius:4px;'>",
          "<b>Small-sample caveat:</b> with only ", n_samples, " samples, an apparently perfect ",
          "classifier can be driven by a handful of highly variable taxa. Treat the taxa list as ",
          "<i>hypothesis-generating</i> and validate on an independent cohort or by qPCR.",
          "</p>") else "",

        "<h4 style='color:#1e88e5;'>Feature Importance Assessment</h4>",
        "<p>Feature importance is quantified by <b>Mean Decrease Gini</b>, which is the average ",
          "reduction in node impurity contributed by that feature across all ", n_trees, " trees. ",
          "Taxa with higher Gini scores carry more classification signal and are candidate biomarkers.</p>",

        "<p style='font-weight:bold; margin-bottom:5px;'>Top ", input$top_n,
          " Discriminatory Taxa (Ranked by Mean Decrease Gini):</p>",
        top_taxa_html,

        "<h4 style='color:#1e88e5;'>Expert-grade Validation Checklist &mdash; methodological coverage</h4>",
        "<p style='margin:2px 0 4px 0; color:#555;'>Answers the standard expert / peer-review question: ",
          "<i>\u201cis enough detail provided to reproduce and trust this classifier?\u201d</i></p>",
        validation_html,

        "</div>"
      ))
    })
    
    # ------------------------------------------------------------------
    # Expert-grade validation renderers (held-out, CV, stability)
    # ------------------------------------------------------------------
    placeholder_validation <- function(text) {
      HTML(paste0(
        "<div style='background:#fff3cd; border-left:5px solid #f0ad4e; ",
        "padding:10px 14px; border-radius:4px; font-size:13px;'>",
        text, "</div>"))
    }

    output$heldout_summary <- renderUI({
      if (is.null(input$run_validation) || input$run_validation == 0) {
        return(placeholder_validation(
          "Train a model, then click 'Run Expert-grade Validation'. The held-out test metrics will appear here."))
      }
      val <- rf_validation()
      validate(need(!is.null(val), "Validation did not return results."))
      h <- val$heldout
      if (isTRUE(!h$feasible)) {
        return(placeholder_validation(paste0(
          "Held-out split is not feasible at the current test fraction (n_test = ",
          h$n_test, "). Decrease the test fraction or add more samples.")))
      }
      acc <- if (is.null(h$accuracy) || is.na(h$accuracy)) "NA" else round(h$accuracy, 3)
      kap <- if (is.null(h$kappa)    || is.na(h$kappa))    "NA" else round(h$kappa,    3)
      auc <- if (is.null(h$auc)      || is.na(h$auc))      "NA" else round(h$auc,      3)
      cm_html <- ""
      if (!is.null(h$confusion)) {
        cm <- h$confusion
        rows <- paste0(
          "<tr><th></th>",
          paste0("<th style='padding:4px 10px;'>", colnames(cm), "</th>", collapse = ""),
          "</tr>",
          paste0(sapply(rownames(cm), function(r) {
            paste0("<tr><th style='padding:4px 10px;'>", r, "</th>",
                   paste0("<td style='padding:4px 10px; text-align:center;'>",
                          cm[r, ], "</td>", collapse = ""),
                   "</tr>")
          }), collapse = ""))
        cm_html <- paste0(
          "<p style='margin:6px 0 2px 0; font-size:12px; color:#555;'><b>Held-out confusion matrix</b> (rows = predicted, cols = actual):</p>",
          "<table style='border-collapse:collapse; font-size:13px; margin-left:10px;'>",
          rows, "</table>")
      }
      HTML(paste0(
        "<div style='border:1px solid #e0e0e0; padding:12px 14px; border-radius:6px; background:#f9f9f9; font-size:13.5px;'>",
        "<p style='margin:0 0 4px 0;'><b>Independent held-out test set</b> (stratified ",
        round((1 - val$test_frac) * 100), "/", round(val$test_frac * 100), " split): ",
        "training n = ", h$n_train, ", test n = ", h$n_test, ".</p>",
        "<ul style='margin:4px 0 6px 20px; padding:0;'>",
        "<li>Accuracy on held-out set: <b>", acc, "</b></li>",
        "<li>Cohen's Kappa on held-out set: <b>", kap, "</b></li>",
        "<li>AUC on held-out set: <b>", auc, "</b></li>",
        "</ul>", cm_html,
        "</div>"))
    })

    output$cv_summary <- renderUI({
      if (is.null(input$run_validation) || input$run_validation == 0) {
        return(placeholder_validation(
          "Repeated cross-validation metrics (Accuracy, Kappa, AUC) will appear here."))
      }
      val <- rf_validation()
      validate(need(!is.null(val), "Validation did not return results."))
      cv <- val$cv
      if (nrow(cv) == 0) {
        return(placeholder_validation(
          "Cross-validation produced no folds \u2014 sample size may be too small for k folds."))
      }
      fmt <- function(x) {
        if (all(is.na(x))) return("NA")
        m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
        paste0(round(m, 3), " \u00b1 ", round(s, 3))
      }
      HTML(paste0(
        "<div style='border:1px solid #e0e0e0; padding:12px 14px; border-radius:6px; background:#f9f9f9; font-size:13.5px;'>",
        "<p style='margin:0 0 4px 0;'><b>", val$cv_repeats, " \u00d7 ", val$cv_folds,
        "-fold stratified cross-validation</b> (", nrow(cv), " folds total):</p>",
        "<ul style='margin:4px 0 6px 20px; padding:0;'>",
        "<li>Accuracy (mean \u00b1 sd): <b>", fmt(cv$Accuracy), "</b></li>",
        "<li>Kappa (mean \u00b1 sd): <b>",    fmt(cv$Kappa),    "</b></li>",
        "<li>AUC (mean \u00b1 sd): <b>",      fmt(cv$AUC),      "</b></li>",
        "</ul>",
        "<p style='margin:2px 0 0 0; color:#555; font-size:12px;'>Lower variance across folds ",
        "= more stable generalisation. A held-out accuracy close to the CV mean is a good sign.</p>",
        "</div>"))
    })

    output$stability_table <- DT::renderDataTable({
      if (is.null(input$run_validation) || input$run_validation == 0) return(NULL)
      val <- rf_validation()
      validate(need(!is.null(val), "Validation did not return results."))
      stab <- val$stability
      if (nrow(stab) == 0) return(NULL)
      show <- head(stab, 50)
      genus  <- if ("Genus"  %in% colnames(show)) .clean_taxon_rf(show$Genus)  else rep("", nrow(show))
      family <- if ("Family" %in% colnames(show)) .clean_taxon_rf(show$Family) else rep("", nrow(show))
      phylum <- if ("Phylum" %in% colnames(show)) .clean_taxon_rf(show$Phylum) else rep("", nrow(show))
      show$Taxonomy <- ifelse(nzchar(genus), genus,
                       ifelse(nzchar(family), family,
                       ifelse(nzchar(phylum), phylum, "(unassigned)")))
      show$SelectionFreq <- round(show$SelectionFreq, 3)
      show$MeanRank      <- round(show$MeanRank, 2)
      show_cols <- c("ASV", "Taxonomy", "SelectionFreq", "SelectionCount", "MeanRank")
      show <- show[, show_cols, drop = FALSE]
      colnames(show) <- c("ASV", "Taxonomy", "Selection frequency", "Selection count", "Mean rank")
      DT::datatable(show, options = list(pageLength = 15, scrollX = TRUE),
                    rownames = FALSE, caption = paste0(
                      "Top 50 ASVs ranked by how often they appear in top-", val$top_n,
                      " across ", val$n_boot, " bootstrap resamples."))
    })

    output$cv_plot <- renderPlot({
      if (is.null(input$run_validation) || input$run_validation == 0) {
        return(
          ggplot() + annotate("text", x = 0.5, y = 0.5,
            label = "CV metric boxplot appears after 'Run Expert-grade Validation'.",
            size = 4.5, color = "#7F8C8D") +
          theme_void() + xlim(0, 1) + ylim(0, 1))
      }
      val <- rf_validation()
      validate(need(!is.null(val), "Validation did not return results."),
               need(nrow(val$cv) > 0, "No CV folds produced."))
      cv <- val$cv
      long <- tidyr::pivot_longer(cv, cols = c("Accuracy", "Kappa", "AUC"),
                                  names_to = "Metric", values_to = "Value")
      long <- long[!is.na(long$Value), , drop = FALSE]
      long$Metric <- factor(long$Metric, levels = c("Accuracy", "Kappa", "AUC"))
      ggplot(long, aes(x = Metric, y = Value, fill = Metric)) +
        geom_boxplot(alpha = 0.55, outlier.shape = NA, width = 0.55) +
        geom_jitter(width = 0.12, size = 2, alpha = 0.75, color = "#34495E") +
        scale_fill_manual(values = c(Accuracy = "#1f77b4",
                                     Kappa    = "#2ca02c",
                                     AUC      = "#d62728"), guide = "none") +
        labs(title = paste0(val$cv_repeats, " \u00d7 ", val$cv_folds,
                            "-fold cross-validation"),
             subtitle = paste0("Each point is one fold (n = ", nrow(cv),
                               " folds total). Higher and tighter = better."),
             x = NULL, y = "Metric value") +
        coord_cartesian(ylim = c(0, 1.02)) +
        theme_bw(base_size = 14) +
        theme(plot.title = element_text(face = "bold"),
              plot.subtitle = element_text(color = "#555555"))
    }, res = 110)

    output$stability_plot <- renderPlot({
      if (is.null(input$run_validation) || input$run_validation == 0) {
        return(
          ggplot() + annotate("text", x = 0.5, y = 0.5,
            label = "Feature-stability bar chart appears after 'Run Expert-grade Validation'.",
            size = 4.5, color = "#7F8C8D") +
          theme_void() + xlim(0, 1) + ylim(0, 1))
      }
      val <- rf_validation()
      validate(need(!is.null(val), "Validation did not return results."),
               need(nrow(val$stability) > 0, "No bootstrap stability computed."))
      stab <- head(val$stability, max(val$top_n, 15))
      genus  <- if ("Genus"  %in% colnames(stab)) .clean_taxon_rf(stab$Genus)  else rep("", nrow(stab))
      family <- if ("Family" %in% colnames(stab)) .clean_taxon_rf(stab$Family) else rep("", nrow(stab))
      stab$.display <- ifelse(
        nzchar(genus),
        paste0(genus,  " (", stab$ASV, ")"),
        ifelse(nzchar(family),
               paste0(family, " (", stab$ASV, ")"),
               stab$ASV))
      stab$.display <- make.unique(stab$.display, sep = " #")
      ggplot(stab, aes(x = reorder(.display, SelectionFreq),
                       y = SelectionFreq, fill = SelectionFreq)) +
        geom_bar(stat = "identity") +
        coord_flip() +
        scale_fill_gradient(low = "#AED6F1", high = "#1B4F72",
                            name = "Selection\nfrequency",
                            limits = c(0, 1)) +
        scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
        labs(title = paste0("Bootstrap feature-importance stability  (",
                            val$n_boot, " resamples)"),
             subtitle = paste0("How often each taxon appears in the top-",
                               val$top_n,
                               " by Mean Decrease Gini after resampling."),
             x = "Taxon (ASV id)",
             y = "Selection frequency across bootstraps") +
        theme_bw(base_size = 13) +
        theme(plot.title = element_text(face = "bold"),
              plot.subtitle = element_text(color = "#555555"),
              legend.position = "right")
    }, res = 110)

    output$download_validation_csv <- downloadHandler(
      filename = function() ezmap_filename("RandomForest_ExpertValidation", "csv"),
      content = function(file) {
        val <- rf_validation()
        req(val)
        tmp_cv <- val$cv
        tmp_cv$Section <- "cross_validation_fold"
        h <- val$heldout
        tmp_heldout <- data.frame(
          Section = "heldout",
          Repeat = NA_integer_, Fold = NA_integer_,
          Accuracy = if (is.null(h$accuracy)) NA_real_ else h$accuracy,
          Kappa    = if (is.null(h$kappa))    NA_real_ else h$kappa,
          AUC      = if (is.null(h$auc))      NA_real_ else h$auc)
        tmp_stab <- val$stability
        tmp_stab$Section <- "feature_stability"
        # write a combined CSV: CV + heldout + stability (columns aligned by common keys)
        tmp <- list(
          cv       = tmp_cv,
          heldout  = tmp_heldout,
          stability = tmp_stab)
        conn <- file(file, open = "w")
        writeLines("## Held-out test set", conn)
        write.csv(tmp$heldout, conn, row.names = FALSE)
        writeLines("", conn)
        writeLines("## Cross-validation folds", conn)
        write.csv(tmp$cv, conn, row.names = FALSE)
        writeLines("", conn)
        writeLines("## Bootstrap feature stability", conn)
        write.csv(tmp$stability, conn, row.names = FALSE)
        close(conn)
      }
    )

    # --- Downloads ---
    output$download_rf_plot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "RandomForest_Importance"),
      content = function(file) {
        res <- rf_results()
        req(res)
        # NULL fallbacks for expert-only color and display parameters
        col_ref  <- if (!is.null(input$imp_color_ref)  && nzchar(input$imp_color_ref))  input$imp_color_ref  else "#1f77b4"
        col_comp <- if (!is.null(input$imp_color_comp) && nzchar(input$imp_color_comp)) input$imp_color_comp else "#d62728"
        top_n_download <- if (is.null(input$top_n)) 20 else input$top_n
        p <- build_rf_importance_plot(res, input$group_1, input$group_2,
                                      col_ref, col_comp, top_n_download, input = input)
        d <- download_dims(input, def_width = 9, def_height = 7)
        ggsave(file, plot = p,
               width = d$width, height = d$height, units = d$units, dpi = d$dpi)
      }
    )

    output$download_ra_plot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "RelativeAbundance_TopASVs"),
      content = function(file) {

        # Recreate the plot logic including ordering
        res <- rf_results()
        # NULL fallbacks for expert-only parameters
        ra_palette <- if (is.null(input$ra_palette)) "Set1" else input$ra_palette
        top_n_plot <- if (is.null(input$top_n)) 20 else input$top_n
        req(res, input$group_variable, input$group_1, input$group_2)

        pseq <- physeq_normalized()
        metadata <- as(sample_data(pseq), "data.frame")

        keep_samples <- rownames(metadata)[metadata[[input$group_variable]] %in% c(input$group_1, input$group_2)]
        sub_pseq <- prune_samples(keep_samples, pseq)
        sub_pseq <- prune_taxa(taxa_sums(sub_pseq) > 0, sub_pseq)

        # Apply the same taxonomy aggregation as training
        tax_rank <- if (!is.null(res$tax_rank)) res$tax_rank else "ASV"
        if (tax_rank != "ASV" && tax_rank %in% colnames(tax_table(sub_pseq))) {
            sub_pseq <- tryCatch({
                glom <- tax_glom(sub_pseq, taxrank = tax_rank, NArm = FALSE)
                tax_labels <- as.character(tax_table(glom)[, tax_rank])
                tax_labels[is.na(tax_labels) | tax_labels == ""] <- paste0("Unclassified_", taxa_names(glom)[is.na(tax_labels) | tax_labels == ""])
                tax_labels <- make.unique(tax_labels, sep = "_")
                taxa_names(glom) <- tax_labels
                glom
            }, error = function(e) sub_pseq)
        }
        feature_label <- if (tax_rank == "ASV") "ASV" else tax_rank

        top_asvs <- intersect(res$top_features$ASV, taxa_names(sub_pseq))
        if(length(top_asvs) == 0) return(NULL)

        sub_pseq_prop <- transform_sample_counts(sub_pseq, function(x) x / sum(x))
        abund_mat <- as.data.frame(t(otu_table(sub_pseq_prop)[top_asvs, ]),
                                   check.names = FALSE)
        abund_mat$SampleID <- rownames(abund_mat)
        abund_mat$Group <- sample_data(sub_pseq_prop)[[input$group_variable]]

        abund_long <- abund_mat %>%
          pivot_longer(cols = all_of(top_asvs), names_to = "ASV", values_to = "Abundance") %>%
          group_by(Group, ASV) %>%
          summarise(MeanAbundance = mean(Abundance), .groups = "drop")

        # Set the order for plotting based on Gini Importance
        sorted_top_asvs <- res$top_features$ASV[res$top_features$ASV %in% abund_long$ASV]
        abund_long$ASV <- factor(abund_long$ASV, levels = rev(sorted_top_asvs))

        n_groups <- length(unique(abund_long$Group))
        colors <- RColorBrewer::brewer.pal(min(8, n_groups), ra_palette)
        names(colors) <- unique(abund_long$Group)

        # Create ggplot object
        p <- ggplot(abund_long, aes(x = ASV, y = MeanAbundance, fill = Group)) +
          geom_bar(stat = "identity", position = position_dodge(width = 0.8)) +
          coord_flip() +
          scale_fill_manual(values = colors) +
          scale_y_continuous(labels = scales::percent) +
          theme_bw(base_size = 14) +
          labs(x = feature_label, y = "Mean Relative Abundance",
               title = paste("Mean Relative Abundance of Top", top_n_plot, "Features (", feature_label, ")")) +
          guides(fill = guide_legend(reverse = TRUE)) +
          theme(legend.title = element_blank())

        # Save as PNG
        d <- download_dims(input, def_width = 10, def_height = 7)
        ggsave(file, plot = p,
               width = d$width, height = d$height, units = d$units, dpi = d$dpi)
      }
    )

    output$download_rf_roc_plot <- downloadHandler(
      filename = function() ezmap_download_filename(input, "RandomForest_ROC"),
      content = function(file) { 
        res <- rf_results()
        req(res, res$is_binary, res$roc_data)
        
        # Re-create the plot explicitly for reliable download
        p <- ggplot(res$roc_data, aes(x = FPR, y = TPR)) +
          geom_line(color = "darkred", size = 1.2) +
          geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray") +
          theme_minimal(base_size = 15) +
          labs(title = paste0("ROC Curve (AUC = ", round(res$auc, 3), ")"),
               x = "False Positive Rate", y = "True Positive Rate")
               
        d <- download_dims(input, def_width = 7, def_height = 7)
        ggsave(file, plot = p,
               width = d$width, height = d$height, units = d$units, dpi = d$dpi)
      }
    )

    output$download_rf_table <- downloadHandler(
      filename = function() ezmap_filename("RandomForest_FeatureImportance", "csv"),
      content = function(file) { write.csv(rf_results()$top_features, file, row.names = FALSE) }
    )

    # ------------------------------------------------------------------
    # (Added 2026-04-16) Expose reactives so other modules
    # (e.g. the combined DESeq2 + RF panel) can consume them.
    # ------------------------------------------------------------------
    # top_n_used reactive lets combined panels (DESeq2+RF, ANCOM-BC+RF)
    # inherit the same Top-N feature cutoff the user picked here.
    # Otherwise their own default of 30 silently overrides the user's
    # choice and produces inconsistent overlap counts.
    return(list(
      rf_results        = rf_results,
      physeq_normalized = physeq_normalized,
      group_variable    = reactive(input$group_variable),
      group_1           = reactive(input$group_1),
      group_2           = reactive(input$group_2),
      top_n_used        = reactive({
          if (is.null(input$top_n) || !is.finite(input$top_n)) 20
          else as.integer(input$top_n)
      })
    ))
  })
}
