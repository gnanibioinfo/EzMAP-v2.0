#!/bin/bash
# =============================================================================
# EzMAP2 — Train a QIIME2 Naive Bayes classifier
# =============================================================================
# Downloads reference sequences + taxonomy, extracts reads for the target
# primer pair, then trains a sklearn classifier. Saves to ~/ezmap2-classifiers/.
#
# Usage:
#   train_classifier.sh --database silva --amplicon 16S-V3V4 [--min-length 100] [--max-length 400] [--threads 4] [--env-name EzMAP2-qiime2]
#   train_classifier.sh --ref-seqs /path/to/seqs.qza --ref-tax /path/to/tax.qza \
#                        --fwd-primer CCTACGGGNGGCWGCAG --rev-primer GACTACHVGGGTATCTAATCC \
#                        --output /path/to/classifier.qza
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $*"; }
die()  { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*" >&2; exit 1; }

# ---- Defaults ----
DATABASE=""           # silva | unite | greengenes2 | custom
AMPLICON=""           # 16S-V3V4 | 16S-V4 | ITS1 | ITS2
REF_SEQS=""           # custom reference sequences .qza
REF_TAX=""            # custom reference taxonomy .qza
FWD_PRIMER=""
REV_PRIMER=""
OUTPUT=""             # custom output path
THREADS=4
MIN_LENGTH=""          # resolved per-amplicon below if not set with --min-length
MAX_LENGTH=""          # resolved per-amplicon below if not set with --max-length
ENV_NAME="EzMAP2-qiime2"
CLASSIFIERS_DIR="${CLASSIFIERS_DIR:-$HOME/ezmap2-classifiers}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/ezmap2-databases}"

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --database)     DATABASE="$2"; shift 2 ;;
        --amplicon)     AMPLICON="$2"; shift 2 ;;
        --ref-seqs)     REF_SEQS="$2"; shift 2 ;;
        --ref-tax)      REF_TAX="$2"; shift 2 ;;
        --fwd-primer)   FWD_PRIMER="$2"; shift 2 ;;
        --rev-primer)   REV_PRIMER="$2"; shift 2 ;;
        --output)       OUTPUT="$2"; shift 2 ;;
        --threads)      THREADS="$2"; shift 2 ;;
        --min-length)   MIN_LENGTH="$2"; shift 2 ;;
        --max-length)   MAX_LENGTH="$2"; shift 2 ;;
        --env-name)     ENV_NAME="$2"; shift 2 ;;
        -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

mkdir -p "$CLASSIFIERS_DIR" "$DOWNLOADS_DIR"

# ---- Activate conda ----
if [[ -z "${CONDA_PREFIX:-}" ]] || [[ "${CONDA_DEFAULT_ENV:-}" != "$ENV_NAME" ]]; then
    log "Activating conda env: $ENV_NAME"
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME" || die "Failed to activate $ENV_NAME."
fi
command -v qiime >/dev/null || die "qiime not found in conda env."

# ---- Resolve primers from amplicon if not custom ----
if [[ -n "$AMPLICON" ]] && [[ -z "$FWD_PRIMER" ]]; then
    case "$AMPLICON" in
        16S-V3V4) FWD_PRIMER="CCTACGGGNGGCWGCAG";      REV_PRIMER="GACTACHVGGGTATCTAATCC" ;;
        16S-V4)   FWD_PRIMER="GTGYCAGCMGCCGCGGTAA";    REV_PRIMER="GGACTACNVGGGTWTCTAAT" ;;
        ITS1)     FWD_PRIMER="CTTGGTCATTTAGAGGAAGTAA"; REV_PRIMER="GCTGCGTTCTTCATCGATGC" ;;
        ITS2)     FWD_PRIMER="GCATCGATGAAGAACGCAGC";   REV_PRIMER="TCCTCCGCTTATTGATATGC" ;;
        *) die "Unknown amplicon: $AMPLICON" ;;
    esac
fi

