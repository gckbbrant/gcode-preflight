///|
fn component(vector : Vec3, axis : Int) -> Double {
  match axis {
    0 => vector.x
    1 => vector.y
    _ => vector.z
  }
}

///|
fn positive_angular_distance(from : Double, to : Double) -> Double {
  let turn = 2.0 * @math.PI
  let mut distance = to - from
  while distance < 0.0 {
    distance += turn
  }
  while distance >= turn {
    distance -= turn
  }
  distance
}

///|
fn arc_contains_angle(
  start : Double,
  sweep : Double,
  candidate : Double,
) -> Bool {
  let distance = if sweep >= 0.0 {
    positive_angular_distance(start, candidate)
  } else {
    positive_angular_distance(candidate, start)
  }
  distance <= sweep.abs() + 0.000000001
}

///|
fn arc_max_abs_trig(start : Double, sweep : Double, sine : Bool) -> Double {
  let end = start + sweep
  let mut maximum = if sine {
    @math.sin(start).abs().max(@math.sin(end).abs())
  } else {
    @math.cos(start).abs().max(@math.cos(end).abs())
  }
  let candidates = if sine {
    [@math.PI / 2.0, 3.0 * @math.PI / 2.0]
  } else {
    [0.0, @math.PI]
  }
  for candidate in candidates {
    if arc_contains_angle(start, sweep, candidate) {
      maximum = 1.0
    }
  }
  maximum
}

///|
fn segment_axis_fractions(segment : ToolPathSegment) -> Vec3 {
  if segment.length_mm <= 0.000000001 {
    return { x: 0.0, y: 0.0, z: 0.0, }
  }
  match segment.center_mm {
    Some(center) if segment.sweep_radians.abs() > 0.000000001 => {
      let dx = segment.start_mm.x - center.x
      let dy = segment.start_mm.y - center.y
      let radius = (dx * dx + dy * dy).sqrt()
      let start_angle = @math.atan2(dy, dx)
      let length_per_radian = segment.length_mm / segment.sweep_radians.abs()
      {
        x: radius *
        arc_max_abs_trig(start_angle, segment.sweep_radians, true) /
        length_per_radian,
        y: radius *
        arc_max_abs_trig(start_angle, segment.sweep_radians, false) /
        length_per_radian,
        z: (segment.end_mm.z - segment.start_mm.z).abs() / segment.length_mm,
      }
    }
    _ =>
      {
        x: (segment.end_mm.x - segment.start_mm.x).abs() / segment.length_mm,
        y: (segment.end_mm.y - segment.start_mm.y).abs() / segment.length_mm,
        z: (segment.end_mm.z - segment.start_mm.z).abs() / segment.length_mm,
      }
  }
}

///|
fn segment_curvature_factors(segment : ToolPathSegment) -> Vec3 {
  match segment.center_mm {
    Some(center) if segment.sweep_radians.abs() > 0.000000001 => {
      let dx = segment.start_mm.x - center.x
      let dy = segment.start_mm.y - center.y
      let radius = (dx * dx + dy * dy).sqrt()
      let start_angle = @math.atan2(dy, dx)
      let length_per_radian = segment.length_mm / segment.sweep_radians.abs()
      let curvature_scale = radius / (length_per_radian * length_per_radian)
      {
        x: curvature_scale *
        arc_max_abs_trig(start_angle, segment.sweep_radians, false),
        y: curvature_scale *
        arc_max_abs_trig(start_angle, segment.sweep_radians, true),
        z: 0.0,
      }
    }
    _ => { x: 0.0, y: 0.0, z: 0.0, }
  }
}

///|
fn requested_segment_speed(
  segment : ToolPathSegment,
  profile : MachineProfile,
) -> Double? {
  match segment.kind {
    Rapid => Some(profile.rapid_mm_per_min)
    Linear | ClockwiseArc | CounterclockwiseArc =>
      match segment.feed_mm_per_min {
        Some(feed) if feed > 0.0 => Some(feed)
        _ => None
      }
  }
}

