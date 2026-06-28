#!/bin/bash
# =============================================================================
# EzMAP2 — Easy Mode pipeline (upstream only)
# =============================================================================
# QIIME2 16S/ITS amplicon analysis: FASTQ → BIOM + taxonomy bundle.
# Upstream stops at taxonomy assignment. All downstream analysis
# (diversity, differential abundance, RF, network, functional prediction)
# is handled by the EzMAP2 Shiny app.
#
# Pipeline steps:
#   1. Manifest generation + FASTQ type detection + sample ID reconciliation
#   2. Import reads into QIIME2
#   3. Primer removal (Cutadapt)
#   4. Quality-driven trim length selection
#   5. Denoising (DADA2 or Deblur)
#   6. Phylogenetic tree (MAFFT + FastTree)
#   7. Taxonomy classification (sklearn naive Bayes)
#   → Bundle: feature-table.biom (with taxonomy), taxonomy.tsv,
#             rooted-tree.nwk, rep-seqs.fasta, metadata.tsv,
#             denoising-stats.tsv, parameters.json
#
# Required args:
#   --fastq-dir  <path>   Directory containing paired FASTQ files
#   --metadata   <path>   QIIME2-compatible metadata TSV
#   --output-dir <path>   Output directory (will be created)
#
# Optional args:
#   --amplicon   <string> 16S-V3V4 (default) | 16S-V4 | ITS1 | ITS2
#   --threads    <int>    CPU threads (default: 4)
#   --env-name   <string> Conda env (default: EzMAP2-qiime2)
#   --classifier <path>   Pre-trained sklearn classifier .qza
#   --min-q-fwd  <int>    Smart-trim forward Q floor (default: 25)
#   --min-q-rev  <int>    Smart-trim reverse Q floor (default: 20)
#   --min-len    <int>    Smart-trim minimum length (default: 150)
#   --skip <step,step>    Comma-separated steps to skip
#   --resume              Skip steps whose outputs already exist
#   --denoiser   <string> dada2 (default) | deblur
#   --low-memory          Force single-threaded DADA2 (safer on <16 GB RAM)
#
# Example:
#   ./easy_mode.sh --fastq-dir /data/fastq --metadata /data/meta.tsv \
#                  --output-dir ~/EzMAP2_results --amplicon 16S-V3V4 --threads 8
# =============================================================================

set -euo pipefail

# ---- Colors ----
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()    { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()     { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
warn()   { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $*"; }
die()    { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*" >&2; exit 1; }

# ---- Defaults ----
FASTQ_DIR=""; METADATA=""; OUTPUT_DIR=""
AMPLICON="16S-V3V4"
THREADS=4
ENV_NAME="EzMAP2-qiime2"
CLASSIFIER=""
MIN_Q_FWD=25; MIN_Q_REV=20; MIN_LEN=150
SKIP_STEPS=""
RESUME=false
DENOISER="dada2"        # dada2 | deblur
DADA2_THREADS=""        # empty -> falls back to $THREADS
LOW_MEMORY=false        # forces DADA2 single-threaded + sets sane defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fastq-dir)        FASTQ_DIR="$2"; shift 2 ;;
        --metadata)         METADATA="$2"; shift 2 ;;
        --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
        --amplicon)         AMPLICON="$2"; shift 2 ;;
        --threads)          THREADS="$2"; shift 2 ;;
        --env-name)         ENV_NAME="$2"; shift 2 ;;
        --classifier)       CLASSIFIER="$2"; shift 2 ;;
        --min-q-fwd)        MIN_Q_FWD="$2"; shift 2 ;;
        --min-q-rev)        MIN_Q_REV="$2"; shift 2 ;;
        --min-len)          MIN_LEN="$2"; shift 2 ;;
        --skip)             SKIP_STEPS="$2"; shift 2 ;;
        --resume)           RESUME=true; shift ;;
        --denoiser)         DENOISER="$2"; shift 2 ;;
        --dada2-threads)    DADA2_THREADS="$2"; shift 2 ;;
        --low-memory)       LOW_MEMORY=true; shift ;;
        -h|--help)          sed -n '2,40p' "$0"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# Validate denoiser choice
case "$DENOISER" in
    dada2|deblur) ;;
    *) die "Unknown --denoiser: $DENOISER (choose dada2 | deblur)" ;;
esac

# Low-memory mode: override heavy settings
if $LOW_MEMORY; then
    DADA2_THREADS=1
fi
# Default DADA2 threads to the global thread count if not explicitly set
[[ -z "$DADA2_THREADS" ]] && DADA2_THREADS="$THREADS"

[[ -z "$FASTQ_DIR"  ]] && die "--fastq-dir is required"
[[ -z "$METADATA"   ]] && die "--metadata is required"
[[ -z "$OUTPUT_DIR" ]] && die "--output-dir is required"
[[ -d "$FASTQ_DIR"  ]] || die "FASTQ dir not found: $FASTQ_DIR"
[[ -f "$METADATA"   ]] || die "Metadata file not found: $METADATA"

mkdir -p "$OUTPUT_DIR"/{qza,qzv,bundle,logs}
LOG_FILE="$OUTPUT_DIR/logs/pipeline.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---- Helpers ----
skipped() { [[ ",$SKIP_STEPS," == *",$1,"* ]]; }
exists()  { [[ -e "$1" ]]; }
step_needs_run() {
    local out="$1"
    if $RESUME && exists "$out"; then
        ok "Skipping (already exists): $(basename "$out")"
        return 1
    fi
    return 0
}

