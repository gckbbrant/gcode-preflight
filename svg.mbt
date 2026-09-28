///|
priv struct SvgBounds {
  mut has_point : Bool
  mut min_x : Double
  mut max_x : Double
  mut min_y : Double
  mut max_y : Double
}

///|
fn include_svg_point(bounds : SvgBounds, point : Vec3) -> Unit {
  if !bounds.has_point {
    bounds.has_point = true
    bounds.min_x = point.x
    bounds.max_x = point.x
    bounds.min_y = point.y
    bounds.max_y = point.y
  } else {
    if point.x < bounds.min_x {
      bounds.min_x = point.x
    }
    if point.x > bounds.max_x {
      bounds.max_x = point.x
    }
    if point.y < bounds.min_y {
      bounds.min_y = point.y
    }
    if point.y > bounds.max_y {
      bounds.max_y = point.y
    }
  }
}

///|
fn include_segment_bounds(
  bounds : SvgBounds,
  segment : ToolPathSegment,
) -> Unit {
  include_svg_point(bounds, segment.start_mm)
  include_svg_point(bounds, segment.end_mm)
  match segment.center_mm {
    Some(center) => {
      let start_angle = @math.atan2(
        segment.start_mm.y - center.y,
        segment.start_mm.x - center.x,
      )
      let radius = ((segment.start_mm.x - center.x) *
      (segment.start_mm.x - center.x) +
      (segment.start_mm.y - center.y) * (segment.start_mm.y - center.y)).sqrt()
      let angles : Array[Double] = [
        0.0,
        @math.PI / 2.0,
        @math.PI,
        3.0 * @math.PI / 2.0,
      ]
      for angle in angles {
        let fraction = arc_fraction(start_angle, angle, segment.sweep_radians)
        if fraction >= 0.0 && fraction <= 1.0 {
          include_svg_point(bounds, {
            x: center.x + radius * @math.cos(angle),
            y: center.y + radius * @math.sin(angle),
            z: segment.start_mm.z +
            (segment.end_mm.z - segment.start_mm.z) * fraction,
          })
        }
      }
    }
    None => ()
  }
}

///|
fn svg_status(status : AnalysisStatus) -> String {
  match status {
    Pass => "PASS"
    Fail => "FAIL"
    Incomplete => "INCOMPLETE"
  }
}

///|
fn svg_segment_path(segment : ToolPathSegment) -> String {
  let start = segment.start_mm
  let end = segment.end_mm
  let path = StringBuilder()
  path.write_string("M ")
  path.write_string(start.x.to_string())
  path.write_char(' ')
  path.write_string((-start.y).to_string())
  match segment.center_mm {
    Some(center) => {
      let radius = ((start.x - center.x) * (start.x - center.x) +
      (start.y - center.y) * (start.y - center.y)).sqrt()
      let large_arc = if segment.sweep_radians.abs() > @math.PI {
        "1"
      } else {
        "0"
      }
      let sweep_flag = match segment.kind {
        ClockwiseArc => "1"
        _ => "0"
      }
      let append_arc_to = fn(x : Double, y : Double) {
        path.write_string(" A ")
        path.write_string(radius.to_string())
        path.write_char(' ')
        path.write_string(radius.to_string())
        path.write_string(" 0 ")
        path.write_string(large_arc)
        path.write_char(' ')
        path.write_string(sweep_flag)
        path.write_char(' ')
        path.write_string(x.to_string())
        path.write_char(' ')
        path.write_string((-y).to_string())
      }
      if (start.x - end.x).abs() < 0.000000001 &&
        (start.y - end.y).abs() < 0.000000001 {
        let start_angle = @math.atan2(start.y - center.y, start.x - center.x)
        let middle_angle = start_angle + segment.sweep_radians / 2.0
        append_arc_to(
          center.x + radius * @math.cos(middle_angle),
          center.y + radius * @math.sin(middle_angle),
        )
        append_arc_to(end.x, end.y)
      } else {
        append_arc_to(end.x, end.y)
      }
    }
    None => {
      path.write_string(" L ")
      path.write_string(end.x.to_string())
      path.write_char(' ')
      path.write_string((-end.y).to_string())
    }
  }
  path.to_string()
}

