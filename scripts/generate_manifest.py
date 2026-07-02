import os
import sys
import re
import json
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
from difflib import SequenceMatcher

def detect_fastq_type(data_path: Path) -> Dict[str, Any]:
    """
    Scans a directory and detects the FASTQ file layout to determine the
    appropriate QIIME2 import method.

    Returns a dict with:
        format:      one of 'PairedEndFastqManifestPhred33V2',
                            'SingleEndFastqManifestPhred33V2',
                            'CasavaOneEightSingleLanePerSampleDirFmt',
                            'EMPPairedEndDirFmt'
        type:        QIIME2 semantic type string
        description: human-readable description
        paired:      True/False
        files_found: count of .fastq.gz files
        samples:     list of detected sample IDs
    """
    # Support all common FASTQ extensions: .fastq.gz, .fq.gz, .fastq, .fq
    # Also check subdirectories one level deep, and handle case-insensitive
    fastq_files = []
    for ext_pattern in ["*.fastq.gz", "*.fq.gz", "*.fastq", "*.fq",
                        "*.FASTQ.gz", "*.FQ.gz", "*.FASTQ", "*.FQ",
                        "*.fastq.GZ", "*.fq.GZ"]:
        fastq_files.extend(data_path.glob(ext_pattern))
    # Deduplicate (case-insensitive OS may return same file) and sort
    seen = set()
    unique_files = []
    for f in sorted(fastq_files, key=lambda x: x.name.lower()):
        if f.resolve() not in seen:
            seen.add(f.resolve())
            unique_files.append(f)
    fastq_files = unique_files

    # If no files in top-level, check one level of subdirectories
    if not fastq_files:
        for sub in sorted(data_path.iterdir()):
            if sub.is_dir():
                for ext_pattern in ["*.fastq.gz", "*.fq.gz", "*.fastq", "*.fq"]:
                    fastq_files.extend(sub.glob(ext_pattern))
        fastq_files = sorted(fastq_files, key=lambda x: x.name.lower())

    filenames = [f.name for f in fastq_files]

    if not filenames:
        return {
            "format": None,
            "type": None,
            "description": "No FASTQ files found (checked .fastq.gz, .fq.gz, .fastq, .fq).",
            "paired": False,
            "files_found": 0,
            "samples": []
        }

    # Common FASTQ extension pattern (matches .fastq.gz, .fq.gz, .fastq, .fq)
    _fq_ext = r"\.(?:fastq|fq)(?:\.gz)?$"

    # ---- Check for Casava 1.8 format ----
    # Pattern: SampleID_S{num}_L{num}_R{1|2}_001.fastq.gz (or .fq.gz etc.)
    casava_re = re.compile(r"(.+?)_S\d+_L\d+_R([12])_001" + _fq_ext, re.IGNORECASE)
    casava_matches = [casava_re.match(fn) for fn in filenames]
    casava_count = sum(1 for m in casava_matches if m)

    if casava_count > len(filenames) * 0.8:
        casava_ids = set(m.group(1) for m in casava_matches if m)
        has_r2 = any(m.group(2) == "2" for m in casava_matches if m)
        if has_r2:
            return {
                "format": "CasavaOneEightSingleLanePerSampleDirFmt",
                "type": "SampleData[PairedEndSequencesWithQuality]",
                "description": "Casava 1.8 paired-end format detected (Illumina demultiplexed output). "
                               "Files follow: SampleID_Sxxx_Lxxx_R1_001.fastq.gz",
                "paired": True,
                "files_found": len(filenames),
                "samples": sorted(casava_ids)
            }
        else:
            return {
                "format": "CasavaOneEightSingleLanePerSampleDirFmt",
                "type": "SampleData[SequencesWithQuality]",
                "description": "Casava 1.8 single-end format detected.",
                "paired": False,
                "files_found": len(filenames),
                "samples": sorted(casava_ids)
            }

    # ---- Check for EMP format ----
    # EMP: forward.fastq.gz, reverse.fastq.gz, barcodes.fastq.gz (or .fq.gz etc.)
    fn_lower = {fn.lower() for fn in filenames}
    emp_bases = {"forward", "reverse", "barcodes"}
    emp_found = all(any(fn_lower_item.startswith(b + ".") for fn_lower_item in fn_lower) for b in emp_bases)
    if emp_found:
        return {
            "format": "EMPPairedEndDirFmt",
            "type": "EMPPairedEndSequences",
            "description": "Earth Microbiome Project (EMP) format detected. "
                           "Files: forward.fastq.gz + reverse.fastq.gz + barcodes.fastq.gz. "
                           "Demultiplexing will be done by QIIME2.",
            "paired": True,
            "files_found": len(filenames),
            "samples": []
        }

    # ---- Standard paired-end (most common user case) ----
    paired_re = re.compile(r"(.+?)[._]R?([12])" + _fq_ext, re.IGNORECASE)
    paired_samples = {}
    for fn in filenames:
        m = paired_re.match(fn)
        if m:
            sid = m.group(1).rstrip('._-')
            read = m.group(2)
            if sid not in paired_samples:
                paired_samples[sid] = set()
            paired_samples[sid].add(read)

    # If most samples have both R1 and R2 → paired-end manifest
    full_pairs = sum(1 for reads in paired_samples.values() if '1' in reads and '2' in reads)
    if full_pairs > 0 and full_pairs >= len(paired_samples) * 0.8:
        return {
            "format": "PairedEndFastqManifestPhred33V2",
            "type": "SampleData[PairedEndSequencesWithQuality]",
            "description": f"Paired-end demultiplexed FASTQ detected ({full_pairs} samples). "
                           f"Files follow: SampleID_R1.fastq.gz / SampleID_R2.fastq.gz (or _1/_2). "
                           f"A manifest file will be generated for QIIME2 import.",
            "paired": True,
            "files_found": len(filenames),
            "samples": sorted(paired_samples.keys())
        }

    # ---- Single-end fallback ----
    single_ids = set()
    single_re = re.compile(r"(.+?)" + _fq_ext, re.IGNORECASE)
    for fn in filenames:
        m = single_re.match(fn)
        if m:
            single_ids.add(m.group(1))

    return {
        "format": "SingleEndFastqManifestPhred33V2",
        "type": "SampleData[SequencesWithQuality]",
        "description": f"Single-end FASTQ files detected ({len(single_ids)} files). "
                       f"A manifest file will be generated for QIIME2 import.",
        "paired": False,
        "files_found": len(filenames),
        "samples": sorted(single_ids)
    }


