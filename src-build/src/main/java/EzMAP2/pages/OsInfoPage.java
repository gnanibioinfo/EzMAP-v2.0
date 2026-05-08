package EzMAP2.pages;

import EzMAP2.WizardController;
import EzMAP2.ui.*;

import javax.swing.*;
import java.awt.*;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Step 1 — Environment Setup (inline, no external windows).
 *
 * Runs all checks and installations inside the activity log:
 *   1. Detect OS → show banner
 *   2. Check WSL + Ubuntu (Windows only) — streamed to log
 *   3. Install QIIME2 environment via install.sh — streamed to log
 *   4. Auto-advance to Choose Mode when done
 *
 * Everything streams into the LogConsole — no popup terminal windows.
 */
public class OsInfoPage extends BasePage {

    private final WizardController wizard;
    private final InfoBanner       osBanner;
    private final PrimaryButton    setupBtn     = new PrimaryButton("Start Environment Setup");
    private final OutlineButton    skipBtn      = new OutlineButton("Skip (already installed)");
    private final LogConsole       console      = new LogConsole();
    private final JLabel           statusLabel  = new JLabel(" ");
    private final JProgressBar     progressBar  = new JProgressBar(0, 4);
    private final Card             doneCard;
    private final PrimaryButton    continueBtn  = new PrimaryButton("Continue to Mode Selection  \u2192");

    private final Card       setupCard;
    private volatile Process runningProcess;
    private volatile boolean setupComplete = false;

