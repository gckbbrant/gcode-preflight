///|
fn validate_profile(profile : MachineProfile) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let tool_change_invalid = match profile.tool_change_seconds {
    Some(seconds) => seconds < 0.0
    None => false
  }
  let invalid = profile.x.min >= profile.x.max ||
    profile.y.min >= profile.y.max ||
    profile.z.min >= profile.z.max ||
    profile.rapid_mm_per_min <= 0.0 ||
    profile.arc_tolerance_mm <= 0.0 ||
    tool_change_invalid
  if invalid {
    diagnostics.push({
      code: "INVALID_PROFILE",
      message: "Axis limits must have positive range; rapid speed and arc tolerance must be positive; tool-change time cannot be negative.",
      line: None,
      severity: Error,
      incomplete: true,
    })
  }
  diagnostics
}

///|
fn motion_state_ready(state : ModalState, motion : Int) -> Bool {
  let base_ready = state.units_mm is Some(_) &&
    state.absolute is Some(_) &&
    state.work_g54 is Some(true) &&
    state.cutter_comp_off is Some(true) &&
    state.tool_length_comp_off is Some(true)
  let arc_ready = if motion == 2 || motion == 3 {
    state.plane_xy is Some(true) && state.arc_center_incremental is Some(true)
  } else {
    true
  }
  base_ready && arc_ready
}

///|
fn line_has_lexical_error(parsed : ParsedProgram, line : Int) -> Bool {
  parsed.diagnostics.any(d => d.line is Some(n) && n == line)
}

///|
fn update_position_after_unknown_start(
  diagnostics : Array[Diagnostic],
  block : GCodeBlock,
  state : ModalState,
  profile : MachineProfile,
  already_reported : Bool,
) -> (Vec3?, Bool) {
  if !already_reported {
    add_diagnostic(
      diagnostics,
      block.line,
      "UNKNOWN_INITIAL_POSITION",
      "The first move has no known starting position. Set initial_position_g54_mm in the profile to analyze its path and time.",
      Warning,
      true,
    )
  }
  (point_from_full_absolute_words(block, state, profile), true)
}

