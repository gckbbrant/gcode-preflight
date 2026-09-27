///|
priv struct GCodeWord {
  address : Char
  value : Double
}

///|
priv struct GCodeBlock {
  line : Int
  words : Array[GCodeWord]
}

///|
priv struct ParsedProgram {
  blocks : Array[GCodeBlock]
  diagnostics : Array[Diagnostic]
}

///|
fn is_number_char(c : Char) -> Bool {
  c.is_ascii_digit() || c == '.' || c == '+' || c == '-'
}

///|
fn parse_decimal(chars : Array[Char], start : Int) -> (Double, Int, Bool) {
  let mut i = start
  let mut sign = 1.0
  if i < chars.length() && chars[i] == '-' {
    sign = -1.0
    i += 1
  } else if i < chars.length() && chars[i] == '+' {
    i += 1
  }
  let mut whole = 0.0
  let mut digits = 0
  while i < chars.length() && chars[i].is_ascii_digit() {
    whole = whole * 10.0 + (chars[i].to_int() - '0'.to_int()).to_double()
    digits += 1
    i += 1
  }
  let mut fraction = 0.0
  let mut scale = 1.0
  if i < chars.length() && chars[i] == '.' {
    i += 1
    while i < chars.length() && chars[i].is_ascii_digit() {
      fraction = fraction * 10.0 +
        (chars[i].to_int() - '0'.to_int()).to_double()
      scale *= 10.0
      digits += 1
      i += 1
    }
  }
  if digits == 0 {
    return (0.0, start, false)
  }
  (sign * (whole + fraction / scale), i, true)
}

///|
fn add_lexical_issue(
  diagnostics : Array[Diagnostic],
  line : Int,
  code : String,
  message : String,
) -> Unit {
  diagnostics.push({
    code,
    message,
    line: Some(line),
    severity: Error,
    incomplete: true,
  })
}

///|
fn lex_line(
  line : StringView,
  line_number : Int,
) -> (GCodeBlock?, Array[Diagnostic]) {
  let chars = line.to_array()
  let words : Array[GCodeWord] = []
  let diagnostics : Array[Diagnostic] = []
  let mut i = 0
  let mut in_comment = false
  let mut saw_word = false
  while i < chars.length() {
    let c = chars[i]
    if in_comment {
      if c == ')' {
        in_comment = false
      } else if c == '(' {
        add_lexical_issue(
          diagnostics, line_number, "NESTED_COMMENT", "Nested parenthesis comments are outside the supported subset.",
        )
      }
      i += 1
    } else if c == ';' {
      break
    } else if c == '(' {
      in_comment = true
      i += 1
    } else if c == ')' {
      add_lexical_issue(
        diagnostics, line_number, "UNMATCHED_COMMENT_END", "A closing parenthesis has no matching comment opener.",
      )
      i += 1
    } else if c.is_ascii_whitespace() || c == '%' {
      i += 1
    } else if c == '/' {
      add_lexical_issue(
        diagnostics, line_number, "BLOCK_DELETE_UNSUPPORTED", "Block-delete markers are not interpreted.",
      )
      i += 1
      while i < chars.length() && chars[i].is_ascii_whitespace() {
        i += 1
      }
    } else if c == '*' {
      add_lexical_issue(
        diagnostics, line_number, "CHECKSUM_UNSUPPORTED", "Line checksums are not interpreted.",
      )
      break
    } else if c == '#' {
      add_lexical_issue(
        diagnostics, line_number, "MACRO_UNSUPPORTED", "Parameter and macro expressions are not interpreted.",
      )
      break
    } else if c.is_ascii_alphabetic() {
      let address = c.to_ascii_uppercase()
      let (value, next, valid) = parse_decimal(chars, i + 1)
      if !valid {
        add_lexical_issue(
          diagnostics, line_number, "MISSING_WORD_VALUE", "A word address is not followed by a numeric value.",
        )
        i += 1
      } else {
        words.push({ address, value })
        saw_word = true
        i = next
      }
    } else if is_number_char(c) {
      add_lexical_issue(
        diagnostics, line_number, "NUMBER_WITHOUT_ADDRESS", "A numeric value is not preceded by a word address.",
      )
      let (_, next, valid) = parse_decimal(chars, i)
      i = if valid { next } else { i + 1 }
    } else {
      add_lexical_issue(
        diagnostics, line_number, "UNEXPECTED_CHARACTER", "The block contains a character outside the supported G-code syntax.",
      )
      i += 1
    }
  }
  if in_comment {
    add_lexical_issue(
      diagnostics, line_number, "UNCLOSED_COMMENT", "A parenthesis comment is not closed before the end of the line.",
    )
  }
  let block = if saw_word { Some({ line: line_number, words }) } else { None }
  (block, diagnostics)
}

///|
fn parse_program(program : String) -> ParsedProgram {
  let blocks : Array[GCodeBlock] = []
  let diagnostics : Array[Diagnostic] = []
  for line_number, line in program.split("\n") {
    let (block, line_diagnostics) = lex_line(line, line_number + 1)
    for diagnostic in line_diagnostics {
      diagnostics.push(diagnostic)
    }
    match block {
      Some(block) => blocks.push(block)
      None => ()
    }
  }
  { blocks, diagnostics }
}
