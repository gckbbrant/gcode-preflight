import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const artifactToolEntry = process.env.ARTIFACT_TOOL_ENTRY;
const { Presentation, PresentationFile } = artifactToolEntry
  ? await import(pathToFileURL(path.resolve(artifactToolEntry)).href)
  : await import("@oai/artifact-tool");

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const output = path.resolve(
  process.argv[2] ?? path.join(root, "_build/architecture-pptx/candidate.pptx"),
);
const previewOutput = path.resolve(
  process.argv[3] ?? path.join(root, "_build/architecture-pptx/slide-1.png"),
);
const C = {
  navy: "#16334F",
  text: "#18344F",
  muted: "#5F7386",
  label: "#55738E",
  border: "#D5E0E9",
  line: "#70869A",
  blue: "#347DAB",
  teal: "#148B83",
  purple: "#745CB1",
  canvas: "#FFFFFF",
  surface: "#F6F9FB",
  pale: "#F8FBFD",
  pass: "#E8F5EF",
  passText: "#187454",
  fail: "#FBEeed",
  failText: "#A43D39",
  incomplete: "#FBF4E4",
  incompleteText: "#946316",
};
const FONT = "Microsoft YaHei";

const presentation = Presentation.create({
  slideSize: { width: 1600, height: 900 },
});
const slide = presentation.slides.add();
slide.background.fill = C.canvas;

function shape(geometry, name, x, y, w, h, fill, stroke = "none", strokeWidth = 0) {
  return slide.shapes.add({
    geometry,
    name,
    position: { left: x, top: y, width: w, height: h },
    fill,
    line: { style: "solid", fill: stroke, width: strokeWidth },
  });
}

function text(name, value, x, y, w, h, size, color = C.text, options = {}) {
  const item = shape("textbox", name, x, y, w, h, "none");
  item.text = value;
  item.text.style = {
    typeface: FONT,
    fontSize: size,
    color,
    bold: options.bold ?? false,
    alignment: options.align ?? "left",
    verticalAlignment: options.valign ?? "middle",
    wrap: "square",
    autoFit: "shrinkText",
    insets: { top: 0, right: 0, bottom: 0, left: 0 },
  };
  return item;
}

function card(name, x, y, w, h, title, bodyLines, accent, tag = undefined) {
  const base = shape("roundRect", `${name}-surface`, x, y, w, h, "#FFFFFF", C.border, 2);
  base.borderRadius = 16;
  shape("roundRect", `${name}-accent`, x, y, 8, h, accent, "none", 0).borderRadius = 4;
  text(`${name}-title`, title, x + 25, y + 13, w - 50, 33, 25, C.text, { bold: true });
  text(`${name}-body`, bodyLines.join("\n"), x + 25, y + 48, w - 50, h - 57, 18, C.muted);
  if (tag) {
    const tagW = Math.max(110, tag.length * 9 + 22);
    const tagShape = shape(
      "roundRect", `${name}-source-tag`, x + w - tagW - 14, y + 10,
      tagW, 26, "#EDF3F7", "none", 0,
    );
    tagShape.borderRadius = 13;
    text(`${name}-source-tag-text`, tag, x + w - tagW - 14, y + 10, tagW, 26, 13, accent,
      { bold: true, align: "center" });
  }
  return base;
}

function line(name, x1, y1, x2, y2, color = C.line, width = 3) {
  return shape("line", name, x1, y1, x2 - x1, y2 - y1, "none", color, width);
}

function arrowHead(name, x, y, direction, color, size = 13) {
  const triangle = shape("triangle", name, x - size / 2, y - size / 2, size, size, color);
  triangle.position = {
    left: x - size / 2,
    top: y - size / 2,
    width: size,
    height: size,
    rotation: direction === "right" ? 90 : 180,
  };
  return triangle;
}

function horizontalArrow(name, x1, y, x2, color = C.line, width = 3) {
  line(`${name}-shaft`, x1, y, x2 - 7, y, color, width);
  arrowHead(`${name}-head`, x2 - 1, y, "right", color);
}

function verticalArrow(name, x, y1, y2, color = C.line, width = 3) {
  line(`${name}-shaft`, x, y1, x, y2 - 7, color, width);
  arrowHead(`${name}-head`, x, y2 - 1, "down", color);
}

// Heading and the two public input surfaces.
text("eyebrow", "SYSTEM ARCHITECTURE", 80, 36, 420, 30, 18, C.label, { bold: true });
text("title", "CNC G-code 预检器架构", 80, 67, 1100, 58, 42, C.navy, { bold: true });
text("subtitle", "从程序与机床配置到可追溯的行程诊断、时间估算和可视化结果", 80, 127, 1350, 34, 21, C.muted);
shape("line", "header-rule", 80, 173, 1440, 0, "none", "#D8E2EB", 2);

