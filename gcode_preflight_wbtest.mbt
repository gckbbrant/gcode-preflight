///|
fn test_profile_with(
  initial : Vec3?,
  offset : Vec3,
  x_max : Double,
  y_max : Double,
) -> MachineProfile {
  {
    x: { min: -100.0, max: x_max, },
    y: { min: -100.0, max: y_max, },
    z: { min: -100.0, max: 100.0, },
    g54_offset_mm: offset,
    initial_position_g54_mm: initial,
    rapid_mm_per_min: 3000.0,
    arc_tolerance_mm: 0.01,
    tool_change_seconds: Some(15.0),
  }
}

///|
fn test_profile() -> MachineProfile {
  test_profile_with(
    Some({ x: 0.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
}

///|
test "lexer accepts compact words and ignores both comment styles" {
  let parsed = parse_program("(job)\nN10G1X1.25Y-2.5F100 (cut) ; tail\n")
  assert_eq(parsed.blocks.length(), 1)
  assert_eq(parsed.blocks[0].words.length(), 5)
  assert_eq(parsed.blocks[0].words[1].address, 'G')
  assert_eq(parsed.blocks[0].words[2].value, 1.25)
  assert_eq(parsed.blocks[0].words[3].value, -2.5)
  assert_eq(parsed.diagnostics.length(), 0)
}

///|
test "modal preamble makes a feed move interpretable" {
  let report = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49\nG1 X1 Y2 F100\nM2",
    test_profile(),
  )
  assert_eq(report.diagnostics.length(), 0)
}

///|
test "rapid moves do not require arc-center or feed modes" {
  let report = analyze("G21 G90 G54 G40 G49 G0 X1 Y2", test_profile())
  assert_eq(report.diagnostics.length(), 0)
}

///|
test "missing setup modes are incomplete" {
  let report = analyze("G1 X1 F100", test_profile())
  assert_true(
    report.diagnostics.any(d => d.code == "MISSING_MODAL_SETUP" && d.incomplete),
  )
  assert_true(
    report.diagnostics.any(d => {
      d.code == "MISSING_MODAL_SETUP" && d.message.contains("G54")
    }),
  )
}

///|
test "conflicting motion modes are incomplete" {
  let report = analyze("G0 G1 X1", test_profile())
  assert_true(
    report.diagnostics.any(d => {
      d.code == "CONFLICTING_MODAL_CODES" && d.incomplete
    }),
  )
}

///|
test "unknown motion-affecting code is incomplete" {
  let report = analyze("G17 G21 G90 G91.1 G94 G54 G40 G49 G71", test_profile())
  assert_true(
    report.diagnostics.any(d => d.code == "UNSUPPORTED_G_CODE" && d.incomplete),
  )
  assert_true(report.status == Incomplete)
}

///|
test "feed and spindle omissions are detected as program errors" {
  let report = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49\nG1 X1\nM3",
    test_profile(),
  )
  assert_true(
    report.diagnostics.any(d => d.code == "MISSING_FEED" && !d.incomplete),
  )
  assert_true(
    report.diagnostics.any(d => {
      d.code == "MISSING_SPINDLE_SPEED" && !d.incomplete
    }),
  )
}

///|
test "macro expressions remain incomplete" {
  let report = analyze("G17 G21 G90 G54 G40 G49 G1 X#1", test_profile())
  assert_true(
    report.diagnostics.any(d => d.code == "MACRO_UNSUPPORTED" && d.incomplete),
  )
  assert_true(report.status == Incomplete)
}

///|
test "inch coordinates and G54 offset convert to machine millimeters" {
  let profile = test_profile_with(
    Some({ x: 0.0, y: 0.0, z: 0.0, }),
    { x: 5.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let report = analyze("G20 G90 G54 G40 G49 G0 X1 Y0 Z0", profile)
  assert_eq(report.segments.length(), 1)
  assert_true((report.segments[0].start_mm.x - 5.0).abs() < 0.000001)
  assert_true((report.segments[0].end_mm.x - 30.4).abs() < 0.000001)
  assert_true((report.distance_mm - 25.4).abs() < 0.000001)
}

///|
test "absolute and incremental coordinates share the programmed endpoint" {
  let report = analyze(
    "G21 G90 G54 G40 G49 G94\nG0 X10 Y0 Z0\nG91 G1 X2 F120",
    test_profile(),
  )
  assert_eq(report.segments.length(), 2)
  assert_true((report.segments[0].end_mm.x - 10.0).abs() < 0.000001)
  assert_true((report.segments[1].end_mm.x - 12.0).abs() < 0.000001)
  assert_true((report.distance_mm - 12.0).abs() < 0.000001)
}

///|
test "clockwise and counterclockwise I/J arcs choose opposite sweeps" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let setup = "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\n"
  let cw = analyze(setup + "G2 X0 Y10 I-10 J0", profile)
  let ccw = analyze(setup + "G3 X0 Y10 I-10 J0", profile)
  assert_eq(cw.segments.length(), 1)
  assert_eq(ccw.segments.length(), 1)
  assert_true(cw.segments[0].sweep_radians < 0.0)
  assert_true(ccw.segments[0].sweep_radians > 0.0)
  assert_true((cw.distance_mm - 15.0 * @math.PI).abs() < 0.000001)
  assert_true((ccw.distance_mm - 5.0 * @math.PI).abs() < 0.000001)
}

///|
test "G90.1 uses absolute arc centers in the active G54 coordinates" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 5.0, y: 6.0, z: 0.0, },
    100.0,
    100.0,
  )
  let report = analyze(
    "G17 G21 G90 G90.1 G94 G54 G40 G49 F100\nG3 X0 Y10 I0 J0", profile,
  )
  assert_true(report.status is Pass)
  assert_eq(report.segments.length(), 1)
  assert_true((report.segments[0].center_mm.unwrap().x - 5.0).abs() < 0.000001)
  assert_true((report.segments[0].center_mm.unwrap().y - 6.0).abs() < 0.000001)
  assert_true((report.segments[0].end_mm.x - 5.0).abs() < 0.000001)
  assert_true((report.segments[0].end_mm.y - 16.0).abs() < 0.000001)
  assert_true((report.distance_mm - 5.0 * @math.PI).abs() < 0.000001)
}