///|
/// Analyze supported G-code against a three-axis machine profile.
///
/// A report is incomplete whenever motion semantics or the initial position
/// are unknown. Time estimation is added by the reporting stage.
pub fn analyze(program : String, profile : MachineProfile) -> AnalysisReport {
  let parsed = parse_program(program)
  let diagnostics = parsed.diagnostics.copy()
  for diagnostic in validate_profile(profile) {
    diagnostics.push(diagnostic)
  }
  let segments : Array[ToolPathSegment] = []
  let mut total_distance_mm = 0.0
  let mut dwell_seconds = 0.0
  let mut tool_changes = 0
  let tool_change_lines : Array[Int] = []
  let mut state = default_modal_state()
  let mut execution_state_known = true
  let mut unknown_start_reported = false
  let mut position : Vec3? = match profile.initial_position_g54_mm {
    Some(initial) =>
      Some({
        x: initial.x + profile.g54_offset_mm.x,
        y: initial.y + profile.g54_offset_mm.y,
        z: initial.z + profile.g54_offset_mm.z,
      })
    None => None
  }
  if profile.x.min >= profile.x.max ||
    profile.y.min >= profile.y.max ||
    profile.z.min >= profile.z.max ||
    profile.rapid_mm_per_min <= 0.0 ||
    profile.arc_tolerance_mm <= 0.0 {
    execution_state_known = false
  }
  for block in parsed.blocks {
    if !state.ended {
      if line_has_lexical_error(parsed, block.line) {
        execution_state_known = false
      }
      let diagnostics_start = diagnostics.length()
      state = update_modal_state(state, block, diagnostics)
      for i in diagnostics_start..<diagnostics.length() {
        if has_poisoning_diagnostic(diagnostics[i]) {
          execution_state_known = false
        }
      }
      if block_has_code(block, 'M', 6.0) {
        tool_changes += 1
        tool_change_lines.push(block.line)
      }
      if block_has_code(block, 'G', 4.0) {
        match block_word(block, 'P') {
          Some(seconds) if seconds >= 0.0 => dwell_seconds += seconds
          _ => ()
        }
      }
      let has_xyz = has_word(block, 'X') ||
        has_word(block, 'Y') ||
        has_word(block, 'Z')
      let has_ij = has_word(block, 'I') || has_word(block, 'J')
      if has_ij && !(state.motion is Some(2)) && !(state.motion is Some(3)) {
        add_diagnostic(
          diagnostics,
          block.line,
          "IJ_WITHOUT_ARC",
          "I/J center offsets are only supported with G2 or G3.",
          Error,
          false,
        )
      }
      let is_arc = state.motion is Some(2) || state.motion is Some(3)
      let has_motion = if is_arc { has_xyz || has_ij } else { has_xyz }
      let is_dwell = block_has_code(block, 'G', 4.0)
      if execution_state_known && has_motion && !is_dwell {
        match state.motion {
          Some(motion) if motion >= 0 && motion <= 3 =>
            if motion_state_ready(state, motion) {
              match position {
                Some(start) =>
                  match endpoint_from_words(start, block, state, profile) {
                    Some(end) => {
                      check_point(diagnostics, block.line, start, profile)
                      check_point(diagnostics, block.line, end, profile)
                      if motion == 2 || motion == 3 {
                        let (center, sweep, length) = arc_geometry(
                          diagnostics, block, start, end, state, profile,
                        )
                        match center {
                          Some(center) => {
                            check_arc_extrema(
                              diagnostics, block, start, end, center, sweep, profile,
                            )
                            let kind = if motion == 2 {
                              ClockwiseArc
                            } else {
                              CounterclockwiseArc
                            }
                            segments.push({
                              line: block.line,
                              kind,
                              start_mm: start,
                              end_mm: end,
                              center_mm: Some(center),
                              sweep_radians: sweep,
                              length_mm: length,
                              feed_mm_per_min: state.feed_mm_per_min,
                            })
                            total_distance_mm += length
                            position = Some(end)
                          }
                          None => execution_state_known = false
                        }
                      } else {
                        let length = xyz_length(start, end)
                        let kind = if motion == 0 { Rapid } else { Linear }
                        segments.push({
                          line: block.line,
                          kind,
                          start_mm: start,
                          end_mm: end,
                          center_mm: None,
                          sweep_radians: 0.0,
                          length_mm: length,
                          feed_mm_per_min: state.feed_mm_per_min,
                        })
                        total_distance_mm += length
                        position = Some(end)
                      }
                    }
                    None =>
                      add_diagnostic(
                        diagnostics,
                        block.line,
                        "MISSING_COORDINATE_MODE",
                        "The endpoint cannot be converted without explicit units and distance mode.",
                        Warning,
                        true,
                      )
                  }
                None => {
                  let (next_position, reported) = update_position_after_unknown_start(
                    diagnostics, block, state, profile, unknown_start_reported,
                  )
                  unknown_start_reported = reported
                  position = next_position
                }
              }
            }
          _ => ()
        }
      }
    }
  }
  let analysis_complete = !diagnostics.any(d => d.incomplete)
  let mut estimated_time_seconds = dwell_seconds
  let mut estimate_complete = true
  for segment in segments {
    match segment.kind {
      Rapid =>
        estimated_time_seconds += segment.length_mm /
          profile.rapid_mm_per_min *
          60.0
      Linear | ClockwiseArc | CounterclockwiseArc =>
        match segment.feed_mm_per_min {
          Some(feed) if feed > 0.0 =>
            estimated_time_seconds += segment.length_mm / feed * 60.0
          _ => estimate_complete = false
        }
    }
  }
  if tool_changes > 0 {
    match profile.tool_change_seconds {
      Some(seconds) if seconds >= 0.0 =>
        estimated_time_seconds += seconds * tool_changes.to_double()
      _ => {
        estimate_complete = false
        let line = if tool_change_lines.is_empty() {
          None
        } else {
          Some(tool_change_lines[0])
        }
        diagnostics.push({
          code: "MISSING_TOOL_CHANGE_DURATION",
          message: "M6 is present but the profile has no non-negative tool_change_seconds value.",
          line,
          severity: Warning,
          incomplete: true,
        })
      }
    }
  }
  if diagnostics.any(d => d.incomplete) ||
    diagnostics.any(d => d.code == "MISSING_OR_INVALID_DWELL") {
    estimate_complete = false
  }
  let estimated_time = if estimate_complete {
    Some(estimated_time_seconds)
  } else {
    None
  }
  let status = status_for(analysis_complete, estimate_complete, diagnostics)
  {
    status,
    analysis_complete,
    estimate_complete,
    diagnostics,
    segments,
    distance_mm: total_distance_mm,
    dwell_seconds,
    tool_changes,
    estimated_time_seconds: estimated_time,
  }
}