[[ -z "$FWD_PRIMER" ]] && die "Forward primer required (--fwd-primer or --amplicon)"
[[ -z "$REV_PRIMER" ]] && die "Reverse primer required (--rev-primer or --amplicon)"

# ---- Resolve read-length bounds per amplicon (only if not user-specified) ----
# extract-reads discards reads outside [min,max]. These bounds must match the
# expected amplicon length AFTER primer removal, or valid reference reads are
# thrown away. V3-V4 (~400-430 bp) needs a much larger max than V4 (~250 bp);
# a single 400 bp cap silently discarded most V3-V4 reads. ITS length is highly
# variable, so its bounds are kept wide. User --min-length/--max-length win.
case "$AMPLICON" in
    16S-V3V4)  MIN_LENGTH="${MIN_LENGTH:-300}"; MAX_LENGTH="${MAX_LENGTH:-500}" ;;
    16S-V4)    MIN_LENGTH="${MIN_LENGTH:-100}"; MAX_LENGTH="${MAX_LENGTH:-400}" ;;
    ITS1|ITS2) MIN_LENGTH="${MIN_LENGTH:-50}";  MAX_LENGTH="${MAX_LENGTH:-600}" ;;
esac
# Fallback for custom primers / unknown amplicon: wide, non-restrictive bounds.
MIN_LENGTH="${MIN_LENGTH:-100}"
MAX_LENGTH="${MAX_LENGTH:-500}"