///|
test "G90.1 center coordinates convert inches before applying G54 offset" {
  let profile = test_profile_with(
    Some({ x: 25.4, y: 0.0, z: 0.0, }),
    { x: 5.08, y: 6.35, z: 0.0, },
    100.0,
    100.0,
  )
  let report = analyze(
    "G17 G20 G90 G90.1 G94 G54 G40 G49 F10\nG3 X0 Y1 I0 J0", profile,
  )
  assert_true(report.status is Pass)
  assert_true((report.segments[0].center_mm.unwrap().x - 5.08).abs() < 0.000001)
  assert_true((report.segments[0].center_mm.unwrap().y - 6.35).abs() < 0.000001)
  assert_true((report.distance_mm - 12.7 * @math.PI).abs() < 0.000001)
}

///|
test "G90.1 requires both center coordinates and conflicts with G91.1" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let setup = "G17 G21 G90 G90.1 G94 G54 G40 G49 F100\n"
  let missing_j = analyze(setup + "G3 X0 Y10 I0", profile)
  assert_true(missing_j.status is Fail)
  assert_true(missing_j.diagnostics.any(d => d.code == "ARC_CENTER_REQUIRED"))
  let conflict = analyze("G90.1 G91.1", test_profile())
  assert_true(conflict.status is Incomplete)
  assert_true(
    conflict.diagnostics.any(d => d.code == "CONFLICTING_MODAL_CODES"),
  )
}

///|
test "I/J arcs require an explicit absolute or incremental center mode" {
  let report = analyze(
    "G17 G21 G90 G94 G54 G40 G49 F100\nG3 X0 Y10 I-10 J0",
    test_profile_with(
      Some({ x: 10.0, y: 0.0, z: 0.0, }),
      { x: 0.0, y: 0.0, z: 0.0, },
      100.0,
      100.0,
    ),
  )
  assert_true(report.status is Incomplete)
  assert_true(
    report.diagnostics.any(d => {
      d.code == "MISSING_MODAL_SETUP" && d.message.contains("G90.1 or G91.1")
    }),
  )
}

