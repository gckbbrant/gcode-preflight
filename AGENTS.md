# 项目开发约定

这是一个 MoonBit 项目。MoonBit 官方文档见 [docs.moonbitlang.com](https://docs.moonbitlang.com)。

## 项目结构

- 每个目录按 package 组织，并在 `moon.pkg` 中声明依赖；`_test.mbt` 为黑盒测试文件，`_wbtest.mbt` 为白盒测试文件。
- 根目录的 `moon.mod` 保存模块信息。

## 代码约定

- MoonBit 代码按 `///|` 分块。块之间可以独立组织，不依赖文件中的先后顺序。
- 弃用的代码块尽量放入各自目录中的 `deprecated.mbt`。

## 常用工具

- 使用 `moon fmt` 格式化代码。
- 使用 `moon ide` 的 `peek-def`、`outline` 和 `find-references` 查看定义与引用。
- 使用 `moon info` 更新 package 生成的 `.mbti` 接口文件。修改接口后检查 `.mbti` 差异是否符合预期。
- 完成代码修改后运行 `moon info`、`moon fmt` 和 `moon test`。快照测试的预期输出需要更新时，运行 `moon test --update`。
- 对稳定结果优先使用 `assert_eq` 或模式断言。需要检查结构化调试输出时使用 `Debug` 和 `debug_inspect`。可以运行 `moon coverage analyze` 查看测试覆盖情况。
