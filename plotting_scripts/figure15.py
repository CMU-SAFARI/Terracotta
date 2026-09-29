"""Figure 15: Terracotta performance sensitivity to controller-latency overhead. Styled to PPT
chart19-22: one line per technique-panel, colored in that technique's Terracotta hue, with a
per-panel y-axis + ticks (different scales). PRADA = single-core PuM speedup; MoPAC-C/MASA/
ChargeCache = four-core weighted speedup normalized to baseline.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, sweep_line, style_axes,
                        panel_title, save_figure, guard_run, panels_in_order)

FIG_ID = 15
XLABEL = "Memory controller latency overhead (in cycles)"
YLABEL_PANEL = {"PRADA": "System Performance\nNormalized to Baseline"}
PANEL_COLOR = {"PRADA": "#636B2F", "MoPAC-C": "#0B3041", "MASA": "#C04F15", "ChargeCache": "#78206E",
               "ChargeCacheMASA": "#104862"}   # Fig 15's ChargeCacheMASA hue
AXIS = {"PRADA": (0.0, 125.0, 25.0), "MoPAC-C": (0.9, 1.0, 0.02),
        "MASA": (1.0, 1.08, 0.02), "ChargeCache": (0.98, 1.08, 0.02),
        "ChargeCacheMASA": (1.0, 1.08, 0.02)}
# ChargeCache: no baseline line at 1.000 (paper omits it); others coincide with a spine anyway.
BASELINE = {"PRADA": None, "MoPAC-C": 1.0, "MASA": 1.0, "ChargeCache": None, "ChargeCacheMASA": 1.0}
PANEL_TITLE = {"PRADA": "(a) PRADA", "MoPAC-C": "(b) MoPAC-C\n($T_{RH}$=250)",
                "MASA": "(c) MASA", "ChargeCache": "(d) ChargeCache",
                "ChargeCacheMASA": "(e) ChargeCache\nMASA"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    fig, axes = plt.subplots(1, len(panels), figsize=(1.0 * len(panels) + 0.6, 1.30),
                             squeeze=False, sharey=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel]
        base = BASELINE.get(panel, 1.0)
        # Paper shades the nominal 2-cycle operating point.
        sweep_line(ax, sub, baseline=base, shade=["2"],
                   colors={"Terracotta": PANEL_COLOR.get(panel, "#636B2F")})
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=YLABEL_PANEL.get(panel, ""), baseline=base,
                   ymin=ymin, ymax=ymax, major=major, box=True, ylabel_fs=6.0)
        panel_title(ax, PANEL_TITLE.get(panel, panel), fontsize=4.5)
    fig.supxlabel(XLABEL, fontsize=6.5, y=0.01)
    fig.subplots_adjust(top=0.72, bottom=0.24, wspace=0.68)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
