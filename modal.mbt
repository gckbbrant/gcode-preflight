///|
priv struct ModalState {
  mut plane_xy : Bool?
  mut units_mm : Bool?
  mut absolute : Bool?
  mut arc_center_incremental : Bool?
  mut feed_per_minute : Bool?
  mut work_g54 : Bool?
  mut cutter_comp_off : Bool?
  mut tool_length_comp_off : Bool?
  mut motion : Int?
  mut feed_mm_per_min : Double?
  mut spindle_rpm : Double?
  mut selected_tool : Int?
  mut ended : Bool
}

///|
fn default_modal_state() -> ModalState {
  {
    plane_xy: None,
    units_mm: None,
    absolute: None,
    arc_center_incremental: None,
    feed_per_minute: None,
    work_g54: None,
    cutter_comp_off: None,
    tool_length_comp_off: None,
    motion: None,
    feed_mm_per_min: None,
    spindle_rpm: None,
    selected_tool: None,
    ended: false,
  }
}

///|
fn mode_diagnostic(
  diagnostics : Array[Diagnostic],
  line : Int,
  code : String,
  message : String,
  incomplete : Bool,
) -> Unit {
  diagnostics.push({
    code,
    message,
    line: Some(line),
    severity: Error,
    incomplete,
    point_mm: None,
  })
}

///|
fn code_is(actual : Double, expected : Double) -> Bool {
  (actual - expected).abs() < 0.0000001
}

///|
fn block_word(block : GCodeBlock, address : Char) -> Double? {
  for word in block.words {
    if word.address == address {
      return Some(word.value)
    }
  }
  None
}

///|
fn block_has_code(block : GCodeBlock, address : Char, code : Double) -> Bool {
  for word in block.words {
    if word.address == address && code_is(word.value, code) {
      return true
    }
  }
  false
}

///|
fn count_address(block : GCodeBlock, address : Char) -> Int {
  let mut count = 0
  for word in block.words {
    if word.address == address {
      count += 1
    }
  }
  count
}

///|
fn recognized_g_code(value : Double) -> Bool {
  code_is(value, 0.0) ||
  code_is(value, 1.0) ||
  code_is(value, 2.0) ||
  code_is(value, 3.0) ||
  code_is(value, 4.0) ||
  code_is(value, 17.0) ||
  code_is(value, 20.0) ||
  code_is(value, 21.0) ||
  code_is(value, 40.0) ||
  code_is(value, 49.0) ||
  code_is(value, 54.0) ||
  code_is(value, 90.0) ||
  code_is(value, 91.0) ||
  code_is(value, 91.1) ||
  code_is(value, 94.0)
}

///|
fn recognized_m_code(value : Double) -> Bool {
  code_is(value, 2.0) ||
  code_is(value, 3.0) ||
  code_is(value, 4.0) ||
  code_is(value, 5.0) ||
  code_is(value, 6.0) ||
  code_is(value, 30.0)
}

///|
fn require_mode(
  diagnostics : Array[Diagnostic],
  line : Int,
  configured : Bool?,
  name : String,
) -> Unit {
  if configured is None {
    mode_diagnostic(
      diagnostics,
      line,
      "MISSING_MODAL_SETUP",
      "Motion requires an explicit \{name} mode in this program.",
      true,
    )
  }
}

