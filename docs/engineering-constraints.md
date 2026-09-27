# Engineering constraints

## Incomplete analysis cannot pass

The analyzer may report `PASS` only when it has fully interpreted every input
construct that can affect motion, coordinates, or the requested estimate.
Any unsupported or ambiguous construct that could change those results makes
the report `INCOMPLETE`; a later clean block cannot restore `PASS`.

Examples that require `INCOMPLETE` include:

- macros, parameter expressions, subprogram calls, and canned cycles;
- R-format arcs, arcs outside G17/XY, or malformed/unsupported arc geometry;
- G18/G19, G41/G42, G43, G52/G92, and other unsupported coordinate or tool
  transformations;
- an unknown G/M code that may affect execution state;
- a motion block before required plane, units, distance, arc-center, feed-mode,
  and work-coordinate modes are established;
- a feed move without a valid modal feed rate, or a time-affecting tool change
  when the profile has no tool-change duration (the latter makes the time
  estimate incomplete; geometric analysis can still be complete).

The implementation must express this rule in the report-status calculation
and test that unsupported or ambiguous input never produces `PASS`.

## Scope of a clean result

The supported profile is a three-axis mill using G54, G17, millimeter/inch
units, absolute/incremental endpoint coordinates, incremental I/J arc centers,
and G94 feed-per-minute. Travel checks cover programmed control points and
interpolated XY arc extrema. They do not account for tool radius, holder
geometry, tool length compensation, fixture geometry, controller lookahead,
acceleration, or actual cutting load. `PASS` means only that the supported
subset was completely analyzed without detected profile violations.
