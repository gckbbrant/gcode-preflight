# 架构图说明

架构图对应仓库中的程序处理流程：命令行读取 G-code 和 `MachineProfile`，调用 MoonBit 分析核心，再输出终端摘要、JSON 报告和 SVG 刀路图。

[`../images/architecture.svg`](../images/architecture.svg) 是流程图的矢量文件。图中模块对应 `lexer.mbt`、`modal.mbt`、`geometry.mbt`、`timing.mbt` 和 `model.mbt`。

演示文件的生成脚本为 [`generate_architecture_pptx.mjs`](generate_architecture_pptx.mjs)，需要 Node.js 24 和 `@oai/artifact-tool` 2.x：

```sh
node docs/architecture/generate_architecture_pptx.mjs
```

可以用位置参数指定 `.pptx` 和 `.png` 输出路径。如果运行环境无法按包名导入依赖，可设置 `ARTIFACT_TOOL_ENTRY` 指向 `dist/artifact_tool.mjs`。

运行以下命令会检查演示文件的页数、比例、图中文字和图形结构：

```sh
python scripts/check_architecture_pptx.py
```

图中的 `PASS`、`FAIL` 和 `INCOMPLETE` 与分析报告状态一致。`PASS` 仅表示程序在当前支持范围内完整分析且没有发现确定错误；运行时间是估算值。
