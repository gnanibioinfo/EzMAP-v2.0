################################################################################
# panels/panel-server-filter.R — Filtering Server Logic
#
# Dynamically applies Bacteria (16S) or Fungi (ITS) filtering criteria
# based on the dataset_type reactive passed from the main server.
#
# Bacteria (16S) criteria:
#   - Remove Order  = "Chloroplast"
#   - Remove Family = "Mitochondria"
#   - Remove Kingdom = "Eukaryota"
#   - Remove Kingdom = "Archaea" (optional)
#   - Remove Phylum = "NA"
#   - Strip QIIME2 "D_x__" taxonomy prefixes
#
# Fungi (ITS) criteria:
#   - Remove Kingdom = "Chromista"    (k__Chromista)
#   - Remove Kingdom = "Rhizaria"     (k__Rhizaria)
#   - Remove Phylum = "unidentified"  (p__unidentified)
#   - Remove Phylum = "NA"
#   - Strip lowercase taxonomy prefixes [k__/p__/c__/o__/f__/g__/s__]
#
# Custom exclusion:
#   - User selects taxonomy rank → sees unique values from data
#   - Multi-select taxa to exclude → stored in a reactiveVal list
#   - Applied as subset_taxa() after built-in filters
#
# Shared: abundance thresholds + optional median-depth normalization.
################################################################################

