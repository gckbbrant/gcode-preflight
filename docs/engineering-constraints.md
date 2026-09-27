# Engineering constraints

## Incomplete analysis cannot pass

The analyzer may report `PASS` only when it has fully interpreted every input
construct that can affect motion, coordinates, or the requested estimate.
Any unsupported or ambiguous construct that could change those results makes
the report `INCOMPLETE`; a later clean block cannot restore `PASS`.

Examples that require `INCOMPLETE` include:

- macros, parameter expressions, subprogram calls, and canned cycles;
- R-format arcs, arcs outside G17/XY, or unsupported arc geometry;
- G18/G19, G41/G42, G43, G52/G92, and other unsupported coordinate or tool
  transformations;
- an unknown G/M code that may affect execution state;
- a motion block before required units, distance, work-coordinate, and
  compensation-cancel modes are established; arcs additionally require G17 and
  G91.1, and feed moves require G94;
- any movement when the starting position is unknown. Provide
  initial_position_g54_mm in the profile to identify the first machine point;
- unsupported semantics anywhere in the program, even when preceding moves
  were analyzable.

Fully understood program errors such as missing F/S, malformed I/J radius,
missing G4 P, or a travel-limit violation produce FAIL. A missing tool-change
duration makes the time estimate incomplete while geometric analysis can
remain complete.

The implementation must express this rule in the report-status calculation
and test that unsupported or ambiguous input never produces `PASS`.

## Scope of a clean result

The supported profile is a three-axis mill using G54, G17, millimeter/inch
units, absolute/incremental endpoint coordinates, incremental I/J arc centers,
and G94 feed-per-minute. The profile's optional initial_position_g54_mm field
is required for programs that move; it is a G54 coordinate in millimeters and
is converted to machine coordinates using g54_offset_mm. Travel checks cover
programmed control points and interpolated XY arc extrema. They do not account for tool radius, holder
geometry, tool length compensation, fixture geometry, controller lookahead,
acceleration, or actual cutting load. `PASS` means only that the supported
subset was completely analyzed without detected profile violations.