///|
fn svg_segment_class(kind : MotionKind) -> String {
  match kind {
    Rapid => "rapid"
    Linear => "linear"
    ClockwiseArc => "arc-cw"
    CounterclockwiseArc => "arc-ccw"
  }
}

///|
fn segment_violates_travel(
  report : AnalysisReport,
  segment : ToolPathSegment,
) -> Bool {
  report.diagnostics.any(diagnostic => {
    diagnostic.line is Some(line) &&
    line == segment.line &&
    diagnostic.code.has_prefix("TRAVEL_LIMIT_")
  })
}

///|
fn svg_segment_class_for_report(
  report : AnalysisReport,
  segment : ToolPathSegment,
) -> String {
  let motion_class = svg_segment_class(segment.kind)
  if segment_violates_travel(report, segment) {
    motion_class + " violation"
  } else {
    motion_class
  }
}

///|
fn svg_status_class(status : AnalysisStatus) -> String {
  match status {
    Pass => "status-pass"
    Fail => "status-fail"
    Incomplete => "status-incomplete"
  }
}

///|
fn svg_rounded_number(value : Double) -> String {
  let scaled = value * 100.0
  let rounded = if scaled >= 0.0 {
    (scaled + 0.5).to_int()
  } else {
    (scaled - 0.5).to_int()
  }
  (rounded.to_double() / 100.0).to_string()
}

///|
fn svg_estimate_text(report : AnalysisReport) -> String {
  match report.estimated_time_seconds {
    Some(seconds) => "\{svg_rounded_number(seconds)} s estimated cycle time"
    None => "Cycle time estimate unavailable"
  }
}

///|
fn svg_write_text(
  svg : StringBuilder,
  class : String,
  x : Double,
  y : Double,
  size : Double,
  text : String,
) -> Unit {
  svg.write_string(
    "  <text class=\"\{class}\" x=\"\{x}\" y=\"\{y}\" font-size=\"\{size}\">\{text}</text>\n",
  )
}

///|
fn svg_write_legend_item(
  svg : StringBuilder,
  class : String,
  label : String,
  x : Double,
  y : Double,
  font_size : Double,
) -> Unit {
  svg.write_string(
    "  <path class=\"\{class}\" d=\"M \{x} \{y - font_size * 0.3} h \{font_size * 1.4}\" />\n",
  )
  svg_write_text(svg, "legend-label", x + font_size * 1.9, y, font_size, label)
}

