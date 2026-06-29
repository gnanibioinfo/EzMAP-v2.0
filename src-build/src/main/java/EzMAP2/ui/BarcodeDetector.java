package EzMAP2.ui;

import java.io.*;
import java.util.*;
import java.util.zip.*;

/**
 * Detects non-biological barcode/linker prefixes in demultiplexed FASTQ reads
 * inside a QIIME 2 .qza artifact.
 *
 * <p><b>Algorithm:</b></p>
 * <ol>
 *   <li>Open the .qza (ZIP) and find .fastq.gz files from distinct samples.</li>
 *   <li>Read first N reads from each sample.</li>
 *   <li>Cross-sample comparison: within a sample, barcode bases are identical;
 *       across samples, barcode positions differ. The transition point where
 *       cross-sample disagreement drops marks the end of the barcode region.</li>
 *   <li>Search for known 16S primer motifs (515F, 806R) as independent validation.</li>
 *   <li>Return a {@link DetectionResult} with suggested trim-left values.</li>
 * </ol>
 *
 * <p>Runs entirely in-memory; no temp files are created.</p>
 */
public class BarcodeDetector {

    /** Number of reads to sample per FASTQ file. */
    private static final int READS_PER_SAMPLE = 50;

    /** Minimum number of distinct samples needed for cross-sample comparison. */
    private static final int MIN_SAMPLES = 2;

    /** Maximum number of samples to examine (for speed). */
    private static final int MAX_SAMPLES = 6;

    /** If cross-sample mismatch rate at a position exceeds this, it's likely barcode. */
    private static final double BARCODE_MISMATCH_THRESHOLD = 0.30;

    /**
     * Primer definition: a short motif for detection + the full primer length
     * so that trim-left = motif_position + full_primer_length.
     *
     * The motif is what we search for (short enough for reliable fuzzy matching).
     * The fullLength is the total primer length to remove.
     * The motifOffset is where the motif sits within the full primer
     * (0 = motif starts at primer start; >0 = motif is internal to primer).
     */
    private static class PrimerDef {
        final String motif;
        final int fullLength;   // total length of the full primer
        final int motifOffset;  // position of motif within the full primer

        PrimerDef(String motif, int fullLength, int motifOffset) {
            this.motif = motif;
            this.fullLength = fullLength;
            this.motifOffset = motifOffset;
        }
    }

    /**
     * Known forward primers.
     * 515F (Parada): GTGYCAGCMGCCGCGGTAA (19bp)
     * 341F: CCTACGGGNGGCWGCAG (17bp)
     * 338F: CCTACGGGAGGCAGCAG (17bp)
     */
    private static final PrimerDef[] FWD_PRIMERS = {
        new PrimerDef("GTGYCAGCMGCCGCGGTAA", 19, 0),  // 515F full (IUPAC)
        new PrimerDef("GTGCCAGCMGCCGCGGTAA", 19, 0),  // 515F-Y→C variant
        new PrimerDef("GTGTCAGCMGCCGCGGTAA", 19, 0),  // 515F-Y→T variant
        new PrimerDef("CCTACGGGNGGCWGCAG",   17, 0),   // 341F
        new PrimerDef("CCTACGGGAGGCAGCAG",   17, 0),   // 338F
    };

    // For backward-compatible primer pattern arrays (used by detectByPrimerSearch)
    private static final String[] FWD_PRIMER_PATTERNS;
    static {
        FWD_PRIMER_PATTERNS = new String[FWD_PRIMERS.length];
        for (int i = 0; i < FWD_PRIMERS.length; i++) {
            FWD_PRIMER_PATTERNS[i] = FWD_PRIMERS[i].motif;
        }
    }

    /**
     * Known reverse primers (as they appear on R2).
     * 806R (Apprill): GGACTACNVGGGTWTCTAAT (20bp)
     * Motifs are short distinctive subsequences; motifOffset tells where
     * each motif sits within the 20bp full primer.
     */
    private static final PrimerDef[] REV_PRIMERS = {
        new PrimerDef("GGACTACNVGGGTWTCTAAT", 20, 0),  // 806R full (20bp)
        new PrimerDef("GGACTAC",               20, 0),  // 806R start (7bp motif, offset 0)
        new PrimerDef("GACTACHVGGG",           20, 1),  // 806R core (offset 1 from primer start)
        new PrimerDef("TATCTAAT",              20, 12), // 806R tail (offset 12 from primer start)
        new PrimerDef("ATTAGAWACCC",           20, 0),  // 806R reverse-complement start
    };