# ---- Download or locate reference database ----
if [[ -n "$DATABASE" ]] && [[ -z "$REF_SEQS" ]]; then
    case "$DATABASE" in
        silva)
            REF_SEQS="$DOWNLOADS_DIR/silva-138.2-ssu-nr99-seqs.qza"
            REF_TAX="$DOWNLOADS_DIR/silva-138.2-ssu-nr99-tax.qza"
            if [[ ! -f "$REF_SEQS" ]]; then
                log "Downloading SILVA 138.2 reference sequences…"
                wget -q --show-progress \
                    "https://data.qiime2.org/2024.10/common/silva-138-99-seqs.qza" \
                    -O "$REF_SEQS" || curl -L --progress-bar \
                    "https://data.qiime2.org/2024.10/common/silva-138-99-seqs.qza" \
                    -o "$REF_SEQS"
                ok "Downloaded: $REF_SEQS"
            else
                ok "SILVA sequences already downloaded."
            fi
            if [[ ! -f "$REF_TAX" ]]; then
                log "Downloading SILVA 138.2 reference taxonomy…"
                wget -q --show-progress \
                    "https://data.qiime2.org/2024.10/common/silva-138-99-tax.qza" \
                    -O "$REF_TAX" || curl -L --progress-bar \
                    "https://data.qiime2.org/2024.10/common/silva-138-99-tax.qza" \
                    -o "$REF_TAX"
                ok "Downloaded: $REF_TAX"
            else
                ok "SILVA taxonomy already downloaded."
            fi
            ;;
        unite)
            # UNITE requires manual download due to licensing.
            # The user-imported file naming varies a lot across releases:
            #   unite-ver7-99-seqs-04.04.2024.qza   (legacy, dotted dates)
            #   unite-ver7-99-tax-04.04.2024.qza
            #   unite-ver8-99-seqs-04.02.2020.qza
            #   unite-ver10-seqs-dynamic.qza        (newer, "dynamic" tag)
            #   unite-ver10-tax-dynamic.qza
            #   unite-ver10-seqs-developer.qza      (developer release)
            # Instead of hard-coding a single filename, search the downloads
            # directory for any *seqs* / *tax* pair that mentions "unite",
            # then pair the highest-version match. Falls back to a clear
            # diagnostic that lists what WAS found if nothing matches.
            log "Searching for UNITE reference under $DOWNLOADS_DIR/ …"

            # All UNITE *.qza files (case-insensitive on the "unite" tag)
            mapfile -t UNITE_FILES < <(
                find "$DOWNLOADS_DIR" -maxdepth 1 -type f -iname 'unite*.qza' 2>/dev/null \
                    | sort -V -r
            )

            UNITE_SEQS_FILE=""
            UNITE_TAX_FILE=""
            for f in "${UNITE_FILES[@]}"; do
                base=$(basename "$f")
                lower=${base,,}
                # Skip files that look like a trained classifier
                if [[ "$lower" == *"classifier"* || "$lower" == *"-nb-"* ]]; then
                    continue
                fi
                if [[ -z "$UNITE_SEQS_FILE" && ( "$lower" == *"seqs"* || "$lower" == *"sequences"* || "$lower" == *"rep"* ) ]]; then
                    UNITE_SEQS_FILE="$f"
                fi
                if [[ -z "$UNITE_TAX_FILE" && ( "$lower" == *"tax"* || "$lower" == *"taxonomy"* ) ]]; then
                    UNITE_TAX_FILE="$f"
                fi
            done

            if [[ -z "$UNITE_SEQS_FILE" || -z "$UNITE_TAX_FILE" ]]; then
                # No .qza pair found — try the raw QIIME release UNITE
                # distributes (e.g. sh_refs_qiime_ver10_99_19.02.2025_dev.fasta
                # plus sh_taxonomy_qiime_ver10_99_19.02.2025_dev.txt — or
                # the same basename with a .txt extension). When found,
                # auto-import to .qza and cache the result so subsequent
                # runs use the imported artifact directly.
                log "No imported UNITE .qza found — checking for raw UNITE QIIME-format files…"

                # Find any FASTA file whose name suggests it's a UNITE
                # reference. UNITE's official tarballs use sh_refs_qiime_*
                # prefixes; we accept anything containing 'unite' or
                # 'sh_refs' just in case the user renamed.
                mapfile -t UNITE_FASTA < <(
                    find "$DOWNLOADS_DIR" -maxdepth 1 -type f \
                        \( -iname 'sh_refs_*.fasta' -o -iname 'unite*.fasta' \
                           -o -iname 'sh_refs_*.fa'    -o -iname 'unite*.fa' \) \
                        2>/dev/null | sort -V -r
                )

                if [[ "${#UNITE_FASTA[@]}" -gt 0 ]]; then
                    UNITE_RAW_FASTA="${UNITE_FASTA[0]}"
                    fasta_base="$(basename "$UNITE_RAW_FASTA")"
                    fasta_stem="${fasta_base%.*}"

                    # Locate the matching taxonomy text file. Try in order:
                    #   1. Same base, .txt extension          (sh_refs_*.txt)
                    #   2. sh_taxonomy_* sibling with the same date/version stamp
                    #   3. Any other unite*.txt / sh_taxonomy_*.txt in the dir
                    UNITE_RAW_TAX=""
                    candidate1="$DOWNLOADS_DIR/${fasta_stem}.txt"
                    candidate2="${UNITE_RAW_FASTA/sh_refs_/sh_taxonomy_}"
                    candidate2="${candidate2%.*}.txt"
                    if [[ -f "$candidate1" ]]; then
                        UNITE_RAW_TAX="$candidate1"
                    elif [[ -f "$candidate2" ]]; then
                        UNITE_RAW_TAX="$candidate2"
                    else
                        # Last resort: any *.txt that looks like a UNITE taxonomy
                        mapfile -t UNITE_TXT < <(
                            find "$DOWNLOADS_DIR" -maxdepth 1 -type f \
                                \( -iname 'sh_taxonomy_*.txt' -o -iname 'unite*tax*.txt' \
                                   -o -iname 'unite*taxonomy*.txt' \) \
                                2>/dev/null | sort -V -r
                        )
                        [[ "${#UNITE_TXT[@]}" -gt 0 ]] && UNITE_RAW_TAX="${UNITE_TXT[0]}"
                    fi

                    if [[ -z "$UNITE_RAW_TAX" || ! -f "$UNITE_RAW_TAX" ]]; then
                        warn "Found UNITE FASTA but no matching taxonomy .txt:"
                        warn "  FASTA: $fasta_base"
                        warn "Expected one of: ${fasta_stem}.txt, sh_taxonomy_*.txt, or unite*tax*.txt in $DOWNLOADS_DIR/"
                        die "UNITE taxonomy file not found. Place the matching .txt next to the .fasta and retry."
                    fi

                    log "Auto-importing raw UNITE files to QIIME 2 .qza format (one-time step):"
                    log "  FASTA:    $(basename "$UNITE_RAW_FASTA")"
                    log "  Taxonomy: $(basename "$UNITE_RAW_TAX")"

                    # Output names: keep the fasta stem so subsequent runs
                    # find the .qza pair via the existing search above.
                    UNITE_SEQS_FILE="$DOWNLOADS_DIR/${fasta_stem}-seqs.qza"
                    UNITE_TAX_FILE="$DOWNLOADS_DIR/${fasta_stem}-tax.qza"

                    if [[ ! -f "$UNITE_SEQS_FILE" ]]; then
                        log "  Importing sequences → $(basename "$UNITE_SEQS_FILE")"
                        qiime tools import \
                            --type 'FeatureData[Sequence]' \
                            --input-path "$UNITE_RAW_FASTA" \
                            --output-path "$UNITE_SEQS_FILE" \
                            || die "qiime tools import failed for $UNITE_RAW_FASTA"
                    fi
                    if [[ ! -f "$UNITE_TAX_FILE" ]]; then
                        log "  Importing taxonomy → $(basename "$UNITE_TAX_FILE")"
                        qiime tools import \
                            --type 'FeatureData[Taxonomy]' \
                            --input-format HeaderlessTSVTaxonomyFormat \
                            --input-path "$UNITE_RAW_TAX" \
                            --output-path "$UNITE_TAX_FILE" \
                            || die "qiime tools import failed for $UNITE_RAW_TAX"
                    fi
                    ok "UNITE raw files imported and cached as .qza."
                else
                    warn "UNITE reference not located. Files found in $DOWNLOADS_DIR/:"
                    if [[ "${#UNITE_FILES[@]}" -eq 0 ]]; then
                        # Show every .qza / .fasta / .txt to help the user
                        mapfile -t ALL_FILES < <(
                            find "$DOWNLOADS_DIR" -maxdepth 1 -type f \
                                \( -iname '*.qza' -o -iname '*.fasta' -o -iname '*.fa' -o -iname '*.txt' \) \
                                2>/dev/null
                        )
                        if [[ "${#ALL_FILES[@]}" -eq 0 ]]; then
                            warn "  (directory empty)"
                        else
                            for f in "${ALL_FILES[@]}"; do warn "  $(basename "$f")"; done
                        fi
                    else
                        for f in "${UNITE_FILES[@]}"; do warn "  $(basename "$f")"; done
                    fi
                    die "UNITE database not found at $DOWNLOADS_DIR/. Provide either: (a) a pair of .qza artifacts (*seqs*.qza + *tax*.qza), OR (b) the raw UNITE QIIME release files (sh_refs_qiime_*.fasta + matching .txt). Download from https://unite.ut.ee/repository.php."
                fi
            fi

            REF_SEQS="$UNITE_SEQS_FILE"
            REF_TAX="$UNITE_TAX_FILE"
            ok "UNITE reference ready:"
            ok "    seqs: $(basename "$REF_SEQS")"
            ok "    tax:  $(basename "$REF_TAX")"
            ;;
        greengenes2)
            REF_SEQS="$DOWNLOADS_DIR/gg2-2024.09-nb-seqs.qza"
            REF_TAX="$DOWNLOADS_DIR/gg2-2024.09-nb-tax.qza"
            # Greengenes2 reference files live on the microbio.me FTP, not on
            # data.qiime2.org (the old gg2-2024.09-nb-* URLs there 404).
            GG2_SEQS_URL="http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.full-length.fna.qza"
            GG2_TAX_URL="http://ftp.microbio.me/greengenes_release/2024.09/2024.09.backbone.tax.qza"
            if [[ ! -f "$REF_SEQS" ]]; then
                log "Downloading Greengenes2 reference…"
                curl -fSL --retry 3 "$GG2_SEQS_URL" -o "$REF_SEQS" \
                    || wget --tries=3 "$GG2_SEQS_URL" -O "$REF_SEQS"
            fi
            if [[ ! -f "$REF_TAX" ]]; then
                curl -fSL --retry 3 "$GG2_TAX_URL" -o "$REF_TAX" \
                    || wget --tries=3 "$GG2_TAX_URL" -O "$REF_TAX"
            fi
            ok "Greengenes2 reference ready."
            ;;
        *) die "Unknown database: $DATABASE (choose silva | unite | greengenes2)" ;;
    esac
