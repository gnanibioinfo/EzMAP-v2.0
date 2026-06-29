package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ComponentAdapter;
import java.awt.event.ComponentEvent;

/**
 * Colored banner used to show environment state or contextual info
 * (e.g. "Windows detected — running via WSL").
 *
 * The body text wraps responsively to the banner's current width so a long
 * message never forces the page wider than the viewport (which would clip
 * controls such as the Browse buttons on the right edge).
 */
public class InfoBanner extends JPanel {

    public enum Kind { INFO, SUCCESS, WARNING, DANGER }

    // Width (px) of the fixed elements left of the wrapping text:
    // icon (36) + BorderLayout hgap (14) + left/right empty border (14+14)
    // + line border (~2) plus a small safety margin.
    private static final int TEXT_INSET = 90;

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
        final String bodyText = body == null ? "" : body;
        final JLabel b = new JLabel(wrapHtml(bodyText, 400));
        b.setFont(Theme.FONT_SMALL);
        b.setForeground(Theme.INK_3);
        textCol.add(t);
        textCol.add(Box.createVerticalStrut(2));
        textCol.add(b);
        add(textCol, BorderLayout.CENTER);

        // Re-wrap the body text to the actual available width whenever the
        // banner is resized. Starting from a modest 400px keeps the initial
        // preferred width small so the banner never pushes the page wider than
        // the viewport; once laid out it expands to fill the available width.
        addComponentListener(new ComponentAdapter() {
            @Override public void componentResized(ComponentEvent e) {
                int avail = getWidth() - TEXT_INSET;
                if (avail < 160) avail = 160;
                b.setText(wrapHtml(bodyText, avail));
            }
        });
    }

    /** Wrap plain body text in fixed-width HTML so the JLabel reflows. */
    private static String wrapHtml(String body, int widthPx) {
        return "<html><body style='width:" + widthPx + "px'>" + body + "</body></html>";
    }
}