///|
/// Render a top-view SVG of the analyzed XY toolpath.
///
/// Rapid moves use a dashed gray line. Feed moves and arcs use blue and purple
/// strokes. The view is an XY projection; helical Z motion is represented by
/// the same projected circular path. Configured XY limits and travel violations
/// are shown as a boundary and red path/point markers.
pub fn render_svg(report : AnalysisReport) -> String {
  let bounds = SvgBounds::{
    has_point: false,
    min_x: 0.0,
    max_x: 0.0,
    min_y: 0.0,
    max_y: 0.0,
  }
  let limits = report.travel_limits
  let show_limits = limits.x.min < limits.x.max && limits.y.min < limits.y.max
  if show_limits {
    include_svg_point(bounds, { x: limits.x.min, y: limits.y.min, z: 0.0, })
    include_svg_point(bounds, { x: limits.x.max, y: limits.y.max, z: 0.0, })
  }
  for segment in report.segments {
    include_segment_bounds(bounds, segment)
  }
  if !bounds.has_point {
    bounds.has_point = true
    bounds.min_x = -10.0
    bounds.max_x = 10.0
    bounds.min_y = -10.0
    bounds.max_y = 10.0
  }
  let span = if bounds.max_x - bounds.min_x > bounds.max_y - bounds.min_y {
    bounds.max_x - bounds.min_x
  } else {
    bounds.max_y - bounds.min_y
  }
  let safe_span = span.max(1.0)
  let font_size = (safe_span * 0.025).max(1.5)
  let padding = safe_span * 0.05 + 2.0
  let title_band = font_size * 4.8
  let footer_band = font_size * 3.5
  let map_width = bounds.max_x - bounds.min_x
  let content_width = map_width.max(safe_span * 1.15)
  let content_center_x = (bounds.min_x + bounds.max_x) / 2.0
  let content_min_x = content_center_x - content_width / 2.0
  let view_x = content_min_x - padding
  let view_y = -bounds.max_y - padding - title_band
  let view_width = content_width + 2.0 * padding
  let view_height = bounds.max_y -
    bounds.min_y +
    2.0 * padding +
    title_band +
    footer_band
  let map_top = -bounds.max_y
  let map_bottom = -bounds.min_y
  let content_left = content_min_x
  let title_y = view_y + font_size * 1.55
  let status_y = view_y + font_size * 2.9
  let summary_y = view_y + font_size * 4.15
  let footer_y = map_bottom + padding + font_size * 1.4
  let svg = StringBuilder()
  svg.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"\{1200.0 * view_height / view_width}\" viewBox=\"\{view_x} \{view_y} \{view_width} \{view_height}\" role=\"img\" aria-label=\"CNC G-code preflight toolpath report\">\n",
  )
  svg.write_string(
    "  <title>CNC G-code Preflight — \{svg_status(report.status)}</title>\n",
  )
  svg.write_string(
    "  <style>path{fill:none;stroke-width:0.35;stroke-linecap:round;stroke-linejoin:round}.rapid{stroke:#64748b;stroke-dasharray:1.2 0.8}.linear{stroke:#2563eb}.arc-cw{stroke:#7c3aed}.arc-ccw{stroke:#db2777}.point{fill:#0f172a}.travel-limit{fill:#cbd5e1;fill-opacity:.12;stroke:#334155;stroke-width:.35;stroke-dasharray:2 1}.violation{stroke:#dc2626;stroke-width:.65}.violation-point{fill:#dc2626;stroke:#fff;stroke-width:.25}</style>\n",
  )
  svg.write_string(
    "  <style>text{font-family:Inter,ui-sans-serif,system-ui,sans-serif;fill:#0f172a}.title{font-weight:700}.meta,.axis-label,.tick{fill:#475569}.tick{fill:#64748b;text-anchor:middle}.axis-label{text-anchor:middle}.header-rule{stroke:#cbd5e1;stroke-width:.25}.grid{stroke:#94a3b8;stroke-opacity:.32;stroke-width:.18}.status-pass{fill:#047857}.status-fail{fill:#b91c1c}.status-incomplete{fill:#b45309}.legend-label{fill:#334155}</style>\n",
  )
  svg.write_string(
    "  <rect x=\"\{view_x}\" y=\"\{view_y}\" width=\"\{view_width}\" height=\"\{view_height}\" fill=\"#f8fafc\" rx=\"\{font_size * 0.55}\" />\n",
  )
  svg_write_text(
    svg,
    "title",
    content_left,
    title_y,
    font_size * 1.35,
    "CNC G-code Preflight",
  )
  let status_detail = if report.analysis_complete {
    "Analysis complete"
  } else {
    "Analysis incomplete"
  }
  svg_write_text(
    svg,
    svg_status_class(report.status),
    content_left,
    status_y,
    font_size,
    "\{svg_status(report.status)} · \{status_detail}",
  )
  svg_write_text(
    svg,
    "meta",
    content_left,
    summary_y,
    font_size * 0.85,
    "\{report.segments.length()} moves · \{svg_rounded_number(report.distance_mm)} mm · \{report.diagnostics.length()} diagnostics · \{svg_estimate_text(report)}",
  )
  svg.write_string(
    "  <path class=\"header-rule\" d=\"M \{content_left} \{map_top - padding * 0.45} H \{content_left + content_width}\" />\n",
  )
  if show_limits {
    svg.write_string(
      "  <rect class=\"travel-limit\" x=\"\{limits.x.min}\" y=\"\{-limits.y.max}\" width=\"\{limits.x.max - limits.x.min}\" height=\"\{limits.y.max - limits.y.min}\"><title>Configured XY travel boundary (mm)</title></rect>\n",
    )
  }
  if show_limits {
    for division in 1..<4 {
      let x = limits.x.min +
        (limits.x.max - limits.x.min) * division.to_double() / 4.0
      let y = limits.y.min +
        (limits.y.max - limits.y.min) * division.to_double() / 4.0
      svg.write_string(
        "  <path class=\"grid\" d=\"M \{x} \{-limits.y.max} V \{-limits.y.min} M \{limits.x.min} \{-y} H \{limits.x.max}\" />\n",
      )
    }
    for division in 0..<5 {
      let x = limits.x.min +
        (limits.x.max - limits.x.min) * division.to_double() / 4.0
      let y = limits.y.min +
        (limits.y.max - limits.y.min) * division.to_double() / 4.0
      svg_write_text(
        svg,
        "tick",
        x,
        -limits.y.min + font_size * 0.9,
        font_size * 0.62,
        x.to_string(),
      )
      let tick_y = -y + font_size * 0.22
      svg.write_string(
        "  <text class=\"tick\" x=\"\{limits.x.min - font_size * 0.55}\" y=\"\{tick_y}\" font-size=\"\{font_size * 0.62}\" text-anchor=\"end\">\{y}</text>\n",
      )
    }
    svg_write_text(
      svg,
      "axis-label",
      (limits.x.min + limits.x.max) / 2.0,
      -limits.y.min + font_size * 1.75,
      font_size * 0.72,
      "X coordinate (mm)",
    )
    let y_label_x = limits.x.min - font_size * 2.8
    let y_label_y = -((limits.y.min + limits.y.max) / 2.0)
    svg.write_string(
      "  <text class=\"axis-label\" x=\"\{y_label_x}\" y=\"\{y_label_y}\" font-size=\"\{font_size * 0.72}\" transform=\"rotate(-90 \{y_label_x} \{y_label_y})\">Y coordinate (mm)</text>\n",
    )
  }
  for segment in report.segments {
    svg.write_string(
      "  <path class=\"\{svg_segment_class_for_report(report, segment)}\" d=\"\{svg_segment_path(segment)}\" data-line=\"\{segment.line}\" />\n",
    )
  }
  if report.segments.length() > 0 {
    let first = report.segments[0].start_mm
    svg.write_string(
      "  <circle class=\"point\" cx=\"\{first.x}\" cy=\"\{-first.y}\" r=\"0.55\"><title>Program start</title></circle>\n",
    )
    for segment in report.segments {
      svg.write_string(
        "  <circle class=\"point\" cx=\"\{segment.end_mm.x}\" cy=\"\{-segment.end_mm.y}\" r=\"0.3\"><title>Line \{segment.line}</title></circle>\n",
      )
    }
  }
  for diagnostic in report.diagnostics {
    if diagnostic.code.has_prefix("TRAVEL_LIMIT_") {
      match (diagnostic.line, diagnostic.point_mm) {
        (Some(line), Some(point)) =>
          svg.write_string(
            "  <circle class=\"violation-point\" cx=\"\{point.x}\" cy=\"\{-point.y}\" r=\"0.9\" data-line=\"\{line}\"><title>Line \{line}: \{diagnostic.code} at X\{point.x} Y\{point.y} Z\{point.z} mm</title></circle>\n",
          )
        _ => ()
      }
    }
  }
  let legend_x = content_left
  let legend_gap = font_size * 11.5
  svg_write_legend_item(
    svg,
    "rapid",
    "Rapid",
    legend_x,
    footer_y,
    font_size * 0.72,
  )
  svg_write_legend_item(
    svg,
    "linear",
    "Linear feed",
    legend_x + legend_gap,
    footer_y,
    font_size * 0.72,
  )
  svg_write_legend_item(
    svg,
    "arc-cw",
    "CW arc",
    legend_x + legend_gap * 2.0,
    footer_y,
    font_size * 0.72,
  )
  svg_write_legend_item(
    svg,
    "arc-ccw",
    "CCW arc",
    legend_x + legend_gap * 3.0,
    footer_y,
    font_size * 0.72,
  )
  svg_write_text(
    svg,
    "meta",
    content_left,
    footer_y + font_size * 1.6,
    font_size * 0.62,
    "XY top view · red marks indicate travel-limit violations · units: mm",
  )
  svg.write_string("</svg>\n")
  svg.to_string()
}