# ---- Primers ----
case "$AMPLICON" in
    16S-V3V4) FWD_PRIMER="CCTACGGGNGGCWGCAG";           REV_PRIMER="GACTACHVGGGTATCTAATCC" ;;
    16S-V4)   FWD_PRIMER="GTGYCAGCMGCCGCGGTAA";         REV_PRIMER="GGACTACNVGGGTWTCTAAT" ;;
    ITS1)     FWD_PRIMER="CTTGGTCATTTAGAGGAAGTAA";      REV_PRIMER="GCTGCGTTCTTCATCGATGC"  ;;
    ITS2)     FWD_PRIMER="GCATCGATGAAGAACGCAGC";        REV_PRIMER="TCCTCCGCTTATTGATATGC"  ;;
    *) die "Unknown --amplicon: $AMPLICON (choose 16S-V3V4 | 16S-V4 | ITS1 | ITS2)" ;;
esac

log "============================================================"
log "EzMAP2 Easy Mode pipeline"
log "============================================================"
log "FASTQ dir    : $FASTQ_DIR"
log "Metadata     : $METADATA"
log "Output dir   : $OUTPUT_DIR"
log "Amplicon     : $AMPLICON  (fwd=$FWD_PRIMER, rev=$REV_PRIMER)"
log "Denoiser     : $DENOISER  (dada2 threads: $DADA2_THREADS${LOW_MEMORY:+, low-memory mode})"
log "Threads      : $THREADS"
log "============================================================"

# ---- Activate conda env ----
if [[ -z "${CONDA_PREFIX:-}" ]] || [[ "${CONDA_DEFAULT_ENV:-}" != "$ENV_NAME" ]]; then
    log "Activating conda env: $ENV_NAME"
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME" || die "Failed to activate $ENV_NAME. Run install.sh first."
fi
command -v qiime >/dev/null || die "qiime command not found; conda env is not correct."

QIIME_VERSION=$(qiime --version 2>&1 | head -1 | sed 's/q2cli version //')
ok "QIIME2 ready: $QIIME_VERSION"

# ============================================================
# STEP 1  —  Manifest + FASTQ type detection + ID reconciliation
# ============================================================
# Place manifest & metadata outputs in the OUTPUT directory so user can find them
MANIFEST="$OUTPUT_DIR/samples_manifest.tsv"
FASTQ_TYPE_JSON="$OUTPUT_DIR/fastq_type.json"
RECON_JSON="$OUTPUT_DIR/reconciliation.json"

if ! skipped "manifest"; then
    if step_needs_run "$MANIFEST"; then
        log "[1/7] Detecting FASTQ type and generating manifest…"
        GEN_SCRIPT="$SCRIPT_DIR/../generate_manifest.py"
        [[ -f "$GEN_SCRIPT" ]] || GEN_SCRIPT="$SCRIPT_DIR/generate_manifest.py"

        # Pass --metadata so the script can:
        #   1) detect FASTQ format (writes fastq_type.json)
        #   2) reconcile sample IDs (writes reconciliation.json)
        #   3) remap manifest IDs to match metadata if needed
        python3 "$GEN_SCRIPT" "$FASTQ_DIR" "$MANIFEST" --metadata "$METADATA"

        # Show detected FASTQ type
        if [[ -f "$FASTQ_TYPE_JSON" ]]; then
            DETECTED_FORMAT=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('format','unknown'))" 2>/dev/null || echo "unknown")
            DETECTED_TYPE=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('type','unknown'))" 2>/dev/null || echo "unknown")
            DETECTED_PAIRED=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('paired',False))" 2>/dev/null || echo "unknown")
            DETECTED_FILES=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('files_found',0))" 2>/dev/null || echo "0")

            ok "FASTQ type detected:"
            log "  Format:      $DETECTED_FORMAT"
            log "  QIIME2 type: $DETECTED_TYPE"
            log "  Paired-end:  $DETECTED_PAIRED"
            log "  Files found: $DETECTED_FILES"
        fi

        # Show reconciliation summary
        if [[ -f "$RECON_JSON" ]]; then
            ALL_MATCHED=$(python3 -c "import json; d=json.load(open('$RECON_JSON')); print(d.get('all_matched',False))" 2>/dev/null || echo "False")
            if [[ "$ALL_MATCHED" == "True" ]]; then
                ok "Sample ID reconciliation: all IDs matched."
            else
                warn "Sample ID reconciliation: some IDs could not be matched."
                warn "Check reconciliation.json for details: $RECON_JSON"
            fi
        fi

        # Safety net: if an older build wrote the manifest elsewhere (legacy)
        if [[ ! -f "$MANIFEST" ]]; then
            for cand in \
                "$FASTQ_DIR/samples_manifest.tsv" \
                "$PWD/samples_manifest.tsv" \
                "$SCRIPT_DIR/../samples_manifest.tsv" \
                "$SCRIPT_DIR/samples_manifest.tsv"; do
                if [[ -f "$cand" ]]; then
                    mv "$cand" "$MANIFEST"
                    break
                fi
            done
        fi

        [[ -f "$MANIFEST" ]] || die "Manifest not produced at $MANIFEST"
        ok "Manifest: $MANIFEST"
    fi
fi

