# --- panels/panel-server-network.R ---
# Core packages (already loaded by global.r)
# library(shiny), library(phyloseq), library(ggplot2), library(dplyr)

# Optional packages -- guard so app doesn't crash if missing
.has_igraph <- requireNamespace("igraph", quietly = TRUE)
.has_DT_net <- requireNamespace("DT", quietly = TRUE)
if (.has_igraph) library(igraph)
if (.has_DT_net) library(DT)

# ======================================================================
# HELPER FUNCTIONS
# ======================================================================

calculate_stats_from_network <- function(net, pseq_data) {
  # closeness / eigen_centrality can fail or return NaN on disconnected graphs
  safe_closeness <- tryCatch(igraph::closeness(net), error = function(e) rep(0, igraph::vcount(net)))
  safe_closeness[!is.finite(safe_closeness)] <- 0
  safe_eigen <- tryCatch(igraph::eigen_centrality(net)$vector, error = function(e) rep(0, igraph::vcount(net)))
  safe_eigen[!is.finite(safe_eigen)] <- 0

  safe_betweenness <- tryCatch(igraph::betweenness(net), error = function(e) rep(0, igraph::vcount(net)))
  safe_betweenness[!is.finite(safe_betweenness)] <- 0

  df_stats <- data.frame(
    ASV = igraph::V(net)$name,
    degree = igraph::degree(net),
    betweennesscentrality = safe_betweenness,
    closenesscentrality = safe_closeness,
    eigencentrality = safe_eigen
  )

  tax_df <- data.frame(phyloseq::tax_table(pseq_data))
  tax_df$ASV <- rownames(tax_df)
  df_stats <- left_join(df_stats, tax_df, by = "ASV")
  
  edge_counts <- if (igraph::ecount(net) > 0) {
    table(igraph::E(net)$interaction)
  } else {
    c("Positive" = 0, "Negative" = 0)
  }
  
  total_edges <- igraph::ecount(net)
  df_proportions <- data.frame(
    Interaction = names(edge_counts),
    Count = as.numeric(edge_counts)
  ) %>%
    mutate(
      TotalEdges = total_edges,
      Proportion = ifelse(TotalEdges > 0, Count / TotalEdges, 0)
    )
  
  return(list(node_stats = df_stats, edge_proportions = df_proportions))
}

# --- Build an igraph network from a correlation matrix + threshold ---
# When q_mat (matrix of FDR-corrected p-values) is supplied, edges must
# satisfy BOTH |r| > cor_threshold AND q < pval_threshold. When q_mat is
# NULL (legacy / Pearson / Spearman without bootstrap), only |r| is
# applied. The reviewer (2026) explicitly asked for BH-FDR-corrected
# p-value filtering on top of the effect-size threshold; this is the
# implementation point.
.cor_matrix_to_network <- function(cor_mat, cor_threshold = 0.5,
                                   q_mat = NULL, pval_threshold = 0.05,
                                   ci_lower = NULL, ci_upper = NULL) {
  cor_mat[is.na(cor_mat)] <- 0          # guard against NA from small-sample cor()
  adj_mat <- ifelse(abs(cor_mat) > cor_threshold, 1, 0)
  if (!is.null(q_mat)) {
    q_mat[is.na(q_mat)] <- 1            # missing q -> treat as not-significant
    adj_mat <- adj_mat * ifelse(q_mat < pval_threshold, 1, 0)
  }
  # Bootstrap-CI gate: edge kept only when 0 lies OUTSIDE the CI, i.e.
  # the correlation's sign is consistent across bootstrap resamples.
  # Standard SparCC CI test from Friedman & Alm 2012.
  if (!is.null(ci_lower) && !is.null(ci_upper)) {
    ci_lower[is.na(ci_lower)] <- 0
    ci_upper[is.na(ci_upper)] <- 0
    ci_significant <- (ci_lower > 0) | (ci_upper < 0)
    adj_mat <- adj_mat * ifelse(ci_significant, 1, 0)
  }
  diag(adj_mat) <- 0
  net <- igraph::graph_from_adjacency_matrix(adj_mat, mode = "undirected", diag = FALSE)
  edge_list <- as.data.frame(igraph::get.edgelist(net))
  if (nrow(edge_list) > 0) {
    edge_cor <- mapply(function(x, y) cor_mat[x, y], edge_list$V1, edge_list$V2)
    igraph::E(net)$interaction <- ifelse(edge_cor > 0, "Positive", "Negative")
    igraph::E(net)$weight      <- abs(edge_cor)
    if (!is.null(q_mat)) {
      edge_q <- mapply(function(x, y) q_mat[x, y], edge_list$V1, edge_list$V2)
      igraph::E(net)$qvalue <- edge_q
    }
    if (!is.null(ci_lower) && !is.null(ci_upper)) {
      edge_lo <- mapply(function(x, y) ci_lower[x, y], edge_list$V1, edge_list$V2)
      edge_hi <- mapply(function(x, y) ci_upper[x, y], edge_list$V1, edge_list$V2)
      igraph::E(net)$ci_lower <- edge_lo
      igraph::E(net)$ci_upper <- edge_hi
    }
  } else {
    igraph::E(net)$interaction <- character(0)
    igraph::E(net)$weight      <- numeric(0)
    if (!is.null(q_mat)) igraph::E(net)$qvalue <- numeric(0)
    if (!is.null(ci_lower)) {
      igraph::E(net)$ci_lower <- numeric(0)
      igraph::E(net)$ci_upper <- numeric(0)
    }
  }
  net
}

# ======================================================================
# BOOTSTRAP PERMUTATION p-VALUES for any correlation method
# ======================================================================
# For each pair (i, j) we shuffle taxon j's abundances independently
# across samples B times, recompute the correlation matrix, and count
# how often the permuted |r| reaches or exceeds the observed |r|. The
# resulting p-value is the empirical right-tail probability under the
# null of no association. Two-tailed (we use |r|).
#
# `cor_fn` is a function taking a counts matrix (samples × taxa) and
# returning a correlation matrix. This indirection lets us reuse the
# loop for SparCC, Pearson, and Spearman.
.bootstrap_pvalues <- function(counts, cor_fn, observed_cor, n_bootstrap = 100,
                               progress_callback = NULL) {
  p <- ncol(counts)
  if (p < 3 || n_bootstrap <= 0) {
    return(matrix(NA_real_, nrow = p, ncol = p,
                  dimnames = list(colnames(counts), colnames(counts))))
  }
  obs_abs <- abs(observed_cor)
  ge_count <- matrix(0L, nrow = p, ncol = p)
  for (b in seq_len(n_bootstrap)) {
    perm <- counts
    # Independent column shuffling -- destroys taxon-taxon associations
    # while preserving each taxon's marginal distribution. Standard for
    # SparCC / Spearman null testing.
    for (j in seq_len(p)) perm[, j] <- sample(perm[, j])
    null_cor <- tryCatch(cor_fn(perm),
                         error = function(e) NULL)
    if (!is.null(null_cor)) {
      null_abs <- abs(null_cor)
      null_abs[is.na(null_abs)] <- 0
      ge_count <- ge_count + (null_abs >= obs_abs)
    }
    if (!is.null(progress_callback)) progress_callback(b, n_bootstrap)
  }
  # +1 / +1 to avoid p = 0; standard "permutation p-value" formula.
  p_mat <- (ge_count + 1) / (n_bootstrap + 1)
  diag(p_mat) <- 1
  dimnames(p_mat) <- list(colnames(counts), colnames(counts))
  p_mat
}

