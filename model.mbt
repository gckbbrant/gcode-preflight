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
  initial_position_g54_mm : Vec3?
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
/// Interpreted motion type.
pub(all) enum MotionKind {
  Rapid
  Linear
  ClockwiseArc
  CounterclockwiseArc
} derive(ToJson)

///|
/// One validated move in the programmed XY toolpath.
pub(all) struct ToolPathSegment {
  line : Int
  kind : MotionKind
  start_mm : Vec3
  end_mm : Vec3
  center_mm : Vec3?
  sweep_radians : Double
  length_mm : Double
  feed_mm_per_min : Double?
} derive(ToJson)

///|
/// Result of analyzing one program against a machine profile.
pub(all) struct AnalysisReport {
  status : AnalysisStatus
  analysis_complete : Bool
  estimate_complete : Bool
  diagnostics : Array[Diagnostic]
  segments : Array[ToolPathSegment]
  distance_mm : Double
  dwell_seconds : Double
  tool_changes : Int
  estimated_time_seconds : Double?
} derive(ToJson)

///|
pub extend AxisLimit with Eq::{not_equal, equal}

///|
pub extend AxisLimit with ToJson::{to_json}

///|
pub extend AxisLimit with @json.FromJson::{from_json}

///|
pub extend Vec3 with Eq::{not_equal, equal}

///|
pub extend Vec3 with ToJson::{to_json}

///|
pub extend Vec3 with @json.FromJson::{from_json}

///|
pub extend MachineProfile with ToJson::{to_json}

///|
pub extend MachineProfile with @json.FromJson::{from_json}

///|
pub extend DiagnosticSeverity with Eq::{not_equal, equal}

///|
pub extend DiagnosticSeverity with ToJson::{to_json}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub extend AnalysisStatus with Eq::{not_equal, equal}

///|
pub extend AnalysisStatus with ToJson::{to_json}

///|
pub extend MotionKind with ToJson::{to_json}

///|
pub extend ToolPathSegment with ToJson::{to_json}

///|
pub extend AnalysisReport with ToJson::{to_json}
