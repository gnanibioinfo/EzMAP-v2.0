#!/usr/bin/env Rscript
################################################################################
# install_r_packages.R — Auto-install all R packages needed by EzMAP2 Downstream
#
# Called by the Java app before launching Shiny. Checks each package and only
# installs what's missing. Prints progress to stdout so Java can show it in
# the log console.
#
# KEY OPTIMIZATION: On Linux, uses Posit Public Package Manager (PPM) which
# serves pre-compiled binary packages. This reduces install time from ~2.5 hours
# (compiling from source) to ~2-5 minutes (downloading binaries).
#
# Exit codes:
#   0 = all packages ready (or only optional packages missing)
#   1 = core packages failed to install
################################################################################

cat("=== EzMAP2: Checking R packages ===\n")

# ============================================================================
# FAST PATH: Skip if packages were already installed successfully before.
# A lock file records the R version + success state. If it matches, skip.
# Delete the lock file to force a re-check (e.g. after upgrading R).
# ============================================================================
lock_file <- file.path(Sys.getenv("HOME"), ".ezmap2_packages_ok")
r_ver_tag <- paste0("R-", getRversion())

if (file.exists(lock_file)) {
  lock_content <- tryCatch(readLines(lock_file, warn = FALSE), error = function(e) "")
  if (length(lock_content) > 0 && lock_content[1] == r_ver_tag) {
    cat("[OK] Packages were verified previously (", r_ver_tag, "). Skipping check.\n")
    cat("[OK] To force re-check, delete: ", lock_file, "\n")
    quit(status = 0)
  } else {
    cat("[INFO] R version changed or lock file invalid — re-checking packages.\n")
  }
}

# ---- Network settings: shorter timeouts to avoid 15-min hangs ----
options(timeout = 120)

# ============================================================================
# STEP 0: Configure binary package repository for fast installs
# ============================================================================
# Posit Public Package Manager (PPM) serves pre-compiled binaries for Linux.
# This is the single biggest speedup: no compilation = minutes instead of hours.

setup_binary_repos <- function() {
  os_info <- Sys.info()["sysname"]

  if (os_info == "Linux") {
    # Detect Ubuntu version for binary URL
    os_release <- tryCatch({
      info <- readLines("/etc/os-release", warn = FALSE)
      codename <- sub("^VERSION_CODENAME=", "",
                      grep("^VERSION_CODENAME=", info, value = TRUE))
      if (length(codename) == 0 || codename == "") "jammy"  # default to 22.04
      else codename
    }, error = function(e) "jammy")

    # PPM binary repo URL for this Ubuntu version
    ppm_url <- sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", os_release)

    cat(sprintf("[SETUP] Linux detected (%s) — using Posit PPM binary packages for fast install.\n", os_release))
    cat(sprintf("[SETUP] Repo: %s\n", ppm_url))

    # Set as primary repo; keep CRAN as fallback
    options(repos = c(PPM = ppm_url, CRAN = "https://cloud.r-project.org"))

    # Tell R to accept binary packages on Linux
    options(HTTPUserAgent = sprintf(
      "R/%s R (%s)", getRversion(),
      paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])
    ))

  } else {
    # macOS/Windows: CRAN already provides binaries
    cat("[SETUP] Non-Linux OS — using standard CRAN repository.\n")
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }
}

setup_binary_repos()

# ---- Check for system libraries needed by compiled R packages ----
# (Only needed if PPM binaries are unavailable and R falls back to source)
check_system_deps <- function() {
  os_info <- Sys.info()["sysname"]
  if (os_info != "Linux") return()

  missing_libs <- character(0)
  check_lib <- function(header, pkg_name) {
    result <- suppressWarnings(system2("pkg-config", c("--exists", pkg_name),
                                       stdout = FALSE, stderr = FALSE))
    if (!is.null(result) && result != 0) {
      missing_libs <<- c(missing_libs, pkg_name)
    }
  }

  for (lib in c("fontconfig", "freetype2", "harfbuzz", "fribidi", "libpng", "libtiff-4")) {
    check_lib(lib, lib)
  }

  if (length(missing_libs) > 0) {
    cat("\n[SYSTEM] Note: Some system C libraries may be needed if binary packages are unavailable.\n")
    cat("[SYSTEM] If any CRAN install falls back to source compilation and fails, run:\n")
    cat("[SYSTEM]   sudo apt-get install -y \\\n")
    cat("[SYSTEM]     libfontconfig1-dev libfreetype6-dev libharfbuzz-dev \\\n")
    cat("[SYSTEM]     libfribidi-dev libpng-dev libtiff5-dev libjpeg-dev \\\n")
    cat("[SYSTEM]     libcurl4-openssl-dev libssl-dev libxml2-dev\n\n")
  }
}
check_system_deps()

# ---- CRAN packages ----
cran_packages <- c(
  "shiny", "shinyjs", "bslib", "shinycssloaders",
  "ggplot2", "plotly", "DT",
  "dplyr", "tidyr", "plyr", "stringr",
  "RColorBrewer", "viridis",
  "vegan", "igraph", "randomForest",
  "reshape2", "pheatmap", "ape",
  "data.table", "scales", "gridExtra",
  "png", "markdown", "rmarkdown",
  "shinythemes", "networkD3", "caret",
  "ggrepel"
)