filterServer <- function(id, physeq_data, global_state_rv, dataset_type = reactive("bacteria")) {

    moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # ==================================================================
        # SAMPLE SUBSETTING — Step 0 (applied before any other filter)
        # ==================================================================

        # Render: metadata column picker for subsetting
        output$subset_column_ui <- renderUI({
            pseq <- physeq_data()
            req(pseq)
            metadata <- as(sample_data(pseq), "data.frame")
            # Only show columns with categorical (factor/character) values
            # and more than 1 unique value (otherwise subsetting is pointless)
            cat_cols <- names(metadata)[sapply(metadata, function(x)
                (is.factor(x) || is.character(x)) && length(unique(x)) > 1 && length(unique(x)) <= 50
            )]

            if (length(cat_cols) == 0) {
                return(helpText(style = "font-size:11px; color:#e74c3c;",
                                "No suitable categorical metadata columns found."))
            }

            selectInput(ns("subset_column"), "Group by metadata column:",
                        choices = c("(No subsetting)" = "", cat_cols),
                        selected = "")
        })

        # Render: group checkboxes based on selected column
        output$subset_groups_ui <- renderUI({
            pseq <- physeq_data()
            req(pseq)
            col <- input$subset_column
            if (is.null(col) || !nzchar(col)) return(NULL)

            metadata <- as(sample_data(pseq), "data.frame")
            if (!col %in% colnames(metadata)) return(NULL)

            groups <- sort(unique(as.character(metadata[[col]])))
            groups <- groups[!is.na(groups) & nzchar(groups)]

            if (length(groups) == 0) return(NULL)

            # Build choices with sample counts
            group_labels <- sapply(groups, function(g) {
                n <- sum(metadata[[col]] == g, na.rm = TRUE)
                paste0(g, " (n=", n, ")")
            })
            names(groups) <- group_labels

            checkboxGroupInput(ns("subset_groups"), "Select groups to keep:",
                               choices  = groups,
                               selected = groups)  # all selected by default
        })

        # Render: preview of subsetting impact
        output$subset_preview_ui <- renderUI({
            pseq <- physeq_data()
            req(pseq)
            col <- input$subset_column
            if (is.null(col) || !nzchar(col)) return(NULL)

            selected <- input$subset_groups
            metadata <- as(sample_data(pseq), "data.frame")
            if (!col %in% colnames(metadata)) return(NULL)

            total_samples <- nsamples(pseq)
            all_groups <- unique(as.character(metadata[[col]]))
            all_groups <- all_groups[!is.na(all_groups) & nzchar(all_groups)]

            if (is.null(selected) || length(selected) == 0) {
                return(div(style = "background:#FDEDEC; border:1px solid #F5B7B1; border-left:4px solid #E74C3C; border-radius:4px; padding:6px 10px; margin-top:4px; font-size:12px; color:#C0392B;",
                    icon("exclamation-triangle"),
                    strong(" No groups selected."),
                    " Select at least one group to proceed."
                ))
            }

            n_keep <- sum(metadata[[col]] %in% selected, na.rm = TRUE)
            n_excluded <- total_samples - n_keep
            excluded_groups <- setdiff(all_groups, selected)

            if (n_excluded == 0) {
                return(div(style = "background:#F0FDF4; border:1px solid #BBF7D0; border-left:4px solid #10B981; border-radius:4px; padding:6px 10px; margin-top:4px; font-size:12px; color:#059669;",
                    icon("check-circle"),
                    " All ", total_samples, " samples selected (no subsetting)."
                ))
            }

            div(style = "background:#EFF6FF; border:1px solid #BFDBFE; border-left:4px solid #3B82F6; border-radius:4px; padding:6px 10px; margin-top:4px; font-size:12px; color:#1E40AF;",
                icon("filter"),
                strong(paste0(" Keeping ", n_keep, " of ", total_samples, " samples.")),
                tags$br(),
                tags$small(style = "color:#64748B;",
                    "Excluding: ", paste(excluded_groups, collapse = ", "))
            )
        })

        # ==================================================================
        # Custom exclusion list — stored as named list: list(Rank = c(taxa))
        # ==================================================================
        custom_exclusions <- reactiveVal(list())

        # ------------------------------------------------------------------
        # Dataset type badge — shows which mode is active
        # ------------------------------------------------------------------
        output$dataset_type_badge <- renderUI({
            ds <- dataset_type()
            if (!is.null(ds) && ds == "fungi") {
                div(class = "alert alert-success", role = "alert",
                    style = "padding:8px 12px; margin-bottom:4px; font-size:12.5px;",
                    icon("leaf"),
                    strong(" Fungi (ITS) mode"),
                    " \u2014 Filtering for fungal-specific contaminants."
                )
            } else {
                div(class = "alert alert-info", role = "alert",
                    style = "padding:8px 12px; margin-bottom:4px; font-size:12.5px;",
                    icon("bacterium"),
                    strong(" Bacteria (16S) mode"),
                    " \u2014 Filtering for bacterial-specific contaminants."
                )
            }
        })

        # ------------------------------------------------------------------
        # Easy mode banner — context-aware per dataset type
        # ------------------------------------------------------------------
        output$easy_mode_banner <- renderUI({
            ds <- dataset_type()
            is_fungi <- !is.null(ds) && ds == "fungi"

            if (is_fungi) {
                filter_desc <- paste0(
                    "Chromista, Rhizaria, unidentified phyla removed. ",
                    "Taxonomy prefixes stripped. Min 3 reads, 20% sample prevalence. ",
                    "Normalized to median sequencing depth.")
            } else {
                filter_desc <- paste0(
                    "Chloroplast, Mitochondria, Eukaryota removed. ",
                    "Taxonomy prefixes stripped. Min 3 reads, 20% sample prevalence. ",
                    "Normalized to median sequencing depth.")
            }

            div(style = "background:#D1FAE5; border:1px solid #A7F3D0; border-radius:8px; padding:10px 14px; margin-bottom:12px;",
                tags$span(style = "font-weight:600; color:#065F46; font-size:13px;",
                          icon("check-circle"), " Easy Mode \u2014 Sensible defaults applied"),
                tags$p(style = "font-size:11px; color:#047857; margin:4px 0 0;",
                       filter_desc,
                       " To customize, restart the app and select Expert mode.")
            )
        })

        # ------------------------------------------------------------------
        # Dynamic taxonomic filter checkboxes
        # ------------------------------------------------------------------
        output$taxonomic_filters_ui <- renderUI({
            ds <- dataset_type()

            if (!is.null(ds) && ds == "fungi") {
                # ---- FUNGI (ITS) filters ----
                tagList(
                    checkboxInput(ns("filterNA"),
                        "Filter Phylum = 'NA'", TRUE),
                    checkboxInput(ns("filterChromista"),
                        "Filter Kingdom = 'Chromista'", TRUE),
                    checkboxInput(ns("filterRhizaria"),
                        "Filter Kingdom = 'Rhizaria'", TRUE),
                    checkboxInput(ns("removeTaxPatterns"),
                        "Remove 'k__/p__/c__/o__/f__/g__/s__' prefixes", TRUE),
                    hr(),
                    h6(strong("Unidentified taxa handling")),
                    radioButtons(ns("unidentified_mode"),
                        label = NULL,
                        choices = c(
                            "Keep all (do not remove)"                          = "keep",
                            "Remove only fully unclassified (safe)"             = "strict",
                            "Remove ALL with Phylum = 'unidentified' (aggressive)" = "aggressive"
                        ),
                        selected = "strict"
                    ),
                    helpText(style = "font-size:11px; color:#64748B;",
                        icon("info-circle"),
                        tags$b("Safe:"), " only removes ASVs that are unidentified ",
                        "at every rank (Phylum through Species) \u2014 preserves fungi ",
                        "with valid Genus/Species but unknown Phylum.",
                        tags$br(),
                        tags$b("Aggressive:"), " removes ALL ASVs with Phylum = 'unidentified' ",
                        "regardless of lower-rank classification.",
                        tags$br(),
                        tags$b("Common in ITS:"), " many well-classified fungi (e.g. known ",
                        "at Genus) have 'unidentified' Phylum in UNITE \u2014 the safe ",
                        "option prevents losing these."),
                    # Live preview of impact
                    uiOutput(ns("unidentified_impact_preview"))
                )
            } else {
                # ---- BACTERIA (16S) filters ----
                tagList(
                    checkboxInput(ns("filterNA"),
                        "Filter Phylum = 'NA'", TRUE),
                    checkboxInput(ns("filterChloroplast"),
                        "Filter Order = 'Chloroplast'", TRUE),
                    checkboxInput(ns("filterMitochondria"),
                        "Filter Family = 'Mitochondria'", TRUE),
                    checkboxInput(ns("filterEukaryota"),
                        "Filter Kingdom = 'Eukaryota'", TRUE),
                    checkboxInput(ns("filterArchaea"),
                        "Filter Kingdom = 'Archaea'", FALSE),
                    checkboxInput(ns("removeTaxPatterns"),
                        "Remove taxonomy prefixes (D_x__ / k__/p__/…)", TRUE),
                    helpText(style = "font-size:11px; color:#64748B;",
                        icon("info-circle"),
                        " Bacteria-specific: removes chloroplasts, mitochondria, ",
                        "eukaryotes. Strips all QIIME2 taxonomy prefixes.")
                )
            }
        })

        # ==================================================================
        # LIVE PREVIEW: Impact of "unidentified" filter mode (fungi only)
        # Shows ASV count and read % BEFORE the user clicks Apply.
        # ==================================================================
        output$unidentified_impact_preview <- renderUI({
            pseq <- physeq_data()
            req(pseq)
            ds <- dataset_type()
            if (is.null(ds) || ds != "fungi") return(NULL)

            mode <- input$unidentified_mode
            if (is.null(mode) || mode == "keep") return(NULL)

            tax_df <- as.data.frame(as(tax_table(pseq), "matrix"),
                                    stringsAsFactors = FALSE)
            # Strip prefixes to match what the filter will see
            for (col in colnames(tax_df)) {
                tax_df[[col]] <- .strip_tax_prefixes(as.character(tax_df[[col]]))
            }

            total_asvs <- ntaxa(pseq)
            total_reads <- sum(sample_sums(pseq))

            otu_mat <- as(otu_table(pseq), "matrix")
            if (!taxa_are_rows(pseq)) otu_mat <- t(otu_mat)

            # Helper: is a value "unidentified" or empty/NA?
            .is_unid <- function(x) {
                is.na(x) | !nzchar(x) | tolower(x) %in% c(
                    "unidentified", "unclassified", "unknown",
                    "incertae_sedis", "incertae sedis")
            }

            phylum_vals <- tax_df[["Phylum"]]
            has_unid_phylum <- .is_unid(phylum_vals)

            if (mode == "aggressive") {
                # All ASVs with unidentified phylum
                affected_idx <- which(has_unid_phylum)
            } else {
                # Strict: only remove if ALL ranks below Kingdom are unidentified
                lower_ranks <- intersect(
                    c("Phylum","Class","Order","Family","Genus","Species"),
                    colnames(tax_df))
                all_unid <- rep(TRUE, nrow(tax_df))
                for (rk in lower_ranks) {
                    all_unid <- all_unid & .is_unid(tax_df[[rk]])
                }
                affected_idx <- which(all_unid)
            }

            n_affected <- length(affected_idx)
            if (n_affected == 0) {
                return(div(style = "font-size:11px; color:#27ae60; margin-top:4px;",
                    icon("check-circle"),
                    " No ASVs would be removed by this filter."
                ))
            }

            reads_affected <- sum(rowSums(otu_mat[affected_idx, , drop = FALSE]))
            pct_reads <- round(100 * reads_affected / total_reads, 1)

            # Colour the warning based on severity
            if (pct_reads > 50) {
                col <- "#c0392b"; bg <- "#fdedec"; border <- "#e74c3c"
                ico <- "exclamation-triangle"
            } else if (pct_reads > 20) {
                col <- "#e67e22"; bg <- "#fef5e7"; border <- "#f0ad4e"
                ico <- "exclamation-circle"
            } else {
                col <- "#2c3e50"; bg <- "#eaf2f8"; border <- "#3B82F6"
                ico <- "info-circle"
            }

            # Show some examples of what will be removed
            example_taxa <- character(0)
            if (n_affected > 0 && "Genus" %in% colnames(tax_df)) {
                genera <- tax_df[["Genus"]][affected_idx]
                genera <- genera[!.is_unid(genera)]
                genera <- unique(genera)
                if (length(genera) > 0) {
                    example_taxa <- head(genera, 5)
                }
            }

            example_html <- ""
            if (length(example_taxa) > 0) {
                example_html <- paste0(
                    "<div style='margin-top:4px; font-size:11px;'>",
                    "<b>Classified genera that would be lost:</b> ",
                    paste(example_taxa, collapse = ", "),
                    if (length(unique(tax_df[["Genus"]][affected_idx])) > 5)
                        ", ..." else "",
                    "</div>")
            }

            div(style = paste0(
                    "background:", bg, "; border:1px solid ", border,
                    "; border-left:4px solid ", border,
                    "; border-radius:4px; padding:8px 10px; margin-top:6px;",
                    " font-size:12px; color:", col, ";"),
                icon(ico),
                HTML(paste0(
                    " <b>Preview:</b> ",
                    n_affected, " of ", total_asvs, " ASVs (",
                    pct_reads, "% of total reads) would be removed."
                )),
                HTML(example_html)
            )
        })

        # ==================================================================
        # CUSTOM TAXA EXCLUSION — dynamic selector
        # ==================================================================

        # Helper: strip all known taxonomy prefixes from a character vector
        # so that values display consistently regardless of whether the user
        # has already applied prefix removal.
        .strip_tax_prefixes <- function(x) {
            x <- gsub("[Dd]_[0-9]__", "", x)          # QIIME2 D_x__
            x <- gsub("^[dkpcofgs]__", "", x)          # lowercase d__/k__/p__/…
            trimws(x)
        }

        # Reactive: unique taxa values at the selected rank (shown with
        # prefixes stripped so users see clean names that will actually match).
        unique_taxa_at_rank <- reactive({
            pseq <- physeq_data()
            req(pseq)
            rank <- input$custom_tax_rank
            req(rank)

            tax_df <- as.data.frame(as(tax_table(pseq), "matrix"),
                                    stringsAsFactors = FALSE)

            if (!rank %in% colnames(tax_df)) return(character(0))

            vals <- as.character(tax_df[[rank]])
            vals <- .strip_tax_prefixes(vals)
            vals <- vals[!is.na(vals) & nzchar(vals)]
            sort(unique(vals))
        })

        # Render the multi-select dropdown + Add button
        output$custom_taxa_selector_ui <- renderUI({
            taxa_choices <- unique_taxa_at_rank()
            rank <- input$custom_tax_rank

            if (length(taxa_choices) == 0) {
                return(helpText(style = "font-size:11px; color:#e74c3c;",
                                "No data loaded yet. Upload data first."))
            }

            tagList(
                selectizeInput(ns("custom_taxa_to_exclude"),
                    label = NULL,
                    choices  = taxa_choices,
                    selected = NULL,
                    multiple = TRUE,
                    options  = list(
                        placeholder = paste0("Search & select ", rank,
                                             " to exclude..."),
                        maxItems    = 50,
                        plugins     = list("remove_button")
                    )
                ),
                div(style = "display:flex; gap:6px; margin-top:-4px;",
                    actionButton(ns("add_exclusion"),
                        label = tagList(icon("plus"), "Add to exclusion list"),
                        class = "btn btn-outline-danger btn-sm",
                        style = "flex:1;"),
                    actionButton(ns("clear_exclusions"),
                        label = tagList(icon("trash"), "Clear all"),
                        class = "btn btn-outline-secondary btn-sm")
                )
            )
        })

        # Observer: Add selected taxa to the exclusion list
        observeEvent(input$add_exclusion, {
            selected <- input$custom_taxa_to_exclude
            rank     <- input$custom_tax_rank
            if (is.null(selected) || length(selected) == 0) {
                showNotification("Select at least one taxon to exclude.",
                                 type = "warning", duration = 3)
                return()
            }

            current <- custom_exclusions()
            # Merge with existing entries for this rank
            existing <- current[[rank]]
            current[[rank]] <- unique(c(existing, selected))
            custom_exclusions(current)

            # Clear the selector after adding
            updateSelectizeInput(session, "custom_taxa_to_exclude",
                                 selected = character(0))

            n_added <- length(selected)
            showNotification(
                paste0("Added ", n_added, " ", rank,
                       ifelse(n_added > 1, " taxa", " taxon"),
                       " to exclusion list."),
                type = "message", duration = 3)
        })

        # Observer: Clear all exclusions
        observeEvent(input$clear_exclusions, {
            custom_exclusions(list())
            showNotification("Exclusion list cleared.", type = "message",
                             duration = 2)
        })

        # Observer: Remove individual items (dynamic buttons)
        observeEvent(input$remove_exclusion_item, {
            # Value format: "Rank::TaxonName"
            val <- input$remove_exclusion_item
            if (is.null(val) || !grepl("::", val)) return()
            parts <- strsplit(val, "::", fixed = TRUE)[[1]]
            if (length(parts) != 2) return()

            rank_name <- parts[1]
            taxon_name <- parts[2]

            current <- custom_exclusions()
            if (rank_name %in% names(current)) {
                current[[rank_name]] <- setdiff(current[[rank_name]], taxon_name)
                if (length(current[[rank_name]]) == 0) {
                    current[[rank_name]] <- NULL
                }
            }
            custom_exclusions(current)
        })

        # Render the exclusion list as styled tags with remove buttons
        output$exclusion_list_display <- renderUI({
            excl <- custom_exclusions()

            if (length(excl) == 0) return(NULL)

            # Count total exclusions
            total_n <- sum(vapply(excl, length, integer(1)))

            # Build tag chips grouped by rank
            tag_groups <- lapply(names(excl), function(rank_name) {
                taxa_vec <- excl[[rank_name]]
                chips <- lapply(taxa_vec, function(tx) {
                    btn_id <- paste0(rank_name, "::", tx)
                    tags$span(
                        style = paste0(
                            "display:inline-flex; align-items:center; gap:4px;",
                            "background:#fdedec; border:1px solid #f5b7b1;",
                            "color:#922b21; border-radius:12px; padding:2px 8px 2px 10px;",
                            "font-size:11.5px; margin:2px 3px; line-height:1.4;"
                        ),
                        tags$span(tx),
                        tags$a(
                            href = "#",
                            style = "color:#c0392b; font-weight:bold; text-decoration:none; font-size:13px; line-height:1;",
                            onclick = sprintf(
                                "Shiny.setInputValue('%s', '%s', {priority: 'event'}); return false;",
                                ns("remove_exclusion_item"), btn_id),
                            "\u00d7"
                        )
                    )
                })

                tagList(
                    tags$div(
                        style = "font-size:11px; font-weight:600; color:#94A3B8; margin-top:4px; text-transform:uppercase; letter-spacing:0.5px;",
                        rank_name
                    ),
                    tags$div(style = "display:flex; flex-wrap:wrap;", chips)
                )
            })

            div(
                style = "background:#fef9f9; border:1px solid #f5b7b1; border-radius:6px; padding:8px 10px; margin-top:6px;",
                div(style = "display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;",
                    tags$span(
                        style = "font-size:12px; font-weight:600; color:#922b21;",
                        icon("ban"),
                        paste0(" Exclusion list (", total_n, " taxa)")
                    )
                ),
                tag_groups
            )
        })

        # ------------------------------------------------------------------
        # Apply filters on button click
        # ------------------------------------------------------------------
        filtered_results <- eventReactive(input$applyFilter, {
            Bacteria <- physeq_data()
            req(Bacteria)

            ds <- dataset_type()
            is_fungi <- !is.null(ds) && ds == "fungi"

            # Detect Easy vs Expert mode
            analysis_mode <- shiny::getDefaultReactiveDomain()$input$analysis_mode
            is_easy <- !is.null(analysis_mode) && analysis_mode == "easy"

            initial_samples <- nsamples(Bacteria)
            initial_asvs <- ntaxa(Bacteria)
            filter_log <- paste("Initial samples:", initial_samples, "\n")
            filter_log <- paste0(filter_log, "Initial ASVs: ", initial_asvs, "\n")
            filter_log <- paste0(filter_log, "Dataset type: ",
                                 ifelse(is_fungi, "Fungi (ITS)", "Bacteria (16S)"), "\n")

            # --- 0. Sample Subsetting (FIRST FILTER) ---
            subset_col <- input$subset_column
            if (!is.null(subset_col) && nzchar(subset_col)) {
                selected_groups <- input$subset_groups
                if (!is.null(selected_groups) && length(selected_groups) > 0) {
                    metadata <- as(sample_data(Bacteria), "data.frame")
                    if (subset_col %in% colnames(metadata)) {
                        keep_samples <- rownames(metadata)[
                            as.character(metadata[[subset_col]]) %in% selected_groups
                        ]
                        if (length(keep_samples) > 0 && length(keep_samples) < nsamples(Bacteria)) {
                            Bacteria <- prune_samples(keep_samples, Bacteria)
                            # Also remove taxa that are now entirely absent
                            Bacteria <- prune_taxa(taxa_sums(Bacteria) > 0, Bacteria)
                            excluded_groups <- setdiff(
                                unique(as.character(metadata[[subset_col]])),
                                selected_groups
                            )
                            filter_log <- paste0(filter_log,
                                "\n--- Sample Subsetting ---\n",
                                "Column: ", subset_col, "\n",
                                "Kept groups: ", paste(selected_groups, collapse = ", "), "\n",
                                "Excluded groups: ", paste(excluded_groups, collapse = ", "), "\n",
                                "Samples remaining: ", nsamples(Bacteria),
                                " (removed ", initial_samples - nsamples(Bacteria), ")\n",
                                "ASVs remaining: ", ntaxa(Bacteria),
                                " (removed ", initial_asvs - ntaxa(Bacteria), " zero-sum taxa)\n")
                        } else {
                            filter_log <- paste0(filter_log,
                                "\nSample subsetting: all groups selected (no change).\n")
                        }
                    }
                } else {
                    showNotification(
                        "No sample groups selected! Select at least one group.",
                        type = "error", duration = 5)
                    return(NULL)
                }
            }

            # --- Easy mode defaults: all filters ON when inputs are hidden ---
            # For expert mode, explicitly check checkbox values
            # Checkboxes return FALSE when unchecked, TRUE when checked (never NULL)
            do_remove_prefix    <- if (is_easy) TRUE else isTRUE(input$removeTaxPatterns)
            do_filter_na        <- if (is_easy) TRUE else isTRUE(input$filterNA)
            do_filter_chloro    <- if (is_easy) TRUE else isTRUE(input$filterChloroplast)
            do_filter_mito      <- if (is_easy) TRUE else isTRUE(input$filterMitochondria)
            do_filter_euk       <- if (is_easy) TRUE else isTRUE(input$filterEukaryota)
            do_filter_archaea   <- if (is_easy) TRUE else isTRUE(input$filterArchaea)
            do_filter_chromista <- if (is_easy) TRUE else isTRUE(input$filterChromista)
            do_filter_rhizaria  <- if (is_easy) TRUE else isTRUE(input$filterRhizaria)
            # For fungi unidentified mode: Easy = "strict", Expert = user choice
            do_unid_mode        <- if (is_easy) "strict" else input$unidentified_mode

            # --- 1. Remove taxonomy prefixes ---
            if (do_remove_prefix) {
                tax_mat <- as(tax_table(Bacteria), "matrix")

                # Strip ALL known taxonomy prefixes regardless of dataset type:
                #   D_0__ / D_1__ / ...  (old QIIME2 / SILVA)
                #   d__ / k__ / p__ / c__ / o__ / f__ / g__ / s__  (new QIIME2)
                # Note: Apply both patterns to all cells (handles mixed cases in taxonomy table)
                tax_mat[, ] <- gsub("[Dd]_[0-9]__", "", tax_mat[, ])
                tax_mat[, ] <- gsub("^[dkpcofgs]__", "", tax_mat[, ])
                # Also handle uppercase prefixes that might appear (K__, P__, etc.)
                tax_mat[, ] <- gsub("^[DKPCOFGS]__", "", tax_mat[, ])
                tax_mat[, ] <- trimws(tax_mat[, ])
                filter_log <- paste0(filter_log,
                    "\nTaxonomic prefixes (D_x__ and k__/p__/c__/o__/f__/g__/s__/K__/P__/etc.) removed.\n")

                tax_table(Bacteria) <- tax_table(tax_mat)
            }

            # --- 2. Built-in taxonomic filtering ---

            # Phylum = NA (shared)
            if (do_filter_na) {
                Bacteria <- subset_taxa(Bacteria, Phylum != "NA")
                filter_log <- paste0(filter_log,
                    "Removed Phylum 'NA': ", ntaxa(Bacteria), " ASVs remaining.\n")
            }

            if (is_fungi) {
                # ---- FUNGI-SPECIFIC FILTERS ----
                if (do_filter_chromista) {
                    Bacteria <- subset_taxa(Bacteria,
                        is.na(Kingdom) | (Kingdom != "Chromista" & Kingdom != "k__Chromista"))
                    filter_log <- paste0(filter_log,
                        "Removed Kingdom 'Chromista': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
                if (do_filter_rhizaria) {
                    Bacteria <- subset_taxa(Bacteria,
                        is.na(Kingdom) | (Kingdom != "Rhizaria" & Kingdom != "k__Rhizaria"))
                    filter_log <- paste0(filter_log,
                        "Removed Kingdom 'Rhizaria': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
                # Unidentified taxa handling (3 modes)
                unid_mode <- do_unid_mode
                if (!is.null(unid_mode) && unid_mode != "keep") {

                    .is_unid_val <- function(x) {
                        is.na(x) | !nzchar(x) | tolower(x) %in% c(
                            "unidentified", "unclassified", "unknown",
                            "p__unidentified", "incertae_sedis", "incertae sedis")
                    }

                    if (unid_mode == "aggressive") {
                        # Remove ALL ASVs with Phylum = unidentified
                        pre_n <- ntaxa(Bacteria)
                        tax_check <- as.data.frame(as(tax_table(Bacteria), "matrix"),
                                                   stringsAsFactors = FALSE)
                        keep <- !.is_unid_val(tax_check[["Phylum"]])
                        Bacteria <- prune_taxa(taxa_names(Bacteria)[keep], Bacteria)
                        filter_log <- paste0(filter_log,
                            "Removed ALL Phylum 'unidentified' (aggressive): ",
                            pre_n - ntaxa(Bacteria), " ASVs removed, ",
                            ntaxa(Bacteria), " remaining.\n")

                    } else if (unid_mode == "strict") {
                        # Remove only ASVs unidentified at EVERY rank below Kingdom
                        pre_n <- ntaxa(Bacteria)
                        tax_check <- as.data.frame(as(tax_table(Bacteria), "matrix"),
                                                   stringsAsFactors = FALSE)
                        lower_ranks <- intersect(
                            c("Phylum","Class","Order","Family","Genus","Species"),
                            colnames(tax_check))
                        all_unid <- rep(TRUE, nrow(tax_check))
                        for (rk in lower_ranks) {
                            all_unid <- all_unid & .is_unid_val(tax_check[[rk]])
                        }
                        keep <- !all_unid
                        Bacteria <- prune_taxa(taxa_names(Bacteria)[keep], Bacteria)
                        n_removed <- pre_n - ntaxa(Bacteria)
                        filter_log <- paste0(filter_log,
                            "Removed fully unclassified taxa (safe): ",
                            n_removed, " ASVs removed, ",
                            ntaxa(Bacteria), " remaining.\n")
                        if (n_removed == 0) {
                            filter_log <- paste0(filter_log,
                                "  (All ASVs with unidentified Phylum have valid ",
                                "lower-rank classification \u2014 none removed.)\n")
                        }
                    }
                }
            } else {
                # ---- BACTERIA-SPECIFIC FILTERS ----
                if (do_filter_chloro) {
                    Bacteria <- subset_taxa(Bacteria,
                        is.na(Order) | Order != "Chloroplast")
                    filter_log <- paste0(filter_log,
                        "Removed Order 'Chloroplast': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
                if (do_filter_mito) {
                    Bacteria <- subset_taxa(Bacteria,
                        is.na(Family) | Family != "Mitochondria")
                    filter_log <- paste0(filter_log,
                        "Removed Family 'Mitochondria': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
                if (do_filter_euk) {
                    Bacteria <- subset_taxa(Bacteria,
                        Kingdom != "Eukaryota")
                    filter_log <- paste0(filter_log,
                        "Removed Kingdom 'Eukaryota': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
                if (do_filter_archaea) {
                    Bacteria <- subset_taxa(Bacteria,
                        Kingdom != "Archaea")
                    filter_log <- paste0(filter_log,
                        "Removed Kingdom 'Archaea': ", ntaxa(Bacteria), " ASVs remaining.\n")
                }
            }

            # --- 3. Custom taxa exclusion ---
            # NOTE: By this point, taxonomy prefixes may have been stripped
            # (step 1). The exclusion targets may have been added BEFORE
            # stripping (e.g. "k__Chromista") or AFTER ("Chromista").
            # We normalize both sides to ensure a reliable match.
            excl <- custom_exclusions()
            if (length(excl) > 0) {
                filter_log <- paste0(filter_log, "\n--- Custom Exclusions ---\n")

                tax_df <- as.data.frame(as(tax_table(Bacteria), "matrix"),
                                        stringsAsFactors = FALSE)

                for (rank_name in names(excl)) {
                    taxa_to_remove <- excl[[rank_name]]
                    if (length(taxa_to_remove) == 0) next
                    if (!rank_name %in% colnames(tax_df)) next

                    pre_count <- ntaxa(Bacteria)

                    # Normalize both sides: strip prefixes for comparison
                    targets_clean <- .strip_tax_prefixes(taxa_to_remove)
                    rank_vals     <- as.character(tax_df[[rank_name]])
                    rank_clean    <- .strip_tax_prefixes(rank_vals)

                    keep_idx <- is.na(rank_vals) | !(rank_clean %in% targets_clean)
                    Bacteria <- prune_taxa(taxa_names(Bacteria)[keep_idx], Bacteria)

                    # Refresh tax_df after pruning
                    tax_df <- as.data.frame(as(tax_table(Bacteria), "matrix"),
                                            stringsAsFactors = FALSE)

                    n_removed <- pre_count - ntaxa(Bacteria)
                    # Display clean names in the log
                    display_names <- unique(targets_clean)
                    filter_log <- paste0(filter_log,
                        "Removed ", rank_name, " [",
                        paste(display_names, collapse = ", "), "]: ",
                        n_removed, " ASVs removed, ",
                        ntaxa(Bacteria), " remaining.\n")
                }
            }

            # --- 4. Abundance filtering ---
            pre_abundance_asvs <- ntaxa(Bacteria)

            min_counts  <- if (is.null(input$minCounts)) 3 else input$minCounts
            min_pct     <- if (is.null(input$minSamplePercent)) 20 else input$minSamplePercent
            min_samples <- min_pct / 100 * nsamples(Bacteria)

            Bacteria <- filter_taxa(Bacteria,
                function(x) sum(x > min_counts) > min_samples, TRUE)

            asvs_removed_abundance <- pre_abundance_asvs - ntaxa(Bacteria)
            filter_log <- paste0(filter_log,
                "\nAbundance Filter (", min_counts, " reads in >",
                min_pct, "% samples):\n")
            filter_log <- paste0(filter_log,
                "Removed ", asvs_removed_abundance, " ASVs.\n")
            filter_log <- paste0(filter_log,
                "Final ASVs remaining: ", ntaxa(Bacteria), ".\n")

            pre_normalization_sums <- sample_sums(Bacteria)

            # Save the filtered-but-not-normalized phyloseq for downstream use
            physeq_pre_norm <- Bacteria

            # --- 5. Normalization step ---
            do_normalize <- if (is_easy) TRUE else isTRUE(input$normalizeAbundance)
            normalized_flag <- FALSE
            if (do_normalize) {
                total <- median(sample_sums(Bacteria))
                standf <- function(x, t = total) round(t * (x / sum(x)))
                Bacteria <- transform_sample_counts(Bacteria, standf)
                normalized_flag <- TRUE
                filter_log <- paste0(filter_log,
                    "\nAbundance Normalized to Median Depth (", total, " reads).\n")
            }

            return(list(
                physeq                 = Bacteria,
                physeq_filtered_only   = physeq_pre_norm,
                log                    = filter_log,
                is_normalized          = normalized_flag,
                pre_normalization_sums = pre_normalization_sums
            ))
        })

        # ------------------------------------------------------------------
        # Summary display
        # ------------------------------------------------------------------
        output$summaryText <- renderPrint({
            req(filtered_results())
            results <- filtered_results()

            cat("--- Step-by-Step Filtering Log ---\n")
            cat(results$log)

            cat("\n--- Final Phyloseq Object Summary ---\n")
            print(results$physeq)

            if (results$is_normalized) {
                cat("\n--- Reads per Sample (After Filtering, Before Normalization) ---\n")
                cat("Sample IDs and read counts:\n")
                print(as.data.frame(results$pre_normalization_sums))
                cat("\n--- Reads per Sample (After Normalization to Median Depth) ---\n")
                cat("Sample IDs and normalized read counts:\n")
                print(as.data.frame(sample_sums(results$physeq)))
            } else {
                cat("\n--- Reads per Sample (After Filtering) ---\n")
                cat("Sample IDs and read counts:\n")
                print(as.data.frame(sample_sums(results$physeq)))
            }
        })

        # ------------------------------------------------------------------
        # Return the reactive filtered data list for downstream modules
        # ------------------------------------------------------------------
        return(reactive({
            res <- filtered_results()
            list(
                normalized      = res$physeq,
                filtered_counts = res$physeq_filtered_only
            )
        }))
    })
}