# ============================================================
# PRE-FLIGHT  —  Validate sample IDs (manifest vs metadata)
# ============================================================
# This check runs BEFORE any expensive QIIME2 steps so the user
# gets an immediate, actionable error if the IDs don't match.
if [[ -f "$MANIFEST" ]] && [[ -f "$METADATA" ]]; then
    log "Pre-flight: Validating sample IDs (manifest ↔ metadata)…"

    # Extract sample IDs from manifest (column 1, skip header)
    MANIFEST_IDS=$(tail -n +2 "$MANIFEST" | cut -f1 | sort -u)

    # Extract sample IDs from metadata (column 1, skip header and #q2:types row)
    METADATA_IDS=$(tail -n +2 "$METADATA" | grep -v '^#q2:types' | cut -f1 | sort -u)

    # Find IDs in manifest but NOT in metadata
    ONLY_IN_MANIFEST=$(comm -23 <(echo "$MANIFEST_IDS") <(echo "$METADATA_IDS"))
    # Find IDs in metadata but NOT in manifest
    ONLY_IN_METADATA=$(comm -13 <(echo "$MANIFEST_IDS") <(echo "$METADATA_IDS"))

    ERRORS=0

    if [[ -n "$ONLY_IN_MANIFEST" ]]; then
        warn "These sample IDs are in the FASTQ manifest but MISSING from your metadata file:"
        echo "$ONLY_IN_MANIFEST" | while read -r sid; do
            echo -e "    ${RED}✗${NC}  $sid"
        done
        ERRORS=1
    fi

    if [[ -n "$ONLY_IN_METADATA" ]]; then
        warn "These sample IDs are in the metadata but have NO matching FASTQ files:"
        echo "$ONLY_IN_METADATA" | while read -r sid; do
            echo -e "    ${YELLOW}?${NC}  $sid"
        done
        # Extras in metadata are a warning, not fatal — QIIME2 tolerates them
        warn "(Extra metadata rows are tolerated by QIIME2, but check for typos.)"
    fi

    if [[ $ERRORS -eq 1 ]]; then
        echo ""
        warn "╔══════════════════════════════════════════════════════════════╗"
        warn "║  SAMPLE ID MISMATCH — pipeline cannot continue.            ║"
        warn "║                                                            ║"
        warn "║  The sample IDs in your FASTQ filenames do not match the   ║"
        warn "║  sample IDs in your metadata file.                         ║"
        warn "║                                                            ║"
        warn "║  How to fix:                                               ║"
        warn "║  1. Open your metadata TSV and check the 'sample-id'       ║"
        warn "║     column (first column).                                 ║"
        warn "║  2. Ensure each FASTQ file's sample ID matches exactly.    ║"
        warn "║     FASTQ naming convention:  <SampleID>_R1.fastq.gz      ║"
        warn "║                          or:  <SampleID>.R1.fastq.gz      ║"
        warn "║  3. Manifest file for reference: $MANIFEST                 ║"
        warn "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        die "Fix the sample IDs above and re-run the pipeline."
    fi

    MATCHED=$(comm -12 <(echo "$MANIFEST_IDS") <(echo "$METADATA_IDS") | wc -l)
    ok "Pre-flight passed: $MATCHED samples matched between manifest and metadata."
fi

# ============================================================
# STEP 2  —  Import (auto-detected format)
# ============================================================
DEMUX_QZA="$OUTPUT_DIR/qza/demux.qza"
if ! skipped "import"; then
    if step_needs_run "$DEMUX_QZA"; then
        # Read detected format from fastq_type.json (if available)
        IMPORT_FORMAT="PairedEndFastqManifestPhred33V2"
        IMPORT_TYPE="SampleData[PairedEndSequencesWithQuality]"
        IMPORT_SOURCE="$MANIFEST"

        if [[ -f "$FASTQ_TYPE_JSON" ]]; then
            DETECTED_FORMAT=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('format',''))" 2>/dev/null || echo "")
            DETECTED_TYPE=$(python3 -c "import json; d=json.load(open('$FASTQ_TYPE_JSON')); print(d.get('type',''))" 2>/dev/null || echo "")

            if [[ -n "$DETECTED_FORMAT" && -n "$DETECTED_TYPE" ]]; then
                IMPORT_FORMAT="$DETECTED_FORMAT"
                IMPORT_TYPE="$DETECTED_TYPE"

                # For directory-based formats (Casava, EMP), import from the FASTQ dir
                case "$IMPORT_FORMAT" in
                    CasavaOneEightSingleLanePerSampleDirFmt|EMPPairedEndDirFmt)
                        IMPORT_SOURCE="$FASTQ_DIR"
                        ;;
                esac
            fi
        fi

        log "[2/7] Importing reads…"
        log "  Format: $IMPORT_FORMAT"
        log "  Type:   $IMPORT_TYPE"
        log "  Source: $IMPORT_SOURCE"

        qiime tools import \
            --type "$IMPORT_TYPE" \
            --input-path "$IMPORT_SOURCE" \
            --output-path "$DEMUX_QZA" \
            --input-format "$IMPORT_FORMAT"
        ok "Imported: $DEMUX_QZA"
    fi
fi

# ============================================================
# STEP 3  —  Primer removal (cutadapt)
# ============================================================
TRIMMED_QZA="$OUTPUT_DIR/qza/demux-trimmed.qza"
TRIMMED_QZV="$OUTPUT_DIR/qzv/demux-trimmed.qzv"
if ! skipped "cutadapt"; then
    if step_needs_run "$TRIMMED_QZA"; then
        log "[3/7] Removing primers (cutadapt)…"
        qiime cutadapt trim-paired \
            --i-demultiplexed-sequences "$DEMUX_QZA" \
            --p-front-f "$FWD_PRIMER" \
            --p-front-r "$REV_PRIMER" \
            --p-discard-untrimmed \
            --p-minimum-length 50 \
            --p-cores "$THREADS" \
            --o-trimmed-sequences "$TRIMMED_QZA" \
            --verbose
        ok "Primers removed."
    fi
    if step_needs_run "$TRIMMED_QZV"; then
        log "  Building quality visualization artifact (this may take 1–2 minutes)…"
        qiime demux summarize \
            --i-data "$TRIMMED_QZA" \
            --o-visualization "$TRIMMED_QZV"
        ok "Quality summary: $TRIMMED_QZV"
    fi
fi

