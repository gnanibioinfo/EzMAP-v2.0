package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;

/** Filled teal button — the main call-to-action. */
public class PrimaryButton extends JButton {

    public PrimaryButton(String text) {
        super(text);
        setFont(Theme.FONT_BUTTON);
        setForeground(Color.WHITE);
        setBackground(Theme.PRIMARY);
        setFocusPainted(false);
        setBorderPainted(false);
        setOpaque(true);
        setBorder(BorderFactory.createEmptyBorder(
                Theme.PAD_BUTTON.top, Theme.PAD_BUTTON.left,
                Theme.PAD_BUTTON.bottom, Theme.PAD_BUTTON.right));
        setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));

        addMouseListener(new MouseAdapter() {
            @Override public void mouseEntered(MouseEvent e) {
                if (isEnabled()) setBackground(Theme.PRIMARY_DARK);
            }
            @Override public void mouseExited(MouseEvent e) {
                setBackground(Theme.PRIMARY);
            }
        });
    }

    @Override public void setEnabled(boolean b) {
        super.setEnabled(b);
        setBackground(b ? Theme.PRIMARY : new Color(0xCB, 0xD5, 0xE1));
        setForeground(b ? Color.WHITE : Theme.INK_3);
        setCursor(Cursor.getPredefinedCursor(b ? Cursor.HAND_CURSOR : Cursor.DEFAULT_CURSOR));
    }
}
