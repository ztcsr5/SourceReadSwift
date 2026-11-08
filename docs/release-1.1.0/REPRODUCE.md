# 重现与回滚

所有应用源码已提交在 `codex/release-1.1.0`；测试/打包源码提交以 `F:/SourceReadSwift/release-1.1.0/artifact-commit.json` 为准。没有自动重置用户Git历史，也没有删除原有备份。

## 本机验证（PowerShell）

```powershell
Set-Location -LiteralPath 'D:/Gemini反重力/SourceReadSwift2'
python -X utf8 'D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.0/browser_qa.py'
python -X utf8 'D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.0/motion_regression.py'
python -X utf8 'D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.0/package_release.py'
git diff --check
```

浏览器测试需要 Python Playwright 与本机 Edge/Chrome；必要时 `python -m pip install playwright`、`python -m playwright install chromium`。动画对照测试需要 Node.js。图谱需要 `graphifyy`，它是审查辅助，不是编译器或正确性证明。
打包证据脚本读取现有 copy-first BASELINE，不在原项目上做回滚。输出的 `reproduction` 是脚本归档；这些脚本应从上述项目 docs 目录运行，不能假定移动后相对路径仍可用。

## 原生验证

Windows不能运行Xcode。CI使用仓库的 iOS 与 Unsigned IPA 工作流，实际run链接、原始日志、xcresult归档和测试计数见 VERIFICATION.txt。较新模拟器通过不代表iOS16设备通过；设备步骤见 DEVICE_ACCEPTANCE.md。

## 回滚源码（不回滚手机数据）

```powershell
& 'F:/SourceReadSwift/release-1.1.0/ROLLBACK.ps1' -Root 'D:/Gemini反重力/SourceReadSwift2'
```

这会恢复本轮涉及的文件，删除本轮新增且哈希匹配的文件；未知后续编辑会被拒绝覆盖。它**不**重置Git分支/提交、不删除其他未跟踪文件，也不操作手机书架/阅读记录。执行后Git会显示相对于当前提交的反向差异，属于预期。

需要重新应用补丁时，先在独立副本中使用 `ROLLBACK.py --root <副本绝对路径> --canonical` 得到Git标准LF基线，再 `git apply --check F:/SourceReadSwift/release-1.1.0/DIFF_FILE.patch` 和 `git apply`。完整哈希演练见 VERIFICATION-local.json；不要在有未知后续编辑的工作区强行覆盖。