# ============================================================
# STEP 4  —  Smart trim  (quality-driven)
# ============================================================
TRIM_JSON="$OUTPUT_DIR/logs/smart_trim.json"
if ! skipped "smart-trim"; then
    log "[4/7] Choosing DADA2 trim lengths (quality-driven)…"

    # Per-amplicon fallback truncation lengths (used if smart_trim.py fails
    # to parse the .qzv — e.g. when QIIME 2 changes the visualization
    # layout, or for ITS variable-length reads where the quality table
    # may not be informative). Keep these in sync with the SMART_TRIM
    # array in src-build/.../pages/DenoisingPage.java.
    case "$AMPLICON" in
        16S-V3V4) FALLBACK_F=260; FALLBACK_R=220 ;;
        16S-V4)   FALLBACK_F=230; FALLBACK_R=200 ;;
        ITS1|ITS2) FALLBACK_F=0;   FALLBACK_R=0  ;;
        *)        FALLBACK_F=0;   FALLBACK_R=0  ;;
    esac

    set +e
    python3 "$SCRIPT_DIR/smart_trim.py" "$TRIMMED_QZV" \
        --min-q-fwd "$MIN_Q_FWD" --min-q-rev "$MIN_Q_REV" --min-len "$MIN_LEN" \
        --output "$TRIM_JSON" >/dev/null
    smart_trim_rc=$?
    set -e

    if [[ $smart_trim_rc -ne 0 ]] || [[ ! -s "$TRIM_JSON" ]]; then
        warn "smart_trim.py could not parse $TRIMMED_QZV (exit $smart_trim_rc)."
        warn "Falling back to per-amplicon defaults for $AMPLICON: trunc-len-f=$FALLBACK_F  trunc-len-r=$FALLBACK_R"
        warn "These match the Expert-mode UI defaults; review your demux quality plot before publishing."
        TRUNC_F=$FALLBACK_F
        TRUNC_R=$FALLBACK_R
        FWD_LEN=0
        REV_LEN=0
        # Write a minimal JSON so the bundle's parameters.json still
        # carries a valid smart_trim block.
        mkdir -p "$(dirname "$TRIM_JSON")"
        cat > "$TRIM_JSON" <<JSON
{
  "forward_trunc": $TRUNC_F,
  "reverse_trunc": $TRUNC_R,
  "forward_length": 0,
  "reverse_length": 0,
  "method": "fallback-per-amplicon-default",
  "amplicon": "$AMPLICON",
  "note": "smart_trim.py exited $smart_trim_rc; fell back to per-amplicon defaults"
}
JSON
    else
        TRUNC_F=$(python3 -c "import json;print(json.load(open('$TRIM_JSON'))['forward_trunc'])")
        TRUNC_R=$(python3 -c "import json;print(json.load(open('$TRIM_JSON'))['reverse_trunc'])")
        FWD_LEN=$(python3 -c "import json;print(json.load(open('$TRIM_JSON'))['forward_length'])")
        REV_LEN=$(python3 -c "import json;print(json.load(open('$TRIM_JSON'))['reverse_length'])")
    fi

    # Safety checks for trunc lengths
    # 1. Must not exceed actual read lengths
    if [[ "$TRUNC_F" -gt "$FWD_LEN" ]]; then
        warn "trunc-len-f ($TRUNC_F) exceeds forward read length ($FWD_LEN) — setting to 0 (no truncation)."
        TRUNC_F=0
    fi
    if [[ "$TRUNC_R" -gt "$REV_LEN" ]] && [[ "$REV_LEN" -gt 0 ]]; then
        warn "trunc-len-r ($TRUNC_R) exceeds reverse read length ($REV_LEN) — setting to 0 (no truncation)."
        TRUNC_R=0
    fi
    # 2. If trunc is >= 95% of read length, no point truncating — use 0 (full length)
    #    This avoids edge cases where reads vary slightly in length after Cutadapt
    if [[ "$FWD_LEN" -gt 0 ]] && [[ "$TRUNC_F" -gt 0 ]]; then
        threshold=$(( FWD_LEN * 95 / 100 ))
        if [[ "$TRUNC_F" -ge "$threshold" ]]; then
            log "  trunc-len-f ($TRUNC_F) is ≥95% of read length ($FWD_LEN) — using 0 (no truncation)."
            TRUNC_F=0
        fi
    fi
    if [[ "$REV_LEN" -gt 0 ]] && [[ "$TRUNC_R" -gt 0 ]]; then
        threshold=$(( REV_LEN * 95 / 100 ))
        if [[ "$TRUNC_R" -ge "$threshold" ]]; then
            log "  trunc-len-r ($TRUNC_R) is ≥95% of read length ($REV_LEN) — using 0 (no truncation)."
            TRUNC_R=0
        fi
    fi

    # 3. ITS-specific override: ITS1 / ITS2 are length-variable amplicons
    #    (~150–500+ bp). The seven-number summary of read quality reflects
    #    only reads that REACH each position, so smart_trim's "median
    #    Q < 25" cut-off systematically picks truncation lengths longer
    #    than the majority of reads. DADA2 then hard-truncates and DROPS
    #    every read shorter than --p-trunc-len-f, leaving an empty (or
    #    near-empty) table and the run dies.
    #
    #    The Bokulich-Caporaso ITS workflow (and the Expert-mode UI's
    #    per-amplicon SMART_TRIM table at DenoisingPage.java line 94-95)
    #    both pass 0 / 0 for ITS so DADA2 keeps reads at their natural
    #    variable lengths. Mirror that here so Easy Mode behaves the
    #    same way and ITS runs no longer fail.
    case "$AMPLICON" in
        ITS1|ITS2)
            if [[ "$TRUNC_F" -ne 0 ]] || [[ "$TRUNC_R" -ne 0 ]]; then
                warn "ITS amplicon detected — overriding smart_trim suggestion ($TRUNC_F / $TRUNC_R) to 0 / 0."
                warn "ITS reads are length-variable; fixed truncation drops most reads and breaks DADA2."
                warn "This matches the Expert-mode default and the Bokulich-Caporaso ITS workflow."
            fi
            TRUNC_F=0
            TRUNC_R=0
            ;;
    esac

    ok "trunc-len-f=$TRUNC_F  trunc-len-r=$TRUNC_R  (reads: fwd=${FWD_LEN}bp, rev=${REV_LEN}bp)"