    private static final String[] REV_PRIMER_PATTERNS;
    static {
        REV_PRIMER_PATTERNS = new String[REV_PRIMERS.length];
        for (int i = 0; i < REV_PRIMERS.length; i++) {
            REV_PRIMER_PATTERNS[i] = REV_PRIMERS[i].motif;
        }
    }

    // ────────────────────────────────────────────────────────────────────────

    /** Result of barcode/linker detection. */
    public static class DetectionResult {
        public final int suggestedTrimLeftF;
        public final int suggestedTrimLeftR;
        public final String forwardDetail;   // human-readable explanation
        public final String reverseDetail;
        public final boolean detected;       // true if any barcode/linker found
        public final int avgReadLenF;        // average forward read length
        public final int avgReadLenR;        // average reverse read length
        public final boolean hasPairedEnd;   // whether R2 files were found
        public final int suggestedTruncF;    // suggested truncation (0 = no truncation)
        public final int suggestedTruncR;

        public DetectionResult(int trimF, int trimR, String fwdDetail, String revDetail,
                               boolean detected, int avgLenF, int avgLenR, boolean paired,
                               int truncF, int truncR) {
            this.suggestedTrimLeftF = trimF;
            this.suggestedTrimLeftR = trimR;
            this.forwardDetail = fwdDetail;
            this.reverseDetail = revDetail;
            this.detected = detected;
            this.avgReadLenF = avgLenF;
            this.avgReadLenR = avgLenR;
            this.hasPairedEnd = paired;
            this.suggestedTruncF = truncF;
            this.suggestedTruncR = truncR;
        }
    }

    // ────────────────────────────────────────────────────────────────────────

    /**
     * Analyze a QIIME 2 .qza artifact and detect barcode/linker prefixes.
     *
     * @param qzaPath path to the demultiplexed .qza file
     * @return detection result (never null; {@code detected=false} if nothing found)
     */
    public static DetectionResult analyze(String qzaPath) {
        return analyze(qzaPath, 460);  // default V3-V4
    }

    /**
     * Analyze a QIIME 2 .qza artifact and detect barcode/linker prefixes.
     *
     * @param qzaPath       path to the demultiplexed .qza file
     * @param ampliconLength expected amplicon length for overlap estimation
     *                       (e.g. 253 for V4, 460 for V3-V4)
     * @return detection result (never null; {@code detected=false} if nothing found)
     */
    public static DetectionResult analyze(String qzaPath, int ampliconLength) {
        try {
            return doAnalyze(qzaPath, ampliconLength);
        } catch (Exception e) {
            return new DetectionResult(0, 0,
                "Analysis failed: " + e.getMessage(), "", false,
                0, 0, false, 0, 0);
        }
    }

    private static DetectionResult doAnalyze(String qzaPath, int ampliconLength) throws Exception {
        // ---- 1. Collect FASTQ entries from the .qza ZIP ----
        Map<String, List<String>> fwdReadsBySample = new LinkedHashMap<>();
        Map<String, List<String>> revReadsBySample = new LinkedHashMap<>();

        try (ZipInputStream zis = new ZipInputStream(
                new BufferedInputStream(new FileInputStream(qzaPath)))) {

            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                String name = entry.getName();

                // .qza structure: <uuid>/data/<sample-id>_*_R[12]_*.fastq.gz
                // or: <uuid>/data/<sample-id>_*_L001_R1_001.fastq.gz
                if (!name.endsWith(".fastq.gz") && !name.endsWith(".fq.gz")) continue;
                if (!name.contains("/data/")) continue;

                // Determine R1 or R2
                String basename = name.substring(name.lastIndexOf('/') + 1);
                boolean isR1 = basename.contains("_R1_") || basename.contains("_R1.");
                boolean isR2 = basename.contains("_R2_") || basename.contains("_R2.");
                if (!isR1 && !isR2) {
                    // Single-end: treat as R1
                    isR1 = true;
                }

                // Extract sample ID from filename (everything before first _)
                String sampleId = extractSampleId(basename);

                Map<String, List<String>> target = isR1 ? fwdReadsBySample : revReadsBySample;

                if (target.size() >= MAX_SAMPLES && !target.containsKey(sampleId)) {
                    continue;  // already have enough samples
                }

                // Read sequences from gzipped FASTQ inside ZIP
                List<String> seqs = readFastqFromZipEntry(zis, READS_PER_SAMPLE);
                target.computeIfAbsent(sampleId, k -> new ArrayList<>()).addAll(seqs);
            }
        }

