// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "gckbbrant/gcode-preflight"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/gckbbrant/gcode-preflight"

license = "Apache-2.0"

keywords = [ "gcode", "cnc", "preflight", "moonbit" ]

preferred_target = "native"

description = "Static preflight checks and XY toolpath previews for a supported three-axis CNC G-code subset."

import {
  "moonbitlang/async@0.20.2",
}