fi

# ============================================================
# STEP 4b  —  Barcode / linker auto-detection
# ============================================================
# Mirrors the Expert-mode "Apply Suggestions" button on the Denoising
# page. Some library-prep kits leave a non-biological prefix (sample
# barcode + linker) at the 5' end of reads even after Cutadapt has
# stripped the primer — Cutadapt's --p-front-f matches the primer
# fuzzily but cannot strip a 16+bp barcode that precedes it. The
# detector samples FASTQ from the demux-trimmed.qza, runs cross-sample
# disagreement + primer-motif search, and outputs suggested
# trim-left-f / trim-left-r values. We feed those to DADA2 below.
# Without this step, ITS runs with linker-prefixed reads die with an
# empty DADA2 table.
TRIM_LEFT_F=0
TRIM_LEFT_R=0
DETECT_JSON="$OUTPUT_DIR/logs/detect_barcode.json"
if ! skipped "barcode-detect"; then
    log "[4b/7] Auto-detecting barcode / linker prefixes (Easy Mode)…"
    set +e
    python3 "$SCRIPT_DIR/detect_barcode.py" "$TRIMMED_QZA" \
        --output "$DETECT_JSON" >/dev/null
    detect_rc=$?
    set -e
    if [[ $detect_rc -ne 0 ]] || [[ ! -s "$DETECT_JSON" ]]; then
        warn "Barcode auto-detection failed (exit $detect_rc) — proceeding with trim-left = 0 / 0."
    else
        TRIM_LEFT_F=$(python3 -c "import json;print(json.load(open('$DETECT_JSON')).get('trim_left_f',0))")
        TRIM_LEFT_R=$(python3 -c "import json;print(json.load(open('$DETECT_JSON')).get('trim_left_r',0))")
        DETECTED=$(python3 -c "import json;print(json.load(open('$DETECT_JSON')).get('detected',False))")
        FWD_DET=$(python3 -c "import json;print(json.load(open('$DETECT_JSON')).get('forward_detail',''))")
        REV_DET=$(python3 -c "import json;print(json.load(open('$DETECT_JSON')).get('reverse_detail',''))")
        if [[ "$DETECTED" == "True" ]]; then
            ok "Barcode/linker detected — applying trim-left to DADA2:"
            ok "    trim-left-f = $TRIM_LEFT_F  ($FWD_DET)"
            [[ -n "$REV_DET" ]] && ok "    trim-left-r = $TRIM_LEFT_R  ($REV_DET)"
        else
            ok "No barcode/linker detected — using trim-left = 0 / 0."
        fi
    fi
fi

# ============================================================
# STEP 5  —  Denoising  (DADA2 or Deblur)
# ============================================================
TABLE_QZA="$OUTPUT_DIR/qza/table.qza"
REPSEQ_QZA="$OUTPUT_DIR/qza/rep-seqs.qza"
STATS_QZA="$OUTPUT_DIR/qza/dada2-stats.qza"   # DADA2 path only