///|
fn limited_path_speed(
  requested_mm_per_min : Double,
  fractions : Vec3,
  limits : Vec3?,
) -> Double {
  match limits {
    Some(axis_limits) => {
      let mut speed = requested_mm_per_min
      for axis in 0..<3 {
        let fraction = component(fractions, axis)
        if fraction > 0.000000001 {
          speed = speed.min(component(axis_limits, axis) / fraction)
        }
      }
      speed
    }
    None => requested_mm_per_min
  }
}

///|
fn trapezoidal_rest_to_rest_seconds(
  distance_mm : Double,
  maximum_speed_mm_per_second : Double,
  acceleration_mm_per_second2 : Double,
) -> Double {
  if distance_mm <= 0.000000001 {
    return 0.0
  }
  let transition_distance = maximum_speed_mm_per_second *
    maximum_speed_mm_per_second /
    acceleration_mm_per_second2
  if distance_mm >= transition_distance {
    2.0 * maximum_speed_mm_per_second / acceleration_mm_per_second2 +
    (distance_mm - transition_distance) / maximum_speed_mm_per_second
  } else {
    2.0 * (distance_mm / acceleration_mm_per_second2).sqrt()
  }
}

///|
fn time_estimate_model(profile : MachineProfile) -> String {
  if profile.axis_max_acceleration_mm_per_sec2 is Some(_) {
    "axis_trapezoidal_rest_to_rest"
  } else if profile.axis_max_velocity_mm_per_min is Some(_) {
    "axis_velocity_limited"
  } else {
    "nominal_path_length"
  }
}

///|
fn segment_cycle_time_seconds(
  segment : ToolPathSegment,
  profile : MachineProfile,
) -> Double? {
  if segment.length_mm <= 0.000000001 {
    return Some(0.0)
  }
  let requested_speed = match requested_segment_speed(segment, profile) {
    Some(speed) if speed > 0.0 => speed
    _ => return None
  }
  let fractions = segment_axis_fractions(segment)
  let mut path_speed_mm_per_min = limited_path_speed(
    requested_speed,
    fractions,
    profile.axis_max_velocity_mm_per_min,
  )
  let mut path_acceleration_mm_per_sec2 : Double? = None
  match profile.axis_max_acceleration_mm_per_sec2 {
    Some(axis_acceleration) => {
      let curvature = segment_curvature_factors(segment)
      let is_arc = segment.center_mm is Some(_)
      let reserved_fraction = if is_arc { 0.5 } else { 1.0 }
      if is_arc {
        for axis in 0..<3 {
          let curvature_factor = component(curvature, axis)
          if curvature_factor > 0.000000001 {
            let centripetal_budget = component(axis_acceleration, axis) *
              reserved_fraction
            let curvature_speed_mm_per_second = (centripetal_budget /
            curvature_factor).sqrt()
            path_speed_mm_per_min = path_speed_mm_per_min.min(
              curvature_speed_mm_per_second * 60.0,
            )
          }
        }
      }
      let mut path_acceleration = 0.0
      let mut has_path_acceleration = false
      for axis in 0..<3 {
        let fraction = component(fractions, axis)
        if fraction > 0.000000001 {
          let available = component(axis_acceleration, axis) * reserved_fraction
          let axis_path_acceleration = available / fraction
          path_acceleration = if has_path_acceleration {
            path_acceleration.min(axis_path_acceleration)
          } else {
            axis_path_acceleration
          }
          has_path_acceleration = true
        }
      }
      if has_path_acceleration {
        path_acceleration_mm_per_sec2 = Some(path_acceleration)
      }
    }
    None => ()
  }
  let path_speed_mm_per_second = path_speed_mm_per_min / 60.0
  if path_speed_mm_per_second <= 0.0 {
    return None
  }
  match path_acceleration_mm_per_sec2 {
    Some(acceleration) if acceleration > 0.0 =>
      Some(
        trapezoidal_rest_to_rest_seconds(
          segment.length_mm,
          path_speed_mm_per_second,
          acceleration,
        ),
      )
    _ => Some(segment.length_mm / path_speed_mm_per_second)
  }
}
