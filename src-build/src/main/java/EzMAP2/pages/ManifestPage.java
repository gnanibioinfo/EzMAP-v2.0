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

/**
 * Expert Mode — Step 1: Validate Inputs.
 *
 * Mirrors Easy Mode's smart logic:
 *   - Project directory picker (sets start dir for all other pickers)
 *   - FASTQ directory, Metadata file, Output directory
 *   - Auto-detects FASTQ type (paired/single/Casava/EMP)
 *   - Generates manifest, reconciles sample IDs with metadata
 *   - Stores everything in wizard properties for subsequent pages
 */
public class ManifestPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    // --- Input pickers (same pattern as Easy Mode) ---
    private final DirectoryPicker projectPicker;
    private final DirectoryPicker fastqPicker;
    private final DirectoryPicker metaPicker;
    private final DirectoryPicker outPicker;

    // --- Amplicon & primer status (asked upfront) ---
    private final JComboBox<String> ampliconCombo = new JComboBox<>(
            new String[]{"16S-V4", "16S-V3V4", "ITS1", "ITS2", "Custom"});
    private final JComboBox<String> primerStatusCombo = new JComboBox<>(
            new String[]{
                "Present in reads (run Cutadapt)",
                "Already removed (skip Cutadapt)",
                "I don't know (auto-detect)"
            });

    // --- Controls ---
    private final PrimaryButton validateBtn = new PrimaryButton("Validate Inputs");
    private final OutlineButton openBtn     = new OutlineButton("Open Manifest");
    private final JLabel statusLabel        = new JLabel(" ");
    private final LogConsole console         = new LogConsole();

    public ManifestPage(WizardController wizard) {
        super("Expert Mode — Step 1: Validate Inputs",
              "Select your project directory, FASTQ folder, metadata file, and output location. " +
              "EzMAP v2 will auto-detect the FASTQ format, generate a QIIME2 manifest, " +
              "and validate sample IDs against your metadata.");
        this.wizard = wizard;

        // ---- Card 1: Input files ----
        Card inputCard = new Card("1 \u00B7 Input Files");

        inputCard.row(caption("Project / Working directory (sets default location for all browsers):"));
        projectPicker = new DirectoryPicker("Select working directory",
                f -> onProjectDirSet(f));
        inputCard.row(projectPicker).gap(10);

        inputCard.row(caption("FASTQ folder (paired-end or single-end reads):"));
        fastqPicker = new DirectoryPicker("Select FASTQ directory",
                f -> onFastqPicked(f));
        inputCard.row(fastqPicker).gap(8);

        inputCard.row(caption("Metadata file (.tsv) \u2014 sample IDs in first column:"));
        metaPicker = new DirectoryPicker("Select metadata .tsv file",
                f -> refreshValidateState(), true);
        inputCard.row(metaPicker).gap(8);

        inputCard.row(caption("Output directory (for all pipeline results):"));
        outPicker = new DirectoryPicker("Select output directory",
                f -> refreshValidateState());
        inputCard.row(outPicker);

        add(inputCard);

        // ---- Card 1b: Amplicon & Primer Status ----
        Card ampliconCard = new Card("2 \u00B7 Sequencing Details");

        ampliconCard.row(new InfoBanner(InfoBanner.Kind.INFO, "About your data",
                "Tell EzMAP v2 about your amplicon region and whether primers/barcodes are still in the reads. " +
                "This information is used for primer removal, quality trimming, and overlap estimation. " +
                "If you don\u2019t know, select \u201CI don\u2019t know\u201D and EzMAP v2 will auto-detect."))
                .gap(10);

        JPanel ampGrid = new JPanel(new GridBagLayout());
        ampGrid.setOpaque(false);
        GridBagConstraints agc = new GridBagConstraints();
        agc.insets = new Insets(6, 0, 6, 12);
        agc.anchor = GridBagConstraints.WEST;

        agc.gridx = 0; agc.gridy = 0;
        JLabel ampLabel = new JLabel("Amplicon region:");
        ampLabel.setFont(Theme.FONT_BODY);
        ampLabel.setForeground(Theme.INK_2);
        ampLabel.setToolTipText("The 16S/ITS region targeted by your primers. Used for overlap estimation and primer auto-fill.");
        ampGrid.add(ampLabel, agc);
        agc.gridx = 1; agc.fill = GridBagConstraints.HORIZONTAL; agc.weightx = 1;
        ampliconCombo.setFont(Theme.FONT_BODY);
        ampGrid.add(ampliconCombo, agc);

        agc.gridx = 0; agc.gridy = 1; agc.fill = GridBagConstraints.NONE; agc.weightx = 0;
        JLabel primerLabel = new JLabel("Primers/barcodes:");
        primerLabel.setFont(Theme.FONT_BODY);
        primerLabel.setForeground(Theme.INK_2);
        primerLabel.setToolTipText("Are primers and barcodes still present in the reads, or have they already been removed?");
        ampGrid.add(primerLabel, agc);
        agc.gridx = 1; agc.fill = GridBagConstraints.HORIZONTAL; agc.weightx = 1;
        primerStatusCombo.setFont(Theme.FONT_BODY);
        ampGrid.add(primerStatusCombo, agc);

        ampliconCard.row(ampGrid);
        add(ampliconCard);

        // ---- Card 3: Info + Action ----
        Card actionCard = new Card("3 \u00B7 Validate & Generate Manifest");

        actionCard.row(new InfoBanner(InfoBanner.Kind.INFO,
                "What validation does",
                "Detects your FASTQ file format (paired-end, single-end, Casava, EMP), " +
                "generates a sample manifest, and checks that FASTQ sample IDs match your metadata file. " +
                "If IDs don\u2019t match exactly, EzMAP v2 uses intelligent fuzzy matching and asks for approval."))
               .gap(10);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        btnRow.add(validateBtn);
        btnRow.add(openBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        actionCard.row(btnRow);
        add(actionCard);

        // ---- Card 4: Log ----
        Card logCard = new Card("Execution log");
        console.setPreferredSize(new Dimension(0, 180));
        logCard.row(console);
        add(logCard);

        // ---- Navigation: Back to Mode Selection ----
        JPanel navRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        navRow.setOpaque(false);
        GhostButton backBtn = new GhostButton("\u2190  Back to Mode Selection");
        backBtn.addActionListener(e -> wizard.previous());
        navRow.add(backBtn);
        add(navRow);

        // ---- Wiring ----
        validateBtn.setEnabled(false);
        openBtn.setEnabled(false);
        validateBtn.addActionListener(e -> executeValidation());
        openBtn.addActionListener(e -> openManifest());
    }

    // ================================================================
    //  Smart directory propagation (same pattern as Easy Mode)
    // ================================================================

    /** When project dir is selected, propagate to all other pickers. */
    private void onProjectDirSet(File dir) {
        if (dir == null || !dir.isDirectory()) return;
        fastqPicker.setStartDirectory(dir);
        metaPicker.setStartDirectory(dir);
        outPicker.setStartDirectory(dir);
        // Pre-fill output to projectDir/output if not already set
        if (outPicker.isEmpty()) {
            outPicker.setPath(dir.getAbsolutePath() + File.separator + "output");
        }
        refreshValidateState();
    }

    /** When FASTQ folder is selected, point metadata/output pickers nearby. */
    private void onFastqPicked(File fastqDir) {
        if (fastqDir != null) {
            File parent = fastqDir.getParentFile();
            if (parent != null && parent.isDirectory()) {
                if (metaPicker.isEmpty()) metaPicker.setStartDirectory(parent);
                if (outPicker.isEmpty())  outPicker.setStartDirectory(parent);
            }
        }
        refreshValidateState();
    }

    @Override
    public void onShown() {
        refreshValidateState();
    }

    private void refreshValidateState() {
        validateBtn.setEnabled(!fastqPicker.isEmpty() && !metaPicker.isEmpty()
                && !outPicker.isEmpty());
    }

    // ================================================================
    //  Locate generate_manifest.py
    // ================================================================
    private File findScript(File baseDir) {
        String name = "generate_manifest.py";
        File[] candidates = {
            new File(baseDir, name),
            new File(baseDir, "scripts" + File.separator + name),
            new File(baseDir.getParentFile(), name),
            new File(baseDir.getParentFile(), "scripts" + File.separator + name),
        };
        for (File f : candidates) {
            if (f.isFile()) return f;
        }
        return null;
    }

    // ================================================================
    //  Execute validation: detect type + generate manifest + reconcile
    // ================================================================
    private void executeValidation() {
        validateBtn.setEnabled(false);
        openBtn.setEnabled(false);
        statusLabel.setText("<html><span style='color:#64748B'>Validating\u2026</span></html>");
        console.clear();
        console.info("Starting input validation\u2026");

        final String fastqDir = fastqPicker.getPath();
        final String metaFile = metaPicker.getPath();
        final String outDir   = outPicker.getPath();

        new Thread(() -> {
            try {
                new File(outDir).mkdirs();

                File scriptDir = new File(System.getProperty("user.dir"));
                File scriptFile = findScript(scriptDir);
                if (scriptFile == null) {
                    SwingUtilities.invokeLater(() -> {
                        console.err("generate_manifest.py not found.");
                        console.err("Searched in: " + scriptDir.getAbsolutePath()
                                + " and scripts/ subfolder.");
                        statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Script not found</span></html>");
                        validateBtn.setEnabled(true);
                    });
                    return;
                }

                String manifestPath = fastqDir + File.separator + "samples_manifest.tsv";
                String os = System.getProperty("os.name").toLowerCase();
                ProcessBuilder pb;

                if (os.contains("win")) {
                    String scriptWsl = toWsl(scriptFile.getAbsolutePath());
                    String fastqWsl  = toWsl(fastqDir);
                    String metaWsl   = toWsl(metaFile);
                    String manifestWsl = toWsl(manifestPath);

                    String cmd = "python3 " + q(scriptWsl) + " " + q(fastqWsl)
                            + " " + q(manifestWsl)
                            + " --metadata " + q(metaWsl);

                    final String displayCmd = cmd;
                    SwingUtilities.invokeLater(() -> console.info("WSL: " + displayCmd));
                    pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                            "bash", "-lc", cmd);
                } else {
                    pb = new ProcessBuilder("python3",
                            scriptFile.getAbsolutePath(), fastqDir,
                            manifestPath, "--metadata", metaFile);
                    SwingUtilities.invokeLater(() ->
                        console.info("Script: " + scriptFile.getAbsolutePath()));
                }

                pb.redirectErrorStream(true);
                pb.directory(scriptFile.getParentFile());

                Process proc = pb.start();
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        final String s = line;
                        SwingUtilities.invokeLater(() -> console.info(s));
                    }
                }
                int exit = proc.waitFor();

                if (exit != 0) {
                    SwingUtilities.invokeLater(() -> {
                        console.err("Validation failed (exit code " + exit + ").");
                        statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Failed</span></html>");
                        validateBtn.setEnabled(true);
                    });
                    return;
                }

                // --- Read fastq_type.json ---
                File fastqTypeFile = new File(fastqDir, "fastq_type.json");
                String fastqTypeJson = fastqTypeFile.exists()
                        ? new String(Files.readAllBytes(fastqTypeFile.toPath()), StandardCharsets.UTF_8)
                        : null;

                // --- Read reconciliation.json ---
                File reconFile = new File(fastqDir, "reconciliation.json");
                String reconJson = reconFile.exists()
                        ? new String(Files.readAllBytes(reconFile.toPath()), StandardCharsets.UTF_8)
                        : null;

                // --- Show dialogs on EDT ---
                SwingUtilities.invokeAndWait(() -> {
                    // 1) FASTQ Type Alert
                    if (fastqTypeJson != null) {
                        showFastqTypeAlert(fastqTypeJson);

                        String format = extractJsonString(fastqTypeJson, "format");
                        String type   = extractJsonString(fastqTypeJson, "type");
                        String paired = extractJsonString(fastqTypeJson, "paired");

                        wizard.put("fastq.format", format);
                        wizard.put("fastq.type", type);
                        wizard.put("read.type", "true".equals(paired) ? "paired" : "single");

                        console.ok("Detected: " + format
                                + " (" + ("true".equals(paired) ? "paired-end" : "single-end") + ")");
                    }

                    // 2) Sample ID Reconciliation
                    boolean approved = true;
                    if (reconJson != null) {
                        approved = showReconciliationDialog(reconJson, fastqDir);
                    }

                    if (approved) {
                        // Store amplicon and primer status
                        String selectedAmplicon = (String) ampliconCombo.getSelectedItem();
                        String selectedPrimerStatus = (String) primerStatusCombo.getSelectedItem();
                        wizard.put("amplicon", selectedAmplicon);
                        if (selectedPrimerStatus.startsWith("Present")) {
                            wizard.put("primer.status", "present");
                        } else if (selectedPrimerStatus.startsWith("Already")) {
                            wizard.put("primer.status", "removed");
                        } else {
                            wizard.put("primer.status", "auto-detect");
                        }

                        wizard.put("fastq.dir", fastqDir);
                        wizard.put("metadata.tsv", metaFile);
                        wizard.put("output.dir", outDir);
                        wizard.put("manifest.tsv", manifestPath);

                        // ----- Pipeline log persistence (Expert Mode) -----
                        // Easy Mode tees its shell-script output to
                        //   <output.dir>/logs/pipeline.log
                        // via "exec > >(tee -a ...) 2>&1" inside easy_mode.sh.
                        // Expert Mode runs QIIME 2 commands directly from
                        // Java, so the log used to live only in the in-memory
                        // LogConsole and was lost when the app closed. We
                        // configure QiimeCommand to mirror every subsequent
                        // run() / runBash() call to the same file path so
                        // Expert Mode produces the same pipeline.log artifact.
                        try {
                            Path logFile = Paths.get(outDir, "logs", "pipeline.log");
                            Files.createDirectories(logFile.getParent());
                            QiimeCommand.setPipelineLogFile(logFile.toFile());
                            console.info("Pipeline log will be saved to " + logFile);
                        } catch (IOException logErr) {
                            console.warn("Could not create pipeline log file: "
                                    + logErr.getMessage());
                        }

                        statusLabel.setText(
                            "<html><span style='color:#16A34A'>\u2713 Validation passed \u2014 proceed to Import</span></html>");
                        console.ok("Manifest: " + manifestPath);
                        console.ok("Metadata: " + metaFile);
                        console.ok("All inputs validated. Proceed to the next step.");
                        openBtn.setEnabled(true);
                        stepComplete = true;
                        notifyStepCompletion();
                    } else {
                        statusLabel.setText(
                            "<html><span style='color:#DC2626'>\u2718 Fix sample IDs and re-validate</span></html>");
                        console.warn("Fix your metadata sample IDs and try again.");
                    }
                    validateBtn.setEnabled(true);
                });

            } catch (Exception ex) {
                SwingUtilities.invokeLater(() -> {
                    console.err("Error: " + ex.getMessage());
                    statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Error</span></html>");
                    validateBtn.setEnabled(true);
                });
            }
        }).start();
    }

    // ================================================================
    //  FASTQ Type Detection Alert
    // ================================================================
    private void showFastqTypeAlert(String jsonStr) {
        try {
            String format = extractJsonString(jsonStr, "format");
            String type   = extractJsonString(jsonStr, "type");
            String desc   = extractJsonString(jsonStr, "description");
            String paired = extractJsonString(jsonStr, "paired");
            String files  = extractJsonString(jsonStr, "files_found");

            JDialog dlg = new JDialog(
                    (Frame) SwingUtilities.getWindowAncestor(this),
                    "FASTQ Detection \u2014 EzMAP v2", true);
            dlg.setDefaultCloseOperation(JDialog.DISPOSE_ON_CLOSE);

            JPanel root = new JPanel(new BorderLayout(0, 0));
            root.setBackground(Theme.SURFACE);

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

            gc.gridx = 0; gc.gridy = rows.length; gc.gridwidth = 2;
            gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
            gc.insets = new Insets(14, 0, 4, 0);
            JLabel descLbl = new JLabel("<html><body style='width:520px; color:#64748B; font-size:11px'>"
                    + desc + "</body></html>");
            body.add(descLbl, gc);

            gc.gridy++;
            gc.insets = new Insets(4, 0, 0, 0);
            body.add(new JLabel("<html><b style='color:#0B5E5D; font-size:11px'>"
                    + "This format will be used automatically in the Import step.</b></html>"), gc);
            root.add(body, BorderLayout.CENTER);

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

    // ================================================================
    //  Sample ID Reconciliation Dialog
    // ================================================================
    private boolean showReconciliationDialog(String jsonStr, String fastqDir) {
        try {
            boolean allMatched = jsonStr.contains("\"all_matched\": true");
            java.util.List<String[]> rows = parseReconciliationRows(jsonStr);

            if (rows.isEmpty()) return true;

            boolean allExact = rows.stream().allMatch(r -> "exact".equals(r[2]));
            if (allExact) {
                console.ok("All " + rows.size() + " sample IDs match exactly.");
                return true;
            }

            final boolean[] approved = {false};
            JDialog dlg = new JDialog(
                    (Frame) SwingUtilities.getWindowAncestor(this),
                    allMatched ? "Sample ID Reconciliation" : "Sample ID Mismatch", true);
            dlg.setDefaultCloseOperation(JDialog.DISPOSE_ON_CLOSE);

            JPanel root = new JPanel(new BorderLayout(0, 0));
            root.setBackground(Theme.SURFACE);

            Color headerBg, headerBorder, headerText;
            if (allMatched) {
                headerBg     = new Color(0xFF, 0xFB, 0xEB);
                headerBorder = new Color(0xFB, 0xBF, 0x24);
                headerText   = new Color(0x92, 0x40, 0x0E);
            } else {
                headerBg     = new Color(0xFE, 0xF2, 0xF2);
                headerBorder = new Color(0xF8, 0x71, 0x71);
                headerText   = new Color(0x99, 0x1B, 0x1B);
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

            String explanation = allMatched
                ? "<html><body style='width:680px'>FASTQ filenames produce <b>different sample IDs</b> "
                  + "than your metadata. EzMAP v2 auto-matched them. <b>Review and click OK if correct.</b> "
                  + "Double-click <i>Metadata ID</i> to edit.</body></html>"
                : "<html><body style='width:680px'>Some FASTQ IDs could <b>not</b> be matched. "
                  + "<b>Fix metadata</b> or double-click <i>Metadata ID</i> to type the correct ID.</body></html>";
            JLabel explanationLbl = new JLabel(explanation);
            explanationLbl.setFont(Theme.FONT_BODY);
            explanationLbl.setForeground(Theme.INK_2);
            explanationLbl.setAlignmentX(LEFT_ALIGNMENT);
            header.add(explanationLbl);
            root.add(header, BorderLayout.NORTH);

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
            table.setGridColor(Theme.BORDER);
            table.setShowGrid(true);
            table.getTableHeader().setFont(Theme.FONT_BODY_BOLD);

            // Color-code status
            table.getColumnModel().getColumn(4).setCellRenderer(new DefaultTableCellRenderer() {
                @Override public Component getTableCellRendererComponent(JTable t, Object v,
                        boolean sel, boolean focus, int row, int col) {
                    Component c = super.getTableCellRendererComponent(t, v, sel, focus, row, col);
                    String val = v != null ? v.toString() : "";
                    if (val.startsWith("\u2713"))      c.setForeground(Theme.SUCCESS);
                    else if (val.startsWith("\u2718")) c.setForeground(Theme.DANGER);
                    else                               c.setForeground(Theme.WARNING);
                    return c;
                }
            });

            JPanel tablePanel = new JPanel(new BorderLayout());
            tablePanel.setBorder(BorderFactory.createEmptyBorder(16, 20, 8, 20));
            tablePanel.add(new JScrollPane(table), BorderLayout.CENTER);
            root.add(tablePanel, BorderLayout.CENTER);

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
            console.warn("Reconciliation error: " + e.getMessage());
            return JOptionPane.showConfirmDialog(
                    SwingUtilities.getWindowAncestor(this),
                    "Could not parse reconciliation data.\nProceed anyway?",
                    "EzMAP v2", JOptionPane.YES_NO_OPTION) == JOptionPane.YES_OPTION;
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

    // ================================================================
    //  Open manifest
    // ================================================================
    private void openManifest() {
        String fastqDir = fastqPicker.getPath();
        if (fastqDir == null) return;
        File f = new File(fastqDir, "samples_manifest.tsv");
        try {
            if (f.exists()) Desktop.getDesktop().open(f);
            else console.warn("Manifest not found: " + f.getAbsolutePath());
        } catch (IOException ex) {
            console.err("Couldn't open: " + ex.getMessage());
        }
    }

    // ================================================================
    //  Helpers
    // ================================================================
    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

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

    private static int findMatchingBrace(String s, int openIdx) {
        int depth = 0;
        boolean inString = false;
        for (int i = openIdx; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' && (i == 0 || s.charAt(i - 1) != '\\')) inString = !inString;
            else if (!inString) {
                if (c == '{') depth++;
                else if (c == '}') { depth--; if (depth == 0) return i; }
            }
        }
        return -1;
    }

    private static String toWsl(String winPath) {
        if (winPath == null || winPath.isEmpty()) return winPath;
        String p = winPath.replace("\\", "/");
        if (p.length() >= 2 && p.charAt(1) == ':') {
            return "/mnt/" + Character.toLowerCase(p.charAt(0)) + p.substring(2);
        }
        return p;
    }

    private static String q(String s) { return "\"" + s.replace("\"", "\\\"") + "\""; }
}
