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
    private final LogConsole       console      = new LogConsole();
    private final JLabel           statusLabel  = new JLabel(" ");
    private final JProgressBar     progressBar  = new JProgressBar(0, 4);
    private final Card             doneCard;
    private final PrimaryButton    continueBtn  = new PrimaryButton("Continue to Database & Classifiers  \u2192");

    private final Card       setupCard;
    private volatile Process runningProcess;
    private volatile boolean setupComplete = false;

    /**
     * Actual WSL distribution name to target (e.g. "Ubuntu" or "Ubuntu-24.04").
     * Resolved at detection time from `wsl -l -q`; never hardcode "Ubuntu" in
     * `wsl -d ...` calls, or fresh machines whose distro is named "Ubuntu-24.04"
     * fail with "There is no distribution with the supplied name 'Ubuntu'".
     */
    private volatile String wslDistro = "Ubuntu";

    public OsInfoPage(WizardController wizard) {
        super("Environment Setup",
              "EzMAP v2.0 checks your system, installs Miniconda and the QIIME2 environment. " +
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
        continueBtn.addActionListener(e -> wizard.next());
    }

    private InfoBanner buildOsBanner() {
        String name    = System.getProperty("os.name");
        String version = System.getProperty("os.version");
        String lower   = name.toLowerCase();

        InfoBanner.Kind kind = InfoBanner.Kind.INFO;
        String body;
        if (lower.contains("win")) {
            body = "Detected <b>" + name + " " + version + "</b>. EzMAP v2.0 will run QIIME2 through <b>WSL (Ubuntu)</b>.";
        } else if (lower.contains("mac")) {
            body = "Detected <b>macOS " + version + "</b>. EzMAP v2.0 will use the native terminal.";
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

            // Hide the setup button once complete
            setupBtn.setVisible(false);

            // Show status
            statusLabel.setText("<html><span style='color:#16A34A; font-weight:bold'>"
                    + "\u2713 Setup complete</span></html>");

            // Log the good news
            console.ok("QIIME2 environment 'EzMAP2-qiime2' is already installed.");
            console.ok("Miniconda and all dependencies are ready.");
            console.info("No installation needed — you can continue to Database & Classifiers.");

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
                        err("  4. Return to EzMAP v2.0 and try again");
                        SwingUtilities.invokeLater(() -> showWslMissingDialog());
                        resetButtons();
                        return;
                    }
                    ok("WSL detected.");

                    // Check Ubuntu distro
                    log("Checking for Ubuntu distribution…");
                    WslResult distros = runAndRead(new String[]{"wsl.exe", "-l", "-q"});
                    String ubuntuName = EzMAP2.ui.WslEnv.parseUbuntu(distros.output);

                    if (ubuntuName == null) {
                        String distroText = distros.output
                                .replaceAll("[\\u0000\\uFEFF]", "")
                                .replaceAll("\\s+", " ").trim();
                        err("Ubuntu not found in WSL. Installed distros: "
                                + (distroText.isEmpty() ? "(none)" : distroText));
                        err("To install Ubuntu:");
                        err("  1. Open PowerShell");
                        err("  2. Run: wsl --install -d Ubuntu");
                        err("  3. Set a username/password when prompted");
                        err("  4. Return to EzMAP v2.0 and try again");
                        SwingUtilities.invokeLater(() -> showUbuntuMissingDialog());
                        resetButtons();
                        return;
                    }
                    // Use the REAL distro name for every later `wsl -d ...` call,
                    // and share it app-wide so every page targets the same distro.
                    wslDistro = ubuntuName;
                    EzMAP2.ui.WslEnv.setDistro(ubuntuName);
                    ok("Ubuntu found: " + ubuntuName);

                    // A freshly `wsl --install`-ed Ubuntu is *registered* but not
                    // usable until the user launches it once to create a UNIX
                    // account — until then it sits in the "Installing" state and
                    // every `wsl -d ...` command fails. Probe with a trivial
                    // command (timed, so an OOBE prompt can't hang setup).
                    log("Verifying Ubuntu is ready…");
                    WslResult probe = runAndReadTimed(new String[]{
                            "wsl.exe", "-d", wslDistro, "--",
                            "bash", "-lc", "echo EZMAP2_WSL_READY"}, 25);
                    boolean ready = !probe.failed
                            && probe.output.contains("EZMAP2_WSL_READY");
                    if (!ready) {
                        String detail = probe.output
                                .replaceAll("[\\u0000\\uFEFF]", "").trim();
                        err("Ubuntu (" + wslDistro + ") is installed but not ready yet.");
                        if (!detail.isEmpty() && !detail.contains("EZMAP2_WSL_READY")) {
                            err("WSL said: " + detail);
                        }
                        err("This usually means Ubuntu was installed but never launched.");
                        err("To finish first-time setup:");
                        err("  1. Open the Start menu and launch “Ubuntu” once");
                        err("  2. Create a username and password when prompted");
                        err("  3. Wait for “Installation successful!”, then close it");
                        err("  4. Return to EzMAP v2.0 and click Start Environment Setup again");
                        SwingUtilities.invokeLater(() -> showUbuntuNotReadyDialog(wslDistro));
                        resetButtons();
                        return;
                    }
                    ok("Ubuntu is ready.");
                } else {
                    ok("Native " + System.getProperty("os.name") + " — no WSL needed.");
                }

                // ---- Step 2: Check if already installed ----
                updateProgress(2, "Checking existing QIIME2 installation…");

                // Detect the env reliably. A plain `conda env list` fails when
                // conda isn't initialized in this shell (no conda init in
                // .bashrc) and returns nothing — which made this wrongly report
                // "QIIME2 not found" even though the env exists. So we both
                // source conda AND directly check for the env directory under
                // every common conda install location.
                String condaEnvCheck =
                    "for d in \"$HOME/miniconda3\" \"$HOME/anaconda3\" \"$HOME/miniforge3\" "
                  + "\"$HOME/mambaforge\" \"$HOME/.conda\" \"/opt/miniconda3\" \"/opt/conda\" "
                  + "\"/opt/miniforge3\"; do "
                  + "if [ -d \"$d/envs/EzMAP2-qiime2\" ]; then echo EZMAP2_ENV_FOUND; break; fi; "
                  + "done";

                WslResult envCheck;
                if (isWindows) {
                    envCheck = runAndRead(new String[]{
                        "wsl.exe", "-d", wslDistro, "--", "bash", "-lc", condaEnvCheck});
                } else {
                    envCheck = runAndRead(new String[]{"bash", "-lc", condaEnvCheck});
                }
                boolean alreadyInstalled = envCheck.output.contains("EZMAP2_ENV_FOUND");

                if (alreadyInstalled) {
                    ok("QIIME2 environment 'EzMAP2-qiime2' is already installed!");
                    updateProgress(4, "Setup complete — already installed");
                    setupDone();
                    return;
                }

                // Neutral wording: the installer below checks every component
                // and skips whatever is already present, so we must NOT claim
                // "QIIME2 not found" (which alarmed users when the quick check
                // missed an existing env).
                log("Running environment setup — already-installed components are skipped automatically…");

                // ---- Step 3 + 4: Run install.sh ----
                updateProgress(3, "Setting up environment (first-time install can take 15–30 min)…");

                String installScript = findInstallScript();
                if (installScript == null) {
                    err("Could not find install.sh.");
                    err("It should sit next to EzMAP2.jar in your EzMAP v2.0 folder.");
                    err("Searched the app folder, its parent, and the launch directory.");
                    err("Put install.sh beside EzMAP2.jar, then try again.");
                    resetButtons();
                    return;
                }
                File scriptFile = new File(installScript);
                File workDir = scriptFile.getParentFile();

                ProcessBuilder pb;
                if (isWindows) {
                    String wslPath = toWsl(installScript);
                    pb = new ProcessBuilder("wsl.exe", "-d", wslDistro, "--",
                            "bash", "-l", wslPath);
                } else {
                    pb = new ProcessBuilder("bash", "-l", installScript);
                }
                pb.redirectErrorStream(true);
                pb.directory(workDir != null ? workDir
                        : new File(System.getProperty("user.dir")));

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
            // Hide the setup button, show success in progress area
            setupBtn.setVisible(false);
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
          + "<p>EzMAP v2.0 needs <b>WSL (Windows Subsystem for Linux)</b> with Ubuntu.</p>"
          + "<p><b>To install:</b></p>"
          + "<ol>"
          + "  <li>Open <b>PowerShell</b> as <b>Administrator</b></li>"
          + "  <li>Run: <code>wsl --install</code></li>"
          + "  <li><b>Restart</b> your computer</li>"
          + "  <li>Return to EzMAP v2.0 and click Setup again</li>"
          + "</ol>"
          + "</body></html>";
        JOptionPane.showMessageDialog(this, msg, "WSL Required", JOptionPane.WARNING_MESSAGE);
    }

    // --- Ubuntu missing dialog (WSL present but no Ubuntu distro) ---
    private void showUbuntuMissingDialog() {
        String msg =
            "<html><body style='width:440px'>"
          + "<h3 style='margin-top:0'>Ubuntu is not installed in WSL</h3>"
          + "<p>WSL is present, but no <b>Ubuntu</b> distribution was found. "
          + "EzMAP v2.0 runs QIIME2 inside Ubuntu.</p>"
          + "<p><b>To install Ubuntu:</b></p>"
          + "<ol>"
          + "  <li>Open <b>PowerShell</b></li>"
          + "  <li>Run: <code>wsl --install -d Ubuntu</code></li>"
          + "  <li>Set a <b>username and password</b> when Ubuntu first launches</li>"
          + "  <li>Return to EzMAP v2.0 and click <b>Start Environment Setup</b> again</li>"
          + "</ol>"
          + "</body></html>";
        JOptionPane.showMessageDialog(this, msg, "Ubuntu Required", JOptionPane.WARNING_MESSAGE);
    }

    // --- Ubuntu present but not initialized (registered, never launched) ---
    private void showUbuntuNotReadyDialog(String distro) {
        String msg =
            "<html><body style='width:460px'>"
          + "<h3 style='margin-top:0'>Ubuntu needs to finish setting up</h3>"
          + "<p><b>" + distro + "</b> is installed but hasn't been initialized yet, "
          + "so EzMAP v2.0 can't run commands inside it. This is the normal state right "
          + "after <code>wsl --install</code>, before Ubuntu has been opened once.</p>"
          + "<p><b>To finish first-time setup:</b></p>"
          + "<ol>"
          + "  <li>Open the <b>Start menu</b> and launch <b>Ubuntu</b> once</li>"
          + "  <li>Create a <b>username and password</b> when prompted</li>"
          + "  <li>Wait for <b>“Installation successful!”</b>, then close the window</li>"
          + "  <li>Return to EzMAP v2.0 and click <b>Start Environment Setup</b> again</li>"
          + "</ol>"
          + "</body></html>";
        JOptionPane.showMessageDialog(this, msg, "Finish Ubuntu Setup", JOptionPane.WARNING_MESSAGE);
    }

    // --- Utility ---
    /**
     * Like {@link #runAndRead} but bounded by a timeout, draining stdout on a
     * background thread so a process that blocks on input (e.g. an Ubuntu OOBE
     * prompt on a not-yet-initialized distro) cannot hang the setup thread.
     * On timeout the process is force-killed and {@code failed} is set.
     */
    private WslResult runAndReadTimed(String[] cmd, int timeoutSec) {
        WslResult r = new WslResult();
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            final java.io.InputStream in = p.getInputStream();
            final java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            Thread reader = new Thread(() -> {
                try {
                    byte[] buf = new byte[4096];
                    int len;
                    while ((len = in.read(buf)) != -1) {
                        synchronized (bos) { bos.write(buf, 0, len); }
                    }
                } catch (Exception ignored) { }
            });
            reader.setDaemon(true);
            reader.start();

            boolean done = p.waitFor(timeoutSec, java.util.concurrent.TimeUnit.SECONDS);
            if (!done) {
                p.destroyForcibly();
                r.failed = true;
            } else {
                r.failed = p.exitValue() != 0;
            }
            reader.join(1500);

            byte[] raw;
            synchronized (bos) { raw = bos.toByteArray(); }
            String asUtf8 = new String(raw, StandardCharsets.UTF_8);
            r.output = asUtf8.indexOf('\0') >= 0
                    ? new String(raw, Charset.forName("UTF-16LE")) : asUtf8;
        } catch (Exception e) {
            r.failed = true;
            r.output = e.getMessage() == null ? "" : e.getMessage();
        }
        return r;
    }

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
     * Locate install.sh independent of where the app was *launched* from.
     *
     * <p>{@code user.dir} is unreliable: a desktop/Start-menu shortcut makes it
     * {@code C:\\WINDOWS\\system32}, so EzMAP looked for install.sh there and
     * failed with "No such file or directory". We instead search, in order:
     * the folder containing EzMAP2.jar, that folder's parent, then user.dir and
     * its parent — each with install.sh / install_auto.sh, at the base and in a
     * scripts/ subfolder. Returns an absolute path, or null if not found.
     */
    private static String findInstallScript() {
        String sep = File.separator;
        java.util.List<String> bases = new java.util.ArrayList<>();
        String jd = jarDir();
        if (jd != null) {
            bases.add(jd);
            String jp = new File(jd).getParent();
            if (jp != null) bases.add(jp);
        }
        String ud = System.getProperty("user.dir");
        if (ud != null) {
            bases.add(ud);
            String up = new File(ud).getParent();
            if (up != null) bases.add(up);
        }
        String[] names = { "install.sh", "install_auto.sh" };
        String[] subs  = { "", "scripts" + sep };
        for (String base : bases) {
            for (String sub : subs) {
                for (String name : names) {
                    File f = new File(base + sep + sub + name);
                    if (f.isFile()) return f.getAbsolutePath();
                }
            }
        }
        return null;
    }

    /** Absolute directory containing the running EzMAP2 jar, or null. */
    private static String jarDir() {
        try {
            String jarPath = OsInfoPage.class.getProtectionDomain()
                    .getCodeSource().getLocation().getPath();
            return new File(java.net.URLDecoder.decode(jarPath, "UTF-8"))
                    .getAbsoluteFile().getParent();
        } catch (Exception e) {
            return null;
        }
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
