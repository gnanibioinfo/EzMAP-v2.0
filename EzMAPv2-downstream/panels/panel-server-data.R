################################################################################
# panels/panel-server-data.R — Clean Data Upload Server (Exact Original Metadata)
#
# Supports two modes:
#   1. Manual upload: user uploads BIOM, metadata, tree via file inputs.
#   2. Auto-load: if EZMAP2_BIOM / EZMAP2_METADATA / EZMAP2_TREE env vars
#      are set (by the Java launcher), files are loaded automatically on startup
#      and the upload UI shows "Files auto-loaded from EzMAP2 pipeline".
################################################################################

dataUploadServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    local({

      # ================================================================
      # Check for auto-load env vars (set by Java launcher)
      # ================================================================
      env_biom <- Sys.getenv("EZMAP2_BIOM", unset = "")
      env_meta <- Sys.getenv("EZMAP2_METADATA", unset = "")
      env_tree <- Sys.getenv("EZMAP2_TREE", unset = "")

      auto_load <- nzchar(env_biom) && file.exists(env_biom) &&
                   nzchar(env_meta) && file.exists(env_meta)
      auto_tree <- nzchar(env_tree) && file.exists(env_tree)

      # Reactive flag so UI can react to auto-load state
      auto_loaded <- reactiveVal(FALSE)

      # ------------------------------------------------------------------
      # Safe Metadata Import (Preserve exact original columns)
      # ------------------------------------------------------------------
      safe_import_metadata <- function(filepath) {
        meta <- read.table(
          filepath,
          header = TRUE,
          sep = "\t",
          comment.char = "",
          quote = "",
          check.names = FALSE,  # Preserve original column names
          stringsAsFactors = FALSE,
          row.names = NULL
        )

        # Remove #q2:types row if present
        meta <- meta[!grepl("^#q2:types", meta[[1]]), ]

        # Remove any duplicate columns that might exist in the file
        meta <- meta[, !duplicated(names(meta))]

        # Set rownames to sample-id if exists
        if ("sample-id" %in% names(meta)) {
          rownames(meta) <- meta$`sample-id`
        }

        return(meta)
      }

      # ------------------------------------------------------------------
      # Core builder: constructs phyloseq from file paths
      # ------------------------------------------------------------------
      build_phyloseq <- function(biom_path, meta_path, tree_path = NULL) {
        withProgress(message = 'Loading Data...', value = 0, {

          incProgress(0.2, detail = "Reading BIOM feature table...")
          biom1 <- biomformat::read_biom(biom_path)
          mp0 <- import_biom(biom1)

          incProgress(0.2, detail = "Processing sample metadata...")
          metadata_df <- safe_import_metadata(meta_path)
          cleaned_qsd <- sample_data(metadata_df)

          # Pre-flight check: BIOM sample IDs vs metadata sample IDs.
          # If they don't overlap, merge_phyloseq() throws an obscure
          # "invalid class 'phyloseq' object: Component sample names do
          # not match" error -- give the user a clearer, actionable
          # message instead.
          biom_ids <- sample_names(mp0)
          meta_ids <- rownames(metadata_df)
          common_ids <- intersect(biom_ids, meta_ids)
          if (length(common_ids) == 0) {
              showNotification(ui = tagList(
                  tags$b("Sample IDs in BIOM and metadata don't match."),
                  tags$br(),
                  "BIOM has ", length(biom_ids), " samples (e.g. ",
                  tags$code(paste(head(biom_ids, 3), collapse = ", ")), "); ",
                  "metadata has ", length(meta_ids), " (e.g. ",
                  tags$code(paste(head(meta_ids, 3), collapse = ", ")), "). ",
                  tags$br(), tags$br(),
                  "Fix: ensure the first column of your metadata TSV ",
                  "(sample-id) contains exactly the same IDs as the BIOM ",
                  "table column headers. Watch for hidden whitespace, ",
                  "trailing newlines, or BOM characters."
              ), type = "error", duration = NULL)
              stop("Sample IDs in BIOM and metadata don't match. ",
                   "BIOM has ", length(biom_ids), " samples, metadata has ",
                   length(meta_ids), ", overlap = 0. Check the first column ",
                   "of your metadata file.", call. = FALSE)
          }
          if (length(common_ids) < length(biom_ids) ||
              length(common_ids) < length(meta_ids)) {
              showNotification(ui = tagList(
                  tags$b("Partial sample-ID overlap."),
                  tags$br(),
                  "BIOM has ", length(biom_ids), " samples, metadata has ",
                  length(meta_ids), ", overlap = ", length(common_ids), ". ",
                  "Continuing with the ", length(common_ids), " matched samples. ",
                  "Samples missing from one side will be dropped."
              ), type = "warning", duration = 12)
          }

          incProgress(0.2, detail = "Merging counts and metadata...")
          mp1 <- merge_phyloseq(mp0, cleaned_qsd)

          if (!is.null(tree_path) && file.exists(tree_path)) {
            incProgress(0.3, detail = "Reading phylogenetic tree...")
            tree1 <- read_tree(tree_path)
            physeq <- merge_phyloseq(mp1, tree1)
          } else {
            incProgress(0.3, detail = "No tree file — skipping phylogeny.")
            physeq <- mp1
          }

          # Standardize taxa names (ASV1, ASV2, …)
          taxa_names(physeq) <- paste0("ASV", 1:ntaxa(physeq))
          colnames(tax_table(physeq)) <- c("Kingdom", "Phylum", "Class",
                                           "Order", "Family", "Genus", "Species")

          # Strip QIIME 2 / SILVA / Greengenes taxonomy-rank prefixes
          # (d__, k__, p__, c__, o__, f__, g__, s__ and the older
          # D_0__ / D_1__ ... pattern) from EVERY value in the tax_table.
          # Doing it once here means every downstream panel — Relative
          # Abundance, plot legends, exports, FunGuild matching, etc. —
          # sees clean human-readable names without each panel having
          # to repeat the regex. Local strips in DESeq2/ANCOM-BC/RF/
          # Beta/LEfSe become no-ops on already-clean strings but stay
          # as defensive safety nets.
          tax_mat <- as(tax_table(physeq), "matrix")
          tax_mat[,] <- gsub("[Dd]_[0-9]+__", "", tax_mat[,])
          tax_mat[,] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_mat[,])
          tax_mat[,] <- trimws(tax_mat[,])
          tax_table(physeq) <- tax_table(tax_mat)

          incProgress(0.1, detail = "Complete.")
        })

        return(physeq)
      }

      # ------------------------------------------------------------------
      # Reactive metadata (for manual upload path)
      # ------------------------------------------------------------------
      raw_metadata_df <- reactive({
        if (auto_loaded()) {
          safe_import_metadata(env_meta)
        } else {
          req(input$metaFile)
          safe_import_metadata(input$metaFile$datapath)
        }
      })

      # ------------------------------------------------------------------
      # Build Phyloseq object — auto-load OR manual upload
      # ------------------------------------------------------------------
      physeq_object <- reactive({
        if (auto_loaded()) {
          # Auto-load path: use env var file paths directly
          tree_path <- if (auto_tree) env_tree else NULL
          build_phyloseq(env_biom, env_meta, tree_path)
        } else {
          # Manual upload path: require file inputs
          req(input$biomFile, input$metaFile, input$treeFile)
          build_phyloseq(input$biomFile$datapath,
                         input$metaFile$datapath,
                         input$treeFile$datapath)
        }
      })

      # ------------------------------------------------------------------
      # Auto-load trigger: runs once on startup if env vars are set
      # ------------------------------------------------------------------
      if (auto_load) {
        observe({
          # Only trigger once
          if (!auto_loaded()) {
            auto_loaded(TRUE)
            message("[EzMAP2] Auto-loading data from pipeline output:")
            message("  BIOM: ", env_biom)
            message("  META: ", env_meta)
            if (auto_tree) message("  TREE: ", env_tree)
          }
        })
      }

      # ------------------------------------------------------------------
      # Outputs
      # ------------------------------------------------------------------
      # Data loaded successfully — placeholder for post-load actions
      observeEvent(physeq_object(), {
        # Data is ready; downstream modules can now access it
      })

      # Auto-load status message (shown in the UI)
      output$autoLoadStatus <- renderUI({
        if (auto_loaded()) {
          div(class = "guide-step",
              style = "border-color:#10B981; background:#F0FDF4;",
              icon("check-circle", style = "color:#16A34A;"),
              strong(" Files auto-loaded from EzMAP2 pipeline"),
              tags$br(),
              tags$small(style = "color:#94A3B8;",
                         "BIOM: ", basename(env_biom),
                         if (auto_tree) paste0(" | Tree: ", basename(env_tree)) else "",
                         " | Metadata: ", basename(env_meta)))
        }
      })

      output$dataSummary <- renderPrint({
        physeq <- physeq_object()
        req(physeq)
        if (auto_loaded()) {
          cat("Auto-loaded from EzMAP2 pipeline output.\n")
        } else {
          cat("Uploaded and processed successfully!\n")
        }
        print(physeq)
      })

      output$metadataTable <- DT::renderDataTable({
        physeq <- physeq_object()
        req(physeq)

        sd <- sample_data(physeq)
        metadata_df <- as(sd, "data.frame")

        if (is.null(metadata_df) || nrow(metadata_df) == 0 || ncol(metadata_df) == 0) {
          return(DT::datatable(
            data.frame(Message = "No sample metadata available."),
            rownames = FALSE,
            options  = list(dom = 't'),
            class    = "display compact cell-border stripe hover"
          ))
        }

        DT::datatable(
          metadata_df,
          rownames = FALSE,
          filter   = "top",
          options = list(
            pageLength  = 10,
            lengthMenu  = c(5, 10, 25, 50, 100),
            autoWidth   = TRUE,
            scrollX     = TRUE,
            scrollY     = "380px",
            scrollCollapse = TRUE,
            dom         = 'lftipr',
            columnDefs  = list(list(className = 'dt-left', targets = "_all"))
          ),
          caption = if (auto_loaded()) "Auto-loaded Sample Metadata"
                    else "Uploaded Sample Metadata (exact original columns)",
          class   = "display compact cell-border stripe hover nowrap"
        )
      })

      return(physeq_object)
    })
  })
}
