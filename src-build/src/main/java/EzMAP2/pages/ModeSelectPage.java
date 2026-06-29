package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.GhostButton;
import EzMAP2.ui.PrimaryButton;
import EzMAP2.ui.Theme;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.io.File;
import java.util.Arrays;

/**
 * Two-card chooser: Easy Mode (one-click pipeline) vs Expert Mode (full wizard).
 * Click a card to select it (highlighted border), then use Back/Continue at the bottom.
 */
public class ModeSelectPage extends BasePage {

    private final WizardController wizard;
    private String selectedMode = null;   // "easy", "expert", or "resume"
    private JPanel easyCard, expertCard, resumeCard;
    private final PrimaryButton continueBtn = new PrimaryButton("Continue  \u2192");
    // Shortcut: jump straight to the final Expert step (Phylogeny & Export)
    // when rep-seqs / table / taxonomy already exist from a previous run.
    private final GhostButton skipBtn =
            new GhostButton("Skip to final step (Phylogeny & Export)  \u2192");

    public ModeSelectPage(WizardController wizard) {
        super("Choose Your Analysis Mode",
              "Easy Mode runs the full QIIME2 pipeline with validated defaults — pick files, press Run, " +
              "download your bundle. Expert Mode steps through every QIIME2 stage with full parameter control.");
        this.wizard = wizard;

        JPanel row = new JPanel(new GridLayout(1, 3, 16, 0));
        row.setOpaque(false);
        row.setAlignmentX(LEFT_ALIGNMENT);

        easyCard = buildCard(
                "Easy Mode",
                "\u26A1",
                "One-click upstream pipeline. Pick your FASTQ folder, metadata, and amplicon region — " +
                "EzMAP v2.0 runs import, Cutadapt, DADA2, phylogeny, and taxonomy with validated defaults, " +
                "then builds a BIOM bundle ready for the Shiny downstream module.",
                new String[]{
                        "7-step pipeline: FASTQ \u2192 BIOM + taxonomy",
                        "Quality-driven DADA2 trim lengths",
                        "SILVA 138.2 / UNITE 10 classifier",
                        "Every parameter recorded to parameters.json"
                },
                Theme.PRIMARY,
                "easy"
        );
        row.add(easyCard);

        expertCard = buildCard(
                "Expert Mode",
                "\u2699",
                "Full wizard. Configure every QIIME2 step manually — manifest, import, Cutadapt, " +
                "denoising, taxonomy, and classifier training — with complete control over parameters.",
                new String[]{
                        "Per-step parameter control",
                        "Train custom classifier or use pre-trained",
                        "Inspect intermediate .qza / .qzv",
                        "Custom primers, trim lengths, confidence"
                },
                Theme.ACCENT,
                "expert"
        );
        row.add(expertCard);

        resumeCard = buildCard(
                "Resume Downstream",
                "\uD83D\uDCC2",   // open file folder
                "Already completed the upstream pipeline? Select your output folder to view " +
                "denoising stats, taxonomy summary, and launch downstream analysis — no need to " +
                "re-run the pipeline.",
                new String[]{
                        "Load existing pipeline results",
                        "View denoising QC & taxonomy snapshot",
                        "Launch Shiny with auto-loaded data",
                        "Skip re-running the pipeline"
                },
                new Color(0x7C, 0x3A, 0xED),  // purple accent
                "resume"
        );
        row.add(resumeCard);

        add(row);

        // --- Bottom navigation: Back + Continue ---
        JPanel navRow = new JPanel(new BorderLayout());
        navRow.setOpaque(false);
        navRow.setBorder(new EmptyBorder(12, 0, 0, 0));

        GhostButton backBtn = new GhostButton("\u2190  Back");
        backBtn.addActionListener(e -> wizard.previous());

        continueBtn.setEnabled(false);  // disabled until a card is selected
        continueBtn.addActionListener(e -> applySelectionAndContinue());

        // Shown only once Expert Mode is selected. Builds the full Expert flow
        // (so the sidebar still lists every step) but jumps directly to the
        // last page, where the user browses to their existing rep-seqs / table
        // / taxonomy and re-runs just the Phylogeny & Export step.
        skipBtn.setVisible(false);
        skipBtn.addActionListener(e -> {
            applyExpertFlow();
            wizard.showId("downstream");
        });
        JPanel leftBtns = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        leftBtns.setOpaque(false);
        leftBtns.add(skipBtn);
        navRow.add(leftBtns, BorderLayout.WEST);

        JPanel rightBtns = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        rightBtns.setOpaque(false);
        rightBtns.add(backBtn);
        rightBtns.add(continueBtn);
        navRow.add(rightBtns, BorderLayout.EAST);

        add(navRow);
    }

    private void selectMode(String mode) {
        selectedMode = mode;
        continueBtn.setEnabled(true);
        skipBtn.setVisible("expert".equals(mode));   // only meaningful for Expert
        if (skipBtn.getParent() != null) {
            skipBtn.getParent().revalidate();
            skipBtn.getParent().repaint();
        }
        // Update card borders to show selection
        updateCardBorder(easyCard,   "easy".equals(mode),   Theme.PRIMARY);
        updateCardBorder(expertCard,  "expert".equals(mode),  Theme.ACCENT);
        updateCardBorder(resumeCard,  "resume".equals(mode),  new Color(0x7C, 0x3A, 0xED));
    }

