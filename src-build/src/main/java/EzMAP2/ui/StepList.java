package EzMAP2.ui;

import javax.swing.*;
import java.awt.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Vertical wizard step list for the sidebar. Steps have three states:
 * DONE, ACTIVE, TODO — visually distinct.
 */
public class StepList extends JPanel {

    public enum State { DONE, ACTIVE, TODO }

    public static final List<String> DEFAULT_STEPS = Arrays.asList(
            "Environment Setup",
            "Choose Mode",
            "Manifest File",
            "Import Sequences",
            "Quality Assessment",
            "Denoising (DADA2)",
            "Taxonomy",
            "Downstream Analysis"
    );

    public static final List<String> EASY_STEPS = Arrays.asList(
            "Environment Setup",
            "Choose Mode",
            "Easy Mode Pipeline",
            "Results & Downloads"
    );

    private final List<JPanel> rows = new ArrayList<>();
    private List<String> labels;
    private int activeIndex = 0;
    private JLabel titleLbl;

    public StepList() { this(DEFAULT_STEPS); }

    public StepList(List<String> stepLabels) {
        this.labels = stepLabels;
        setOpaque(false);
        setLayout(new BoxLayout(this, BoxLayout.Y_AXIS));
        setBorder(BorderFactory.createEmptyBorder(8, 10, 8, 10));

        titleLbl = new JLabel("WORKFLOW");
        titleLbl.setFont(Theme.FONT_LABEL);
        titleLbl.setForeground(new Color(255, 255, 255, 140));
        titleLbl.setBorder(BorderFactory.createEmptyBorder(6, 8, 8, 8));
        titleLbl.setAlignmentX(LEFT_ALIGNMENT);
        add(titleLbl);

        rebuildRows();
    }

    /** Replace the step labels and rebuild the row widgets in place. */
    public void setLabels(List<String> newLabels) {
        this.labels = newLabels;
        if (activeIndex >= labels.size()) activeIndex = labels.size() - 1;
        rebuildRows();
    }

    private void rebuildRows() {
        for (JPanel row : rows) remove(row);
        rows.clear();
        for (int i = 0; i < labels.size(); i++) {
            JPanel row = buildRow(i, labels.get(i));
            rows.add(row);
            add(row);
        }
        refresh();
    }

    public void setActive(int index) {
        this.activeIndex = index;
        refresh();
    }

    public int getActive() { return activeIndex; }

    private JPanel buildRow(int index, String text) {
        JPanel row = new JPanel(new BorderLayout(10, 0));
        row.setOpaque(true);
        row.setBorder(BorderFactory.createEmptyBorder(8, 10, 8, 10));
        row.setAlignmentX(LEFT_ALIGNMENT);
        row.setMaximumSize(new Dimension(Integer.MAX_VALUE, 40));

        JLabel num = new JLabel(String.valueOf(index + 1), SwingConstants.CENTER);
        num.setPreferredSize(new Dimension(22, 22));
        num.setOpaque(true);
        num.setFont(Theme.FONT_LABEL);
        row.add(num, BorderLayout.WEST);

        JLabel lab = new JLabel(text);
        lab.setFont(Theme.FONT_BODY);
        row.add(lab, BorderLayout.CENTER);
        return row;
    }

    private void refresh() {
        for (int i = 0; i < rows.size(); i++) {
            JPanel row = rows.get(i);
            JLabel num = (JLabel) row.getComponent(0);
            JLabel lab = (JLabel) row.getComponent(1);

            State s = i < activeIndex ? State.DONE
                    : i == activeIndex ? State.ACTIVE
                    : State.TODO;

            switch (s) {
                case DONE:
                    row.setBackground(new Color(0, 0, 0, 0));
                    lab.setForeground(new Color(255, 255, 255, 220));
                    num.setBackground(new Color(0x10, 0xB9, 0x81));
                    num.setForeground(Color.WHITE);
                    num.setText("\u2713");
                    break;
                case ACTIVE:
                    row.setBackground(new Color(255, 255, 255, 38));
                    lab.setForeground(Color.WHITE);
                    lab.setFont(Theme.FONT_BODY_BOLD);
                    num.setBackground(Color.WHITE);
                    num.setForeground(Theme.PRIMARY_DARK);
                    num.setText(String.valueOf(i + 1));
                    break;
                case TODO:
                default:
                    row.setBackground(new Color(0, 0, 0, 0));
                    lab.setForeground(new Color(255, 255, 255, 140));
                    lab.setFont(Theme.FONT_BODY);
                    num.setBackground(new Color(255, 255, 255, 30));
                    num.setForeground(new Color(255, 255, 255, 200));
                    num.setText(String.valueOf(i + 1));
                    break;
            }
            // round the number pill
            num.setBorder(BorderFactory.createEmptyBorder());
        }
        revalidate();
        repaint();
    }
}