if ! skipped "denoise"; then
    if step_needs_run "$TABLE_QZA"; then

        if [[ "$DENOISER" == "dada2" ]]; then
            log "[5/7] DADA2 denoising (threads=$DADA2_THREADS)…"
            log "  This is the slowest step — typically 5–30 minutes depending on data size."
            log "  DADA2 stages: 1) Filtering → 2) Learning error rates → 3) Denoising → 4) Chimera removal"
            log "  The process is running; please wait…"
            # Detect OOM kills (exit 137 / signal 15) and hint at low-memory mode.
            set +e
            # NOTE: Easy Mode passes EVERY DADA2 quality-filtering parameter
            # explicitly — even those whose values match the QIIME 2 / DADA2
            # built-in defaults — so Easy and Expert Modes are reproducibly
            # identical and a future QIIME 2 release that changes a default
            # cannot silently drift Easy Mode away from the Expert Mode UI.
            # The four pinned values (max-ee 2.0/2.0, trunc-q 2,
            # min-fold-parent-over-abundance 1.0) match the spinner defaults
            # in src-build/.../pages/DenoisingPage.java.
            qiime dada2 denoise-paired \
                --i-demultiplexed-seqs "$TRIMMED_QZA" \
                --p-trim-left-f "$TRIM_LEFT_F" \
                --p-trim-left-r "$TRIM_LEFT_R" \
                --p-trunc-len-f "$TRUNC_F" \
                --p-trunc-len-r "$TRUNC_R" \
                --p-max-ee-f 2.0 \
                --p-max-ee-r 2.0 \
                --p-trunc-q 2 \
                --p-chimera-method consensus \
                --p-min-fold-parent-over-abundance 1.0 \
                --p-n-threads "$DADA2_THREADS" \
                --o-table "$TABLE_QZA" \
                --o-representative-sequences "$REPSEQ_QZA" \
                --o-denoising-stats "$STATS_QZA" \
                --verbose
            rc=$?
            set -e
            if [[ $rc -ne 0 ]]; then
                if [[ $rc -eq 137 || $rc -eq 143 ]] || [[ ! -f "$TABLE_QZA" ]]; then
                    warn "DADA2 was killed (likely out-of-memory)."
                    warn "Retry with --low-memory (forces single-threaded DADA2),"
                    warn "or switch denoiser to deblur (--denoiser deblur)."
                fi
                die "DADA2 failed with exit code $rc."
            fi

            log "  Generating DADA2 statistics visualization…"
            qiime metadata tabulate \
                --m-input-file "$STATS_QZA" \
                --o-visualization "$OUTPUT_DIR/qzv/dada2-stats.qzv"
            ok "DADA2 denoising complete."

        else  # ----------------- Deblur -----------------
            case "$AMPLICON" in
                16S-*) ;;
                *) die "Deblur only supports 16S amplicons. For ITS use --denoiser dada2." ;;
            esac

            log "[5/7] Deblur denoising (light-weight path, 8-GB friendly)…"
            MERGED_QZA="$OUTPUT_DIR/qza/demux-merged.qza"
            FILT_QZA="$OUTPUT_DIR/qza/demux-merged-filtered.qza"
            FILT_STATS_QZA="$OUTPUT_DIR/qza/demux-filter-stats.qza"
            DEBLUR_STATS_QZA="$OUTPUT_DIR/qza/deblur-stats.qza"

            log "  a) Joining paired reads (vsearch merge-pairs)…"
            qiime vsearch merge-pairs \
                --i-demultiplexed-seqs "$TRIMMED_QZA" \
                --p-threads "$THREADS" \
                --o-merged-sequences "$MERGED_QZA" \
                --verbose

            log "  b) Quality filtering (q-score)…"
            qiime quality-filter q-score \
                --i-demux "$MERGED_QZA" \
                --o-filtered-sequences "$FILT_QZA" \
                --o-filter-stats "$FILT_STATS_QZA"

            # Use the smart_trim forward length as Deblur's single trim length.
            log "  c) Deblur denoise-16S (trim-length=$TRUNC_F, threads=$THREADS)…"
            set +e
            qiime deblur denoise-16S \
                --i-demultiplexed-seqs "$FILT_QZA" \
                --p-trim-length "$TRUNC_F" \
                --p-sample-stats \
                --p-jobs-to-start "$THREADS" \
                --o-representative-sequences "$REPSEQ_QZA" \
                --o-table "$TABLE_QZA" \
                --o-stats "$DEBLUR_STATS_QZA" \
                --verbose
            rc=$?
            set -e
            [[ $rc -ne 0 ]] && die "Deblur failed with exit code $rc."

            qiime deblur visualize-stats \
                --i-deblur-stats "$DEBLUR_STATS_QZA" \
                --o-visualization "$OUTPUT_DIR/qzv/deblur-stats.qzv"
            qiime metadata tabulate \
                --m-input-file "$FILT_STATS_QZA" \
                --o-visualization "$OUTPUT_DIR/qzv/quality-filter-stats.qzv"
        fi

        log "  Summarizing feature table (this may take a minute)…"
        qiime feature-table summarize \
            --i-table "$TABLE_QZA" \
            --m-sample-metadata-file "$METADATA" \
            --o-visualization "$OUTPUT_DIR/qzv/table.qzv"
        log "  Tabulating representative sequences…"
        qiime feature-table tabulate-seqs \
            --i-data "$REPSEQ_QZA" \
            --o-visualization "$OUTPUT_DIR/qzv/rep-seqs.qzv"
        ok "Denoising and feature table summary complete ($DENOISER)."
    fi
fi

# ============================================================
# STEP 6  —  Taxonomy
# ============================================================
# NOTE: Step order matches the QIIME 2 Moving Pictures / Atacama
# tutorials and the Expert-Mode wizard flow (denoise → taxonomy →
# phylogeny). Easy Mode previously did phylogeny before taxonomy,
# which produced identical artifacts but read differently in the
# pipeline log and methods section. Both steps consume only
# rep-seqs.qza (no inter-dependency), so swapping the order is
# safe — the BIOM bundle and downstream Shiny inputs are unchanged.
TAXONOMY_QZA="$OUTPUT_DIR/qza/taxonomy.qza"
if ! skipped "taxonomy"; then
    if step_needs_run "$TAXONOMY_QZA"; then
        if [[ -z "$CLASSIFIER" ]]; then
            CL_DIR="${CLASSIFIERS_DIR:-$HOME/ezmap2-classifiers}"
            warn "No --classifier provided. Searching $CL_DIR/…"
            CAND=""
            case "$AMPLICON" in
                16S-V3V4)
                    CAND="$CL_DIR/silva-16S-V3V4-nb-classifier.qza"
                    [[ ! -f "$CAND" ]] && CAND="$CL_DIR/greengenes2-16S-V3V4-nb-classifier.qza"
                    [[ ! -f "$CAND" ]] && CAND="$CL_DIR/silva-138-99-nb-classifier.qza"
                    ;;
                16S-V4)
                    CAND="$CL_DIR/silva-16S-V4-nb-classifier.qza"
                    [[ ! -f "$CAND" ]] && CAND="$CL_DIR/greengenes2-16S-V4-nb-classifier.qza"
                    [[ ! -f "$CAND" ]] && CAND="$CL_DIR/silva-138-99-515-806-nb-classifier.qza"
                    [[ ! -f "$CAND" ]] && CAND="$CL_DIR/silva-138-99-nb-classifier.qza"
                    ;;
                ITS1)
                    CAND="$CL_DIR/unite-ITS1-nb-classifier.qza"
                    ;;
                ITS2)
                    CAND="$CL_DIR/unite-ITS2-nb-classifier.qza"
                    ;;
                *)
                    # Fallback: try to find any classifier matching the amplicon tag
                    CAND=$(find "$CL_DIR/" -name "*${AMPLICON}*-nb-classifier.qza" 2>/dev/null | head -1)
                    # If still nothing, try any classifier at all
                    [[ -z "$CAND" ]] && CAND=$(find "$CL_DIR/" -name "*nb-classifier.qza" 2>/dev/null | head -1)
                    ;;
            esac
            if [[ -n "$CAND" ]] && [[ -f "$CAND" ]]; then
                CLASSIFIER="$CAND"
                ok "Using cached classifier: $CLASSIFIER"
            else
                die "No classifier found for $AMPLICON. Train one via Settings → Pre-trained Classifiers, or pass --classifier <path>."
            fi
        fi
        log "[6/7] Classifying taxonomy (sklearn)…"
        log "  Loading classifier and classifying features — this may take 3–10 minutes…"
        qiime feature-classifier classify-sklearn \
            --i-classifier "$CLASSIFIER" \
            --i-reads "$REPSEQ_QZA" \
            --p-n-jobs "$THREADS" \
            --p-confidence 0.7 \
            --o-classification "$TAXONOMY_QZA"
        ok "Classification complete."
        log "  Building taxonomy visualization…"
        qiime metadata tabulate \
            --m-input-file "$TAXONOMY_QZA" \
            --o-visualization "$OUTPUT_DIR/qzv/taxonomy.qzv"
        ok "Taxonomy assignment done."
    fi