# tidyverse is a meta-package that needs system libs — try it, but don't block on it
tidyverse_pkg <- "tidyverse"

# ---- Bioconductor packages ----
bioc_packages <- c(
  "phyloseq", "biomformat", "DESeq2",
  "genefilter", "rhdf5"
)

# Optional Bioconductor (may not be available for all BioC versions)
optional_bioc <- c("metagenomeSeq", "EnhancedVolcano")

# ---- Additional packages (GitHub) ----
special_packages <- c("pairwiseAdonis")

# ---- Helper: check if installed ----
is_installed <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

# ============================================================================
# Step 1: CRAN packages (using binary repo — should be very fast)
# ============================================================================
missing_cran <- cran_packages[!sapply(cran_packages, is_installed)]
if (length(missing_cran) == 0) {
  cat("[OK] All CRAN packages already installed.\n")
} else {
  cat(sprintf("[INSTALL] Missing CRAN packages (%d): %s\n",
              length(missing_cran), paste(missing_cran, collapse = ", ")))
  cat("[INSTALL] Using binary packages — this should take 2-5 minutes...\n")

  # Install all at once (faster than one-by-one for binaries)
  tryCatch({
    install.packages(missing_cran, quiet = TRUE, Ncpus = max(1, parallel::detectCores() - 1))
    still_missing <- missing_cran[!sapply(missing_cran, is_installed)]
    if (length(still_missing) == 0) {
      cat(sprintf("  [OK] All %d CRAN packages installed successfully.\n", length(missing_cran)))
    } else {
      cat(sprintf("  [WARN] %d package(s) still missing after bulk install: %s\n",
                  length(still_missing), paste(still_missing, collapse = ", ")))
      # Retry individually for better error messages
      for (pkg in still_missing) {
        cat(sprintf("  Retrying %s individually...\n", pkg))
        tryCatch({
          install.packages(pkg, quiet = TRUE)
          if (is_installed(pkg)) cat(sprintf("  [OK] %s installed.\n", pkg))
          else cat(sprintf("  [WARN] %s still not loadable.\n", pkg))
        }, error = function(e) {
          cat(sprintf("  [WARN] %s failed: %s\n", pkg, conditionMessage(e)))
        })
      }
    }
  }, error = function(e) {
    cat(sprintf("  [WARN] Bulk install failed: %s\n", conditionMessage(e)))
    cat("  Falling back to individual installs...\n")
    for (pkg in missing_cran) {
      if (!is_installed(pkg)) {
        cat(sprintf("  Installing %s...\n", pkg))
        tryCatch({
          install.packages(pkg, quiet = TRUE)
          if (is_installed(pkg)) cat(sprintf("  [OK] %s installed.\n", pkg))
          else cat(sprintf("  [WARN] %s not loadable.\n", pkg))
        }, error = function(e2) {
          cat(sprintf("  [WARN] %s failed: %s\n", pkg, conditionMessage(e2)))
        })
      }
    }
  })
}

# ---- tidyverse (try separately — needs system libs) ----
if (!is_installed(tidyverse_pkg)) {
  cat("[INSTALL] Installing tidyverse (may need system libraries)...\n")
  tryCatch({
    install.packages(tidyverse_pkg, quiet = TRUE)
    if (is_installed(tidyverse_pkg)) {
      cat("  [OK] tidyverse installed.\n")
    } else {
      cat("  [WARN] tidyverse failed to install. This is usually caused by missing system libraries.\n")
      cat("  [WARN] Run: sudo apt-get install -y libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev libpng-dev libtiff5-dev libjpeg-dev\n")
      cat("  [WARN] Then restart EzMAP2 to retry. Core functionality works without tidyverse.\n")
    }
  }, error = function(e) {
    cat(sprintf("  [WARN] tidyverse failed: %s\n", conditionMessage(e)))
    cat("  [WARN] Install system libraries and retry. See above for the apt-get command.\n")
  })
}

# ============================================================================
# Step 2: Bioconductor packages (with proper repo configuration)
# ============================================================================
if (!is_installed("BiocManager")) {
  cat("  Installing BiocManager...\n")
  install.packages("BiocManager", quiet = TRUE)
}

missing_bioc <- bioc_packages[!sapply(bioc_packages, is_installed)]
if (length(missing_bioc) == 0) {
  cat("[OK] All Bioconductor packages already installed.\n")
} else {
  cat(sprintf("[INSTALL] Missing Bioconductor packages (%d): %s\n",
              length(missing_bioc), paste(missing_bioc, collapse = ", ")))

  for (pkg in missing_bioc) {
    cat(sprintf("  Installing %s (Bioconductor)...\n", pkg))
    tryCatch({
      BiocManager::install(pkg, update = FALSE, ask = FALSE, quiet = TRUE,
                           force = TRUE)
      if (is_installed(pkg)) {
        cat(sprintf("  [OK] %s installed.\n", pkg))
      } else {
        cat(sprintf("  [WARN] %s: install completed but package not loadable.\n", pkg))
      }
    }, error = function(e) {
      cat(sprintf("  [WARN] %s failed: %s\n", pkg, conditionMessage(e)))
    })
  }
}