def read_metadata_ids(metadata_path: str) -> List[str]:
    """Read sample IDs from a QIIME2 metadata TSV (first column, skip header + #q2:types)."""
    ids = []
    with open(metadata_path, 'r') as f:
        header = True
        for line in f:
            line = line.strip()
            if not line:
                continue
            if header:
                header = False
                continue
            if line.startswith('#q2:types') or line.startswith('#q2'):
                continue
            parts = line.split('\t')
            if parts:
                ids.append(parts[0].strip())
    return ids


def fuzzy_match_ids(manifest_ids: List[str], metadata_ids: List[str]) -> Dict[str, Dict[str, Any]]:
    """
    Try to match manifest sample IDs to metadata sample IDs using multiple strategies:
    1. Exact match
    2. Prefix match (metadata ID is a prefix of manifest ID)
    3. Suffix stripping (common sequencing suffixes like -B, -L001, _S1, etc.)
    4. Fuzzy similarity (SequenceMatcher > 0.7)

    Returns a dict:
        { manifest_id: { "matched_to": metadata_id or None,
                         "method": "exact"|"prefix"|"suffix_strip"|"fuzzy"|"unmatched",
                         "confidence": float 0-1 } }
    """
    results = {}
    remaining_meta = list(metadata_ids)

    # Common sequencing suffixes to try stripping from manifest IDs
    strip_patterns = [
        re.compile(r'-[A-Z]$'),          # -B, -L (batch/lane)
        re.compile(r'_S\d+$'),           # _S1, _S12 (Illumina sample number)
        re.compile(r'[-_]L\d+$'),        # -L001, _L001 (lane)
        re.compile(r'[-_]rep\d*$', re.I),# -rep1, _Rep2 (replicate)
    ]

    # Pass 1: exact match
    for mid in manifest_ids:
        if mid in remaining_meta:
            results[mid] = {"matched_to": mid, "method": "exact", "confidence": 1.0}
            remaining_meta.remove(mid)
        else:
            results[mid] = None  # placeholder

    unmatched_manifest = [mid for mid in manifest_ids if results[mid] is None]

    # Pass 2: metadata ID is prefix of manifest ID
    for mid in unmatched_manifest[:]:
        for meta_id in remaining_meta:
            if mid.startswith(meta_id) and len(meta_id) >= 2:
                results[mid] = {"matched_to": meta_id, "method": "prefix",
                                "confidence": len(meta_id) / len(mid)}
                remaining_meta.remove(meta_id)
                unmatched_manifest.remove(mid)
                break

    # Pass 3: strip common suffixes from manifest ID and try matching
    for mid in unmatched_manifest[:]:
        for pattern in strip_patterns:
            stripped = pattern.sub('', mid)
            if stripped != mid and stripped in remaining_meta:
                results[mid] = {"matched_to": stripped, "method": "suffix_strip",
                                "confidence": 0.85}
                remaining_meta.remove(stripped)
                unmatched_manifest.remove(mid)
                break

    # Pass 4: fuzzy matching for remaining
    for mid in unmatched_manifest[:]:
        best_score = 0.0
        best_match = None
        for meta_id in remaining_meta:
            score = SequenceMatcher(None, mid.lower(), meta_id.lower()).ratio()
            if score > best_score:
                best_score = score
                best_match = meta_id
        if best_score >= 0.65 and best_match:
            results[mid] = {"matched_to": best_match, "method": "fuzzy",
                            "confidence": round(best_score, 3)}
            remaining_meta.remove(best_match)
            unmatched_manifest.remove(mid)

    # Mark remaining as unmatched
    for mid in unmatched_manifest:
        results[mid] = {"matched_to": None, "method": "unmatched", "confidence": 0.0}

    return results


