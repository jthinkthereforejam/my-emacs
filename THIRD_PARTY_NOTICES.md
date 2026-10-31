# 第三方来源

## Everforest for Zed

本仓库的独立 Emacs 主题移植了 [albertsko/zed-everforest](https://github.com/albertsko/zed-everforest) 中 **Everforest Dark Soft (material)** 的语义配色；参考本机安装扩展 **0.2.0** 的 `themes/everforest-material.json`。TODO/error 注释强调 `#ff5555` 对应本机 Zed 的个人设置。

Copyright (c) 2025 Albert Skonieczny。上游采用 MIT 许可，完整文本保存在 [themes/LICENSE.everforest-zed](themes/LICENSE.everforest-zed)。

Everforest 原始配色设计来自 [sainnhe/everforest](https://github.com/sainnhe/everforest)。

## 安装的扩展

Vertico、Orderless、Marginalia、Consult、Corfu 由 GNU/NonGNU ELPA 安装；Jai 主模式由内置 `package-vc` 从 [valignatev/jai-mode](https://github.com/valignatev/jai-mode) 安装。它们的源码和许可随包保存在本地 `elpa/`，不随本仓库提交或重新分发。

Jacket 是单独安装的 [matteopolak/jacket](https://github.com/matteopolak/jacket) 工具链；本配置仅启动已有的语言服务器和格式化程序，不打包其二进制或标准库。

配置的教学与组织方式参考 [Emacs Bedrock](https://github.com/ashton314/emacs-bedrock) 和 [kickstart.emacs](https://github.com/MiniApollo/kickstart.emacs)，未复制它们的整套配置。