///|
test "signed R arcs select minor and major sweeps without G91.1" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let setup = "G17 G21 G90 G94 G54 G40 G49 F100\n"
  let ccw_minor = analyze(setup + "G3 X5 Y8.660254037844386 R10", profile)
  let ccw_major = analyze(setup + "G3 X5 Y8.660254037844386 R-10", profile)
  let cw_minor = analyze(setup + "G2 X5 Y8.660254037844386 R10", profile)
  let cw_major = analyze(setup + "G2 X5 Y8.660254037844386 R-10", profile)
  assert_true(ccw_minor.status is Pass)
  assert_true(ccw_major.status is Pass)
  assert_true(cw_minor.status is Pass)
  assert_true(cw_major.status is Pass)
  assert_true(
    (ccw_minor.segments[0].sweep_radians - @math.PI / 3.0).abs() < 0.000001,
  )
  assert_true(
    (ccw_major.segments[0].sweep_radians - 5.0 * @math.PI / 3.0).abs() <
    0.000001,
  )
  assert_true(
    (cw_minor.segments[0].sweep_radians + @math.PI / 3.0).abs() < 0.000001,
  )
  assert_true(
    (cw_major.segments[0].sweep_radians + 5.0 * @math.PI / 3.0).abs() < 0.000001,
  )
  assert_true((ccw_minor.distance_mm - 10.0 * @math.PI / 3.0).abs() < 0.000001)
}

///|
test "R arcs reject invalid chords, full circles, mixed formats, and non-arcs" {
  let origin_profile = test_profile()
  let invalid_chord = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X20 Y0 R5", origin_profile,
  )
  assert_true(invalid_chord.status is Fail)
  assert_true(invalid_chord.diagnostics.any(d => d.code == "INVALID_R_ARC"))
  let zero_radius = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X1 Y0 R0", origin_profile,
  )
  assert_true(zero_radius.status is Fail)
  assert_true(zero_radius.diagnostics.any(d => d.code == "INVALID_R_ARC"))
  let start_profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let full_circle = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X10 Y0 R10", start_profile,
  )
  assert_true(full_circle.status is Fail)
  assert_true(full_circle.diagnostics.any(d => d.code == "INVALID_R_ARC"))
  let mixed = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X5 Y8.660254 I-10 J0 R10", start_profile,
  )
  assert_true(mixed.status is Fail)
  assert_true(mixed.diagnostics.any(d => d.code == "CONFLICTING_ARC_FORMATS"))
  let radius_without_arc = analyze(
    "G17 G21 G90 G94 G54 G40 G49 F100\nG1 X5 R10", origin_profile,
  )
  assert_true(radius_without_arc.status is Incomplete)
  assert_true(
    radius_without_arc.diagnostics.any(d => d.code == "R_WITHOUT_ARC"),
  )
  let duplicate_radius = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X5 Y5 R5 R5", origin_profile,
  )
  assert_true(duplicate_radius.status is Incomplete)
  assert_true(duplicate_radius.diagnostics.any(d => d.code == "DUPLICATE_WORD"))
}

///|
test "R-format diametric arcs are valid only for the positive minor form" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let setup = "G17 G21 G90 G94 G54 G40 G49 F100\n"
  let positive = analyze(setup + "G3 X-10 Y0 R10", profile)
  let negative = analyze(setup + "G3 X-10 Y0 R-10", profile)
  assert_true(positive.status is Pass)
  assert_true((positive.segments[0].sweep_radians - @math.PI).abs() < 0.000001)
  assert_true(
    positive.diagnostics.any(d => d.code == "R_ARC_ROUNDING_SENSITIVE"),
  )
  assert_true(negative.status is Fail)
  assert_true(negative.diagnostics.any(d => d.code == "INVALID_R_ARC"))
  let tiny_minor = analyze(
    setup + "G3 X9.961946980917455 Y0.871557427476582 R10",
    profile,
  )
  let near_full = analyze(
    setup + "G3 X9.961946980917455 Y0.871557427476582 R-10",
    profile,
  )
  assert_true(tiny_minor.status is Pass)
  assert_true(
    !tiny_minor.diagnostics.any(d => d.code == "R_ARC_ROUNDING_SENSITIVE"),
  )
  assert_true(near_full.status is Pass)
  assert_true(
    near_full.diagnostics.any(d => d.code == "R_ARC_ROUNDING_SENSITIVE"),
  )
}

