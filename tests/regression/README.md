# Regression corpus

`cases.json` is an executable, reviewable contract for representative
programs. It checks status, motion kinds, path length, arc sweep, estimate
completeness, diagnostic codes/source lines, and exact points used by the SVG.
Run it with:

```sh
python3 scripts/check_regression_corpus.py
```

The three `linuxcnc-*.nc` programs adapt center-format examples from the
[LinuxCNC G-code reference](https://linuxcnc.org/docs/html/gcode.html): a CW/CCW
pair, a full circle, and an XY helical arc. The remaining fixtures cover
incremental coordinates, inch-to-mm conversion with G54 offset, dwell/tool
change, missing feed, and an arc whose endpoints fit while its interior
cardinal points exceed the configured X travel. The R-format cases cover
positive minor and negative major sweeps, a helical arc, inch conversion,
interior travel violations, impossible chords, and rejection of R full circles.
The diametric arc fixture also confirms the rounding-sensitivity warning does
not change a valid program's PASS status.

The corpus stays within the project's explicitly supported subset. It records
expected behavior; it is not a general certification of arbitrary controller
dialects.
