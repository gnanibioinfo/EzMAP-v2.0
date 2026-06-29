package EzMAP2.pages;

import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.net.URI;

/**
 * About dialog — opens from the top-bar "About" button.
 *
 * Provides:
 *   - What EzMAP v2.0 is
 *   - Step-by-step installation & usage instructions
 *     (Java, QIIME 2, R + downstream packages, themetagenomics, FUNGuild, SpiecEasi)
 *   - Developer / contact information
 */
public class AboutPage extends JDialog {

    private static final Color CODE_BG = new Color(0xF1, 0xF5, 0xF9);
    private static final Color LINK    = new Color(0x1D, 0x4E, 0xD8);

    public AboutPage(Frame owner) {
        super(owner, "About — EzMAP v2.0", true);
        setSize(760, 720);
        setMinimumSize(new Dimension(640, 500));
        setLocationRelativeTo(owner);

        JPanel root = new JPanel(new BorderLayout());
        root.setBackground(Theme.BACKGROUND);

        // ---- Header ----
        JPanel header = new JPanel(new BorderLayout());
        header.setBackground(Theme.SIDEBAR_TOP);
        header.setBorder(new EmptyBorder(14, 20, 14, 20));
        JLabel title = new JLabel("About EzMAP v2.0");
        title.setFont(Theme.FONT_PAGE_TITLE.deriveFont(18f));
        title.setForeground(Color.WHITE);
        header.add(title, BorderLayout.WEST);
        JLabel ver = new JLabel("Easy Microbiome Analysis Pipeline");
        ver.setFont(Theme.FONT_SMALL);
        ver.setForeground(new Color(210, 220, 220));
        header.add(ver, BorderLayout.EAST);
        root.add(header, BorderLayout.NORTH);

        // ---- Tabs ----
        JTabbedPane tabs = new JTabbedPane(JTabbedPane.TOP);
        tabs.setFont(Theme.FONT_BODY);
        tabs.addTab("Installation & Usage", scroll(buildUsageTab()));
        tabs.addTab("Developers & Contact", scroll(buildDevelopersTab()));
        root.add(tabs, BorderLayout.CENTER);

        // ---- Footer ----
        JPanel footer = new JPanel(new FlowLayout(FlowLayout.RIGHT, 10, 0));
        footer.setBackground(Theme.SURFACE);
        footer.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(1, 0, 0, 0, Theme.BORDER),
                new EmptyBorder(10, 18, 10, 18)));
        PrimaryButton closeBtn = new PrimaryButton("Close");
        closeBtn.addActionListener(e -> dispose());
        footer.add(closeBtn);
        root.add(footer, BorderLayout.SOUTH);

        setContentPane(root);
    }

    // ====================================================================
    //  Tab 1 — Installation & Usage
    // ====================================================================
    private JPanel buildUsageTab() {
        JPanel p = column();

        p.add(sectionTitle("What is EzMAP v2.0?"));
        p.add(para("EzMAP v2.0 (Easy Microbiome Analysis Pipeline) is a graphical front-end for QIIME 2 "
                + "amplicon analysis. It runs the full upstream pipeline (import → primer removal → "
                + "denoising → taxonomy → phylogeny) and hands the results to an R Shiny module for "
                + "downstream diversity, taxonomy, and network analysis."));

        p.add(sectionTitle("1. Java (required to run EzMAP v2.0)"));
        p.add(para("EzMAP v2.0 is a Java desktop application. Install Java 11 or newer (a JDK is recommended)."));
        p.add(bullet("Download Eclipse Temurin (Adoptium):"));
        p.add(link("https://adoptium.net", "https://adoptium.net"));
        p.add(code("# verify the installation\njava -version"));

        p.add(sectionTitle("2. QIIME 2 environment (upstream pipeline)"));
        p.add(para("The pipeline runs QIIME 2 inside a conda environment named \"EzMAP2-qiime2\"."));
        p.add(bullet("Windows: enable WSL2 + Ubuntu, then let EzMAP set up the environment."));
        p.add(code("# Windows (PowerShell, one time)\nwsl --install"));
        p.add(bullet("All platforms: open the \"Environment Setup\" page in EzMAP and run the installer, "
                + "or run the bundled install.sh, which installs Miniconda (if needed) and creates the "
                + "EzMAP2-qiime2 environment."));

        p.add(sectionTitle("3. R + downstream packages (Shiny module)"));
        p.add(para("The downstream analysis dashboard needs R 4.2 or newer."));
        p.add(bullet("Install R (and optionally RStudio):"));
        p.add(link("https://cran.r-project.org", "https://cran.r-project.org"));
        p.add(bullet("Install the required R packages:"));
        p.add(code("install.packages(c(\"shiny\", \"ggplot2\", \"vegan\",\n"
                + "                   \"remotes\", \"BiocManager\"))\n"
                + "BiocManager::install(c(\"phyloseq\", \"DESeq2\", \"microbiome\"))"));

        p.add(sectionTitle("4. Tax4Fun2 / themetagenomics (functional prediction)"));
        p.add(para("The Tax4Fun2 panel predicts KEGG functional profiles from 16S taxonomy using the "
                + "themetagenomics R package. Install it in R from GitHub (it compiles from source)."));
        p.add(code("install.packages(\"remotes\")\n"
                + "remotes::install_github(\"EESI/themetagenomics\")"));
        p.add(bullet("Windows needs Rtools; macOS needs Xcode tools (run \"xcode-select --install\")."));
        p.add(bullet("GitHub:"));
        p.add(link("https://github.com/EESI/themetagenomics", "https://github.com/EESI/themetagenomics"));

        p.add(sectionTitle("5. FUNGuild (functional guilds for fungal/ITS data)"));
        p.add(para("FUNGuild assigns functional guild information to OTUs/ASVs. It is a small Python "
                + "script that queries the FUNGuild database (needs Python and the 'requests' package)."));
        p.add(code("git clone https://github.com/UMNFuN/FUNGuild\n"
                + "pip install requests\n"
                + "python FUNGuild/Guilds_v1.1.py -h"));
        p.add(bullet("GitHub:"));
        p.add(link("https://github.com/UMNFuN/FUNGuild", "https://github.com/UMNFuN/FUNGuild"));

        p.add(sectionTitle("6. SpiecEasi (microbial co-occurrence networks)"));
        p.add(para("SpiecEasi estimates microbial association networks from compositional abundance data. "
                + "Install it in R from GitHub (it compiles from source)."));
        p.add(code("install.packages(\"remotes\")\n"
                + "remotes::install_github(\"zdk123/SpiecEasi\")"));
        p.add(bullet("Windows needs Rtools; macOS needs gfortran (run \"xcode-select --install\")."));
        p.add(bullet("GitHub:"));
        p.add(link("https://github.com/zdk123/SpiecEasi", "https://github.com/zdk123/SpiecEasi"));

        p.add(note("First time? Use the bundled example data in Easy Mode to verify your whole setup "
                + "end-to-end before running your own samples."));
        return p;
    }

    // ====================================================================
    //  Tab 2 — Developers & Contact
    // ====================================================================
    private JPanel buildDevelopersTab() {
        JPanel p = column();

        p.add(sectionTitle("Developers"));
        p.add(devName("Gnanendra Shanmugam"));
        p.add(devName("Junhyun Jeon"));
        p.add(Box.createVerticalStrut(8));

        p.add(sectionTitle("Affiliation"));
        p.add(para("Department of Biotechnology,\nYeungnam University,\nGyeongsan, South Korea"));

        p.add(sectionTitle("Contact"));
        p.add(mailto("gnani.science@gmail.com"));
        p.add(mailto("jjeon@yu.ac.kr"));

        p.add(Box.createVerticalStrut(14));
        p.add(note("EzMAP v2.0 — Easy Microbiome Analysis Pipeline. "
                + "Developed for reproducible microbiome research."));
        return p;
    }

    // ====================================================================
    //  Helpers
    // ====================================================================
    private JPanel column() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setOpaque(false);
        panel.setBorder(new EmptyBorder(14, 18, 18, 18));
        return panel;
    }

    private JScrollPane scroll(JComponent inner) {
        JScrollPane sp = new JScrollPane(inner);
        sp.setBorder(BorderFactory.createEmptyBorder());
        sp.getVerticalScrollBar().setUnitIncrement(14);
        return sp;
    }

    private JLabel sectionTitle(String text) {
        JLabel l = new JLabel(text);
        l.setFont(Theme.FONT_PAGE_TITLE.deriveFont(15f));
        l.setForeground(Theme.PRIMARY_DARK);
        l.setBorder(new EmptyBorder(12, 0, 4, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }

    private JComponent para(String text) {
        JTextArea a = new JTextArea(text);
        a.setLineWrap(true);
        a.setWrapStyleWord(true);
        a.setEditable(false);
        a.setOpaque(false);
        a.setFont(Theme.FONT_BODY);
        a.setForeground(Theme.INK_2);
        a.setBorder(new EmptyBorder(0, 0, 0, 0));
        a.setAlignmentX(LEFT_ALIGNMENT);
        a.setMaximumSize(new Dimension(Integer.MAX_VALUE, Integer.MAX_VALUE));
        return a;
    }

    private JComponent bullet(String text) {
        JTextArea a = new JTextArea("•  " + text);
        a.setLineWrap(true);
        a.setWrapStyleWord(true);
        a.setEditable(false);
        a.setOpaque(false);
        a.setFont(Theme.FONT_SMALL);
        a.setForeground(Theme.INK_2);
        a.setBorder(new EmptyBorder(2, 4, 0, 0));
        a.setAlignmentX(LEFT_ALIGNMENT);
        a.setMaximumSize(new Dimension(Integer.MAX_VALUE, Integer.MAX_VALUE));
        return a;
    }

    private JComponent code(String text) {
        JTextArea a = new JTextArea(text);
        a.setEditable(false);
        a.setFont(new Font(Font.MONOSPACED, Font.PLAIN, 12));
        a.setBackground(CODE_BG);
        a.setForeground(new Color(0x0F, 0x17, 0x2A));
        a.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER),
                new EmptyBorder(8, 10, 8, 10)));
        a.setAlignmentX(LEFT_ALIGNMENT);
        a.setMaximumSize(new Dimension(Integer.MAX_VALUE, a.getPreferredSize().height + 18));
        return a;
    }

    private JComponent link(String label, String url) {
        JLabel l = new JLabel("<html><u>" + label + "</u></html>");
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(LINK);
        l.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        l.setBorder(new EmptyBorder(2, 16, 2, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        l.addMouseListener(new MouseAdapter() {
            @Override public void mouseClicked(MouseEvent e) { open(url); }
        });
        return l;
    }

    private JComponent mailto(String email) {
        return link(email, "mailto:" + email);
    }

    private JComponent devName(String name) {
        JLabel l = new JLabel("•  " + name);
        l.setFont(Theme.FONT_BODY_BOLD);
        l.setForeground(Theme.INK_1);
        l.setBorder(new EmptyBorder(2, 4, 0, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }

    private JLabel note(String text) {
        JLabel l = new JLabel("<html><body style='width:640px'><i>" + text + "</i></body></html>");
        l.setFont(Theme.FONT_SMALL);
        l.setForeground(Theme.INK_3);
        l.setBorder(new EmptyBorder(14, 4, 4, 0));
        l.setAlignmentX(LEFT_ALIGNMENT);
        return l;
    }

    private static void open(String url) {
        try {
            if (Desktop.isDesktopSupported()) {
                Desktop.getDesktop().browse(new URI(url));
            }
        } catch (Exception ignore) {
            // best-effort; ignore if no browser/mail client is available
        }
    }
}
