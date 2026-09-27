///|
fn has_word(block : GCodeBlock, address : Char) -> Bool {
  block_word(block, address) is Some(_)
}

///|
fn units_factor(state : ModalState) -> Double? {
  match state.units_mm {
    Some(true) => Some(1.0)
    Some(false) => Some(25.4)
    None => None
  }
}

///|
fn endpoint_from_words(
  start : Vec3,
  block : GCodeBlock,
  state : ModalState,
  profile : MachineProfile,
) -> Vec3? {
  let factor = match units_factor(state) {
    Some(factor) => factor
    None => return None
  }
  let absolute = match state.absolute {
    Some(absolute) => absolute
    None => return None
  }
  let offset = profile.g54_offset_mm
  let x = match block_word(block, 'X') {
    Some(value) =>
      if absolute {
        value * factor + offset.x
      } else {
        start.x + value * factor
      }
    None => start.x
  }
  let y = match block_word(block, 'Y') {
    Some(value) =>
      if absolute {
        value * factor + offset.y
      } else {
        start.y + value * factor
      }
    None => start.y
  }
  let z = match block_word(block, 'Z') {
    Some(value) =>
      if absolute {
        value * factor + offset.z
      } else {
        start.z + value * factor
      }
    None => start.z
  }
  Some({ x, y, z, })
}

///|
fn point_from_full_absolute_words(
  block : GCodeBlock,
  state : ModalState,
  profile : MachineProfile,
) -> Vec3? {
  if !(has_word(block, 'X') && has_word(block, 'Y') && has_word(block, 'Z')) {
    return None
  }
  if !(state.absolute is Some(true)) {
    return None
  }
  let factor = match units_factor(state) {
    Some(factor) => factor
    None => return None
  }
  Some({
    x: block_word(block, 'X').unwrap() * factor + profile.g54_offset_mm.x,
    y: block_word(block, 'Y').unwrap() * factor + profile.g54_offset_mm.y,
    z: block_word(block, 'Z').unwrap() * factor + profile.g54_offset_mm.z,
  })
}

///|
fn xyz_length(start : Vec3, end : Vec3) -> Double {
  let dx = end.x - start.x
  let dy = end.y - start.y
  let dz = end.z - start.z
  (dx * dx + dy * dy + dz * dz).sqrt()
}

///|
fn normalize_angle(angle : Double) -> Double {
  let tau = 2.0 * @math.PI
  let mut normalized = angle
  while normalized < 0.0 {
    normalized += tau
  }
  while normalized >= tau {
    normalized -= tau
  }
  normalized
}

///|
fn arc_sweep(
  start_angle : Double,
  end_angle : Double,
  clockwise : Bool,
  full : Bool,
) -> Double {
  if full {
    if clockwise {
      -2.0 * @math.PI
    } else {
      2.0 * @math.PI
    }
  } else if clockwise {
    let travel = normalize_angle(start_angle - end_angle)
    -travel
  } else {
    normalize_angle(end_angle - start_angle)
  }
}

///|
fn arc_fraction(
  start_angle : Double,
  candidate : Double,
  sweep : Double,
) -> Double {
  if sweep >= 0.0 {
    normalize_angle(candidate - start_angle) / sweep
  } else {
    normalize_angle(start_angle - candidate) / -sweep
  }
}

///|
fn add_diagnostic(
  diagnostics : Array[Diagnostic],
  line : Int,
  code : String,
  message : String,
  severity : DiagnosticSeverity,
  incomplete : Bool,
) -> Unit {
  diagnostics.push({ code, message, line: Some(line), severity, incomplete, })
}

///|
fn check_axis(
  diagnostics : Array[Diagnostic],
  line : Int,
  axis_name : String,
  value : Double,
  limit : AxisLimit,
) -> Unit {
  if value < limit.min - 0.000000001 || value > limit.max + 0.000000001 {
    add_diagnostic(
      diagnostics,
      line,
      "TRAVEL_LIMIT_\{axis_name}",
      "\{axis_name} coordinate \{value} mm is outside \{limit.min}..\{limit.max} mm.",
      Error,
      false,
    )
  }
}

///|
fn check_point(
  diagnostics : Array[Diagnostic],
  line : Int,
  point : Vec3,
  profile : MachineProfile,
) -> Unit {
  check_axis(diagnostics, line, "X", point.x, profile.x)
  check_axis(diagnostics, line, "Y", point.y, profile.y)
  check_axis(diagnostics, line, "Z", point.z, profile.z)
}