fi

# ============================================================
# STEP 7  —  Phylogeny
# ============================================================
ALIGNED_QZA="$OUTPUT_DIR/qza/aligned-rep-seqs.qza"
MASKED_QZA="$OUTPUT_DIR/qza/masked-aligned-rep-seqs.qza"
TREE_QZA="$OUTPUT_DIR/qza/unrooted-tree.qza"
ROOTED_QZA="$OUTPUT_DIR/qza/rooted-tree.qza"
if ! skipped "phylogeny"; then
    if step_needs_run "$ROOTED_QZA"; then
        log "[7/7] Building phylogeny (MAFFT + FastTree)…"
        log "  Aligning sequences and building tree — this may take 2–5 minutes…"
        qiime phylogeny align-to-tree-mafft-fasttree \
            --i-sequences "$REPSEQ_QZA" \
            --o-alignment "$ALIGNED_QZA" \
            --o-masked-alignment "$MASKED_QZA" \
            --o-tree "$TREE_QZA" \
            --o-rooted-tree "$ROOTED_QZA" \
            --p-n-threads "$THREADS"
        ok "Rooted tree: $ROOTED_QZA"
    fi
fi

# ============================================================
# BUILD DOWNSTREAM BUNDLE
# ============================================================
# Upstream is done (7 steps). Now export artifacts into portable
# formats and build the bundle for the Shiny downstream app.
# ============================================================
log "============================================================"
log "Building downstream bundle…"
log "============================================================"

PARAMS_JSON="$OUTPUT_DIR/bundle/parameters.json"
cat > "$PARAMS_JSON" <<JSON
{
  "ezmap2_version":   "2.0.0",
  "mode":             "easy",
  "run_timestamp":    "$(date -Iseconds)",
  "qiime2_version":   "$QIIME_VERSION",
  "amplicon":         "$AMPLICON",
  "primers":          {"forward": "$FWD_PRIMER", "reverse": "$REV_PRIMER"},
  "cutadapt":         {"discard_untrimmed": true, "minimum_length": 50},
  "smart_trim":       $(cat "$TRIM_JSON" 2>/dev/null || echo '{}'),
  "denoiser":         "$DENOISER",
  "low_memory_mode":  $LOW_MEMORY,
  "dada2":            {"trunc_len_f": ${TRUNC_F:-0}, "trunc_len_r": ${TRUNC_R:-0}, "chimera_method": "consensus", "n_threads": $DADA2_THREADS},
  "deblur":           {"trim_length": ${TRUNC_F:-0}, "enabled": $([[ "$DENOISER" == "deblur" ]] && echo true || echo false)},
  "phylogeny":        {"method": "align-to-tree-mafft-fasttree"},
  "classifier":       "$(basename "${CLASSIFIER:-none}")",
  "classify":         {"method": "classify-sklearn", "confidence": 0.7},
  "threads":          $THREADS,
  "bundle_contents":  ["feature-table.biom", "feature-table-tax.biom", "rooted-tree.nwk", "taxonomy.tsv", "rep-seqs.fasta", "metadata.tsv", "denoising-stats.tsv"]
}
JSON

# ---- Export QIIME2 artifacts into portable formats ----
log "  Exporting BIOM table…"
qiime tools export --input-path "$TABLE_QZA"    --output-path "$OUTPUT_DIR/bundle/feature-table" >/dev/null

log "  Exporting rooted tree…"
qiime tools export --input-path "$ROOTED_QZA"   --output-path "$OUTPUT_DIR/bundle/tree"          >/dev/null

log "  Exporting taxonomy…"
qiime tools export --input-path "$TAXONOMY_QZA" --output-path "$OUTPUT_DIR/bundle/taxonomy"      >/dev/null

log "  Exporting representative sequences…"
qiime tools export --input-path "$REPSEQ_QZA"   --output-path "$OUTPUT_DIR/bundle/rep-seqs"      >/dev/null

# ---- Export denoising statistics as TSV ----
log "  Exporting denoising statistics…"
if [[ "$DENOISER" == "dada2" ]] && [[ -f "$STATS_QZA" ]]; then
    qiime tools export --input-path "$STATS_QZA" --output-path "$OUTPUT_DIR/bundle/denoise-stats" >/dev/null
    mv "$OUTPUT_DIR/bundle/denoise-stats/stats.tsv" "$OUTPUT_DIR/bundle/denoising-stats.tsv" 2>/dev/null || true
    rmdir "$OUTPUT_DIR/bundle/denoise-stats" 2>/dev/null || true
