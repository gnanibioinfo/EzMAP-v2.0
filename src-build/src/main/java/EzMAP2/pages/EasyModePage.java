package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.Desktop;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/**
 * Easy Mode — two-phase pipeline launcher.
 *
 * PHASE 1 (Validation):
 *   User picks FASTQ folder + metadata → clicks "Validate Inputs"
 *   → detects FASTQ type, generates manifest, reconciles sample IDs
 *   → shows FASTQ type alert + sample ID mapping table for approval
 *
 * PHASE 2 (Pipeline):
 *   Only after validation passes → amplicon/threads/denoiser options unlock
 *   → user clicks "Run Full Pipeline"
 */
public class EasyModePage extends BasePage {

    private final WizardController wizard;

    // --- Project directory (sets starting location for all other pickers) ---
    private final DirectoryPicker projectPicker = new DirectoryPicker(
            "Select working directory (all browsers default here)", f -> onProjectDirSet(f));

    // --- Phase 1: Validation inputs ---
    private final DirectoryPicker fastqPicker = new DirectoryPicker(
            "/path/to/fastq/directory", f -> onFastqPicked(f));
    private final DirectoryPicker metaPicker  = new DirectoryPicker(
            "/path/to/metadata.tsv", f -> refreshValidateState(), true);
    private final DirectoryPicker outPicker   = new DirectoryPicker(
            "/path/to/output/folder", f -> refreshValidateState());
    private final PrimaryButton validateBtn   = new PrimaryButton("Validate Inputs");
    private final JLabel validationStatus     = new JLabel(" ");

    // --- Phase 2: Pipeline config (locked until validation passes) ---
    private final Card            pipelineCard;
    private final DirectoryPicker classifierPicker = new DirectoryPicker(
            "(optional) classifier.qza", f -> {}, true);
    private final JComboBox<String> amplicon = new JComboBox<>(
            new String[]{"16S-V3V4", "16S-V4", "ITS1", "ITS2"});
    private final JSpinner threads = new JSpinner(new SpinnerNumberModel(4, 1, 64, 1));
    private final JComboBox<String> denoiser = new JComboBox<>(
            new String[]{"DADA2 (recommended)", "Deblur (low memory, 16S only)"});
    private final JCheckBox lowMemBox = new JCheckBox(
            "Low-memory mode (single-threaded DADA2, safer on <16 GB RAM)");
    private final PrimaryButton runBtn  = new PrimaryButton("Run Full Pipeline");
    private final OutlineButton stopBtn = new OutlineButton("Stop");

    // --- Shared ---
    private final LogConsole console = new LogConsole();

    private final Card            resultsCard;
    private final PrimaryButton   openFolderBtn  = new PrimaryButton("Open results folder");
    private final OutlineButton   openBundleBtn  = new OutlineButton("Open bundle .zip");
    private final PrimaryButton   downstreamBtn  = new PrimaryButton("Go to Downstream Analysis \u2192");
    private final JLabel          resultsSummary = new JLabel();

    private volatile Process runningProcess;
    private volatile String  lastOutputDir;
    private volatile boolean validationPassed = false;

