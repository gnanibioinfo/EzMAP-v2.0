package EzMAP2;

import EzMAP2.pages.*;
import EzMAP2.ui.*;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.geom.Ellipse2D;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.InputStream;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;
import javax.imageio.ImageIO;

/**
 * Application shell: sidebar (brand + step list + lab footer),
 * top bar (breadcrumbs + help/settings), center card area,
 * bottom footer (progress + Back/Continue).
 */
public class MainFrame extends JFrame {

    private final CardLayout cardLayout = new CardLayout();
    private final JPanel     cards      = new JPanel(cardLayout);
    private final WizardController wizard = new WizardController(cards, cardLayout);

    private final StepList   stepList   = new StepList();
    private final JLabel     crumb      = new JLabel();
    private final JProgressBar progress = new JProgressBar();
    private final GhostButton   backBtn = new GhostButton("\u2190  Back");
    private final PrimaryButton nextBtn = new PrimaryButton("Continue  \u2192");

    public MainFrame() {
        super("EzMAP v2 — Easy Microbiome Pipeline");
        setDefaultCloseOperation(EXIT_ON_CLOSE);
        setMinimumSize(new Dimension(960, 680));
        setPreferredSize(new Dimension(1100, 760));

        cards.setBackground(Theme.BACKGROUND);

        // Set window icon (taskbar + title bar)
        try {
            InputStream iconStream = getClass().getResourceAsStream("/images/ezmap_icon_64.png");
            if (iconStream != null) {
                setIconImage(ImageIO.read(iconStream));
                iconStream.close();
            }
        } catch (Exception ignored) {}

        setContentPane(buildShell());

        registerPages();
        wizard.setOnChange(this::syncShell);
        wizard.setOnFlowChange(this::syncFlow);

        // Start with the Welcome page — user chooses Full Analysis or Downstream Only
        wizard.setActiveFlow(
                Arrays.asList("welcome"),
                Arrays.asList("Welcome"));
        wizard.showIndex(0);

        pack();
        setLocationRelativeTo(null);

        // Background smart-start: if QIIME2 already installed, show success on env page
        new Thread(() -> {
            if (isQiime2Ready()) {
                OsInfoPage envPage = (OsInfoPage) wizard.getPages().get("env");
                if (envPage != null) {
                    envPage.showAlreadyInstalled();
                }
            }
        }).start();
    }

    // ---- Shell construction ------------------------------------------------
    private JPanel buildShell() {
        JPanel root = new JPanel(new BorderLayout());
        root.setBackground(Theme.BACKGROUND);

        root.add(buildSidebar(), BorderLayout.WEST);

        JPanel main = new JPanel(new BorderLayout());
        main.setBackground(Theme.BACKGROUND);
        main.add(buildTopBar(),    BorderLayout.NORTH);
        main.add(cards,            BorderLayout.CENTER);
        main.add(buildFooterBar(), BorderLayout.SOUTH);
        root.add(main, BorderLayout.CENTER);

        return root;
    }

    private JComponent buildSidebar() {
        JPanel side = new JPanel() {
            @Override protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                Graphics2D g2 = (Graphics2D) g.create();
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                g2.setPaint(new GradientPaint(0, 0, Theme.SIDEBAR_TOP, 0, getHeight(), Theme.SIDEBAR_BOTTOM));
                g2.fillRect(0, 0, getWidth(), getHeight());
                g2.dispose();
            }
        };
        side.setLayout(new BorderLayout());
        side.setPreferredSize(new Dimension(250, 0));

        // ── Brand area (top): "Ez" circle on left + text on right ──
        JPanel brand = new JPanel(new BorderLayout(10, 0));
        brand.setOpaque(false);
        brand.setBorder(new EmptyBorder(20, 16, 16, 16));

        JLabel logoIcon = createEzCircleLabel(58, 24f);
        brand.add(logoIcon, BorderLayout.WEST);

        JPanel brandText = new JPanel();
        brandText.setOpaque(false);
        brandText.setLayout(new BoxLayout(brandText, BoxLayout.Y_AXIS));
        brandText.setBorder(new EmptyBorder(4, 0, 0, 0));
        JLabel nameLabel = new JLabel("EzMAP V2");
        nameLabel.setFont(Theme.FONT_BRAND.deriveFont(Font.BOLD, 22f));
        nameLabel.setForeground(Color.WHITE);
        JLabel subLabel = new JLabel("Easy Microbiome Pipeline");
        subLabel.setFont(Theme.FONT_BRAND_SUB.deriveFont(Font.BOLD, 11f));
        subLabel.setForeground(new Color(255, 255, 255, 200));
        brandText.add(nameLabel);
        brandText.add(Box.createVerticalStrut(2));
        brandText.add(subLabel);
        brand.add(brandText, BorderLayout.CENTER);