elif [[ -f "${DEBLUR_STATS_QZA:-}" ]]; then
    qiime tools export --input-path "$DEBLUR_STATS_QZA" --output-path "$OUTPUT_DIR/bundle/denoise-stats" >/dev/null
    # Deblur stats export as per-sample JSON — convert to simple TSV
    mv "$OUTPUT_DIR/bundle/denoise-stats/"*.tsv "$OUTPUT_DIR/bundle/denoising-stats.tsv" 2>/dev/null || \
    mv "$OUTPUT_DIR/bundle/denoise-stats/"*.csv "$OUTPUT_DIR/bundle/denoising-stats.tsv" 2>/dev/null || true
    rmdir "$OUTPUT_DIR/bundle/denoise-stats" 2>/dev/null || true
fi

# Copy metadata into the bundle
cp "$METADATA" "$OUTPUT_DIR/bundle/metadata.tsv"

# ---- Flatten exported files to top-level names ----
# (QIIME2 export creates subdirectories — move to bundle root)
mv "$OUTPUT_DIR/bundle/feature-table/feature-table.biom" "$OUTPUT_DIR/bundle/feature-table.biom" 2>/dev/null || true
mv "$OUTPUT_DIR/bundle/tree/tree.nwk"                     "$OUTPUT_DIR/bundle/rooted-tree.nwk"   2>/dev/null || true
mv "$OUTPUT_DIR/bundle/taxonomy/taxonomy.tsv"             "$OUTPUT_DIR/bundle/taxonomy.tsv"       2>/dev/null || true
mv "$OUTPUT_DIR/bundle/rep-seqs/dna-sequences.fasta"      "$OUTPUT_DIR/bundle/rep-seqs.fasta"    2>/dev/null || true
rmdir "$OUTPUT_DIR/bundle/feature-table" "$OUTPUT_DIR/bundle/tree" \
      "$OUTPUT_DIR/bundle/taxonomy" "$OUTPUT_DIR/bundle/rep-seqs" 2>/dev/null || true

# ---- Create taxonomy-merged BIOM file ----
# This attaches taxonomy as observation metadata so downstream tools
# (phyloseq, R, Python) can access taxonomy directly from the BIOM.
log "  Creating taxonomy-merged BIOM file…"
if [[ -f "$OUTPUT_DIR/bundle/feature-table.biom" ]] && [[ -f "$OUTPUT_DIR/bundle/taxonomy.tsv" ]]; then
    # biom add-metadata expects a specific header format
    # QIIME2 exports taxonomy.tsv as: Feature ID\tTaxon\tConfidence
    # biom needs: #OTUID\ttaxonomy\tconfidence
    BIOM_TAX_HEADER="$OUTPUT_DIR/bundle/taxonomy_biom_header.tsv"
    echo -e "#OTUID\ttaxonomy\tconfidence" > "$BIOM_TAX_HEADER"
    tail -n +2 "$OUTPUT_DIR/bundle/taxonomy.tsv" | grep -v '^#' >> "$BIOM_TAX_HEADER"

    biom add-metadata \
        -i "$OUTPUT_DIR/bundle/feature-table.biom" \
        -o "$OUTPUT_DIR/bundle/feature-table-tax.biom" \
        --observation-metadata-fp "$BIOM_TAX_HEADER" \
        --sc-separated taxonomy 2>/dev/null || {
            # Fallback: if biom add-metadata fails (older biom versions), just copy
            warn "biom add-metadata failed; taxonomy-merged BIOM not created."
            cp "$OUTPUT_DIR/bundle/feature-table.biom" "$OUTPUT_DIR/bundle/feature-table-tax.biom"
        }
    rm -f "$BIOM_TAX_HEADER"
    ok "Taxonomy-merged BIOM: feature-table-tax.biom"
else
    warn "Could not create taxonomy-merged BIOM (missing input files)."
fi

# ---- Zip the bundle (convenience archive only) ----
# The real outputs already exist in $OUTPUT_DIR/bundle/. The .zip is just a
# single-file convenience, so a missing 'zip' binary must NOT fail the pipeline
# (it isn't installed in every WSL/conda environment). Prefer 'zip'; fall back
# to Python's zipfile (Python is always present in the QIIME2 conda env).
BUNDLE_ZIP="$OUTPUT_DIR/EzMAP2_results_$(date +%Y%m%d_%H%M%S).zip"
if command -v zip >/dev/null 2>&1; then
    ( cd "$OUTPUT_DIR" && zip -qr "$BUNDLE_ZIP" bundle ) \
        && ok "Results bundle: $BUNDLE_ZIP" \
        || warn "Could not create .zip — your results are still in $OUTPUT_DIR/bundle/"
else
    ( cd "$OUTPUT_DIR" && python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1],'zip',root_dir='.',base_dir='bundle')" "${BUNDLE_ZIP%.zip}" ) \
        && ok "Results bundle: $BUNDLE_ZIP" \
        || warn "Could not create .zip — your results are still in $OUTPUT_DIR/bundle/"
fi

log "============================================================"
ok "Upstream pipeline finished successfully (7 steps)."
log ""
log "Bundle contents ($OUTPUT_DIR/bundle/):"
log "  feature-table.biom       — ASV abundance table (plain)"
log "  feature-table-tax.biom   — ASV table with taxonomy metadata"
log "  taxonomy.tsv             — Taxonomic classifications"
log "  rooted-tree.nwk          — Phylogenetic tree (for UniFrac)"
log "  rep-seqs.fasta           — Representative ASV sequences"
log "  metadata.tsv             — Sample metadata"
log "  denoising-stats.tsv      — DADA2/Deblur filtering statistics"
log "  parameters.json          — Full run parameters (reproducibility)"
log ""
log "Next: Launch the EzMAP2 Downstream Analysis (Shiny) module."
log "      Load the bundle to run diversity, differential abundance,"
log "      Random Forest, network analysis, and functional prediction."
log "============================================================"
