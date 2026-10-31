# Emacs，从这里开始

一份可以读懂、可以逐步改成自己的 Emacs 配置。采用原生键位，重点是编辑、基础 Org 笔记与 Jai；默认配色为 Zed 的 **Everforest Dark Soft (material)**。

要求 **GNU Emacs 31.1+**。本机已使用 Windows Emacs 31.1 验证；其他系统的主配置可移植，但尚未实机验证。设计参考 [Emacs Bedrock](https://github.com/ashton314/emacs-bedrock) 和 [kickstart.emacs](https://github.com/MiniApollo/kickstart.emacs)。

## 第一次使用

先显式启动这份配置。路径含空格时保留引号：

```powershell
& 'C:\Program Files\Emacs\emacs-31.1\bin\runemacs.exe' --init-directory 'F:\project\my-emacs'
```

其他机器使用 `emacs --init-directory /path/to/my-emacs`。旧的 `~/.emacs` 或 Windows `_emacs` 可能优先于目录配置；先备份这些入口，再验证加载路径。

首次运行 `M-x kickstart-install-packages`，安装完成后重启。平时启动不刷新包源、不自动更新，也不会自动下载语言服务器。包安装失败时可以继续基础编辑，联网后重新运行同一命令即可。

复制 `local.example.el` 为 `local.el`，设置本机 Jacket、ripgrep 路径及笔记目录。`local.el` 不进入 Git。本机的笔记入口设为 `C:/Users/zhouy/Documents/org/`，第一次按 `C-c n` 时才创建目录；通用默认值是 `~/org`。

## 先学这些键

`C-` 表示 Ctrl，`M-` 通常是 Alt；`C-x C-f` 是先按 Ctrl+X，再按 Ctrl+F。`M-x` 是按 Alt+X，输入命令名，再按 Enter。

| 键 | 用途 |
|---|---|
| `C-g` | 取消当前命令或提示 |
| `C-x C-f` / `C-x C-s` | 打开 / 保存文件 |
| `C-x b` / `C-x k` | 切换 / 关闭缓冲区 |
| `C-/` | 撤销 |
| `C-s` / `M-%` | 向前搜索 / 查询替换 |
| `C-x 2` / `C-x 3` | 上下 / 左右分屏 |
| `C-x o` / `C-x 1` | 切换窗口 / 只留当前窗口 |
| `C-h t` / `C-h k` | 官方教程 / 解释一个按键 |
| `C-c h` / `C-c e` / `C-c n` | 本地指南 / 主配置 / 笔记目录 |
| `M-s l` / `M-s r` | 搜索当前缓冲区 / 目录或项目内容 |
| `M-g i` | 当前文件的符号目录 |
| `C-x p f` / `C-x p p` | 项目文件 / 切换项目 |
| `C-M-i` | 当前位置补全；Windows 可按 Ctrl+Alt+I |

保留 `C-s` 等原生命令；新增搜索放在标准的 `M-s` 前缀。Which-key 会在前缀后停顿时提示下一步。补全窗口里使用上下方向键，`RET` 确认，`C-g` 退出。Corfu 默认手动触发，避免写笔记时不停弹出。

在 Emacs 中按 **`C-c h`** 阅读和练习 [guide.org](guide.org)。

## 配置怎么读、怎么改

1. `early-init.el`：只放初始窗口设置。
2. `init.el`：按用途分节；每个扩展直接使用 `use-package`，没有额外框架或生成步骤。
3. `lisp/kickstart-jai.el`：Jai 项目识别、Eglot 和手动格式化。
4. `themes/everforest-zed-theme.el`：独立主题，与 Zed 语义配色对应。

五个交互扩展：Vertico 显示候选列表，Orderless 支持多个词匹配，Marginalia 解释候选，Consult 搜索与导航，Corfu 显示正文补全。文件管理、项目、Org、Which-key、Eglot 和 Flymake 都使用 Emacs 内置功能。Jai 主模式通过内置 `package-vc` 从 [valignatev/jai-mode](https://github.com/valignatev/jai-mode) 安装。

添加扩展时，把包名加入 `kickstart-packages`，再加一个带 `(package-installed-p '包名)` 条件的 `use-package` 配置，然后运行安装命令。更新已有包使用 `M-x list-packages`，读完更新内容再选择；正常启动不会更新它们。

个人路径放 `local.el`；通过 `M-x customize` 产生的设置写入 `var/custom.el`。`var/`、`elpa/`、编译缓存、备份和锁文件都不进入 Git。备份与自动保存保持启用，保存至 `var/`，不污染工作项目。

## Jai

本机复用已有 Jacket 0.30.4，不安装或替换项目的编译器。`kickstart-jacket-directory` 指向同时含 `jailsp`、`jaifmt` 与 `stdlib/` 的工具链目录；留空时从 PATH 查找。

打开项目里的 `.jai` 自动进入 `jai-mode`，找到 `jailsp` 时自动启动 Eglot。`.git` 或 `jacket.toml` 标识项目；Jacket 会读取最近上级 `jacket.toml` 中的入口与模块目录。独立文件仍有语法高亮，需要语言服务时可手动 `M-x eglot`。

| 操作 | 命令 / 键 |
|---|---|
| 补全 / 定义 / 返回 / 引用 | `C-M-i` / `M-.` / `M-,` / `M-?` |
| 类型和签名说明 | Eldoc 自动显示；`M-x eldoc-doc-buffer` 查看完整说明 |
| 问题列表 / 下一问题 | `M-x flymake-show-buffer-diagnostics` / `M-x flymake-goto-next-error` |
| 重命名 / 代码操作 | `M-x eglot-rename` / `M-x eglot-code-actions` |
| 格式化 | `M-x kickstart-jai-format-buffer` |
| 重连 | `M-x eglot-reconnect` |

Jacket 0.30.4 的 LSP 不提供格式化，因此手动格式化调用同套工具的 `jaifmt --stdin`。它包含未保存的编辑，失败不改原文，成功后可按一次 `C-/` 撤销。保存时不会自动格式化。内联类型提示默认关闭，可在 `local.el` 设置 `(setq kickstart-jai-inlay-hints t)`。

Jacket 能力与限制见 [上游文档](https://github.com/matteopolak/jacket/blob/v0.30.4/docs/compiler/language-server.md)。

## Windows 默认切换与回退

先保存并退出所有 Emacs 窗口。在仓库根目录运行：

```powershell
.\scripts\use-repository.ps1 -WhatIf
.\scripts\use-repository.ps1
```

脚本把旧 `%APPDATA%\.emacs.d` 完整移动至同级带时间的备份包，在原位置创建指向仓库的 junction，并修改开始菜单 Emacs 快捷方式参数。备份包保存旧目录、原快捷方式和恢复记录；终端会输出实际备份路径。已有相同配置时可重复运行。脚本不改 HOME 或系统 PATH。

回退时先退出 Emacs，再把实际备份路径传入：

```powershell
.\scripts\use-repository.ps1 -RestoreBackup 'C:\Users\you\AppData\Roaming\.emacs.d.backup-实际时间与编号'
```

回退只移除指向本仓库的 junction 本身，再恢复旧目录与快捷方式。若目标或快捷方式后来被改动，脚本会停止，避免覆盖。不要对 junction 使用递归删除。

确认当前实际配置：`M-: user-init-file RET` 应指向本仓库；经默认 junction 启动时路径会显示 `%APPDATA%\.emacs.d`。Windows 的 `file-truename` 不展开 junction，可用 `M-: (file-equal-p user-init-file "F:/project/my-emacs/init.el") RET` 核对，结果应为 `t`。

## 排错与验证

- 启动报错：用 `emacs --init-directory /path/to/my-emacs --debug-init` 看具体位置。`emacs -Q` 可临时进入干净会话，它不会验证这份配置。
- 缺包：运行 `M-x kickstart-install-packages`；不需要删除整个 `elpa/`。
- 目录内容搜索需要 ripgrep (`rg`)；不在 PATH 时，通过 `kickstart-extra-paths` 添加其目录。当前文件搜索不需要外部工具。
- Jai 无语言服务：检查 `kickstart-jacket-directory`、项目根和 `M-x eglot-events-buffer`。工具缺失不会妨碍编辑或笔记。

Jai 的自动测试见 `tests/kickstart-jai-test.el`；正常启动检查见 `tests/check-startup.el`。正常启动检查不使用 `-Q`、`-q` 或 `--batch`，会核对实际的 `early-init.el`、`init.el` 和主题/模式，然后退出。

主题来源、版本与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。旧 Handmade 配置可从 Git 历史查看。