# ======================================================================
# BOOTSTRAP CI EDGE TEST -- Friedman & Alm (2012) approach
# ----------------------------------------------------------------------
# Resamples SAMPLES (rows) with replacement, recomputes the correlation
# on each bootstrap, and stores the full distribution of correlations
# per pair. An edge is considered significant if its (1 - alpha)
# bootstrap CI does not contain zero -- i.e. the observed correlation
# direction is consistent across resampling.
#
# This is fundamentally different from .bootstrap_pvalues() which
# permutes columns to destroy correlations and tests against a null of
# no association. The CI approach tests whether the observed
# correlation's *direction* is robust to sampling variation.
#
# Why this matters for microbiome networks:
#   - BH FDR over n*(n-1)/2 permutation p-values is mathematically
#     incapable of finding edges (smallest p = 1/(B+1) gets multiplied
#     into oblivion by the number of tests).
#   - Bootstrap CI gives a per-edge significance call without needing
#     multiple-testing correction at all -- each edge is its own test
#     of robustness, not part of a joint hypothesis.
#   - Friedman & Alm 2012 (the SparCC paper itself) uses this approach.
#   - Faust et al. 2012, Berry & Widder 2014, and most published
#     microbiome co-occurrence networks use bootstrap CI rather than
#     FDR-corrected p-values.
#
# Memory: stores n_bootstrap full correlation matrices in a 3D array.
# For 500 taxa x 100 boots ~= 200 MB. Pre-filter aggressively for
# wider tables.
# ======================================================================
.bootstrap_ci <- function(counts, cor_fn, n_bootstrap = 100,
                          ci_level = 0.95, progress_callback = NULL) {
  N <- nrow(counts)
  p <- ncol(counts)
  if (p < 3 || n_bootstrap <= 0 || N < 4) {
    return(list(lower = NULL, upper = NULL, n_bootstrap = 0))
  }
  # 3D array: [taxon_i, taxon_j, bootstrap_replicate]
  boot_cors <- array(NA_real_, dim = c(p, p, n_bootstrap))
  for (b in seq_len(n_bootstrap)) {
    boot_idx <- sample.int(N, N, replace = TRUE)
    boot_mat <- counts[boot_idx, , drop = FALSE]
    bc <- tryCatch(cor_fn(boot_mat), error = function(e) NULL)
    if (!is.null(bc)) boot_cors[, , b] <- bc
    if (!is.null(progress_callback)) progress_callback(b, n_bootstrap)
  }
  alpha <- 1 - ci_level
  # apply across the bootstrap dimension (3) for each (i,j) pair
  lower <- apply(boot_cors, c(1, 2), stats::quantile,
                 probs = alpha / 2, na.rm = TRUE)
  upper <- apply(boot_cors, c(1, 2), stats::quantile,
                 probs = 1 - alpha / 2, na.rm = TRUE)
  dimnames(lower) <- list(colnames(counts), colnames(counts))
  dimnames(upper) <- list(colnames(counts), colnames(counts))
  list(lower = lower, upper = upper, n_bootstrap = n_bootstrap,
       ci_level = ci_level)
}

# Apply BH (or other) FDR correction across the upper triangle of a
# p-value matrix and return a matching q-value matrix.
.apply_fdr <- function(p_mat, method = "BH") {
  p <- nrow(p_mat)
  if (p < 2) return(p_mat)
  upper_idx <- which(upper.tri(p_mat))
  q_vec <- stats::p.adjust(p_mat[upper_idx], method = method)
  q_mat <- matrix(1, nrow = p, ncol = p,
                  dimnames = dimnames(p_mat))
  q_mat[upper_idx] <- q_vec
  q_mat[lower.tri(q_mat)] <- t(q_mat)[lower.tri(q_mat)]   # mirror
  diag(q_mat) <- 1
  q_mat
}

# ======================================================================
# NETWORK SUMMARY METRICS -- for the manuscript's "quantitative comparison"
# ======================================================================
# Returns a single-row data.frame with the standard graph-theoretic
# descriptors a reviewer expects: N nodes, N edges, density, mean
# degree, average clustering coefficient, modularity (Louvain),
# number of communities, mean path length, components, assortativity.
.compute_network_metrics <- function(g, label = "network") {
  if (is.null(g) || igraph::vcount(g) == 0) {
    return(data.frame(
      Network = label,
      N_nodes = 0L, N_edges = 0L, Density = NA_real_,
      Mean_degree = NA_real_, Median_degree = NA_real_, Max_degree = NA_integer_,
      Avg_clustering_coef = NA_real_, Modularity_louvain = NA_real_,
      N_communities = NA_integer_, Mean_path_length = NA_real_,
      N_components = NA_integer_, Largest_component = NA_integer_,
      Assortativity_degree = NA_real_, Pos_edges = 0L, Neg_edges = 0L,
      stringsAsFactors = FALSE
    ))
  }

  deg <- igraph::degree(g)
  n_nodes <- igraph::vcount(g)
  n_edges <- igraph::ecount(g)

  # Louvain community detection (fastest, used in most micro-network papers)
  louvain <- tryCatch(igraph::cluster_louvain(g),
                      error = function(e) NULL)
  modularity_val <- if (!is.null(louvain))
                      igraph::modularity(louvain) else NA_real_
  n_comm <- if (!is.null(louvain)) length(unique(igraph::membership(louvain))) else NA_integer_

  comps <- igraph::components(g)

  # Edge sign breakdown -- biologically meaningful for co-occurrence
  # vs. mutual-exclusion analyses.
  n_pos <- sum(igraph::E(g)$interaction == "Positive", na.rm = TRUE)
  n_neg <- sum(igraph::E(g)$interaction == "Negative", na.rm = TRUE)

  data.frame(
    Network             = label,
    N_nodes             = n_nodes,
    N_edges             = n_edges,
    Density             = round(igraph::edge_density(g, loops = FALSE), 4),
    Mean_degree         = round(mean(deg), 3),
    Median_degree       = stats::median(deg),
    Max_degree          = as.integer(max(deg)),
    Avg_clustering_coef = round(igraph::transitivity(g, type = "average", isolates = "zero"), 4),
    Modularity_louvain  = round(modularity_val, 4),
    N_communities       = n_comm,
    Mean_path_length    = round(igraph::mean_distance(g, directed = FALSE,
                                                       unconnected = TRUE), 3),
    N_components        = comps$no,
    Largest_component   = as.integer(max(comps$csize)),
    Assortativity_degree = round(igraph::assortativity_degree(g, directed = FALSE), 4),
    Pos_edges           = n_pos,
    Neg_edges           = n_neg,
    stringsAsFactors    = FALSE
  )
}

# ======================================================================
# NATIVE SparCC -- Friedman & Alm (2012)
#
# Compositional-aware correlation estimation via iterative log-ratio
# variance decomposition. Zero-dependency implementation (no SpiecEasi
# needed). The algorithm is:
#   1. Build matrix of Var(log(xi/xj)) for every pair (i,j)
#   2. Iteratively refine basis variances and covariances
#   3. Threshold tiny correlations to enforce sparsity
#   4. Return correlation matrix
# ======================================================================
.sparcc_native <- function(counts, n_iter = 20, exclude_threshold = 0.1,
                           iter_callback = NULL) {
  # ---------------------------------------------------------------
  # Vectorised SparCC (Friedman & Alm 2012).
  #
  # Earlier version had four sets of nested for-loops: T-matrix,
  # basis_cov update, variance re-estimation, and sparsify. On a
  # 1000-taxon table that's ~5 million R-level evaluations and
  # explains why "Computing observed correlations" used to sit
  # silent for 5-10 minutes on a Xeon. Each loop is replaced with
  # one BLAS-accelerated matrix op, giving ~50-500x speedup.
  #
  # Math identities used:
  #   var(log xi - log xj) = var(log xi) + var(log xj) - 2 cov(log xi, log xj)
  #   c_ij = (v_i + v_j - T_ij) / 2
  #
  # `iter_callback(k, n)` lets the caller report per-iteration
  # progress so the overlay shows "SparCC iteration 5/20" instead
  # of a static spinner.
  # ---------------------------------------------------------------
  counts <- as.matrix(counts)
  counts[counts <= 0] <- 1          # pseudocount avoids log(0)
  p <- ncol(counts)

  # relative abundances -> log
  fracs     <- counts / rowSums(counts)
  log_fracs <- log(fracs)

  # T_mat[i,j] = Var(log xi - log xj). Vectorised in one matrix op.
  v_log  <- apply(log_fracs, 2, stats::var)
  C_log  <- stats::cov(log_fracs)
  T_mat  <- outer(v_log, v_log, "+") - 2 * C_log
  diag(T_mat) <- 0

  # Initial basis variances: median of off-diagonal T row, /2.
  T_off  <- T_mat
  diag(T_off) <- NA
  basis_var <- pmax(apply(T_off, 1, stats::median, na.rm = TRUE) / 2, 1e-10)
  basis_cov <- matrix(0, p, p)

  for (iter in seq_len(n_iter)) {
    if (!is.null(iter_callback)) iter_callback(iter, n_iter)

    # c_ij = (v_i + v_j - T_ij) / 2 -- entire matrix in one op.
    basis_cov <- (outer(basis_var, basis_var, "+") - T_mat) / 2
    diag(basis_cov) <- 0

    # Re-estimate variances. v_i = median over j!=i of:
    #   T_ij - basis_var[j] + 2 * basis_cov[i,j]
    M <- T_mat -
         matrix(basis_var, nrow = p, ncol = p, byrow = TRUE) +
         2 * basis_cov
    diag(M) <- NA
    basis_var <- pmax(apply(M, 1, stats::median, na.rm = TRUE), 1e-10)

    # Sparsify: zero out off-diagonal covariances whose implied
    # |rho| is below the exclusion threshold.
    denom_full <- sqrt(outer(basis_var, basis_var))
    rho_full   <- basis_cov / denom_full
    rho_full[!is.finite(rho_full)] <- 0
    mask <- abs(rho_full) < exclude_threshold
    basis_cov[mask] <- 0
    diag(basis_cov) <- 0
  }

  # Final correlation matrix in one op.
  denom <- sqrt(outer(basis_var, basis_var))
  denom[denom == 0] <- 1
  cor_mat <- basis_cov / denom
  cor_mat <- pmax(pmin(cor_mat, 1), -1)
  diag(cor_mat) <- 1
  rownames(cor_mat) <- colnames(counts)
  colnames(cor_mat) <- colnames(counts)
  list(Cor = cor_mat)
}

