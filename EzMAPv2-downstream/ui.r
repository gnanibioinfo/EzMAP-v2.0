################################################################################
# ui.R — EzMAP v2.0 Downstream Analysis UI
# Redesigned 2026-04-20: Professional dark-nav theme with modern card layout
################################################################################

# --- Source Module UI Files ---
source("panels/panel-ui-data.R",        local = TRUE)
source("panels/panel-ui-filter.R",      local = TRUE)
source("panels/panel-ui-ra.R",          local = TRUE)
source("panels/panel-ui-rarefaction.R", local = TRUE)
source("panels/panel-ui-alpha.R",       local = TRUE)
source("panels/panel-ui-beta.R",        local = TRUE)
source("panels/panel-ui-deseq2.R",      local = TRUE)
source("panels/panel-ui-random.R",      local = TRUE)
source("panels/panel-ui-network.R",     local = TRUE)
source("panels/panel-ui-tax4fun2.R",    local = TRUE)
source("panels/panel-ui-bugbase.R",     local = TRUE)
source("panels/panel-ui-lefse.R",       local = TRUE)
source("panels/panel-ui-ancombc.R",     local = TRUE)
source("panels/panel-ui-deseq2rf.R",    local = TRUE)
source("panels/panel-ui-ancombcrf.R",   local = TRUE)
source("panels/panel-ui-funguild.R",    local = TRUE)


