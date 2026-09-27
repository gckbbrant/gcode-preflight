///|
fn validate_profile(profile : MachineProfile) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  if profile.x.min >= profile.x.max ||
    profile.y.min >= profile.y.max ||
    profile.z.min >= profile.z.max ||
    profile.rapid_mm_per_min <= 0.0 ||
    profile.arc_tolerance_mm <= 0.0 {
    diagnostics.push({
      code: "INVALID_PROFILE",
      message: "Axis limits must have positive range; rapid speed and arc tolerance must be positive.",
      line: None,
      severity: Error,
      incomplete: true,
    })
  }
  diagnostics
}

///|
/// Analyze supported G-code against a machine profile.
///
/// The early implementation deliberately reports `INCOMPLETE` until the full
/// geometry, travel, time, and SVG passes have been implemented.
pub fn analyze(program : String, profile : MachineProfile) -> AnalysisReport {
  let parsed = parse_program(program)
  let diagnostics = inspect_modal_program(parsed)
  for diagnostic in validate_profile(profile) {
    diagnostics.push(diagnostic)
  }
  diagnostics.push({
    code: "ANALYZER_IN_PROGRESS",
    message: "The full geometry and travel analysis is not implemented yet.",
    line: None,
    severity: Info,
    incomplete: true,
  })
  { status: Incomplete, diagnostics }
}