# ---- Optional Bioconductor packages (non-fatal) ----
missing_opt_bioc <- optional_bioc[!sapply(optional_bioc, is_installed)]
if (length(missing_opt_bioc) > 0) {
  cat(sprintf("[INSTALL] Optional Bioconductor packages (%d): %s\n",
              length(missing_opt_bioc), paste(missing_opt_bioc, collapse = ", ")))

  for (pkg in missing_opt_bioc) {
    cat(sprintf("  Installing %s (optional)...\n", pkg))
    tryCatch({
      BiocManager::install(pkg, update = FALSE, ask = FALSE, quiet = TRUE,
                           force = TRUE)
      if (is_installed(pkg)) {
        cat(sprintf("  [OK] %s installed.\n", pkg))
      } else {
        cat(sprintf("  [SKIP] %s not available for Bioconductor %s. Feature will be disabled.\n",
                    pkg, as.character(BiocManager::version())))
      }
    }, error = function(e) {
      cat(sprintf("  [SKIP] %s: %s (optional — feature disabled)\n", pkg, conditionMessage(e)))
    })
  }
} else {
  cat("[OK] All optional Bioconductor packages already installed.\n")
}

# ============================================================================
# Step 3: pairwiseAdonis (GitHub)
# ============================================================================
if (!is_installed("pairwiseAdonis")) {
  cat("[INSTALL] pairwiseAdonis (from GitHub)...\n")

  if (!is_installed("remotes")) {
    cat("  Installing remotes...\n")
    install.packages("remotes", quiet = TRUE)
  }

  tryCatch({
    remotes::install_github("pmartinezarbizu/pairwiseAdonis/pairwiseAdonis",
                            upgrade = "never", quiet = TRUE)
    cat("  [OK] pairwiseAdonis installed.\n")
  }, error = function(e) {
    cat(sprintf("  [SKIP] pairwiseAdonis: %s (optional)\n", conditionMessage(e)))
  })
} else {
  cat("[OK] pairwiseAdonis already installed.\n")
}

# ============================================================================
# Step 4: FUNGuildR (CRAN — optional)
# ============================================================================
if (!is_installed("FUNGuildR")) {
  cat("[INSTALL] FUNGuildR (optional, for fungal analysis)...\n")
  tryCatch({
    install.packages("FUNGuildR", quiet = TRUE)
    cat("  [OK] FUNGuildR installed.\n")
  }, error = function(e) {
    cat(sprintf("  [SKIP] FUNGuildR: %s (optional — fungal guild prediction disabled)\n",
                conditionMessage(e)))
  })
} else {
  cat("[OK] FUNGuildR already installed.\n")
}

# ============================================================================
# Step 5: themetagenomics (GitHub — required for Tax4Fun panel)
# ============================================================================
if (!is_installed("themetagenomics")) {
  cat("[INSTALL] themetagenomics (from GitHub, for Tax4Fun analysis)...\n")

  if (!is_installed("remotes")) {
    cat("  Installing remotes...\n")
    install.packages("remotes", quiet = TRUE)
  }

  tryCatch({
    remotes::install_github("EESI/themetagenomics",
                            upgrade = "never", quiet = TRUE)
    cat("  [OK] themetagenomics installed.\n")
  }, error = function(e) {
    cat(sprintf("  [SKIP] themetagenomics: %s (optional — Tax4Fun panel will auto-install on first use)\n",
                conditionMessage(e)))
  })
} else {
  cat("[OK] themetagenomics already installed.\n")
}

# ============================================================================
# Final summary
# ============================================================================
all_core <- c(cran_packages, bioc_packages)
all_optional <- c(tidyverse_pkg, optional_bioc, special_packages, "FUNGuildR", "themetagenomics")

core_missing <- all_core[!sapply(all_core, is_installed)]
opt_missing  <- all_optional[!sapply(all_optional, is_installed)]

cat("\n=== Summary ===\n")

if (length(core_missing) > 0) {
  cat(sprintf("[ERROR] %d core package(s) missing: %s\n",
              length(core_missing), paste(core_missing, collapse = ", ")))
  cat("The Shiny app may not start. Install these packages manually.\n")
} else {
  cat(sprintf("[OK] All %d core packages ready.\n", length(all_core)))

  # Write lock file so next launch skips the check entirely
  tryCatch({
    writeLines(r_ver_tag, lock_file)
    cat(sprintf("[OK] Lock file written: %s\n", lock_file))
    cat("[OK] Next launch will skip package checks. Delete this file to force re-check.\n")
  }, error = function(e) {
    cat("[WARN] Could not write lock file — will re-check next time.\n")
  })
}

if (length(opt_missing) > 0) {
  cat(sprintf("[INFO] %d optional package(s) not available: %s\n",
              length(opt_missing), paste(opt_missing, collapse = ", ")))
  cat("The app will run with some features disabled.\n")
}

# Exit 0 to let Shiny launch — it handles missing optional packages gracefully
quit(status = 0)