///|
fn arc_geometry(
  diagnostics : Array[Diagnostic],
  block : GCodeBlock,
  start : Vec3,
  end : Vec3,
  state : ModalState,
  profile : MachineProfile,
) -> (Vec3?, Double, Double) {
  let factor = match units_factor(state) {
    Some(factor) => factor
    None => return (None, 0.0, 0.0)
  }
  if !has_word(block, 'I') && !has_word(block, 'J') {
    add_diagnostic(
      diagnostics,
      block.line,
      "ARC_CENTER_REQUIRED",
      "G2/G3 requires at least one incremental I or J center offset.",
      Error,
      false,
    )
    return (None, 0.0, 0.0)
  }
  let i = match block_word(block, 'I') {
    Some(value) => value * factor
    None => 0.0
  }
  let j = match block_word(block, 'J') {
    Some(value) => value * factor
    None => 0.0
  }
  let center = { x: start.x + i, y: start.y + j, z: start.z, }
  let dx0 = start.x - center.x
  let dy0 = start.y - center.y
  let dx1 = end.x - center.x
  let dy1 = end.y - center.y
  let radius_start = (dx0 * dx0 + dy0 * dy0).sqrt()
  let radius_end = (dx1 * dx1 + dy1 * dy1).sqrt()
  if radius_start <= 0.000000001 ||
    radius_end <= 0.000000001 ||
    (radius_start - radius_end).abs() > profile.arc_tolerance_mm {
    add_diagnostic(
      diagnostics,
      block.line,
      "INVALID_ARC_RADIUS",
      "Arc start and end radii must be non-zero and agree within the configured tolerance.",
      Error,
      false,
    )
    return (None, 0.0, 0.0)
  }
  let start_angle = @math.atan2(dy0, dx0)
  let end_angle = @math.atan2(dy1, dx1)
  let full = (end.x - start.x).abs() < 0.000000001 &&
    (end.y - start.y).abs() < 0.000000001
  let clockwise = state.motion is Some(2)
  let sweep = arc_sweep(start_angle, end_angle, clockwise, full)
  let arc_xy_length = radius_start * sweep.abs()
  let dz = end.z - start.z
  let length = (arc_xy_length * arc_xy_length + dz * dz).sqrt()
  (Some(center), sweep, length)
}

///|
fn check_arc_extrema(
  diagnostics : Array[Diagnostic],
  block : GCodeBlock,
  start : Vec3,
  end : Vec3,
  center : Vec3,
  sweep : Double,
  profile : MachineProfile,
) -> Unit {
  let start_angle = @math.atan2(start.y - center.y, start.x - center.x)
  let radius = ((start.x - center.x) * (start.x - center.x) +
  (start.y - center.y) * (start.y - center.y)).sqrt()
  let cardinal_angles : Array[Double] = [
    0.0,
    @math.PI / 2.0,
    @math.PI,
    3.0 * @math.PI / 2.0,
  ]
  for angle in cardinal_angles {
    let fraction = arc_fraction(start_angle, angle, sweep)
    if fraction >= 0.0 && fraction <= 1.0 {
      let z = start.z + (end.z - start.z) * fraction
      let point = {
        x: center.x + radius * @math.cos(angle),
        y: center.y + radius * @math.sin(angle),
        z,
      }
      check_point(diagnostics, block.line, point, profile)
    }
  }
}

///|
fn has_poisoning_diagnostic(diagnostic : Diagnostic) -> Bool {
  diagnostic.incomplete &&
  (
    diagnostic.code == "UNSUPPORTED_G_CODE" ||
    diagnostic.code == "UNSUPPORTED_M_CODE" ||
    diagnostic.code == "UNSUPPORTED_WORD" ||
    diagnostic.code == "R_ARC_UNSUPPORTED" ||
    diagnostic.code == "MACRO_UNSUPPORTED" ||
    diagnostic.code == "SUBPROGRAM_UNSUPPORTED" ||
    diagnostic.code == "BLOCK_DELETE_UNSUPPORTED" ||
    diagnostic.code == "CHECKSUM_UNSUPPORTED" ||
    diagnostic.code == "UNEXPECTED_CHARACTER" ||
    diagnostic.code == "MISSING_WORD_VALUE" ||
    diagnostic.code == "NUMBER_WITHOUT_ADDRESS" ||
    diagnostic.code == "NESTED_COMMENT" ||
    diagnostic.code == "UNCLOSED_COMMENT" ||
    diagnostic.code == "UNMATCHED_COMMENT_END" ||
    diagnostic.code == "CONFLICTING_MODAL_CODES" ||
    diagnostic.code == "DUPLICATE_WORD"
  )
}

///|
fn status_for(
  analysis_complete : Bool,
  estimate_complete : Bool,
  diagnostics : Array[Diagnostic],
) -> AnalysisStatus {
  if diagnostics.any(d => d.incomplete) {
    Incomplete
  } else if diagnostics.any(d => d.severity == Error) {
    Fail
  } else if !analysis_complete || !estimate_complete {
    Incomplete
  } else {
    Pass
  }
}