def generate_manifest(raw_data_dir: str, output_file: str = "samples_manifest.tsv",
                      metadata_file: str = None) -> None:
    """
    Scans a directory for FASTQ.GZ files, groups paired-end reads, and generates
    a tab-separated manifest file with absolute POSIX paths.

    If --metadata is provided:
      1. Detects FASTQ type and writes fastq_type.json
      2. Matches manifest sample IDs to metadata IDs (fuzzy matching)
      3. Writes reconciliation.json with the mapping
      4. If all IDs match or can be reconciled, writes the manifest using
         metadata IDs (so QIIME2 won't complain)

    Args:
        raw_data_dir: Path to directory containing FASTQ files.
        output_file:  Path for the output manifest file.
        metadata_file: Optional path to QIIME2 metadata TSV.
    """
    data_path = Path(raw_data_dir).resolve()
    if not data_path.is_dir():
        print(f"Error: Directory not found at '{raw_data_dir}'")
        sys.exit(1)

    print(f"Scanning directory: {data_path}")

    # ---- Step 0: Detect FASTQ type ----
    fastq_info = detect_fastq_type(data_path)
    output_dir = Path(output_file).parent
    fastq_type_file = output_dir / "fastq_type.json"

    with open(fastq_type_file, 'w') as f:
        json.dump(fastq_info, f, indent=2)
    print(f"FASTQ type detection: {fastq_type_file}")
    print(f"  Format:  {fastq_info['format']}")
    print(f"  Type:    {fastq_info['type']}")
    print(f"  Paired:  {fastq_info['paired']}")
    print(f"  Files:   {fastq_info['files_found']}")

    if fastq_info['format'] is None:
        print("Error: No FASTQ files found.")
        sys.exit(1)

    # For non-manifest formats (EMP, Casava), we just write the type info
    # and the pipeline will use direct import (no manifest needed)
    if fastq_info['format'] in ('CasavaOneEightSingleLanePerSampleDirFmt', 'EMPPairedEndDirFmt'):
        print(f"\n{fastq_info['description']}")
        print("No manifest file needed — QIIME2 will import directly from the directory.")
        # Still write reconciliation if metadata provided
        if metadata_file and fastq_info['samples']:
            _write_reconciliation(fastq_info['samples'], metadata_file, output_dir)
        return

    # ---- Step 1: Build sample→path mapping ----
    _fq_ext_manifest = r"\.(?:fastq|fq)(?:\.gz)?$"
    pattern = re.compile(
        r"(.+?)[._]R?([12])" + _fq_ext_manifest + r"|(.+?)" + _fq_ext_manifest,
        re.IGNORECASE
    )
    samples: Dict[str, Dict[str, str]] = {}

    # Collect all FASTQ files with any common extension
    all_fq = []
    for ext_pat in ["*.fastq.gz", "*.fq.gz", "*.fastq", "*.fq"]:
        all_fq.extend(data_path.glob(ext_pat))
    # Also check one level of subdirectories
    if not all_fq:
        for sub in data_path.iterdir():
            if sub.is_dir():
                for ext_pat in ["*.fastq.gz", "*.fq.gz", "*.fastq", "*.fq"]:
                    all_fq.extend(sub.glob(ext_pat))

    for fpath in sorted(set(all_fq)):
        filename = fpath.name
        match = pattern.match(filename)
        if match:
            if match.group(1) and match.group(2):
                sample_id = match.group(1).rstrip('._-')
                read_type = f"R{match.group(2)}"
            elif match.group(3):
                sample_id = match.group(3)
                read_type = "R1"

            absolute_path = fpath.resolve().as_posix()
            if sample_id not in samples:
                samples[sample_id] = {'R1': '', 'R2': ''}
            samples[sample_id][read_type] = absolute_path
        else:
            print(f"Warning: Skipping file with unrecognized naming: {filename}")

    # ---- Step 2: Reconcile with metadata (if provided) ----
    id_mapping = {}   # manifest_id → final_id (may be remapped to metadata ID)
    reconciliation = None

    if metadata_file and os.path.isfile(metadata_file):
        metadata_ids = read_metadata_ids(metadata_file)
        manifest_ids = sorted(samples.keys())

        print(f"\n--- Sample ID Reconciliation ---")
        print(f"Manifest IDs ({len(manifest_ids)}): {', '.join(manifest_ids)}")
        print(f"Metadata IDs ({len(metadata_ids)}): {', '.join(metadata_ids)}")

        reconciliation = fuzzy_match_ids(manifest_ids, metadata_ids)

        # Build the final ID mapping
        all_matched = True
        for mid, info in reconciliation.items():
            if info['matched_to']:
                id_mapping[mid] = info['matched_to']
                status = f"✓ {info['method']} (conf={info['confidence']:.2f})"
            else:
                id_mapping[mid] = mid  # keep original
                all_matched = False
                status = "✗ NO MATCH"
            print(f"  {mid:20s} → {id_mapping[mid]:20s}  [{status}]")

        # Detect metadata IDs with no FASTQ
        matched_meta = set(info['matched_to'] for info in reconciliation.values()
                          if info['matched_to'])
        orphan_meta = [m for m in metadata_ids if m not in matched_meta]
        if orphan_meta:
            print(f"\n  Metadata IDs with no matching FASTQ: {', '.join(orphan_meta)}")

        # Write reconciliation JSON for the Java GUI to read
        recon_output = {
            "manifest_ids": manifest_ids,
            "metadata_ids": metadata_ids,
            "mapping": {mid: {**info, "final_id": id_mapping.get(mid, mid)}
                        for mid, info in reconciliation.items()},
            "orphan_metadata_ids": orphan_meta,
            "all_matched": all_matched,
            "needs_user_approval": not all_matched or any(
                info['method'] != 'exact' for info in reconciliation.values()
            )
        }
        recon_file = output_dir / "reconciliation.json"
        with open(recon_file, 'w') as f:
            json.dump(recon_output, f, indent=2)
        print(f"\nReconciliation report: {recon_file}")
    else:
        # No metadata — just use manifest IDs as-is
        for sid in samples:
            id_mapping[sid] = sid

    # ---- Step 3: Write manifest ----
    output_path = Path(output_file).resolve()
    with open(output_path, 'w') as outfile:
        if fastq_info['paired']:
            outfile.write("sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n")
            for manifest_id in sorted(samples.keys()):
                r1 = samples[manifest_id]['R1']
                r2 = samples[manifest_id]['R2']
                if not r1:
                    print(f"Warning: Skipping '{manifest_id}' — R1/Forward read not found.")
                    continue
                final_id = id_mapping.get(manifest_id, manifest_id)
                outfile.write(f"{final_id}\t{r1}\t{r2}\n")
        else:
            outfile.write("sample-id\tabsolute-filepath\n")
            for manifest_id in sorted(samples.keys()):
                r1 = samples[manifest_id]['R1']
                if not r1:
                    continue
                final_id = id_mapping.get(manifest_id, manifest_id)
                outfile.write(f"{final_id}\t{r1}\n")

    print("-" * 40)
    print(f"Manifest file: {output_path}")
    print(f"  Samples: {len(samples)}")
    if metadata_file:
        remapped = sum(1 for mid, fid in id_mapping.items() if mid != fid)
        if remapped:
            print(f"  IDs remapped to match metadata: {remapped}")
    print("Paths are absolute (POSIX) — QIIME2 will resolve them directly.")

    # ---- Step 4: R1/R2 orientation check (paired-end only) ----
    if fastq_info['paired']:
        _verify_read_orientation(samples)


