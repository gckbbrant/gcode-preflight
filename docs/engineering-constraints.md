# Engineering constraints

## Incomplete analysis cannot pass

The analyzer may report `PASS` only when it has fully interpreted every input
construct that can affect motion, coordinates, or the requested estimate.
Any unsupported or ambiguous construct that could change those results makes
the report `INCOMPLETE`; a later clean block cannot restore `PASS`.

Examples that require `INCOMPLETE` include:

- macros, parameter expressions, subprogram calls, and canned cycles;
- arcs outside G17/XY or unsupported arc geometry;
- G18/G19, G41/G42, G43, G52/G92, and other unsupported coordinate or tool
  transformations;
- an unknown G/M code that may affect execution state;
- a motion block before required units, distance, work-coordinate, and
  compensation-cancel modes are established; G53 linear moves require units
  and compensation-cancel modes but do not depend on G90/G91 or a work offset;
  other moves require an explicit work coordinate system; arcs require G17,
  I/J arcs require G90.1 or G91.1, and feed moves require G94;
- a selected G55-G59.3 system whose translation is absent from the profile;
- a profile work-system entry with nonzero XY rotation, which this analyzer
  does not transform;
- any movement when the starting position is unknown. Provide
  initial_position_g54_mm in the profile to identify the first machine point;
- unsupported semantics anywhere in the program, even when preceding moves
  were analyzable.

Fully understood program errors such as missing F/S, malformed I/J or R arc
geometry, G53 on an arc, missing G4 P, or a travel-limit violation produce
FAIL. A missing tool-change duration makes the time estimate incomplete while geometric
analysis can remain complete.

The implementation must express this rule in the report-status calculation
and test that unsupported or ambiguous input never produces `PASS`.

## Cycle-time estimate assumptions

The optional `axis_max_velocity_mm_per_min` and
`axis_max_acceleration_mm_per_sec2` profile vectors describe positive XYZ
limits in machine units. A supplied vector with a zero or negative component
makes the profile invalid and the report `INCOMPLETE`.

Without these vectors, preserve the nominal path-length estimate. Axis velocity
limits cap the requested G0 rapid or G1/G2/G3 feed by each moving axis's
direction component. With acceleration limits, estimate each programmed move
independently from rest to rest using a trapezoidal speed profile, or a
triangular profile when the move is too short to reach the capped speed. Arc
speed uses the XY tangent components and a centripetal-acceleration cap; half
of each configured axis acceleration is reserved for tangential acceleration
on arcs.

The report must identify its estimate model. This simplified model does not
simulate controller lookahead, G64 corner blending, jerk limits, spindle ramp,
feed override, or cutting load. Explicit path-control G-codes remain outside
the supported subset and therefore cannot produce `PASS`.

## Scope of a clean result

The supported profile is a three-axis mill using G54-G59.3 with configured
XYZ translations, non-modal G53 linear moves, G17, millimeter/inch units,
absolute/incremental endpoint coordinates, absolute/incremental I/J arc
centers, signed R-format arcs, and G94 feed-per-minute. G53 always addresses
machine coordinates and applies to one block; its next move returns to the
selected work system. Rotated work systems are not modeled. An I/J arc
requires an explicit G90.1 or G91.1 mode; G90.1 requires both I and J. Positive
R selects a sweep up to 180 degrees; negative R selects a sweep greater than
180 degrees. R format requires distinct XY endpoints, so full circles use I/J
centers. R arcs within
15 degrees of a half or full circle receive a non-blocking rounding-sensitivity
warning. The profile's optional initial_position_g54_mm field
is required for programs that move; it is a G54 coordinate in millimeters and
is converted to machine coordinates using g54_offset_mm. Other work positions
use their matching additional_work_offsets_mm entry. Travel checks cover
programmed control points and interpolated XY arc extrema. They do not account
for tool radius, holder geometry, tool length compensation, fixture geometry,
controller lookahead, acceleration, or actual cutting load. `PASS` means only
that the supported subset was completely analyzed without detected profile
violations.

Travel-limit diagnostics carry the exact machine-space point in `point_mm`.
The report also carries the configured X/Y/Z limits so `render_svg(report)` can
draw the XY envelope and highlight each violating move and point without
parsing human-readable diagnostic messages. A Z violation is marked at its XY
projection and includes the Z value in the marker title.