    public OsInfoPage(WizardController wizard) {
        super("Environment Setup",
              "EzMAP v2 checks your system, installs Miniconda and the QIIME2 environment. " +
              "Everything runs right here — no separate terminal windows.");
        this.wizard = wizard;

        osBanner = buildOsBanner();
        add(osBanner);

        // --- Compact setup controls (top) ---
        setupCard = new Card("1 · Automated Environment Setup");

        // Progress bar
        progressBar.setStringPainted(true);
        progressBar.setString("Ready");
        progressBar.setForeground(Theme.PRIMARY);
        progressBar.setPreferredSize(new Dimension(0, 22));
        setupCard.row(progressBar).gap(6);

        statusLabel.setFont(Theme.FONT_BODY);
        statusLabel.setForeground(Theme.INK_3);
        setupCard.row(statusLabel).gap(8);

        // Buttons in a row
        JPanel btnRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 8, 0));
        btnRow.setOpaque(false);
        btnRow.add(setupBtn);
        btnRow.add(skipBtn);
        setupCard.row(btnRow);

        add(setupCard);

        // --- Activity log (takes most of the space, in the middle) ---
        Card logCard = new Card("Activity log");
        console.setPreferredSize(new Dimension(0, 340));
        logCard.row(console);
        add(logCard);

        // --- Done card (hidden until setup completes, at the bottom after log) ---
        doneCard = new Card(null);
        JLabel doneLabel = new JLabel(
            "<html><span style='color:#16A34A; font-size:14px'>"
            + "<b>\u2713 Environment is ready!</b> "
            + "Review the log above, then continue.</span></html>");
        doneCard.row(doneLabel).gap(12);
        continueBtn.setAlignmentX(LEFT_ALIGNMENT);
        doneCard.row(continueBtn);
        doneCard.setVisible(false);
        add(doneCard);

        // --- Wiring ---
        setupBtn.addActionListener(e -> startSetup());
        skipBtn.addActionListener(e -> {
            console.ok("Setup skipped by user. Proceeding to mode selection.");
            setupComplete = true;
            wizard.next();
        });
        continueBtn.addActionListener(e -> wizard.next());
    }

    private InfoBanner buildOsBanner() {
        String name    = System.getProperty("os.name");
        String version = System.getProperty("os.version");
        String lower   = name.toLowerCase();

        InfoBanner.Kind kind = InfoBanner.Kind.INFO;
        String body;
        if (lower.contains("win")) {
            body = "Detected <b>" + name + " " + version + "</b>. EzMAP v2 will run QIIME2 through <b>WSL (Ubuntu)</b>.";
        } else if (lower.contains("mac")) {
            body = "Detected <b>macOS " + version + "</b>. EzMAP v2 will use the native terminal.";
            kind = InfoBanner.Kind.SUCCESS;
        } else {
            body = "Detected <b>" + name + " " + version + "</b>. Native Linux — ideal for QIIME2.";
            kind = InfoBanner.Kind.SUCCESS;
        }
        return new InfoBanner(kind, "Operating System", body);
    }

    /**
     * Called by MainFrame when background check finds QIIME2 already installed.
     * Shows a success message on the env page and lets the user click Continue.
     */
    public void showAlreadyInstalled() {
        SwingUtilities.invokeLater(() -> {
            setupComplete = true;

            // Update progress bar to complete
            progressBar.setValue(4);
            progressBar.setString("Already installed");

            // Hide setup/skip buttons
            setupBtn.setVisible(false);
            skipBtn.setVisible(false);

            // Show status
            statusLabel.setText("<html><span style='color:#16A34A; font-weight:bold'>"
                    + "\u2713 Setup complete</span></html>");

            // Log the good news
            console.ok("QIIME2 environment 'EzMAP2-qiime2' is already installed.");
            console.ok("Miniconda and all dependencies are ready.");
            console.info("No installation needed — you can continue to mode selection.");

            // Show done card with Continue button
            doneCard.setVisible(true);
            doneCard.setMaximumSize(new Dimension(Short.MAX_VALUE, doneCard.getPreferredSize().height));
            getBody().revalidate();
            getBody().repaint();

            continueBtn.requestFocusInWindow();
        });
    }

    // ==================================================================
    //  SETUP FLOW — all inline, no external windows
    // ==================================================================

    private void startSetup() {
        setupBtn.setEnabled(false);
        skipBtn.setEnabled(false);
        console.clear();
        progressBar.setValue(0);
        progressBar.setString("Starting…");

        new Thread(() -> {
            String os = System.getProperty("os.name").toLowerCase();
            boolean isWindows = os.contains("win");

            try {
                // ---- Step 1: OS check ----
                updateProgress(1, "Checking operating system…");

                if (isWindows) {
                    // Check WSL
                    log("Checking WSL installation…");
                    WslResult wslStatus = runAndRead(new String[]{"wsl.exe", "--status"});
                    if (wslStatus.failed) {
                        err("WSL is not installed on this system.");
                        err("To install WSL + Ubuntu:");
                        err("  1. Open PowerShell as Administrator");
                        err("  2. Run: wsl --install");
                        err("  3. Restart your computer");
                        err("  4. Return to EzMAP v2 and try again");
                        SwingUtilities.invokeLater(() -> showWslMissingDialog());
                        resetButtons();
                        return;
                    }
                    ok("WSL detected.");

                    // Check Ubuntu distro
                    log("Checking for Ubuntu distribution…");
                    WslResult distros = runAndRead(new String[]{"wsl.exe", "-l", "-q"});
                    String distroText = distros.output.replaceAll("\\s+", " ").trim();
                    boolean hasUbuntu = distroText.toLowerCase().contains("ubuntu");

                    if (!hasUbuntu) {
                        err("Ubuntu not found in WSL. Installed distros: " + distroText);
                        err("To install Ubuntu:");
                        err("  1. Open PowerShell");
                        err("  2. Run: wsl --install -d Ubuntu");
                        err("  3. Set a username/password when prompted");
                        err("  4. Return to EzMAP v2 and try again");
                        resetButtons();
                        return;
                    }
                    ok("Ubuntu found: " + distroText.trim());
                } else {
                    ok("Native " + System.getProperty("os.name") + " — no WSL needed.");
                }

                // ---- Step 2: Check if already installed ----
                updateProgress(2, "Checking existing QIIME2 installation…");

                boolean alreadyInstalled = false;
                if (isWindows) {
                    WslResult envCheck = runAndRead(new String[]{
                        "wsl.exe", "-d", "Ubuntu", "--",
                        "bash", "-lc", "conda env list 2>/dev/null"});
                    alreadyInstalled = envCheck.output.contains("EzMAP2-qiime2");
                } else {
                    WslResult envCheck = runAndRead(new String[]{
                        "bash", "-lc", "conda env list 2>/dev/null"});
                    alreadyInstalled = envCheck.output.contains("EzMAP2-qiime2");
                }

                if (alreadyInstalled) {
                    ok("QIIME2 environment 'EzMAP2-qiime2' is already installed!");
                    updateProgress(4, "Setup complete — already installed");
                    setupDone();
                    return;
                }

                log("QIIME2 not found. Starting installation…");

                // ---- Step 3 + 4: Run install.sh ----
                updateProgress(3, "Installing Miniconda + QIIME2 (this may take 15–30 min)…");

                String projectDir = System.getProperty("user.dir");
                String installScript = findInstallScript(projectDir);

                ProcessBuilder pb;
                if (isWindows) {
                    String wslPath = toWsl(installScript);
                    pb = new ProcessBuilder("wsl.exe", "-d", "Ubuntu", "--",
                            "bash", "-l", wslPath);
                } else {
                    pb = new ProcessBuilder("bash", "-l", installScript);
                }
                pb.redirectErrorStream(true);
                pb.directory(new File(projectDir));

                runningProcess = pb.start();
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(runningProcess.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        final String s = line;
                        SwingUtilities.invokeLater(() -> routeLogLine(s));
                    }
                }
                int exit = runningProcess.waitFor();

                if (exit == 0) {
                    updateProgress(4, "Setup complete!");
                    ok("Environment setup finished successfully.");
                    setupDone();
                } else {
                    err("Installation failed with exit code " + exit + ".");
                    err("Check the log above for details. Fix the issue and click 'Start Environment Setup' again.");
                    resetButtons();
                }

            } catch (Exception ex) {
                err("Setup error: " + ex.getMessage());
                resetButtons();
            }
        }).start();
    }

    private void setupDone() {
        setupComplete = true;
        SwingUtilities.invokeLater(() -> {
            // Hide setup buttons, show success in progress area
            setupBtn.setVisible(false);
            skipBtn.setVisible(false);
            statusLabel.setText("<html><span style='color:#16A34A; font-weight:bold'>"
                + "\u2713 Setup complete</span></html>");

            // Show the done card with Continue button BELOW the activity log
            doneCard.setVisible(true);
            // Update max size so BoxLayout can show it after it becomes visible
            doneCard.setMaximumSize(new Dimension(Short.MAX_VALUE, doneCard.getPreferredSize().height));
            getBody().revalidate();
            getBody().repaint();

            // Scroll to the bottom so the Continue button is visible
            SwingUtilities.invokeLater(() -> {
                Rectangle r = doneCard.getBounds();
                getBody().scrollRectToVisible(r);
                continueBtn.requestFocusInWindow();
            });
        });
    }

    private void resetButtons() {
        SwingUtilities.invokeLater(() -> {
            setupBtn.setEnabled(true);
            skipBtn.setEnabled(true);
        });
    }

    private void updateProgress(int step, String msg) {
        SwingUtilities.invokeLater(() -> {
            progressBar.setValue(step);
            progressBar.setString("Step " + step + "/4: " + msg);
            statusLabel.setText("<html><span style='color:#64748B'>" + msg + "</span></html>");
        });
    }

    // --- Log helpers (route to console on EDT) ---
    private void log(String msg) {
        SwingUtilities.invokeLater(() -> console.info(msg));
    }
    private void ok(String msg) {
        SwingUtilities.invokeLater(() -> console.ok(msg));
    }
    private void err(String msg) {
        SwingUtilities.invokeLater(() -> console.err(msg));
    }

    /** Route ANSI-colored lines from install script to styled console. */
    private void routeLogLine(String line) {
        String stripped = line.replaceAll("\u001B\\[[;\\d]*m", "");
        String lower = stripped.toLowerCase();
        if (lower.contains("\u2713") || lower.contains("complete") || lower.contains("ready")
                || lower.contains("already installed") || lower.contains("skipping")) {
            console.ok(stripped);
        } else if (lower.contains("\u26A0") || lower.contains("warn")) {
            console.warn(stripped);
        } else if (lower.contains("\u2718") || lower.contains("error") || lower.contains("failed")) {
            console.err(stripped);
        } else {
            console.info(stripped);
        }
    }

    // --- WSL missing dialog (only for fatal WSL-not-installed case) ---
    private void showWslMissingDialog() {
        String msg =
            "<html><body style='width:420px'>"
          + "<h3 style='margin-top:0'>WSL is not installed</h3>"
          + "<p>EzMAP v2 needs <b>WSL (Windows Subsystem for Linux)</b> with Ubuntu.</p>"
          + "<p><b>To install:</b></p>"
          + "<ol>"
          + "  <li>Open <b>PowerShell</b> as <b>Administrator</b></li>"
          + "  <li>Run: <code>wsl --install</code></li>"
          + "  <li><b>Restart</b> your computer</li>"
          + "  <li>Return to EzMAP v2 and click Setup again</li>"
          + "</ol>"
          + "</body></html>";
        JOptionPane.showMessageDialog(this, msg, "WSL Required", JOptionPane.WARNING_MESSAGE);
    }

    // --- Utility ---
    /** Run a command, capture output, return result. */
    private WslResult runAndRead(String[] cmd) {
        WslResult r = new WslResult();
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            byte[] raw = p.getInputStream().readAllBytes();
            int exit = p.waitFor();
            String asUtf8 = new String(raw, StandardCharsets.UTF_8);
            String asUtf16 = new String(raw, Charset.forName("UTF-16LE"));
            r.output = asUtf8.indexOf('\0') >= 0 ? asUtf16 : asUtf8;
            r.failed = exit != 0;
        } catch (Exception e) {
            r.failed = true;
            r.output = e.getMessage() == null ? "" : e.getMessage();
        }
        return r;
    }

    private static class WslResult {
        boolean failed;
        String  output = "";
    }

    /**
     * Search for the install script in multiple locations.
     * Checks: install.sh (current name), install_auto.sh (legacy name),
     * and scripts/ subfolder for both.
     */
    private static String findInstallScript(String projectDir) {
        String sep = File.separator;
        String[] candidates = {
            projectDir + sep + "install.sh",
            projectDir + sep + "install_auto.sh",
            projectDir + sep + "scripts" + sep + "install.sh",
            projectDir + sep + "scripts" + sep + "install_auto.sh",
            new File(projectDir).getParent() + sep + "install.sh",
            new File(projectDir).getParent() + sep + "install_auto.sh",
        };
        for (String path : candidates) {
            if (new File(path).isFile()) return path;
        }
        // Fallback to expected name (will produce a clear "not found" error)
        return projectDir + sep + "install.sh";
    }

    /** Convert Windows path to WSL path. */
    private static String toWsl(String winPath) {
        if (winPath == null || winPath.isEmpty()) return winPath;
        String p = winPath.replace("\\", "/");
        if (p.length() >= 2 && p.charAt(1) == ':') {
            String drive = Character.toString(Character.toLowerCase(p.charAt(0)));
            return "/mnt/" + drive + p.substring(2);
        }
        return p;
    }
}
