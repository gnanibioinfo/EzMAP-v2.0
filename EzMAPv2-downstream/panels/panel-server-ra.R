################################################################################
# panels/panel-server-ra.R — Relative Abundance Plot Server Logic (Multi-variable Filter + Flexible Grouping)
################################################################################

raPlotServer <- function(id, physeq_data_LIST, global_state_rv = NULL) {
    moduleServer(id, function(input, output, session) {
        
        ns <- session$ns
        
        output$groupVariableUI <- renderUI({
            req(physeq_data_LIST())
            physeq <- physeq_data_LIST()$normalized
            req(physeq)
            sample_vars <- sample_variables(physeq)
            selectInput(
                ns("groupVariable"),
                "Group by Sample Variable(s):",
                choices = sample_vars,
                selected = NULL,
                multiple = TRUE
            )
        })
        
        # --- Facet variable selector ---
        output$facetVariableUI <- renderUI({
            req(physeq_data_LIST())
            physeq <- physeq_data_LIST()$normalized
            req(physeq)
            sample_vars <- sample_variables(physeq)
            selectInput(
                ns("facetVariable"),
                "Facet by (optional):",
                choices = c("None" = "none", sample_vars),
                selected = "none"
            )
        })

        # --- Custom order UI (sortable list of current group levels) ---
        output$customOrderUI <- renderUI({
            req(physeq_data_LIST(), input$groupVariable)
            physeq <- physeq_data_LIST()$normalized
            req(physeq)
            meta <- as.data.frame(sample_data(physeq))
            group_vars <- input$groupVariable
            if (length(group_vars) > 1) {
                combo <- apply(meta[, group_vars, drop = FALSE], 1, paste, collapse = "_")
                lvls <- sort(unique(combo))
            } else {
                lvls <- sort(unique(as.character(meta[[group_vars]])))
            }
            selectizeInput(
                ns("customLevelOrder"),
                "Drag to reorder groups:",
                choices = lvls,
                selected = lvls,
                multiple = TRUE,
                options = list(
                    plugins = list("drag_drop", "remove_button"),
                    placeholder = "Drag groups into desired order..."
                )
            )
        })

        output$filterVariableSelector <- renderUI({
            req(physeq_data_LIST())
            physeq <- physeq_data_LIST()$normalized
            sample_vars <- sample_variables(physeq)
            checkboxGroupInput(
                ns("filterVars"),
                "Select Metadata Variables to Filter:",
                choices = sample_vars,
                selected = NULL
            )
        })
        
        output$filterValueSelectors <- renderUI({
            req(physeq_data_LIST(), input$filterVars)
            physeq <- physeq_data_LIST()$normalized
            meta <- as.data.frame(sample_data(physeq))
            lapply(input$filterVars, function(var) {
                var_levels <- sort(unique(meta[[var]]))
                selectInput(
                    ns(paste0("filter_", var)),
                    label = paste("Filter by", var, ":"),
                    choices = var_levels,
                    selected = var_levels,
                    multiple = TRUE
                )
            })
        })
        
        # Plot reactive: requires at least one button click before rendering.
        # After the first click, subsequent input changes auto-update the plot.
        ra_plot_data <- reactive({
            # Track the button — first click gates initial render
            btn <- input$updatePlot
            req(btn > 0)
            req(physeq_data_LIST(), input$groupVariable)

            # Handle NULL fallbacks for expert-only parameters (returned when in Easy mode)
            min_abund <- if (is.null(input$minAbundance)) 1 else input$minAbundance
            color_palette <- if (is.null(input$colorPalette)) "Paired" else input$colorPalette
            base_font_size <- if (is.null(input$baseFontSize)) 14 else input$baseFontSize
            axis_label_size <- if (is.null(input$axisLabelSize)) 12 else input$axisLabelSize
            x_angle <- if (is.null(input$xAngle)) 45 else input$xAngle
            legend_pos <- if (is.null(input$legendPosition)) "right" else input$legendPosition
            legend_cols <- if (is.null(input$legendCols)) 1 else input$legendCols
            custom_x_label <- if (is.null(input$customXLabel)) "" else input$customXLabel
            custom_y_label <- if (is.null(input$customYLabel)) "" else input$customYLabel

            # Resolve the shared styling block: plot title, legend title,
            # ggplot theme, grid toggles, and X/Y axis-title font sizes.
            # See ezmap_plot_styling() in global.r.
            styles <- ezmap_plot_styling(input,
                                         default_legend_title = input$taxaRank,
                                         base_size = base_font_size)

            physeq <- if(input$data_source == "normalized") {
                physeq_data_LIST()$normalized
            } else {
                physeq_data_LIST()$filtered_counts
            }

            if(!is.null(input$filterVars) && length(input$filterVars) > 0){
                meta_df <- as.data.frame(sample_data(physeq))
                keep_samples <- rep(TRUE, nrow(meta_df))
                for(var in input$filterVars){
                    selected_vals <- input[[paste0("filter_", var)]]
                    keep_samples <- keep_samples & (meta_df[[var]] %in% selected_vals)
                }
                physeq <- prune_samples(keep_samples, physeq)
            }

            group_vars <- input$groupVariable
            meta_df <- as.data.frame(sample_data(physeq))
            if(length(group_vars) > 1){
                combo_name <- paste(group_vars, collapse = "_")
                meta_df[[combo_name]] <- apply(meta_df[, group_vars, drop = FALSE], 1, paste, collapse = "_")
                sample_data(physeq) <- meta_df
                group_var <- sym(combo_name)
            } else {
                group_var <- sym(group_vars)
            }

            ra_data <- physeq %>%
                tax_glom(taxrank = input$taxaRank) %>%
                transform_sample_counts(function(x) x / sum(x)) %>%
                psmelt() %>%
                filter(Abundance >= min_abund / 100) %>%
                arrange(!!group_var)

            # --- X-axis reordering ---
            grp_col_name <- as.character(group_var)
            sample_order <- if (is.null(input$sampleOrder)) "default" else input$sampleOrder

            if (sample_order == "alpha") {
                lvls <- sort(unique(as.character(ra_data[[grp_col_name]])))
                ra_data[[grp_col_name]] <- factor(ra_data[[grp_col_name]], levels = lvls)
            } else if (sample_order == "abundance") {
                # Order by total abundance of the most abundant taxon (descending)
                grp_totals <- tapply(ra_data$Abundance, ra_data[[grp_col_name]], sum)
                lvls <- names(sort(grp_totals, decreasing = TRUE))
                ra_data[[grp_col_name]] <- factor(ra_data[[grp_col_name]], levels = lvls)
            } else if (sample_order == "custom" && !is.null(input$customLevelOrder)) {
                custom_lvls <- input$customLevelOrder
                # Include any levels not in user selection at the end
                all_lvls <- unique(as.character(ra_data[[grp_col_name]]))
                lvls <- c(custom_lvls, setdiff(all_lvls, custom_lvls))
                ra_data[[grp_col_name]] <- factor(ra_data[[grp_col_name]], levels = lvls)
            }
            # default: leave as-is (metadata order)

            colourCount <- length(unique(ra_data[[input$taxaRank]]))
            palette_size <- min(12, brewer.pal.info[color_palette, "maxcolors"])
            getPalette <- colorRampPalette(brewer.pal(palette_size, color_palette))

            # Legend title: helper handles user override; falls back to
            # taxonomy rank (passed in default_legend_title above) when
            # the user leaves the field blank.
            fill_title <- if (is.null(styles$legend_title)) input$taxaRank else styles$legend_title

            p <- ggplot(ra_data, aes(x = !!group_var, y = Abundance, fill = !!sym(input$taxaRank))) +
                geom_bar(stat = "identity", position = "fill", width = 0.8) +
                labs(title = styles$title,
                     x = custom_x_label,
                     y = custom_y_label,
                     fill = fill_title) +
                scale_fill_manual(values = getPalette(colourCount)) +
                scale_y_continuous(labels = scales::percent_format(accuracy = 1), limits = c(0, 1)) +
                # Theme: shared styling first (sets axis-title sizes,
                # plot title, grid toggles), then panel-specific
                # overrides (tick text size, x-angle, legend position).
                styles$theme_fn(base_size = base_font_size) +
                styles$grid_theme +
                theme(
                    axis.text.x = element_text(angle = x_angle,
                                               hjust = ifelse(x_angle == 0, 0.5, 1),
                                               vjust = 0.5,
                                               size = axis_label_size),
                    axis.text.y = element_text(size = axis_label_size),
                    legend.position = legend_pos,
                    legend.key.size = unit(0.8, "lines")
                ) +
                guides(fill = guide_legend(ncol = legend_cols))

            # --- Faceting ---
            facet_var <- if (is.null(input$facetVariable)) "none" else input$facetVariable
            if (facet_var != "none" && facet_var %in% colnames(ra_data)) {
                p <- p + facet_wrap(as.formula(paste("~", facet_var)),
                                    scales = "free_x")
            }

            p
        })
        
        output$raPlot <- renderPlot({
            ra_plot_data()
        })
        
        output$downloadRAplot <- downloadHandler(
            filename = function() {
                ezmap_download_filename(input, paste0("Relative_Abundance_", input$taxaRank))
            },
            content = function(file) {
                # Handle pixel-based dimensions
                units <- input$downloadUnits
                width <- input$downloadWidth
                height <- input$downloadHeight
                dpi <- input$downloadDPI
                if(units == "px"){
                    # Convert pixels to inches for ggsave
                    width <- width / dpi
                    height <- height / dpi
                    units <- "in"
                }
                ggsave(file,
                       plot = ra_plot_data(),
                       width = width,
                       height = height,
                       units = units,
                       dpi = dpi)
            }
        )
    })
}