text("input-layer-label", "输入与接口层", 80, 183, 420, 27, 19, C.label, { bold: true });
const input = card(
  "program-input", 80, 211, 620, 100, "任务输入",
  ["G-code 程序  .nc / .tap", "MachineProfile  行程 · 偏置 · 轴约束"], C.blue,
);
const cli = card(
  "native-cli", 900, 211, 620, 100, "原生 CLI  ·  cmd/main",
  ["argparse 接收文件与选项", "调用 analyze(program, profile) 并写出结果"], C.blue,
);
horizontalArrow("input-to-cli", 700, 261, 900, "#6F94AE", 4);

// Core analysis boundary and ordered processing stages.
const core = shape("roundRect", "moonbit-analysis-core", 62, 333, 1476, 380, C.surface, "#D9E4EC", 2);
core.borderRadius = 22;
text("core-title", "MoonBit 分析核心  ·  analyze(program, profile)", 92, 347, 880, 38, 24, "#183B58", { bold: true });
text("core-note", "纯逻辑分析路径", 1240, 349, 260, 34, 16, "#6D8498", { align: "right" });

horizontalArrow("lexer-to-modal", 390, 465, 435, C.line, 3);
horizontalArrow("modal-to-geometry", 735, 465, 780, C.line, 3);
horizontalArrow("geometry-to-timing", 1115, 465, 1160, C.line, 3);
line("geometry-report-drop", 947, 525, 947, 548, "#8B9CAD", 3);
line("timing-report-drop", 1325, 525, 1325, 548, "#8B9CAD", 3);
line("report-feed-trunk", 800, 548, 1325, 548, "#8B9CAD", 3);
verticalArrow("report-feed-arrow", 800, 548, 566, "#8B9CAD", 3);

const lexer = card("lexer", 90, 405, 300, 120, "词法解析", ["注释 / 紧凑字词", "代码 → 有行号的块"], C.blue, "lexer.mbt");
const modal = card("modal", 435, 405, 300, 120, "模态状态", ["单位 · 坐标 · 平面", "进给 / 偏置 / 补偿模式"], C.blue, "modal.mbt");
const geometry = card("geometry", 780, 405, 335, 120, "几何与行程", ["直线 / XY 圆弧 / 螺旋", "机床坐标 · 越界诊断"], C.teal, "geometry.mbt");
const timing = card("timing", 1160, 405, 330, 120, "周期估算", ["G0 / 进给 / 暂停 / 换刀", "可选轴速度与加速度约束"], C.teal, "timing.mbt");

const report = card(
  "analysis-report", 475, 566, 650, 112, "AnalysisReport  ·  可追溯分析结果",
  ["状态 / 完整性 / 源行诊断 / 刀路段 / 距离与估算时间"], C.purple, "model.mbt",
);

// Report formats and the strict state contract.
const outputs = [
  card("cli-output", 80, 746, 430, 76, "CLI 摘要", ["终端状态与诊断"], C.purple),
  card("json-output", 585, 746, 430, 76, "JSON 报告", ["机器可读结果"], C.purple),
  card("svg-output", 1090, 746, 430, 76, "SVG 刀路图", ["XY 行程框 · 移动类型 · 越界标记"], C.purple),
];
line("report-output-drop", 800, 678, 800, 725, "#A294BF", 2);
line("output-branch", 295, 725, 1305, 725, "#A294BF", 2);
for (const [index, centerX] of [295, 800, 1305].entries()) {
  verticalArrow(`output-${index + 1}-arrow`, centerX, 725, 746, "#A294BF", 2);
}

function status(name, label, detail, x, w, fill, color) {
  const base = shape("roundRect", `${name}-status`, x, 846, w, 38, fill, "none", 0);
  base.borderRadius = 19;
  text(`${name}-status-label`, `${label}  ${detail}`, x + 12, 846, w - 24, 38, 16, color,
    { bold: true, align: "center" });
}
status("pass", "PASS", "完整且无确定违规", 80, 420, C.pass, C.passText);
status("fail", "FAIL", "支持范围内的确定错误", 535, 480, C.fail, C.failText);
status("incomplete", "INCOMPLETE", "未知语义不予放行", 1040, 480, C.incomplete, C.incompleteText);

slide.speakerNotes.textFrame.setText(
  "Architecture based on the repository's implemented MoonBit modules: lexer.mbt, modal.mbt, geometry.mbt, timing.mbt, model.mbt, and cmd/main. The core analysis remains pure logic. PASS, FAIL, and INCOMPLETE are mutually meaningful states; unsupported or ambiguous semantics cannot pass. The diagram describes implemented scope and does not claim machine safety certification.",
);

await fs.mkdir(path.dirname(output), { recursive: true });
await fs.mkdir(path.dirname(previewOutput), { recursive: true });
await (await PresentationFile.exportPptx(presentation)).save(output);
const preview = await presentation.export({ slide, format: "png", scale: 1 });
await fs.writeFile(previewOutput, new Uint8Array(await preview.arrayBuffer()));
console.log(`Draft written: ${output}`);
console.log(`Preview written: ${previewOutput}`);