///|
fn update_modal_state(
  state : ModalState,
  block : GCodeBlock,
  diagnostics : Array[Diagnostic],
) -> ModalState {
  let line = block.line
  let next = state
  let mut motion_code : Int? = None
  let mut motion_code_count = 0
  let mut dwell = false
  let mut g17 = false
  let mut g20 = false
  let mut g21 = false
  let mut g40 = false
  let mut g49 = false
  let mut g54 = false
  let mut g90 = false
  let mut g91 = false
  let mut g91_1 = false
  let mut g94 = false
  let mut m3 = false
  let mut m4 = false
  let mut m5 = false
  let mut m6 = false
  let mut end_program = false
  for word in block.words {
    if word.address == 'G' {
      if !recognized_g_code(word.value) {
        mode_diagnostic(
          diagnostics,
          line,
          "UNSUPPORTED_G_CODE",
          "G\{word.value} is outside the supported G-code subset.",
          true,
        )
      } else if code_is(word.value, 0.0) {
        motion_code_count += 1
        motion_code = Some(0)
      } else if code_is(word.value, 1.0) {
        motion_code_count += 1
        motion_code = Some(1)
      } else if code_is(word.value, 2.0) {
        motion_code_count += 1
        motion_code = Some(2)
      } else if code_is(word.value, 3.0) {
        motion_code_count += 1
        motion_code = Some(3)
      } else if code_is(word.value, 4.0) {
        dwell = true
      } else if code_is(word.value, 17.0) {
        g17 = true
      } else if code_is(word.value, 20.0) {
        g20 = true
      } else if code_is(word.value, 21.0) {
        g21 = true
      } else if code_is(word.value, 40.0) {
        g40 = true
      } else if code_is(word.value, 49.0) {
        g49 = true
      } else if code_is(word.value, 54.0) {
        g54 = true
      } else if code_is(word.value, 90.0) {
        g90 = true
      } else if code_is(word.value, 91.0) {
        g91 = true
      } else if code_is(word.value, 91.1) {
        g91_1 = true
      } else if code_is(word.value, 94.0) {
        g94 = true
      }
    } else if word.address == 'M' {
      if !recognized_m_code(word.value) {
        mode_diagnostic(
          diagnostics,
          line,
          "UNSUPPORTED_M_CODE",
          "M\{word.value} is outside the supported M-code subset.",
          true,
        )
      } else if code_is(word.value, 2.0) || code_is(word.value, 30.0) {
        end_program = true
      } else if code_is(word.value, 3.0) {
        m3 = true
      } else if code_is(word.value, 4.0) {
        m4 = true
      } else if code_is(word.value, 5.0) {
        m5 = true
      } else if code_is(word.value, 6.0) {
        m6 = true
      }
    } else if word.address == 'R' {
      mode_diagnostic(
        diagnostics, line, "R_ARC_UNSUPPORTED", "R-format arc geometry is not supported; use incremental I/J centers.",
        true,
      )
    } else if word.address == 'O' {
      mode_diagnostic(
        diagnostics, line, "SUBPROGRAM_UNSUPPORTED", "Program labels and subprograms are not interpreted.",
        true,
      )
    } else if word.address == 'A' ||
      word.address == 'B' ||
      word.address == 'C' ||
      word.address == 'U' ||
      word.address == 'V' ||
      word.address == 'W' ||
      word.address == 'H' ||
      word.address == 'D' ||
      word.address == 'L' ||
      word.address == 'Q' {
      mode_diagnostic(
        diagnostics,
        line,
        "UNSUPPORTED_WORD",
        "Word \{word.address} can affect motion or execution and is not supported.",
        true,
      )
    } else if word.address != 'N' &&
      word.address != 'X' &&
      word.address != 'Y' &&
      word.address != 'Z' &&
      word.address != 'I' &&
      word.address != 'J' &&
      word.address != 'F' &&
      word.address != 'S' &&
      word.address != 'T' &&
      word.address != 'P' {
      mode_diagnostic(
        diagnostics,
        line,
        "UNSUPPORTED_WORD",
        "Word \{word.address} is outside the supported subset.",
        true,
      )
    }
  }
  if (g20 && g21) ||
    (g90 && g91) ||
    motion_code_count > 1 ||
    (dwell && motion_code_count > 0) ||
    (m3 && m4) ||
    (m5 && (m3 || m4)) {
    mode_diagnostic(
      diagnostics, line, "CONFLICTING_MODAL_CODES", "The block contains conflicting codes from one modal group.",
      true,
    )
  }
  if g17 {
    next.plane_xy = Some(true)
  }
  if g20 {
    next.units_mm = Some(false)
  }
  if g21 {
    next.units_mm = Some(true)
  }
  if g90 {
    next.absolute = Some(true)
  }
  if g91 {
    next.absolute = Some(false)
  }
  if g91_1 {
    next.arc_center_incremental = Some(true)
  }
  if g94 {
    next.feed_per_minute = Some(true)
  }
  if g54 {
    next.work_g54 = Some(true)
  }
  if g40 {
    next.cutter_comp_off = Some(true)
  }
  if g49 {
    next.tool_length_comp_off = Some(true)
  }
  match motion_code {
    Some(code) => next.motion = Some(code)
    None => ()
  }
  match block_word(block, 'F') {
    Some(feed) if feed > 0.0 => {
      let factor = match next.units_mm {
        Some(true) => 1.0
        Some(false) => 25.4
        None => 1.0
      }
      next.feed_mm_per_min = Some(feed * factor)
    }
    Some(_) =>
      mode_diagnostic(
        diagnostics, line, "INVALID_FEED", "Feed rate F must be greater than zero.",
        false,
      )
    None => ()
  }
  match block_word(block, 'S') {
    Some(rpm) if rpm > 0.0 => next.spindle_rpm = Some(rpm)
    Some(_) =>
      mode_diagnostic(
        diagnostics, line, "INVALID_SPINDLE_SPEED", "Spindle speed S must be greater than zero.",
        false,
      )
    None => ()
  }
  match block_word(block, 'T') {
    Some(tool) if tool >= 0.0 && tool == tool.floor() =>
      next.selected_tool = Some(tool.to_int())
    Some(_) =>
      mode_diagnostic(
        diagnostics, line, "INVALID_TOOL_NUMBER", "Tool number T must be a non-negative integer.",
        false,
      )
    None => ()
  }
  if m3 || m4 {
    if next.spindle_rpm is None {
      mode_diagnostic(
        diagnostics, line, "MISSING_SPINDLE_SPEED", "M3/M4 requires a modal spindle speed S before spindle start.",
        false,
      )
    }
  }
  if m6 && next.selected_tool is None {
    mode_diagnostic(
      diagnostics, line, "MISSING_TOOL_NUMBER", "M6 requires a selected tool number T.",
      false,
    )
  }
  let has_xyz = block_word(block, 'X') is Some(_) ||
    block_word(block, 'Y') is Some(_) ||
    block_word(block, 'Z') is Some(_)
  let has_arc_center = block_word(block, 'I') is Some(_) ||
    block_word(block, 'J') is Some(_)
  let has_axis = has_xyz ||
    ((next.motion is Some(2) || next.motion is Some(3)) && has_arc_center)
  if dwell {
    if motion_code is Some(_) || has_axis {
      mode_diagnostic(
        diagnostics, line, "MIXED_DWELL_AND_MOTION", "A dwell and a motion command cannot share a block in this subset.",
        true,
      )
    }
    match block_word(block, 'P') {
      Some(seconds) if seconds >= 0.0 => ()
      _ =>
        mode_diagnostic(
          diagnostics, line, "MISSING_OR_INVALID_DWELL", "G4 requires a non-negative dwell duration P in seconds.",
          false,
        )
    }
  } else if block_word(block, 'P') is Some(_) {
    mode_diagnostic(
      diagnostics, line, "UNSUPPORTED_P_WORD", "P is only supported with G4 dwell blocks.",
      true,
    )
  }
  if has_axis {
    let effective_motion = match motion_code {
      Some(code) => Some(code)
      None => next.motion
    }
    match effective_motion {
      Some(0) | Some(1) | Some(2) | Some(3) => {
        require_mode(diagnostics, line, next.units_mm, "G20 or G21 units")
        require_mode(
          diagnostics,
          line,
          next.absolute,
          "G90 or G91 distance mode",
        )
        require_mode(
          diagnostics,
          line,
          next.work_g54,
          "G54 work coordinate system",
        )
        require_mode(
          diagnostics,
          line,
          next.cutter_comp_off,
          "G40 cutter compensation cancel",
        )
        require_mode(
          diagnostics,
          line,
          next.tool_length_comp_off,
          "G49 tool-length compensation cancel",
        )
        if effective_motion is Some(2) || effective_motion is Some(3) {
          require_mode(diagnostics, line, next.plane_xy, "G17 XY plane")
          require_mode(
            diagnostics,
            line,
            next.arc_center_incremental,
            "G91.1 incremental arc-center mode",
          )
        }
        if effective_motion is Some(1) ||
          effective_motion is Some(2) ||
          effective_motion is Some(3) {
          require_mode(
            diagnostics,
            line,
            next.feed_per_minute,
            "G94 feed-per-minute mode",
          )
          if next.feed_mm_per_min is None {
            mode_diagnostic(
              diagnostics, line, "MISSING_FEED", "G1/G2/G3 motion requires a modal feed rate F.",
              false,
            )
          }
        }
      }
      None =>
        mode_diagnostic(
          diagnostics, line, "MISSING_MOTION_MODE", "Axis words require an explicit G0/G1/G2/G3 motion mode.",
          true,
        )
      _ => ()
    }
  }
  if count_address(block, 'N') > 1 ||
    count_address(block, 'X') > 1 ||
    count_address(block, 'Y') > 1 ||
    count_address(block, 'Z') > 1 ||
    count_address(block, 'I') > 1 ||
    count_address(block, 'J') > 1 ||
    count_address(block, 'F') > 1 ||
    count_address(block, 'S') > 1 ||
    count_address(block, 'T') > 1 ||
    count_address(block, 'P') > 1 {
    mode_diagnostic(
      diagnostics, line, "DUPLICATE_WORD", "A non-modal address occurs more than once in the block.",
      true,
    )
  }
  if end_program {
    next.ended = true
  }
  next
}