# --- UI DEFINITION ---
ui <- bslib::page_navbar(
    id = "main_nav",
    theme = bslib::bs_theme(
        version   = 5,
        bootswatch = "flatly",
        "primary"   = "#3B82F6",
        "success"   = "#10B981",
        "info"      = "#06B6D4",
        "warning"   = "#F59E0B",
        "danger"    = "#EF4444",
        "font-scale" = 0.88,
        bg   = "#FFFFFF",
        fg   = "#1E293B",
        base_font    = bslib::font_collection(
            bslib::font_google("Inter", wght = "300..700"),
            "-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "sans-serif"
        ),
        heading_font = bslib::font_collection(
            bslib::font_google("Inter", wght = "600..800"),
            "-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "sans-serif"
        )
    ),
    bg      = "#0F172A",
    inverse = TRUE,

    title = span(
        style = "display:inline-flex; align-items:center; gap:8px; font-weight:600;",
        tags$img(src = "ezmap_icon.png", height = "28px", style = "margin-right:4px; vertical-align:middle;"),
        span("EzMAP v2.0", style = "letter-spacing:0.3px;")
    ),

    # ==================================================================
    # HEAD: CSS + JS
    # ==================================================================
    tags$head(
        useShinyjs(),
        tags$style(HTML("

            /* ==========================================================
               DESIGN TOKENS
               ========================================================== */
            :root {
                --ez-navy:     #0F172A;
                --ez-slate:    #1E293B;
                --ez-blue:     #3B82F6;
                --ez-blue-lt:  #60A5FA;
                --ez-emerald:  #10B981;
                --ez-amber:    #F59E0B;
                --ez-rose:     #F43F5E;
                --ez-gray-50:  #F8FAFC;
                --ez-gray-100: #F1F5F9;
                --ez-gray-200: #E2E8F0;
                --ez-gray-300: #CBD5E1;
                --ez-gray-400: #94A3B8;
                --ez-gray-500: #64748B;
                --ez-gray-600: #475569;
                --ez-gray-700: #334155;
                --ez-text:     #1E293B;
                --ez-muted:    #64748B;
                --ez-radius:   8px;
                --ez-shadow:   0 1px 3px rgba(15,23,42,0.08), 0 1px 2px rgba(15,23,42,0.04);
                --ez-shadow-md: 0 4px 6px rgba(15,23,42,0.07), 0 2px 4px rgba(15,23,42,0.04);
            }

            /* ==========================================================
               NAVBAR
               ========================================================== */
            .navbar {
                padding: 6px 16px !important;
                margin-bottom: 0 !important;
                min-height: auto !important;
                box-shadow: 0 1px 3px rgba(0,0,0,0.3);
                border-bottom: 1px solid rgba(255,255,255,0.06);
            }
            .navbar .navbar-brand {
                font-size: 15px !important;
                padding: 4px 0 !important;
            }
            .navbar .nav-link {
                font-size: 13px !important;
                font-weight: 500;
                padding: 6px 12px !important;
                color: rgba(255,255,255,0.8) !important;
                border-radius: 6px;
                transition: all 0.15s ease;
            }
            .navbar .nav-link:hover {
                color: #fff !important;
                background: rgba(255,255,255,0.08);
            }
            .navbar .nav-link.active,
            .navbar .nav-item.show > .nav-link {
                color: #fff !important;
                background: rgba(59,130,246,0.25) !important;
                font-weight: 600;
            }
            /* Mode badge in navbar (read-only after selection) */
            .mode-badge {
                display: inline-flex;
                align-items: center;
                gap: 5px;
                padding: 3px 14px;
                font-size: 11px;
                font-weight: 600;
                border-radius: 14px;
                letter-spacing: 0.3px;
            }
            .mode-badge.easy {
                color: #fff;
                background: linear-gradient(135deg, #10B981, #059669);
                border: 1px solid #10B981;
                box-shadow: 0 0 8px rgba(16,185,129,0.35);
            }
            .mode-badge.expert {
                color: #fff;
                background: linear-gradient(135deg, #3B82F6, #2563EB);
                border: 1px solid #3B82F6;
                box-shadow: 0 0 8px rgba(59,130,246,0.35);
            }

            /* ========== WELCOME PAGE ========== */
            .welcome-container {
                max-width: 800px;
                margin: 0 auto;
                padding: 40px 20px;
                text-align: center;
            }
            .welcome-container h2 {
                font-size: 28px;
                font-weight: 700;
                color: var(--ez-text);
                margin-bottom: 8px;
            }
            .welcome-container .subtitle {
                font-size: 15px;
                color: var(--ez-muted);
                margin-bottom: 36px;
            }
            .mode-cards {
                display: flex;
                gap: 24px;
                justify-content: center;
                flex-wrap: wrap;
            }
            .mode-card {
                flex: 1;
                max-width: 340px;
                min-width: 280px;
                border-radius: 12px;
                padding: 32px 24px;
                text-align: center;
                cursor: pointer;
                transition: all 0.25s ease;
                border: 2px solid var(--ez-gray-200);
                background: #fff;
                box-shadow: var(--ez-shadow);
            }
            .mode-card:hover {
                transform: translateY(-4px);
                box-shadow: var(--ez-shadow-md);
            }
            .mode-card.easy-card:hover {
                border-color: #10B981;
                box-shadow: 0 8px 24px rgba(16,185,129,0.18);
            }
            .mode-card.expert-card:hover {
                border-color: #3B82F6;
                box-shadow: 0 8px 24px rgba(59,130,246,0.18);
            }
            .mode-card .card-icon {
                font-size: 40px;
                margin-bottom: 16px;
            }
            .mode-card.easy-card .card-icon { color: #10B981; }
            .mode-card.expert-card .card-icon { color: #3B82F6; }
            .mode-card h4 {
                font-size: 20px;
                font-weight: 700;
                margin-bottom: 8px;
            }
            .mode-card.easy-card h4 { color: #059669; }
            .mode-card.expert-card h4 { color: #2563EB; }
            .mode-card .card-desc {
                font-size: 13px;
                color: var(--ez-muted);
                line-height: 1.5;
                margin-bottom: 20px;
            }
            .mode-card .card-features {
                text-align: left;
                font-size: 12px;
                color: var(--ez-gray-600);
                line-height: 1.8;
                margin-bottom: 20px;
                padding-left: 8px;
            }
            .mode-card .card-features .feat {
                display: flex;
                align-items: baseline;
                gap: 6px;
            }
            .mode-card.easy-card .feat-icon { color: #10B981; }
            .mode-card.expert-card .feat-icon { color: #3B82F6; }
            .mode-card .select-btn {
                display: inline-block;
                padding: 10px 28px;
                border-radius: 8px;
                font-weight: 600;
                font-size: 14px;
                color: #fff;
                border: none;
                cursor: pointer;
                transition: all 0.15s ease;
            }
            .mode-card.easy-card .select-btn {
                background: linear-gradient(135deg, #10B981, #059669);
            }
            .mode-card.easy-card .select-btn:hover {
                background: linear-gradient(135deg, #059669, #047857);
            }
            .mode-card.expert-card .select-btn {
                background: linear-gradient(135deg, #3B82F6, #2563EB);
            }
            .mode-card.expert-card .select-btn:hover {
                background: linear-gradient(135deg, #2563EB, #1D4ED8);
            }
            .welcome-tip {
                margin-top: 28px;
                font-size: 12px;
                color: var(--ez-gray-400);
                font-style: italic;
            }

            .navbar .dropdown-menu {
                background: var(--ez-navy);
                border: 1px solid rgba(255,255,255,0.1);
                border-radius: var(--ez-radius);
                box-shadow: var(--ez-shadow-md);
                padding: 6px;
                margin-top: 4px;
            }
            .navbar .dropdown-item {
                color: rgba(255,255,255,0.85) !important;
                font-size: 12.5px;
                padding: 6px 12px;
                border-radius: 5px;
                transition: all 0.12s ease;
            }
            .navbar .dropdown-item:hover,
            .navbar .dropdown-item:focus {
                background: rgba(59,130,246,0.2) !important;
                color: #fff !important;
            }
            .navbar .dropdown-item.active {
                background: rgba(59,130,246,0.3) !important;
                color: #fff !important;
            }
            /* Dropdown header / separator */
            .navbar .dropdown-header {
                color: var(--ez-gray-400) !important;
                font-size: 11px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                padding: 6px 12px 4px;
            }
            .navbar .dropdown-divider {
                border-color: rgba(255,255,255,0.08);
            }

            /* ==========================================================
               FLATTEN BSLIB GAP SPACING
               ========================================================== */
            :root, body, main, .bslib-page-navbar,
            main.bslib-gap-spacing, .bslib-page-navbar .tab-content {
                --bslib-gap: 0 !important;
                --bslib-page-sidebar-gap: 0 !important;
                --bs-gutter-y: 0 !important;
            }
            body > .bslib-page-navbar,
            .bslib-page-navbar,
            .bslib-page-navbar > *,
            .bslib-page-navbar > main,
            .bslib-page-navbar > main > *,
            .bslib-page-navbar > .container-fluid,
            .bslib-page-navbar > .container-fluid > *,
            .bslib-page-navbar .tab-content,
            .bslib-page-navbar .tab-content > *,
            .bslib-page-navbar .tab-pane,
            main.bslib-gap-spacing,
            main.bslib-gap-spacing > *,
            main.html-fill-container,
            main.html-fill-container > * {
                padding-top: 0 !important;
                margin-top: 0 !important;
                gap: 0 !important;
                row-gap: 0 !important;
            }

            /* ==========================================================
               PAGE BANNER — styled h3 + hr at top of each tab
               ========================================================== */
            .page-banner {
                background: linear-gradient(135deg, var(--ez-gray-50) 0%, #EEF2FF 100%);
                border-left: 4px solid var(--ez-blue);
                padding: 12px 18px;
                margin: 8px 0 10px 0;
                border-radius: 0 var(--ez-radius) var(--ez-radius) 0;
            }
            .page-banner h3 {
                font-size: 16px !important;
                font-weight: 700 !important;
                color: var(--ez-slate) !important;
                margin: 0 0 2px 0 !important;
                padding: 0 !important;
                line-height: 1.3 !important;
            }
            .page-banner p {
                font-size: 12.5px;
                color: var(--ez-gray-500);
                margin: 0;
                line-height: 1.4;
            }
            /* Legacy h3 + hr in panels that haven't been converted yet */
            .tab-pane > h3,
            .tab-pane > div > h3,
            .tab-pane > div > div > h3,
            .tab-pane h3:first-child,
            main h3:first-child {
                font-size: 15px !important;
                margin: 6px 0 2px 0 !important;
                padding: 0 !important;
                color: var(--ez-slate);
                font-weight: 700;
                line-height: 1.2 !important;
            }
            .tab-pane h3 + hr,
            .tab-pane > div > h3 + hr,
            .tab-pane > div > div > h3 + hr {
                margin: 2px 0 6px 0 !important;
                border-top: 2px solid var(--ez-gray-200);
                opacity: 0.6;
            }
            .tab-pane > .row,
            .tab-pane > div > .row {
                --bs-gutter-y: 0 !important;
                margin-top: 0 !important;
            }

            /* ==========================================================
               CARDS — modern styling with colored top accents
               ========================================================== */
            .card, .bslib-card {
                margin-bottom: 8px;
                border: 1px solid var(--ez-gray-200);
                border-radius: var(--ez-radius) !important;
                box-shadow: var(--ez-shadow);
                overflow: hidden;
                transition: box-shadow 0.2s ease;
            }
            .card:hover {
                box-shadow: var(--ez-shadow-md);
            }
            .card-header, .bslib-card .card-header {
                font-weight: 600;
                font-size: 13px;
                color: var(--ez-slate);
                padding: 8px 14px !important;
                border-bottom: 1px solid var(--ez-gray-200);
                background: var(--ez-gray-50) !important;
            }
            .card-header .fa, .card-header i {
                color: var(--ez-blue);
                margin-right: 6px;
            }
            .card-body, .bslib-card .card-body {
                padding: 6px 10px !important;
            }

            /* Card accent variants — applied via wrapper class */
            .card-controls { border-top: 3px solid var(--ez-blue); }
            .card-results  { border-top: 3px solid var(--ez-emerald); }
            .card-aesthetics { border-top: 3px solid var(--ez-amber); }
            .card-guide    { border-top: 3px solid var(--ez-gray-400); }
            .card-upload   { border-top: 3px solid var(--ez-blue); }

            /* ==========================================================
               CARD BODY — form controls, text, spacing
               ========================================================== */
            .card-body h5 {
                font-size: 12.5px;
                margin-top: 2px;
                margin-bottom: 3px;
                font-weight: 700;
                color: var(--ez-slate);
            }
            .card-body h6 {
                font-size: 12px;
                margin-top: 2px;
                margin-bottom: 3px;
                font-weight: 600;
                color: var(--ez-gray-600);
            }
            .card-body .form-group,
            .card-body .shiny-input-container,
            .card-body .form-group.shiny-input-container,
            .card .card-body .form-group,
            .card .card-body .shiny-input-container,
            .bslib-card .card-body .form-group,
            .bslib-card .card-body .shiny-input-container {
                margin-bottom: 2px !important;
                padding-bottom: 0 !important;
            }
            /* selectize wrapper adds extra bottom margin */
            .card-body .selectize-control {
                margin-bottom: 0 !important;
            }
            .card-body .selectize-control + .help-block,
            .card-body .selectize-control + p {
                margin-top: 1px !important;
            }
            .card-body hr {
                margin-top: 4px !important;
                margin-bottom: 4px !important;
                border-top-color: var(--ez-gray-200);
                opacity: 0.5;
            }
            .card-body .control-label,
            .card-body label,
            .card .card-body .control-label,
            .card .card-body label {
                font-size: 11.5px !important;
                margin-bottom: 0 !important;
                padding-bottom: 0 !important;
                color: var(--ez-slate);
                font-weight: 500;
            }
            .card-body .form-control,
            .card-body .selectize-input,
            .card-body input[type='number'],
            .card-body input[type='text'] {
                font-size: 12px !important;
                padding: 2px 8px !important;
                height: auto !important;
                min-height: 26px;
                border-radius: 6px;
                border: 1px solid var(--ez-gray-300);
                transition: border-color 0.15s ease, box-shadow 0.15s ease;
            }
            .card-body .form-control:focus,
            .card-body .selectize-input.focus {
                border-color: var(--ez-blue) !important;
                box-shadow: 0 0 0 3px rgba(59,130,246,0.12) !important;
            }
            .card-body .row {
                margin-left: -6px;
                margin-right: -6px;
                margin-top: 0 !important;
                margin-bottom: 0 !important;
            }
            .card-body .row > [class*='col-'] {
                padding-left: 6px;
                padding-right: 6px;
            }
            .card-body .row > [class*='col-'] > .form-group:last-child,
            .card-body .row > [class*='col-'] > .shiny-input-container:last-child {
                margin-bottom: 3px !important;
            }
            .card-body .help-block,
            .card-body .shiny-html-output,
            .card-body p {
                font-size: 11px;
                line-height: 1.35;
                color: var(--ez-gray-600);
                margin-bottom: 2px;
            }
            .card-body .help-block {
                margin-top: 0 !important;
                margin-bottom: 2px !important;
            }

            /* Section label — small uppercase divider */
            .section-label {
                font-size: 10px;
                font-weight: 700;
                text-transform: uppercase;
                letter-spacing: 0.8px;
                color: var(--ez-gray-400);
                margin-bottom: 6px;
            }

            /* ==========================================================
               BUTTONS
               ========================================================== */
            .card-body .btn {
                font-size: 12px;
                padding: 5px 10px;
                border-radius: 6px;
                font-weight: 600;
                transition: all 0.15s ease;
            }
            .btn-primary {
                background: var(--ez-blue) !important;
                border-color: var(--ez-blue) !important;
                box-shadow: 0 1px 2px rgba(59,130,246,0.3);
            }
            .btn-primary:hover {
                background: #2563EB !important;
                border-color: #2563EB !important;
                box-shadow: 0 2px 4px rgba(59,130,246,0.4);
                transform: translateY(-1px);
            }
            .btn-success {
                background: var(--ez-emerald) !important;
                border-color: var(--ez-emerald) !important;
                box-shadow: 0 1px 2px rgba(16,185,129,0.3);
            }
            .btn-success:hover {
                background: #059669 !important;
                border-color: #059669 !important;
            }
            /* Accent button class */
            .btn-accent {
                background: var(--ez-emerald);
                border-color: var(--ez-emerald);
                color: #fff;
            }
            .btn-accent:hover {
                background: #059669;
                border-color: #059669;
                color: #fff;
            }

            /* ==========================================================
               CHECKBOXES, RADIOS, SLIDERS
               ========================================================== */
            .card-body .checkbox,
            .card-body .form-check,
            .card-body .shiny-input-container.form-group .checkbox {
                margin-top: 0 !important;
                margin-bottom: 2px !important;
                padding-top: 0 !important;
                padding-bottom: 0 !important;
                min-height: 0 !important;
            }
            .card-body .checkbox label,
            .card-body .form-check label {
                padding-top: 0 !important;
                padding-bottom: 0 !important;
                line-height: 1.35;
                font-size: 12.5px;
            }
            .card-body .checkbox + .checkbox,
            .card-body .form-check + .form-check {
                margin-top: 0 !important;
            }
            .card-body .shiny-input-container > .checkbox {
                margin-bottom: 0 !important;
            }
            .card-body .selectize-control { margin-bottom: 0 !important; }
            .card-body .selectize-input {
                padding: 3px 8px !important;
                min-height: 28px !important;
                border-radius: 6px !important;
            }
            .card-body .irs { margin-bottom: 0 !important; }
            .card-body .irs-with-grid { margin-bottom: 2px !important; }
            .card-body h5 + .shiny-input-container,
            .card-body h5 + .form-group {
                margin-top: 0 !important;
            }
            .card-body .btn-success.w-100.mt-4 { margin-top: 14px !important; }

            /* ==========================================================
               WORKFLOW GUIDE — step tags + instruction boxes
               ========================================================== */
            .step-instruction {
                border-left: 3px solid var(--ez-blue);
                padding: 10px 14px;
                margin-bottom: 8px;
                background: var(--ez-gray-50);
                border-radius: 0 6px 6px 0;
                font-size: 12.5px;
                color: var(--ez-slate);
            }
            .guide-step {
                padding: 10px 12px;
                margin-bottom: 8px;
                background: var(--ez-gray-50);
                border-radius: 6px;
                border: 1px solid var(--ez-gray-200);
            }
            .guide-step h6 {
                margin: 4px 0 4px 0;
                font-weight: 600;
                color: var(--ez-slate);
            }
            .guide-step p {
                font-size: 12px;
                color: var(--ez-gray-500);
                margin: 0;
            }
            .step-tag {
                display: inline-block;
                font-size: 9px;
                font-weight: 700;
                text-transform: uppercase;
                letter-spacing: 0.8px;
                background: var(--ez-blue);
                color: #fff;
                padding: 2px 8px;
                border-radius: 4px;
                line-height: 1.5;
            }

            /* Workflow nav buttons (Back / Next) */
            .wg-nav {
                display: flex;
                justify-content: space-between;
                gap: 8px;
                margin-top: 10px;
                padding-top: 10px;
                border-top: 1px solid var(--ez-gray-200);
            }
            .wg-nav .btn {
                font-size: 12px;
                padding: 5px 10px;
                font-weight: 500;
            }
            .wg-nav .btn.disabled, .wg-nav .btn[disabled] {
                opacity: 0.4;
                cursor: not-allowed;
            }

            /* ==========================================================
               STATUS PILL — dot + text indicator
               ========================================================== */
            .status-pill {
                display: inline-flex;
                align-items: center;
                gap: 6px;
                font-size: 12px;
                color: var(--ez-gray-500);
                padding: 4px 10px;
                background: var(--ez-gray-50);
                border: 1px solid var(--ez-gray-200);
                border-radius: 20px;
            }
            .status-pill .dot {
                width: 7px; height: 7px;
                border-radius: 50%;
                background: var(--ez-gray-300);
                display: inline-block;
            }
            .status-pill.active .dot {
                background: var(--ez-emerald);
                box-shadow: 0 0 6px rgba(16,185,129,0.5);
            }

            /* ==========================================================
               TAB PANELS INSIDE CARDS
               ========================================================== */
            .card-body .nav-tabs {
                border-bottom: 2px solid var(--ez-gray-200);
            }
            .card-body .nav-tabs .nav-link {
                font-size: 12.5px;
                padding: 6px 12px;
                color: var(--ez-gray-500);
                font-weight: 500;
                border: none;
                border-bottom: 2px solid transparent;
                margin-bottom: -2px;
                transition: all 0.15s ease;
            }
            .card-body .nav-tabs .nav-link:hover {
                color: var(--ez-blue);
                border-bottom-color: var(--ez-gray-300);
            }
            .card-body .nav-tabs .nav-link.active {
                font-weight: 600;
                color: var(--ez-blue);
                border-bottom-color: var(--ez-blue);
                background: transparent;
            }
            .tab-pane { padding: 6px 0 0 0 !important; }

            /* ==========================================================
               ERROR / VALIDATION MESSAGES
               ========================================================== */
            .shiny-output-error {
                color: #991B1B !important;
                background: #FEF2F2 !important;
                border: 1px solid #FECACA !important;
                border-left: 4px solid var(--ez-rose) !important;
                border-radius: 6px !important;
                padding: 10px 14px !important;
                margin: 8px 0 !important;
                font-family: 'JetBrains Mono', 'Courier New', monospace !important;
                font-size: 12px !important;
                white-space: pre-wrap !important;
                visibility: visible !important;
            }
            .shiny-output-error::before {
                content: 'Error: ';
                font-weight: 700;
                color: #991B1B;
                font-family: 'Inter', sans-serif;
            }
            .shiny-output-error-validation {
                color: #92400E !important;
                background: #FFFBEB !important;
                border: 1px solid #FDE68A !important;
                border-left: 4px solid var(--ez-amber) !important;
                border-radius: 6px !important;
                padding: 10px 14px !important;
                margin: 8px 0 !important;
                font-size: 12px !important;
                visibility: visible !important;
            }
            .shiny-output-error-validation::before {
                content: 'Note: ';
                font-weight: 700;
            }

            /* ==========================================================
               TABLES — unified sizing
               ========================================================== */
            .shiny-html-output table,
            .shiny-html-output .table,
            table.shiny-table {
                font-size: 12.5px !important;
                line-height: 1.35 !important;
                margin-bottom: 6px !important;
                border-collapse: collapse;
                width: auto !important;
            }
            .shiny-html-output table th,
            .shiny-html-output .table th,
            table.shiny-table th {
                background: var(--ez-gray-50) !important;
                color: var(--ez-slate) !important;
                font-weight: 600 !important;
                padding: 6px 12px !important;
                font-size: 12px !important;
                border-bottom: 2px solid var(--ez-gray-200) !important;
                text-transform: uppercase;
                letter-spacing: 0.3px;
            }
            .shiny-html-output table td,
            .shiny-html-output .table td,
            table.shiny-table td {
                padding: 5px 12px !important;
                font-size: 12.5px !important;
                border-bottom: 1px solid var(--ez-gray-100) !important;
            }
            /* DT::dataTableOutput */
            .dataTables_wrapper,
            .dataTables_wrapper .dataTables_length,
            .dataTables_wrapper .dataTables_filter,
            .dataTables_wrapper .dataTables_info,
            .dataTables_wrapper .dataTables_paginate {
                font-size: 12px !important;
            }
            table.dataTable,
            table.dataTable thead th,
            table.dataTable tbody td {
                font-size: 12.5px !important;
                padding: 5px 10px !important;
            }
            table.dataTable thead th {
                background: var(--ez-gray-50);
                color: var(--ez-slate);
                font-weight: 600;
            }
            .dataTables_wrapper { padding: 6px 4px 2px 4px; }

            /* verbatimTextOutput */
            pre, .shiny-text-output {
                font-size: 12px !important;
                line-height: 1.45 !important;
                padding: 10px 12px !important;
                background: var(--ez-gray-50) !important;
                border: 1px solid var(--ez-gray-200) !important;
                border-radius: 6px !important;
                font-family: 'JetBrains Mono', 'Courier New', monospace !important;
            }

            /* Wellpanels */
            .well {
                background: var(--ez-gray-50);
                border: 1px solid var(--ez-gray-200);
                box-shadow: none;
                border-radius: 6px;
            }

            /* ==========================================================
               BRANDING PLACEHOLDER — only in analysis result panes
               ========================================================== */
            .analysis-results-pane .shiny-plot-output:empty::before {
                content: 'Configure parameters and click Run Analysis';
                display: flex;
                align-items: center;
                justify-content: center;
                width: 100%;
                min-height: 120px;
                text-align: center;
                font-size: 13px;
                font-weight: 500;
                color: var(--ez-gray-400);
                letter-spacing: 0.2px;
                border: 2px dashed var(--ez-gray-200);
                border-radius: var(--ez-radius);
                background: var(--ez-gray-50);
            }

            /* ==========================================================
               FOOTER — professional status bar
               ========================================================== */
            .app-footer {
                position: fixed;
                bottom: 0; left: 0; right: 0;
                background: var(--ez-navy);
                color: rgba(255,255,255,0.7);
                padding: 7px 24px;
                font-size: 12px;
                z-index: 1030;
                display: flex;
                justify-content: space-between;
                align-items: center;
                box-shadow: 0 -2px 8px rgba(0,0,0,0.15);
                border-top: 1px solid rgba(255,255,255,0.06);
            }
            .app-footer strong { color: rgba(255,255,255,0.9); }
            .app-footer .fa, .app-footer i { color: var(--ez-blue-lt); margin-right: 4px; }
            .app-footer .status-pill {
                background: rgba(255,255,255,0.06);
                border-color: rgba(255,255,255,0.1);
                color: rgba(255,255,255,0.75);
            }

            /* Prevent content hidden behind fixed footer */
            body {
                padding-bottom: 80px !important;
                margin-bottom: 40px !important;
            }
            .container-fluid, .tab-content {
                padding-bottom: 80px !important;
            }
            .bslib-page-navbar > .container-fluid,
            main.bslib-gap-spacing,
            main.bslib-gap-spacing > div {
                padding-bottom: 80px !important;
            }
            .tab-pane {
                padding-bottom: 40px !important;
            }
            .tab-pane > .container-fluid,
            .tab-pane > div > .container-fluid { padding-top: 0 !important; }

            /* Left/right breathing room on the body content */
            .tab-pane {
                padding-left: 12px !important;
                padding-right: 12px !important;
            }
            .bslib-page-navbar > .container-fluid,
            .bslib-page-navbar > main > .container-fluid {
                padding-left: 18px !important;
                padding-right: 18px !important;
            }

            /* Last card not cut off by footer */
            .card:last-child { margin-bottom: 30px; }
            .tab-pane > .row:last-child,
            .tab-pane > div > .row:last-child {
                margin-bottom: 30px !important;
            }

            /* ==========================================================
               GLOBAL LOADING OVERLAY
               Shown on initial app start (until Shiny is connected) and
               whenever the user picks Easy / Expert mode (until the new
               UI finishes rendering). Prevents repeated clicks and
               surfaces app activity that would otherwise look frozen.
               ========================================================== */
            #ez-loading-overlay {
                position: fixed;
                inset: 0;
                z-index: 99999;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                gap: 18px;
                background: rgba(15, 23, 42, 0.86);
                backdrop-filter: blur(4px);
                -webkit-backdrop-filter: blur(4px);
                color: #F1F5F9;
                font-family: -apple-system, 'Segoe UI', Roboto, sans-serif;
                opacity: 1;
                transition: opacity 0.25s ease-out;
                pointer-events: auto;
            }
            #ez-loading-overlay.ez-hidden {
                opacity: 0;
                pointer-events: none;
            }
            #ez-loading-spinner {
                width: 64px;
                height: 64px;
                border: 5px solid rgba(96, 165, 250, 0.25);
                border-top-color: #60A5FA;
                border-right-color: #93C5FD;
                border-radius: 50%;
                animation: ez-spin 1s linear infinite;
            }
            @keyframes ez-spin {
                to { transform: rotate(360deg); }
            }
            #ez-loading-title {
                font-size: 18px;
                font-weight: 600;
                letter-spacing: 0.3px;
                color: #E0E7FF;
            }
            #ez-loading-subtitle {
                font-size: 13.5px;
                color: #93C5FD;
                max-width: 480px;
                text-align: center;
                line-height: 1.5;
            }
            /* Disable the welcome buttons while overlay is active so a
               second click can't queue a second mode-switch request. */
            body.ez-loading #welcome_easy,
            body.ez-loading #welcome_expert {
                pointer-events: none;
                opacity: 0.65;
            }

        ")),

        # ------------------------------------------------------------------
        # JavaScript: flatten bslib inline gaps
        # ------------------------------------------------------------------
        tags$script(HTML("
            function ezmapFlattenGap() {
                // Remove top gaps injected by bslib
                var sels = [
                    '.bslib-page-navbar',
                    '.bslib-page-navbar > main',
                    '.bslib-page-navbar > .container-fluid',
                    '.bslib-page-navbar .tab-content',
                    '.bslib-page-navbar .tab-content > .tab-pane.active',
                    'main.bslib-gap-spacing',
                    'main.bslib-gap-spacing > div'
                ];
                sels.forEach(function(s) {
                    document.querySelectorAll(s).forEach(function(el) {
                        el.style.setProperty('padding-top', '0', 'important');
                        el.style.setProperty('margin-top',  '0', 'important');
                        el.style.setProperty('gap',         '0', 'important');
                        el.style.setProperty('row-gap',     '0', 'important');
                    });
                });
                // Force bottom padding so footer never overlaps content
                document.querySelectorAll('body, .container-fluid, .tab-content, main').forEach(function(el) {
                    el.style.setProperty('padding-bottom', '80px', 'important');
                });
            }
            $(document).on('shiny:connected', ezmapFlattenGap);
            $(document).on('shiny:sessioninitialized', ezmapFlattenGap);
            $(document).on('shown.bs.tab shown.bs.collapse', ezmapFlattenGap);
            setTimeout(ezmapFlattenGap, 50);
            setTimeout(ezmapFlattenGap, 300);
            setTimeout(ezmapFlattenGap, 1000);
        ")),

        # ------------------------------------------------------------------
        # JavaScript: filter button spinner + color input sync
        # ------------------------------------------------------------------
        tags$script(HTML("
            $(document).on('click', '#filter-applyFilter', function() {
                var $btn = $(this);
                if ($btn.prop('disabled')) return;
                $btn.prop('disabled', true)
                    .data('origHtml', $btn.html())
                    .html('<i class=\"fa fa-spinner fa-spin\"></i> Filtering...');
            });
            $(document).on('shiny:value shiny:error', function(e) {
                if (e.name === 'filter-summaryText') {
                    var $btn = $('#filter-applyFilter');
                    if ($btn.prop('disabled')) {
                        var orig = $btn.data('origHtml');
                        if (orig) $btn.html(orig);
                        $btn.prop('disabled', false);
                    }
                }
            });

            function ezmapSyncColorInput(el) {
                if (!el || !el.id || !window.Shiny || !Shiny.setInputValue) return;
                Shiny.setInputValue(el.id, el.value, {priority: 'event'});
            }
            $(document).on('input change', 'input[type=color]', function() {
                ezmapSyncColorInput(this);
            });
            $(document).on('shiny:connected shiny:sessioninitialized', function() {
                document.querySelectorAll('input[type=color]').forEach(ezmapSyncColorInput);
            });
            $(document).on('shown.bs.tab', function() {
                setTimeout(function() {
                    document.querySelectorAll('input[type=color]').forEach(ezmapSyncColorInput);
                }, 50);
            });
        ")),

        # ------------------------------------------------------------------
        # JavaScript: global loading overlay show/hide hooks
        # ------------------------------------------------------------------
        tags$script(HTML("
            // Inject the overlay node as soon as the DOM is parsed —
            // before Shiny finishes connecting — so it is visible on
            // first paint instead of flashing in late.
            (function injectEzOverlay() {
                if (document.getElementById('ez-loading-overlay')) return;
                var ov = document.createElement('div');
                ov.id = 'ez-loading-overlay';
                ov.innerHTML =
                    '<div id=\"ez-loading-spinner\"></div>' +
                    '<div id=\"ez-loading-title\">Loading EzMAP v2.0 Downstream Analysis...</div>' +
                    '<div id=\"ez-loading-subtitle\">' +
                        'Initializing R packages (phyloseq, vegan, DESeq2, ANCOM-BC, randomForest, igraph). ' +
                        'Typically 5-15 seconds on first launch -- see elapsed counter below.' +
                    '</div>';
                if (document.body) {
                    document.body.appendChild(ov);
                    document.body.classList.add('ez-loading');
                } else {
                    document.addEventListener('DOMContentLoaded', function() {
                        document.body.appendChild(ov);
                        document.body.classList.add('ez-loading');
                    });
                }
            })();

            function ezShowOverlay(title, subtitle) {
                var ov = document.getElementById('ez-loading-overlay');
                if (!ov) return;
                if (title)    document.getElementById('ez-loading-title').textContent    = title;
                if (subtitle) document.getElementById('ez-loading-subtitle').textContent = subtitle;
                ov.classList.remove('ez-hidden');
                document.body.classList.add('ez-loading');
            }
            function ezHideOverlay() {
                var ov = document.getElementById('ez-loading-overlay');
                if (!ov) return;
                ov.classList.add('ez-hidden');
                document.body.classList.remove('ez-loading');
            }

            // Initial page-load progressive subtitles. Fire as soon as
            // the script loads -- if Shiny connects within 5 s the
            // user only sees the first message. Slower machines see
            // the reassuring updates instead of a stale 5-15 s estimate.
            // ezProgressiveSubtitle is hoisted (var) so we can call it
            // here even though it's defined further down.
            setTimeout(function() {
                if (typeof ezProgressiveSubtitle === 'function') {
                    ezProgressiveSubtitle([
                        {at: 5000,
                         sub: 'Still loading R packages -- phyloseq, ' +
                              'DESeq2, and ANCOM-BC are large. Usually ' +
                              'done by 15 s.'},
                        {at: 20000,
                         sub: 'Slower machines or first-ever launch can ' +
                              'take 30-60 s. Watch the elapsed counter ' +
                              '-- if it keeps moving, the app is alive.'},
                        {at: 45000,
                         sub: 'Unusually slow -- if R errored on a ' +
                              'package, check the R console. Otherwise ' +
                              'just keep waiting.'}
                    ]);
                }
            }, 0);

            // Hide the overlay once Shiny is fully connected and the
            // first reactive cycle has flushed (so the welcome page
            // is rendered before we reveal it). We also use this flag
            // to disarm the page-load fallback timer below.
            var ezSessionInitialized = false;
            $(document).on('shiny:sessioninitialized', function() {
                ezSessionInitialized = true;
                if (typeof ezClearProgressive === 'function') ezClearProgressive();
                // Small delay so the welcome cards animate in cleanly.
                setTimeout(ezHideOverlay, 250);
            });
            // Hard fallback -- only fire if Shiny NEVER initialized
            // (e.g. a port-binding failure). Otherwise this 30-second
            // timer would fire mid-computation when a long-running
            // analysis starts shortly after page load and yank the
            // overlay away while the user's network/RF/DESeq2 run is
            // still going.
            setTimeout(function() {
                if (!ezSessionInitialized) ezHideOverlay();
            }, 30000);

            // Re-show the overlay when the user picks a mode. The
            // mode-switch involves rebuilding the navbarPage to drop
            // the welcome tab and reveal the analysis tabs, which
            // takes 1–3 seconds on typical machines.
            // Welcome-mode clicks reuse the same sustained-idle logic
            // defined further down (ezShowUntilIdle is hoisted via var).
            // Each click also schedules progressive subtitles so users
            // on slow machines (Shiny mode-switch occasionally takes
            // 30-60 s) see reassuring updates instead of a stale
            // 'usually 1-3 seconds' message that contradicts reality.
            // Fallback bumped from 15s to 90s so the overlay doesn't
            // force-hide before the actual mode switch finishes.
            function ezModeSwitchStages(modeLabel) {
                return [
                    {at: 0,
                     sub: 'Preparing the analysis tabs with ' + modeLabel +
                          ' controls. Usually 1\\u20133 seconds.'},
                    {at: 5000,
                     sub: 'Still working \\u2014 building 23 analysis modules ' +
                          'and rendering UI components\\u2026'},
                    {at: 15000,
                     sub: 'Slower systems can take 30\\u201360 seconds. ' +
                          'Watch the elapsed counter below \\u2014 ' +
                          'still progressing.'},
                    {at: 30000,
                     sub: 'Almost there \\u2014 finalizing reactive bindings ' +
                          'and theme compilation\\u2026'}
                ];
            }
            $(document).on('click', '#welcome_easy', function() {
                ezShowUntilIdle(
                    'Switching to Easy Mode\\u2026',
                    'Preparing the analysis tabs with simplified controls. ' +
                    'Usually 1\\u20133 seconds.',
                    90000
                );
                ezProgressiveSubtitle(ezModeSwitchStages('simplified'));
            });
            $(document).on('click', '#welcome_expert', function() {
                ezShowUntilIdle(
                    'Switching to Expert Mode\\u2026',
                    'Preparing the analysis tabs with full parameter controls. ' +
                    'Usually 1\\u20133 seconds.',
                    90000
                );
                ezProgressiveSubtitle(ezModeSwitchStages('full parameter'));
            });

            // ===========================================================
            // Heavy-action overlays
            // -----------------------------------------------------------
            // The first three categories below all trigger long-running
            // R work (file parsing → phyloseq build, filtering, model
            // fitting). Without a full-screen overlay the app looks
            // frozen because the per-output spinners only appear once
            // the reactive graph is far enough along to render the
            // target plot/table — uploads and filter runs in particular
            // have several seconds of dead air with no feedback.
            //
            // Pattern:
            //   1. Show overlay on user trigger (click or file change)
            //   2. Hide on the first shiny:idle after the trigger
            //   3. Hard fallback timer in case shiny:idle never fires
            // ===========================================================

            // Hold the overlay open across a chain of busy/idle cycles.
            // Heavy actions (especially file uploads and Run buttons that
            // touch many downstream reactives) often emit several
            // busy → idle pulses before the work is actually done. We
            // keep a counter of pending busy events; the overlay only
            // hides after the page has been idle for `IDLE_HOLD_MS`
            // continuously, *or* the per-action fallback fires.
            var ezBusyCount = 0;
            var ezIdleTimer = null;
            var IDLE_HOLD_MS = 700;

            $(document).on('shiny:busy', function() {
                ezBusyCount++;
                if (ezIdleTimer) { clearTimeout(ezIdleTimer); ezIdleTimer = null; }
            });

            // Try to hide the overlay only if EVERYTHING below is true:
            //   1. Busy counter is 0 (no pending reactive work)
            //   2. No Shiny progress notification visible
            //      (withProgress() blocks always show one — its presence
            //      means R is in the middle of a long computation that
            //      doesn't pulse busy/idle on every iteration)
            //   3. The overlay is currently visible (ez-loading class)
            // Otherwise reschedule the check.
            function ezTryHide() {
                if (!document.body.classList.contains('ez-loading')) return;
                if (ezBusyCount > 0) return;
                if (document.querySelector('.shiny-notification')) {
                    // R is still inside a withProgress block — wait.
                    ezIdleTimer = setTimeout(ezTryHide, IDLE_HOLD_MS);
                    return;
                }
                ezHideOverlay();
            }
            $(document).on('shiny:idle', function() {
                ezBusyCount = Math.max(0, ezBusyCount - 1);
                if (ezBusyCount === 0 && document.body.classList.contains('ez-loading')) {
                    if (ezIdleTimer) clearTimeout(ezIdleTimer);
                    ezIdleTimer = setTimeout(ezTryHide, IDLE_HOLD_MS);
                }
            });

            // Progressive subtitle updater. Pass an array of
            // {at: ms, sub: text} objects; the function rotates through
            // them as elapsed time crosses each threshold. Handle is
            // returned so the caller can cancel it (we cancel on hide
            // via the MutationObserver below). The 'at' value is
            // milliseconds since the call -- 0 means show immediately.
            // Reassures users on slower machines (Shiny mode-switch
            // can take 30-60 s on first connection) without scaring
            // off users on fast machines who'd see only the optimistic
            // first message.
            var ezProgressiveTimers = [];
            function ezClearProgressive() {
                ezProgressiveTimers.forEach(function(t) { clearTimeout(t); });
                ezProgressiveTimers = [];
            }
            function ezProgressiveSubtitle(stages) {
                ezClearProgressive();
                if (!stages || !stages.length) return;
                stages.forEach(function(stage) {
                    if (stage.at === 0) {
                        var sub = document.getElementById('ez-loading-subtitle');
                        if (sub) sub.innerText = stage.sub;
                    } else {
                        var t = setTimeout(function() {
                            // Only update if overlay is still visible AND
                            // the user hasn't manually changed the text.
                            if (!document.body.classList.contains('ez-loading')) return;
                            var sub = document.getElementById('ez-loading-subtitle');
                            if (sub) sub.innerText = stage.sub;
                        }, stage.at);
                        ezProgressiveTimers.push(t);
                    }
                });
            }

            function ezShowUntilIdle(title, subtitle, fallbackMs) {
                ezShowOverlay(title, subtitle);
                // Hard fallback so a stuck reactive can't trap the user
                // forever -- but DON'T fire if Shiny is still actively
                // working (a withProgress notification is still on
                // screen). Reschedule in 30s instead so legitimate long
                // runs (network with 100 bootstraps, RF validation,
                // SparCC on a wide table) don't get the overlay yanked
                // away while they're still computing.
                var ms = fallbackMs || 60000;
                function ezForceHideCheck() {
                    if (document.querySelector('.shiny-notification')) {
                        // Shiny still working -- reschedule check.
                        setTimeout(ezForceHideCheck, 30000);
                        return;
                    }
                    ezBusyCount = 0;
                    ezHideOverlay();
                }
                setTimeout(ezForceHideCheck, ms);
            }

            // ---- File uploads (BIOM / metadata / tree) ----
            $(document).on('change', 'input[type=file]', function(e) {
                var id = (e.target && e.target.id) || '';
                if (id.indexOf('biomFile') < 0 &&
                    id.indexOf('metaFile') < 0 &&
                    id.indexOf('treeFile') < 0) return;
                var fname = (e.target.files && e.target.files[0])
                            ? e.target.files[0].name : 'file';
                var what  = id.indexOf('biomFile') >= 0 ? 'BIOM table'
                          : id.indexOf('metaFile') >= 0 ? 'sample metadata'
                          : 'phylogenetic tree';
                ezShowUntilIdle(
                    'Loading ' + what + '…',
                    'Parsing ' + fname + ' and rebuilding the phyloseq object. ' +
                    'Large BIOM tables can take 10\\u201360 seconds.',
                    180000
                );
            });

            // ---- Heavy action buttons (one entry per Run / Apply) ----
            // Selectors use [id$=\"...\"] so the same handler works for
            // every namespaced module instance (filter-applyFilter,
            // alpha-runAlphaAnalysis, etc.).
            var ezHeavyActions = [
                {sel: '[id$=\"-applyFilter\"]',
                 title: 'Applying filters\\u2026',
                 sub: 'Subsetting samples, taxa, and renormalizing. ' +
                      '10\\u201330 seconds on large datasets.'},
                {sel: '[id$=\"-runAlphaAnalysis\"]',
                 title: 'Computing alpha diversity\\u2026',
                 sub: 'Calculating Shannon, Simpson, Chao1, Faith PD and ' +
                      'pairwise tests.'},
                {sel: '[id$=\"-run_analysis\"]',
                 title: 'Computing beta diversity\\u2026',
                 sub: 'Building distance matrix and ordination ' +
                      '(PCoA / NMDS) plus PERMANOVA.'},
                {sel: '[id$=\"-runRarefaction\"]',
                 title: 'Computing rarefaction curves\\u2026',
                 sub: 'Subsampling at multiple depths. Typically ' +
                      '30\\u201360 seconds.'},
                {sel: '[id$=\"-updatePlot\"]',
                 title: 'Building relative-abundance plot\\u2026',
                 sub: 'Aggregating taxa at the chosen rank.'},
                {sel: '[id$=\"-run_deseq2\"]',
                 title: 'Running DESeq2\\u2026',
                 sub: 'Negative-binomial differential abundance test ' +
                      '(typically 10\\u201360 seconds).'},
                {sel: '[id$=\"-run_ancombc\"]',
                 title: 'Running ANCOM-BC\\u2026',
                 sub: 'Compositional differential abundance with sampling-' +
                      'fraction bias correction.'},
                {sel: '[id$=\"-run_randomforest\"]',
                 title: 'Training Random Forest\\u2026',
                 sub: 'Building 500 trees and ranking features by Gini ' +
                      'importance.'},
                {sel: '[id$=\"-run_validation\"]',
                 title: 'Running expert-grade validation\\u2026',
                 sub: 'Held-out test + repeated CV + bootstrap feature ' +
                      'stability \\u2014 can take several minutes.',
                 fallback: 600000},
                {sel: '[id$=\"-run_network\"]',
                 title: 'Building correlation network\\u2026',
                 sub: 'Computing correlations + bootstrap p-values + FDR. ' +
                      'SparCC with 100 bootstraps takes several minutes.',
                 fallback: 1800000},
                {sel: '[id$=\"-run_comparison\"]',
                 title: 'Running per-group network comparison\\u2026',
                 sub: 'Building one network per level of the chosen ' +
                      'category and comparing centrality.',
                 fallback: 1800000},
                {sel: '[id$=\"-run_lefse\"]',
                 title: 'Running LEfSe\\u2026',
                 sub: 'Kruskal\\u2013Wallis + Wilcoxon + LDA effect-size ' +
                      'computation.'},
                {sel: '[id$=\"-run_bugbase\"]',
                 title: 'Running BugBase\\u2026',
                 sub: 'Predicting phenotypes from 16S OTUs.'},
                {sel: '[id$=\"-run_tax4fun2\"]',
                 title: 'Running Tax4Fun\\u2026',
                 sub: 'Predicting KEGG functions from taxonomy.',
                 fallback: 600000},
                {sel: '[id$=\"-run_funguild\"]',
                 title: 'Running FunGuild\\u2026',
                 sub: 'Matching ITS taxa to FunGuild functional categories.'},
                {sel: '[id$=\"-run_intersect\"]',
                 title: 'Computing overlap\\u2026',
                 sub: 'Joining the two upstream result sets.'}
            ];
            ezHeavyActions.forEach(function(a) {
                $(document).on('click', a.sel, function() {
                    ezShowUntilIdle(a.title, a.sub, a.fallback);
                });
            });

            // ===========================================================
            // Phase checklist for the overlay (network panel only)
            // -----------------------------------------------------------
            // When the user clicks Run Network we know the order of work
            // up front (preprocessing -> observed correlation -> bootstrap
            // permutations -> FDR -> layout). We render that list in the
            // overlay so the user sees ALL the steps and ticks them off
            // as the matching subtitle text comes through. Each phase
            // has a regex that matches the Shiny progress text; first
            // match flips the row to checked.
            // ===========================================================
            // Network phase labels are intentionally generic so the
            // same checklist works for ALL three edge-significance
            // tests (bootstrap CI, permutation+FDR, |r|-only).
            // Each row's regex is broad enough to match every method's
            // wording in setProgress(detail=...) on the R side.
            //   - Phase 3: 'Bootstrap permutation' OR 'Bootstrap resample'
            //   - Phase 4: 'FDR correction' (permutation path) OR
            //              'bootstrap CI' (CI path) OR 'Filtering edges'
            //              (|r|-only path)
            var ezPhases = {
                'network': [
                    {label: 'Preparing input matrix',           re: /Preparing.*input matrix/i},
                    {label: 'Computing observed correlations',  re: /observed.*correlations/i},
                    {label: 'Bootstrap iterations',             re: /Bootstrap (permutation|resample|iteration)/i},
                    {label: 'Significance test & edge filter',  re: /FDR correction|bootstrap CI|Filtering edges/i},
                    {label: 'Computing graph layout',           re: /Computing layout/i}
                ]
            };
            var ezActivePhases = null;     // current phase list for overlay
            var ezPhaseChecked = [];       // per-row done flag

            function ezBuildChecklist(phases) {
                var ov = document.getElementById('ez-loading-overlay');
                if (!ov) return;
                var existing = document.getElementById('ez-loading-checklist');
                if (existing) existing.remove();
                var list = document.createElement('div');
                list.id = 'ez-loading-checklist';
                list.style.cssText =
                    'margin-top:8px;width:380px;max-width:80vw;font-size:13px;' +
                    'color:#CBD5E1;line-height:1.7;';
                var html = '';
                phases.forEach(function(p, i) {
                    html +=
                        '<div class=\"ez-phase\" data-i=\"' + i + '\" ' +
                        'style=\"display:flex;align-items:center;gap:8px;\">' +
                        '<span class=\"ez-phase-icon\" style=\"' +
                        'display:inline-block;width:18px;height:18px;' +
                        'border:2px solid rgba(148,163,184,0.4);border-radius:50%;' +
                        'flex-shrink:0;text-align:center;line-height:14px;' +
                        'color:#94A3B8;\"></span>' +
                        '<span class=\"ez-phase-label\">' + p.label + '</span>' +
                        '</div>';
                });
                list.innerHTML = html;
                ov.appendChild(list);
                ezPhaseChecked = phases.map(function() { return false; });
                ezActivePhases = phases;
            }
            function ezAdvanceChecklist(text) {
                if (!ezActivePhases) return;
                ezActivePhases.forEach(function(p, i) {
                    if (p.re.test(text) && !ezPhaseChecked[i]) {
                        // Mark all earlier rows complete (in case we
                        // skipped a fast phase) and the current row active.
                        for (var j = 0; j < i; j++) {
                            if (!ezPhaseChecked[j]) ezPhaseSetState(j, 'done');
                            ezPhaseChecked[j] = true;
                        }
                        ezPhaseSetState(i, 'active');
                    }
                });
            }
            function ezPhaseSetState(i, state) {
                var row = document.querySelector(
                    '#ez-loading-checklist .ez-phase[data-i=\"' + i + '\"]');
                if (!row) return;
                var icon = row.querySelector('.ez-phase-icon');
                var label = row.querySelector('.ez-phase-label');
                if (state === 'done') {
                    icon.style.background = '#10B981';
                    icon.style.borderColor = '#10B981';
                    icon.style.color = '#FFFFFF';
                    icon.innerHTML = '\\u2713';
                    label.style.color = '#94A3B8';
                    label.style.textDecoration = 'line-through';
                } else if (state === 'active') {
                    icon.style.background = 'transparent';
                    icon.style.borderColor = '#60A5FA';
                    icon.style.borderTopColor = 'transparent';
                    icon.style.animation = 'ez-spin 0.8s linear infinite';
                    icon.innerHTML = '';
                    label.style.color = '#E0E7FF';
                    label.style.fontWeight = '600';
                }
            }
            // When run_network is clicked (matched by the heavy-action
            // selector), build the checklist after the overlay opens.
            $(document).on('click', '[id$=\"-run_network\"], [id$=\"-run_comparison\"]',
              function() {
                setTimeout(function() {
                    ezBuildChecklist(ezPhases.network);
                }, 50);
              });

            // ===========================================================
            // Mirror Shiny's withProgress() notifications into the
            // overlay subtitle. Shiny renders progress as
            // .shiny-notification (with .shiny-notification-message and
            // .shiny-notification-content). When the overlay is showing
            // and a notification is present, copy its text up into the
            // big subtitle so the user sees \"Bootstrap 47 / 100\"
            // instead of a static \"Building network...\". We also lift
            // the progress bar so it's not stuck at the bottom edge.
            // ===========================================================
            (function() {
                var lastSeen = '';
                var ezStartTs = null;          // when the overlay opened
                function pumpProgressIntoOverlay() {
                    if (!document.body.classList.contains('ez-loading')) return;
                    if (ezStartTs === null) ezStartTs = Date.now();

                    // Update elapsed-time line every tick so the user can
                    // tell something is alive even when the message text
                    // doesn't change for a while (e.g. SparCC iterative fit
                    // silently churning through 20 inner iterations).
                    var elapsedSec = Math.floor((Date.now() - ezStartTs) / 1000);
                    var mm = Math.floor(elapsedSec / 60);
                    var ss = elapsedSec % 60;
                    var elapsedStr = (mm > 0 ? mm + 'm ' : '') + ss + 's';
                    var elap = document.getElementById('ez-loading-elapsed');
                    if (!elap) {
                        var ov = document.getElementById('ez-loading-overlay');
                        if (ov) {
                            elap = document.createElement('div');
                            elap.id = 'ez-loading-elapsed';
                            elap.style.cssText =
                                'margin-top:6px;font-size:12px;color:#94A3B8;' +
                                'font-variant-numeric:tabular-nums;';
                            ov.appendChild(elap);
                        }
                    }
                    if (elap) elap.innerText = 'Elapsed: ' + elapsedStr;

                    // Shiny's progress notification has this DOM:
                    //   .shiny-notification
                    //     .shiny-notification-content
                    //       .progress-text
                    //         .progress-message    -- outer message
                    //         .progress-detail     -- incProgress(detail=...)
                    //       .progress
                    //         .progress-bar        -- width = N%
                    // We want message + detail concatenated so the checklist
                    // regex sees the live 'Bootstrap permutation 47/100'
                    // text, not just the static outer message.
                    var notif = document.querySelector('.shiny-notification');
                    if (!notif) return;
                    var msgEl    = notif.querySelector('.progress-message');
                    var detailEl = notif.querySelector('.progress-detail');
                    var msgTxt   = msgEl    ? (msgEl.innerText    || '').trim() : '';
                    var detTxt   = detailEl ? (detailEl.innerText || '').trim() : '';
                    var txt = detTxt ? (msgTxt + ' \\u2014 ' + detTxt) : msgTxt;
                    if (!txt || txt === lastSeen) {
                        // Even when the text hasn't changed, still try to
                        // advance the bar host below (SparCC bootstrap fires
                        // the same detail string on every iteration).
                    } else {
                        lastSeen = txt;
                        var sub = document.getElementById('ez-loading-subtitle');
                        if (sub) sub.innerText = txt;
                        // Drive the per-step checklist (network panel only).
                        ezAdvanceChecklist(txt);
                    }

                    // Surface the inner Shiny progress bar (if any) inside
                    // the overlay so the user gets a real progress meter.
                    var bar = notif.querySelector('.progress .progress-bar');
                    var ovBarHost = document.getElementById('ez-loading-bar-host');
                    if (bar) {
                        if (!ovBarHost) {
                            ovBarHost = document.createElement('div');
                            ovBarHost.id = 'ez-loading-bar-host';
                            ovBarHost.style.cssText =
                                'width:360px;max-width:80vw;height:8px;' +
                                'background:rgba(96,165,250,0.18);' +
                                'border-radius:6px;overflow:hidden;margin-top:6px;';
                            ovBarHost.innerHTML =
                                '<div id=\"ez-loading-bar\" style=\"' +
                                'height:100%;width:0%;background:linear-gradient(' +
                                '90deg,#60A5FA,#3B82F6);transition:width 0.25s ease;' +
                                '\"></div>';
                            document.getElementById('ez-loading-overlay')
                                .appendChild(ovBarHost);
                        }
                        var pct = bar.style.width || bar.getAttribute('aria-valuenow');
                        if (pct) {
                            var bar2 = document.getElementById('ez-loading-bar');
                            if (bar2) bar2.style.width = pct.endsWith('%') ? pct : (pct + '%');
                        }
                    }
                }
                // Poll twice per second whenever overlay is up. Cheap.
                setInterval(pumpProgressIntoOverlay, 500);

                // When overlay hides, reset the cached text so the next
                // run starts fresh.
                var ov = document.getElementById('ez-loading-overlay');
                if (ov) {
                    new MutationObserver(function() {
                        if (ov.classList.contains('ez-hidden')) {
                            lastSeen = '';
                            // Cancel pending progressive subtitle updates
                            // so a stale message from this run doesn't
                            // overwrite the next run's initial message.
                            if (typeof ezClearProgressive === 'function') {
                                ezClearProgressive();
                            }
                            var host = document.getElementById('ez-loading-bar-host');
                            if (host) host.remove();
                            // Mark all remaining checklist rows complete
                            // before tearing it down -- gives a satisfying
                            // \"all-done\" tick before the overlay fades.
                            if (ezActivePhases) {
                                ezActivePhases.forEach(function(_, i) {
                                    if (!ezPhaseChecked[i]) {
                                        ezPhaseSetState(i, 'done');
                                        ezPhaseChecked[i] = true;
                                    }
                                });
                            }
                            setTimeout(function() {
                                var cl = document.getElementById('ez-loading-checklist');
                                if (cl) cl.remove();
                                var el = document.getElementById('ez-loading-elapsed');
                                if (el) el.remove();
                                ezStartTs = null;
                                ezActivePhases = null;
                                ezPhaseChecked = [];
                            }, 400);
                        }
                    }).observe(ov, {attributes: true, attributeFilter: ['class']});
                }
            })();
        "))
    ),

    # ==================================================================
    # TAB: Welcome — Mode Selection (shown first, hidden after choice)
    # ==================================================================
    tabPanel("Welcome", icon = icon("home"), value = "tab_welcome",
        # Hidden radio that conditionalPanel() reads from — set by server on welcome choice
        div(style = "display:none;",
            radioButtons("analysis_mode", label = NULL,
                         choices = c("Easy" = "easy", "Expert" = "expert"),
                         selected = "easy", inline = TRUE)
        ),
        div(class = "welcome-container",
            tags$img(src = "ezmap_icon.png", height = "64px",
                     style = "margin-bottom:16px; opacity:0.9;"),
            h2("Welcome to EzMAP v2.0 — Downstream Analysis"),
            p(class = "subtitle",
              "Interactive statistical analysis and visualization of QIIME 2 outputs."),
            div(style = "max-width:760px; margin:8px auto 22px auto; text-align:left; font-size:14px; color:#475569; line-height:1.55;",
                tags$p(
                    "This is the ", tags$b("downstream"), " module of EzMAP v2.0 — an ",
                    tags$b("R Shiny application"), " that consumes the BIOM table, sample metadata, and ",
                    "(optional) phylogenetic tree produced by the upstream Java + QIIME 2 pipeline ",
                    "(or any compatible QIIME 2 / DADA2 output) and turns them into publication-ready ",
                    "diversity, differential-abundance, classification, network, and functional-prediction analyses ",
                    "without writing any R code."
                ),
                tags$p(
                    "Built on top of ", tags$b("phyloseq"), ", ", tags$b("vegan"), ", ", tags$b("DESeq2"), ", ",
                    tags$b("ANCOM-BC"), ", ", tags$b("randomForest"), ", ", tags$b("microbiome"), ", and ",
                    tags$b("igraph"), ", every panel exposes Easy-mode defaults from peer-reviewed methodology ",
                    "alongside Expert-mode controls for full reproducibility. Choose a mode below to begin."
                )
            ),

            div(class = "mode-cards",
                # --- Easy Mode Card ---
                div(class = "mode-card easy-card",
                    div(class = "card-icon", icon("leaf")),
                    h4("Easy Mode"),
                    p(class = "card-desc",
                      "Recommended for most users. Sensible defaults are applied automatically — just upload your data and click Run."),
                    div(class = "card-features",
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Pre-set thresholds for all analyses"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "One-click DESeq2, Alpha/Beta diversity"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Guided step-by-step workflow"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Clean, distraction-free interface")
                    ),
                    actionButton("welcome_easy", "Start Easy Mode",
                                 class = "select-btn")
                ),
                # --- Expert Mode Card ---
                div(class = "mode-card expert-card",
                    div(class = "card-icon", icon("sliders-h")),
                    h4("Expert Mode"),
                    p(class = "card-desc",
                      "Full control over every parameter. Customize cutoffs, plot aesthetics, and statistical thresholds."),
                    div(class = "card-features",
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Custom p-value & fold-change cutoffs"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Volcano plot color & label controls"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Advanced filtering parameters"),
                        div(class = "feat", span(class = "feat-icon", icon("check")), "Full statistical output access")
                    ),
                    actionButton("welcome_expert", "Start Expert Mode",
                                 class = "select-btn")
                )
            ),
            p(class = "welcome-tip",
              icon("info-circle"),
              " This choice is locked for the session to prevent rendering issues. Restart the app to switch modes.")
        )
    ),

    # ==================================================================
    # TAB: Data Upload
    # ==================================================================
    tabPanel("Data Upload", icon = icon("upload"), value = "tab_data",
        div(class = "page-banner",
            h3("Data Upload & Phyloseq Construction"),
            p("Upload BIOM, sample metadata, and phylogenetic tree to build your phyloseq object.")),
        fluidRow(
            column(9,
                dataUploadUI("dataUpload")
            ),
            column(3,
                div(class = "card-guide",
                    bslib::card(
                        bslib::card_header(icon("compass"), "Workflow Guide"),
                        uiOutput("render_instructions")
                    )
                )
            )
        )
    ),

    # ==================================================================
    # TAB: Filtering
    # ==================================================================
    tabPanel("Filtering", icon = icon("filter"), value = "tab_filter",
        filterUI("filter",
            guide = uiOutput("render_instructions_filtering"))
    ),

    # ==================================================================
    # TAB: Relative Abundance
    # ==================================================================
    tabPanel("Relative Abundance", icon = icon("chart-bar"), value = "tab_ra",
        raPlotUI("raPlot",
            guide = uiOutput("render_instructions_ra"))
    ),

    # ==================================================================
    # DROPDOWN: Diversity
    # ==================================================================
    navbarMenu("Diversity", icon = icon("calculator"),
        tabPanel("Rarefaction", icon = icon("random"), value = "tab_rarefaction",
            rarefactionUI("rarefaction_panel",
                guide = uiOutput("render_instructions_rarefaction"))
        ),
        tabPanel("Alpha Diversity", icon = icon("calculator"), value = "tab_alpha",
            alphaDiversityUI("alphaDiv",
                guide = uiOutput("render_instructions_alpha"))
        ),
        tabPanel("Beta Diversity", icon = icon("dna"), value = "tab_beta",
            betaDiversityUI("beta_analysis_id",
                guide = uiOutput("render_instructions_beta"))
        )
    ),

    # ==================================================================
    # DROPDOWN: Differential Abundance
    # ==================================================================
    navbarMenu("Differential Abundance", icon = icon("balance-scale"),
        tabPanel("LEfSe", icon = icon("balance-scale"), value = "tab_lefse",
            lefseUI("lefse_panel",
                guide = uiOutput("render_instructions_lefse"))
        ),
        tabPanel("DESeq2", icon = icon("superscript"), value = "tab_deseq2",
            deseq2UI("deseq2",
                guide = uiOutput("render_instructions_deseq2"))
        ),
        tabPanel("ANCOM-BC", icon = icon("microscope"), value = "tab_ancombc",
            ancombcUI("ancombc_panel",
                guide = uiOutput("render_instructions_ancombc"))
        ),
        tabPanel("Random Forest", icon = icon("tree"), value = "tab_rf",
            randomForestUI("random_forest_panel",
                guide = uiOutput("render_instructions_rf"))
        ),
        tabPanel("DESeq2 + RF (Combined)", icon = icon("code-branch"), value = "tab_deseq2rf",
            deseq2rfUI("deseq2rf_panel",
                guide = uiOutput("render_instructions_deseq2rf"))
        ),
        tabPanel("ANCOM-BC + RF (Combined)", icon = icon("code-branch"), value = "tab_ancombcrf",
            ancombcrfUI("ancombcrf_panel",
                guide = uiOutput("render_instructions_ancombcrf"))
        )
    ),

    # ==================================================================
    # DROPDOWN: Functional Analysis
    # ==================================================================
    navbarMenu("Functional Analysis", icon = icon("puzzle-piece"),
        tabPanel("Tax4Fun", icon = icon("puzzle-piece"), value = "tab_tax4fun2",
            tax4fun2UI("tax4fun2_panel",
                guide = uiOutput("render_instructions_tax4fun2"))
        ),
        tabPanel("FunGuild", icon = icon("leaf"), value = "tab_funguild",
            funguildUI("funguild_panel",
                guide = uiOutput("render_instructions_funguild"))
        ),
        tabPanel("BugBase", icon = icon("bacterium"), value = "tab_bugbase",
            bugbaseUI("bugbase_panel",
                guide = uiOutput("render_instructions_bugbase"))
        )
    ),

    # ==================================================================
    # TAB: Network Analysis
    # ==================================================================
    tabPanel("Network", icon = icon("project-diagram"), value = "tab_network",
        networkUI("network_panel",
            guide = uiOutput("render_instructions_network"))
    ),

    # ==================================================================
    # DROPDOWN: Help
    # ==================================================================
    navbarMenu("Help", icon = icon("question-circle"),
        tabPanel("About", icon = icon("info-circle"), value = "tab_about",
            div(class = "page-banner",
                h3("About EzMAP v2.0"),
                p("Easy Microbiome Analysis Pipeline — Version 2.0")),
            fluidRow(
                column(8, offset = 2,
                    bslib::card(class = "card-results",
                        bslib::card_header(icon("flask"), "Overview & Usage"),
                        div(style = "padding: 16px;",
                            tags$p("EzMAP v2.0 is an interactive Shiny-based web application for ",
                                   "16S rRNA and ITS amplicon sequencing data analysis. It provides a complete ",
                                   "Easy Microbiome Analysis Pipeline from data upload through diversity analysis, ",
                                   "differential abundance testing, functional prediction, and network analysis."),
                            tags$h5(style = "color:var(--ez-slate); border-bottom:2px solid var(--ez-blue); padding-bottom:6px; margin-top:16px;",
                                    "How to Use"),
                            tags$ol(style = "font-size:12.5px; line-height:1.8;",
                                tags$li(tags$b("Data Upload:"), " Upload your BIOM file (feature-table.biom), ",
                                        "sample metadata (.tsv), and phylogenetic tree (.nwk). Select whether your ",
                                        "data is Bacteria (16S) or Fungi (ITS)."),
                                tags$li(tags$b("Filtering:"), " Remove non-microbial taxa (chloroplasts, mitochondria), ",
                                        "strip QIIME2 prefixes, set prevalence/abundance thresholds."),
                                tags$li(tags$b("Relative Abundance:"), " Visualise taxonomic composition with stacked ",
                                        "bar plots at any rank (Phylum to Species)."),
                                tags$li(tags$b("Diversity:"), " Alpha diversity (Shannon, Chao1, Simpson with ",
                                        "rarefaction) and Beta diversity (PCoA with PERMANOVA)."),
                                tags$li(tags$b("Differential Abundance:"), " LEfSe, DESeq2, ANCOM-BC, Random Forest, ",
                                        "and combined DESeq2 + RF intersection."),
                                tags$li(tags$b("Functional Analysis:"), " Predict KEGG pathways (Tax4Fun), fungal guilds ",
                                        "(FunGuild), or organism-level phenotypes (BugBase)."),
                                tags$li(tags$b("Network:"), " Build co-occurrence networks with correlation-based ",
                                        "or SPIEC-EASI methods.")
                            ),
                            tags$h5(style = "color:var(--ez-slate); border-bottom:2px solid var(--ez-blue); padding-bottom:6px; margin-top:16px;",
                                    "Core Packages"),
                            div(style = "overflow-x:auto;",
                                tags$table(class = "table table-sm", style = "font-size:12px;",
                                    tags$thead(tags$tr(
                                        tags$th("Package"), tags$th("Purpose"), tags$th("Reference")
                                    )),
                                    tags$tbody(
                                        tags$tr(tags$td("phyloseq"), tags$td("Core microbiome data handling"), tags$td("McMurdie & Holmes (2013)")),
                                        tags$tr(tags$td("vegan"), tags$td("Diversity indices, PERMANOVA, ordination"), tags$td("Oksanen et al.")),
                                        tags$tr(tags$td("DESeq2"), tags$td("Differential abundance testing"), tags$td("Love et al. (2014)")),
                                        tags$tr(tags$td("ANCOMBC"), tags$td("Bias-corrected differential abundance"), tags$td("Lin & Peddada (2020)")),
                                        tags$tr(tags$td("randomForest"), tags$td("Feature importance ranking"), tags$td("Liaw & Wiener (2002)")),
                                        tags$tr(tags$td("Tax4Fun2"), tags$td("KEGG pathway prediction"), tags$td("Wemheuer et al. (2020)")),
                                        tags$tr(tags$td("FunGuild"), tags$td("Fungal guild assignment"), tags$td("Nguyen et al. (2016)")),
                                        tags$tr(tags$td("SpiecEasi"), tags$td("Sparse network estimation"), tags$td("Kurtz et al. (2015)")),
                                        tags$tr(tags$td("ggplot2"), tags$td("Publication-quality visualisations"), tags$td("Wickham (2016)")),
                                        tags$tr(tags$td("shiny / bslib"), tags$td("Interactive web framework"), tags$td("Chang et al."))
                                    )
                                )
                            ),
                            div(style = "text-align:center; margin-top:20px; padding-top:12px; border-top:1px solid var(--ez-gray-200);",
                                tags$p(style = "color:var(--ez-gray-400); font-size:11px; margin:0;",
                                       "Easy Microbiome Analysis Pipeline | Developed for reproducible microbiome research")
                            )
                        )
                    )
                )
            )
        ),
        tabPanel("Parameters Guide", icon = icon("cogs"), value = "tab_params",
            div(class = "page-banner",
                h3("Module Parameters Reference"),
                p("Default values for Easy and Expert modes across every analysis module. ",
                  "In Easy mode, sensible defaults are applied automatically. ",
                  "To customize, restart the app and select Expert mode.")),
            fluidRow(
                column(10, offset = 1,
                    bslib::card(class = "card-results",
                        bslib::card_header(icon("cogs"), "Parameters by Module"),
                        div(style = "padding: 16px;",

                            # ---- Consistent table style ----
                            tags$style(HTML("
                                .param-table { width:100%; border-collapse:collapse; font-size:12.5px; table-layout:fixed; }
                                .param-table th, .param-table td { padding:7px 12px; text-align:left; vertical-align:top; border-bottom:1px solid #E2E8F0; }
                                .param-table thead th { background:#F8FAFC; font-weight:600; color:#334155; border-bottom:2px solid #CBD5E1; }
                                .param-table tbody tr:hover { background:#F1F5F9; }
                                .param-table td:nth-child(1) { width:24%; font-weight:500; color:#1E293B; }
                                .param-table td:nth-child(2) { width:18%; font-family:'SF Mono',SFMono-Regular,Consolas,monospace; font-size:11.5px; color:#10B981; }
                                .param-table td:nth-child(3) { width:18%; font-family:'SF Mono',SFMono-Regular,Consolas,monospace; font-size:11.5px; color:#3B82F6; }
                                .param-table td:nth-child(4) { width:40%; color:#64748B; }
                                .param-section { color:var(--ez-slate); border-bottom:2px solid var(--ez-blue); padding-bottom:6px; margin-top:20px; margin-bottom:8px; }
                                .param-section:first-child { margin-top:0; }
                                .mode-badge-easy { display:inline-block; background:#D1FAE5; color:#065F46; padding:1px 8px; border-radius:10px; font-size:10px; font-weight:600; }
                                .mode-badge-expert { display:inline-block; background:#DBEAFE; color:#1E40AF; padding:1px 8px; border-radius:10px; font-size:10px; font-weight:600; }
                            ")),

                            # ---- Mode legend ----
                            div(style = "margin-bottom:14px; padding:10px 14px; background:#F8FAFC; border-radius:8px; border:1px solid #E2E8F0;",
                                tags$span(class = "mode-badge-easy", "EASY"),
                                tags$span(style = "margin:0 4px; color:#94A3B8;", "\u2014"),
                                tags$span(style = "font-size:12px; color:#64748B;", "Visible with sensible defaults; no user action needed"),
                                tags$span(style = "margin:0 12px; color:#CBD5E1;", "|"),
                                tags$span(class = "mode-badge-expert", "EXPERT"),
                                tags$span(style = "margin:0 4px; color:#94A3B8;", "\u2014"),
                                tags$span(style = "font-size:12px; color:#64748B;", "Unlocked in Expert mode for full control"),
                                tags$span(style = "margin:0 12px; color:#CBD5E1;", "|"),
                                tags$span(style = "font-size:12px; color:#94A3B8;", "Hidden = parameter not shown in that mode")
                            ),

                            # ===== FILTERING =====
                            tags$h5(class = "param-section", "Filtering Parameters"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td("Sample subsetting"),     tags$td("Hidden"),         tags$td("None (selectable)"),  tags$td("Subset samples by metadata group before filtering")),
                                    tags$tr(tags$td("Remove Chloroplast"),    tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),       tags$td("Removes Order = 'Chloroplast'")),
                                    tags$tr(tags$td("Remove Mitochondria"),   tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),       tags$td("Removes Family = 'Mitochondria'")),
                                    tags$tr(tags$td("Remove Eukaryota"),      tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),       tags$td("Removes Kingdom = 'Eukaryota'")),
                                    tags$tr(tags$td("Remove Archaea"),        tags$td("Hidden"),         tags$td("No (toggle)"),        tags$td("Removes Kingdom = 'Archaea'")),
                                    tags$tr(tags$td("Strip taxonomy prefix"), tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),       tags$td("Removes D_x__ and k__/p__/c__/o__/f__/g__/s__ prefixes")),
                                    tags$tr(tags$td("Min reads per ASV"),     tags$td("3 (locked)"),     tags$td("3 (adjustable)"),     tags$td("ASVs with fewer total reads removed")),
                                    tags$tr(tags$td("Min % samples"),         tags$td("20% (locked)"),   tags$td("20% (adjustable)"),   tags$td("ASV must appear in this fraction of samples")),
                                    tags$tr(tags$td("Normalisation"),         tags$td("Off (locked)"),   tags$td("Off (toggle)"),       tags$td("Normalize to Median Sequencing Depth (on/off)"))
                                )
                            ),

                            # ===== ALPHA DIVERSITY =====
                            tags$h5(class = "param-section", "Alpha Diversity"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td("Rarefaction depth"),     tags$td("Auto (locked)"),      tags$td("Auto (adjustable)"),    tags$td("Subsampling depth; auto uses minimum sample depth")),
                                    tags$tr(tags$td("Normalisation"),         tags$td("Rarefaction"),        tags$td("Rarefaction"),          tags$td("Even subsampling; no additional normalisation applied")),
                                    tags$tr(tags$td("Diversity metric"),      tags$td("Shannon (locked)"),   tags$td("Shannon (selectable)"), tags$td("Also: Observed, Chao1, ACE, Simpson, InvSimpson")),
                                    tags$tr(tags$td("Statistical test"),      tags$td("Auto"),               tags$td("Auto"),                 tags$td("ANOVA (normal) or Kruskal-Wallis (non-normal)")),
                                    tags$tr(tags$td("Post-hoc test"),         tags$td("Auto"),               tags$td("Auto"),                 tags$td("Tukey HSD (ANOVA) or Dunn with Bonferroni (KW)")),
                                    tags$tr(tags$td("Comparison mode"),       tags$td("All pairwise"),       tags$td("Manual select"),        tags$td("Select specific group pairs or all pairwise")),
                                    tags$tr(tags$td("Significance cutoff"),   tags$td("0.05 (locked)"),      tags$td("0.05 (adjustable)"),    tags$td("Alpha threshold for bracket display")),
                                    tags$tr(tags$td("Plot customisation"),    tags$td("Hidden"),             tags$td("Full control"),         tags$td("Font size, axis labels, jitter, boxplot width, legend position"))
                                )
                            ),

                            # ===== BETA DIVERSITY =====
                            tags$h5(class = "param-section", "Beta Diversity"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td("Normalisation"),          tags$td("CSS"),                tags$td("CSS"),                  tags$td("Cumulative sum scaling via metagenomeSeq")),
                                    tags$tr(tags$td("Distance method"),       tags$td("Bray-Curtis"),        tags$td("Bray-Curtis (selectable)"), tags$td("Also: Jaccard, UniFrac, Weighted UniFrac")),
                                    tags$tr(tags$td("Ordination"),            tags$td("PCoA"),               tags$td("PCoA"),                 tags$td("Principal Coordinates Analysis")),
                                    tags$tr(tags$td("PERMANOVA"),             tags$td("adonis2 (auto)"),     tags$td("adonis2 (auto)"),       tags$td("Tests group centroid differences")),
                                    tags$tr(tags$td("Permutations"),          tags$td("999 (locked)"),       tags$td("999 (adjustable)"),     tags$td("Number of permutations for PERMANOVA")),
                                    tags$tr(tags$td("Ellipse style"),         tags$td("95% CI (locked)"),    tags$td("95% CI (adjustable)"),  tags$td("Confidence ellipses around group centroids")),
                                    tags$tr(tags$td("Plot customisation"),    tags$td("Hidden"),             tags$td("Full control"),         tags$td("Point size, label toggle, font size, legend position"))
                                )
                            ),

                            # ===== RELATIVE ABUNDANCE =====
                            tags$h5(class = "param-section", "Relative Abundance"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td("Normalisation"),          tags$td("TSS"),                tags$td("TSS"),                  tags$td("Total sum scaling (relative proportions); sums to 1 per sample")),
                                    tags$tr(tags$td("Taxonomy level"),         tags$td("Phylum (selectable)"), tags$td("Phylum (selectable)"), tags$td("Also: Kingdom, Class, Order, Family, Genus, Species")),
                                    tags$tr(tags$td("Top N taxa"),             tags$td("10 (locked)"),        tags$td("10 (adjustable)"),      tags$td("Most abundant taxa shown; rest grouped as 'Other'")),
                                    tags$tr(tags$td("Plot type"),              tags$td("Stacked bar"),        tags$td("Stacked bar"),          tags$td("Stacked bar chart of relative proportions")),
                                    tags$tr(tags$td("Plot customisation"),     tags$td("Hidden"),             tags$td("Full control"),         tags$td("Font size, palette, legend position, bar width"))
                                )
                            ),

                            # ===== DIFFERENTIAL ABUNDANCE =====
                            tags$h5(class = "param-section", "Differential Abundance"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td(tags$b("LEfSe")),            tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("LDA score cutoff"),         tags$td("2.0 (locked)"),   tags$td("2.0 (adjustable)"),     tags$td("Minimum effect size to report a feature")),
                                    tags$tr(tags$td("Significance threshold"),   tags$td("p < 0.05 (locked)"), tags$td("p < 0.05 (adjustable)"), tags$td("Kruskal-Wallis test for initial screening")),
                                    tags$tr(tags$td("Taxonomy level"),           tags$td("Genus (selectable)"), tags$td("Genus (selectable)"), tags$td("Rank at which features are aggregated")),

                                    tags$tr(tags$td(tags$b("DESeq2")),           tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Normalisation"),            tags$td("DESeq2 internal"), tags$td("DESeq2 internal"),     tags$td("Median-of-ratios (size factors); handles library size")),
                                    tags$tr(tags$td("Adjusted p-value"),         tags$td("< 0.05 (locked)"), tags$td("< 0.05 (adjustable)"), tags$td("Benjamini-Hochberg FDR correction")),
                                    tags$tr(tags$td("Log2 fold-change"),         tags$td("|log2FC| > 1 (locked)"), tags$td("|log2FC| > 1 (adjustable)"), tags$td("Minimum effect size for significance")),
                                    tags$tr(tags$td("Test type"),                tags$td("Wald"),           tags$td("Wald"),                 tags$td("Wald test for pairwise group comparison")),
                                    tags$tr(tags$td("Taxonomy level"),           tags$td("Genus (selectable)"), tags$td("Genus (selectable)"), tags$td("Rank at which counts are aggregated")),

                                    tags$tr(tags$td(tags$b("ANCOM-BC")),         tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Normalisation"),            tags$td("ANCOM-BC internal"), tags$td("ANCOM-BC internal"), tags$td("Sampling fraction bias correction; log-linear model")),
                                    tags$tr(tags$td("P-value correction"),       tags$td("FDR"),            tags$td("FDR"),                  tags$td("Benjamini-Hochberg false discovery rate")),
                                    tags$tr(tags$td("Significance threshold"),   tags$td("p < 0.05 (locked)"), tags$td("p < 0.05 (adjustable)"), tags$td("Adjusted p-value cutoff")),
                                    tags$tr(tags$td("Structural zero detect"),   tags$td("Yes"),            tags$td("Yes (toggle)"),         tags$td("Handles zeros via bias correction")),

                                    tags$tr(tags$td(tags$b("Random Forest")),    tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Number of trees"),          tags$td("500 (locked)"),   tags$td("500 (adjustable)"),     tags$td("Trees in the random forest ensemble")),
                                    tags$tr(tags$td("Top features shown"),       tags$td("20 (locked)"),    tags$td("20 (adjustable)"),      tags$td("Features ranked by Gini importance")),
                                    tags$tr(tags$td("Importance metric"),        tags$td("Mean Decrease Gini"), tags$td("Mean Decrease Gini"), tags$td("Variable importance measure"))
                                )
                            ),

                            # ===== FUNCTIONAL PREDICTION =====
                            tags$h5(class = "param-section", "Functional Prediction"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td(tags$b("Tax4Fun")),           tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Reference database"),       tags$td("SILVA-KO"),       tags$td("SILVA-KO"),             tags$td("SILVA taxonomy to KEGG orthology mapping")),
                                    tags$tr(tags$td("Prediction type"),          tags$td("UProC"),          tags$td("UProC"),                tags$td("Ultra-fast protein classification")),
                                    tags$tr(tags$td("Copy-number normalise"),    tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),         tags$td("Corrects for 16S rRNA gene copy number variation")),
                                    tags$tr(tags$td("Sample normalise"),         tags$td("Yes (locked)"),   tags$td("Yes (toggle)"),         tags$td("TSS normalisation to relative abundances per sample")),
                                    tags$tr(tags$td("Aggregation level"),        tags$td("KO (locked)"),    tags$td("KO (selectable)"),      tags$td("Also: KEGG Pathway")),
                                    tags$tr(tags$td("Top functions shown"),      tags$td("50 (locked)"),    tags$td("50 (adjustable)"),      tags$td("Top N by variance for heatmap display")),
                                    tags$tr(tags$td("Row scaling"),              tags$td("Z-score"),        tags$td("Z-score"),              tags$td("Row-wise z-score scaling for heatmap")),

                                    tags$tr(tags$td(tags$b("FunGuild")),          tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Taxonomy level"),           tags$td("Genus (locked)"), tags$td("Genus (selectable)"),   tags$td("Rank used for FunGuild database matching")),
                                    tags$tr(tags$td("Trophic modes"),            tags$td("All (locked)"),   tags$td("All (selectable)"),     tags$td("Saprotroph, Pathotroph, Symbiotroph")),
                                    tags$tr(tags$td("Confidence filter"),        tags$td("Probable+"),      tags$td("Probable+ (selectable)"), tags$td("Minimum confidence: Possible, Probable, Highly Probable")),
                                    tags$tr(tags$td("Statistical test"),         tags$td("Kruskal-Wallis"), tags$td("Kruskal-Wallis"),       tags$td("Non-parametric group comparison")),

                                    tags$tr(tags$td(tags$b("BugBase")),           tags$td(""),               tags$td(""),                     tags$td("")),
                                    tags$tr(tags$td("Phenotypes"),               tags$td("6 of 9 (locked)"), tags$td("6 of 9 (selectable)"), tags$td("Gram+/\u2212, aerobic, anaerobic, biofilm, pathogenic")),
                                    tags$tr(tags$td("Min trait coverage"),       tags$td("10% (locked)"),   tags$td("10% (adjustable)"),     tags$td("Minimum fraction of taxa with trait annotations")),
                                    tags$tr(tags$td("Plot type"),                tags$td("Boxplot (locked)"), tags$td("Boxplot (selectable)"), tags$td("Also: Bar plot, Heatmap")),
                                    tags$tr(tags$td("Legend position"),          tags$td("Bottom (locked)"), tags$td("Bottom (selectable)"), tags$td("Bottom, Top, Right, Left, None"))
                                )
                            ),

                            # ===== NETWORK ANALYSIS =====
                            tags$h5(class = "param-section", "Network Analysis"),
                            tags$table(class = "param-table",
                                tags$thead(tags$tr(tags$th("Parameter"), tags$th("Easy Mode"), tags$th("Expert Mode"), tags$th("Description"))),
                                tags$tbody(
                                    tags$tr(tags$td("Normalisation"),              tags$td("Median depth"),      tags$td("Median depth"),             tags$td("Median sequencing depth normalisation before correlation")),
                                    tags$tr(tags$td("Correlation method"),        tags$td("Spearman (locked)"), tags$td("Spearman (selectable)"),    tags$td("Also: Pearson, SparCC (compositional)")),
                                    tags$tr(tags$td("Correlation threshold"),     tags$td("r > 0.6 (locked)"),  tags$td("r > 0.6 (adjustable)"),    tags$td("Minimum absolute correlation to draw an edge")),
                                    tags$tr(tags$td("P-value cutoff"),            tags$td("< 0.05 (locked)"),   tags$td("< 0.05 (adjustable)"),     tags$td("Significance filter for correlations")),
                                    tags$tr(tags$td("Layout algorithm"),          tags$td("Fruchterman-Reingold"), tags$td("FR (selectable)"),      tags$td("Force-directed graph layout")),
                                    tags$tr(tags$td("Taxonomy level"),            tags$td("Genus (selectable)"), tags$td("Genus (selectable)"),     tags$td("Rank at which taxa are aggregated")),
                                    tags$tr(tags$td("Min prevalence"),            tags$td("30% (locked)"),      tags$td("30% (adjustable)"),        tags$td("Taxa must appear in this fraction of samples")),
                                    tags$tr(tags$td("Min abundance"),             tags$td("> 20 reads (locked)"), tags$td("> 20 reads (adjustable)"), tags$td("Per-taxon count threshold"))
                                )
                            )
                        )
                    )
                )
            )
        )
    ),

    # ==================================================================
    # NAVBAR RIGHT: Read-only mode badge (set from Welcome page)
    # ==================================================================
    # NOTE: bslib::nav_spacer() + bslib::nav_item() used to live here
    # to host the mode-badge in the navbar's right edge. bslib was
    # warning that those positional items aren't tabPanel/navbarMenu
    # children, so the badge has been moved into the footer below.

    # ==================================================================
    # FOOTER — persistent status bar
    # ==================================================================
    footer = div(class = "app-footer",
        span(icon("flask"), strong(" EzMAP v2.0"), " \u2014 Easy Microbiome Analysis Pipeline"),
        htmlOutput("analysis_state", inline = TRUE),
        # Mode badge moved here from the old nav_item right-edge slot.
        span(style = "margin-left:auto; padding-left:14px;",
             uiOutput("navbar_mode_badge", inline = TRUE))
    )
)