def _verify_read_orientation(samples: Dict[str, Dict[str, str]]):
    """
    Sanity-check that R1 files contain forward reads and R2 files contain reverse reads.
    Reads the first sequence from one R1 and one R2 file and checks for known primer motifs.
    Warns if R1 appears to contain reverse-primer sequence (=likely swap).
    """
    import gzip

    # Known primer start motifs (first 10bp) — enough for orientation check
    FWD_MOTIFS = [
        "GTGYCAGCMG",   # 515F (V4)
        "GTGCCAGCMG",   # 515F variant
        "GTGTCAGCMG",   # 515F variant
        "CCTACGGGNG",   # 341F (V3-V4)
        "CCTACGGGAG",   # 338F
        "CTTGGTCATT",   # ITS1-F
        "GCATCGATGA",   # ITS2-F
    ]
    REV_MOTIFS = [
        "GGACTACNVG",   # 806R
        "GGACTACHVG",   # 806R variant
        "GACTACHVGG",   # 806R offset
        "TCCTCCGCTT",   # ITS4-R / ITS2-R
        "GCTGCGTTCT",   # ITS-R
    ]

    def iupac_match(seq: str, motif: str) -> bool:
        """Check if seq starts with motif (IUPAC-aware, allows 2 mismatches)."""
        if len(seq) < len(motif):
            return False
        mm = 0
        iupac = {
            'N': set('ACGT'), 'R': set('AG'), 'Y': set('CT'),
            'S': set('GC'),   'W': set('AT'), 'K': set('GT'),
            'M': set('AC'),   'B': set('CGT'), 'D': set('AGT'),
            'H': set('ACT'),  'V': set('ACG'),
        }
        for i in range(len(motif)):
            s = seq[i].upper()
            m = motif[i].upper()
            if s == m:
                continue
            if m in iupac and s in iupac[m]:
                continue
            mm += 1
            if mm > 2:
                return False
        return True

    def read_first_seq(filepath: str) -> Optional[str]:
        """Read the first sequence from a FASTQ (optionally gzipped)."""
        try:
            if filepath.endswith('.gz'):
                with gzip.open(filepath, 'rt') as f:
                    f.readline()  # header
                    return f.readline().strip()
            else:
                with open(filepath, 'r') as f:
                    f.readline()
                    return f.readline().strip()
        except Exception:
            return None

    # Check up to 3 samples
    checked = 0
    r1_has_fwd = 0; r1_has_rev = 0
    r2_has_fwd = 0; r2_has_rev = 0

    for sid in sorted(samples.keys()):
        r1_path = samples[sid].get('R1', '')
        r2_path = samples[sid].get('R2', '')
        if not r1_path or not r2_path:
            continue

        r1_seq = read_first_seq(r1_path)
        r2_seq = read_first_seq(r2_path)
        if not r1_seq or not r2_seq:
            continue

        # Check R1 against forward and reverse primers
        # Search within first 40bp (in case of barcodes/linkers)
        for offset in range(min(30, len(r1_seq) - 10)):
            sub = r1_seq[offset:]
            for motif in FWD_MOTIFS:
                if iupac_match(sub, motif):
                    r1_has_fwd += 1
                    break
            else:
                continue
            break
        for offset in range(min(30, len(r1_seq) - 10)):
            sub = r1_seq[offset:]
            for motif in REV_MOTIFS:
                if iupac_match(sub, motif):
                    r1_has_rev += 1
                    break
            else:
                continue
            break

        # Check R2
        for offset in range(min(30, len(r2_seq) - 10)):
            sub = r2_seq[offset:]
            for motif in FWD_MOTIFS:
                if iupac_match(sub, motif):
                    r2_has_fwd += 1
                    break
            else:
                continue
            break
        for offset in range(min(30, len(r2_seq) - 10)):
            sub = r2_seq[offset:]
            for motif in REV_MOTIFS:
                if iupac_match(sub, motif):
                    r2_has_rev += 1
                    break
            else:
                continue
            break

        checked += 1
        if checked >= 3:
            break

    if checked == 0:
        return

    print(f"\n--- R1/R2 Orientation Check ({checked} samples) ---")
    print(f"  R1 files → forward primer found: {r1_has_fwd}, reverse primer found: {r1_has_rev}")
    print(f"  R2 files → forward primer found: {r2_has_fwd}, reverse primer found: {r2_has_rev}")

    if r1_has_rev > 0 and r1_has_fwd == 0:
        print(f"  ⚠ WARNING: R1 files contain REVERSE primer sequences!")
        print(f"  ⚠ This suggests R1 and R2 may be SWAPPED in the original data.")
        print(f"  ⚠ The quality plot will show Forward/Reverse quality inverted.")
        print(f"  ⚠ If denoising fails or merging is poor, consider swapping R1↔R2.")
    elif r2_has_fwd > 0 and r2_has_rev == 0:
        print(f"  ⚠ WARNING: R2 files contain FORWARD primer sequences!")
        print(f"  ⚠ This suggests R1 and R2 may be SWAPPED in the original data.")
    elif r1_has_fwd > 0 and r2_has_rev > 0:
        print(f"  ✓ R1/R2 orientation looks correct (R1=forward, R2=reverse).")
    elif r1_has_fwd == 0 and r1_has_rev == 0:
        print(f"  ℹ No primer motifs detected — primers may already be removed.")
        print(f"  ℹ R1/R2 orientation cannot be verified from sequence alone.")


