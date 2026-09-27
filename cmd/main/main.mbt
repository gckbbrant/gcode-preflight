///|
extern "C" fn preflight_exit(code : Int) -> Unit = "exit"

///|
fn status_text(status : @app.AnalysisStatus) -> String {
  match status {
    Pass => "PASS"
    Fail => "FAIL"
    Incomplete => "INCOMPLETE"
  }
}

///|
fn severity_text(severity : @app.DiagnosticSeverity) -> String {
  match severity {
    Error => "ERROR"
    Warning => "WARNING"
    Info => "INFO"
  }
}

///|
fn one_value(values : Map[String, Array[String]], key : String) -> String raise {
  match values.get(key) {
    Some([value, ..]) => value
    _ => fail("missing required CLI value: \{key}")
  }
}

///|
fn human_report(report : @app.AnalysisReport) -> String {
  let output = StringBuilder()
  output.write_string("Status: \{status_text(report.status)}\n")
  output.write_string("Analysis complete: \{report.analysis_complete}\n")
  output.write_string("Time estimate complete: \{report.estimate_complete}\n")
  output.write_string("Motion segments: \{report.segments.length()}\n")
  let path_length_label = if report.analysis_complete {
    "Total path length"
  } else {
    "Analyzed prefix length"
  }
  output.write_string("\{path_length_label}: \{report.distance_mm} mm\n")
  output.write_string("Dwell time: \{report.dwell_seconds} s\n")
  output.write_string("Tool changes: \{report.tool_changes}\n")
  match report.estimated_time_seconds {
    Some(seconds) => output.write_string("Estimated cycle time: \{seconds} s\n")
    None => output.write_string("Estimated cycle time: unavailable\n")
  }
  if report.diagnostics.length() > 0 {
    output.write_string("\nDiagnostics:\n")
    for diagnostic in report.diagnostics {
      output.write_string("  ")
      match diagnostic.line {
        Some(line) => output.write_string("line \{line}: ")
        None => ()
      }
      output.write_string(
        "[\{severity_text(diagnostic.severity)}] \{diagnostic.code}: \{diagnostic.message}",
      )
      if diagnostic.incomplete {
        output.write_string(" (analysis incomplete)")
      }
      output.write_char('\n')
    }
  }
  output.to_string()
}

///|
async fn main {
  let check_command = @argparse.Command(
    "check",
    about="Check a supported three-axis milling G-code program.",
    positionals=[
      @argparse.PositionArg("program", about="Input .nc or .tap program."),
    ],
    options=[
      @argparse.OptionArg(
        "profile",
        about="Machine profile JSON.",
        required=true,
      ),
      @argparse.OptionArg("svg", about="Write an XY toolpath SVG."),
      @argparse.OptionArg("json", about="Write a JSON analysis report."),
    ],
  )
  let command = @argparse.Command(
    "gcode-preflight",
    about="Preflight a supported CNC G-code subset.",
    subcommands=[check_command],
    subcommand_required=true,
  )
  let matches = command.parse()
  match matches.subcommand {
    Some(("check", args)) => {
      let program_path = one_value(args.values, "program")
      let profile_path = one_value(args.values, "profile")
      let program = @fs.read_file(program_path).text()
      let profile_text = @fs.read_file(profile_path).text()
      let profile_json = @json.parse(profile_text)
      let profile : @app.MachineProfile = @json.from_json(profile_json)
      let report = @app.analyze(program, profile)
      @stdio.stdout.write(human_report(report))
      match args.values.get("svg") {
        Some([path, ..]) =>
          @fs.write_file(
            path,
            @app.render_svg(report),
            create_mode=@fs.CreateOrTruncate,
          )
        _ => ()
      }
      match args.values.get("json") {
        Some([path, ..]) =>
          @fs.write_file(
            path,
            @json.to_json(report).stringify(indent=2) + "\n",
            create_mode=@fs.CreateOrTruncate,
          )
        _ => ()
      }
      if report.status is Pass {
        ()
      } else {
        preflight_exit(1)
      }
    }
    _ => fail("expected the check subcommand")
  }
}