# --- SparCC (native, zero-dependency) ----------------------------------
# NOTE: Reviewer comment (2026-04): earlier versions labelled the FastSpar
# option "External" but actually ran Spearman correlation, which is
# misleading. This now runs a genuine SparCC implementation (Friedman &
# Alm 2012) without requiring SpiecEasi or any external dependency.
run_sparcc <- function(pseq, cor_threshold = 0.3,
                       n_bootstrap = 0, pval_threshold = 0.05,
                       fdr_method = "BH",
                       edge_test = "permutation",   # "permutation" | "bootstrap_ci" | "none"
                       ci_level = 0.95,
                       sparcc_n_iter = 20,           # iterative log-ratio fit iters
                       sparcc_exclude_threshold = 0.1,
                       progress_callback = NULL) {
  otu_mat <- t(phyloseq::otu_table(pseq))
  mode(otu_mat) <- "numeric"
  otu_mat <- round(otu_mat)   # SparCC expects integer counts
  otu_mat <- otu_mat[, colSums(otu_mat) > 0, drop = FALSE]
  if (ncol(otu_mat) < 3) stop("Fewer than 3 non-zero taxa -- cannot run SparCC.")

  # Closure that wraps whichever SparCC implementation is available; we
  # use it for both the observed fit and (if requested) the bootstrap
  # null permutations. The iter_cb argument forwards SparCC's inner
  # iteration count up to Shiny's progress notification -- only used for
  # the OBSERVED fit (bootstrap calls would clobber the bootstrap counter).
  sparcc_fn <- function(mat, iter_cb = NULL) {
    sc <- if (requireNamespace("SpiecEasi", quietly = TRUE)) {
      # SpiecEasi has no per-iteration hook; it's also already C-level
      # fast, so skip the callback and just run. SpiecEasi's sparcc()
      # doesn't expose n_iter as an argument either -- it uses its own
      # default. If a user wants to tune iterations, they need to use
      # the native fallback (i.e. uninstall SpiecEasi or comment out
      # the requireNamespace branch).
      SpiecEasi::sparcc(mat)
    } else {
      .sparcc_native(mat,
                     n_iter            = sparcc_n_iter,
                     exclude_threshold = sparcc_exclude_threshold,
                     iter_callback     = iter_cb)
    }
    cm <- as.matrix(sc$Cor)
    rownames(cm) <- colnames(mat)
    colnames(cm) <- colnames(mat)
    cm
  }

  # Observed correlation matrix -- push iteration count through
  # progress_callback so the overlay shows "SparCC iteration 5/20"
  # during the long inner fit.
  observed_iter_cb <- if (!is.null(progress_callback)) {
    function(k, n) {
      # Use a tiny step (0) so we don't move the bar -- just update detail.
      tryCatch(
        shiny::setProgress(detail = paste0("SparCC iteration ", k, " / ", n)),
        error = function(e) NULL
      )
    }
  } else NULL
  cor_mat <- sparcc_fn(otu_mat, iter_cb = observed_iter_cb)

  # Edge significance test -- routed by `edge_test`:
  #   "permutation"   -> .bootstrap_pvalues + FDR (legacy; broken on
  #                      large networks per the BH math).
  #   "bootstrap_ci"  -> .bootstrap_ci, edge kept if CI excludes 0
  #                      (Friedman & Alm 2012, recommended for SparCC).
  #   "none"          -> |r| filter only.
  q_mat <- NULL; p_mat <- NULL
  ci_lower <- NULL; ci_upper <- NULL
  if (!is.null(n_bootstrap) && n_bootstrap > 0 && edge_test == "permutation") {
    p_mat <- .bootstrap_pvalues(otu_mat, sparcc_fn, cor_mat,
                                n_bootstrap = n_bootstrap,
                                progress_callback = progress_callback)
    q_mat <- .apply_fdr(p_mat, method = fdr_method)
  } else if (!is.null(n_bootstrap) && n_bootstrap > 0 && edge_test == "bootstrap_ci") {
    boot_ci <- .bootstrap_ci(otu_mat, sparcc_fn,
                             n_bootstrap = n_bootstrap,
                             ci_level = ci_level,
                             progress_callback = progress_callback)
    ci_lower <- boot_ci$lower
    ci_upper <- boot_ci$upper
  }

  net <- .cor_matrix_to_network(cor_mat,
                                cor_threshold = cor_threshold,
                                q_mat = q_mat,
                                pval_threshold = pval_threshold,
                                ci_lower = ci_lower,
                                ci_upper = ci_upper)
  list(network = net, cor_matrix = cor_mat,
       p_matrix = p_mat,
       q_matrix = q_mat,
       ci_lower = ci_lower, ci_upper = ci_upper,
       n_bootstrap = n_bootstrap,
       pval_threshold = pval_threshold,
       fdr_method = if (!is.null(q_mat)) fdr_method else "none",
       edge_test = edge_test,
       ci_level = if (!is.null(ci_lower)) ci_level else NULL)
}

build_network_for_group <- function(pseq, method, cor_threshold, upload_correlation,
                                    n_bootstrap = 0, pval_threshold = 0.05,
                                    fdr_method = "BH",
                                    edge_test = "permutation",
                                    ci_level = 0.95,
                                    sparcc_n_iter = 20,
                                    sparcc_exclude_threshold = 0.1,
                                    progress_callback = NULL) {
  if (method == "SparCC") {
    run_sparcc(pseq, cor_threshold = cor_threshold %||% 0.3,
               n_bootstrap = n_bootstrap,
               pval_threshold = pval_threshold,
               fdr_method = fdr_method,
               edge_test = edge_test,
               ci_level = ci_level,
               sparcc_n_iter = sparcc_n_iter,
               sparcc_exclude_threshold = sparcc_exclude_threshold,
               progress_callback = progress_callback)
  } else {
    current_method <- tolower(method)   # "pearson" or "spearman"
    otu_mat <- t(phyloseq::otu_table(pseq))
    mode(otu_mat) <- "numeric"
    # Drop zero-variance columns (taxa constant across all samples in this subset)
    col_vars <- apply(otu_mat, 2, var, na.rm = TRUE)
    keep_cols <- !is.na(col_vars) & col_vars > 0
    if (sum(keep_cols) < 3) stop("Fewer than 3 variable taxa in this subset -- cannot compute correlations.")
    otu_mat <- otu_mat[, keep_cols, drop = FALSE]
    cor_fn <- function(mat) suppressWarnings(cor(mat, method = current_method))
    cor_mat <- cor_fn(otu_mat)

    # Edge significance routing -- same three-way switch as run_sparcc.
    q_mat <- NULL; p_mat <- NULL
    ci_lower <- NULL; ci_upper <- NULL
    if (!is.null(n_bootstrap) && n_bootstrap > 0 && edge_test == "permutation") {
      p_mat <- .bootstrap_pvalues(otu_mat, cor_fn, cor_mat,
                                  n_bootstrap = n_bootstrap,
                                  progress_callback = progress_callback)
      q_mat <- .apply_fdr(p_mat, method = fdr_method)
    } else if (!is.null(n_bootstrap) && n_bootstrap > 0 && edge_test == "bootstrap_ci") {
      boot_ci <- .bootstrap_ci(otu_mat, cor_fn,
                               n_bootstrap = n_bootstrap,
                               ci_level = ci_level,
                               progress_callback = progress_callback)
      ci_lower <- boot_ci$lower
      ci_upper <- boot_ci$upper
    }

    net <- .cor_matrix_to_network(cor_mat,
                                  cor_threshold = cor_threshold %||% 0.3,
                                  q_mat = q_mat,
                                  pval_threshold = pval_threshold,
                                  ci_lower = ci_lower,
                                  ci_upper = ci_upper)
    list(network = net, cor_matrix = cor_mat,
         p_matrix = p_mat, q_matrix = q_mat,
         ci_lower = ci_lower, ci_upper = ci_upper,
         n_bootstrap = n_bootstrap,
         pval_threshold = pval_threshold,
         fdr_method = if (!is.null(q_mat)) fdr_method else "none",
         edge_test = edge_test,
         ci_level = if (!is.null(ci_lower)) ci_level else NULL)
  }
}

# small null-coalesce helper
`%||%` <- function(a, b) if (is.null(a)) b else a

# ======================================================================
# SERVER MODULE
# ======================================================================