        boolean hasPaired = !revReadsBySample.isEmpty();

        // ---- 2. Analyze forward reads ----
        int trimF = 0;
        String fwdDetail = "No barcode/linker detected on forward reads.";
        int avgLenF = averageReadLength(fwdReadsBySample);

        if (fwdReadsBySample.size() >= MIN_SAMPLES) {
            int crossSampleTrimF = detectByCrossSampleComparison(fwdReadsBySample);
            int[] primerResultF = detectByPrimerSearchFull(
                fwdReadsBySample, FWD_PRIMER_PATTERNS, FWD_PRIMERS);
            int primerStartF = primerResultF[0];
            int fullTrimF    = primerResultF[1];

            if (crossSampleTrimF > 0 && primerStartF > 0) {
                // Both methods found something — use full trim (barcode + primer)
                trimF = fullTrimF;
                fwdDetail = String.format(
                    "Detected %dbp barcode + %dbp primer on forward reads " +
                    "(total %dbp to trim). Cross-sample analysis found %dbp " +
                    "variable region; primer starts at position %d.",
                    crossSampleTrimF, fullTrimF - primerStartF,
                    fullTrimF, crossSampleTrimF, primerStartF);
            } else if (primerStartF > 0) {
                trimF = fullTrimF;
                fwdDetail = String.format(
                    "Detected primer at position %d on forward reads. " +
                    "Full primer is %dbp — suggests %dbp total non-biological prefix.",
                    primerStartF, fullTrimF - primerStartF, fullTrimF);
            } else if (crossSampleTrimF > 0) {
                trimF = crossSampleTrimF;
                fwdDetail = String.format(
                    "Detected %dbp sample-specific barcode prefix on forward reads " +
                    "(cross-sample analysis). No primer motif found — " +
                    "primer may have already been removed by Cutadapt.",
                    trimF);
            }
        } else if (fwdReadsBySample.size() == 1) {
            int[] primerResultF = detectByPrimerSearchFull(
                fwdReadsBySample, FWD_PRIMER_PATTERNS, FWD_PRIMERS);
            int primerStartF = primerResultF[0];
            int fullTrimF    = primerResultF[1];
            if (primerStartF > 0) {
                trimF = fullTrimF;
                fwdDetail = String.format(
                    "Detected primer at position %d on forward reads (single sample). " +
                    "Full primer is %dbp — suggests %dbp total trim.",
                    primerStartF, fullTrimF - primerStartF, fullTrimF);
            }
        }

        // ---- 3. Analyze reverse reads ----
        int trimR = 0;
        String revDetail = hasPaired ? "No barcode/linker detected on reverse reads." : "";
        int avgLenR = hasPaired ? averageReadLength(revReadsBySample) : 0;

