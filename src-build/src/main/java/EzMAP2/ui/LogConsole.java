package EzMAP2.ui;

import javax.swing.*;
import javax.swing.text.*;
import java.awt.*;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

/**
 * Dark-themed monospace console for streaming shell-script output with
 * colored timestamps. Thread-safe: all append calls marshal to the EDT.
 */
public class LogConsole extends JScrollPane {

    public enum Level { INFO, OK, WARN, ERR }

    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("HH:mm:ss");
    private final JTextPane pane = new JTextPane();
    private final Style sTs, sInfo, sOk, sWarn, sErr;

    public LogConsole() {
        super();

        // JTextPane that wraps text instead of scrolling horizontally
        pane.setEditable(false);
        pane.setBackground(Theme.CONSOLE_BG);
        pane.setForeground(Theme.CONSOLE_FG);
        pane.setFont(Theme.FONT_MONO);
        pane.setMargin(new Insets(10, 14, 10, 14));
        pane.setCaretColor(Theme.CONSOLE_FG);

        StyledDocument doc = pane.getStyledDocument();
        sTs   = doc.addStyle("ts",   null); StyleConstants.setForeground(sTs,   new Color(0x64, 0x74, 0x8B));
        sInfo = doc.addStyle("info", null); StyleConstants.setForeground(sInfo, Theme.CONSOLE_FG);
        sOk   = doc.addStyle("ok",   null); StyleConstants.setForeground(sOk,   Theme.CONSOLE_OK);
        sWarn = doc.addStyle("warn", null); StyleConstants.setForeground(sWarn, Theme.CONSOLE_WARN);
        sErr  = doc.addStyle("err",  null); StyleConstants.setForeground(sErr,  Theme.CONSOLE_ERR);

        // Wrap the pane in a panel that prevents horizontal growth,
        // so JTextPane wraps long lines instead of scrolling sideways.
        JPanel noWrapPanel = new JPanel(new BorderLayout());
        noWrapPanel.add(pane);
        setViewportView(noWrapPanel);

        setHorizontalScrollBarPolicy(JScrollPane.HORIZONTAL_SCROLLBAR_NEVER);
        setBorder(BorderFactory.createLineBorder(new Color(0x0F, 0x17, 0x2A), 1, true));
        getViewport().setBackground(Theme.CONSOLE_BG);
    }

    public void append(Level level, String text) {
        SwingUtilities.invokeLater(() -> {
            StyledDocument doc = pane.getStyledDocument();
            try {
                doc.insertString(doc.getLength(), "[" + LocalTime.now().format(TS) + "] ", sTs);
                Style s;
                switch (level) {
                    case OK:   s = sOk;   break;
                    case WARN: s = sWarn; break;
                    case ERR:  s = sErr;  break;
                    default:   s = sInfo;
                }
                doc.insertString(doc.getLength(), text + "\n", s);
                pane.setCaretPosition(doc.getLength());
            } catch (BadLocationException ignore) {}
        });
    }

    public void info(String s) { append(Level.INFO, s); }
    public void ok  (String s) { append(Level.OK,   s); }
    public void warn(String s) { append(Level.WARN, s); }
    public void err (String s) { append(Level.ERR,  s); }

    public void clear() {
        SwingUtilities.invokeLater(() -> pane.setText(""));
    }
}
