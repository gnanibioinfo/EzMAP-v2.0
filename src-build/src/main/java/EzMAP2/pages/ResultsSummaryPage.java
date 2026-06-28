package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.List;

/**
 * Results summary page — shown after Easy Mode pipeline completes,
 * or when a user resumes from an existing output folder.
 *
 * Four cards:
 *   0. Folder picker  — select pipeline output folder (shown for Resume flow)
 *   1. Denoising QC   — per-sample read counts with color-coded dropout flags
 *   2. Taxonomy snapshot — top phyla/genera, total ASV count
 *   3. Downstream launch — file checklist + Shiny launch button
 */
public class ResultsSummaryPage extends BasePage {

    private final WizardController wizard;

    // Folder picker card (Card 0)
    private final Card folderCard;
    private final DirectoryPicker folderPicker;
    private final PrimaryButton loadSummaryBtn = new PrimaryButton("Load Summary");
    private final JLabel folderStatus = new JLabel(" ");

    // Summary cards (hidden until folder is loaded)
    private final Card denoiseCard;
    private final Card taxaCard;
    private final Card downCard;

    // Denoising QC
    private final DefaultTableModel denoiseModel;
    private final JTable denoiseTable;
    private final JLabel denoiseOverall = new JLabel(" ");

    // Taxonomy snapshot
    private final JLabel taxaSummaryLabel = new JLabel(" ");

    // File checklist
    private final JLabel fileCheckLabel = new JLabel(" ");

    // Downstream launch
    private final PrimaryButton launchBtn   = new PrimaryButton("Open in EzMAP v2.0 Downstream  \u2192");
    private final OutlineButton stopBtn     = new OutlineButton("Stop Shiny");
    private final PrimaryButton openDirBtn  = new PrimaryButton("Open Results Folder");
    private final OutlineButton openBundleBtn = new OutlineButton("Open Bundle .zip");
    private final JLabel launchStatus = new JLabel(" ");
    private final LogConsole console = new LogConsole();

    private String outputDir;
    private volatile Process shinyProcess;