        if (hasPaired && revReadsBySample.size() >= MIN_SAMPLES) {
            int crossSampleTrimR = detectByCrossSampleComparison(revReadsBySample);
            int[] primerResultR = detectByPrimerSearchFull(
                revReadsBySample, REV_PRIMER_PATTERNS, REV_PRIMERS);
            int primerStartR = primerResultR[0];  // where primer begins (= barcode length)
            int fullTrimR    = primerResultR[1];  // barcode + full primer length

            if (crossSampleTrimR > 0 && primerStartR > 0) {
                // Both methods found something — use full trim (barcode + primer)
                trimR = fullTrimR;
                revDetail = String.format(
                    "Detected %dbp barcode + %dbp primer on reverse reads " +
                    "(total %dbp to trim). Cross-sample analysis found %dbp " +
                    "variable region; primer starts at position %d.",
                    crossSampleTrimR, fullTrimR - primerStartR,
                    fullTrimR, crossSampleTrimR, primerStartR);
            } else if (primerStartR > 0) {
                // Primer found but no cross-sample barcode — still trim past primer
                trimR = fullTrimR;
                revDetail = String.format(
                    "Detected primer at position %d on reverse reads. " +
                    "Full primer is %dbp — suggests %dbp total non-biological prefix.",
                    primerStartR, fullTrimR - primerStartR, fullTrimR);
            } else if (crossSampleTrimR > 0) {
                // Only barcode found, no primer — trim barcode only
                trimR = crossSampleTrimR;
                revDetail = String.format(
                    "Detected %dbp sample-specific barcode prefix on reverse reads " +
                    "(cross-sample analysis). No primer motif found — " +
                    "primer may have already been removed by Cutadapt.",
                    trimR);
            }
        } else if (hasPaired && revReadsBySample.size() == 1) {
            int[] primerResultR = detectByPrimerSearchFull(
                revReadsBySample, REV_PRIMER_PATTERNS, REV_PRIMERS);
            int primerStartR = primerResultR[0];
            int fullTrimR    = primerResultR[1];
            if (primerStartR > 0) {
                trimR = fullTrimR;
                revDetail = String.format(
                    "Detected primer at position %d on reverse reads (single sample). " +
                    "Full primer is %dbp — suggests %dbp total trim.",
                    primerStartR, fullTrimR - primerStartR, fullTrimR);
            }
        }

        // ---- 4. Suggest truncation based on read lengths ----
        // After trimming, estimate effective read length and suggest truncation = 0
        // if reads are marginal for overlap
        int effectiveLenF = avgLenF - trimF;
        int effectiveLenR = hasPaired ? avgLenR - trimR : 0;
        int sugTruncF = 0;
        int sugTruncR = 0;

        if (hasPaired && effectiveLenF > 0 && effectiveLenR > 0) {
            // Estimate overlap: effectiveLenF + effectiveLenR - ampliconLen
            // Need at least 20bp overlap for reliable merging
            // If overlap is tight (< 40bp), suggest no truncation (0)
            int estimatedOverlap = effectiveLenF + effectiveLenR - ampliconLength;
            if (estimatedOverlap < 40) {
                sugTruncF = 0;  // no truncation — preserve every base
                sugTruncR = 0;
            } else {
                // Comfortable overlap — can truncate to quality drop-off
                sugTruncF = effectiveLenF - 10;  // leave 10bp safety margin
                sugTruncR = effectiveLenR - 10;
            }
        }

        boolean detected = trimF > 0 || trimR > 0;

        return new DetectionResult(
            trimF, trimR, fwdDetail, revDetail, detected,
            avgLenF, avgLenR, hasPaired, sugTruncF, sugTruncR);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Detection methods
    // ────────────────────────────────────────────────────────────────────────

    /**
     * Compare reads across multiple samples. Barcode positions will have
     * high mismatch rates across samples (different barcode per sample)
     * but low mismatch within each sample.
     *
     * @return estimated barcode length, or 0 if none detected
     */
    private static int detectByCrossSampleComparison(Map<String, List<String>> readsBySample) {
        if (readsBySample.size() < MIN_SAMPLES) return 0;

        // Get one "consensus" read per sample (first read, or most common prefix)
        List<String> representatives = new ArrayList<>();
        for (List<String> reads : readsBySample.values()) {
            if (!reads.isEmpty()) {
                representatives.add(reads.get(0));
            }
        }
        if (representatives.size() < 2) return 0;

        int minLen = representatives.stream().mapToInt(String::length).min().orElse(0);
        if (minLen < 10) return 0;
        int checkLen = Math.min(minLen, 50);  // only check first 50 positions

        // For each position, count how many sample-pairs disagree
        int barcodeEnd = 0;
        int consecutiveAgreements = 0;

        for (int pos = 0; pos < checkLen; pos++) {
            int mismatches = 0;
            int comparisons = 0;

            for (int i = 0; i < representatives.size(); i++) {
                for (int j = i + 1; j < representatives.size(); j++) {
                    comparisons++;
                    if (representatives.get(i).charAt(pos) != representatives.get(j).charAt(pos)) {
                        mismatches++;
                    }
                }
            }

            double mismatchRate = (double) mismatches / comparisons;

            if (mismatchRate >= BARCODE_MISMATCH_THRESHOLD) {
                // This position is variable across samples — likely barcode
                barcodeEnd = pos + 1;
                consecutiveAgreements = 0;
            } else {
                consecutiveAgreements++;
                // Need 5+ consecutive agreements after barcode region to be sure
                if (consecutiveAgreements >= 5 && barcodeEnd > 0) {
                    break;
                }
            }
        }

        // Also verify within-sample consistency at barcode positions
        if (barcodeEnd > 0) {
            for (List<String> reads : readsBySample.values()) {
                if (reads.size() < 2) continue;
                String first = reads.get(0);
                for (int i = 1; i < Math.min(reads.size(), 10); i++) {
                    String prefix1 = first.substring(0, Math.min(barcodeEnd, first.length()));
                    String prefix2 = reads.get(i).substring(0, Math.min(barcodeEnd, reads.get(i).length()));
                    if (!prefix1.equals(prefix2)) {
                        // Within-sample variation at barcode region — might not be barcode
                        // Reduce confidence but don't discard entirely
                        break;
                    }
                }
            }
        }

        return barcodeEnd;
    }

