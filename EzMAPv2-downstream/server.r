################################################################################
# server.R — Application logic and reactive components.
# Updated 2026-04-16 (professional pass):
#   - AI-style Workflow Guide with Next / Previous buttons on every tab.
#   - Status bar styled for the light footer (readable, professional).
#   - Nav buttons fire observers that call bslib::nav_select() to switch tabs.
#   - DESeq2 + RF combined panel wired and fed from upstream modules.
################################################################################

server <- function(input, output, session) {

    # --- State Management (rv): Controls instructions and status ---
    rv <- reactiveValues(
        data_raw     = NULL,
        state        = "waiting_upload", # waiting_upload | data_loaded | filtering_done | processing
        progress_msg = "Awaiting file selection and upload process.",
        mode_locked  = FALSE             # TRUE after welcome page selection
    )

    # ==========================================================================
    # MODE SELECTION — Welcome page logic
    # On startup: hide all analysis tabs. Show only Welcome + Help.
    # When user picks Easy or Expert: lock mode, hide Welcome, show tabs.
    # ==========================================================================

    # --- Hide analysis tabs on startup (runs once via session$onFlushed) ---
    session$onFlushed(function() {
        tabs_to_hide <- c("tab_data", "tab_filter", "tab_ra",
                          "tab_rarefaction", "tab_alpha", "tab_beta",
                          "tab_lefse", "tab_deseq2", "tab_ancombc",
                          "tab_rf", "tab_deseq2rf", "tab_ancombcrf",
                          "tab_tax4fun2", "tab_funguild", "tab_bugbase",
                          "tab_network", "tab_about", "tab_params")
        for (tab in tabs_to_hide) {
            hideTab(inputId = "main_nav", target = tab)
        }
    }, once = TRUE)

    # --- Navbar mode badge (empty until mode chosen) ---
    output$navbar_mode_badge <- renderUI({
        if (!rv$mode_locked) return(NULL)
        mode <- input$analysis_mode
        if (is.null(mode)) return(NULL)
        badge_class <- if (mode == "easy") "mode-badge easy" else "mode-badge expert"
        badge_icon  <- if (mode == "easy") icon("leaf") else icon("sliders-h")
        badge_label <- if (mode == "easy") "Easy Mode" else "Expert Mode"
        div(style = "display:inline-flex; align-items:center; gap:6px; padding:2px 0;",
            span(class = badge_class, badge_icon, badge_label)
        )
    })

    # --- Helper: unlock all analysis tabs (respecting dataset type) ---
    .show_analysis_tabs <- function() {
        tabs_to_show <- c("tab_data", "tab_filter", "tab_ra",
                          "tab_rarefaction", "tab_alpha", "tab_beta",
                          "tab_lefse", "tab_deseq2", "tab_ancombc",
                          "tab_rf", "tab_deseq2rf", "tab_ancombcrf",
                          "tab_tax4fun2", "tab_funguild", "tab_bugbase",
                          "tab_network", "tab_about", "tab_params")
        for (tab in tabs_to_show) {
            showTab(inputId = "main_nav", target = tab)
        }
        hideTab(inputId = "main_nav", target = "tab_welcome")

        # Apply dataset-type-aware tab visibility immediately
        ds_type <- input$`dataUpload-dataset_type`
        if (!is.null(ds_type) && ds_type == "fungi") {
            hideTab(inputId = "main_nav", target = "tab_tax4fun2")
            hideTab(inputId = "main_nav", target = "tab_bugbase")
            showTab(inputId = "main_nav", target = "tab_funguild")
        } else {
            # Default to bacteria mode
            showTab(inputId = "main_nav", target = "tab_tax4fun2")
            showTab(inputId = "main_nav", target = "tab_bugbase")
            hideTab(inputId = "main_nav", target = "tab_funguild")
        }

        bslib::nav_select(id = "main_nav", selected = "tab_data", session = session)
        rv$mode_locked <- TRUE
    }

    # --- Easy Mode button ---
    observeEvent(input$welcome_easy, {
        updateRadioButtons(session, "analysis_mode", selected = "easy")
        .show_analysis_tabs()
    })

    # --- Expert Mode button ---
    observeEvent(input$welcome_expert, {
        updateRadioButtons(session, "analysis_mode", selected = "expert")
        .show_analysis_tabs()
    })

    # ==========================================================================
    # Helper: Workflow Guide card — "what does this step do", "how to read it"
    # + optional Next / Previous nav buttons.
    # ==========================================================================
    guide_card <- function(step, title, what_it_does, how_to_read,
                           tips = NULL, nav = NULL) {
        tips_html <- if (!is.null(tips)) {
            paste0("<div style='background:#FFFBEB; border-left:3px solid #F59E0B;",
                   " padding:8px 12px; margin-top:10px; border-radius:0 6px 6px 0; font-size:12px;'>",
                   "<b style=\"color:#92400E;\">Tip:</b> ", tips, "</div>")
        } else ""

        nav_tag <- if (!is.null(nav)) nav else tags$span()

        tagList(
            HTML(paste0(
                "<div class='guide-step'>",
                "<span class='step-tag'>", step, "</span>",
                "<h6 style='margin-top:6px; font-size:14px; font-weight:700; color:#1E293B;'>",
                title, "</h6>",
                "<div style='font-size:12px; color:#334155;'><b>What it does:</b> ",
                what_it_does, "</div>",
                "<div style='font-size:12px; color:#334155; margin-top:6px;'><b>How to read it:</b> ",
                how_to_read, "</div>",
                tips_html,
                "</div>"
            )),
            nav_tag
        )
    }

    # Nav buttons (rendered at bottom of every Workflow Guide).
    #   prev_id / next_id : actionButton IDs to react on in the server
    #   prev_label / next_label : link text (or NULL to hide that side)
    nav_buttons <- function(prev_id = NULL, prev_label = NULL,
                            next_id = NULL, next_label = NULL) {
        left <- if (!is.null(prev_id)) {
            actionButton(prev_id,
                         label = HTML(paste0("&#8592; ", prev_label)),
                         class = "btn btn-outline-secondary btn-sm")
        } else tags$span()

        right <- if (!is.null(next_id)) {
            actionButton(next_id,
                         label = HTML(paste0(next_label, " &#8594;")),
                         class = "btn btn-primary btn-sm")
        } else tags$span()

        div(class = "wg-nav", left, right)
    }

    # Navigate helper: switch to a named tab on the main_nav.
    go_to <- function(value) {
        bslib::nav_select(id = "main_nav", selected = value, session = session)
    }

    # ==========================================================================
    # Step 1 — Data Upload (state-aware)
    # ==========================================================================
    output$render_instructions <- renderUI({
        state <- rv$state
        message_list <- switch(state,
            "waiting_upload" = list(
                title = "Step 1: Data Input",
                text  = "Upload your required files (BIOM, metadata, tree) in the panel on the left. EzMAP v2 will automatically construct the <b>phyloseq object</b> that powers every downstream step."
            ),
            "data_loaded" = list(
                title = "Success: Data Ready!",
                text  = "The phyloseq object is loaded. Click <b>Next (Filtering)</b> below to continue."
            ),
            "filtering_done" = list(
                title = "Ready for Analysis",
                text  = "Filtering is complete. You can proceed to Relative Abundance, Alpha or Beta Diversity."
            ),
            "processing" = list(
                title = "Running Analysis...",
                text  = paste("Current Task:", rv$progress_msg, ". Please wait.")
            ),
            list(title = "Welcome", text = "Follow this guide as you move through the analysis workflow.")
        )

        tagList(
            div(class = "guide-step",
                span(class = "step-tag", "STEP 1"),
                tags$h6(message_list$title),
                p(HTML(message_list$text))
            ),
            nav_buttons(
                prev_id    = NULL,            # first step
                next_id    = "nav_next_data",
                next_label = "Next: Filtering"
            )
        )
    })

    # ==========================================================================
    # Step 2 — Filtering
    # ==========================================================================
    output$render_instructions_filtering <- renderUI({
        guide_card(
            step = "Step 2 of 7",
            title = "Filter the phyloseq object",
            what_it_does = "Applies dataset-aware filtering. <b>Bacteria (16S):</b> removes chloroplasts, mitochondria, eukaryotes, and strips <code>D_n__</code> prefixes. <b>Fungi (ITS):</b> removes Chromista, Rhizaria, unidentified phyla, and strips <code>k__/p__/c__/o__/f__/g__/s__</code> prefixes. Both modes drop low-prevalence ASVs and optionally normalise to median depth.",
            how_to_read = "The filter panel auto-detects your dataset type from the Data Upload tab. The right-hand pane logs each step — watch the ASV count drop and confirm most taxa survive. Default: <b>&gt;3 reads in &ge;20% of samples</b>.",
            tips = "Use raw counts for DESeq2 (it normalises internally). Normalise here only for plotting and for the Alpha/Beta pages. Switch dataset type on the Data Upload tab to change filter criteria.",
            nav = nav_buttons(
                prev_id = "nav_prev_filter", prev_label = "Data Upload",
                next_id = "nav_next_filter", next_label = "Next: Relative Abundance"
            )
        )
    })

    # ==========================================================================
    # Step 3 — Relative Abundance
    # ==========================================================================
    output$render_instructions_ra <- renderUI({
        guide_card(
            step = "Step 3 of 8",
            title = "Relative Abundance bar-plots",
            what_it_does = "Agglomerates counts to the chosen taxonomic rank, converts to within-sample proportions, and plots stacked bars grouped by any metadata variable.",
            how_to_read = "Each bar sums to 100% of reads in that sample/group. Dominant phyla (often <i>Firmicutes</i>, <i>Bacteroidota</i>, <i>Proteobacteria</i> in gut) should be clearly visible. Very long legends mean your minimum-abundance cut-off is too low.",
            tips = "Start at <b>Phylum</b> level with a 1% minimum abundance, then drill deeper (Family, Genus).",
            nav = nav_buttons(
                prev_id = "nav_prev_ra", prev_label = "Filtering",
                next_id = "nav_next_ra", next_label = "Next: Rarefaction"
            )
        )
    })

    # ==========================================================================
    # Step 4a — Rarefaction
    # ==========================================================================
    output$render_instructions_rarefaction <- renderUI({
        guide_card(
            step = "Step 4 of 8",
            title = "Rarefaction (subsampling)",
            what_it_does = "Subsamples every sample to the same sequencing depth so diversity comparisons are fair. Draws rarefaction curves showing whether your sequencing effort captured most of the community.",
            how_to_read = "Curves that <b>plateau</b> indicate sufficient sequencing depth. Curves still rising steeply suggest more sequencing would reveal additional taxa. After rarefying, proceed to Alpha Diversity.",
            tips = "Use 90-100% of the minimum sample depth. If the minimum is very low, consider removing those samples first (Filtering tab).",
            nav = nav_buttons(
                prev_id = "nav_prev_rarefaction", prev_label = "Relative Abundance",
                next_id = "nav_next_rarefaction", next_label = "Next: Alpha Diversity"
            )
        )
    })

    # ==========================================================================
    # Step 4 — Alpha Diversity
    # ==========================================================================
    output$render_instructions_alpha <- renderUI({
        guide_card(
            step = "Step 5 of 8",
            title = "Alpha diversity (within-sample richness)",
            what_it_does = "Computes Shannon, Chao1, Simpson, and other diversity indices on the <b>rarefied</b> data, then tests group differences with an automatic normality → variance → ANOVA/Kruskal pipeline.",
            how_to_read = "A higher Shannon index means richer AND more even communities. Boxplots compare diversity across your grouping variable. Significance brackets show pairwise Wilcoxon p-values.",
            tips = "Run Rarefaction first (previous tab). If Shapiro-Wilk rejects normality, Kruskal-Wallis + Dunn post-hoc is used automatically.",
            nav = nav_buttons(
                prev_id = "nav_prev_alpha", prev_label = "Rarefaction",
                next_id = "nav_next_alpha", next_label = "Next: Beta Diversity"
            )
        )
    })

    # ==========================================================================
    # Step 5 — Beta Diversity
    # ==========================================================================
    output$render_instructions_beta <- renderUI({
        guide_card(
            step = "Step 6 of 8",
            title = "Beta diversity (between-sample differences)",
            what_it_does = "Computes a pairwise distance matrix (Bray-Curtis, UniFrac, etc.) on CSS-normalised counts, runs PCoA to project samples into 2-D, and tests group separation with PERMANOVA (<code>adonis2</code>).",
            how_to_read = "Look for <b>clustering + ellipse separation</b> on the PCoA. The PERMANOVA R² tells you how much compositional variation your grouping variable explains — values of 0.05–0.15 are common and meaningful; &gt;0.3 is strong.",
            tips = "For phylogenetically-aware distance use Weighted UniFrac (requires a tree).",
            nav = nav_buttons(
                prev_id = "nav_prev_beta", prev_label = "Alpha Diversity",
                next_id = "nav_next_beta", next_label = "Next: LEfSe"
            )
        )
    })

    # ==========================================================================
    # Advanced — DESeq2
    # ==========================================================================
    output$render_instructions_deseq2 <- renderUI({
        guide_card(
            step = "Advanced · Differential Abundance",
            title = "DESeq2 per-ASV testing",
            what_it_does = "Fits a negative-binomial GLM to raw counts (Wald test, parametric dispersion), returns a log2 fold change and FDR-adjusted p-value for every ASV, and draws a volcano plot coloured by significance.",
            how_to_read = "Dots top-right = enriched in Group 2. Dots top-left = enriched in Group 1. Dashed lines are your cut-offs (|log2FC| and padj). Download the CSV to get full taxonomy.",
            tips = "Use <b>raw counts</b> here — DESeq2 handles normalisation internally.",
            nav = nav_buttons(
                prev_id = "nav_prev_deseq2", prev_label = "LEfSe",
                next_id = "nav_next_deseq2", next_label = "Next: ANCOM-BC"
            )
        )
    })

    # ==========================================================================
    # Advanced — Random Forest
    # ==========================================================================
    output$render_instructions_rf <- renderUI({
        guide_card(
            step = "Advanced · Machine Learning",
            title = "Random Forest classifier",
            what_it_does = "Trains an RF model to predict each sample's group label from its ASV abundances, then ranks features by Mean Decrease Gini (how much each ASV improves the classifier).",
            how_to_read = "The feature-importance bar chart lists ASVs that best separate your groups. Accuracy, Kappa, and (for two groups) AUC on the Performance tab quantify how well the model learned — AUC &gt; 0.85 is strong, 0.65–0.85 moderate.",
            tips = "RF is trained and evaluated on the same data here. Treat the biomarker list as exploratory until validated.",
            nav = nav_buttons(
                prev_id = "nav_prev_rf", prev_label = "ANCOM-BC",
                next_id = "nav_next_rf", next_label = "Next: DESeq2 + RF"
            )
        )
    })

    # ==========================================================================
    # Advanced — DESeq2 + RF Combined
    # ==========================================================================
    output$render_instructions_deseq2rf <- renderUI({
        guide_card(
            step = "Advanced · Biomarker Shortlist",
            title = "Intersect DESeq2 and Random Forest",
            what_it_does = "Joins the two previous analyses: the set of ASVs that are <i>both</i> DESeq2-significant (padj &amp; log2FC cut-offs) AND in the top-N of RF importance. The intersection is the highest-confidence biomarker shortlist.",
            how_to_read = "The Overview tab shows four counters and a Venn; the Scatter tab plots effect size (DESeq2) against importance (RF) — <span style='color:#E74C3C;'><b>red points</b></span> are the overlap. The Intersection Table lists those ASVs with full taxonomy.",
            tips = "Empty result? Loosen the cut-offs or raise RF top-N.",
            nav = nav_buttons(
                prev_id = "nav_prev_deseq2rf", prev_label = "Random Forest",
                next_id = "nav_next_deseq2rf", next_label = "Next: ANCOM-BC + RF"
            )
        )
    })

    # ==========================================================================
    # Advanced — ANCOM-BC + RF Combined
    # ==========================================================================
    output$render_instructions_ancombcrf <- renderUI({
        guide_card(
            step = "Advanced · Compositional Biomarker Shortlist",
            title = "Intersect ANCOM-BC and Random Forest",
            what_it_does = "Joins two analyses: the set of ASVs that are <i>both</i> ANCOM-BC-significant (padj &amp; log2FC cut-offs with compositional bias correction) AND in the top-N of RF importance. ANCOM-BC explicitly models sampling fraction, providing unbiased log fold-change estimates.",
            how_to_read = "The Overview tab shows four counters and a Venn; the Scatter tab plots ANCOM-BC effect size against RF importance — <span style='color:#E74C3C;'><b>colored points</b></span> are the overlap. The Method Comparison tab explains how this differs from DESeq2+RF.",
            tips = "Compare with the DESeq2+RF panel: taxa in both intersections are highest-confidence biomarkers.",
            nav = nav_buttons(
                prev_id = "nav_prev_ancombcrf", prev_label = "DESeq2 + RF",
                next_id = "nav_next_ancombcrf", next_label = "Next: Tax4Fun"
            )
        )
    })

    # ==========================================================================
    # Advanced — Network Analysis
    # ==========================================================================
    output$render_instructions_network <- renderUI({
        guide_card(
            step = "Advanced · Co-occurrence",
            title = "Microbial correlation networks",
            what_it_does = "Builds a graph where each node is an ASV and each edge is a strong correlation (Pearson/Spearman/SPIEC-EASI) above your chosen threshold. Positive edges are green, negative red.",
            how_to_read = "Look for <b>hubs</b> (high-degree nodes) — they may be keystone taxa. The Centrality Distributions tab shows degree/betweenness/closeness/eigenvector distributions. The Comparison tab re-runs the network per group.",
            tips = "Correlation ≠ causation. Use SPIEC-EASI to minimise compositional artefacts.",
            nav = nav_buttons(
                prev_id = "nav_prev_network", prev_label = "BugBase",
                next_id = NULL, next_label = NULL
            )
        )
    })

    # ==========================================================================
    # Advanced — Tax4Fun2
    # ==========================================================================
    output$render_instructions_tax4fun2 <- renderUI({
        guide_card(
            step = "Advanced · Functional prediction",
            title = "Tax4Fun2 KEGG pathway inference",
            what_it_does = "Maps your 16S ASVs against a SILVA reference genome database and predicts the relative abundance of KEGG functional pathways.",
            how_to_read = "The heatmap shows the top-variance pathways (rows scaled). Clusters of rows indicate pathway groups that co-vary across samples.",
            tips = "Tax4Fun2 is an <b>approximation</b> of function from taxonomy — validate intriguing pathways with metagenomics or targeted assays.",
            nav = nav_buttons(
                prev_id = "nav_prev_tax4fun2", prev_label = "DESeq2 + RF",
                next_id = "nav_next_tax4fun2", next_label = "Next: BugBase"
            )
        )
    })

    # ==========================================================================
    # Advanced — BugBase
    # ==========================================================================
    output$render_instructions_bugbase <- renderUI({
        guide_card(
            step = "Functional · Phenotype prediction",
            title = "BugBase phenotype inference",
            what_it_does = "Predicts organism-level phenotypes (Gram staining, oxygen tolerance, pathogenicity, biofilm formation) from 16S taxonomy using a curated genus-trait database.",
            how_to_read = "Box plots compare trait scores across groups. Higher scores indicate greater community-level prevalence of a phenotype. Stars indicate significant differences (Kruskal-Wallis).",
            tips = "BugBase uses genus-level mapping — coverage depends on how many genera in your data are in the trait database. Check the Summary tab for coverage statistics.",
            nav = nav_buttons(
                prev_id = "nav_prev_bugbase", prev_label = "Tax4Fun",
                next_id = "nav_next_bugbase", next_label = "Next: Network"
            )
        )
    })

    output$render_instructions_funguild <- renderUI({
        guide_card(
            step = "Functional · Guild assignment",
            title = "FunGuild ecological guild prediction",
            what_it_does = "Matches your ITS fungal taxa against a curated database of ~170 genera to assign <b>trophic modes</b> (Saprotroph, Pathotroph, Symbiotroph) and <b>ecological guilds</b> (e.g. Ectomycorrhizal, Wood Saprotroph, Plant Pathogen). Computes abundance-weighted proportions per sample and tests group differences.",
            how_to_read = "The <b>Trophic Mode</b> tab shows broad functional categories per sample. The <b>Guild Composition</b> tab drills into specific guilds. The <b>Heatmap</b> tab reveals patterns across samples. Check the Statistics tab for Kruskal-Wallis/Wilcoxon group comparisons with FDR correction.",
            tips = "FunGuild works best with <b>ITS data</b> and genus-level identification. Use 'Possible' confidence to maximise coverage, or 'Probable'/'Highly Probable' for stricter matches. Compare trophic mode shifts across your treatment groups.",
            nav = nav_buttons(
                prev_id = "nav_prev_funguild", prev_label = "BugBase",
                next_id = "nav_next_funguild", next_label = "Next: Network"
            )
        )
    })

    # ==========================================================================
    # Advanced — LEfSe
    # ==========================================================================
    output$render_instructions_lefse <- renderUI({
        guide_card(
            step = "Advanced · Differential abundance",
            title = "LEfSe LDA effect size",
            what_it_does = "Identifies taxa that are significantly differentially abundant between groups using Kruskal-Wallis test, pairwise Wilcoxon consistency checks, and LDA effect-size ranking.",
            how_to_read = "The bar plot shows signed LDA scores — bars extend left for the reference group and right for the comparison group. The dot plot provides an alternative view ranked by effect size. Use 'All levels' to test across the full taxonomy.",
            tips = "An LDA cutoff of 2.0 is standard; lower it if too few features are found. Compare LEfSe results with DESeq2 and ANCOM-BC for cross-validation.",
            nav = nav_buttons(
                prev_id = "nav_prev_lefse", prev_label = "Beta Diversity",
                next_id = "nav_next_lefse", next_label = "Next: DESeq2"
            )
        )
    })

    # ==========================================================================
    # Advanced — ANCOM-BC
    # ==========================================================================
    output$render_instructions_ancombc <- renderUI({
        guide_card(
            step = "Advanced · Compositional DA",
            title = "ANCOM-BC bias-corrected differential abundance",
            what_it_does = "Tests for differentially abundant taxa using ANCOM-BC (Lin &amp; Peddada 2020), which explicitly models the unknown sampling fraction to correct for the compositional bias inherent in sequencing data. Provides unbiased log fold changes and FDR-corrected p-values.",
            how_to_read = "The volcano plot shows log2 fold change (x) vs significance (y). Points beyond both dashed lines are significant AND biologically meaningful. The bar plot ranks significant taxa by effect size. Compare results with DESeq2 for cross-validation.",
            tips = "ANCOM-BC is <b>compositional-aware</b> — it's considered more appropriate than DESeq2 for microbiome data. Use both methods and look for <b>overlap</b> to build a high-confidence biomarker list (as recommended by reviewers).",
            nav = nav_buttons(
                prev_id = "nav_prev_ancombc", prev_label = "DESeq2",
                next_id = "nav_next_ancombc", next_label = "Next: Random Forest"
            )
        )
    })

    # ==========================================================================
    # Next / Previous navigation observers
    # Flow: Data → Filter → RA → Alpha → Beta → LEfSe → DESeq2 → ANCOM-BC
    #       → RF → DESeq2+RF → Tax4Fun → BugBase → Network
    # ==========================================================================
    # Step 1 → 2
    observeEvent(input$nav_next_data,      { go_to("tab_filter") })
    # Step 2 - Filtering
    observeEvent(input$nav_prev_filter,    { go_to("tab_data") })
    observeEvent(input$nav_next_filter,    { go_to("tab_ra") })
    # Step 3 - RA
    observeEvent(input$nav_prev_ra,            { go_to("tab_filter") })
    observeEvent(input$nav_next_ra,            { go_to("tab_rarefaction") })
    # Step 4a - Rarefaction
    observeEvent(input$nav_prev_rarefaction,   { go_to("tab_ra") })
    observeEvent(input$nav_next_rarefaction,   { go_to("tab_alpha") })
    # Step 4b - Alpha
    observeEvent(input$nav_prev_alpha,         { go_to("tab_rarefaction") })
    observeEvent(input$nav_next_alpha,         { go_to("tab_beta") })
    # Step 5 - Beta
    observeEvent(input$nav_prev_beta,          { go_to("tab_alpha") })
    observeEvent(input$nav_next_beta,      { go_to("tab_lefse") })
    # LEfSe
    observeEvent(input$nav_prev_lefse,     { go_to("tab_beta") })
    observeEvent(input$nav_next_lefse,     { go_to("tab_deseq2") })
    # DESeq2
    observeEvent(input$nav_prev_deseq2,    { go_to("tab_lefse") })
    observeEvent(input$nav_next_deseq2,    { go_to("tab_ancombc") })
    # ANCOM-BC
    observeEvent(input$nav_prev_ancombc,   { go_to("tab_deseq2") })
    observeEvent(input$nav_next_ancombc,   { go_to("tab_rf") })
    # Random Forest
    observeEvent(input$nav_prev_rf,        { go_to("tab_ancombc") })
    observeEvent(input$nav_next_rf,        { go_to("tab_deseq2rf") })
    # DESeq2+RF
    observeEvent(input$nav_prev_deseq2rf,  { go_to("tab_rf") })
    observeEvent(input$nav_next_deseq2rf,  { go_to("tab_ancombcrf") })
    # ANCOM-BC+RF
    observeEvent(input$nav_prev_ancombcrf, { go_to("tab_deseq2rf") })
    observeEvent(input$nav_next_ancombcrf, { go_to("tab_tax4fun2") })
    # Tax4Fun
    observeEvent(input$nav_prev_tax4fun2,  { go_to("tab_ancombcrf") })
    observeEvent(input$nav_next_tax4fun2,  { go_to("tab_bugbase") })
    # BugBase
    observeEvent(input$nav_prev_bugbase,   { go_to("tab_tax4fun2") })
    observeEvent(input$nav_next_bugbase,   { go_to("tab_network") })
    # Network (last in main flow)
    observeEvent(input$nav_prev_network,   { go_to("tab_bugbase") })
    # FunGuild (separate — accessed from Functional Analysis dropdown)
    observeEvent(input$nav_prev_funguild,  { go_to("tab_bugbase") })
    observeEvent(input$nav_next_funguild,  { go_to("tab_network") })

    # ==========================================================================
    # Dataset type: Fungi/Bacteria — disable irrelevant functional tabs
    # ==========================================================================
    observeEvent(input$`dataUpload-dataset_type`, {
        ds_type <- input$`dataUpload-dataset_type`
        if (!is.null(ds_type) && ds_type == "fungi") {
            # Fungi → disable Tax4Fun & BugBase, enable FunGuild
            hideTab(inputId = "main_nav", target = "tab_tax4fun2")
            hideTab(inputId = "main_nav", target = "tab_bugbase")
            showTab(inputId = "main_nav", target = "tab_funguild")
        } else {
            # Bacteria (default) → disable FunGuild, enable Tax4Fun & BugBase
            showTab(inputId = "main_nav", target = "tab_tax4fun2")
            showTab(inputId = "main_nav", target = "tab_bugbase")
            hideTab(inputId = "main_nav", target = "tab_funguild")
        }
    }, ignoreNULL = FALSE)

    # ==========================================================================
    # Progress/State Display in footer
    # ==========================================================================
    output$analysis_state <- renderUI({
        is_active <- rv$state %in% c("data_loaded", "filtering_done", "processing")
        pill_class <- if (is_active) "status-pill active" else "status-pill"
        state_text <- switch(rv$state,
            "waiting_upload"  = "Awaiting Data",
            "data_loaded"     = "Data Loaded",
            "filtering_done"  = "Data Filtered",
            "processing"      = paste0("Processing: ", rv$progress_msg),
            "Idle"
        )
        span(class = pill_class, span(class = "dot"), state_text)
    })

    # ==========================================================================
    # Module wiring
    # ==========================================================================

    # --- 1. Data Upload ---
    physeq_data_reactive <- dataUploadServer("dataUpload")

    observeEvent(physeq_data_reactive(), {
        if (!is.null(physeq_data_reactive())) {
            rv$data_raw <- physeq_data_reactive()
            if (rv$state == "waiting_upload") {
                rv$state <- "data_loaded"
                rv$progress_msg <- "Phyloseq object successfully created."
            }
        }
    })

    # --- 2. Filtering ---
    # Pass the dataset type so the filter module can switch between
    # bacteria-specific (Chloroplast, Mitochondria, D_x__) and
    # fungi-specific (Chromista, Rhizaria, unidentified, k__/p__/…) criteria.
    dataset_type_reactive <- reactive({
        ds <- input$`dataUpload-dataset_type`
        if (is.null(ds)) "bacteria" else ds
    })

    filtered_data_list_reactive <- filterServer(
        id = "filter",
        physeq_data = physeq_data_reactive,
        global_state_rv = rv,
        dataset_type = dataset_type_reactive
    )

    observeEvent(filtered_data_list_reactive(), {
        if (!is.null(filtered_data_list_reactive()) && rv$state != "waiting_upload") {
            rv$state <- "filtering_done"
            rv$progress_msg <- "Data filtering results available."
        }
    })

    # --- Convenience reactive: filtered counts (pre-normalization) ---
    # All downstream modules receive BOTH raw + filtered reactives so the user
    # can toggle between them via the dataset selector.
    physeq_filtered_reactive <- reactive({
        res <- tryCatch(filtered_data_list_reactive(), error = function(e) NULL)
        if (!is.null(res)) res$filtered_counts else NULL
    })

    # --- 3. Relative Abundance (still uses the full list for normalized view) ---
    raPlotServer(
        id = "raPlot",
        physeq_data_LIST = filtered_data_list_reactive,
        global_state_rv = rv
    )

    # --- 4a. Rarefaction ---
    rarefied_data_reactive <- rarefactionServer(
        id = "rarefaction_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 4b. Alpha Diversity (consumes rarefied data from Rarefaction) ---
    alphaDiversityServer(
        id = "alphaDiv",
        rarefied_data   = rarefied_data_reactive,
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 5. Beta Diversity ---
    betaDiversityServer(
        id = "beta_analysis_id",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 6. DESeq2 (captured so the combined panel can consume it) ---
    deseq2_out <- deseq2Server(
        id = "deseq2",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 7. Random Forest (captured so the combined panel can consume it) ---
    rf_out <- randomForestServer(
        id = "random_forest_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 8. DESeq2 + RF Combined — only joins existing results ---
    deseq2rfServer(
        id = "deseq2rf_panel",
        deseq2_out      = deseq2_out,
        rf_out          = rf_out,
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 9. Network ---
    networkServer(
        id = "network_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 10. Tax4Fun2 ---
    tax4fun2_out <- tax4fun2Server(
        id = "tax4fun2_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 11. BugBase ---
    bugbaseServer(
        id = "bugbase_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 12. LEfSe ---
    lefseServer(
        id = "lefse_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 13. ANCOM-BC ---
    ancombc_out <- ancombcServer(
        id = "ancombc_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 13b. ANCOM-BC + RF Combined — compositional bias-corrected intersection ---
    ancombcrfServer(
        id = "ancombcrf_panel",
        ancombc_out     = ancombc_out,
        rf_out          = rf_out,
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )

    # --- 14. FunGuild ---
    funguildServer(
        id = "funguild_panel",
        physeq_raw      = physeq_data_reactive,
        physeq_filtered = physeq_filtered_reactive,
        global_state_rv = rv
    )
}
