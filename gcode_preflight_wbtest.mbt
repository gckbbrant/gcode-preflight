///|
test "lexer accepts compact words and ignores both comment styles" {
  let parsed = parse_program("(job)\nN10G1X1.25Y-2.5F100 (cut) ; tail\n")
  assert_eq(parsed.blocks.length(), 1)
  assert_eq(parsed.blocks[0].words.length(), 5)
  assert_eq(parsed.blocks[0].words[1].address, 'G')
  assert_eq(parsed.blocks[0].words[2].value, 1.25)
  assert_eq(parsed.blocks[0].words[3].value, -2.5)
  assert_eq(parsed.diagnostics.length(), 0)
}

///|
test "modal preamble makes a feed move interpretable" {
  let parsed = parse_program(
    "G17 G21 G90 G91.1 G94 G54 G40 G49\nG1 X1 Y2 F100\nM2",
  )
  assert_eq(inspect_modal_program(parsed).length(), 0)
}

///|
test "rapid moves do not require arc-center or feed modes" {
  let diagnostics = inspect_modal_program(
    parse_program("G21 G90 G54 G40 G49 G0 X1 Y2"),
  )
  assert_eq(diagnostics.length(), 0)
}

///|
test "missing setup modes are incomplete" {
  let diagnostics = inspect_modal_program(parse_program("G1 X1 F100"))
  assert_true(
    diagnostics.any(d => d.code == "MISSING_MODAL_SETUP" && d.incomplete),
  )
  assert_true(
    diagnostics.any(d => {
      d.code == "MISSING_MODAL_SETUP" && d.message.contains("G54")
    }),
  )
}

///|
test "conflicting motion modes are incomplete" {
  let diagnostics = inspect_modal_program(parse_program("G0 G1 X1"))
  assert_true(
    diagnostics.any(d => d.code == "CONFLICTING_MODAL_CODES" && d.incomplete),
  )
}

///|
test "unknown motion-affecting code is incomplete" {
  let diagnostics = inspect_modal_program(
    parse_program("G17 G21 G90 G91.1 G94 G54 G40 G49 G71"),
  )
  assert_true(
    diagnostics.any(d => d.code == "UNSUPPORTED_G_CODE" && d.incomplete),
  )
}

///|
test "feed and spindle omissions are detected as program errors" {
  let diagnostics = inspect_modal_program(
    parse_program("G17 G21 G90 G91.1 G94 G54 G40 G49\nG1 X1\nM3"),
  )
  assert_true(diagnostics.any(d => d.code == "MISSING_FEED" && !d.incomplete))
  assert_true(
    diagnostics.any(d => d.code == "MISSING_SPINDLE_SPEED" && !d.incomplete),
  )
}

///|
test "R arcs and macro expressions are incomplete" {
  let diagnostics = inspect_modal_program(parse_program("G2 X1 Y0 R1\nG1 X#1"))
  assert_true(
    diagnostics.any(d => d.code == "R_ARC_UNSUPPORTED" && d.incomplete),
  )
  assert_true(
    diagnostics.any(d => d.code == "MACRO_UNSUPPORTED" && d.incomplete),
  )
}