    /**
     * Search for known primer motifs in reads and return the position where
     * the primer starts, which equals the barcode/linker length.
     *
     * @return primer start position, or 0 if not found
     */
    private static int detectByPrimerSearch(Map<String, List<String>> readsBySample,
                                            String[] primerPatterns) {
        // Delegate to the PrimerDef version but return only primer start position
        // (for backward compat — forward primers don't need the full-trim logic
        //  because Cutadapt --p-front handles them)
        int[] result = detectByPrimerSearchFull(readsBySample, primerPatterns, null);
        return result[0];  // primer start position
    }

    /**
     * Result holder for primer search: [primerStartPos, totalTrimLeft].
     * primerStartPos = barcode length (where primer begins).
     * totalTrimLeft  = primerStartPos + fullPrimerLength (everything to remove).
     *
     * If primerDefs is null, totalTrimLeft equals primerStartPos (legacy behavior).
     */
    private static int[] detectByPrimerSearchFull(Map<String, List<String>> readsBySample,
                                                  String[] primerPatterns,
                                                  PrimerDef[] primerDefs) {
        // Collect all reads into a flat list (limit total)
        List<String> allReads = new ArrayList<>();
        for (List<String> reads : readsBySample.values()) {
            for (String r : reads) {
                allReads.add(r);
                if (allReads.size() >= 100) break;
            }
            if (allReads.size() >= 100) break;
        }

        if (allReads.isEmpty()) return new int[]{0, 0};

        // For each primer pattern, search at positions 0..40 in reads.
        // Track votes for primer START position and the associated full-trim value.
        Map<Integer, Integer> positionVotes = new TreeMap<>();
        // Map from primer-start-position → best full-trim-left seen at that position
        Map<Integer, Integer> positionFullTrim = new TreeMap<>();

        for (int pi = 0; pi < primerPatterns.length; pi++) {
            String primerUpper = primerPatterns[pi].toUpperCase();
            int motifLen = primerUpper.length();

            // Determine full primer length and motif offset for this pattern
            int fullPrimerLen = motifLen;  // fallback: motif IS the full primer
            int motifOffset = 0;
            if (primerDefs != null && pi < primerDefs.length) {
                fullPrimerLen = primerDefs[pi].fullLength;
                motifOffset = primerDefs[pi].motifOffset;
            }

            for (String read : allReads) {
                String readUpper = read.toUpperCase();
                if (readUpper.length() < motifLen + 2) continue;

                // Search at each position with fuzzy matching
                for (int pos = 0; pos <= Math.min(40, readUpper.length() - motifLen); pos++) {
                    String sub = readUpper.substring(pos, pos + motifLen);
                    int mismatches = countMismatchesIUPAC(sub, primerUpper);
                    // Allow up to 2 mismatches for short primers, 3 for long ones
                    int maxMismatch = motifLen <= 8 ? 1 : (motifLen <= 15 ? 2 : 3);
                    if (mismatches <= maxMismatch) {
                        // The motif was found at read position 'pos'.
                        // The actual primer START is at: pos - motifOffset
                        int primerStart = Math.max(0, pos - motifOffset);
                        positionVotes.merge(primerStart, 1, Integer::sum);

                        // Full trim = primerStart + fullPrimerLength
                        int fullTrim = primerStart + fullPrimerLen;
                        positionFullTrim.merge(primerStart,
                            fullTrim, Math::max);  // keep the maximum
                    }
                }
            }
        }

        if (positionVotes.isEmpty()) return new int[]{0, 0};

        // Find position with highest votes
        int bestPos = 0;
        int bestVotes = 0;
        for (Map.Entry<Integer, Integer> e : positionVotes.entrySet()) {
            if (e.getValue() > bestVotes) {
                bestVotes = e.getValue();
                bestPos = e.getKey();
            }
        }

        // Require at least 10% of reads to agree on the position
        if (bestVotes < allReads.size() * 0.1) return new int[]{0, 0};

        // Position 0 means primer is at the very start — no barcode prefix
        int fullTrim = positionFullTrim.getOrDefault(bestPos, bestPos);
        return new int[]{bestPos, fullTrim};
    }

