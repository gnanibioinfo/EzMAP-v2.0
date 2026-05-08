package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;

/**
 * Colored banner used to show environment state or contextual info
 * (e.g. "Windows detected — running via WSL").
 */
public class InfoBanner extends JPanel {

    public enum Kind { INFO, SUCCESS, WARNING, DANGER }

    public InfoBanner(Kind kind, String title, String body) {
        super(new BorderLayout(14, 0));
        setOpaque(true);

        Color bg, border, iconBg, iconFg;
        String glyph;
        switch (kind) {
            case SUCCESS: bg = Theme.PRIMARY_SOFT; border = Theme.PRIMARY_BORDER; iconBg = Color.WHITE; iconFg = Theme.PRIMARY_DARK; glyph = "\u2713"; break;
            case WARNING: bg = new Color(0xFF, 0xF7, 0xE6); border = new Color(0xFC, 0xD3, 0x4D); iconBg = Color.WHITE; iconFg = Theme.WARNING;  glyph = "!"; break;
            case DANGER:  bg = new Color(0xFE, 0xE2, 0xE2); border = new Color(0xFC, 0xA5, 0xA5); iconBg = Color.WHITE; iconFg = Theme.DANGER;   glyph = "\u00D7"; break;
            case INFO:
            default:      bg = new Color(0xEF, 0xF6, 0xFF); border = new Color(0xBF, 0xDB, 0xFE); iconBg = Color.WHITE; iconFg = Theme.ACCENT;   glyph = "i"; break;
        }

        setBackground(bg);
        setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(border, 1, true),
                BorderFactory.createEmptyBorder(12, 14, 12, 14)));

        JLabel icon = new JLabel(glyph, SwingConstants.CENTER);
        icon.setPreferredSize(new Dimension(36, 36));
        icon.setOpaque(true);
        icon.setBackground(iconBg);
        icon.setForeground(iconFg);
        icon.setFont(Theme.FONT_BODY_BOLD.deriveFont(16f));
        icon.setBorder(BorderFactory.createLineBorder(border, 1, true));
        add(icon, BorderLayout.WEST);

        JPanel textCol = new JPanel();
        textCol.setOpaque(false);
        textCol.setLayout(new BoxLayout(textCol, BoxLayout.Y_AXIS));
        JLabel t = new JLabel(title);
        t.setFont(Theme.FONT_BODY_BOLD);
        t.setForeground(Theme.INK_1);
        JLabel b = new JLabel("<html>" + body + "</html>");
        b.setFont(Theme.FONT_SMALL);
        b.setForeground(Theme.INK_3);
        textCol.add(t);
        textCol.add(Box.createVerticalStrut(2));
        textCol.add(b);
        add(textCol, BorderLayout.CENTER);
    }
}
