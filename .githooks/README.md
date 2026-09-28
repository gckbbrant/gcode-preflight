# Git 提交钩子

## 提交前检查

提交前钩子会在执行 `git commit` 时自动运行检查。

## 启用方法

1. 确保钩子脚本具有执行权限：

   ```sh
   chmod +x .githooks/pre-commit
   ```

2. 将 Git 钩子目录设为 `.githooks`：

   ```sh
   git config core.hooksPath .githooks
   ```

设置完成后，`git commit` 会自动触发提交前检查。