        side.add(brand, BorderLayout.NORTH);
        side.add(stepList, BorderLayout.CENTER);

        // ── Lab footer (bottom): icon on left + lab info on right ──
        JPanel foot = new JPanel(new BorderLayout(8, 0));
        foot.setOpaque(false);
        foot.setBorder(new EmptyBorder(12, 16, 16, 16));

        JLabel footIcon = createEzCircleLabel(40, 16f);
        foot.add(footIcon, BorderLayout.WEST);

        JPanel footText = new JPanel();
        footText.setOpaque(false);
        footText.setLayout(new BoxLayout(footText, BoxLayout.Y_AXIS));
        JLabel l1 = new JLabel("MG Lab,  Yeungnam University");
        JLabel l2 = new JLabel("Republic of Korea\u2013 2026");
        JLabel l3 = new JLabel("EzMAP v2.0");
        for (JLabel l : new JLabel[]{l1, l2, l3}) {
            l.setFont(Theme.FONT_SMALL);
            l.setForeground(new Color(255, 255, 255, 200));
            l.setAlignmentX(LEFT_ALIGNMENT);
            footText.add(l);
        }
        foot.add(footText, BorderLayout.CENTER);
        side.add(foot, BorderLayout.SOUTH);
        return side;
    }

    /**
     * Create a clean "Ez" text label rendered inside a white circle.
     * Drawn programmatically — no external image needed.
     */
    private JLabel createEzCircleLabel(int diameter, float fontSize) {
        BufferedImage img = new BufferedImage(diameter, diameter, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g2 = img.createGraphics();
        g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g2.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_LCD_HRGB);

        // White circle background
        g2.setColor(Color.WHITE);
        g2.fill(new Ellipse2D.Float(0, 0, diameter, diameter));

        // "Ez" text centered in the circle
        g2.setColor(Theme.PRIMARY_DARK);
        g2.setFont(Theme.FONT_BRAND.deriveFont(Font.BOLD, fontSize));
        FontMetrics fm = g2.getFontMetrics();
        String text = "Ez";
        int tx = (diameter - fm.stringWidth(text)) / 2;
        int ty = (diameter - fm.getHeight()) / 2 + fm.getAscent();
        g2.drawString(text, tx, ty);
        g2.dispose();

        JLabel label = new JLabel(new ImageIcon(img));
        label.setPreferredSize(new Dimension(diameter, diameter));
        return label;
    }

    private JComponent buildTopBar() {
        JPanel top = new JPanel(new BorderLayout());
        top.setBackground(Theme.SURFACE);
        top.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(0, 0, 1, 0, Theme.BORDER),
                new EmptyBorder(0, 24, 0, 24)));
        top.setPreferredSize(new Dimension(0, 56));

        crumb.setFont(Theme.FONT_BODY);
        crumb.setForeground(Theme.INK_3);
        top.add(crumb, BorderLayout.WEST);

        JPanel actions = new JPanel(new FlowLayout(FlowLayout.RIGHT, 4, 0));
        actions.setOpaque(false);
        GhostButton helpBtn = new GhostButton("Help");
        helpBtn.addActionListener(e -> {
            HelpPage dlg = new HelpPage(MainFrame.this);
            dlg.setVisible(true);
        });
        actions.add(helpBtn);
        GhostButton settingsBtn = new GhostButton("\u2699 Settings");
        settingsBtn.addActionListener(e -> {
            SettingsPage dlg = new SettingsPage(MainFrame.this);
            dlg.setVisible(true);
        });
        actions.add(settingsBtn);
        top.add(actions, BorderLayout.EAST);
        return top;
    }

    private JComponent buildFooterBar() {
        JPanel foot = new JPanel(new BorderLayout());
        foot.setBackground(Theme.SURFACE);
        foot.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createMatteBorder(1, 0, 0, 0, Theme.BORDER),
                new EmptyBorder(0, 24, 0, 24)));
        foot.setPreferredSize(new Dimension(0, 60));

        JPanel left = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 0));
        left.setOpaque(false);
        JLabel stepLbl = new JLabel();
        stepLbl.setName("stepLbl");
        stepLbl.setFont(Theme.FONT_SMALL);
        stepLbl.setForeground(Theme.INK_3);
        progress.setPreferredSize(new Dimension(180, 6));
        progress.setBorderPainted(false);
        progress.setForeground(Theme.PRIMARY);
        progress.setBackground(Theme.BORDER);
        left.add(stepLbl);
        left.add(progress);
        foot.add(left, BorderLayout.WEST);

        JPanel right = new JPanel(new FlowLayout(FlowLayout.RIGHT, 8, 0));
        right.setOpaque(false);
        backBtn.addActionListener(e -> wizard.previous());
        nextBtn.addActionListener(e -> wizard.next());
        right.add(backBtn);
        right.add(nextBtn);
        foot.add(right, BorderLayout.EAST);
        return foot;
    }

    // ---- Page registration -------------------------------------------------
    private void registerPages() {
        wizard.addPage("welcome",           new WelcomePage(wizard));
        wizard.addPage("env",               new OsInfoPage(wizard));
        wizard.addPage("db",                new DatabaseSetupPage(wizard));
        wizard.addPage("mode",              new ModeSelectPage(wizard));
        wizard.addPage("easy",              new EasyModePage(wizard));
        wizard.addPage("results-summary",   new ResultsSummaryPage(wizard));
        wizard.addPage("downstream-upload", new DownstreamUploadPage(wizard));
        wizard.addPage("manifest",          new ManifestPage(wizard));
        wizard.addPage("import",            new ImportFilesPage(wizard));
        wizard.addPage("cutadapt",          new CutadaptPage(wizard));
        wizard.addPage("quality",           new SequenceQualityPage(wizard));
        wizard.addPage("denoise",           new DenoisingPage(wizard));
        wizard.addPage("taxonomy",          new TaxonomyPage(wizard));
        wizard.addPage("downstream",        new DownstreamPage(wizard));

        // Wire step completion listener on every page so footer nav updates
        for (BasePage page : wizard.getPages().values()) {
            page.setStepCompletionListener(this::syncShell);
        }
    }

    /** Rebuild sidebar labels when Easy/Expert mode swaps the active flow. */
    private void syncFlow() {
        stepList.setLabels(wizard.getActiveLabels());
    }

    // ---- Shell sync --------------------------------------------------------
    private void syncShell() {
        int i = wizard.getCurrentIndex();
        int n = wizard.getTotal();
        stepList.setActive(i);
        progress.setMinimum(0);
        progress.setMaximum(n - 1);
        progress.setValue(i);

        java.util.List<String> labels = wizard.getActiveLabels();
        String title = labels.isEmpty()
                ? ""
                : labels.get(Math.min(i, labels.size() - 1));
        crumb.setText("<html>Workflow &nbsp;\u203A&nbsp; <b style='color:#0F172A'>" + title + "</b></html>");

        // Hide footer nav on pages that have their own navigation
        String pageId = wizard.getCurrentId();
        boolean hideFooterNav = "welcome".equals(pageId) || "env".equals(pageId)
                || "db".equals(pageId) || "mode".equals(pageId) || "easy".equals(pageId)
                || "downstream-upload".equals(pageId) || "results-summary".equals(pageId)
                || "downstream".equals(pageId);
        backBtn.setVisible(!hideFooterNav);
        nextBtn.setVisible(!hideFooterNav);

        // Check if the current step is complete — block Continue if not
        BasePage currentPage = wizard.getPages().get(pageId);
        boolean stepDone = (currentPage == null) || currentPage.isStepComplete();
        backBtn.setEnabled(i > 0);
        nextBtn.setEnabled(stepDone);
        nextBtn.setText(i == n - 1 ? "Finish" : "Continue  \u2192");

        JLabel lbl = findByName(getContentPane(), "stepLbl");
        if (lbl != null) lbl.setText("Step " + (i + 1) + " of " + n);
    }

    /**
     * Quick background check: is the QIIME2 conda environment already installed?
     * On Windows: runs "wsl -d Ubuntu -- bash -lc 'conda env list'" and checks for EzMAP2-qiime2.
     * On macOS/Linux: runs "conda env list" directly.
     * Returns true if found (skip env setup), false if not found or check fails.
     */
    private boolean isQiime2Ready() {
        try {
            String os = System.getProperty("os.name").toLowerCase();
            ProcessBuilder pb;
            if (os.contains("win")) {
                pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                        "bash", "-lc", "conda env list 2>/dev/null");
            } else {
                pb = new ProcessBuilder("bash", "-lc", "conda env list 2>/dev/null");
            }
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] raw = p.getInputStream().readAllBytes();
            boolean exited = p.waitFor(8, java.util.concurrent.TimeUnit.SECONDS);
            if (!exited) { p.destroyForcibly(); return false; }
            if (p.exitValue() != 0) return false;
            String output = new String(raw, java.nio.charset.StandardCharsets.UTF_8);
            // Check for the EzMAP2-qiime2 environment name
            return output.contains("EzMAP2-qiime2") || output.contains("ezmap2-qiime2");
        } catch (Exception e) {
            return false;
        }
    }

    private static JLabel findByName(Container c, String name) {
        for (Component child : c.getComponents()) {
            if (child instanceof JLabel && name.equals(child.getName())) return (JLabel) child;
            if (child instanceof Container) {
                JLabel found = findByName((Container) child, name);
                if (found != null) return found;
            }
        }
        return null;
    }
}
