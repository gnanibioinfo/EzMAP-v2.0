package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.File;

/**
 * Expert Mode — Step 3: Sequence quality visualization.
 *
 * Runs: qiime demux summarize
 *   --i-data <demux.qza>
 *   --o-visualization <output-dir>/demux-summary.qzv
 *
 * The .qzv file can be opened at https://view.qiime2.org or locally.
 * Helps users decide trim/truncate parameters for denoising.
 */
public class SequenceQualityPage extends BasePage {

    private final WizardController wizard;
    private boolean stepComplete = false;

    @Override public boolean isStepComplete() { return stepComplete; }

    private final DirectoryPicker demuxPicker;
    private final PrimaryButton runBtn = new PrimaryButton("Run Quality Summary  \u2192");
    private final OutlineButton openVizBtn = new OutlineButton("Open Visualization (.qzv)");
    private final OutlineButton stopBtn = new OutlineButton("Stop");
    private final JLabel statusLabel = new JLabel(" ");
    private final LogConsole console = new LogConsole();

    private final JTextArea cmdPreview = new JTextArea(2, 60);
    private String qzvPath;
    private volatile QiimeCommand runningCmd;

    public SequenceQualityPage(WizardController wizard) {
        super("Expert Mode — Step 3: Quality Assessment",
              "Generate quality summaries from your imported reads so you can choose " +
              "trimming and truncation parameters for denoising.");
        this.wizard = wizard;

        // ---- Card 1: Input ----
        Card inputCard = new Card("1 \u00B7 Demultiplexed Artifact");
        JLabel demuxCaption = caption("Demux .qza file (from the Import step):");
        demuxCaption.setToolTipText("The demultiplexed sequences artifact (.qza) from the Import or Cutadapt step.");
        inputCard.row(demuxCaption);
        demuxPicker = new DirectoryPicker("Select demux .qza file",
                f -> runBtn.setEnabled(f != null && f.exists()), true);
        inputCard.row(demuxPicker);
        add(inputCard);

        // ---- Card 2: Run ----
        Card runCard = new Card("2 \u00B7 Run Demux Summarize");
        runCard.row(new InfoBanner(InfoBanner.Kind.INFO, "What this does",
                "Generates a quality plot (.qzv) showing per-base quality scores across all samples. " +
                "Use this to decide where to trim (remove low-quality bases at the start) and " +
                "truncate (cut reads at a position where quality drops) in the next step."))
               .gap(8);

        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        btnRow.setOpaque(false);
        btnRow.add(runBtn);
        btnRow.add(openVizBtn);
        btnRow.add(stopBtn);
        statusLabel.setFont(Theme.FONT_BODY);
        btnRow.add(statusLabel);
        runCard.row(btnRow).gap(8);

        console.setPreferredSize(new Dimension(0, 180));
        runCard.row(console);
        add(runCard);

        // ---- Card 3: Command Preview ----
        Card previewCard = new Card("3 \u00B7 QIIME2 Command Preview");
        cmdPreview.setEditable(false);
        cmdPreview.setFont(Theme.FONT_MONO);
        cmdPreview.setBackground(new Color(0x1E, 0x29, 0x3B));
        cmdPreview.setForeground(new Color(0xA5, 0xD6, 0xFF));
        cmdPreview.setBorder(BorderFactory.createEmptyBorder(10, 12, 10, 12));
        cmdPreview.setLineWrap(true);
        cmdPreview.setWrapStyleWord(true);
        JScrollPane previewScroll = new JScrollPane(cmdPreview);
        previewScroll.setPreferredSize(new Dimension(0, 60));
        previewScroll.setBorder(BorderFactory.createLineBorder(new Color(0x33, 0x44, 0x55)));
        previewCard.row(previewScroll);
        add(previewCard);

        // ---- Card 4: Next step hint ----
        Card hintCard = new Card("4 \u00B7 Next Step");
        hintCard.row(new InfoBanner(InfoBanner.Kind.INFO, "After viewing the quality plot",
                "Once you've examined the quality scores in the .qzv viewer, proceed to the " +
                "Denoising step. EzMAP v2 will suggest trim/truncate values based on your amplicon " +
                "region \u2014 you can adjust them after reviewing the quality plot. " +
                "A full quality interpretation guide is provided on the Denoising page."));
        add(hintCard);

        // ---- Wiring ----
        runBtn.setEnabled(false);
        openVizBtn.setEnabled(false);
        stopBtn.setEnabled(false);
        runBtn.addActionListener(e -> executeQualitySummary());
        openVizBtn.addActionListener(e -> openQzv());
        stopBtn.addActionListener(e -> {
            if (runningCmd != null) runningCmd.cancel();
        });
    }

    @Override
    public void onShown() {
        // Auto-fill from wizard properties
        String demuxQza = wizard.get("demux.qza");
        if (demuxQza != null && demuxPicker.isEmpty()) {
            demuxPicker.setPath(demuxQza);
        }
        runBtn.setEnabled(!demuxPicker.isEmpty());
        refreshCmdPreview();
    }

    private void refreshCmdPreview() {
        String demux = demuxPicker.isEmpty() ? "<demux.qza>" : demuxPicker.getPath();
        String out = wizard.get("output.dir", ".") + File.separator + "demux-summary.qzv";
        cmdPreview.setText("qiime demux summarize \\\n  --i-data " + demux
                + " \\\n  --o-visualization " + out);
        cmdPreview.setCaretPosition(0);
    }

    private void executeQualitySummary() {
        runBtn.setEnabled(false);
        stopBtn.setEnabled(true);
        openVizBtn.setEnabled(false);
        statusLabel.setText("<html><span style='color:#64748B'>Running\u2026</span></html>");
        console.clear();

        final String demuxFile = demuxPicker.getPath();
        final String outDir = wizard.get("output.dir",
                new File(demuxFile).getParent());

        new Thread(() -> {
            try {
                String vizFile = outDir + File.separator + "demux-summary.qzv";

                QiimeCommand cmd = new QiimeCommand("qiime demux summarize")
                        .arg("--i-data", demuxFile)
                        .arg("--o-visualization", vizFile)
                        .workDir(outDir);

                runningCmd = cmd;
                int exit = cmd.run(console);

                if (exit == 0) {
                    qzvPath = vizFile;
                    wizard.put("demux.qzv", vizFile);

                    SwingUtilities.invokeLater(() -> {
                        statusLabel.setText("<html><span style='color:#16A34A'>\u2713 Summary ready</span></html>");
                        openVizBtn.setEnabled(true);
                        console.ok("Visualization: " + vizFile);
                        console.ok("Open the .qzv file to inspect quality, then proceed to Denoising.");
                        stepComplete = true;
                        notifyStepCompletion();
                    });
                } else {
                    SwingUtilities.invokeLater(() ->
                            statusLabel.setText("<html><span style='color:#DC2626'>\u2718 Failed</span></html>"));
                }

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

    private void openQzv() {
        if (qzvPath == null) return;
        // .qzv files can only be viewed at view.qiime2.org — open browser directly
        console.info("Opening QIIME2 Viewer \u2014 drag and drop your .qzv file to view quality plots.");
        console.info("File location: " + qzvPath);
        try {
            Desktop.getDesktop().browse(java.net.URI.create("https://view.qiime2.org"));
        } catch (Exception ex) {
            console.warn("Could not open browser. Please visit https://view.qiime2.org manually.");
            console.info("Then upload: " + qzvPath);
        }
    }

    private JLabel caption(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        return l;
    }

}