fi

[[ -z "$REF_SEQS" ]] && die "Reference sequences required (--ref-seqs or --database)"
[[ -z "$REF_TAX"  ]] && die "Reference taxonomy required (--ref-tax or --database)"
[[ -f "$REF_SEQS" ]] || die "Reference sequences not found: $REF_SEQS"
[[ -f "$REF_TAX"  ]] || die "Reference taxonomy not found: $REF_TAX"

# ---- Determine output path ----
if [[ -z "$OUTPUT" ]]; then
    DB_TAG="${DATABASE:-custom}"
    AMP_TAG="${AMPLICON:-custom}"
    OUTPUT="$CLASSIFIERS_DIR/${DB_TAG}-${AMP_TAG}-nb-classifier.qza"
fi

# Check if classifier already exists
if [[ -f "$OUTPUT" ]]; then
    ok "Classifier already exists: $OUTPUT"
    log "Delete it first if you want to retrain."
    exit 0
fi

log "============================================================"
log "EzMAP2 Classifier Training"
log "============================================================"
log "Database:    ${DATABASE:-custom}"
log "Amplicon:    ${AMPLICON:-custom}"
log "Fwd primer:  $FWD_PRIMER"
log "Rev primer:  $REV_PRIMER"
log "Ref seqs:    $REF_SEQS"
log "Ref tax:     $REF_TAX"
log "Output:      $OUTPUT"
log "Min length:  $MIN_LENGTH"
log "Max length:  $MAX_LENGTH"
log "Threads:     $THREADS"
log "============================================================"

