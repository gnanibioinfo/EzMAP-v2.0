package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Expert Mode — Step 6: Phylogeny + BIOM export + navigate to Results.
 *
 * Runs three pipeline steps:
 *   1. Phylogenetic tree: qiime phylogeny align-to-tree-mafft-fasttree
 *   2. Export BIOM: qiime tools export → biom add-metadata (taxonomy)
 *   3. Export tree, rep-seqs, metadata copies
 *
 * Then navigates to ResultsSummaryPage to view QC and launch Shiny.
 */
public class DownstreamPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    // Input pickers (auto-filled from previous steps)
    private final DirectoryPicker repSeqsPicker;
    private final DirectoryPicker tablePicker;
    private final DirectoryPicker taxonomyPicker;
    private final DirectoryPicker metadataPicker;

    // Controls
    private final PrimaryButton runBtn = new PrimaryButton("Build Phylogeny & Export  \u2192");
    private final OutlineButton stopBtn = new OutlineButton("Stop");
    private final JLabel statusLabel = new JLabel(" ");
    private final LogConsole console = new LogConsole();
    private final JTextArea cmdPreview = new JTextArea(4, 60);

    private volatile QiimeCommand runningCmd;

    public DownstreamPage(WizardController wizard) {
        super("Expert Mode — Step 7: Phylogeny & Export",
              "Build a phylogenetic tree from your representative sequences, export results, " +
              "and prepare data for downstream analysis.");
        this.wizard = wizard;

        // ---- Card 1: Input files ----
        Card inputCard = new Card("1 \u00B7 Input Artifacts");

        JLabel repCaption = caption("Representative sequences (.qza):");
        repCaption.setToolTipText("Unique ASV/OTU sequences from the denoising step. Used to build the phylogenetic tree.");
        inputCard.row(repCaption);
        repSeqsPicker = new DirectoryPicker("rep-seqs.qza", f -> refreshRunState(), true);
        inputCard.row(repSeqsPicker).gap(6);

        JLabel tableCaption = caption("Feature table (.qza):");
        tableCaption.setToolTipText("Feature (ASV/OTU) abundance table from denoising. Will be exported as BIOM format with taxonomy annotations.");
        inputCard.row(tableCaption);
        tablePicker = new DirectoryPicker("table.qza", f -> refreshRunState(), true);
        inputCard.row(tablePicker).gap(6);

        JLabel taxCaption = caption("Taxonomy (.qza) — from classification step:");
        taxCaption.setToolTipText("Taxonomy assignments from the classification step. Will be merged into the BIOM table for downstream analysis.");
        inputCard.row(taxCaption);
        taxonomyPicker = new DirectoryPicker("taxonomy.qza", f -> refreshRunState(), true);
        inputCard.row(taxonomyPicker).gap(6);

        JLabel metaCaption = caption("Sample metadata (.tsv):");
        metaCaption.setToolTipText("Tab-separated metadata file with sample IDs and experimental variables. Used in downstream R Shiny analysis for grouping and statistical tests.");
        inputCard.row(metaCaption);
        metadataPicker = new DirectoryPicker("metadata.tsv", f -> {}, true);
        inputCard.row(metadataPicker);

        add(inputCard);

        // ---- Card 2: Run ----
        Card runCard = new Card("2 \u00B7 Build & Export");

        runCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Pipeline steps",
                "This will: (1) align sequences and build a rooted phylogenetic tree, " +
                "(2) export the feature table as BIOM with taxonomy, " +
                "(3) export the tree as .nwk, and (4) copy metadata. " +
                "Then you'll see the Results Summary page with QC stats and Shiny launch."))
               .gap(8);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        runCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 220));
        runCard.row(console);
        add(runCard);

        // ---- Card 3: Command Preview ----
        Card previewCard = new Card("3 \u00B7 QIIME2 Command Preview");
        previewCard.row(new InfoBanner(InfoBanner.Kind.INFO, "Pipeline commands",
                "These QIIME2 commands will be executed in sequence.")).gap(6);
        cmdPreview.setEditable(false);
        cmdPreview.setFont(Theme.FONT_MONO);
        cmdPreview.setBackground(new Color(0x1E, 0x29, 0x3B));
        cmdPreview.setForeground(new Color(0xA5, 0xD6, 0xFF));
        cmdPreview.setBorder(BorderFactory.createEmptyBorder(10, 12, 10, 12));
        cmdPreview.setLineWrap(true);
        cmdPreview.setWrapStyleWord(true);
        JScrollPane previewScroll = new JScrollPane(cmdPreview);
        previewScroll.setPreferredSize(new Dimension(0, 100));
        previewScroll.setBorder(BorderFactory.createLineBorder(new Color(0x33, 0x44, 0x55)));
        previewCard.row(previewScroll);
        add(previewCard);

        // ---- Wiring ----
        runBtn.setEnabled(false);
        stopBtn.setEnabled(false);
        runBtn.addActionListener(e -> executePhylogenyAndExport());
        stopBtn.addActionListener(e -> {
            if (runningCmd != null) runningCmd.cancel();
        });
    }

    @Override
    public void onShown() {
        // Auto-fill from wizard properties
        String repSeqs = wizard.get("rep-seqs.qza");
        if (repSeqs != null && repSeqsPicker.isEmpty()) repSeqsPicker.setPath(repSeqs);

        String table = wizard.get("table.qza");
        if (table != null && tablePicker.isEmpty()) tablePicker.setPath(table);

        String tax = wizard.get("taxonomy.qza");
        if (tax != null && taxonomyPicker.isEmpty()) taxonomyPicker.setPath(tax);

        String meta = wizard.get("metadata.tsv");
        if (meta != null && metadataPicker.isEmpty()) metadataPicker.setPath(meta);

        refreshRunState();
        refreshCmdPreview();
    }

    private void refreshCmdPreview() {
        String repSeqs = repSeqsPicker.isEmpty() ? "<rep-seqs.qza>" : repSeqsPicker.getPath();
        String table = tablePicker.isEmpty() ? "<table.qza>" : tablePicker.getPath();
        String taxonomy = taxonomyPicker.isEmpty() ? "<taxonomy.qza>" : taxonomyPicker.getPath();
        String outDir = wizard.get("output.dir", ".");

        StringBuilder sb = new StringBuilder();
        sb.append("# Step 1: Build phylogenetic tree\n");
        sb.append("qiime phylogeny align-to-tree-mafft-fasttree \\\n");
        sb.append("  --i-sequences ").append(repSeqs).append(" \\\n");
        sb.append("  --o-alignment aligned-rep-seqs.qza \\\n");
        sb.append("  --o-masked-alignment masked-aligned.qza \\\n");
        sb.append("  --o-tree unrooted-tree.qza \\\n");
        sb.append("  --o-rooted-tree rooted-tree.qza\n\n");
        sb.append("# Step 2-3: Export BIOM + taxonomy\n");
        sb.append("qiime tools export --input-path ").append(table).append(" ...\n");
        sb.append("qiime tools export --input-path ").append(taxonomy).append(" ...\n");
        sb.append("biom add-metadata -i feature-table.biom --observation-metadata-fp taxonomy.tsv ...");
        cmdPreview.setText(sb.toString());
        cmdPreview.setCaretPosition(0);
    }

    private void refreshRunState() {
        runBtn.setEnabled(!repSeqsPicker.isEmpty() && !tablePicker.isEmpty()
                && !taxonomyPicker.isEmpty());
    }

    private void executePhylogenyAndExport() {
        runBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        statusLabel.setText("<html><span style='color:#64748B'>Building phylogeny\u2026</span></html>");
        console.clear();

        final String repSeqs = repSeqsPicker.getPath();
        final String table = tablePicker.getPath();
        final String taxonomy = taxonomyPicker.getPath();
        final String metadata = metadataPicker.isEmpty() ? null : metadataPicker.getPath();
        final String outDir = wizard.get("output.dir",
                new File(repSeqs).getParent());

        new Thread(() -> {
            try {
                new File(outDir).mkdirs();

                // Create bundle subfolder
                String bundleDir = outDir + File.separator + "bundle";
                new File(bundleDir).mkdirs();

                // ============================================================
                // Step 1: Build phylogenetic tree
                // ============================================================
                SwingUtilities.invokeLater(() ->
                        statusLabel.setText("<html><span style='color:#64748B'>Step 1/4: Building phylogenetic tree\u2026</span></html>"));

                String alignedQza = outDir + File.separator + "aligned-rep-seqs.qza";
                String maskedQza  = outDir + File.separator + "masked-aligned-rep-seqs.qza";
                String treeQza    = outDir + File.separator + "unrooted-tree.qza";
                String rootedQza  = outDir + File.separator + "rooted-tree.qza";

                // Keep --verbose for full MAFFT/FastTree progress, but tee it to
                // the pipeline log file instead of streaming it back through the
                // pipe this app reads. Streaming MAFFT's high-volume verbose output
                // to our non-TTY reader pipe aborts MAFFT mid-run (Expert Mode used
                // to fail here while Easy Mode, which logs to a file, did not).
                String phyloLogHost = outDir + File.separator + "logs" + File.separator + "pipeline.log";
                new File(outDir, "logs").mkdirs();
                String phyloLogWsl = QiimeCommand.toWsl(phyloLogHost);
                console.info("Detailed MAFFT/FastTree progress is being written to: " + phyloLogHost);

                QiimeCommand treeCmd = new QiimeCommand("qiime phylogeny align-to-tree-mafft-fasttree")
                        .arg("--i-sequences", repSeqs)
                        .arg("--o-alignment", alignedQza)
                        .arg("--o-masked-alignment", maskedQza)
                        .arg("--o-tree", treeQza)
                        .arg("--o-rooted-tree", rootedQza)
                        .flag("--verbose")
                        .teeOutputTo(phyloLogWsl)
                        .workDir(outDir);

                runningCmd = treeCmd;
                int exitTree = treeCmd.run(console);

                if (exitTree != 0) {
                    // The alignment/tree step is the most memory-hungry part of
                    // the pipeline. When MAFFT exits non-zero with no error text
                    // it has almost always been killed by the WSL out-of-memory
                    // killer. Diagnose the environment and tell the user plainly.
                    final TreeFailureInfo info = diagnoseTreeFailure();
                    SwingUtilities.invokeLater(() -> {
                        statusLabel.setText("<html><span style='color:#DC2626'>"
                                + "\u2718 Tree build failed \u2014 likely out of memory</span></html>");
                        reportTreeFailure(info);
                    });
                    return;
                }

                // ============================================================
                // Step 2: Export tree as .nwk
                // ============================================================
                SwingUtilities.invokeLater(() ->
                        statusLabel.setText("<html><span style='color:#64748B'>Step 2/4: Exporting tree\u2026</span></html>"));

                String treeExportDir = outDir + File.separator + "tree-export";
                QiimeCommand exportTree = new QiimeCommand("qiime tools export")
                        .arg("--input-path", rootedQza)
                        .arg("--output-path", treeExportDir)
                        .workDir(outDir);
                runningCmd = exportTree;
                exportTree.run(console);

                // Move tree.nwk to bundle
                File treeNwk = new File(treeExportDir, "tree.nwk");
                File treeTarget = new File(bundleDir, "rooted-tree.nwk");
                if (treeNwk.exists()) treeNwk.renameTo(treeTarget);

                // ============================================================
                // Step 3: Export feature table as BIOM + add taxonomy
                // ============================================================
                SwingUtilities.invokeLater(() ->
                        statusLabel.setText("<html><span style='color:#64748B'>Step 3/4: Exporting BIOM with taxonomy\u2026</span></html>"));

                // Export table.qza → BIOM
                String tableExportDir = outDir + File.separator + "table-export";
                QiimeCommand exportTable = new QiimeCommand("qiime tools export")
                        .arg("--input-path", table)
                        .arg("--output-path", tableExportDir)
                        .workDir(outDir);
                runningCmd = exportTable;
                exportTable.run(console);

                // Export taxonomy.qza → TSV
                String taxExportDir = outDir + File.separator + "taxonomy-export";
                QiimeCommand exportTax = new QiimeCommand("qiime tools export")
                        .arg("--input-path", taxonomy)
                        .arg("--output-path", taxExportDir)
                        .workDir(outDir);
                runningCmd = exportTax;
                exportTax.run(console);

                // Copy taxonomy.tsv to bundle
                File taxTsv = new File(taxExportDir, "taxonomy.tsv");
                File taxTarget = new File(bundleDir, "taxonomy.tsv");
                if (taxTsv.exists()) copyFile(taxTsv, taxTarget);

                // Prepare biom-compatible taxonomy header
                // sed 's/Feature ID/#OTUID/' 's/Taxon/taxonomy/' 's/Confidence/confidence/'
                String biomTaxTsv = outDir + File.separator + "biom-taxonomy.tsv";
                if (taxTsv.exists()) {
                    QiimeCommand.runBash(
                            "sed '1s/Feature ID/#OTUID/; 1s/Taxon/taxonomy/; 1s/Confidence/confidence/' "
                            + "\"" + taxTsv.getAbsolutePath() + "\" > \"" + biomTaxTsv + "\"",
                            new File(outDir), console);
                }

                // Add taxonomy metadata to BIOM
                File biomFile = new File(tableExportDir, "feature-table.biom");
                File biomTarget = new File(bundleDir, "feature-table.biom");
                if (biomFile.exists()) {
                    copyFile(biomFile, biomTarget); // plain BIOM without taxonomy

                    File biomTaxFile = new File(biomTaxTsv);
                    if (biomTaxFile.exists()) {
                        String biomWithTax = bundleDir + File.separator + "feature-table-tax.biom";
                        QiimeCommand.runBash(
                                "biom add-metadata -i \"" + biomTarget.getAbsolutePath()
                                + "\" -o \"" + biomWithTax
                                + "\" --observation-metadata-fp \"" + biomTaxTsv
                                + "\" --sc-separated taxonomy 2>/dev/null || "
                                + "cp \"" + biomTarget.getAbsolutePath() + "\" \"" + biomWithTax + "\"",
                                new File(outDir), console);
                    }
                }

                // ============================================================
                // Step 4: Copy remaining files to bundle
                // ============================================================
                SwingUtilities.invokeLater(() ->
                        statusLabel.setText("<html><span style='color:#64748B'>Step 4/4: Packaging bundle\u2026</span></html>"));

                // Export rep-seqs as FASTA
                String seqExportDir = outDir + File.separator + "seqs-export";
                QiimeCommand exportSeqs = new QiimeCommand("qiime tools export")
                        .arg("--input-path", repSeqs)
                        .arg("--output-path", seqExportDir)
                        .workDir(outDir);
                runningCmd = exportSeqs;
                exportSeqs.run(console);

                File fastaFile = new File(seqExportDir, "dna-sequences.fasta");
                File fastaTarget = new File(bundleDir, "rep-seqs.fasta");
                if (fastaFile.exists()) fastaFile.renameTo(fastaTarget);

                // Copy metadata if provided
                if (metadata != null) {
                    File metaSrc = new File(metadata);
                    if (metaSrc.exists()) {
                        copyFile(metaSrc, new File(bundleDir, "metadata.tsv"));
                    }
                }

                // Copy denoising stats if available
                String statsFile = wizard.get("denoising-stats.qza");
                if (statsFile != null) {
                    File statsQza = new File(statsFile);
                    if (statsQza.exists()) {
                        // Already exported in denoising step — check for TSV
                        File statsTsv = new File(outDir, "denoising-stats.tsv");
                        if (statsTsv.exists()) {
                            copyFile(statsTsv, new File(bundleDir, "denoising-stats.tsv"));
                        }
                    }
                }

                // Store final output dir
                wizard.put("output.dir", outDir);
                wizard.put("bundle.dir", bundleDir);

                SwingUtilities.invokeLater(() -> {
                    statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Export complete</span></html>");
                    console.ok("Bundle ready: " + bundleDir);
                    console.ok("Navigating to Results Summary\u2026");
                    stepComplete = true;
                    notifyStepCompletion();

                    // Navigate to ResultsSummaryPage
                    ResultsSummaryPage resultsPage = (ResultsSummaryPage) wizard.getPages().get("results-summary");
                    if (resultsPage != null) {
                        resultsPage.loadResults(outDir);
                        // Add results-summary to the flow and navigate
                        java.util.List<String> flow = new java.util.ArrayList<>(wizard.getActiveFlow());
                        java.util.List<String> labels = new java.util.ArrayList<>(wizard.getActiveLabels());
                        if (!flow.contains("results-summary")) {
                            flow.add("results-summary");
                            labels.add("Results");
                        }
                        wizard.setActiveFlow(flow, labels);
                        wizard.showId("results-summary");
                    }
                });

            } catch (Exception ex) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Error: " + ex.getMessage());
                    statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Error</span></html>");
                });
            } finally {
                SwingUtilities.invokeLater(() -> {
                    runBtn.setEnabled(true);
                    stopBtn.setEnabled(false);
                });
            }
        }).start();
    }

    // ---- Helpers ----

    private static void copyFile(File src, File dest) {
        try {
            java.nio.file.Files.copy(src.toPath(), dest.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            // Silently skip if copy fails
        }
    }

    // ================================================================
    //  Tree-build failure diagnosis (out-of-memory detection)
    // ================================================================

    /** Collected evidence about why the phylogeny step failed. */
    private static final class TreeFailureInfo {
        boolean oom;          // confirmed OOM kill found in the kernel log
        boolean lowMem;       // little memory was actually available
        boolean diskFull;     // /tmp is full
        String  free;         // `free -m` output
        String  df;           // `df -h /tmp` output
        String  dmesg;        // matching kernel OOM lines (may be empty/blocked)
        int     wslMemMb  = -1; // total memory WSL currently has
        int     availMb   = -1; // memory that was actually available

        /** One of: "oom", "disk", "unknown". Drives the message shown. */
        String category() {
            if (oom || lowMem) return "oom";
            if (diskFull)      return "disk";
            return "unknown";
        }
    }

    /**
     * Probe the WSL environment after a tree-build failure to confirm the
     * cause. Runs quick, read-only commands (free / df / dmesg). Safe to call
     * from a background thread; never throws.
     */
    private TreeFailureInfo diagnoseTreeFailure() {
        TreeFailureInfo info = new TreeFailureInfo();
        info.free  = captureWsl("free -m");
        info.df    = captureWsl("df -h /tmp");
        // dmesg is often restricted for non-root users; tolerate failure.
        info.dmesg = captureWsl(
                "dmesg 2>/dev/null | grep -iE 'out of memory|killed process|oom-kill' | tail -n 8 || true");

        String d = info.dmesg == null ? "" : info.dmesg.toLowerCase();
        info.oom = d.contains("out of memory") || d.contains("killed process") || d.contains("oom-kill");
        info.diskFull = info.df != null && info.df.contains("100%");
        info.wslMemMb = parseMemTotalMb(info.free);
        info.availMb  = parseMemAvailMb(info.free);
        // Treat as memory-driven only if memory was actually scarce.
        info.lowMem = info.availMb >= 0 && info.availMb < 1500;
        return info;
    }

    /** Log the diagnosis to the console and show a dialog with fixes (EDT). */
    private void reportTreeFailure(TreeFailureInfo info) {
        console.err("✘ Phylogeny step failed.");
        switch (info.category()) {
            case "oom":
                if (info.oom)
                    console.err("Diagnosis: the Linux out-of-memory killer terminated MAFFT (confirmed in the kernel log).");
                else
                    console.err("Diagnosis: very little memory was available (" + info.availMb
                            + " MB) — MAFFT was almost certainly killed for running out of memory.");
                break;
            case "disk":
                console.err("Diagnosis: the temporary disk (/tmp) is full — MAFFT could not write its work files.");
                break;
            default:
                console.warn("Diagnosis: MAFFT stopped with no error message, but memory and disk look sufficient. "
                        + "This points to a MAFFT/WSL runtime issue rather than a lack of resources.");
        }

        logBlock("WSL memory (MB)", info.free);
        logBlock("Temp disk", info.df);
        logBlock("Kernel OOM log", info.dmesg);
        console.info("You only need to rerun THIS step, not the whole pipeline — earlier results are saved on disk.");

        String title = "disk".equals(info.category()) ? "Tree build failed — out of disk space"
                : "oom".equals(info.category())        ? "Tree build failed — out of memory"
                :                                        "Tree build failed";
        JOptionPane.showMessageDialog(this, buildFailureLabel(info), title, JOptionPane.WARNING_MESSAGE);
    }

    /** Build the themed guidance message shown in the failure dialog. */
    private JComponent buildFailureLabel(TreeFailureInfo info) {
        String rerunNote = "<p style='margin-top:8px;color:#166534'>"
            + "<b>You do not need to rerun the whole pipeline.</b> Import, denoising and taxonomy already "
            + "completed and are saved on disk — only this final step needs to run again.</p>";

        String body;
        if ("oom".equals(info.category())) {
            int curGb = info.wslMemMb > 0 ? Math.max(1, Math.round(info.wslMemMb / 1024f)) : -1;
            int recGb = curGb > 0 ? Math.min(16, Math.max(8, curGb * 2)) : 8;
            String cur = curGb > 0 ? (curGb + " GB") : "an unknown amount";
            String wslconfig = System.getProperty("user.home") + File.separator + ".wslconfig";
            body = "<h3 style='margin:0 0 6px 0;color:#B45309'>Tree build failed — out of memory</h3>"
                + "<p>The final step aligns your sequences with <b>MAFFT</b>. It was killed for running "
                + "out of memory" + (info.oom ? " (confirmed in the kernel log)." : ".") + "</p>"
                + "<p style='margin-top:8px'><b>How to get this step to run:</b></p>"
                + "<ol style='margin:4px 0 0 18px;padding:0'>"
                + "<li>Close memory-heavy apps (web browsers, etc.), then click "
                + "<b>Build Phylogeny &amp; Export</b> again.</li>"
                + "<li>Give WSL more memory: create <code>.wslconfig</code> in your Windows home folder "
                + "(<code>" + wslconfig + "</code>) containing:"
                + "<div style='font-family:monospace;background:#F1F5F9;padding:6px;margin:4px 0'>"
                + "[wsl2]<br>memory=" + recGb + "GB<br>swap=4GB</div>"
                + "Then run <code>wsl --shutdown</code> in PowerShell, reopen EzMAP, and rerun. "
                + "WSL currently has " + cur + "; you can go up to ~75% of your PC's RAM.</li>"
                + "</ol>";
        } else if ("disk".equals(info.category())) {
            body = "<h3 style='margin:0 0 6px 0;color:#B91C1C'>Tree build failed — out of disk space</h3>"
                + "<p>MAFFT could not write its temporary files because the disk holding <code>/tmp</code> "
                + "inside WSL is full.</p>"
                + "<p style='margin-top:8px'><b>How to fix:</b></p>"
                + "<ol style='margin:4px 0 0 18px;padding:0'>"
                + "<li>Free up space on your system drive (C:) — WSL keeps <code>/tmp</code> and its virtual "
                + "disk there. Aim for 20–30 GB+ free.</li>"
                + "<li>Run <code>wsl --shutdown</code> in PowerShell to clear temp files, then rerun.</li>"
                + "</ol>";
        } else {
            // Memory and disk look fine — be honest that the cause is unclear.
            body = "<h3 style='margin:0 0 6px 0;color:#334155'>Tree build failed</h3>"
                + "<p>MAFFT (the alignment tool) stopped with <b>no error message</b>, but your system had "
                + "enough memory" + (info.availMb >= 0 ? " (" + info.availMb + " MB free)" : "")
                + " and disk space. This looks like a <b>MAFFT/WSL runtime problem</b>, not a lack of resources.</p>"
                + "<p style='margin-top:8px'><b>Things to try:</b></p>"
                + "<ol style='margin:4px 0 0 18px;padding:0'>"
                + "<li>Click <b>Build Phylogeny &amp; Export</b> again — transient WSL hiccups happen.</li>"
                + "<li>Restart WSL: run <code>wsl --shutdown</code> in PowerShell, reopen EzMAP, and rerun.</li>"
                + "<li>See MAFFT's real error: open a WSL terminal, run "
                + "<code>conda activate EzMAP2-qiime2</code> then "
                + "<code>echo &gt;foo.fasta; mafft foo.fasta</code> — if MAFFT itself is broken it will say so. "
                + "If needed, reinstall it: <code>conda install -n EzMAP2-qiime2 -c bioconda mafft</code>.</li>"
                + "</ol>";
        }

        return new JLabel("<html><body style='width:540px;font-family:sans-serif;color:#0F172A'>"
                + body + rerunNote + "</body></html>");
    }

    /** Append a labelled multi-line block to the console (skips if empty). */
    private void logBlock(String title, String content) {
        if (content == null || content.trim().isEmpty()) return;
        console.info(title + ":");
        for (String l : content.split("\\R")) {
            if (!l.trim().isEmpty()) console.info("  " + l);
        }
    }

    /** Parse total memory (MB) from `free -m` output; -1 if not found. */
    private static int parseMemTotalMb(String freeOutput) {
        return parseMemColumn(freeOutput, 1);
    }

    /** Parse available memory (MB) from `free -m` output; -1 if not found. */
    private static int parseMemAvailMb(String freeOutput) {
        // Columns: total used free shared buff/cache available
        return parseMemColumn(freeOutput, 6);
    }

    /** Read a numeric column from the "Mem:" line of `free -m` output. */
    private static int parseMemColumn(String freeOutput, int col) {
        if (freeOutput == null) return -1;
        for (String line : freeOutput.split("\\R")) {
            String t = line.trim();
            if (t.toLowerCase().startsWith("mem:")) {
                String[] parts = t.split("\\s+");
                if (parts.length > col) {
                    try { return Integer.parseInt(parts[col]); }
                    catch (NumberFormatException ignore) { /* fall through */ }
                }
            }
        }
        return -1;
    }

    /**
     * Run a short read-only shell command in WSL (or local bash on
     * macOS/Linux) and capture its combined output. Returns null on error.
     */
    private static String captureWsl(String bashCmd) {
        try {
            String os = System.getProperty("os.name").toLowerCase();
            ProcessBuilder pb = os.contains("win")
                    ? new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--",
                            "bash", "-lc", bashCmd)
                    : new ProcessBuilder("bash", "-lc", bashCmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            StringBuilder sb = new StringBuilder();
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) sb.append(line).append('\n');
            }
            if (!p.waitFor(15, TimeUnit.SECONDS)) p.destroyForcibly();
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }
}