///|
test "full-circle and helical arcs include circumference and Z travel" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let setup = "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\n"
  let full = analyze(setup + "G3 I-10 J0", profile)
  let helix = analyze(setup + "G3 X10 Y0 Z5 I-10 J0", profile)
  assert_eq(full.segments.length(), 1)
  assert_true((full.distance_mm - 20.0 * @math.PI).abs() < 0.000001)
  assert_true(
    (helix.distance_mm - (400.0 * @math.PI * @math.PI + 25.0).sqrt()).abs() <
    0.000001,
  )
}

///|
test "arc cardinal extrema are checked against axis travel" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    8.0,
  )
  let report = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X0 Y10 I-10 J0", profile,
  )
  assert_true(report.diagnostics.any(d => d.code == "TRAVEL_LIMIT_Y"))
  assert_true(report.status == Fail)
  assert_true(report.travel_limits.y.max == 8.0)
  let has_exact_violation_point = report.diagnostics.any(d => {
    if d.code == "TRAVEL_LIMIT_Y" {
      match d.point_mm {
        Some(point) =>
          point.x.abs() < 0.000001 &&
          (point.y - 10.0).abs() < 0.000001 &&
          point.z == 0.0
        None => false
      }
    } else {
      false
    }
  })
  assert_true(has_exact_violation_point)
  let svg = render_svg(report)
  assert_true(svg.contains("class=\"travel-limit\""))
  assert_true(svg.contains("class=\"arc-ccw violation\""))
  assert_true(svg.contains("class=\"violation-point\""))
}

///|
test "bad radius and missing initial position cannot pass" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let bad_arc = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG3 X0 Y9 I-10 J0", profile,
  )
  assert_true(bad_arc.diagnostics.any(d => d.code == "INVALID_ARC_RADIUS"))
  let no_start = analyze(
    "G21 G90 G54 G40 G49 G0 X1 Y1 Z0",
    test_profile_with(None, { x: 0.0, y: 0.0, z: 0.0, }, 100.0, 100.0),
  )
  assert_true(
    no_start.diagnostics.any(d => d.code == "UNKNOWN_INITIAL_POSITION"),
  )
  assert_true(no_start.status != Pass)
}

///|
test "cycle time includes rapid, feed, dwell, and configured tool change" {
  let report = analyze(
    "G21 G90 G54 G40 G49 G94 F600\nG0 X10 Y0 Z0\nG1 X20 F600\nG4 P2\nT1 M6\nM2",
    test_profile(),
  )
  assert_true(report.analysis_complete)
  assert_true(report.estimate_complete)
  assert_true(report.status is Pass)
  assert_eq(report.tool_changes, 1)
  assert_true((report.dwell_seconds - 2.0).abs() < 0.000001)
  assert_true((report.estimated_time_seconds.unwrap() - 18.2).abs() < 0.000001)
}

///|
test "missing tool-change duration leaves an incomplete estimate" {
  let profile = { ..test_profile(), tool_change_seconds: None, }
  let report = analyze("G21 G90 G54 G40 G49 T1 M6", profile)
  assert_true(report.analysis_complete)
  assert_true(!report.estimate_complete)
  assert_true(report.status is Incomplete)
  assert_true(
    report.diagnostics.any(d => {
      d.code == "MISSING_TOOL_CHANGE_DURATION" && d.incomplete
    }),
  )
}

///|
test "SVG contains linear and arc commands with status" {
  let profile = test_profile_with(
    Some({ x: 10.0, y: 0.0, z: 0.0, }),
    { x: 0.0, y: 0.0, z: 0.0, },
    100.0,
    100.0,
  )
  let report = analyze(
    "G17 G21 G90 G91.1 G94 G54 G40 G49 F100\nG1 X10 Y10\nG2 X0 Y0 I-10 J0\nG71",
    profile,
  )
  let svg = render_svg(report)
  assert_true(svg.has_prefix("<svg"))
  assert_true(svg.contains("class=\"linear\""))
  assert_true(svg.contains("class=\"arc-cw\""))
  assert_true(svg.contains("CNC G-code Preflight — INCOMPLETE"))
  assert_true(svg.contains(" A "))
}

///|
test "SVG labels incomplete programs without drawing a misleading path" {
  let report = analyze("G71", test_profile())
  let svg = render_svg(report)
  assert_true(svg.contains("INCOMPLETE"))
  assert_true(!svg.contains("<path "))
}
