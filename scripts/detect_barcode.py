#!/usr/bin/env python3
"""
detect_barcode.py — Detect non-biological barcode/linker prefixes in
demultiplexed FASTQ reads inside a QIIME 2 .qza artifact.

This is a Python port of EzMAP v2's Java `BarcodeDetector` so that Easy
Mode (which is driven by easy_mode.sh, not the Java wizard) can apply
the same trim-left heuristics that Expert Mode applies through the
"Apply Suggestions" button.

Algorithm (matches src-build/.../ui/BarcodeDetector.java):
  1. Open the .qza (ZIP), find every <uuid>/data/<sample>_R[12]_*.fastq.gz.
  2. Read the first 50 sequences from each sample (up to 6 distinct
     samples per direction).
  3. Cross-sample comparison: at each position 0..50, count how many
     sample-pair representatives disagree. A position with mismatch
     rate >= 0.30 is "variable across samples", i.e. likely barcode.
     Walk forward; once we see 5+ consecutive low-mismatch positions
     after a variable region, stop. The end of the variable region is
     the barcode length.
  4. Primer-motif search: for each known 16S/ITS primer motif, find
     the most common position in the reads. If consistent, the primer
     position == barcode length.
  5. Combine the two methods (matches Java logic): if both find
     something, pick "barcode + full primer length" as full trim.
     Otherwise prefer primer position alone, or cross-sample alone.

Output:
  Single JSON document on stdout (also to --output if given) containing
  trim_left_f, trim_left_r, forward_detail, reverse_detail, detected,
  avg_read_len_f, avg_read_len_r, has_paired_end.

Exit codes:
  0  Detection ran (regardless of whether anything was found).
  1  Hard failure (could not open .qza, no FASTQ inside, etc.).
"""
from __future__ import annotations
import argparse
import gzip
import io
import json
import re
import sys
import zipfile
from collections import OrderedDict
from pathlib import Path

# ---- Constants (mirror Java BarcodeDetector) -----------------------
READS_PER_SAMPLE = 50
MIN_SAMPLES = 2
MAX_SAMPLES = 6
BARCODE_MISMATCH_THRESHOLD = 0.30

# IUPAC nucleotide ambiguity table.
IUPAC = {
    'A': 'A',     'C': 'C',     'G': 'G',     'T': 'T', 'U': 'T',
    'R': 'AG',    'Y': 'CT',    'S': 'GC',    'W': 'AT',
    'K': 'GT',    'M': 'AC',    'B': 'CGT',   'D': 'AGT',
    'H': 'ACT',   'V': 'ACG',   'N': 'ACGT',
}


def iupac_to_regex(motif: str) -> re.Pattern:
    """Convert an IUPAC primer string into a compiled regex."""
    parts = []
    for c in motif.upper():
        bases = IUPAC.get(c, c)
        parts.append('[' + bases + ']' if len(bases) > 1 else bases)
    return re.compile(''.join(parts))


# ---- Primer definitions (16S + ITS — superset of Java table) -------
# (motif, full_primer_length, motif_offset_within_primer)
FWD_PRIMERS = [
    # --- 16S ---
    ('GTGYCAGCMGCCGCGGTAA', 19, 0),   # 515F (Parada)
    ('GTGCCAGCMGCCGCGGTAA', 19, 0),   # 515F-Y→C variant
    ('GTGTCAGCMGCCGCGGTAA', 19, 0),   # 515F-Y→T variant
    ('CCTACGGGNGGCWGCAG',   17, 0),   # 341F (V3-V4)
    ('CCTACGGGAGGCAGCAG',   17, 0),   # 338F
    # --- ITS ---
    ('CTTGGTCATTTAGAGGAAGTAA', 22, 0),  # ITS1F
    ('GCATCGATGAAGAACGCAGC',   20, 0),  # ITS3 / ITS3-Mix
]

REV_PRIMERS = [
    # --- 16S ---
    ('GGACTACNVGGGTWTCTAAT', 20, 0),  # 806R (Apprill, full)
    ('GGACTAC',               7, 0),  # 806R 5' motif (start)
    ('GACTACHVGGG',          11, 1),  # 806R core (offset 1)
    ('TATCTAAT',              8, 12), # 806R tail (offset 12 within 806R)
    ('ATTAGAWACCC',          11, 0),  # 806R reverse-complement start
    ('GACTACHVGGGTATCTAATCC', 21, 0), # 805R (V3-V4)
    # --- ITS ---
    ('GCTGCGTTCTTCATCGATGC', 20, 0),  # ITS2
    ('TCCTCCGCTTATTGATATGC', 20, 0),  # ITS4
]


# ---- FASTQ extraction ---------------------------------------------
_R1_RE = re.compile(r'_R1[_.]')
_R2_RE = re.compile(r'_R2[_.]')


def extract_sample_id(basename: str) -> str:
    """Best-effort sample-id extraction from QIIME's Casava 1.8 layout."""
    return basename.split('_')[0]