def _write_reconciliation(fastq_ids: List[str], metadata_file: str, output_dir: Path):
    """Write reconciliation for non-manifest import formats."""
    metadata_ids = read_metadata_ids(metadata_file)
    reconciliation = fuzzy_match_ids(fastq_ids, metadata_ids)
    recon_output = {
        "manifest_ids": fastq_ids,
        "metadata_ids": metadata_ids,
        "mapping": {mid: {**info, "final_id": info.get('matched_to', mid) or mid}
                    for mid, info in reconciliation.items()},
        "orphan_metadata_ids": [m for m in metadata_ids
                                 if m not in set(i['matched_to'] for i in reconciliation.values() if i['matched_to'])],
        "all_matched": all(info['matched_to'] for info in reconciliation.values()),
        "needs_user_approval": True
    }
    recon_file = output_dir / "reconciliation.json"
    with open(recon_file, 'w') as f:
        json.dump(recon_output, f, indent=2)
    print(f"Reconciliation report: {recon_file}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_manifest.py <fastq_dir> [output_file] [--metadata <metadata.tsv>]")
        print("\nExample:")
        print("  python generate_manifest.py ./raw_data")
        print("  python generate_manifest.py ./raw_data --metadata ./metadata.tsv")
        sys.exit(1)

    input_dir = sys.argv[1]

    # Parse optional args
    metadata_arg = None
    output_arg = None
    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == '--metadata' and i + 1 < len(sys.argv):
            metadata_arg = sys.argv[i + 1]
            i += 2
        elif not sys.argv[i].startswith('--'):
            output_arg = sys.argv[i]
            i += 1
        else:
            i += 1

    if output_arg is None:
        output_arg = str(Path(input_dir) / "samples_manifest.tsv")

    generate_manifest(input_dir, output_arg, metadata_arg)
