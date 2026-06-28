package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.concurrent.TimeUnit;

/**
 * Expert Mode — Step 6: Taxonomy Assignment.
 *
 * Two modes:
 *   (A) Use pre-trained classifier — dropdown of available classifiers in ~/ezmap2-classifiers/
 *   (B) Train custom classifier — pick database + amplicon or provide custom ref-seqs + primers
 *
 * After classifier is ready, runs qiime feature-classifier classify-sklearn on the rep-seqs
 * produced by the denoising step.
 */
public class TaxonomyPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }
    private final LogConsole console = new LogConsole();

    // Classifier source selection
    private final JRadioButton rbPreTrained = new JRadioButton("Use pre-trained classifier", true);
    private final JRadioButton rbTrainNew   = new JRadioButton("Train a new classifier");
    private final JRadioButton rbCustomFile = new JRadioButton("Select custom classifier file (.qza)");

    // Pre-trained panel
    private final JComboBox<String> classifierDropdown = new JComboBox<>();
    private final JLabel classifierStatus = new JLabel(" ");
    private final OutlineButton refreshBtn = new OutlineButton("Refresh");

    // Train-new panel
    private final JComboBox<String> dbCombo = new JComboBox<>(
            new String[]{"SILVA 138.2", "Greengenes2 2024.09", "UNITE 10.0"});
    private final JComboBox<String> ampCombo = new JComboBox<>(
            new String[]{"16S-V3V4", "16S-V4", "ITS1", "ITS2"});
    private final JTextField fwdPrimerField = new JTextField(30);
    private final JTextField revPrimerField = new JTextField(30);
    private final JSpinner threadsSpinner   = new JSpinner(new SpinnerNumberModel(4, 1, 64, 1));
    private final JSpinner minLengthSpinner = new JSpinner(new SpinnerNumberModel(100, 50, 2000, 10));
    private final JSpinner maxLengthSpinner = new JSpinner(new SpinnerNumberModel(400, 100, 5000, 10));
    private final PrimaryButton trainBtn    = new PrimaryButton("Train Classifier");

    // Custom file panel
    private final JTextField classifierPathField = new JTextField(40);
    private final OutlineButton browseBtn = new OutlineButton("Browse…");

    // Classification controls
    private final JSpinner confidenceSpinner = new JSpinner(
            new SpinnerNumberModel(0.7, 0.0, 1.0, 0.05));
    private final JSpinner nJobsSpinner = new JSpinner(
            new SpinnerNumberModel(4, 1, 64, 1));
    private final JSpinner readsPerBatchSpinner = new JSpinner(
            new SpinnerNumberModel(0, 0, 100000, 1000));
    private final JTextField repSeqsField = new JTextField(40);
    private final OutlineButton repSeqsBrowseBtn = new OutlineButton("Browse…");
    private final PrimaryButton classifyBtn = new PrimaryButton("Run Classification");

    // Card panels for show/hide
    private JPanel preTrainedPanel, trainNewPanel, customFilePanel;

    // Command preview
    private final JTextArea cmdPreview = new JTextArea(3, 60);

    // State
    private String selectedClassifier = null;
    private volatile boolean isTraining = false;
    private volatile boolean isClassifying = false;

    private static final String CLASSIFIERS_DIR_NAME = "ezmap2-classifiers";

    // Primer defaults by amplicon
    private static final String[][] PRIMER_DEFAULTS = {
        {"16S-V3V4", "CCTACGGGNGGCWGCAG",      "GACTACHVGGGTATCTAATCC"},
        {"16S-V4",   "GTGYCAGCMGCCGCGGTAA",    "GGACTACNVGGGTWTCTAAT"},
        {"ITS1",     "CTTGGTCATTTAGAGGAAGTAA",  "GCTGCGTTCTTCATCGATGC"},
        {"ITS2",     "GCATCGATGAAGAACGCAGC",    "TCCTCCGCTTATTGATATGC"},
    };

    public TaxonomyPage(WizardController wizard) {
        super("Expert Mode — Step 6: Taxonomy Assignment",
              "Train or select a Naive Bayes classifier, then classify your representative sequences. "
              + "Pre-trained classifiers from ~/ezmap2-classifiers/ are listed below, or train a new one.");
        this.wizard = wizard;

        // ---- Card 1: Classifier Source ----
        Card sourceCard = new Card("Classifier Source");

        ButtonGroup bg = new ButtonGroup();
        bg.add(rbPreTrained);
        bg.add(rbTrainNew);
        bg.add(rbCustomFile);

        JPanel radioCol = new JPanel();
        radioCol.setOpaque(false);
        radioCol.setLayout(new BoxLayout(radioCol, BoxLayout.Y_AXIS));
        for (JRadioButton rb : new JRadioButton[]{rbPreTrained, rbTrainNew, rbCustomFile}) {
            rb.setFont(Theme.FONT_BODY);
            rb.setForeground(Theme.INK_1);
            rb.setOpaque(false);
            rb.setAlignmentX(LEFT_ALIGNMENT);
            radioCol.add(rb);
            radioCol.add(Box.createVerticalStrut(4));
        }
        sourceCard.row(radioCol);
        sourceCard.gap(8);

        // ---- Pre-trained sub-panel ----
        preTrainedPanel = buildPreTrainedPanel();
        sourceCard.row(preTrainedPanel);

        // ---- Train-new sub-panel ----
        trainNewPanel = buildTrainNewPanel();
        trainNewPanel.setVisible(false);
        sourceCard.row(trainNewPanel);

        // ---- Custom file sub-panel ----
        customFilePanel = buildCustomFilePanel();
        customFilePanel.setVisible(false);
        sourceCard.row(customFilePanel);

        add(sourceCard);

        // ---- Card 2: Classification Settings ----
        Card classifyCard = new Card("Classification");

        JPanel classifyGrid = new JPanel(new GridBagLayout());
        classifyGrid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(4, 0, 4, 10);
        gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        classifyGrid.add(tipLabel("Rep-seqs (.qza):",
                "Path to representative sequences (.qza) from the denoising step. These are the unique ASV/OTU sequences to classify."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        repSeqsField.setFont(Theme.FONT_SMALL);
        classifyGrid.add(repSeqsField, gc);
        gc.gridx = 2; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        classifyGrid.add(repSeqsBrowseBtn, gc);

        gc.gridx = 0; gc.gridy = 1;
        classifyGrid.add(tipLabel("Confidence:",
                "Minimum confidence threshold for taxonomy assignment (default 0.7). Assignments below this threshold are labeled 'Unassigned'. Lower values (e.g. 0.5) = more assignments but less reliable. Higher values (e.g. 0.9) = fewer but more confident assignments. Set to -1 to disable the threshold and use QIIME2's default behavior."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.NONE;
        confidenceSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) confidenceSpinner.getEditor()).getTextField().setColumns(5);
        JPanel confRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        confRow.setOpaque(false);
        confRow.add(confidenceSpinner);
        JLabel confHint = new JLabel("(0.7 = default, lower = more assignments, higher = stricter)");
        confHint.setFont(Theme.FONT_SMALL);
        confHint.setForeground(Theme.INK_3);
        confRow.add(confHint);
        classifyGrid.add(confRow, gc);

        gc.gridx = 0; gc.gridy = 2;
        classifyGrid.add(tipLabel("Parallel jobs:",
                "Number of parallel CPU jobs for classification (default 4). More jobs = faster classification. Set to -1 to use all available cores. Higher values use more memory."), gc);
        gc.gridx = 1;
        nJobsSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) nJobsSpinner.getEditor()).getTextField().setColumns(5);
        classifyGrid.add(nJobsSpinner, gc);

        gc.gridx = 0; gc.gridy = 3;
        classifyGrid.add(tipLabel("Reads per batch:",
                "Number of reads to process in each batch (default 0 = auto). For very large datasets, setting a batch size (e.g. 10000) can reduce memory usage at the cost of speed. Leave at 0 for automatic batching."), gc);
        gc.gridx = 1;
        readsPerBatchSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) readsPerBatchSpinner.getEditor()).getTextField().setColumns(5);
        JPanel batchRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        batchRow.setOpaque(false);
        batchRow.add(readsPerBatchSpinner);
        JLabel batchHint = new JLabel("(0 = auto)");
        batchHint.setFont(Theme.FONT_SMALL);
        batchHint.setForeground(Theme.INK_3);
        batchRow.add(batchHint);
        classifyGrid.add(batchRow, gc);

        classifyCard.row(classifyGrid);
        classifyCard.gap(8);

        JPanel classifyBtnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        classifyBtnRow.setOpaque(false);
        classifyBtn.setEnabled(false);
        classifyBtnRow.add(classifyBtn);
        classifyCard.row(classifyBtnRow);

        add(classifyCard);

        // ---- Card 3: Log ----
        Card logCard = new Card("Execution Log");
        console.setPreferredSize(new Dimension(0, 220));
        logCard.row(console);
        add(logCard);

        // ---- Card 4: Command Preview ----
        Card previewCard = new Card("QIIME2 Command Preview");
        cmdPreview.setEditable(false);
        cmdPreview.setFont(Theme.FONT_MONO);
        cmdPreview.setBackground(new Color(0x1E, 0x29, 0x3B));
        cmdPreview.setForeground(new Color(0xA5, 0xD6, 0xFF));
        cmdPreview.setBorder(BorderFactory.createEmptyBorder(10, 12, 10, 12));
        cmdPreview.setLineWrap(true);
        cmdPreview.setWrapStyleWord(true);
        JScrollPane previewScroll = new JScrollPane(cmdPreview);
        previewScroll.setPreferredSize(new Dimension(0, 80));
        previewScroll.setBorder(BorderFactory.createLineBorder(new Color(0x33, 0x44, 0x55)));
        previewCard.row(previewScroll);
        add(previewCard);

        // ---- Wire listeners ----
        wireListeners();
    }

    // ========================================================================
    // Sub-panels
    // ========================================================================
    private JPanel buildPreTrainedPanel() {
        JPanel panel = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 4));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(4, 24, 4, 0));

        classifierDropdown.setFont(Theme.FONT_BODY);
        classifierDropdown.setPreferredSize(new Dimension(350, 30));
        panel.add(classifierDropdown);
        panel.add(refreshBtn);

        classifierStatus.setFont(Theme.FONT_SMALL);
        classifierStatus.setForeground(Theme.INK_3);
        panel.add(classifierStatus);

        return panel;
    }

    private JPanel buildTrainNewPanel() {
        JPanel panel = new JPanel();
        panel.setOpaque(false);
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setBorder(new EmptyBorder(4, 24, 4, 0));

        JPanel grid = new JPanel(new GridBagLayout());
        grid.setOpaque(false);
        GridBagConstraints gc = new GridBagConstraints();
        gc.insets = new Insets(4, 0, 4, 10);
        gc.anchor = GridBagConstraints.WEST;

        gc.gridx = 0; gc.gridy = 0;
        grid.add(tipLabel("Database:",
                "Reference database for taxonomy. SILVA 138.2 for 16S/18S, Greengenes2 for 16S, UNITE for ITS (fungi)."), gc);
        gc.gridx = 1;
        dbCombo.setFont(Theme.FONT_BODY);
        grid.add(dbCombo, gc);

        gc.gridx = 0; gc.gridy = 1;
        grid.add(tipLabel("Amplicon:",
                "Amplicon region used in your study. Determines which region of the reference database to extract for training."), gc);
        gc.gridx = 1;
        ampCombo.setFont(Theme.FONT_BODY);
        grid.add(ampCombo, gc);

        gc.gridx = 0; gc.gridy = 2;
        grid.add(tipLabel("Fwd Primer:",
                "Forward primer used in your study. Must match the primers used for Cutadapt trimming. Used to extract the correct reference region."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        fwdPrimerField.setFont(Theme.FONT_MONO);
        grid.add(fwdPrimerField, gc);

        gc.gridx = 0; gc.gridy = 3; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        grid.add(tipLabel("Rev Primer:",
                "Reverse primer used in your study. Must match the primers used for Cutadapt trimming."), gc);
        gc.gridx = 1; gc.fill = GridBagConstraints.HORIZONTAL; gc.weightx = 1;
        revPrimerField.setFont(Theme.FONT_MONO);
        grid.add(revPrimerField, gc);

        gc.gridx = 0; gc.gridy = 4; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        grid.add(tipLabel("Min Length:",
                "Minimum amplicon length to retain after in-silico PCR (--p-min-length). "
                + "Sequences shorter than this are discarded. Typical: 100 for V4, 200 for V3-V4."), gc);
        gc.gridx = 1;
        minLengthSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) minLengthSpinner.getEditor()).getTextField().setColumns(5);
        grid.add(minLengthSpinner, gc);

        gc.gridx = 0; gc.gridy = 5;
        grid.add(tipLabel("Max Length:",
                "Maximum amplicon length to retain after in-silico PCR (--p-max-length). "
                + "Sequences longer than this are discarded. Typical: 400 for V4, 500 for V3-V4, 600 for ITS."), gc);
        gc.gridx = 1;
        maxLengthSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) maxLengthSpinner.getEditor()).getTextField().setColumns(5);
        grid.add(maxLengthSpinner, gc);

        gc.gridx = 0; gc.gridy = 6; gc.fill = GridBagConstraints.NONE; gc.weightx = 0;
        grid.add(tipLabel("Threads:",
                "Number of threads for classifier training. More threads = faster training but higher memory usage."), gc);
        gc.gridx = 1;
        threadsSpinner.setFont(Theme.FONT_BODY);
        ((JSpinner.DefaultEditor) threadsSpinner.getEditor()).getTextField().setColumns(4);
        grid.add(threadsSpinner, gc);

        grid.setAlignmentX(LEFT_ALIGNMENT);
        panel.add(grid);
        panel.add(Box.createVerticalStrut(8));

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        btnRow.setAlignmentX(LEFT_ALIGNMENT);
        trainBtn.addActionListener(e -> doTrainClassifier());
        btnRow.add(trainBtn);

        JLabel trainHint = new JLabel("Training takes 20–60 min depending on database size.");
        trainHint.setFont(Theme.FONT_SMALL);
        trainHint.setForeground(Theme.INK_3);
        btnRow.add(trainHint);
        panel.add(btnRow);

        return panel;
    }

    private JPanel buildCustomFilePanel() {
        JPanel panel = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 4));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(4, 24, 4, 0));

        classifierPathField.setFont(Theme.FONT_SMALL);
        classifierPathField.setToolTipText("Path to a .qza Naive Bayes classifier");
        panel.add(classifierPathField);
        panel.add(browseBtn);

        return panel;
    }

    // ========================================================================
    // Listeners
    // ========================================================================
    private void wireListeners() {
        // Radio button switching
        rbPreTrained.addActionListener(e -> showPanel("pretrained"));
        rbTrainNew.addActionListener(e -> showPanel("train"));
        rbCustomFile.addActionListener(e -> showPanel("custom"));

        // Refresh classifier list
        refreshBtn.addActionListener(e -> scanClassifiers());

        // Amplicon combo → auto-fill primers + length defaults
        ampCombo.addActionListener(e -> {
            String sel = (String) ampCombo.getSelectedItem();
            if (sel != null) {
                for (String[] pd : PRIMER_DEFAULTS) {
                    if (pd[0].equals(sel)) {
                        fwdPrimerField.setText(pd[1]);
                        revPrimerField.setText(pd[2]);
                        break;
                    }
                }
                // Set amplicon-appropriate min/max length defaults
                switch (sel) {
                    case "16S-V4":
                        minLengthSpinner.setValue(100);
                        maxLengthSpinner.setValue(400);
                        break;
                    case "16S-V3V4":
                        minLengthSpinner.setValue(200);
                        maxLengthSpinner.setValue(500);
                        break;
                    case "ITS1": case "ITS2":
                        minLengthSpinner.setValue(100);
                        maxLengthSpinner.setValue(600);
                        break;
                    default:
                        minLengthSpinner.setValue(100);
                        maxLengthSpinner.setValue(400);
                        break;
                }
            }
        });
        // Initialize primers for default selection
        ampCombo.setSelectedIndex(0);

        // Classifier dropdown → enable classify
        classifierDropdown.addActionListener(e -> { updateClassifyState(); refreshCmdPreview(); });

        // Custom file browse
        browseBtn.addActionListener(e -> {
            JFileChooser fc = new JFileChooser();
            fc.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter("QIIME2 Artifact (.qza)", "qza"));
            if (fc.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
                classifierPathField.setText(fc.getSelectedFile().getAbsolutePath());
                updateClassifyState();
            }
        });

        // Rep-seqs browse
        repSeqsBrowseBtn.addActionListener(e -> {
            JFileChooser fc = new JFileChooser();
            fc.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter("QIIME2 Artifact (.qza)", "qza"));
            if (fc.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
                repSeqsField.setText(fc.getSelectedFile().getAbsolutePath());
                updateClassifyState();
            }
        });

        // Custom file text change
        classifierPathField.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
            public void insertUpdate(javax.swing.event.DocumentEvent e)  { updateClassifyState(); refreshCmdPreview(); }
            public void removeUpdate(javax.swing.event.DocumentEvent e)  { updateClassifyState(); refreshCmdPreview(); }
            public void changedUpdate(javax.swing.event.DocumentEvent e) { updateClassifyState(); refreshCmdPreview(); }
        });

        // Rep-seqs text change → preview update
        repSeqsField.getDocument().addDocumentListener(new javax.swing.event.DocumentListener() {
            public void insertUpdate(javax.swing.event.DocumentEvent e)  { refreshCmdPreview(); }
            public void removeUpdate(javax.swing.event.DocumentEvent e)  { refreshCmdPreview(); }
            public void changedUpdate(javax.swing.event.DocumentEvent e) { refreshCmdPreview(); }
        });

        // Confidence / n-jobs / reads-per-batch change → preview update
        confidenceSpinner.addChangeListener(e -> refreshCmdPreview());
        nJobsSpinner.addChangeListener(e -> refreshCmdPreview());
        readsPerBatchSpinner.addChangeListener(e -> refreshCmdPreview());

        // Classify button
        classifyBtn.addActionListener(e -> doClassify());
    }

    private void showPanel(String which) {
        preTrainedPanel.setVisible("pretrained".equals(which));
        trainNewPanel.setVisible("train".equals(which));
        customFilePanel.setVisible("custom".equals(which));
        updateClassifyState();
        revalidate();
        repaint();
    }

    private void refreshCmdPreview() {
        String repSeqs = repSeqsField.getText().trim();
        if (repSeqs.isEmpty()) repSeqs = "<rep-seqs.qza>";
        double confidence = (double) confidenceSpinner.getValue();

        String classifierPath;
        if (rbPreTrained.isSelected()) {
            String sel = classifierDropdown.getSelectedItem() != null
                    ? classifierDropdown.getSelectedItem().toString() : "<classifier.qza>";
            if (sel.startsWith("(")) sel = "<classifier.qza>";
            classifierPath = "~/ezmap2-classifiers/" + sel;
        } else if (rbCustomFile.isSelected()) {
            String p = classifierPathField.getText().trim();
            classifierPath = p.isEmpty() ? "<classifier.qza>" : p;
        } else {
            classifierPath = "<trained-classifier.qza>";
        }

        int nJobs = (int) nJobsSpinner.getValue();
        int readsPerBatch = (int) readsPerBatchSpinner.getValue();

        StringBuilder sb = new StringBuilder();
        sb.append("qiime feature-classifier classify-sklearn \\\n");
        sb.append("  --i-classifier ").append(classifierPath).append(" \\\n");
        sb.append("  --i-reads ").append(repSeqs).append(" \\\n");
        sb.append("  --p-confidence ").append(confidence).append(" \\\n");
        sb.append("  --p-n-jobs ").append(nJobs).append(" \\\n");
        if (readsPerBatch > 0) {
            sb.append("  --p-reads-per-batch ").append(readsPerBatch).append(" \\\n");
        }
        sb.append("  --o-classification taxonomy.qza");
        cmdPreview.setText(sb.toString());
        cmdPreview.setCaretPosition(0);
    }

    private void updateClassifyState() {
        boolean hasClassifier;
        if (rbPreTrained.isSelected()) {
            hasClassifier = classifierDropdown.getSelectedItem() != null
                    && !classifierDropdown.getSelectedItem().toString().startsWith("(");
        } else if (rbCustomFile.isSelected()) {
            String p = classifierPathField.getText().trim();
            hasClassifier = !p.isEmpty() && p.endsWith(".qza");
        } else {
            hasClassifier = false; // must train first
        }
        boolean hasRepSeqs = !repSeqsField.getText().trim().isEmpty();
        classifyBtn.setEnabled(hasClassifier && hasRepSeqs && !isClassifying && !isTraining);
    }

    // ========================================================================
    // Scan for existing classifiers
    // ========================================================================
    @Override
    public void onShown() {
        scanClassifiers();
        // Auto-fill rep-seqs from denoising step
        String repSeqs = wizard.get("rep-seqs.qza");
        if (repSeqs != null && repSeqsField.getText().trim().isEmpty()) {
            repSeqsField.setText(repSeqs);
        }
        updateClassifyState();
        refreshCmdPreview();
    }

    private void scanClassifiers() {
        classifierDropdown.removeAllItems();
        Path clDir = Paths.get(System.getProperty("user.home"), CLASSIFIERS_DIR_NAME);
        if (Files.isDirectory(clDir)) {
            try {
                Files.list(clDir)
                    .filter(p -> p.toString().endsWith("-nb-classifier.qza"))
                    .sorted()
                    .forEach(p -> classifierDropdown.addItem(p.getFileName().toString()));
            } catch (IOException e) {
                console.warn("Could not scan classifiers: " + e.getMessage());
            }
        }
        if (classifierDropdown.getItemCount() == 0) {
            classifierDropdown.addItem("(no classifiers found — train one first)");
            classifierStatus.setText("Train a classifier in Settings or below.");
            classifierStatus.setForeground(Theme.WARNING);
        } else {
            classifierStatus.setText(classifierDropdown.getItemCount() + " classifier(s) available");
            classifierStatus.setForeground(Theme.SUCCESS);
        }
        updateClassifyState();
    }

    // ========================================================================
    // Train classifier
    // ========================================================================
    private void doTrainClassifier() {
        if (isTraining) return;
        isTraining = true;
        trainBtn.setEnabled(false);
        classifyBtn.setEnabled(false);

        String dbSel  = (String) dbCombo.getSelectedItem();
        String ampSel = (String) ampCombo.getSelectedItem();
        String fwd    = fwdPrimerField.getText().trim();
        String rev    = revPrimerField.getText().trim();
        int threads   = (int) threadsSpinner.getValue();
        int minLength = (int) minLengthSpinner.getValue();
        int maxLength = (int) maxLengthSpinner.getValue();

        if (fwd.isEmpty() || rev.isEmpty()) {
            console.err("Forward and reverse primers are required.");
            isTraining = false;
            trainBtn.setEnabled(true);
            return;
        }

        // Map display name to script arg
        String dbArg;
        if (dbSel.toLowerCase().contains("silva"))       dbArg = "silva";
        else if (dbSel.toLowerCase().contains("green"))  dbArg = "greengenes2";
        else if (dbSel.toLowerCase().contains("unite"))  dbArg = "unite";
        else dbArg = "silva";

        console.clear();
        console.info("Training classifier: " + ampSel + " / " + dbArg);
        console.info("Primers: " + fwd + " / " + rev);
        console.info("This will take 20–60 minutes. Please wait…");

        new Thread(() -> {
            try {
                String scriptDir = findScriptsDir();
                String cmd = "bash \"" + scriptDir + "/train_classifier.sh\""
                        + " --database " + dbArg
                        + " --amplicon " + ampSel
                        + " --fwd-primer " + fwd
                        + " --rev-primer " + rev
                        + " --min-length " + minLength
                        + " --max-length " + maxLength
                        + " --threads " + threads;

                runShellStreaming(cmd);
                console.ok("Classifier training complete!");

                SwingUtilities.invokeLater(() -> {
                    scanClassifiers();
                    isTraining = false;
                    trainBtn.setEnabled(true);
                    updateClassifyState();
                });
            } catch (Exception e) {
                console.err("Training failed: " + e.getMessage());
                SwingUtilities.invokeLater(() -> {
                    isTraining = false;
                    trainBtn.setEnabled(true);
                });
            }
        }).start();
    }

    // ========================================================================
    // Classify
    // ========================================================================
    private void doClassify() {
        if (isClassifying) return;
        isClassifying = true;
        classifyBtn.setEnabled(false);

        // Resolve classifier path
        String classifierPath;
        if (rbPreTrained.isSelected()) {
            String sel = (String) classifierDropdown.getSelectedItem();
            classifierPath = Paths.get(System.getProperty("user.home"), CLASSIFIERS_DIR_NAME, sel).toString();
        } else if (rbCustomFile.isSelected()) {
            classifierPath = classifierPathField.getText().trim();
        } else {
            console.err("No classifier selected. Train one first or switch to pre-trained.");
            isClassifying = false;
            classifyBtn.setEnabled(true);
            return;
        }

        String repSeqs    = repSeqsField.getText().trim();
        double confidence = (double) confidenceSpinner.getValue();
        int nJobs         = (int) nJobsSpinner.getValue();
        int readsPerBatch = (int) readsPerBatchSpinner.getValue();

        if (!new File(classifierPath).exists() && !classifierPath.startsWith("/mnt/")) {
            // On Windows+WSL the path might be a WSL path
            console.warn("Classifier file may not exist locally; will try in WSL context.");
        }

        console.info("Running taxonomy classification…");
        console.info("Classifier: " + classifierPath);
        console.info("Rep-seqs:   " + repSeqs);
        console.info("Confidence: " + confidence);
        console.info("Jobs: " + nJobs + " | Reads/batch: " + (readsPerBatch == 0 ? "auto" : readsPerBatch));
        console.info("This may take 3–10 minutes depending on dataset size…");

        new Thread(() -> {
            try {
                // Output goes next to rep-seqs
                File repFile = new File(repSeqs);
                String outDir = repFile.getParent() != null ? repFile.getParent() : ".";
                String taxOut = outDir + "/taxonomy.qza";

                String cmd = "qiime feature-classifier classify-sklearn"
                        + " --i-classifier \"" + classifierPath + "\""
                        + " --i-reads \"" + repSeqs + "\""
                        + " --p-confidence " + confidence
                        + " --p-n-jobs " + nJobs
                        + (readsPerBatch > 0 ? " --p-reads-per-batch " + readsPerBatch : "")
                        + " --o-classification \"" + taxOut + "\"";

                runShellStreaming(cmd);
                console.ok("Taxonomy classification complete!");
                console.ok("Output: " + taxOut);

                // Store for downstream steps
                wizard.put("taxonomy.qza", taxOut);
                wizard.put("output.dir", outDir);

                // Also export to TSV
                String tsvDir = outDir + "/taxonomy-export";
                String exportCmd = "qiime tools export --input-path \"" + taxOut
                        + "\" --output-path \"" + tsvDir + "\"";
                runShellStreaming(exportCmd);
                console.ok("Taxonomy TSV exported to: " + tsvDir + "/taxonomy.tsv");

                SwingUtilities.invokeLater(() -> {
                    isClassifying = false;
                    classifyBtn.setEnabled(true);
                    updateClassifyState();
                    stepComplete = true;
                    notifyStepCompletion();
                });
            } catch (Exception e) {
                console.err("Classification failed: " + e.getMessage());
                SwingUtilities.invokeLater(() -> {
                    isClassifying = false;
                    classifyBtn.setEnabled(true);
                });
            }
        }).start();
    }

    // ========================================================================
    // Shell helpers
    // ========================================================================
    /** Run a QIIME2 command using the shared QiimeCommand executor. */
    private void runShellStreaming(String cmd) throws Exception {
        // Use QiimeCommand.runBash which handles conda activation properly
        int rc = QiimeCommand.runBash(cmd, null, console);
        if (rc != 0) {
            throw new RuntimeException("Command exited with code " + rc);
        }
    }

    private String findScriptsDir() {
        String[] candidates = {
            "scripts",
            "EzMAP2_redesign/scripts",
            System.getProperty("user.dir") + "/scripts",
        };
        for (String c : candidates) {
            if (new File(c, "train_classifier.sh").exists()) return c;
        }
        return "scripts";
    }

    private static JLabel fieldLabel(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY_BOLD);
        l.setForeground(Theme.INK_2);
        return l;
    }

    private JLabel tipLabel(String text, String tooltip) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_BODY_BOLD);
        l.setForeground(Theme.INK_2);
        l.setToolTipText(tooltip);
        l.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        return l;
    }
}