def read_fastq_seqs(stream: io.BufferedReader, max_reads: int):
    """Read up to max_reads sequences (every 4th line) from a gzipped
    FASTQ byte stream, returning a list of ASCII strings."""
    seqs = []
    with gzip.GzipFile(fileobj=stream) as gz:
        line_no = 0
        for line in io.TextIOWrapper(gz, encoding='ascii', errors='replace'):
            ln = line_no % 4
            if ln == 1:
                s = line.rstrip('\n').rstrip('\r').upper()
                if s:
                    seqs.append(s)
                if len(seqs) >= max_reads:
                    break
            line_no += 1
    return seqs


def collect_reads_from_qza(qza_path: Path):
    """Return (fwd_by_sample, rev_by_sample) — OrderedDicts of
    sample-id → list[str] (sequences). Reverse map is empty if SE."""
    fwd_by_sample: 'OrderedDict[str, list]' = OrderedDict()
    rev_by_sample: 'OrderedDict[str, list]' = OrderedDict()

    with zipfile.ZipFile(qza_path) as z:
        for info in z.infolist():
            name = info.filename
            if not (name.endswith('.fastq.gz') or name.endswith('.fq.gz')):
                continue
            if '/data/' not in name:
                continue
            basename = name.rsplit('/', 1)[-1]
            is_r1 = bool(_R1_RE.search(basename))
            is_r2 = bool(_R2_RE.search(basename))
            if not is_r1 and not is_r2:
                # Single-end: treat as forward
                is_r1 = True
            sample_id = extract_sample_id(basename)
            target = fwd_by_sample if is_r1 else rev_by_sample
            if len(target) >= MAX_SAMPLES and sample_id not in target:
                continue
            with z.open(info) as fh:
                seqs = read_fastq_seqs(fh, READS_PER_SAMPLE)
            target.setdefault(sample_id, []).extend(seqs)
    return fwd_by_sample, rev_by_sample


# ---- Detection methods --------------------------------------------
def avg_read_length(reads_by_sample) -> int:
    lens = []
    for reads in reads_by_sample.values():
        for r in reads:
            lens.append(len(r))
    return int(sum(lens) / len(lens)) if lens else 0


def detect_by_cross_sample(reads_by_sample) -> int:
    """Cross-sample disagreement → barcode length. Returns 0 if not
    enough samples or no variable region found."""
    if len(reads_by_sample) < MIN_SAMPLES:
        return 0
    representatives = [reads[0] for reads in reads_by_sample.values() if reads]
    if len(representatives) < 2:
        return 0
    min_len = min(len(r) for r in representatives)
    if min_len < 10:
        return 0
    check_len = min(min_len, 50)

    barcode_end = 0
    consecutive_agreements = 0
    for pos in range(check_len):
        mismatches = 0
        comparisons = 0
        for i in range(len(representatives)):
            for j in range(i + 1, len(representatives)):
                comparisons += 1
                if representatives[i][pos] != representatives[j][pos]:
                    mismatches += 1
        rate = mismatches / comparisons if comparisons else 0.0
        if rate >= BARCODE_MISMATCH_THRESHOLD:
            barcode_end = pos + 1
            consecutive_agreements = 0
        else:
            consecutive_agreements += 1
            if consecutive_agreements >= 5 and barcode_end > 0:
                break
    return barcode_end


def detect_by_primer_search_full(reads_by_sample, primer_defs):
    """For each primer in primer_defs, find its most-frequent start
    position across sampled reads. Returns (primer_start, full_trim) or
    (0, 0) if none found consistently. full_trim = primer_start +
    full_primer_length - motif_offset (so that everything up to and
    including the full primer is removed).
    """
    all_reads = []
    for reads in reads_by_sample.values():
        all_reads.extend(reads)
    if not all_reads:
        return (0, 0)

    best_start = 0
    best_full = 0
    best_count = 0

    # Search each primer; pick the one with the strongest signal.
    for motif, full_len, offset in primer_defs:
        rx = iupac_to_regex(motif)
        # Allow primer to start anywhere in the first 30 bp.
        position_counts = {}
        for read in all_reads:
            if not read:
                continue
            window = read[:50]
            m = rx.search(window)
            if m is None:
                continue
            primer_start_in_read = m.start() - offset
            if primer_start_in_read < 0:
                continue
            # Round to 0..30
            if primer_start_in_read > 30:
                continue
            position_counts[primer_start_in_read] = \
                position_counts.get(primer_start_in_read, 0) + 1
        if not position_counts:
            continue
        # Most frequent start position for this primer
        pos, count = max(position_counts.items(), key=lambda kv: kv[1])
        # Require at least 30% of reads to agree on the position
        if count < max(3, int(len(all_reads) * 0.30)):
            continue
        if count > best_count:
            best_count = count
            best_start = pos
            best_full = pos + full_len
    return (best_start, best_full)


