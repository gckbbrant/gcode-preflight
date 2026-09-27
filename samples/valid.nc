%
(Three-axis contour with a rapid approach, feed moves, and XY arcs)
G21 G90 G17 G91.1 G94 G54 G40 G49
S12000 M3
T1 M6
G0 X10 Y10 Z5
G1 Z-1 F300
G1 X50 Y10
G2 X60 Y20 I0 J10
G3 X50 Y30 I-10 J0
G0 Z5
M5
M30
%
