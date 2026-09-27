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
fn work_offset_for_system(profile : MachineProfile, system : Int) -> Vec3? {
  if system == 1 {
    return Some(profile.g54_offset_mm)
  }
  let system_name = match system {
    2 => "G55"
    3 => "G56"
    4 => "G57"
    5 => "G58"
    6 => "G59"
    7 => "G59.1"
    8 => "G59.2"
    9 => "G59.3"
    _ => return None
  }
  match profile.additional_work_offsets_mm {
    Some(offsets) => {
      for entry in offsets {
        if entry.system == system_name {
          return Some(entry.offset_mm)
        }
      }
      None
    }
    None => None
  }
}

///|
fn selected_work_offset(profile : MachineProfile, state : ModalState) -> Vec3? {
  match state.work_coordinate {
    Some(system) => work_offset_for_system(profile, system)
    None => None
  }
}

///|
fn endpoint_from_words(
  start : Vec3,
  block : GCodeBlock,
  state : ModalState,
  profile : MachineProfile,
  machine_coordinates : Bool,
) -> Vec3? {
  let factor = match units_factor(state) {
    Some(factor) => factor
    None => return None
  }
  let absolute = if machine_coordinates {
    true
  } else {
    match state.absolute {
      Some(absolute) => absolute
      None => return None
    }
  }
  let offset : Vec3 = if machine_coordinates {
    { x: 0.0, y: 0.0, z: 0.0, }
  } else {
    match selected_work_offset(profile, state) {
      Some(offset) => offset
      None => return None
    }
  }
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
  machine_coordinates : Bool,
) -> Vec3? {
  if !(has_word(block, 'X') && has_word(block, 'Y') && has_word(block, 'Z')) {
    return None
  }
  if !machine_coordinates && !(state.absolute is Some(true)) {
    return None
  }
  let factor = match units_factor(state) {
    Some(factor) => factor
    None => return None
  }
  let offset : Vec3 = if machine_coordinates {
    { x: 0.0, y: 0.0, z: 0.0, }
  } else {
    match selected_work_offset(profile, state) {
      Some(offset) => offset
      None => return None
    }
  }
  Some({
    x: block_word(block, 'X').unwrap() * factor + offset.x,
    y: block_word(block, 'Y').unwrap() * factor + offset.y,
    z: block_word(block, 'Z').unwrap() * factor + offset.z,
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
  diagnostics.push({
    code,
    message,
    line: Some(line),
    severity,
    incomplete,
    point_mm: None,
  })
}

///|
fn add_travel_violation(
  diagnostics : Array[Diagnostic],
  line : Int,
  axis_name : String,
  value : Double,
  limit : AxisLimit,
  point : Vec3,
) -> Unit {
  diagnostics.push({
    code: "TRAVEL_LIMIT_\{axis_name}",
    message: "\{axis_name} coordinate \{value} mm is outside \{limit.min}..\{limit.max} mm.",
    line: Some(line),
    severity: Error,
    incomplete: false,
    point_mm: Some(point),
  })
}

///|
fn check_axis(
  diagnostics : Array[Diagnostic],
  line : Int,
  axis_name : String,
  value : Double,
  limit : AxisLimit,
  point : Vec3,
) -> Unit {
  if value < limit.min - 0.000000001 || value > limit.max + 0.000000001 {
    add_travel_violation(diagnostics, line, axis_name, value, limit, point)
  }
}

///|
fn check_point(
  diagnostics : Array[Diagnostic],
  line : Int,
  point : Vec3,
  profile : MachineProfile,
) -> Unit {
  check_axis(diagnostics, line, "X", point.x, profile.x, point)
  check_axis(diagnostics, line, "Y", point.y, profile.y, point)
  check_axis(diagnostics, line, "Z", point.z, profile.z, point)
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
  let has_i = has_word(block, 'I')
  let has_j = has_word(block, 'J')
  let has_r = has_word(block, 'R')
  if has_r && (has_i || has_j) {
    add_diagnostic(
      diagnostics,
      block.line,
      "CONFLICTING_ARC_FORMATS",
      "Specify either R radius format or I/J center format, not both.",
      Error,
      false,
    )
    return (None, 0.0, 0.0)
  }
  if has_r {
    return radius_arc_geometry(
      diagnostics,
      block,
      start,
      end,
      block_word(block, 'R').unwrap() * factor,
      state.motion is Some(2),
      profile,
    )
  }
  if !has_i && !has_j {
    add_diagnostic(
      diagnostics,
      block.line,
      "ARC_CENTER_REQUIRED",
      "G2/G3 requires I/J center coordinates.",
      Error,
      false,
    )
    return (None, 0.0, 0.0)
  }
  let absolute_center = state.arc_center_incremental is Some(false)
  if absolute_center && !(has_i && has_j) {
    add_diagnostic(
      diagnostics,
      block.line,
      "ARC_CENTER_REQUIRED",
      "G90.1 absolute center format requires both I and J coordinates.",
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
  let center : Vec3 = if absolute_center {
    let offset = selected_work_offset(profile, state).unwrap()
    { x: i + offset.x, y: j + offset.y, z: start.z, }
  } else {
    { x: start.x + i, y: start.y + j, z: start.z, }
  }
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
fn radius_arc_geometry(
  diagnostics : Array[Diagnostic],
  block : GCodeBlock,
  start : Vec3,
  end : Vec3,
  signed_radius : Double,
  clockwise : Bool,
  profile : MachineProfile,
) -> (Vec3?, Double, Double) {
  let dx = end.x - start.x
  let dy = end.y - start.y
  let chord = (dx * dx + dy * dy).sqrt()
  let radius = signed_radius.abs()
  let invalid_reason = if !has_word(block, 'X') && !has_word(block, 'Y') {
    Some("R-format arcs require an X or Y endpoint.")
  } else if radius <= 0.000000001 {
    Some("R-format arc radius must be non-zero.")
  } else if chord <= 0.000000001 {
    Some("R-format arcs cannot describe a full circle; use I/J center offsets.")
  } else if chord > 2.0 * radius + profile.arc_tolerance_mm {
    Some("The R-format arc chord is longer than its diameter beyond tolerance.")
  } else {
    None
  }
  match invalid_reason {
    Some(message) => {
      add_diagnostic(
        diagnostics,
        block.line,
        "INVALID_R_ARC",
        message,
        Error,
        false,
      )
      return (None, 0.0, 0.0)
    }
    None => ()
  }
  let half_chord = chord / 2.0
  let height_squared = radius * radius - half_chord * half_chord
  let height = if height_squared > 0.0 { height_squared.sqrt() } else { 0.0 }
  let midpoint_x = (start.x + end.x) / 2.0
  let midpoint_y = (start.y + end.y) / 2.0
  let perpendicular_x = -dy / chord
  let perpendicular_y = dx / chord
  let centers : Array[Vec3] = [
    {
      x: midpoint_x + perpendicular_x * height,
      y: midpoint_y + perpendicular_y * height,
      z: start.z,
    },
    {
      x: midpoint_x - perpendicular_x * height,
      y: midpoint_y - perpendicular_y * height,
      z: start.z,
    },
  ]
  let want_major = signed_radius < 0.0
  let mut selected_center : Vec3? = None
  let mut selected_sweep = 0.0
  let mut selected_radius = 0.0
  for center in centers {
    let start_angle = @math.atan2(start.y - center.y, start.x - center.x)
    let end_angle = @math.atan2(end.y - center.y, end.x - center.x)
    let sweep = arc_sweep(start_angle, end_angle, clockwise, false)
    let magnitude = sweep.abs()
    let fits_radius_sign = if want_major {
      magnitude > @math.PI + 0.000000001
    } else {
      magnitude <= @math.PI + 0.000000001
    }
    if selected_center is None && fits_radius_sign {
      selected_center = Some(center)
      selected_sweep = sweep
      let radius_x = start.x - center.x
      let radius_y = start.y - center.y
      selected_radius = (radius_x * radius_x + radius_y * radius_y).sqrt()
    }
  }
  match selected_center {
    Some(center) => {
      let sweep_magnitude = selected_sweep.abs()
      let full_turn = 2.0 * @math.PI
      let warning_margin = @math.PI / 12.0
      if (sweep_magnitude - @math.PI).abs() <= warning_margin ||
        full_turn - sweep_magnitude <= warning_margin {
        add_diagnostic(
          diagnostics,
          block.line,
          "R_ARC_ROUNDING_SENSITIVE",
          "R-format arcs near a half or full circle amplify endpoint rounding; consider I/J center format.",
          Warning,
          false,
        )
      }
      let arc_xy_length = selected_radius * selected_sweep.abs()
      let dz = end.z - start.z
      let length = (arc_xy_length * arc_xy_length + dz * dz).sqrt()
      (Some(center), selected_sweep, length)
    }
    None => {
      add_diagnostic(
        diagnostics,
        block.line,
        "INVALID_R_ARC",
        "The radius sign does not select a valid minor or major arc for these endpoints.",
        Error,
        false,
      )
      (None, 0.0, 0.0)
    }
  }
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
      let point : Vec3 = {
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