# ---- Main analyze --------------------------------------------------
def analyze(qza_path: Path, amplicon_length: int):
    fwd_by_sample, rev_by_sample = collect_reads_from_qza(qza_path)
    has_paired = bool(rev_by_sample)
    avg_f = avg_read_length(fwd_by_sample)
    avg_r = avg_read_length(rev_by_sample) if has_paired else 0

    # ---- Forward ----
    trim_f = 0
    fwd_detail = "No barcode/linker detected on forward reads."
    if len(fwd_by_sample) >= MIN_SAMPLES:
        cross_f = detect_by_cross_sample(fwd_by_sample)
        primer_start_f, full_trim_f = detect_by_primer_search_full(fwd_by_sample, FWD_PRIMERS)
        if cross_f > 0 and primer_start_f > 0:
            trim_f = full_trim_f
            fwd_detail = (
                f"Detected {cross_f}bp barcode + {full_trim_f - primer_start_f}bp primer "
                f"on forward reads (total {full_trim_f}bp to trim). Cross-sample analysis "
                f"found {cross_f}bp variable region; primer starts at position {primer_start_f}.")
        elif primer_start_f > 0:
            trim_f = full_trim_f
            fwd_detail = (
                f"Detected primer at position {primer_start_f} on forward reads. "
                f"Full primer is {full_trim_f - primer_start_f}bp — suggests {full_trim_f}bp total prefix.")
        elif cross_f > 0:
            trim_f = cross_f
            fwd_detail = (
                f"Detected {cross_f}bp sample-specific barcode prefix on forward reads "
                f"(cross-sample analysis). No primer motif found — primer may have already "
                f"been removed by Cutadapt.")
    elif len(fwd_by_sample) == 1:
        primer_start_f, full_trim_f = detect_by_primer_search_full(fwd_by_sample, FWD_PRIMERS)
        if primer_start_f > 0:
            trim_f = full_trim_f
            fwd_detail = (
                f"Detected primer at position {primer_start_f} on forward reads (single sample). "
                f"Full primer is {full_trim_f - primer_start_f}bp — suggests {full_trim_f}bp total trim.")

    # ---- Reverse ----
    trim_r = 0
    rev_detail = "No barcode/linker detected on reverse reads." if has_paired else ""
    if has_paired and len(rev_by_sample) >= MIN_SAMPLES:
        cross_r = detect_by_cross_sample(rev_by_sample)
        primer_start_r, full_trim_r = detect_by_primer_search_full(rev_by_sample, REV_PRIMERS)
        if cross_r > 0 and primer_start_r > 0:
            trim_r = full_trim_r
            rev_detail = (
                f"Detected {cross_r}bp barcode + {full_trim_r - primer_start_r}bp primer "
                f"on reverse reads (total {full_trim_r}bp to trim).")
        elif primer_start_r > 0:
            trim_r = full_trim_r
            rev_detail = (
                f"Detected primer at position {primer_start_r} on reverse reads. "
                f"Full primer is {full_trim_r - primer_start_r}bp — suggests {full_trim_r}bp total prefix.")
        elif cross_r > 0:
            trim_r = cross_r
            rev_detail = (
                f"Detected {cross_r}bp sample-specific barcode prefix on reverse reads "
                f"(cross-sample analysis). No primer motif found — primer may have already "
                f"been removed by Cutadapt.")
    elif has_paired and len(rev_by_sample) == 1:
        primer_start_r, full_trim_r = detect_by_primer_search_full(rev_by_sample, REV_PRIMERS)
        if primer_start_r > 0:
            trim_r = full_trim_r
            rev_detail = (
                f"Detected primer at position {primer_start_r} on reverse reads (single sample). "
                f"Full primer is {full_trim_r - primer_start_r}bp — suggests {full_trim_r}bp total trim.")

    detected = (trim_f > 0) or (trim_r > 0)
    return {
        "trim_left_f":     trim_f,
        "trim_left_r":     trim_r,
        "forward_detail":  fwd_detail,
        "reverse_detail":  rev_detail,
        "detected":        detected,
        "avg_read_len_f":  avg_f,
        "avg_read_len_r":  avg_r,
        "has_paired_end":  has_paired,
        "n_fwd_samples":   len(fwd_by_sample),
        "n_rev_samples":   len(rev_by_sample),
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("qza", type=Path, help="demultiplexed (post-Cutadapt) .qza")
    p.add_argument("--amplicon-length", type=int, default=460,
                   help="expected amplicon length (only used by primer-search heuristics)")
    p.add_argument("--output", type=Path, default=None,
                   help="Write JSON to file as well as stdout")
    args = p.parse_args(argv)

    if not args.qza.exists():
        sys.stderr.write(f"[detect_barcode] ERROR: file not found: {args.qza}\n")
        return 1
    try:
        result = analyze(args.qza, args.amplicon_length)
    except Exception as e:
        sys.stderr.write(f"[detect_barcode] ERROR: analysis failed: {e}\n")
        # Emit a no-op JSON so easy_mode.sh's caller doesn't choke.
        result = {
            "trim_left_f": 0, "trim_left_r": 0,
            "forward_detail": f"Detection failed: {e}",
            "reverse_detail": "",
            "detected": False,
            "avg_read_len_f": 0, "avg_read_len_r": 0,
            "has_paired_end": False, "error": str(e),
            "n_fwd_samples": 0, "n_rev_samples": 0,
        }
    text = json.dumps(result, indent=2)
    print(text)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
