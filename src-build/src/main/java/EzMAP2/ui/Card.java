package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;

/**
 * A titled surface card: white background, subtle rounded border, an uppercase
 * caption, and a content area. Use for grouping related controls on a page.
 */
public class Card extends JPanel {

    private final JPanel content;

    public Card(String title) {
        super(new BorderLayout(0, 10));
        setOpaque(true);
        setBackground(Theme.SURFACE);
        setBorder(Theme.cardBorder());

        if (title != null && !title.isEmpty()) {
            JLabel caption = new JLabel(title.toUpperCase());
            caption.setFont(Theme.FONT_LABEL);
            caption.setForeground(Theme.INK_3);
            add(caption, BorderLayout.NORTH);
        }

        content = new JPanel();
        content.setOpaque(false);
        content.setLayout(new BoxLayout(content, BoxLayout.Y_AXIS));
        add(content, BorderLayout.CENTER);
    }

    /** Add a component to the card body. */
    public Card row(Component c) {
        if (c instanceof JComponent) ((JComponent) c).setAlignmentX(LEFT_ALIGNMENT);
        content.add(c);
        return this;
    }

    public Card gap(int px) {
        content.add(Box.createVerticalStrut(px));
        return this;
    }
}