    // ────────────────────────────────────────────────────────────────────────
    // IUPAC-aware matching
    // ────────────────────────────────────────────────────────────────────────

    private static int countMismatchesIUPAC(String seq, String pattern) {
        int mm = 0;
        for (int i = 0; i < pattern.length() && i < seq.length(); i++) {
            if (!iupacMatch(seq.charAt(i), pattern.charAt(i))) mm++;
        }
        return mm;
    }

    /** Returns true if base matches the IUPAC ambiguity code. */
    private static boolean iupacMatch(char base, char code) {
        if (base == code) return true;
        base = Character.toUpperCase(base);
        code = Character.toUpperCase(code);
        if (base == code) return true;

        switch (code) {
            case 'N': return true;
            case 'R': return base == 'A' || base == 'G';
            case 'Y': return base == 'C' || base == 'T';
            case 'S': return base == 'G' || base == 'C';
            case 'W': return base == 'A' || base == 'T';
            case 'K': return base == 'G' || base == 'T';
            case 'M': return base == 'A' || base == 'C';
            case 'B': return base == 'C' || base == 'G' || base == 'T';
            case 'D': return base == 'A' || base == 'G' || base == 'T';
            case 'H': return base == 'A' || base == 'C' || base == 'T';
            case 'V': return base == 'A' || base == 'C' || base == 'G';
            default: return false;
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // FASTQ reading utilities
    // ────────────────────────────────────────────────────────────────────────

    /**
     * Read sequences from a gzipped FASTQ stream (inside a ZIP entry).
     * Does NOT close the outer ZipInputStream.
     */
    private static List<String> readFastqFromZipEntry(ZipInputStream zis, int maxReads) {
        List<String> seqs = new ArrayList<>();
        try {
            GZIPInputStream gzis = new GZIPInputStream(new NonClosingInputStream(zis));
            BufferedReader br = new BufferedReader(new InputStreamReader(gzis));
            String line;
            int lineNum = 0;
            while ((line = br.readLine()) != null && seqs.size() < maxReads) {
                lineNum++;
                // FASTQ: line 1 = header (@), line 2 = sequence, line 3 = +, line 4 = quality
                if (lineNum % 4 == 2) {
                    seqs.add(line.trim());
                }
            }
        } catch (IOException e) {
            // Partial read is fine
        }
        return seqs;
    }

    /**
     * Wrapper that prevents GZIPInputStream from closing the underlying ZipInputStream
     * when it finishes reading an entry.
     */
    private static class NonClosingInputStream extends FilterInputStream {
        NonClosingInputStream(InputStream in) { super(in); }
        @Override public void close() throws IOException {
            // Don't close the underlying stream
        }
    }

    /** Extract sample ID from FASTQ filename: everything before the first underscore. */
    private static String extractSampleId(String filename) {
        // Common patterns:
        // SampleID_S1_L001_R1_001.fastq.gz
        // SampleID_R1.fastq.gz
        int idx = filename.indexOf('_');
        return idx > 0 ? filename.substring(0, idx) : filename;
    }

    /** Compute average read length across all samples. */
    private static int averageReadLength(Map<String, List<String>> readsBySample) {
        long totalLen = 0;
        int count = 0;
        for (List<String> reads : readsBySample.values()) {
            for (String r : reads) {
                totalLen += r.length();
                count++;
            }
        }
        return count > 0 ? (int) (totalLen / count) : 0;
    }
}