    private void updateCardBorder(JPanel card, boolean selected, Color accent) {
        if (selected) {
            card.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(accent, 2, true),
                    new EmptyBorder(23, 23, 23, 23)));
        } else {
            card.setBorder(BorderFactory.createCompoundBorder(
                    BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                    new EmptyBorder(24, 24, 24, 24)));
        }
    }

    private void applySelectionAndContinue() {
        if (selectedMode == null) return;

        java.util.List<String> flow = wizard.getActiveFlow();
        boolean hasWelcome = flow.contains("welcome");
        boolean hasEnv = flow.contains("env");
        boolean hasDb  = flow.contains("db");

        // Build prefix: pages that came before mode selection
        java.util.List<String> prefixIds    = new java.util.ArrayList<>();
        java.util.List<String> prefixLabels = new java.util.ArrayList<>();
        if (hasWelcome) { prefixIds.add("welcome"); prefixLabels.add("Welcome"); }
        if (hasEnv)     { prefixIds.add("env");     prefixLabels.add("Environment Setup"); }
        if (hasDb)      { prefixIds.add("db");      prefixLabels.add("Database & Classifiers"); }
        prefixIds.add("mode"); prefixLabels.add("Choose Mode");

        if ("easy".equals(selectedMode)) {
            java.util.List<String> ids    = new java.util.ArrayList<>(prefixIds);
            java.util.List<String> labels = new java.util.ArrayList<>(prefixLabels);
            ids.add("easy");               labels.add("Easy Mode Pipeline");
            ids.add("results-summary");    labels.add("Results & Summary");
            wizard.setActiveFlow(ids, labels);

        } else if ("expert".equals(selectedMode)) {
            applyExpertFlow();

        } else if ("resume".equals(selectedMode)) {
            // Navigate to results-summary — folder picker is on that page
            java.util.List<String> ids    = new java.util.ArrayList<>(prefixIds);
            java.util.List<String> labels = new java.util.ArrayList<>(prefixLabels);
            ids.add("results-summary");    labels.add("Results & Summary");
            wizard.setActiveFlow(ids, labels);

            // Tell ResultsSummaryPage to show the folder picker (resume flow)
            BasePage rsp = wizard.getPages().get("results-summary");
            if (rsp instanceof ResultsSummaryPage) {
                ((ResultsSummaryPage) rsp).showFolderPicker();
            }
        }

        // Advance past the mode page
        wizard.next();
    }

    /**
     * Build the full Expert Mode flow (prefix pages + all seven Expert steps)
     * and make it the active flow. Used both by the normal Continue action and
     * by the "Skip to final step" shortcut.
     */
    private void applyExpertFlow() {
        java.util.List<String> flow = wizard.getActiveFlow();
        java.util.List<String> ids    = new java.util.ArrayList<>();
        java.util.List<String> labels = new java.util.ArrayList<>();
        if (flow.contains("welcome")) { ids.add("welcome"); labels.add("Welcome"); }
        if (flow.contains("env"))     { ids.add("env");     labels.add("Environment Setup"); }
        if (flow.contains("db"))      { ids.add("db");      labels.add("Database & Classifiers"); }
        ids.add("mode"); labels.add("Choose Mode");
        ids.addAll(Arrays.asList("manifest", "import", "cutadapt", "quality", "denoise", "taxonomy", "downstream"));
        labels.addAll(Arrays.asList("Validate Inputs", "Import Sequences", "Primer Removal",
                "Quality Assessment", "Denoising", "Taxonomy", "Phylogeny & Export"));
        wizard.setActiveFlow(ids, labels);
    }

    private JPanel buildCard(String title, String icon, String desc, String[] bullets,
                             Color accent, String modeId) {
        JPanel card = new JPanel();
        card.setLayout(new BoxLayout(card, BoxLayout.Y_AXIS));
        card.setBackground(Theme.SURFACE);
        card.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                new EmptyBorder(24, 24, 24, 24)));

        JLabel ic = new JLabel(icon);
        ic.setFont(new Font(Theme.FONT_PAGE_TITLE.getFamily(), Font.BOLD, 36));
        ic.setForeground(accent);
        ic.setAlignmentX(LEFT_ALIGNMENT);
        card.add(ic);
        card.add(Box.createVerticalStrut(8));

        JLabel t = new JLabel(title);
        t.setFont(Theme.FONT_PAGE_TITLE.deriveFont(20f));
        t.setForeground(Theme.INK_1);
        t.setAlignmentX(LEFT_ALIGNMENT);
        card.add(t);
        card.add(Box.createVerticalStrut(6));

        JLabel d = new JLabel("<html><body style='width:220px'>" + desc + "</body></html>");
        d.setFont(Theme.FONT_BODY);
        d.setForeground(Theme.INK_3);
        d.setAlignmentX(LEFT_ALIGNMENT);
        card.add(d);
        card.add(Box.createVerticalStrut(14));

        for (String b : bullets) {
            JLabel bl = new JLabel("\u2713  " + b);
            bl.setFont(Theme.FONT_SMALL);
            bl.setForeground(Theme.INK_2);
            bl.setAlignmentX(LEFT_ALIGNMENT);
            card.add(bl);
            card.add(Box.createVerticalStrut(4));
        }

        // Click anywhere on the card to select this mode
        card.addMouseListener(new MouseAdapter() {
            @Override public void mouseClicked(MouseEvent e) {
                selectMode(modeId);
            }
            @Override public void mouseEntered(MouseEvent e) {
                if (!modeId.equals(selectedMode)) {
                    card.setBorder(BorderFactory.createCompoundBorder(
                            BorderFactory.createLineBorder(accent, 2, true),
                            new EmptyBorder(23, 23, 23, 23)));
                }
            }
            @Override public void mouseExited(MouseEvent e) {
                if (!modeId.equals(selectedMode)) {
                    card.setBorder(BorderFactory.createCompoundBorder(
                            BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                            new EmptyBorder(24, 24, 24, 24)));
                }
            }
        });
        card.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        return card;
    }
}