networkServer <- function(id, physeq_raw, physeq_filtered, global_state_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Check required optional packages
    if (!.has_igraph) {
      showNotification("Package 'igraph' is not installed. Network analysis is disabled. Install with: install.packages('igraph')",
                       type = "error", duration = NULL)
    }

    # --- Dataset selector (Raw vs Filtered) ---
    physeq_data <- dataset_selector_reactive(input, physeq_raw, physeq_filtered)

    # (F-R animation removed: `area` and `repulserad` are defunct in igraph >= 2.0)

    # --- Preprocess phyloseq ---
    preprocessed_physeq <- reactive({
      req(.has_igraph)  # Block if igraph missing
      req(physeq_data())
      pseq <- physeq_data()

      withProgress(message = "Processing Microbiome Data...", value = 0, {
        incProgress(0.1, detail = "Standardizing taxonomy")
        # NOTE: Do NOT rename taxa here. Canonical "ASV1..ASV(N_raw)" IDs
        # are assigned once at upload (panel-server-data.R) and preserved
        # by the Filter tab. Local renames re-number surviving taxa to
        # "ASV1..ASV(local_n)", desyncing network IDs from every other
        # panel and breaking cross-panel ASV references. Rename removed.
        colnames(tax_table(pseq)) <- c("Kingdom","Phylum","Class","Order","Family","Genus","Species")

        # NOTE: NO local taxa filtering and NO local count normalization.
        # The central Filter tab is the single source of truth for taxa
        # filtering (chloroplast / mitochondria / Eukaryota / Archaea /
        # abundance / prevalence / custom exclusions). Previously this
        # panel re-ran:
        #     subset_taxa(!grepl("Eukaryota|Archaea", Kingdom))      # kills fungi
        #     filter_taxa(sum(x > 20) > 0.3 * length(x))             # keeps only
        #                                                            # UNIVERSAL taxa
        #     transform_sample_counts(median-depth)                  # not needed
        # The 30% prevalence filter applied to ALL samples (across all
        # conditions) silently killed condition-specific signal -- every
        # per-condition network ended up with the same node count
        # (e.g. 622 across control/disease/salt/drought) because the
        # surviving taxa were by construction present in every sample.
        # Per-condition `prune_taxa(taxa_sums > 0)` happens later in
        # selected_physeq() and is the right level for the network
        # subset to reflect the condition's actual biology.
        # The median-depth normalization is also removed: SparCC expects
        # integer counts and does its own log-ratio bias correction
        # internally; Pearson / Spearman either work on the raw counts
        # or the user can rarefy via the Rarefaction tab beforehand.
        incProgress(0.5, detail = "Cleaning taxonomy strings")
        tax_mat <- as(tax_table(pseq), "matrix")
        tax_mat[,] <- gsub("[Dd]_[0-9]+__", "", tax_mat[,])
        tax_mat[,] <- gsub("^[dkpcofgsDKPCOFGS]__", "", tax_mat[,])
        tax_mat[,] <- trimws(tax_mat[,])
        tax_table(pseq) <- tax_table(tax_mat)
      })
      return(pseq)
    })
    
    # --- UI Outputs ---
    output$category_ui <- renderUI({
      req(preprocessed_physeq())
      metadata <- as(sample_data(preprocessed_physeq()), "data.frame")
      group_vars <- names(metadata)[sapply(metadata, function(x)
        (is.factor(x) || is.character(x)) && length(unique(na.omit(x))) > 1)]
      selectInput(ns("category"), "Select Metadata Category:", choices = group_vars)
    })
    
    output$sample_group_ui <- renderUI({
      req(input$category)
      metadata <- as(sample_data(preprocessed_physeq()), "data.frame")
      levels_group <- unique(na.omit(metadata[[input$category]]))
      selectInput(ns("groups"), "Select Groups:", choices = levels_group,
                  selected = levels_group[1:2], multiple = TRUE)
    })

    # ------------------------------------------------------------------
    # Per-group ASV / sample count breakdown.
    # Shared helper from global.r -- same card appears on DESeq2, ANCOM-BC,
    # RF, and Network panels so the user gets a consistent view of
    # condition-specific richness across every analysis.
    # ------------------------------------------------------------------
    output$group_asv_counts_ui <- renderUI({
      req(input$category)
      group_asv_count_card(
        pseq            = preprocessed_physeq(),
        category        = input$category,
        selected_groups = input$groups %||% character(0)
      )
    })
    
    # |r| threshold slider rendered ONCE here (visible in both Easy
    # and Expert) -- the panel UI now references this output from
    # outside the conditionalPanel. Default raised from 0.3 to 0.6:
    # bootstrap CI (now the default edge test) is a sign-robustness
    # test, not a strength test, so 0.3 leaks too many weak-but-
    # consistent edges into the result. |r| >= 0.6 produces the
    # ~1-3% edge density typical of published microbiome networks.
    output$method_specific_ui <- renderUI({
      method <- input$method %||% "Spearman"
      if (method %in% c("Pearson", "Spearman")) {
        sliderInput(ns("cor_threshold"), "Correlation Threshold (|r|):",
                    min = 0.1, max = 1, value = 0.6, step = 0.01)
      } else if (method == "SparCC") {
        sliderInput(ns("cor_threshold"), "SparCC |r| threshold:",
                    min = 0.1, max = 0.9, value = 0.6, step = 0.01)
      } else { NULL }
    })

    # --- Selected Subset ---
    selected_physeq <- reactive({
      req(input$category, input$groups)
      metadata <- as(sample_data(preprocessed_physeq()), "data.frame")
      keep_samples <- rownames(metadata)[metadata[[input$category]] %in% input$groups]
      sub_pseq <- prune_samples(keep_samples, preprocessed_physeq())
      sub_pseq <- prune_taxa(taxa_sums(sub_pseq) > 0, sub_pseq)

      # ----------------------------------------------------------------
      # Network-specific pre-filter (stacks ON TOP of global Filtering
      # tab). 1000+ taxa = FDR correction over n*(n-1)/2 ~ 500k tests
      # which floors every q-value at 1.0 -- so the test always returns
      # zero edges. Aggressive prevalence + abundance filtering brings
      # taxa count down to a tractable 50-500 range.
      #
      # Differential-abundance tabs intentionally skip this filter
      # (they want rare taxa as biomarker candidates), so it lives
      # here in the network panel only.
      # ----------------------------------------------------------------
      min_prev_pct <- if (is.null(input$net_min_prevalence) ||
                          !is.finite(input$net_min_prevalence)) 30
                      else input$net_min_prevalence
      min_reads    <- if (is.null(input$net_min_reads) ||
                          !is.finite(input$net_min_reads)) 50
                      else input$net_min_reads

      if (min_prev_pct > 0 || min_reads > 0) {
        n_samples <- nsamples(sub_pseq)
        min_samples <- ceiling((min_prev_pct / 100) * n_samples)
        # taxa_sums for total reads, count of non-zero samples for prevalence
        otu_mat   <- as(otu_table(sub_pseq), "matrix")
        if (taxa_are_rows(sub_pseq)) {
          prevalence  <- rowSums(otu_mat > 0)
          total_reads <- rowSums(otu_mat)
        } else {
          prevalence  <- colSums(otu_mat > 0)
          total_reads <- colSums(otu_mat)
        }
        keep <- prevalence >= min_samples & total_reads >= min_reads
        sub_pseq <- prune_taxa(keep, sub_pseq)
      }
      sub_pseq
    })

    # --- Live preview of post-filter taxa count ---
    # Renders a small status card so the user can dial the prevalence /
    # min-reads thresholds and see how many ASVs survive BEFORE clicking
    # Run Network. Flags too-high (won't find edges) and too-low
    # (overfiltered) outcomes.
    output$net_filter_preview <- renderUI({
      pseq <- tryCatch(selected_physeq(), error = function(e) NULL)
      if (is.null(pseq)) {
        return(div(style = "padding:8px 10px; background:#F1F5F9; border-radius:6px; font-size:11px; color:#64748B;",
                   "Pick a metadata category and group to see the filtered ASV count."))
      }
      n_taxa <- ntaxa(pseq)
      # Pre-filter count for context
      raw_pseq <- tryCatch({
        metadata <- as(sample_data(preprocessed_physeq()), "data.frame")
        keep_samples <- rownames(metadata)[metadata[[input$category]] %in% input$groups]
        sub <- prune_samples(keep_samples, preprocessed_physeq())
        prune_taxa(taxa_sums(sub) > 0, sub)
      }, error = function(e) NULL)
      n_pre <- if (!is.null(raw_pseq)) ntaxa(raw_pseq) else NA_integer_

      # Color-coded health check, method-aware.
      #
      # Old verdicts hard-coded BH FDR language (e.g. "good for FDR-
      # corrected networks") because that was the assumed test before
      # bootstrap CI became the default. Now Easy mode uses bootstrap
      # CI (no FDR over edges) and Expert can pick any of three tests,
      # so the verdict text adapts to whichever the user has selected.
      #
      # Thresholds also differ by test:
      #   - bootstrap CI / |r|-only: density-driven (any taxa count
      #     mathematically works; the issue is plot interpretability)
      #   - permutation + FDR: BH/Bonferroni hit a hard wall around
      #     ~50 taxa where smallest-possible q exceeds 1.0
      etest <- if (is.null(input$edge_test) || !nzchar(input$edge_test)) {
                  "bootstrap_ci"   # Easy default
              } else { input$edge_test }
      uses_fdr_correction <- (etest == "permutation") &&
                             !is.null(input$fdr_method) &&
                             input$fdr_method != "none"

      verdict <- if (uses_fdr_correction) {
        # Permutation + FDR path: warn about the BH math wall.
        if (n_taxa <= 50) {
          list(bg = "#D1FAE5", border = "#10B981", icon = "check-circle",
               txt = paste0(n_taxa, " ASVs -- FDR-tractable network size."))
        } else if (n_taxa <= 200) {
          list(bg = "#FEF3C7", border = "#F59E0B", icon = "exclamation-triangle",
               txt = paste0(n_taxa, " ASVs -- FDR may struggle here; ",
                            "smallest possible q exceeds 0.05. Consider ",
                            "switching to Bootstrap CI test or tightening filter."))
        } else {
          list(bg = "#FEE2E2", border = "#EF4444", icon = "exclamation-circle",
               txt = paste0(n_taxa, " ASVs -- FDR mathematically empty at ",
                            "this scale. Use Bootstrap CI test or tighten filter."))
        }
      } else {
        # Bootstrap CI / |r|-only path: density-driven verdict, geared
        # toward publication interpretability.
        if (n_taxa <= 500) {
          list(bg = "#D1FAE5", border = "#10B981", icon = "check-circle",
               txt = paste0(n_taxa, " ASVs -- good size for publication-quality networks."))
        } else if (n_taxa <= 1000) {
          list(bg = "#FEF3C7", border = "#F59E0B", icon = "exclamation-triangle",
               txt = paste0(n_taxa, " ASVs -- network may be too dense. ",
                            "Consider tighter filter for cleaner figure."))
        } else {
          list(bg = "#FEE2E2", border = "#EF4444", icon = "exclamation-circle",
               txt = paste0(n_taxa, " ASVs -- too many for interpretable ",
                            "co-occurrence network. Tighten the filter."))
        }
      }
      div(style = paste0("background:", verdict$bg,
                         "; border-left:4px solid ", verdict$border,
                         "; padding:8px 12px; border-radius:6px; font-size:11.5px;"),
          icon(verdict$icon, style = paste0("color:", verdict$border, "; margin-right:4px;")),
          tags$b(verdict$txt),
          if (!is.na(n_pre) && n_pre != n_taxa) {
              tagList(tags$br(),
                      tags$small(style = "color:#64748B;",
                                 "Pre-filter: ", n_pre, " ASVs -> post-filter: ",
                                 n_taxa, " (-", n_pre - n_taxa, ")"))
          })
    })
    
    # --- Compute Single Network (and its layout) ---
    # IMPORTANT: the igraph layout (especially layout_with_fr with 500
    # iterations) is the slow part of this panel -- easily several seconds
    # on networks with hundreds of nodes. Previously the layout was
    # computed INSIDE output$network_plot's renderPlot. Shiny re-runs a
    # renderPlot whenever its container becomes visible again after being
    # hidden, so flipping to the "Statistics & Plots" tab and back caused
    # the layout to be recomputed every time, which made the UI look
    # frozen for several seconds on each return visit.
    #
    # Fix: compute the layout ONCE inside the eventReactive, cache it
    # alongside the network in the returned list, and have renderPlot
    # just read the cached coordinates. Tab switches now re-paint the
    # plot from cache instantly. Layout is only recomputed when the user
    # clicks Run Network again (e.g. with a different group or method).
    # set.seed makes the result deterministic so the layout doesn't
    # "jump" between identical runs either.
    network_result <- eventReactive(input$run_network, {
      req(selected_physeq())
      method <- input$method %||% "Spearman"
      cor_threshold <- input$cor_threshold %||% 0.3
      # Bootstrap permutation p-values + FDR.
      #
      # IMPORTANT: conditionalPanel() doesn't unmount its children -- it
      # just hides them with CSS. So input$n_bootstrap (Expert numeric
      # input) and input$n_bootstrap_easy (Easy slider) BOTH always have
      # values regardless of which mode the user picked. We have to read
      # the actual mode from the root session and pick the matching one.
      #
      # Default 100 matches Friedman & Alm 2012 (the SparCC paper).
      # Set to 0 in Expert to skip the bootstrap loop entirely
      # (legacy |r|-only behaviour).
      mode_now <- ezmap_get_mode()
      n_bootstrap <- if (mode_now == "expert" &&
                         !is.null(input$n_bootstrap) &&
                         is.finite(input$n_bootstrap)) {
                         as.integer(input$n_bootstrap)
                     } else if (!is.null(input$n_bootstrap_easy) &&
                                is.finite(input$n_bootstrap_easy)) {
                         as.integer(input$n_bootstrap_easy)
                     } else {
                         100L
                     }
      # In Easy mode the Expert input$pval_threshold (default 0.05) and
      # input$fdr_method (default "BH") are still in the DOM but hidden
      # by conditionalPanel -- so we route on actual mode rather than
      # is.null. Otherwise Easy mode would silently use BH FDR which
      # is mathematically incapable of finding edges on any realistic
      # network size (smallest possible bootstrap p = 1/(N+1); BH
      # multiplies by n_tests = T*(T-1)/2; on 500 taxa that's 125k
      # tests, so smallest q = 0.01 * 125k = 1250, capped at 1.0).
      #
      # Easy mode now filters on raw bootstrap p-value + |r| only --
      # which is what published microbiome networks actually do --
      # and produces real edges. Expert mode keeps BH as the default
      # for users who know what they're doing, with the pre-flight
      # check below warning them if their choice can't possibly work.
      pval_threshold  <- if (mode_now == "expert" &&
                             !is.null(input$pval_threshold) &&
                             is.finite(input$pval_threshold)) {
                            as.numeric(input$pval_threshold)
                         } else { 0.05 }
      fdr_method      <- if (mode_now == "expert" &&
                             !is.null(input$fdr_method) &&
                             nzchar(input$fdr_method)) {
                            input$fdr_method
                         } else { "none" }
      # Edge significance test choice. Easy mode now defaults to
      # "bootstrap_ci" (the Friedman & Alm 2012 SparCC-paper approach
      # and what most rigorous published microbiome network papers
      # actually report). Expert mode falls through to whatever the
      # user selected, defaulting to bootstrap_ci as well.
      # The CI path costs more memory (stores full p*p*B array) but
      # is reviewer-proof and produces real edges on real network sizes
      # without the BH-FDR pathology.
      edge_test       <- if (mode_now == "expert" &&
                             !is.null(input$edge_test) &&
                             nzchar(input$edge_test)) {
                            input$edge_test
                         } else { "bootstrap_ci" }
      ci_level        <- if (!is.null(input$ci_level) &&
                             is.finite(input$ci_level)) {
                            as.numeric(input$ci_level)
                         } else { 0.95 }
      # SparCC inner solver controls (Expert only). Friedman & Alm
      # 2012 default = 20 iterations, exclude_threshold = 0.1. Easy
      # users get the literature defaults silently.
      sparcc_n_iter   <- if (mode_now == "expert" &&
                             !is.null(input$sparcc_n_iter) &&
                             is.finite(input$sparcc_n_iter) &&
                             input$sparcc_n_iter > 0) {
                            as.integer(input$sparcc_n_iter)
                         } else { 20L }
      sparcc_exclude  <- if (mode_now == "expert" &&
                             !is.null(input$sparcc_exclude_threshold) &&
                             is.finite(input$sparcc_exclude_threshold)) {
                            as.numeric(input$sparcc_exclude_threshold)
                         } else { 0.1 }
      # Default layout = layout_nicely (auto-picks the fastest sensible
      # algorithm based on graph size). Easy Mode hides the layout
      # dropdown, so the %||% fallback here is the ONE source of truth
      # for that mode. layout_with_fr was the previous default; on
      # networks of more than ~200 nodes its 500-iteration loop took
      # several seconds and made the panel look frozen on every redraw.
      layout_func <- input$layout_method %||% "layout_nicely"
      # FR-iterations default lowered from 500 to 200 -- still produces
      # a clean layout, but several times faster.
      fr_niter <- if (is.null(input$fr_niter) || !is.finite(input$fr_niter) ||
                      input$fr_niter <= 0) 200 else input$fr_niter

      # ----------------------------------------------------------------
      # Pre-flight FDR sanity check.
      # If the user picked an FDR method that is mathematically incapable
      # of producing edges given (n_taxa, n_bootstrap, alpha), warn them
      # BEFORE we kick off the long bootstrap loop. Otherwise they wait
      # 5+ minutes for a guaranteed-empty network.
      #
      # Smallest possible bootstrap p-value is 1/(n_bootstrap+1).
      # BH q-value for the smallest test is min_p * n_tests / 1.
      # If that exceeds alpha, BH cannot find any edge no matter what.
      # ----------------------------------------------------------------
      # Only the permutation+FDR path has the BH-cannot-find-edges issue.
      # Bootstrap CI doesn't use FDR (per-edge robustness, not joint
      # hypothesis), and "none" obviously doesn't either.
      if (n_bootstrap > 0 && edge_test == "permutation" && fdr_method != "none") {
        n_taxa_now <- ntaxa(selected_physeq())
        n_tests    <- n_taxa_now * (n_taxa_now - 1) / 2
        min_p      <- 1 / (n_bootstrap + 1)
        # Approximate worst-case minimum q for BH (best-case for the user
        # is BH; Bonferroni / Holm / BY are stricter and only get worse).
        min_q_approx <- min_p * n_tests
        if (min_q_approx > pval_threshold) {
          showNotification(
            ui = tagList(
                tags$b("FDR test cannot find edges with these settings."),
                tags$br(),
                "With ", tags$b(n_taxa_now), " taxa = ", tags$b(format(n_tests, big.mark = ",")),
                " edge tests and ", tags$b(n_bootstrap), " bootstraps, the smallest ",
                "possible q-value (", round(min_q_approx, 2), ") is above your ",
                "p-value threshold (", pval_threshold, "). The network will return ",
                tags$b("zero edges"), " unless you do one of:",
                tags$ul(
                    tags$li("Switch ", tags$b("FDR method to None"),
                            " (filter on raw p-value + |r| only -- this is what ",
                            "most published microbiome networks do)"),
                    tags$li("Filter to ", tags$b("fewer taxa"),
                            " in the Network pre-filter above ",
                            "(target < ", floor(pval_threshold * (n_bootstrap + 1)),
                            " ASVs would let BH work here)"),
                    tags$li("Set ", tags$b("Bootstrap iterations to 0"),
                            " to skip the permutation test and filter on |r| only")
                )
            ),
            type = "warning",
            duration = 20
          )
        }
      }

      withProgress(message = paste("Constructing network (", method, ")..."), value = 0.05, {
        # ---- Phase 1: preprocessing ----
        # Visible message even before the network call starts so the
        # overlay subtitle stops looking frozen during the silent
        # preprocessing window (taxa filtering + matrix transpose).
        incProgress(0.05, detail = paste0(
            "Preparing ", method, " input matrix..."))

        # ---- Phase 2: observed correlation ----
        # SparCC's iterative log-ratio fit and Pearson/Spearman matrix
        # multiplications are both fast on ~500 taxa, slow on >2000.
        # Surface them so the user knows we're past the silent setup.
        incProgress(0.05, detail = paste0(
            "Computing observed ", method, " correlations..."))

        # Progress callback for the bootstrap loop -- the longest stage,
        # so we surface its progress instead of leaving the user staring
        # at an unmoving spinner. Wording differs by edge_test method:
        # bootstrap CI is genuine resampling (sample rows with
        # replacement), permutation shuffles columns to break association.
        boot_label <- switch(edge_test,
            "bootstrap_ci" = "Bootstrap resample",
            "permutation"  = "Bootstrap permutation",
            "Bootstrap iteration"
        )
        boot_cb <- if (n_bootstrap > 0) {
          function(b, n_total) {
            # Allocate 0.1 -> 0.6 of the bar to bootstraps.
            incProgress(0.5 / max(n_total, 1),
                        detail = paste0(boot_label, " ", b,
                                        " / ", n_total))
          }
        } else NULL
        result <- build_network_for_group(
          selected_physeq(), method, cor_threshold, NULL,
          n_bootstrap     = n_bootstrap,
          pval_threshold  = pval_threshold,
          fdr_method      = fdr_method,
          edge_test       = edge_test,
          ci_level        = ci_level,
          sparcc_n_iter   = sparcc_n_iter,
          sparcc_exclude_threshold = sparcc_exclude,
          progress_callback = boot_cb
        )

        # ---- Phase 3: significance test + edge filtering ----
        # Message differs by method: bootstrap CI computes per-edge CIs
        # (no FDR), permutation applies multiple-testing correction,
        # |r|-only just filters.
        if (!is.null(n_bootstrap) && n_bootstrap > 0) {
            phase3_msg <- switch(edge_test,
                "bootstrap_ci" = paste0("Computing ",
                                        round(100 * (ci_level %||% 0.95)),
                                        "% bootstrap CI & filtering edges..."),
                "permutation"  = paste0("Applying ", fdr_method,
                                        " FDR correction & filtering edges..."),
                "Filtering edges by |r| threshold..."
            )
            incProgress(0.05, detail = phase3_msg)
        } else {
            incProgress(0.05, detail = "Filtering edges by |r| threshold...")
        }

        # Layout is no longer pre-computed inside this eventReactive.
        # See network_layout() reactive below: layout depends on
        # input$layout_method (and input$fr_niter) so that switching the
        # layout dropdown re-renders the plot without rebuilding the
        # whole network. The result list still gets layout_func_used =
        # NULL here so downstream code can detect that layout is owned
        # by the separate reactive.

        incProgress(1.0, detail = "Done")
        return(result)
      })
    }, ignoreNULL = FALSE)

    # --- Network layout (separate reactive so dropdown switching is live) ---
    # Layout was previously baked into network_result() and only
    # recomputed on Run Network click. That cached the coordinates but
    # broke the layout dropdown -- changing it did nothing because the
    # eventReactive didn't depend on input$layout_method.
    #
    # Splitting layout into its own reactive means:
    #   - Run Network click -> rebuilds network (slow, click-gated)
    #   - Layout dropdown change -> only re-runs this reactive (fast)
    #   - Both invalidate output$network_plot which uses both
    network_layout <- reactive({
      res <- network_result()
      req(res, res$network)
      g <- res$network
      if (igraph::vcount(g) == 0) return(NULL)
      layout_func <- input$layout_method %||% "layout_nicely"
      fr_niter <- if (is.null(input$fr_niter) || !is.finite(input$fr_niter) ||
                      input$fr_niter <= 0) 200 else input$fr_niter
      set.seed(42)  # reproducible coords -- no jumps between identical reruns
      coords <- tryCatch({
        if (layout_func == "layout_with_fr") {
          igraph::layout_with_fr(g, niter = fr_niter)
        } else {
          fn <- tryCatch(getExportedValue("igraph", layout_func),
                         error = function(e) NULL)
          if (is.null(fn)) stop("Unknown layout function: ", layout_func)
          fn(g)
        }
      }, error = function(e) {
        showNotification(paste0("Layout '", layout_func,
                                "' failed: ", e$message,
                                " -- falling back to Nicely."),
                         type = "warning")
        set.seed(42)
        igraph::layout_nicely(g)
      })
      list(coords = coords, func_used = layout_func)
    })

    # --- Plot Network (live layout + live aesthetics) ---
    # Reads coordinates from network_layout() which depends on
    # input$layout_method, so switching the dropdown re-renders the
    # plot without rebuilding the network. Other aesthetic inputs
    # (node size, colors, edge width, curvature) are also live.
    output$network_plot <- renderPlot({
      res <- network_result()
      req(res$network)

      g <- res$network

      # Coordinates from the live-switching reactive. If unavailable
      # (e.g. empty graph) fall back to a quick nicely layout.
      lay <- network_layout()
      if (is.null(lay) || is.null(lay$coords)) {
        set.seed(42)
        layout_coords <- igraph::layout_nicely(g)
        layout_func   <- "layout_nicely"
      } else {
        layout_coords <- lay$coords
        layout_func   <- lay$func_used
      }

      # --- Resolve visual parameters from UI (with safe defaults) ---
      # Node-size resolution.
      # When sizing by a centrality metric we compute that metric on the
      # network, rescale linearly from input$node_size (min) to
      # input$node_size_max (max), and pass the per-node vector to
      # vertex.size. When mode = "fixed" we just use input$node_size.
      v_size_min  <- if (is.null(input$node_size)     || !is.finite(input$node_size))     3   else input$node_size
      v_size_max  <- if (is.null(input$node_size_max) || !is.finite(input$node_size_max)) 14  else input$node_size_max
      v_size_mode <- if (is.null(input$node_size_by)  || !nzchar(input$node_size_by))     "degree" else input$node_size_by

      # Compute the per-node size vector. Wrapped in tryCatch so a
      # disconnected graph (zero edges -> zero degree -> all nodes
      # identical at min size) doesn't error out.
      v_size <- if (v_size_mode == "fixed" || igraph::ecount(g) == 0) {
          v_size_min
      } else {
          metric <- tryCatch({
              switch(v_size_mode,
                  "degree"      = igraph::degree(g),
                  "log_degree"  = log1p(igraph::degree(g)),
                  "betweenness" = igraph::betweenness(g, normalized = TRUE),
                  "closeness"   = igraph::closeness(g, normalized = TRUE),
                  "eigen"       = igraph::eigen_centrality(g)$vector,
                  igraph::degree(g))
          }, error = function(e) igraph::degree(g))
          metric[!is.finite(metric)] <- 0
          rng <- range(metric, na.rm = TRUE)
          if (rng[2] - rng[1] < 1e-9) {
              # All nodes have the same metric -> fall back to mid-size
              rep((v_size_min + v_size_max) / 2, length(metric))
          } else {
              v_size_min + (v_size_max - v_size_min) *
                  (metric - rng[1]) / (rng[2] - rng[1])
          }
      }
      v_border  <- if (is.null(input$node_border) || !is.finite(input$node_border)) 1.5  else max(input$node_border, 0.1)
      v_fill    <- if (is.null(input$node_fill_color)   || !nzchar(input$node_fill_color))   "#DAA520" else input$node_fill_color
      v_bcol    <- if (is.null(input$node_border_color) || !nzchar(input$node_border_color)) "#333333" else input$node_border_color
      e_width   <- if (is.null(input$edge_width)  || !is.finite(input$edge_width))  0.6  else input$edge_width
      e_curved  <- if (is.null(input$edge_curved) || !is.finite(input$edge_curved)) 0.2  else input$edge_curved
      col_pos   <- if (is.null(input$edge_pos_color) || !nzchar(input$edge_pos_color)) "#27AE60" else input$edge_pos_color
      col_neg   <- if (is.null(input$edge_neg_color) || !nzchar(input$edge_neg_color)) "#E74C3C" else input$edge_neg_color

      # Edge colors: positive = green, negative = red
      e_colors <- if (igraph::ecount(g) > 0) {
        ifelse(igraph::E(g)$interaction == "Positive", col_pos, col_neg)
      } else {
        character(0)
      }

      # --- Plot the network ---
      plot(
        g,
        layout             = layout_coords,
        vertex.label       = NA,
        vertex.size        = v_size,
        vertex.color       = v_fill,
        vertex.frame.color = v_bcol,
        vertex.frame.width = v_border,
        edge.color         = e_colors,
        edge.width         = e_width,
        edge.curved        = e_curved,
        main               = paste0("Network (", input$method %||% "Spearman", ") \u2014 Layout: ",
                                    gsub("layout_", "", layout_func))
      )
    })
    
    # ==========================================================================
    # (Added 2026-04-16) Complete single-network outputs: centrality plots,
    # edge proportions, GraphML + CSV downloads, comparison-by-group tab,
    # and workflow-style detailed instructions.
    # ==========================================================================

    # --- Detailed on-panel instructions (shown above the network plot) ---
    output$detailed_instructions <- renderUI({
      res <- tryCatch(network_result(), error = function(e) NULL)
      if (is.null(res) || is.null(res$network) || igraph::vcount(res$network) == 0) {
        return(
          tags$div(
            class = "step-instruction",
            tags$strong("Build a co-occurrence network"),
            tags$p(HTML(
              "Pick a <b>metadata category</b> and one or more groups, choose a
               correlation method and threshold, then press <b>Run Network</b>.
               Edges are drawn between ASVs whose abundance correlates above the
               chosen cut-off; green = positive, red = negative."
            ))
          )
        )
      }
      g <- res$network
      n_nodes <- igraph::vcount(g)
      n_edges <- igraph::ecount(g)
      tags$div(
        class = "step-instruction",
        tags$strong("Network constructed"),
        tags$p(HTML(paste0(
          "Method: <b>", input$method %||% "Spearman", "</b> · Nodes (ASVs): <b>", n_nodes,
          "</b> · Edges: <b>", n_edges, "</b>. Inspect the <b>Statistics &amp; Plots</b>
           tab for centrality distributions, and the <b>Network Comparison</b>
           tab to compare this network across groups."
        )))
      )
    })

    # --- Node/Edge Stats reactive ---
    network_stats <- reactive({
      res <- network_result()
      req(res$network)
      calculate_stats_from_network(res$network, selected_physeq())
    })

    # ------------------------------------------------------------------
    # Network-level metrics (modularity, clustering, density, etc.)
    # The reviewer (2026) explicitly asked for a quantitative comparison
    # of network properties -- these are the canonical descriptors used
    # in published microbiome-network papers. Displayed in the new
    # "Network Statistics" tab and downloadable as CSV.
    # ------------------------------------------------------------------
    network_metrics <- reactive({
      res <- network_result()
      req(res$network)
      label <- paste0(input$method %||% "Spearman", " network")
      .compute_network_metrics(res$network, label = label)
    })

    output$network_metrics_table <- renderTable({
      m <- network_metrics()
      if (is.null(m)) return(NULL)
      # Two-column display (Metric | Value) is easier to read than the
      # original wide row.
      pretty_labels <- c(
        Network             = "Network label",
        N_nodes             = "Nodes (ASVs/taxa)",
        N_edges             = "Edges",
        Density             = "Edge density",
        Mean_degree         = "Mean degree",
        Median_degree       = "Median degree",
        Max_degree          = "Max degree",
        Avg_clustering_coef = "Avg. clustering coefficient",
        Modularity_louvain  = "Modularity (Louvain)",
        N_communities       = "Communities (Louvain)",
        Mean_path_length    = "Mean shortest-path length",
        N_components        = "Connected components",
        Largest_component   = "Largest component (nodes)",
        Assortativity_degree = "Assortativity (degree)",
        Pos_edges           = "Positive edges",
        Neg_edges           = "Negative edges"
      )
      vals <- as.character(unlist(m[1, ]))
      data.frame(
        Metric = pretty_labels[colnames(m)],
        Value  = vals,
        stringsAsFactors = FALSE
      )
    }, striped = TRUE, hover = TRUE, bordered = TRUE,
       width = "100%", spacing = "s")

    output$network_metrics_caption <- renderUI({
      res <- network_result()
      if (is.null(res) || is.null(res$network)) return(NULL)
      n_boot     <- res$n_bootstrap     %||% 0
      pthr       <- res$pval_threshold  %||% 0.05
      fdr        <- res$fdr_method      %||% "none"
      cor_thr    <- input$cor_threshold %||% 0.3
      method     <- input$method        %||% "Spearman"
      etest      <- res$edge_test       %||% "permutation"
      ci_lvl     <- res$ci_level
      etest_label <- switch(etest,
        "bootstrap_ci" = "Bootstrap CI",
        "permutation"  = "Permutation p-value",
        "none"         = "None (|r| only)",
        etest
      )
      tagList(
        p(style = "font-size:12px; color:#475569; margin:6px 0 12px;",
          tags$b("Method: "), method, " | ",
          tags$b("|r| threshold: "), round(cor_thr, 3), " | ",
          tags$b("Edge test: "), etest_label,
          if (n_boot > 0) {
            if (etest == "bootstrap_ci") {
              tagList(" | ",
                      tags$b("Bootstrap iterations: "), n_boot, " | ",
                      tags$b("CI level: "),
                      paste0(round(100 * (ci_lvl %||% 0.95)), "%"))
            } else if (etest == "permutation") {
              tagList(" | ",
                      tags$b("Bootstrap iterations: "), n_boot, " | ",
                      tags$b("p-value threshold: "), pthr, " | ",
                      tags$b("FDR: "), fdr)
            } else {
              NULL
            }
          } else {
            tagList(" | ",
                    tags$b("Bootstrap test: "), tags$em("disabled"),
                    " (effect-size only)")
          }
        )
      )
    })

    output$download_network_metrics <- downloadHandler(
      filename = function() ezmap_filename(
                                paste0("Network_Metrics_",
                                       input$method %||% "Spearman"),
                                "csv"),
      content = function(file) {
        m <- network_metrics()
        # Add the parameters used so the CSV is self-documenting.
        res <- network_result()
        params <- data.frame(
          Network = m$Network,
          Method            = input$method %||% "Spearman",
          Cor_threshold     = input$cor_threshold %||% 0.3,
          N_bootstrap       = res$n_bootstrap     %||% 0,
          P_threshold       = res$pval_threshold  %||% 0.05,
          FDR_method        = res$fdr_method      %||% "none",
          stringsAsFactors  = FALSE
        )
        out <- merge(m, params, by = "Network")
        write.csv(out, file, row.names = FALSE)
      }
    )

    # --- Centrality distribution plots ---
    make_centrality_plot <- function(df, col, title, fill_color) {
      ggplot(df, aes_string(x = col)) +
        geom_histogram(bins = 25, fill = fill_color, color = "white", alpha = 0.85) +
        theme_bw(base_size = 12) +
        labs(title = title, x = col, y = "Number of ASVs")
    }

    output$plot_degree <- renderPlot({
      stats <- network_stats()
      req(stats$node_stats)
      make_centrality_plot(stats$node_stats, "degree", "Degree", "#3498DB")
    })

    output$plot_betweenness <- renderPlot({
      stats <- network_stats()
      req(stats$node_stats)
      make_centrality_plot(stats$node_stats, "betweennesscentrality",
                           "Betweenness centrality", "#9B59B6")
    })

    output$plot_closeness <- renderPlot({
      stats <- network_stats()
      req(stats$node_stats)
      make_centrality_plot(stats$node_stats, "closenesscentrality",
                           "Closeness centrality", "#E67E22")
    })

    output$plot_eigen <- renderPlot({
      stats <- network_stats()
      req(stats$node_stats)
      make_centrality_plot(stats$node_stats, "eigencentrality",
                           "Eigenvector centrality", "#27AE60")
    })

    output$plot_edge_proportions <- renderPlot({
      stats <- network_stats()
      req(stats$edge_proportions)
      df <- stats$edge_proportions
      if (nrow(df) == 0 || sum(df$Count) == 0) {
        return(
          ggplot() + theme_void() +
            annotate("text", x = 0, y = 0,
                     label = "No edges in the current network -- try a lower correlation threshold.",
                     size = 5, color = "grey40")
        )
      }
      ggplot(df, aes(x = Interaction, y = Proportion, fill = Interaction)) +
        geom_col(width = 0.6) +
        geom_text(aes(label = paste0(Count, "\n(", round(Proportion * 100, 1), "%)")),
                  vjust = -0.3, size = 4) +
        scale_fill_manual(values = c("Positive" = "#27AE60", "Negative" = "#E74C3C")) +
        scale_y_continuous(labels = scales::percent, limits = c(0, 1.15)) +
        theme_bw(base_size = 13) +
        labs(title = "Proportion of positive vs. negative edges",
             x = NULL, y = "Proportion of edges")
    })

    # --- Downloads ---
    output$download_network_graphml <- downloadHandler(
      filename = function() ezmap_filename(paste0("Network_", input$method %||% "Spearman"), "graphml"),
      content = function(file) {
        res <- network_result()
        req(res$network)
        igraph::write_graph(res$network, file, format = "graphml")
      }
    )

    output$download_node_stats <- downloadHandler(
      filename = function() ezmap_filename(paste0("NodeStatistics_", input$method %||% "Spearman"), "csv"),
      content = function(file) {
        stats <- network_stats()
        req(stats$node_stats)
        write.csv(stats$node_stats, file, row.names = FALSE)
      }
    )

    # ------------------------------------------------------------------------
    # Network comparison across all levels of the chosen category
    # ------------------------------------------------------------------------
    # Use reactiveVal + observeEvent instead of eventReactive so we can:
    #   (a) switch the user to the "Group Comparison" tab automatically,
    #   (b) store a result even on failure (empty df) so spinners resolve,
    #   (c) surface diagnostics clearly.
    comparison_rv      <- reactiveVal(NULL)
    comparison_edge_rv <- reactiveVal(NULL)

    observeEvent(input$run_comparison, {
      cat("[Network] Group comparison button clicked\n")

      # Guard: need category & method
      if (is.null(input$category) || input$category == "") {
        showNotification("Please select a metadata category first.",
                         type = "error", duration = 6)
        return()
      }

      # Auto-switch to the Group Comparison tab so user sees progress / result
      updateTabsetPanel(session, "network_tabs", selected = "Group Comparison")

      pseq_all <- tryCatch(preprocessed_physeq(), error = function(e) NULL)
      if (is.null(pseq_all)) {
        showNotification("No data loaded -- upload a phyloseq object first.",
                         type = "error", duration = 6)
        return()
      }

      metadata <- as(sample_data(pseq_all), "data.frame")
      groups <- sort(unique(na.omit(as.character(metadata[[input$category]]))))
      cat("[Network] Groups found for comparison:", paste(groups, collapse = ", "), "\n")

      if (length(groups) < 2) {
        showNotification(
          paste0("Group comparison needs >= 2 levels in '", input$category,
                 "', found ", length(groups), "."),
          type = "error", duration = 8)
        comparison_rv(data.frame())
        return()
      }

      method_val    <- input$method %||% "Spearman"
      threshold_val <- input$cor_threshold %||% 0.3

      withProgress(message = "Comparing networks across groups...", value = 0.05, {
        all_stats <- list()
        all_edges <- list()
        skipped   <- character(0)
        failed    <- character(0)

        for (i in seq_along(groups)) {
          grp <- groups[i]
          incProgress(1 / (length(groups) + 1),
                      detail = paste("Building network for:", grp))

          keep <- rownames(metadata)[metadata[[input$category]] == grp]
          sub  <- tryCatch({
            s <- prune_samples(keep, pseq_all)
            prune_taxa(taxa_sums(s) > 0, s)
          }, error = function(e) NULL)

          if (is.null(sub) || ntaxa(sub) < 3 || nsamples(sub) < 3) {
            skipped <- c(skipped, paste0(grp, " (<3 samples or taxa)"))
            cat("[Network]  Skipped group:", grp, "(too few samples/taxa)\n")
            next
          }

          net_res <- tryCatch(
            build_network_for_group(sub, method_val, threshold_val, NULL),
            error = function(e) {
              cat("[Network]  ERROR building network for", grp, ":", e$message, "\n")
              failed <<- c(failed, paste0(grp, ": ", e$message))
              NULL
            }
          )
          if (is.null(net_res)) next

          if (igraph::vcount(net_res$network) == 0) {
            skipped <- c(skipped, paste0(grp, " (empty network)"))
            cat("[Network]  Skipped group:", grp, "(0 nodes)\n")
            next
          }

          s <- tryCatch(
            calculate_stats_from_network(net_res$network, sub),
            error = function(e) {
              cat("[Network]  ERROR calculating stats for", grp, ":", e$message, "\n")
              failed <<- c(failed, paste0(grp, " stats: ", e$message))
              NULL
            }
          )
          if (is.null(s)) next

          s$node_stats$Group <- grp
          all_stats[[grp]] <- s$node_stats

          # Collect edge proportions for this group
          ep <- s$edge_proportions
          ep$Group <- grp
          all_edges[[grp]] <- ep

          cat("[Network]  Group", grp, "OK --", nrow(s$node_stats), "nodes,",
              sum(ep$Count), "edges\n")
        }
        incProgress(1, detail = "Done")
      })

      # Surface diagnostics
      if (length(failed) > 0)
        showNotification(paste0("Errors: ", paste(failed, collapse = "; ")),
                         type = "error", duration = 12)
      if (length(skipped) > 0)
        showNotification(paste0("Skipped: ", paste(skipped, collapse = "; ")),
                         type = "warning", duration = 10)

      if (length(all_stats) == 0) {
        showNotification(
          "No usable networks -- try a lower correlation threshold or different category.",
          type = "error", duration = 10)
        comparison_rv(data.frame())
        comparison_edge_rv(data.frame())
        return()
      }

      result_df <- tryCatch(do.call(rbind, all_stats), error = function(e) {
        showNotification(paste("Error combining results:", e$message),
                         type = "error", duration = 10)
        data.frame()
      })
      edge_df <- tryCatch(do.call(rbind, all_edges), error = function(e) data.frame())
      cat("[Network] Comparison complete --", nrow(result_df), "total rows,",
          length(unique(result_df$Group)), "groups\n")
      comparison_rv(result_df)
      comparison_edge_rv(edge_df)
    })

    # Shared helper: returns a ggplot or a "no data" placeholder
    make_comparison_plot <- function(df, col, title) {
      if (is.null(df) || nrow(df) == 0 || !col %in% names(df)) {
        return(
          ggplot() + theme_void() +
            annotate("text", x = 0.5, y = 0.5,
                     label = "No comparison data.\nClick 'Run Group Comparison'.",
                     size = 5, color = "grey50")
        )
      }
      ggplot(df, aes_string(x = "Group", y = col, fill = "Group")) +
        geom_boxplot(outlier.alpha = 0.4, alpha = 0.8) +
        geom_jitter(width = 0.15, size = 1, alpha = 0.5) +
        scale_fill_brewer(palette = "Set2") +
        theme_bw(base_size = 13) +
        theme(legend.position = "none") +
        labs(title = title, x = NULL, y = col)
    }

    output$comparison_plot_degree <- renderPlot({
      df <- comparison_rv()
      make_comparison_plot(df, "degree", "Degree by group")
    })

    output$comparison_plot_betweenness <- renderPlot({
      df <- comparison_rv()
      make_comparison_plot(df, "betweennesscentrality", "Betweenness by group")
    })

    output$comparison_plot_closeness <- renderPlot({
      df <- comparison_rv()
      make_comparison_plot(df, "closenesscentrality", "Closeness by group")
    })

    output$comparison_plot_eigen <- renderPlot({
      df <- comparison_rv()
      make_comparison_plot(df, "eigencentrality", "Eigenvector centrality by group")
    })

    output$comparison_plot_edge_props <- renderPlot({
      df <- comparison_edge_rv()
      if (is.null(df) || nrow(df) == 0 ||
          !all(c("Interaction", "Count", "Group") %in% names(df))) {
        return(
          ggplot() + theme_void() +
            annotate("text", x = 0.5, y = 0.5,
                     label = "No edge data.\nClick 'Run Group Comparison'.",
                     size = 5, color = "grey50")
        )
      }

      # Grouped bar chart: count of positive vs negative edges per group
      ggplot(df, aes(x = Group, y = Count, fill = Interaction)) +
        geom_col(position = position_dodge(width = 0.7), width = 0.6) +
        geom_text(aes(label = Count),
                  position = position_dodge(width = 0.7),
                  vjust = -0.4, size = 3.5) +
        scale_fill_manual(values = c("Positive" = "#27AE60", "Negative" = "#E74C3C")) +
        theme_bw(base_size = 13) +
        labs(title = "Positive vs. Negative Edge Counts by Group",
             x = NULL, y = "Number of edges", fill = "Interaction")
    })
  })
}