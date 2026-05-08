#!/usr/bin/env python3
"""
smart_trim.py — Quality-driven DADA2 trim-length picker.

Reads a QIIME2 demux-summarize visualization (.qzv) and chooses
`--p-trunc-len-f` and `--p-trunc-len-r` based on where the median
Phred score drops below a threshold. Deterministic, reproducible,
publication-defensible.

Method:
    For each read direction, walk the per-base median quality scores
    from 5' to 3'. Truncate at the first position where the median
    falls below MIN_Q_FWD (default 25) or MIN_Q_REV (default 20).
    A minimum length floor (default 150) prevents pathological cases.
    A maximum read length ceiling caps the trim at the read length.

Usage:
    python smart_trim.py demux.qzv [--min-q-fwd 25] [--min-q-rev 20] \\
           [--min-len 150] [--output trim.json]

Output (JSON to stdout and/or file):
    {
      "forward_trunc": 240,
      "reverse_trunc": 200,
      "forward_median_at_trunc": 28,
      "reverse_median_at_trunc": 22,
      "min_q_fwd": 25,
      "min_q_rev": 20,
      "min_len": 150,
      "method": "median-q-drop"
    }
"""
from __future__ import annotations
import argparse
import json
import re
import sys
import zipfile
from pathlib import Path


# Patterns we accept for the per-position seven-number summary tables.
# Different QIIME 2 versions / plugin builds emit the file with slightly
# different names (e.g. .tsv vs .csv) and inside different sub-paths
# within the .qzv archive — match by basename + flexible regex so we
# survive those drifts.
_FWD_RE = re.compile(r"forward[-_].*number[-_]summaries\.(tsv|csv)$",
                     re.IGNORECASE)
_REV_RE = re.compile(r"reverse[-_].*number[-_]summaries\.(tsv|csv)$",
                     re.IGNORECASE)


def load_quality_table(qzv_path: Path):
    """
    A QIIME 2 demux-summarize .qzv contains per-position quality summary
    tables with rows for 25%, 50% (median), 75%, etc. and one column per
    base position. Recent QIIME 2 builds have used several variants:
        forward-seven-number-summaries.tsv          (older)
        forward-seven-number-summaries.csv          (newer)
        per-sample-data/forward-seven-number-summaries.tsv (nested)
    We accept any basename matching forward*number*summaries.{tsv,csv}
    (case-insensitive) and parse it as either tab- or comma-separated.

    Returns (fwd_medians: list[float], rev_medians: list[float] | None).
    """
    fwd = None
    rev = None
    fwd_path = None
    rev_path = None
    archive_files: list[str] = []
    with zipfile.ZipFile(qzv_path) as z:
        archive_files = z.namelist()
        for n in archive_files:
            base = Path(n).name
            if fwd is None and _FWD_RE.search(base):
                fwd = _parse_median_row(z.read(n).decode("utf-8", "replace"))
                fwd_path = n
            elif rev is None and _REV_RE.search(base):
                rev = _parse_median_row(z.read(n).decode("utf-8", "replace"))
                rev_path = n
    if fwd is None:
        # Print the archive contents to stderr so the user can see what
        # the QIIME 2 version actually emitted — turns a cryptic crash
        # into something diagnosable.
        candidates = [
            n for n in archive_files
            if "summaries" in n.lower() or "quality" in n.lower()
        ]
        sys.stderr.write(
            "[smart_trim] ERROR: no forward-quality-summary table found "
            "inside %s\n" % qzv_path
        )
        sys.stderr.write(
            "[smart_trim] Tried regex: %s (case-insensitive)\n"
            % _FWD_RE.pattern
        )
        if candidates:
            sys.stderr.write(
                "[smart_trim] Files in the archive that mention "
                "'summaries' or 'quality':\n"
            )
            for c in candidates:
                sys.stderr.write("    %s\n" % c)
        else:
            sys.stderr.write(
                "[smart_trim] No likely candidate files found. Full "
                "archive listing:\n"
            )
            for n in archive_files:
                sys.stderr.write("    %s\n" % n)
        raise RuntimeError(
            "Could not locate a forward seven-number summary table "
            "inside %s. The QIIME 2 version may have changed the "
            "visualization layout — see archive listing above." % qzv_path
        )
    if fwd_path is not None:
        sys.stderr.write("[smart_trim] forward summary: %s\n" % fwd_path)
    if rev_path is not None:
        sys.stderr.write("[smart_trim] reverse summary: %s\n" % rev_path)
    return fwd, rev  # rev may be None for single-end


def _parse_median_row(text: str):
    """Row labelled '50%' (or 'median') holds per-position median Phred
    scores. Tolerate either tab- or comma-separated text — newer QIIME 2
    builds emit CSV in some places."""
    # Pick the more-frequent delimiter on the first non-empty line.
    first = next((ln for ln in text.splitlines() if ln.strip()), "")
    delim = "\t" if first.count("\t") >= first.count(",") else ","
    rows = [ln.rstrip("\n").split(delim) for ln in text.splitlines() if ln.strip()]
    if not rows:
        return []
    for row in rows[1:]:
        if row and row[0].strip().strip('"') in ("50%", "50.0%", "median"):
            medians = []
            for v in row[1:]:
                v = v.strip().strip('"')
                try:
                    medians.append(float(v))
                except ValueError:
                    medians.append(float("nan"))
            return medians
    # Fall back: take the first row that's all numeric
    for row in rows[1:]:
        try:
            vals = [float(x.strip().strip('"')) for x in row[1:]]
            if vals:
                return vals
        except ValueError:
            continue
    return []


def pick_trunc(medians, min_q: float, min_len: int):
    """Return the first position where median < min_q; else len(medians).
    Result is always capped at len(medians) (the actual read length)."""
    if not medians:
        return 0
    read_length = len(medians)
    for i, q in enumerate(medians):
        if q == q and q < min_q:          # NaN-safe (NaN != NaN)
            if i < min_len:
                # Floor, but never exceed the actual read length
                return min(max(min_len, 0), read_length)
            return i
    return read_length


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("qzv", type=Path, help="demux-summarize visualization (.qzv)")
    p.add_argument("--min-q-fwd", type=float, default=25.0)
    p.add_argument("--min-q-rev", type=float, default=20.0)
    p.add_argument("--min-len", type=int, default=150)
    p.add_argument("--output", type=Path, default=None, help="Write JSON to file as well as stdout")
    args = p.parse_args(argv)

    fwd, rev = load_quality_table(args.qzv)
    fwd_trunc = pick_trunc(fwd, args.min_q_fwd, args.min_len)
    rev_trunc = pick_trunc(rev, args.min_q_rev, args.min_len) if rev else 0

    out = {
        "forward_trunc":          fwd_trunc,
        "reverse_trunc":          rev_trunc,
        "forward_length":         len(fwd),
        "reverse_length":         len(rev) if rev else 0,
        "forward_median_at_trunc": fwd[fwd_trunc - 1] if fwd_trunc and fwd_trunc <= len(fwd) else None,
        "reverse_median_at_trunc": rev[rev_trunc - 1] if rev and rev_trunc and rev_trunc <= len(rev) else None,
        "min_q_fwd":              args.min_q_fwd,
        "min_q_rev":              args.min_q_rev,
        "min_len":                args.min_len,
        "method":                 "median-q-drop",
    }
    text = json.dumps(out, indent=2)
    print(text)
    if args.output:
        args.output.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
