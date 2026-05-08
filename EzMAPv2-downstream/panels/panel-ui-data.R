# panels/panel-ui-data.R — Data Upload Panel UI (modern card layout)

library(shinycssloaders)

dataUploadUI <- function(id) {
    ns <- NS(id)

    # Check if files are being auto-loaded from EzMAP2 Java launcher
    env_biom <- Sys.getenv("EZMAP2_BIOM", unset = "")
    is_auto <- nzchar(env_biom) && file.exists(env_biom)

    tagList(
        # Auto-load status banner (rendered by server, visible only when auto-loaded)
        uiOutput(ns("autoLoadStatus")),
        fluidRow(
            # --- Left: file inputs + dataset type ---
            column(4,
                bslib::card(class = "card-upload",
                    bslib::card_header(icon("cloud-upload-alt"),
                        if (is_auto) "Files Auto-Loaded" else "Upload Files"),
                    div(class = "section-label", "Dataset type"),
                    radioButtons(ns("dataset_type"), NULL,
                                 choices  = c("Bacteria (16S rRNA)" = "bacteria",
                                              "Fungi (ITS)"         = "fungi"),
                                 selected = "bacteria", inline = TRUE),
                    helpText(style = "font-size:11px; color:#64748B; margin-top:-4px;",
                             tags$b("Bacteria:"), " enables Tax4Fun & BugBase.",
                             tags$br(),
                             tags$b("Fungi:"), " enables FunGuild."),
                    hr(),
                    if (is_auto) {
                        # Show file paths instead of upload widgets when auto-loaded
                        tagList(
                            div(style = "padding:10px 14px; background:#F0FDF4; border:1px solid #BBF7D0; border-radius:8px; margin-bottom:10px;",
                                icon("check-circle", style = "color:#16A34A;"),
                                strong(" Data loaded automatically."),
                                tags$br(), tags$br(),
                                tags$small(style = "color:#1E293B; font-family:monospace; font-size:11px;",
                                    icon("file"), " ", basename(Sys.getenv("EZMAP2_BIOM")), tags$br(),
                                    icon("file"), " ", basename(Sys.getenv("EZMAP2_METADATA")),
                                    if (nzchar(Sys.getenv("EZMAP2_TREE", ""))) {
                                        tagList(tags$br(), icon("file"), " ",
                                                basename(Sys.getenv("EZMAP2_TREE")))
                                    }
                                )
                            ),
                            helpText(style = "font-size:11px; color:#94A3B8;",
                                     "Files passed from EzMAP2 pipeline. ",
                                     "Restart manually to upload different files."),
                            hr(),
                            tags$details(
                                tags$summary(style = "cursor:pointer; color:#3B82F6; font-size:12px; font-weight:500;",
                                             "Upload different files manually..."),
                                fileInput(ns("biomFile"), "Upload BIOM File (.biom)", accept = ".biom"),
                                fileInput(ns("metaFile"), "Upload Sample Metadata (.tsv)", accept = ".tsv"),
                                fileInput(ns("treeFile"), "Upload Phylogenetic Tree (.nwk)", accept = c(".nwk", ".txt"))
                            )
                        )
                    } else {
                        # Normal upload mode
                        tagList(
                            fileInput(ns("biomFile"), "Upload BIOM File (.biom)", accept = ".biom"),
                            fileInput(ns("metaFile"), "Upload Sample Metadata (.tsv)", accept = ".tsv"),
                            fileInput(ns("treeFile"), "Upload Phylogenetic Tree (.nwk)", accept = c(".nwk", ".txt")),
                            hr(),
                            uiOutput(ns("renameConflictUI")),
                            helpText(style = "font-size:11px; color:#94A3B8;",
                                     "Upload all files before proceeding. Max 50 MB.")
                        )
                    }
                )
            ),
            # --- Right: phyloseq summary + metadata table ---
            column(8,
                # Phyloseq object summary
                bslib::card(class = "card-results",
                    bslib::card_header(icon("clipboard-list"),
                                       "Phyloseq Object Summary"),
                    shinycssloaders::withSpinner(
                        verbatimTextOutput(ns("dataSummary")),
                        type = 6, color = "#3B82F6", size = 0.7,
                        proxy.height = "80px"
                    )
                ),
                # Sample metadata table
                bslib::card(class = "card-results",
                    bslib::card_header(icon("th"), "Sample Metadata"),
                    div(style = "overflow-x:auto; max-width:100%;",
                        shinycssloaders::withSpinner(
                            DT::dataTableOutput(ns("metadataTable")),
                            type = 6, color = "#3B82F6", size = 0.8,
                            caption = "Upload files to view metadata..."
                        )
                    )
                )
            )
        )
    )
}
