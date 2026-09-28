# Architecture diagram assets

This is the selected **layered pipeline** design for the implemented CNC
G-code preflight project. The picture follows the actual analysis flow and
module names in the repository.

- [`../images/architecture.svg`](../images/architecture.svg) is the standalone
  vector version.
- [`cnc-gcode-preflight-architecture.pptx`](cnc-gcode-preflight-architecture.pptx)
  is a 16:9, one-slide PowerPoint. All visible diagram parts are native shapes,
  text boxes, and lines, so they can be selected and changed in PowerPoint.
- [`generate_architecture_pptx.mjs`](generate_architecture_pptx.mjs) is the
  authoring source. Run it with Node.js 24 and `@oai/artifact-tool` 2.x
  available to the module loader:

  ```sh
  node docs/architecture/generate_architecture_pptx.mjs
  ```

  Optional positional arguments select the output `.pptx` and preview `.png`
  paths. In an environment where the package name does not resolve, set
  `ARTIFACT_TOOL_ENTRY` to the absolute path of `dist/artifact_tool.mjs`.

The repository acceptance check verifies the committed PowerPoint package has
one 16:9 slide, the expected diagram labels, and native editable shapes rather
than embedded screenshots:

```sh
python scripts/check_architecture_pptx.py
```

## What the diagram means

The CLI accepts a G-code program and `MachineProfile`, then calls the pure
MoonBit analysis API. The core sequence is represented by `lexer.mbt`,
`modal.mbt`, `geometry.mbt`, and `timing.mbt`; `model.mbt` defines the report
data. The CLI emits a terminal summary, JSON report, and SVG toolpath. An
incomplete interpretation cannot produce PASS. The cycle estimate remains a
planning estimate and the diagram does not imply machine-safety certification.
