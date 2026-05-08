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
import java.util.Arrays;

/**
 * Landing page — first screen the user sees.
 * Two paths: "Full Analysis" (upstream + downstream) or "Downstream Only".
 */
public class WelcomePage extends BasePage {

    private final WizardController wizard;
    private String selectedPath = null;   // "full" or "downstream"
    private JPanel fullCard, downCard;
    private final PrimaryButton continueBtn = new PrimaryButton("Get Started  \u2192");

    public WelcomePage(WizardController wizard) {
        super("Welcome to EzMAP v2",
              "Choose how you'd like to proceed. Run the full pipeline from raw FASTQ reads, " +
              "or jump straight to downstream analysis if you already have processed data.");
        this.wizard = wizard;

        // ---- Two-card row ----
        JPanel row = new JPanel(new GridLayout(1, 2, 20, 0));
        row.setOpaque(false);
        row.setAlignmentX(LEFT_ALIGNMENT);

        fullCard = buildCard(
                "Full Analysis",
                "\uD83D\uDD2C",   // microscope emoji
                "Run the complete QIIME2 pipeline from raw FASTQ reads to results — " +
                "includes environment setup, database configuration, quality control, " +
                "denoising, taxonomy, and phylogeny. Produces a ready-to-analyze bundle " +
                "for downstream visualization and statistics.",
                new String[]{
                        "Environment & database setup wizard",
                        "Easy Mode (one-click) or Expert Mode (full control)",
                        "FASTQ \u2192 BIOM + taxonomy + phylogenetic tree",
                        "Seamless handoff to downstream analysis"
                },
                Theme.PRIMARY,
                "full"
        );
        row.add(fullCard);

        downCard = buildCard(
                "Downstream Only",
                "\uD83D\uDCCA",   // bar chart emoji
                "Already have a BIOM table, taxonomy, and phylogenetic tree from a previous " +
                "EzMAP v2 run or another tool? Skip setup and pipeline — go straight to " +
                "interactive visualization, diversity analysis, and statistical testing " +
                "in the EzMAP v2 Shiny module.",
                new String[]{
                        "Upload BIOM, metadata & tree files",
                        "No QIIME2 or conda required",
                        "Interactive diversity & taxonomy plots",
                        "Differential abundance & statistical tests"
                },
                Theme.ACCENT,
                "downstream"
        );
        row.add(downCard);

        add(row);

        // ---- Tip banner ----
        JLabel tip = new JLabel(
            "<html><body style='width:680px; font-size:11px; color:#64748B'>"
            + "<b>Tip:</b> If you've already run the upstream pipeline and want to revisit results "
            + "or re-launch downstream analysis, choose <b>Full Analysis</b> — you can skip to results "
            + "from the mode selection screen."
            + "</body></html>");
        tip.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                BorderFactory.createEmptyBorder(10, 14, 10, 14)));
        tip.setOpaque(true);
        tip.setBackground(Theme.SURFACE_2);
        add(tip);

        // ---- Bottom navigation ----
        JPanel navRow = new JPanel(new BorderLayout());
        navRow.setOpaque(false);
        navRow.setBorder(new EmptyBorder(12, 0, 0, 0));

        continueBtn.setEnabled(false);
        continueBtn.addActionListener(e -> applySelection());

        JPanel rightBtns = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        rightBtns.setOpaque(false);
        rightBtns.add(continueBtn);
        navRow.add(rightBtns, BorderLayout.EAST);

        add(navRow);
    }

    private void selectPath(String path) {
        selectedPath = path;
        continueBtn.setEnabled(true);
        updateCardBorder(fullCard, "full".equals(path), Theme.PRIMARY);
        updateCardBorder(downCard, "downstream".equals(path), Theme.ACCENT);
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

    private void applySelection() {
        if (selectedPath == null) return;

        if ("full".equals(selectedPath)) {
            // Full analysis: welcome → env → db → mode (then easy/expert extends it)
            wizard.setActiveFlow(
                    Arrays.asList("welcome", "env", "db", "mode"),
                    Arrays.asList("Welcome", "Environment Setup",
                                  "Database & Classifiers", "Choose Mode"));
            wizard.next();
        } else {
            // Downstream only: welcome → downstream-upload (2-step, minimal)
            wizard.setActiveFlow(
                    Arrays.asList("welcome", "downstream-upload"),
                    Arrays.asList("Welcome", "Downstream Analysis"));
            wizard.next();
        }
    }

    private JPanel buildCard(String title, String icon, String desc, String[] bullets,
                             Color accent, String pathId) {
        JPanel card = new JPanel();
        card.setLayout(new BoxLayout(card, BoxLayout.Y_AXIS));
        card.setBackground(Theme.SURFACE);
        card.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                new EmptyBorder(24, 24, 24, 24)));

        JLabel ic = new JLabel(icon);
        ic.setFont(new Font(Font.SANS_SERIF, Font.PLAIN, 36));
        ic.setAlignmentX(LEFT_ALIGNMENT);
        card.add(ic);
        card.add(Box.createVerticalStrut(8));

        JLabel t = new JLabel(title);
        t.setFont(Theme.FONT_PAGE_TITLE.deriveFont(20f));
        t.setForeground(Theme.INK_1);
        t.setAlignmentX(LEFT_ALIGNMENT);
        card.add(t);
        card.add(Box.createVerticalStrut(6));

        JLabel d = new JLabel("<html><body style='width:280px'>" + desc + "</body></html>");
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

        card.addMouseListener(new MouseAdapter() {
            @Override public void mouseClicked(MouseEvent e)  { selectPath(pathId); }
            @Override public void mouseEntered(MouseEvent e) {
                if (!pathId.equals(selectedPath)) {
                    card.setBorder(BorderFactory.createCompoundBorder(
                            BorderFactory.createLineBorder(accent, 2, true),
                            new EmptyBorder(23, 23, 23, 23)));
                }
            }
            @Override public void mouseExited(MouseEvent e) {
                if (!pathId.equals(selectedPath)) {
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
