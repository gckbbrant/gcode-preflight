///|
/// A machine axis interval, in millimeters.
pub(all) struct AxisLimit {
  min : Double
  max : Double
} derive(Eq, ToJson, FromJson)

///|
/// A point in machine or program coordinates, in millimeters after conversion.
pub(all) struct Vec3 {
  x : Double
  y : Double
  z : Double
} derive(Eq, ToJson, FromJson)

///|
/// Machine settings used by analysis. All lengths and speeds are expressed in
/// millimeters and millimeters per minute.
pub(all) struct MachineProfile {
  x : AxisLimit
  y : AxisLimit
  z : AxisLimit
  g54_offset_mm : Vec3
  rapid_mm_per_min : Double
  arc_tolerance_mm : Double
  tool_change_seconds : Double?
} derive(ToJson, FromJson)

///|
/// Severity of an analysis finding.
pub(all) enum DiagnosticSeverity {
  Error
  Warning
  Info
} derive(Eq, ToJson)

///|
/// A machine-readable finding tied to a source line when possible.
pub(all) struct Diagnostic {
  code : String
  message : String
  line : Int?
  severity : DiagnosticSeverity
  incomplete : Bool
} derive(ToJson)

///|
/// Overall result for a complete supported-subset analysis.
pub(all) enum AnalysisStatus {
  Pass
  Fail
  Incomplete
} derive(Eq, ToJson)

///|
/// Result of analyzing one program against a machine profile.
pub(all) struct AnalysisReport {
  status : AnalysisStatus
  diagnostics : Array[Diagnostic]
} derive(ToJson)