    public ResultsSummaryPage(WizardController wizard) {
        super("Results & Summary",
              "Review your pipeline results, check denoising quality, and launch downstream analysis.");
        this.wizard = wizard;

        // ==============================================================
        //  Card 0: Folder Picker (for Resume Downstream flow)
        // ==============================================================
        folderCard = new Card("Select Pipeline Output Folder");

        JLabel folderHint = new JLabel("<html><body style='width:640px'>" +
                "Browse to the folder containing your EzMAP v2.0 pipeline output. " +
                "This folder should contain files like <code>feature-table-tax.biom</code>, " +
                "<code>taxonomy.tsv</code>, and <code>denoising-stats.tsv</code>. " +
                "These may be in the folder root or inside a <code>bundle/</code> subfolder." +
                "</body></html>");
        folderHint.setFont(Theme.FONT_BODY);
        folderHint.setForeground(Theme.INK_3);
        folderCard.row(folderHint).gap(10);

        folderPicker = new DirectoryPicker("Choose pipeline output folder\u2026", file -> {
            // Enable the load button when a folder is picked
            loadSummaryBtn.setEnabled(true);
            folderStatus.setText(" ");
        });
        folderCard.row(folderPicker).gap(8);

        JPanel loadRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        loadRow.setOpaque(false);
        loadSummaryBtn.setEnabled(false);
        loadRow.add(loadSummaryBtn);
        folderStatus.setFont(Theme.FONT_BODY);
        loadRow.add(folderStatus);
        folderCard.row(loadRow);

        loadSummaryBtn.addActionListener(e -> onLoadSummary());
        add(folderCard);

        // ==============================================================
        //  Card 1: Denoising QC
        // ==============================================================
        denoiseCard = new Card("1 \u00B7 Denoising Quality Check");

        String[] cols = {"Sample ID", "Input", "Filtered", "Denoised", "Merged", "Non-chimeric", "Survival %"};
        denoiseModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int row, int col) { return false; }
        };
        denoiseTable = new JTable(denoiseModel);
        styleTable(denoiseTable);

        // Color-code the Survival % column
        denoiseTable.getColumnModel().getColumn(6).setCellRenderer(new DefaultTableCellRenderer() {
            @Override public Component getTableCellRendererComponent(JTable t, Object v,
                    boolean sel, boolean focus, int row, int col) {
                Component c = super.getTableCellRendererComponent(t, v, sel, focus, row, col);
                c.setBackground(sel ? Theme.PRIMARY_SOFT : Theme.SURFACE);
                try {
                    double pct = Double.parseDouble(v.toString().replace("%", "").trim());
                    if (pct >= 60) { c.setForeground(Theme.SUCCESS); }
                    else if (pct >= 40) { c.setForeground(Theme.WARNING); c.setFont(Theme.FONT_BODY_BOLD); }
                    else { c.setForeground(Theme.DANGER); c.setFont(Theme.FONT_BODY_BOLD); }
                } catch (NumberFormatException e) {
                    c.setForeground(Theme.INK_2);
                }
                return c;
            }
        });

        JScrollPane denoiseScroll = new JScrollPane(denoiseTable);
        denoiseScroll.setPreferredSize(new Dimension(0, 180));
        denoiseScroll.setBorder(BorderFactory.createLineBorder(Theme.BORDER));
        denoiseScroll.getViewport().setBackground(Theme.SURFACE);
        denoiseCard.row(denoiseScroll).gap(6);

        denoiseOverall.setFont(Theme.FONT_BODY);
        denoiseCard.row(denoiseOverall);
        denoiseCard.setVisible(false);
        add(denoiseCard);

        // ==============================================================
        //  Card 2: Taxonomy Snapshot
        // ==============================================================
        taxaCard = new Card("2 \u00B7 Taxonomy Snapshot");
        taxaSummaryLabel.setFont(Theme.FONT_BODY);
        taxaSummaryLabel.setForeground(Theme.INK_2);
        taxaCard.row(taxaSummaryLabel);
        taxaCard.setVisible(false);
        add(taxaCard);

        // ==============================================================
        //  Card 3: Downstream Analysis
        // ==============================================================
        downCard = new Card("3 \u00B7 Downstream Analysis");

        fileCheckLabel.setFont(Theme.FONT_BODY);
        fileCheckLabel.setForeground(Theme.INK_2);
        downCard.row(fileCheckLabel).gap(10);

        InfoBanner instructions = new InfoBanner(InfoBanner.Kind.INFO,
                "Ready for downstream",
                "Click 'Open in EzMAP v2.0 Downstream' to launch the interactive Shiny module. " +
                "Your data files will be auto-loaded. You can also open the results folder " +
                "to access raw files directly.");
        downCard.row(instructions).gap(10);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(launchBtn);
        btnRow.add(stopBtn);
        btnRow.add(openDirBtn);
        btnRow.add(openBundleBtn);
        launchStatus.setFont(Theme.FONT_BODY);
        btnRow.add(launchStatus);
        downCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 140));
        downCard.row(console);
        downCard.setVisible(false);
        add(downCard);

        // ==============================================================
        //  Navigation bar — Back to mode selection
        // ==============================================================
        JPanel navRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        navRow.setOpaque(false);
        GhostButton backBtn = new GhostButton("\u2190  Back to Mode Selection");
        backBtn.addActionListener(e -> wizard.previous());
        navRow.add(backBtn);
        add(navRow);

        // ---- Wiring ----
        stopBtn.setEnabled(false);
        launchBtn.addActionListener(e -> launchShiny());
        stopBtn.addActionListener(e -> stopShiny());
        openDirBtn.addActionListener(e -> openPath(outputDir));
        openBundleBtn.addActionListener(e -> openPath(findBundleZip()));
    }

    // ==================================================================
    //  Folder picker action — validate and load
    // ==================================================================

    private void onLoadSummary() {
        String path = folderPicker.getPath();
        if (path == null || path.isEmpty()) {
            folderStatus.setText("<html><span style='color:#DC2626'>\u2718 Please select a folder first.</span></html>");
            return;
        }

        File dir = new File(path);
        if (!dir.isDirectory()) {
            folderStatus.setText("<html><span style='color:#DC2626'>\u2718 Selected path is not a valid directory.</span></html>");
            return;
        }

        // Check for at least one expected output file
        boolean hasAnyFile = findInOutput(path, "feature-table-tax.biom") != null
                || findInOutput(path, "feature-table.biom") != null
                || findInOutput(path, "taxonomy.tsv") != null
                || findInOutput(path, "denoising-stats.tsv") != null;

        if (!hasAnyFile) {
            folderStatus.setText("<html><span style='color:#D97706'>\u26A0 No pipeline output files found. " +
                    "Check the folder path and try again.</span></html>");
            // Still allow loading — user might have partial results
        }

        folderStatus.setText("<html><span style='color:#16A34A'>\u2713 Folder loaded successfully.</span></html>");
        loadResults(path);

        // Show summary cards
        denoiseCard.setVisible(true);
        taxaCard.setVisible(true);
        downCard.setVisible(true);

        // Revalidate layout so cards render
        revalidate();
        repaint();
    }

    // ==================================================================
    //  Public API — called by EasyModePage (auto-load, no folder picker)
    // ==================================================================

    /** Load results from a pipeline output directory. */
    public void loadResults(String outputDir) {
        this.outputDir = outputDir;

        // If called programmatically (e.g., from Easy Mode), hide folder picker
        // and show summary cards directly
        if (outputDir != null && !outputDir.isEmpty()) {
            folderCard.setVisible(false);
            denoiseCard.setVisible(true);
            taxaCard.setVisible(true);
            downCard.setVisible(true);
        }

        SwingUtilities.invokeLater(() -> {
            loadDenoisingStats(outputDir);
            loadTaxonomySummary(outputDir);
            buildFileChecklist(outputDir);
            revalidate();
            repaint();
        });
    }

    /**
     * Show the folder picker card (used when arriving from Resume Downstream flow).
     * Call this before the page is displayed to reset to the folder-picker state.
     */
    public void showFolderPicker() {
        folderCard.setVisible(true);
        denoiseCard.setVisible(false);
        taxaCard.setVisible(false);
        downCard.setVisible(false);
        folderStatus.setText(" ");
        loadSummaryBtn.setEnabled(!folderPicker.isEmpty());
        revalidate();
        repaint();
    }

    // ==================================================================
    //  Denoising stats parser
    // ==================================================================

    private void loadDenoisingStats(String outDir) {
        denoiseModel.setRowCount(0);

        // Look for denoising-stats.tsv in output dir or bundle/
        File statsFile = findInOutput(outDir, "denoising-stats.tsv");
        if (statsFile == null) {
            denoiseOverall.setText("<html><span style='color:#D97706'>\u26A0 denoising-stats.tsv not found</span></html>");
            return;
        }

        try {
            List<String> lines = Files.readAllLines(statsFile.toPath(), StandardCharsets.UTF_8);
            // Skip comment lines starting with #
            int headerIdx = 0;
            for (int i = 0; i < lines.size(); i++) {
                if (!lines.get(i).startsWith("#")) { headerIdx = i; break; }
            }
            if (lines.size() <= headerIdx + 1) {
                denoiseOverall.setText("<html><span style='color:#D97706'>\u26A0 No data in denoising stats</span></html>");
                return;
            }

            // Parse header to find column indices
            String[] header = lines.get(headerIdx).split("\t");
            int idxId = findCol(header, "sample-id", "sample_id", "sampleid");
            int idxInput = findCol(header, "input");
            int idxFiltered = findCol(header, "filtered");
            int idxDenoised = findCol(header, "denoised");
            int idxMerged = findCol(header, "merged");
            int idxNonchim = findCol(header, "non-chimeric", "nonchimeric", "non_chimeric");

            int totalSamples = 0;
            int lowSurvival = 0;
            long totalInput = 0;
            long totalOutput = 0;

            // Skip the second line if it looks like a type-spec row (starts with #q2)
            int dataStart = headerIdx + 1;
            if (dataStart < lines.size() && lines.get(dataStart).startsWith("#")) dataStart++;

            for (int i = dataStart; i < lines.size(); i++) {
                String line = lines.get(i).trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] parts = line.split("\t");

                String sampleId = idxId >= 0 && idxId < parts.length ? parts[idxId] : "?";
                long input    = parseLong(parts, idxInput);
                long filtered = parseLong(parts, idxFiltered);
                long denoised = parseLong(parts, idxDenoised);
                long merged   = parseLong(parts, idxMerged);
                long nonchim  = parseLong(parts, idxNonchim);

                double survPct = input > 0 ? (nonchim * 100.0 / input) : 0;
                String survStr = String.format("%.1f%%", survPct);

                denoiseModel.addRow(new Object[]{
                        sampleId,
                        String.valueOf(input),
                        String.valueOf(filtered),
                        String.valueOf(denoised),
                        String.valueOf(merged),
                        String.valueOf(nonchim),
                        survStr
                });

                totalSamples++;
                totalInput += input;
                totalOutput += nonchim;
                if (survPct < 50) lowSurvival++;
            }

            double overallPct = totalInput > 0 ? (totalOutput * 100.0 / totalInput) : 0;
            String color = lowSurvival == 0 ? "#16A34A" : lowSurvival <= 2 ? "#D97706" : "#DC2626";
            String icon  = lowSurvival == 0 ? "\u2713" : "\u26A0";
            denoiseOverall.setText(String.format(
                    "<html><span style='color:%s'>%s %d samples · Overall survival: %.1f%% · %s</span></html>",
                    color, icon, totalSamples, overallPct,
                    lowSurvival == 0 ? "All samples passed QC"
                            : lowSurvival + " sample(s) below 50%% survival — check quality"));

        } catch (IOException e) {
            denoiseOverall.setText("<html><span style='color:#DC2626'>\u2718 Error reading stats: " +
                    e.getMessage() + "</span></html>");
        }
    }

    // ==================================================================
    //  Taxonomy summary
    // ==================================================================

    private void loadTaxonomySummary(String outDir) {
        File taxFile = findInOutput(outDir, "taxonomy.tsv");
        if (taxFile == null) {
            taxaSummaryLabel.setText("<html><span style='color:#D97706'>\u26A0 taxonomy.tsv not found</span></html>");
            return;
        }

        try {
            List<String> lines = Files.readAllLines(taxFile.toPath(), StandardCharsets.UTF_8);

            Map<String, Integer> phylaCounts = new LinkedHashMap<>();
            Map<String, Integer> genusCounts = new LinkedHashMap<>();
            int totalASVs = 0;

            for (String line : lines) {
                if (line.startsWith("#") || line.toLowerCase().startsWith("feature")) continue;
                String[] parts = line.split("\t");
                if (parts.length < 2) continue;

                totalASVs++;
                String taxon = parts[1]; // Taxon column

                // Extract phylum (p__) and genus (g__)
                String phylum = extractTaxLevel(taxon, "p__");
                String genus  = extractTaxLevel(taxon, "g__");

                if (phylum != null && !phylum.isEmpty()) {
                    phylaCounts.merge(phylum, 1, Integer::sum);
                }
                if (genus != null && !genus.isEmpty()) {
                    genusCounts.merge(genus, 1, Integer::sum);
                }
            }

            // Sort by count descending, take top entries
            List<Map.Entry<String, Integer>> topPhyla = sortedTop(phylaCounts, 8);
            List<Map.Entry<String, Integer>> topGenera = sortedTop(genusCounts, 8);

            StringBuilder html = new StringBuilder();
            html.append("<html><body style='width:680px'>");
            html.append("<b>Total ASVs:</b> ").append(totalASVs);
            html.append(" &nbsp;\u00B7&nbsp; <b>Unique phyla:</b> ").append(phylaCounts.size());
            html.append(" &nbsp;\u00B7&nbsp; <b>Unique genera:</b> ").append(genusCounts.size());
            html.append("<br><br>");

            html.append("<b>Top phyla:</b> ");
            for (int i = 0; i < topPhyla.size(); i++) {
                if (i > 0) html.append(", ");
                html.append(topPhyla.get(i).getKey())
                    .append(" (").append(topPhyla.get(i).getValue()).append(")");
            }

            html.append("<br><b>Top genera:</b> ");
            for (int i = 0; i < topGenera.size(); i++) {
                if (i > 0) html.append(", ");
                html.append(topGenera.get(i).getKey())
                    .append(" (").append(topGenera.get(i).getValue()).append(")");
            }

            html.append("</body></html>");
            taxaSummaryLabel.setText(html.toString());

        } catch (IOException e) {
            taxaSummaryLabel.setText("<html><span style='color:#DC2626'>\u2718 Error reading taxonomy: " +
                    e.getMessage() + "</span></html>");
        }
    }

    private String extractTaxLevel(String taxon, String prefix) {
        int idx = taxon.indexOf(prefix);
        if (idx < 0) return null;
        int start = idx + prefix.length();
        int end = taxon.indexOf(';', start);
        if (end < 0) end = taxon.length();
        String val = taxon.substring(start, end).trim();
        // Skip empty assignments like "p__" with nothing after
        return val.isEmpty() || val.equals("__") ? null : val;
    }

    private List<Map.Entry<String, Integer>> sortedTop(Map<String, Integer> map, int n) {
        List<Map.Entry<String, Integer>> entries = new ArrayList<>(map.entrySet());
        entries.sort((a, b) -> Integer.compare(b.getValue(), a.getValue()));
        return entries.subList(0, Math.min(n, entries.size()));
    }

    // ==================================================================
    //  File checklist
    // ==================================================================

    private void buildFileChecklist(String outDir) {
        String[][] expected = {
                {"feature-table-tax.biom", "ASV table with taxonomy"},
                {"feature-table.biom",     "ASV abundance table"},
                {"taxonomy.tsv",           "Taxonomic classifications"},
                {"rooted-tree.nwk",        "Phylogenetic tree"},
                {"rep-seqs.fasta",         "Representative sequences"},
                {"denoising-stats.tsv",    "Denoising statistics"},
                {"metadata.tsv",           "Sample metadata"}
        };

        StringBuilder html = new StringBuilder("<html><body style='width:680px'>");
        html.append("<b>Output files for downstream analysis:</b><br><br>");

        int found = 0;
        for (String[] pair : expected) {
            File f = findInOutput(outDir, pair[0]);
            boolean exists = f != null;
            if (exists) found++;
            String icon = exists ? "\u2713" : "\u2718";
            String color = exists ? "#16A34A" : "#DC2626";
            html.append("<span style='color:").append(color).append("'>")
                .append(icon).append("</span> <code>").append(pair[0])
                .append("</code> \u2014 ").append(pair[1]).append("<br>");
        }

        html.append("<br><b>").append(found).append("/").append(expected.length)
            .append("</b> files found.");
        if (found >= 4) {
            html.append(" <span style='color:#16A34A'>Ready for downstream analysis.</span>");
        }
        html.append("</body></html>");
        fileCheckLabel.setText(html.toString());

        // Enable/disable launch based on minimum files
        File biom = findInOutput(outDir, "feature-table-tax.biom");
        if (biom == null) biom = findInOutput(outDir, "feature-table.biom");
        launchBtn.setEnabled(biom != null);
        openBundleBtn.setEnabled(findBundleZip() != null);
    }

    // ==================================================================
    //  Shiny launch (delegates to DownstreamUploadPage.buildShinyProcess)
    // ==================================================================

    private void stopShiny() {
        Process p = shinyProcess;
        if (p != null) {
            console.warn("Stopping Shiny server\u2026");
            DownstreamUploadPage.killShinyTree(p);
            shinyProcess = null;
            console.ok("Shiny server stopped.");
        }
        // Reset the UI immediately so the user can relaunch.
        SwingUtilities.invokeLater(() -> {
            launchBtn.setEnabled(true);
            stopBtn.setEnabled(false);
            launchStatus.setText(" ");
        });
    }

    private void launchShiny() {
        launchBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        launchStatus.setText("<html><span style='color:#64748B'>Launching\u2026</span></html>");
        console.clear();
        console.info("Starting EzMAP v2.0 Downstream (Shiny)\u2026");

        new Thread(() -> {
            try {
                // Step 1: Auto-install missing R packages
                DownstreamUploadPage.ensureRPackages(console, launchStatus);

                // Step 2: Locate and launch Shiny
                String projectDir = System.getProperty("user.dir");
                File shinyDir = locateShinyApp(projectDir);
                if (shinyDir == null) {
                    SwingUtilities.invokeLater(() -> {
                        console.err("EzMAPv2-downstream/ not found.");
                        launchStatus.setText("<html><span style='color:#DC2626'>\u2718 Not found</span></html>");
                        launchBtn.setEnabled(true);
                    });
                    return;
                }

                // Resolve data files from pipeline output
                File biom = findInOutput(outputDir, "feature-table-tax.biom");
                if (biom == null) biom = findInOutput(outputDir, "feature-table.biom");
                File meta = findInOutput(outputDir, "metadata.tsv");
                File tree = findInOutput(outputDir, "rooted-tree.nwk");

                String osName = System.getProperty("os.name").toLowerCase();
                ProcessBuilder pb = DownstreamUploadPage.buildShinyProcess(
                        osName, shinyDir,
                        biom != null ? biom.getAbsolutePath() : null,
                        meta != null ? meta.getAbsolutePath() : null,
                        tree != null ? tree.getAbsolutePath() : null);

                pb.redirectErrorStream(true);

                SwingUtilities.invokeLater(() -> console.info("R command ready, starting server\u2026"));

                shinyProcess = pb.start();
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(shinyProcess.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        final String s = line;
                        SwingUtilities.invokeLater(() -> {
                            console.info(s);
                            if (s.contains("Listening on")) {
                                launchStatus.setText("<html><span style='color:#16A34A'>\u2713 Running — " +
                                        s.substring(s.indexOf("http")) + "</span></html>");
                            }
                        });
                    }
                }

                int exit = shinyProcess.waitFor();
                SwingUtilities.invokeLater(() -> {
                    console.ok("Shiny app stopped (exit " + exit + ").");
                    launchStatus.setText(" ");
                    launchBtn.setEnabled(true);
                    stopBtn.setEnabled(false);
                });

            } catch (Exception ex) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Launch error: " + ex.getMessage());
                    launchStatus.setText("<html><span style='color:#DC2626'>\u2718 Error</span></html>");
                    launchBtn.setEnabled(true);
                    stopBtn.setEnabled(false);
                });
            }
        }).start();
    }

    // ==================================================================
    //  Helpers
    // ==================================================================

    private File locateShinyApp(String projectDir) {
        // Resolve JAR location so we find the Shiny app bundled with this build
        String jarDir = null;
        try {
            String jarPath = ResultsSummaryPage.class.getProtectionDomain()
                    .getCodeSource().getLocation().getPath();
            jarDir = new File(java.net.URLDecoder.decode(jarPath, "UTF-8")).getParent();
        } catch (Exception ignored) {}

        String[] tries = {
                // 1. Same folder as the JAR (highest priority — bundled distribution)
                jarDir != null ? jarDir + File.separator + "EzMAPv2-downstream" : null,
                // 2. Inside the working directory
                projectDir + File.separator + "EzMAPv2-downstream",
                // 3. Sibling of working directory
                new File(projectDir).getParent() + File.separator + "EzMAPv2-downstream",
                // 4. Grandparent
                new File(projectDir).getParentFile().getParent() + File.separator + "EzMAPv2-downstream"
        };
        for (String path : tries) {
            if (path == null) continue;
            File f = new File(path);
            if (f.isDirectory()) return f;
        }
        return null;
    }

    /** Find a file in the output dir or its bundle/ subfolder. */
    private File findInOutput(String outDir, String filename) {
        if (outDir == null) return null;
        File f = new File(outDir, filename);
        if (f.isFile()) return f;
        File bundle = new File(outDir, "bundle" + File.separator + filename);
        if (bundle.isFile()) return bundle;
        return null;
    }

    private String findBundleZip() {
        if (outputDir == null) return null;
        File dir = new File(outputDir);
        if (!dir.isDirectory()) return null;
        File[] zips = dir.listFiles((d, n) -> n.startsWith("EzMAP2_results_") && n.endsWith(".zip"));
        if (zips == null || zips.length == 0) return null;
        File newest = zips[0];
        for (File z : zips) if (z.lastModified() > newest.lastModified()) newest = z;
        return newest.getAbsolutePath();
    }

    private void openPath(String path) {
        if (path == null || path.isEmpty()) return;
        File f = new File(path);
        if (!f.exists()) { console.warn("Path not found: " + path); return; }
        try { Desktop.getDesktop().open(f); }
        catch (IOException ex) { console.err("Cannot open: " + ex.getMessage()); }
    }

    private void styleTable(JTable table) {
        table.setFont(Theme.FONT_BODY);
        table.setRowHeight(28);
        table.setBackground(Theme.SURFACE);
        table.setSelectionBackground(Theme.PRIMARY_SOFT);
        table.setSelectionForeground(Theme.INK_1);
        table.setGridColor(Theme.BORDER);
        table.setShowGrid(true);
        table.setIntercellSpacing(new Dimension(1, 1));
        table.getTableHeader().setFont(Theme.FONT_BODY_BOLD);
        table.getTableHeader().setBackground(Theme.SURFACE_2);
        table.getTableHeader().setForeground(Theme.INK_1);
        table.getTableHeader().setBorder(BorderFactory.createMatteBorder(0, 0, 1, 0, Theme.BORDER));
    }

    private int findCol(String[] header, String... names) {
        for (int i = 0; i < header.length; i++) {
            String h = header[i].trim().toLowerCase().replace("-", "").replace("_", "");
            for (String name : names) {
                if (h.equals(name.replace("-", "").replace("_", ""))) return i;
            }
        }
        return -1;
    }

    private long parseLong(String[] parts, int idx) {
        if (idx < 0 || idx >= parts.length) return 0;
        try { return Long.parseLong(parts[idx].trim()); }
        catch (NumberFormatException e) { return 0; }
    }

}
