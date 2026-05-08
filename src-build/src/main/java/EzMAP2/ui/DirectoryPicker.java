package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.io.File;
import java.util.function.Consumer;

/** TextField + Browse button combo for selecting a directory or file. */
public class DirectoryPicker extends JPanel {

    private final JTextField field = new JTextField();
    private final OutlineButton browse = new OutlineButton("Browse\u2026");
    private final boolean filesOnly;
    private File startDir = null;  // default start directory for file chooser

    public DirectoryPicker(String placeholder, Consumer<File> onPick) {
        this(placeholder, onPick, false);
    }

    /** @param filesOnly when true, the chooser selects files instead of directories. */
    public DirectoryPicker(String placeholder, Consumer<File> onPick, boolean filesOnly) {
        super(new BorderLayout(8, 0));
        setOpaque(false);
        this.filesOnly = filesOnly;

        field.setFont(Theme.FONT_MONO);
        field.setEditable(false);
        field.setForeground(Theme.INK_2);
        field.setBackground(Theme.SURFACE_2);
        field.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(Theme.BORDER, 1, true),
                BorderFactory.createEmptyBorder(8, 10, 8, 10)));
        if (placeholder != null) field.putClientProperty("JTextField.placeholderText", placeholder);

        browse.addActionListener(e -> {
            JFileChooser fc = new JFileChooser();
            fc.setFileSelectionMode(filesOnly ? JFileChooser.FILES_ONLY : JFileChooser.DIRECTORIES_ONLY);
            fc.setDialogTitle(filesOnly ? "Select file" : "Select directory");

            // Set starting directory: explicit startDir > current field value > user home
            if (startDir != null && startDir.isDirectory()) {
                fc.setCurrentDirectory(startDir);
            } else if (!isEmpty()) {
                File current = new File(getPath());
                if (current.isDirectory()) {
                    fc.setCurrentDirectory(current);
                } else if (current.getParentFile() != null && current.getParentFile().isDirectory()) {
                    fc.setCurrentDirectory(current.getParentFile());
                }
            }

            if (fc.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
                File f = fc.getSelectedFile();
                field.setText(f.getAbsolutePath());
                if (onPick != null) onPick.accept(f);
            }
        });

        add(field, BorderLayout.CENTER);
        add(browse, BorderLayout.EAST);

        // Fixed height so it doesn't stretch in BoxLayout
        setMaximumSize(new Dimension(Short.MAX_VALUE, 40));
    }

    public String getPath()            { return field.getText(); }
    public void   setPath(String path) { field.setText(path); }
    public boolean isEmpty()           { return field.getText() == null || field.getText().isEmpty(); }

    /**
     * Set the default starting directory for the file chooser.
     * When the user clicks Browse, the dialog will open here.
     */
    public void setStartDirectory(File dir) {
        this.startDir = dir;
    }

    /** Convenience: set start directory from a path string. */
    public void setStartDirectory(String path) {
        if (path != null && !path.isEmpty()) {
            this.startDir = new File(path);
        }
    }
}