    public EasyModePage(WizardController wizard) {
        super("Easy Mode — Guided Pipeline",
              "Pick your FASTQ folder, metadata, and output directory. " +
              "EzMAP v2.0 first validates your inputs and matches sample IDs, " +
              "then you configure and launch the full QIIME2 pipeline.");
        this.wizard = wizard;

        // ==============================================================
        //  PHASE 1: Validation Card
        // ==============================================================
        Card inputsCard = new Card("1 · Input Validation");

        // Project / Working Directory — sets the starting location for all pickers
        inputsCard.row(caption("Project / Working directory (sets default for all browsers below)"));
        inputsCard.row(projectPicker).gap(12);

        inputsCard.row(caption("FASTQ folder (paired-end reads)")).row(fastqPicker).gap(8);
        inputsCard.row(caption("Metadata file (.tsv)")).row(metaPicker).gap(8);
        inputsCard.row(caption("Output folder")).row(outPicker).gap(12);

        JLabel valHelp = new JLabel(
            "<html><body style='width:680px; font-size:11px; color:#64748B'>"
            + "<b>What validation does:</b> Detects your FASTQ file format (paired-end, Casava, EMP), "
            + "generates a sample manifest, and checks that FASTQ sample IDs match your metadata file. "
            + "If IDs don't match exactly, EzMAP v2.0 uses intelligent fuzzy matching and asks for your approval."
            + "</body></html>");
        inputsCard.row(valHelp).gap(10);

        JPanel valRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 0));
        valRow.setOpaque(false);
        valRow.add(validateBtn);
        validationStatus.setFont(Theme.FONT_BODY);
        valRow.add(validationStatus);
        inputsCard.row(valRow);

        add(inputsCard);

        // ==============================================================
        //  PHASE 2: Pipeline Configuration (locked until validated)
        // ==============================================================
        pipelineCard = new Card("2 · Pipeline Configuration");

        InfoBanner lockedBanner = new InfoBanner(InfoBanner.Kind.INFO,
                "Validate first",
                "Complete input validation above before configuring the pipeline.");
        lockedBanner.setName("lockedBanner");
        pipelineCard.row(lockedBanner).gap(10);

        // Amplicon + Threads row
        JPanel ampRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 0));
        ampRow.setOpaque(false);
        ampRow.add(caption("Amplicon region"));
        ampRow.add(amplicon);
        ampRow.add(Box.createHorizontalStrut(18));
        ampRow.add(caption("Threads"));
        ampRow.add(threads);
        pipelineCard.row(ampRow).gap(8);

        // Denoiser row
        JPanel dRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 12, 0));
        dRow.setOpaque(false);
        dRow.add(caption("Denoiser"));
        dRow.add(denoiser);
        pipelineCard.row(dRow).gap(6);

        lowMemBox.setOpaque(false);
        lowMemBox.setFont(Theme.FONT_BODY);
        lowMemBox.setForeground(Theme.INK_2);
        pipelineCard.row(lowMemBox).gap(10);

        // Classifier (optional)
        pipelineCard.row(caption("Classifier .qza (optional — auto-detected if blank)"));
        pipelineCard.row(classifierPicker).gap(12);

        // Defaults summary
        pipelineCard.row(defaultsSummary()).gap(12);

        // Run buttons
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(stopBtn);
        pipelineCard.row(btnRow);

        add(pipelineCard);

        // ==============================================================
        //  Activity Log
        // ==============================================================
        Card logCard = new Card("Activity log");
        console.setPreferredSize(new Dimension(0, 240));
        logCard.row(console);
        add(logCard);

        // ==============================================================
        //  Results Card (hidden until pipeline succeeds)
        // ==============================================================
        resultsCard = new Card("3 · Results & Downloads");
        resultsSummary.setFont(Theme.FONT_BODY);
        resultsSummary.setForeground(Theme.INK_2);
        resultsCard.row(resultsSummary).gap(10);

        JPanel resultBtns = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        resultBtns.setOpaque(false);
        resultBtns.add(openFolderBtn);
        resultBtns.add(openBundleBtn);
        resultBtns.add(Box.createHorizontalStrut(20));
        resultBtns.add(downstreamBtn);
        resultsCard.row(resultBtns);
        resultsCard.setVisible(false);
        add(resultsCard);

        // ==============================================================
        //  Navigation — Back to Mode Selection
        // ==============================================================
        JPanel navRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        navRow.setOpaque(false);
        GhostButton backBtn = new GhostButton("\u2190  Back to Mode Selection");
        backBtn.addActionListener(e -> wizard.previous());
        navRow.add(backBtn);
        add(navRow);

        // ==============================================================
        //  Wiring
        // ==============================================================
        validateBtn.addActionListener(e -> runValidation());
        runBtn.addActionListener(e -> startPipeline());
        stopBtn.addActionListener(e -> stopPipeline());
        openFolderBtn.addActionListener(e -> openPath(lastOutputDir));
        openBundleBtn.addActionListener(e -> openPath(findBundleZip(lastOutputDir)));
        downstreamBtn.addActionListener(e -> goToDownstream());

        // Denoiser toggle
        denoiser.addActionListener(e -> {
            boolean isDada2 = denoiser.getSelectedIndex() == 0;
            lowMemBox.setEnabled(isDada2);
            if (!isDada2) lowMemBox.setSelected(false);
        });
        long totalMb = Runtime.getRuntime().maxMemory() / (1024 * 1024);
        if (totalMb < 2048) lowMemBox.setSelected(true);

        // Default start directory for classifier: ~/ezmap2-classifiers/
        classifierPicker.setStartDirectory(
                System.getProperty("user.home") + File.separator + "ezmap2-classifiers");

        // Initial state: Phase 2 locked
        validateBtn.setEnabled(false);
        lockPipelinePhase(true);
    }

    // ==================================================================
    //  State management
    // ==================================================================

    private void refreshValidateState() {
        validateBtn.setEnabled(!fastqPicker.isEmpty()
                && !metaPicker.isEmpty()
                && !outPicker.isEmpty());
        // If user changes inputs after validation, re-lock pipeline
        if (validationPassed) {
            validationPassed = false;
            lockPipelinePhase(true);
            validationStatus.setText("<html><span style='color:#D97706'>\u26A0 Inputs changed — re-validate</span></html>");
        }
    }

    /** When the project/working directory is selected, propagate it as the starting
     *  location for all other file browsers so the user doesn't re-navigate. */
    private void onProjectDirSet(File dir) {
        if (dir == null || !dir.isDirectory()) return;
        fastqPicker.setStartDirectory(dir);
        metaPicker.setStartDirectory(dir);
        outPicker.setStartDirectory(dir);
        // Pre-fill output to projectDir/output if user hasn't set one yet
        if (outPicker.isEmpty()) {
            outPicker.setPath(dir.getAbsolutePath() + File.separator + "output");
        }
        refreshValidateState();
    }

    /** When FASTQ folder is selected, propagate its parent as the fallback start
     *  directory for metadata and output pickers (they're likely nearby). */
    private void onFastqPicked(File fastqDir) {
        if (fastqDir != null) {
            File parent = fastqDir.getParentFile();
            if (parent != null && parent.isDirectory()) {
                // Only set start dir if the user hasn't already browsed there via project dir
                if (metaPicker.isEmpty()) metaPicker.setStartDirectory(parent);
                if (outPicker.isEmpty())  outPicker.setStartDirectory(parent);
            }
        }
        refreshValidateState();
    }

    private void lockPipelinePhase(boolean locked) {
        amplicon.setEnabled(!locked);
        threads.setEnabled(!locked);
        denoiser.setEnabled(!locked);
        lowMemBox.setEnabled(!locked);
        classifierPicker.setEnabled(!locked);
        runBtn.setEnabled(!locked);
        stopBtn.setEnabled(false);

        // Show/hide locked banner
        Component banner = findByName(pipelineCard, "lockedBanner");
        if (banner != null) banner.setVisible(locked);
    }

    // ==================================================================
    //  PHASE 1: Validation
    // ==================================================================

    private void runValidation() {
        validateBtn.setEnabled(false);
        validationPassed = false;
        lockPipelinePhase(true);
        console.clear();
        console.info("Starting input validation\u2026");
        validationStatus.setText("<html><span style='color:#64748B'>Validating\u2026</span></html>");

        final String fastq = fastqPicker.getPath();
        final String meta  = metaPicker.getPath();
        final String out   = outPicker.getPath();

        new Thread(() -> {
            try {
                new File(out).mkdirs();

                String projectDir = System.getProperty("user.dir");
                String genScript  = findGenerateManifest(projectDir);
                if (genScript == null) {
                    SwingUtilities.invokeLater(() -> {
                        console.err("generate_manifest.py not found.");
                        console.err("Searched in: " + projectDir + " and scripts/ subfolder.");
                        validationStatus.setText(
                            "<html><span style='color:#DC2626'>\u2718 Script not found</span></html>");
                        validateBtn.setEnabled(true);
                    });
                    return;
                }
                String manifestPath = fastq + File.separator + "samples_manifest.tsv";

                String osName = System.getProperty("os.name").toLowerCase();
                ProcessBuilder pb;

                if (osName.contains("win")) {
                    String scriptWsl   = toWsl(genScript);
                    String fastqWsl    = toWsl(fastq);
                    String metaWsl     = toWsl(meta);
                    String manifestWsl = toWsl(manifestPath);

                    // Use python3 (not python) — Ubuntu WSL has python3 by default
                    String cmd = "python3 " + q(scriptWsl) + " " + q(fastqWsl)
                            + " " + q(manifestWsl)
                            + " --metadata " + q(metaWsl);

                    final String displayCmd = cmd;
                    SwingUtilities.invokeLater(() -> console.info("WSL: " + displayCmd));
                    pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--",
                            "bash", "-lc", cmd);
                } else {
                    pb = new ProcessBuilder("python3", genScript, fastq,
                            manifestPath, "--metadata", meta);
                }

                pb.redirectErrorStream(true);
                pb.directory(new File(projectDir));

                Process proc = pb.start();
                final StringBuilder lastErr = new StringBuilder();
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        final String s = line;
                        String low = s.toLowerCase();
                        if (low.contains("error") || low.contains("not found")
                                || low.contains("traceback") || low.contains("exception")
                                || low.contains("no such")) {
                            lastErr.setLength(0); lastErr.append(s);
                        }
                        SwingUtilities.invokeLater(() -> console.info(s));
                    }
                }
                int genExit = proc.waitFor();

                if (genExit != 0) {
                    final String detail = lastErr.toString();
                    SwingUtilities.invokeLater(() -> {
                        // Surface the script's REAL error, not a generic message.
                        if (!detail.isEmpty()) console.err("Validation failed: " + detail);
                        else                   console.err("Validation failed (exit code " + genExit + ").");
                        console.err("Tip: if the path to your data or metadata contains spaces or is "
                                + "under OneDrive, move it to a simple path such as C:\\EzMAP2_data\\ and retry.");
                        validationStatus.setText("<html><span style='color:#DC2626'>\u2718 Validation failed</span></html>");
                        validateBtn.setEnabled(true);
                    });
                    return;
                }

                // --- Read output files ---
                // On Windows, the files are written inside WSL paths but are accessible via the
                // Windows mount. The paths we passed were Windows paths, so the output files
                // should be at the Windows-side locations.
                File fastqTypeFile = new File(fastq, "fastq_type.json");
                String fastqTypeJson = fastqTypeFile.exists()
                        ? new String(Files.readAllBytes(fastqTypeFile.toPath()), StandardCharsets.UTF_8)
                        : null;

                File reconFile = new File(fastq, "reconciliation.json");
                String reconJson = reconFile.exists()
                        ? new String(Files.readAllBytes(reconFile.toPath()), StandardCharsets.UTF_8)
                        : null;

                // --- Show dialogs on EDT ---
                SwingUtilities.invokeAndWait(() -> {
                    // 1) FASTQ Type Alert
                    if (fastqTypeJson != null) {
                        showFastqTypeAlert(fastqTypeJson);
                    }

                    // 2) Reconciliation approval
                    boolean approved = true;
                    if (reconJson != null) {
                        approved = showReconciliationDialog(reconJson, fastq);
                    }

                    if (approved) {
                        validationPassed = true;
                        validationStatus.setText(
                            "<html><span style='color:#16A34A'>\u2713 Validation passed — configure pipeline below</span></html>");
                        console.ok("Validation passed! Configure amplicon and pipeline settings below, then click Run.");
                        lockPipelinePhase(false);
                    } else {
                        validationStatus.setText(
                            "<html><span style='color:#DC2626'>\u2718 Fix sample IDs and re-validate</span></html>");
                        console.warn("Validation not approved. Fix your metadata sample IDs and try again.");
                    }
                    validateBtn.setEnabled(true);
                });

            } catch (Exception ex) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Validation error: " + ex.getMessage());
                    validationStatus.setText("<html><span style='color:#DC2626'>\u2718 Error</span></html>");
                    validateBtn.setEnabled(true);
                });
            }
        }).start();
    }

    // ------------------------------------------------------------------
    //  FASTQ TYPE ALERT DIALOG (themed)
    // ------------------------------------------------------------------
    private void showFastqTypeAlert(String jsonStr) {
        try {
            String format = extractJsonString(jsonStr, "format");
            String type   = extractJsonString(jsonStr, "type");
            String desc   = extractJsonString(jsonStr, "description");
            String paired = extractJsonString(jsonStr, "paired");
            String files  = extractJsonString(jsonStr, "files_found");

            JDialog dlg = new JDialog(
                    (Frame) SwingUtilities.getWindowAncestor(this),
                    "FASTQ Detection \u2014 EzMAP v2.0", true);
            dlg.setDefaultCloseOperation(JDialog.DISPOSE_ON_CLOSE);

            JPanel root = new JPanel(new BorderLayout(0, 0));
            root.setBackground(Theme.SURFACE);
            root.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 0));

            // ---- Teal header strip ----
            JPanel header = new JPanel(new FlowLayout(FlowLayout.LEFT, 14, 10));
            header.setBackground(Theme.PRIMARY_SOFT);
            header.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createMatteBorder(0, 0, 1, 0, Theme.PRIMARY_BORDER),
                    BorderFactory.createEmptyBorder(8, 16, 8, 16)));
            JLabel titleLbl = new JLabel("FASTQ File Detection");
            titleLbl.setFont(Theme.FONT_SECTION.deriveFont(16f));
            titleLbl.setForeground(new Color(0x0B, 0x5E, 0x5D));
            header.add(titleLbl);
            root.add(header, BorderLayout.NORTH);

            // ---- Details grid ----
            JPanel body = new JPanel(new GridBagLayout());
            body.setBackground(Theme.SURFACE);
            body.setBorder(BorderFactory.createEmptyBorder(20, 24, 8, 24));
            GridBagConstraints gc = new GridBagConstraints();
            gc.anchor = GridBagConstraints.WEST;
            gc.insets = new Insets(6, 0, 6, 16);

            String[][] rows = {
                {"Import format:", format},
                {"QIIME2 type:",   type},
                {"Paired-end:",    "true".equals(paired) ? "\u2713 Yes" : "No"},
                {"Files found:",   files}
            };
            for (int i = 0; i < rows.length; i++) {
                gc.gridx = 0; gc.gridy = i; gc.fill = GridBagConstraints.NONE;
                JLabel lbl = new JLabel(rows[i][0]);
                lbl.setFont(Theme.FONT_BODY_BOLD);
                lbl.setForeground(Theme.INK_2);
                body.add(lbl, gc);

                gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
                JLabel val = new JLabel(rows[i][1]);
                val.setFont(Theme.FONT_BODY);
                val.setForeground(Theme.INK_1);
                body.add(val, gc);
                gc.weightx = 0;
            }

            // Description text
            gc.gridx = 0; gc.gridy = rows.length; gc.gridwidth = 2;
            gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
            gc.insets = new Insets(14, 0, 4, 0);
            JLabel descLbl = new JLabel("<html><body style='width:520px; color:#64748B; font-size:11px'>"
                    + desc + "</body></html>");
            body.add(descLbl, gc);

            gc.gridy++;
            gc.insets = new Insets(4, 0, 0, 0);
            JLabel autoLbl = new JLabel("<html><b style='color:#0B5E5D; font-size:11px'>"
                    + "This format will be used automatically during the import step.</b></html>");
            body.add(autoLbl, gc);

            root.add(body, BorderLayout.CENTER);

            // ---- Footer with OK button ----
            JPanel footer = new JPanel(new FlowLayout(FlowLayout.RIGHT, 12, 0));
            footer.setBackground(Theme.SURFACE);
            footer.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createMatteBorder(1, 0, 0, 0, Theme.BORDER),
                    BorderFactory.createEmptyBorder(12, 16, 12, 16)));
            PrimaryButton okBtn = new PrimaryButton("OK");
            okBtn.addActionListener(e -> dlg.dispose());
            footer.add(okBtn);
            root.add(footer, BorderLayout.SOUTH);

            dlg.setContentPane(root);
            dlg.setSize(620, 400);
            dlg.setLocationRelativeTo(SwingUtilities.getWindowAncestor(this));
            dlg.setVisible(true);
        } catch (Exception e) {
            console.warn("Could not display FASTQ type info: " + e.getMessage());
        }
    }

    // ------------------------------------------------------------------
    //  SAMPLE ID RECONCILIATION DIALOG (themed)
    // ------------------------------------------------------------------
    private boolean showReconciliationDialog(String jsonStr, String fastqDir) {
        try {
            boolean allMatched = jsonStr.contains("\"all_matched\": true");
            java.util.List<String[]> rows = parseReconciliationRows(jsonStr);

            if (rows.isEmpty()) return true;

            // If all exact matches → auto-approve, just log it
            boolean allExact = rows.stream().allMatch(r -> "exact".equals(r[2]));
            if (allExact) {
                console.ok("All " + rows.size() + " sample IDs match exactly between FASTQ and metadata.");
                return true;
            }

            // --- Build themed dialog ---
            final boolean[] approved = {false};

            JDialog dlg = new JDialog(
                    (Frame) SwingUtilities.getWindowAncestor(this),
                    allMatched ? "Sample ID Reconciliation \u2014 EzMAP v2.0"
                               : "Sample ID Mismatch \u2014 EzMAP v2.0", true);
            dlg.setDefaultCloseOperation(JDialog.DISPOSE_ON_CLOSE);

            JPanel root = new JPanel(new BorderLayout(0, 0));
            root.setBackground(Theme.SURFACE);

            // ---- Header strip (warning amber or error red) ----
            Color headerBg, headerBorder, headerText;
            if (allMatched) {
                headerBg     = new Color(0xFF, 0xFB, 0xEB); // amber-50
                headerBorder = new Color(0xFB, 0xBF, 0x24); // amber-400
                headerText   = new Color(0x92, 0x40, 0x0E); // amber-800
            } else {
                headerBg     = new Color(0xFE, 0xF2, 0xF2); // red-50
                headerBorder = new Color(0xF8, 0x71, 0x71); // red-400
                headerText   = new Color(0x99, 0x1B, 0x1B); // red-800
            }

            JPanel header = new JPanel();
            header.setLayout(new BoxLayout(header, BoxLayout.Y_AXIS));
            header.setBackground(headerBg);
            header.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createMatteBorder(0, 0, 1, 0, headerBorder),
                    BorderFactory.createEmptyBorder(14, 20, 14, 20)));

            JLabel titleLbl = new JLabel(allMatched
                    ? "\u26A0  Sample ID Mapping Needed"
                    : "\u2718  Sample ID Mismatch");
            titleLbl.setFont(Theme.FONT_SECTION.deriveFont(15f));
            titleLbl.setForeground(headerText);
            titleLbl.setAlignmentX(LEFT_ALIGNMENT);
            header.add(titleLbl);
            header.add(Box.createVerticalStrut(8));

            String explanationText;
            if (allMatched) {
                explanationText = "<html><body style='width:680px'>"
                    + "Your FASTQ filenames produce <b>different sample IDs</b> than your metadata file. "
                    + "EzMAP v2.0 auto-matched them using intelligent fuzzy matching."
                    + "<br><br>"
                    + "<b>Review the mapping below and click OK if correct.</b> "
                    + "You can double-click the <i>Metadata ID</i> column to edit any mapping manually. "
                    + "The manifest will use the <b>Metadata ID</b> column so QIIME2 can link samples correctly."
                    + "</body></html>";
            } else {
                explanationText = "<html><body style='width:680px'>"
                    + "Some FASTQ sample IDs could <b>not</b> be matched to your metadata. "
                    + "These will cause QIIME2 errors during analysis."
                    + "<br><br>"
                    + "<b>Fix your metadata file</b> or double-click the <i>Metadata ID</i> column "
                    + "to type the correct ID manually."
                    + "</body></html>";
            }
            JLabel explanationLbl = new JLabel(explanationText);
            explanationLbl.setFont(Theme.FONT_BODY);
            explanationLbl.setForeground(Theme.INK_2);
            explanationLbl.setAlignmentX(LEFT_ALIGNMENT);
            header.add(explanationLbl);

            root.add(header, BorderLayout.NORTH);

            // ---- Table ----
            String[] colNames = {"FASTQ Sample ID", "Metadata ID", "Match Method", "Confidence", "Status"};
            DefaultTableModel model = new DefaultTableModel(colNames, 0) {
                @Override public boolean isCellEditable(int row, int col) { return col == 1; }
            };

            for (String[] row : rows) {
                String status;
                if ("exact".equals(row[2]))         status = "\u2713 Exact";
                else if ("unmatched".equals(row[2])) status = "\u2718 No match";
                else                                  status = "\u2248 Auto (" + row[2] + ")";
                model.addRow(new Object[]{row[0], row[3], row[2], row[4], status});
            }

            JTable table = new JTable(model);
            table.setFont(Theme.FONT_BODY);
            table.setRowHeight(30);
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

            // Color-code status column
            table.getColumnModel().getColumn(4).setCellRenderer(new DefaultTableCellRenderer() {
                @Override public Component getTableCellRendererComponent(JTable t, Object v,
                        boolean sel, boolean focus, int row, int col) {
                    Component c = super.getTableCellRendererComponent(t, v, sel, focus, row, col);
                    c.setBackground(sel ? Theme.PRIMARY_SOFT : Theme.SURFACE);
                    String val = v != null ? v.toString() : "";
                    if (val.startsWith("\u2713"))      c.setForeground(Theme.SUCCESS);
                    else if (val.startsWith("\u2718")) { c.setForeground(Theme.DANGER); c.setFont(Theme.FONT_BODY_BOLD); }
                    else                                c.setForeground(Theme.WARNING);
                    return c;
                }
            });

            // Color-code metadata ID column
            table.getColumnModel().getColumn(1).setCellRenderer(new DefaultTableCellRenderer() {
                @Override public Component getTableCellRendererComponent(JTable t, Object v,
                        boolean sel, boolean focus, int row, int col) {
                    Component c = super.getTableCellRendererComponent(t, v, sel, focus, row, col);
                    c.setBackground(sel ? Theme.PRIMARY_SOFT : Theme.SURFACE);
                    String method = (String) model.getValueAt(row, 2);
                    if ("unmatched".equals(method))      { c.setForeground(Theme.DANGER); c.setFont(Theme.FONT_BODY_BOLD); }
                    else if (!"exact".equals(method))     c.setForeground(new Color(0x92, 0x40, 0x0E));
                    else                                   c.setForeground(Theme.INK_1);
                    return c;
                }
            });

            JPanel tablePanel = new JPanel(new BorderLayout());
            tablePanel.setBackground(Theme.SURFACE);
            tablePanel.setBorder(BorderFactory.createEmptyBorder(16, 20, 8, 20));
            JScrollPane scrollPane = new JScrollPane(table);
            scrollPane.setBorder(BorderFactory.createLineBorder(Theme.BORDER));
            scrollPane.getViewport().setBackground(Theme.SURFACE);
            tablePanel.add(scrollPane, BorderLayout.CENTER);

            // Sample count label below table
            JLabel countLbl = new JLabel(rows.size() + " sample" + (rows.size() != 1 ? "s" : "") + " total");
            countLbl.setFont(Theme.FONT_SMALL);
            countLbl.setForeground(Theme.INK_3);
            countLbl.setBorder(BorderFactory.createEmptyBorder(6, 2, 0, 0));
            tablePanel.add(countLbl, BorderLayout.SOUTH);

            root.add(tablePanel, BorderLayout.CENTER);

            // ---- Footer with buttons ----
            JPanel footer = new JPanel(new FlowLayout(FlowLayout.RIGHT, 10, 0));
            footer.setBackground(Theme.SURFACE);
            footer.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createMatteBorder(1, 0, 0, 0, Theme.BORDER),
                    BorderFactory.createEmptyBorder(12, 20, 12, 20)));

            OutlineButton cancelBtn = new OutlineButton("Cancel");
            cancelBtn.addActionListener(e -> dlg.dispose());

            PrimaryButton okBtn = new PrimaryButton("OK");
            okBtn.addActionListener(e -> { approved[0] = true; dlg.dispose(); });

            footer.add(cancelBtn);
            footer.add(okBtn);
            root.add(footer, BorderLayout.SOUTH);

            dlg.setContentPane(root);
            // Size: fit all rows comfortably — header ~200px + row*32 + footer ~60 + count label
            int tableHeight = Math.max(rows.size() * 32 + 60, 180);
            dlg.setSize(780, Math.min(300 + tableHeight, 700));
            dlg.setLocationRelativeTo(SwingUtilities.getWindowAncestor(this));
            dlg.setVisible(true);

            if (approved[0]) {
                updateManifestFromTable(model, fastqDir);
                return true;
            }
            return false;

        } catch (Exception e) {
            console.warn("Reconciliation dialog error: " + e.getMessage());
            int ch = JOptionPane.showConfirmDialog(
                    SwingUtilities.getWindowAncestor(this),
                    "Could not parse reconciliation data.\nProceed anyway?",
                    "EzMAP v2.0", JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
            return ch == JOptionPane.YES_OPTION;
        }
    }

    private void updateManifestFromTable(DefaultTableModel model, String fastqDir) {
        try {
            Path manifestPath = Paths.get(fastqDir, "samples_manifest.tsv");
            if (!Files.exists(manifestPath)) return;

            java.util.Map<String, String> idMap = new java.util.LinkedHashMap<>();
            for (int i = 0; i < model.getRowCount(); i++) {
                String fastqId = (String) model.getValueAt(i, 0);
                String metaId  = (String) model.getValueAt(i, 1);
                if (metaId != null && !metaId.trim().isEmpty()) {
                    idMap.put(fastqId, metaId.trim());
                }
            }

            java.util.List<String> lines = Files.readAllLines(manifestPath, StandardCharsets.UTF_8);
            if (lines.isEmpty()) return;

            StringBuilder sb = new StringBuilder();
            sb.append(lines.get(0)).append("\n");
            for (int i = 1; i < lines.size(); i++) {
                String line = lines.get(i).trim();
                if (line.isEmpty()) continue;
                String[] parts = line.split("\t", 2);
                String newId = idMap.getOrDefault(parts[0], parts[0]);
                sb.append(newId);
                if (parts.length > 1) sb.append("\t").append(parts[1]);
                sb.append("\n");
            }
            Files.write(manifestPath, sb.toString().getBytes(StandardCharsets.UTF_8));
            console.ok("Manifest updated with approved sample IDs.");
        } catch (IOException e) {
            console.warn("Could not update manifest: " + e.getMessage());
        }
    }

    // ==================================================================
    //  PHASE 2: Pipeline Launch
    // ==================================================================

    private void startPipeline() {
        if (!validationPassed) {
            console.warn("Please validate inputs first.");
            return;
        }
        runBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        console.info("Launching Easy Mode pipeline\u2026");

        final String fastq = fastqPicker.getPath();
        final String meta  = metaPicker.getPath();
        final String out   = outPicker.getPath();
        final String clf   = classifierPicker.isEmpty() ? "" : classifierPicker.getPath();
        final String amp   = (String) amplicon.getSelectedItem();
        final int    th    = (Integer) threads.getValue();
        final String den   = denoiser.getSelectedIndex() == 0 ? "dada2" : "deblur";
        final boolean lowMem = lowMemBox.isSelected() && "dada2".equals(den);

        new Thread(() -> runPipeline(fastq, meta, out, clf, amp, th, den, lowMem)).start();
    }

    private void runPipeline(String fastq, String meta, String out,
                             String clf, String amp, int th,
                             String den, boolean lowMem) {
        try {
            String osName = System.getProperty("os.name").toLowerCase();
            String projectDir = System.getProperty("user.dir");
            String scriptHost = projectDir + File.separator + "scripts" + File.separator + "easy_mode.sh";

            ProcessBuilder pb;

            if (osName.contains("win")) {
                String scriptWsl = toWsl(scriptHost);
                String fastqWsl  = toWsl(fastq);
                String metaWsl   = toWsl(meta);
                String outWsl    = toWsl(out);
                String clfWsl    = clf.isEmpty() ? "" : toWsl(clf);

                // Build path to classifiers dir in WSL-accessible /mnt/ format
                String winHome = System.getProperty("user.home").replace('\\', '/');
                String wslHome = "/mnt/" + Character.toLowerCase(winHome.charAt(0)) + winHome.substring(2);
                String clDirWsl = wslHome + "/ezmap2-classifiers";

                StringBuilder cmd = new StringBuilder();
                cmd.append("export CLASSIFIERS_DIR=\"").append(clDirWsl).append("\"; ");
                cmd.append("bash ").append(q(scriptWsl))
                   .append(" --fastq-dir ").append(q(fastqWsl))
                   .append(" --metadata ").append(q(metaWsl))
                   .append(" --output-dir ").append(q(outWsl))
                   .append(" --amplicon ").append(amp)
                   .append(" --threads ").append(th)
                   .append(" --denoiser ").append(den)
                   .append(" --resume");
                if (lowMem)            cmd.append(" --low-memory");
                if (!clfWsl.isEmpty()) cmd.append(" --classifier ").append(q(clfWsl));

                console.info("WSL command: " + cmd);
                pb = new ProcessBuilder("wsl.exe", "-d", EzMAP2.ui.WslEnv.distro(), "--", "bash", "-lc", cmd.toString());
            } else {
                java.util.List<String> cmd = new java.util.ArrayList<>();
                cmd.add("bash"); cmd.add(scriptHost);
                cmd.add("--fastq-dir"); cmd.add(fastq);
                cmd.add("--metadata");  cmd.add(meta);
                cmd.add("--output-dir");cmd.add(out);
                cmd.add("--amplicon");  cmd.add(amp);
                cmd.add("--threads");   cmd.add(String.valueOf(th));
                cmd.add("--denoiser");  cmd.add(den);
                cmd.add("--resume");
                if (lowMem)         cmd.add("--low-memory");
                if (!clf.isEmpty()) { cmd.add("--classifier"); cmd.add(clf); }
                pb = new ProcessBuilder(cmd);
            }
            pb.redirectErrorStream(true);
            pb.directory(new File(projectDir));

            runningProcess = pb.start();
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(runningProcess.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) {
                    String s = line;
                    SwingUtilities.invokeLater(() -> routeLogLine(s));
                }
            }
            int exit = runningProcess.waitFor();
            SwingUtilities.invokeLater(() -> {
                if (exit == 0) {
                    console.ok("Easy Mode pipeline finished successfully.");
                    console.info("Results folder: " + out);
                    lastOutputDir = out;
                    // Navigate to the Results & Summary page
                    navigateToResults(out);
                } else {
                    console.err("Pipeline exited with code " + exit + ".");
                }
                runBtn.setEnabled(true);
                stopBtn.setEnabled(false);
            });
        } catch (IOException | InterruptedException ex) {
            SwingUtilities.invokeLater(() -> {
                console.err("Failed to launch pipeline: " + ex.getMessage());
                runBtn.setEnabled(true);
                stopBtn.setEnabled(false);
            });
        }
    }

    // ==================================================================
    //  Results, Navigation, Helpers
    // ==================================================================

    /** Navigate to the ResultsSummaryPage, loading results from the output directory. */
    private void navigateToResults(String outDir) {
        // Load results into the summary page
        ResultsSummaryPage resultsPage = (ResultsSummaryPage) wizard.getPages().get("results-summary");
        if (resultsPage != null) {
            resultsPage.loadResults(outDir);
        }

        // Ensure results-summary is in the flow
        java.util.List<String> flow   = new java.util.ArrayList<>(wizard.getActiveFlow());
        java.util.List<String> labels = new java.util.ArrayList<>(wizard.getActiveLabels());
        if (!flow.contains("results-summary")) {
            flow.add("results-summary");
            labels.add("Results & Summary");
            wizard.setActiveFlow(flow, labels);
        }
        wizard.showId("results-summary");
    }

    private void showResults(String outDir) {
        String bundle = findBundleZip(outDir);
        StringBuilder html = new StringBuilder("<html><body style='font-family:sans-serif'>");
        html.append("<b style='color:#16A34A'>\u2713 Upstream pipeline complete.</b><br><br>");
        html.append("Output: <code>").append(outDir).append("</code><br>");
        if (bundle != null)
            html.append("Bundle: <code>").append(new File(bundle).getName()).append("</code><br>");
        html.append("<br><b>Bundle contents:</b><br>");
        html.append("<code>feature-table.biom</code> \u2014 ASV abundance table<br>");
        html.append("<code>feature-table-tax.biom</code> \u2014 BIOM with taxonomy metadata<br>");
        html.append("<code>taxonomy.tsv</code> \u2014 Taxonomic classifications<br>");
        html.append("<code>rooted-tree.nwk</code> \u2014 Phylogenetic tree<br>");
        html.append("<code>rep-seqs.fasta</code> \u2014 Representative sequences<br>");
        html.append("<code>denoising-stats.tsv</code> \u2014 DADA2/Deblur stats<br>");
        html.append("<code>metadata.tsv</code> \u2014 Sample metadata<br>");
        html.append("<code>parameters.json</code> \u2014 Full run parameters<br>");
        html.append("<br><i>Load this bundle in the EzMAP v2.0 Downstream (Shiny) module.</i>");
        html.append("</body></html>");
        resultsSummary.setText(html.toString());
        openBundleBtn.setEnabled(bundle != null);
        resultsCard.setVisible(true);
        resultsCard.revalidate();
        resultsCard.repaint();
    }

    private void stopPipeline() {
        if (runningProcess != null && runningProcess.isAlive()) {
            runningProcess.destroy();
            console.warn("Stop requested; sending SIGTERM\u2026");
        }
    }

    private void goToDownstream() {
        java.util.List<String> flow   = new java.util.ArrayList<>(wizard.getActiveFlow());
        java.util.List<String> labels = new java.util.ArrayList<>(wizard.getActiveLabels());
        if (!flow.contains("downstream")) {
            flow.add("downstream");
            labels.add("Downstream Analysis");
            wizard.setActiveFlow(flow, labels);
        }
        wizard.showId("downstream");
    }

    private void openPath(String path) {
        if (path == null || path.isEmpty()) return;
        File f = new File(path);
        if (!f.exists()) { console.warn("Path not found: " + path); return; }
        try { Desktop.getDesktop().open(f); }
        catch (IOException ex) { console.err("Cannot open: " + ex.getMessage()); }
    }

    private String findBundleZip(String outDir) {
        if (outDir == null) return null;
        // The zip is created at $OUTPUT_DIR/EzMAP2_results_*.zip (same level as bundle/)
        File outFile = new File(outDir);
        if (!outFile.isDirectory()) return null;
        File[] zips = outFile.listFiles((d, n) -> n.startsWith("EzMAP2_results_") && n.endsWith(".zip"));
        if (zips == null || zips.length == 0) return null;
        File newest = zips[0];
        for (File z : zips) if (z.lastModified() > newest.lastModified()) newest = z;
        return newest.getAbsolutePath();
    }

    private void routeLogLine(String line) {
        String stripped = line.replaceAll("\u001B\\[[;\\d]*m", "");
        String lower = stripped.toLowerCase();
        if (lower.contains("\u2713") || lower.contains("[ok]") || lower.contains("finished successfully"))
            console.ok(stripped);
        else if (lower.contains("\u26A0") || lower.contains("warn"))
            console.warn(stripped);
        else if (lower.contains("\u2718") || lower.contains("error") || lower.contains("failed"))
            console.err(stripped);
        else
            console.info(stripped);
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

    private JComponent defaultsSummary() {
        String html =
            "<html><body style='font-family:sans-serif;color:#334155'>"
          + "<table cellpadding='3' style='font-size:10px'>"
          + "  <tr><td><b>Pipeline</b></td><td>7 steps: Manifest → Import → Cutadapt → Smart-trim → Denoise → Phylogeny → Taxonomy</td></tr>"
          + "  <tr><td><b>Primers</b></td><td>V3\u2013V4 = 341F/805R · V4 = 515F/806R · ITS1F/ITS2 · ITS3/ITS4</td></tr>"
          + "  <tr><td><b>Cutadapt</b></td><td>--discard-untrimmed, min-len 50</td></tr>"
          + "  <tr><td><b>Smart trim</b></td><td>forward Q\u226525, reverse Q\u226520, floor 150 bp</td></tr>"
          + "  <tr><td><b>DADA2</b></td><td>chimera=consensus; auto-trim; threads per toggle</td></tr>"
          + "  <tr><td><b>Taxonomy</b></td><td>classify-sklearn · confidence\u22650.7 · SILVA 138.2 / UNITE 10</td></tr>"
          + "  <tr><td><b>Output</b></td><td>BIOM (with taxonomy) + tree + stats → Shiny downstream</td></tr>"
          + "</table></body></html>";
        JLabel l = new JLabel(html);
        l.setBorder(BorderFactory.createEmptyBorder(4, 4, 4, 4));
        return l;
    }

    // --- JSON helpers (no external deps) ---
    private static String extractJsonString(String json, String key) {
        int idx = json.indexOf("\"" + key + "\"");
        if (idx < 0) return "";
        int colonIdx = json.indexOf(":", idx + key.length() + 2);
        if (colonIdx < 0) return "";
        int start = colonIdx + 1;
        while (start < json.length() && json.charAt(start) == ' ') start++;
        if (start >= json.length()) return "";
        if (json.charAt(start) == '"') {
            int end = json.indexOf('"', start + 1);
            return end > start ? json.substring(start + 1, end) : "";
        } else {
            int end = start;
            while (end < json.length() && json.charAt(end) != ',' && json.charAt(end) != '}'
                    && json.charAt(end) != '\n') end++;
            return json.substring(start, end).trim();
        }
    }

    private java.util.List<String[]> parseReconciliationRows(String json) {
        java.util.List<String[]> rows = new java.util.ArrayList<>();
        int mapIdx = json.indexOf("\"mapping\"");
        if (mapIdx < 0) return rows;
        int braceStart = json.indexOf('{', mapIdx);
        if (braceStart < 0) return rows;

        // Find the matching closing brace for the mapping object using depth counting
        int mappingEnd = findMatchingBrace(json, braceStart);
        if (mappingEnd < 0) mappingEnd = json.length();
        String mappingBlock = json.substring(braceStart + 1, mappingEnd);

        int pos = 0;
        while (pos < mappingBlock.length()) {
            int keyStart = mappingBlock.indexOf('"', pos);
            if (keyStart < 0) break;
            int keyEnd = mappingBlock.indexOf('"', keyStart + 1);
            if (keyEnd < 0) break;
            String manifestId = mappingBlock.substring(keyStart + 1, keyEnd);
            int valStart = mappingBlock.indexOf('{', keyEnd);
            if (valStart < 0) break;
            int valEnd = findMatchingBrace(mappingBlock, valStart);
            if (valEnd < 0) break;
            String entry = mappingBlock.substring(valStart, valEnd + 1);
            String matchedTo  = extractJsonString(entry, "matched_to");
            String method     = extractJsonString(entry, "method");
            String finalId    = extractJsonString(entry, "final_id");
            String confidence = extractJsonString(entry, "confidence");
            if ("null".equals(matchedTo)) matchedTo = "";
            if (finalId.isEmpty()) finalId = matchedTo.isEmpty() ? manifestId : matchedTo;
            if (confidence.isEmpty()) confidence = "0.0";
            rows.add(new String[]{manifestId, matchedTo, method, finalId, confidence});
            pos = valEnd + 1;
        }
        return rows;
    }

    /** Find the index of the closing '}' that matches the opening '{' at position openIdx. */
    private static int findMatchingBrace(String s, int openIdx) {
        int depth = 0;
        boolean inString = false;
        for (int i = openIdx; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' && (i == 0 || s.charAt(i - 1) != '\\')) {
                inString = !inString;
            } else if (!inString) {
                if (c == '{') depth++;
                else if (c == '}') {
                    depth--;
                    if (depth == 0) return i;
                }
            }
        }
        return -1;
    }

    private static Component findByName(Container c, String name) {
        for (Component child : c.getComponents()) {
            if (name.equals(child.getName())) return child;
            if (child instanceof Container) {
                Component found = findByName((Container) child, name);
                if (found != null) return found;
            }
        }
        return null;
    }

    /**
     * Locate generate_manifest.py — checks multiple candidate locations
     * relative to the project directory (same logic as ManifestPage.findScript).
     */
    private static String findGenerateManifest(String projectDir) {
        String name = "generate_manifest.py";
        String sep = File.separator;
        String[] candidates = {
            projectDir + sep + name,                                   // root
            projectDir + sep + "scripts" + sep + name,                 // scripts/
            new File(projectDir).getParent() + sep + name,             // parent/
            new File(projectDir).getParent() + sep + "scripts" + sep + name, // parent/scripts/
        };
        for (String path : candidates) {
            if (new File(path).isFile()) return path;
        }
        return null;
    }

    private static String toWsl(String winPath) {
        if (winPath == null || winPath.isEmpty()) return winPath;
        String p = winPath.replace("\\", "/");
        if (p.length() >= 2 && p.charAt(1) == ':') {
            String drive = Character.toString(Character.toLowerCase(p.charAt(0)));
            return "/mnt/" + drive + p.substring(2);
        }
        return p;
    }

    // Quote a path for a bash command sent through wsl.exe. Use SINGLE quotes:
    // double quotes get mangled passing Windows -> wsl.exe -> bash, which splits
    // paths at spaces (e.g. OneDrive folders, "EzMAP experimental database").
    // Single quotes survive that chain; embedded single quotes are escaped the
    // bash-safe way ('\'').
    private static String q(String s) { return "'" + s.replace("'", "'\\''") + "'"; }
}