# ---- Step 1: Extract reads for primer pair ----
EXTRACTED="$CLASSIFIERS_DIR/.tmp-extracted-reads.qza"
log "[1/2] Extracting reference reads for primer pair…"
log "  This trims the reference database to your amplicon region."
log "  May take 5–15 minutes depending on database size…"

qiime feature-classifier extract-reads \
    --i-sequences "$REF_SEQS" \
    --p-f-primer "$FWD_PRIMER" \
    --p-r-primer "$REV_PRIMER" \
    --p-min-length "$MIN_LENGTH" \
    --p-max-length "$MAX_LENGTH" \
    --p-n-jobs "$THREADS" \
    --o-reads "$EXTRACTED"
ok "Reads extracted for region."

# ---- Step 2: Train Naive Bayes classifier ----
log "[2/2] Training Naive Bayes classifier…"
log "  This step may take 15–45 minutes. The process is running; please wait…"

qiime feature-classifier fit-classifier-naive-bayes \
    --i-reference-reads "$EXTRACTED" \
    --i-reference-taxonomy "$REF_TAX" \
    --o-classifier "$OUTPUT"

# Cleanup temp
rm -f "$EXTRACTED"

ok "Classifier trained: $OUTPUT"
log "============================================================"
log "Classifier saved to: $OUTPUT"
log "You can use this with --classifier in the pipeline."
log "============================================================"
