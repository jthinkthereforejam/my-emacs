;;; init.el --- 从这里开始读懂自己的 Emacs -*- lexical-binding: t; -*-

;; 阅读顺序：目录与本机设置 → 包 → 编辑 → 搜索补全 → Org → Jai。
;; C-h t 打开教程，C-h k 解释按键，C-h v 解释变量，C-h f 解释函数。
;; 修改后先重启 Emacs；逐段用 C-x C-e 执行表达式留到熟悉 Lisp 之后。
(when (version< emacs-version "31.1")
  (error "这份配置需要 Emacs 31.1 或更新版本"))

;;; 1. 配置、个人设置与运行数据

(defconst kickstart-directory
  (file-name-as-directory
   (file-truename (file-name-directory (or load-file-name buffer-file-name))))
  "当前加载的配置目录；Windows junction 与仓库访问的是同一套文件。")
(defconst kickstart-state-directory (expand-file-name "var/" kickstart-directory))
(add-to-list 'load-path (expand-file-name "lisp/" kickstart-directory))
(make-directory kickstart-state-directory t)

;; Customize 是 Emacs 的图形设置界面。将它生成的 Lisp 与手写配置分开。
(setq custom-file (expand-file-name "custom.el" kickstart-state-directory))
(defvar kickstart-jacket-directory nil "Jacket 工具链目录；nil 表示从 PATH 查找。")
(defvar kickstart-extra-paths nil "仅供 Emacs 使用的额外可执行文件目录。")
(defvar kickstart-font-height 140 "默认字体大小，单位为十分之一磅。")

;; org-directory 是笔记的默认入口，个人笔记不保存在配置仓库。
(setq org-directory (expand-file-name "~/org"))
;; 本机路径和私人选择写到 local.el，它不进入 Git。先读设置，再启用功能。
(load (expand-file-name "local.el" kickstart-directory) t t)
(dolist (directory kickstart-extra-paths)
  (when (file-directory-p directory)
    (add-to-list 'exec-path (directory-file-name directory))
    (setenv "PATH" (concat (directory-file-name directory) path-separator
                          (or (getenv "PATH") "")))))

;;; 2. 包：安装与启动分开，平时启动不需要联网

(require 'package)
(setq package-user-dir (expand-file-name "elpa/" kickstart-directory)
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")))
(package-initialize)
(require 'use-package)
(setq use-package-always-ensure nil)

(defconst kickstart-packages '(vertico orderless marginalia consult corfu)
  "五个各司其职的交互扩展；依赖由 package.el 安装。")
;; 让 package-autoremove 知道这些是主动选择的包，而不是可清理的孤立依赖。
(setq package-selected-packages (append kickstart-packages '(jai-mode)))

(defun kickstart-install-packages ()
  "安装缺失的扩展与 Jai 主模式。已安装的包不会重复安装或自动更新。"
  (interactive)
  (condition-case err
      (progn
        (when (seq-some (lambda (pkg) (not (package-installed-p pkg)))
                        kickstart-packages)
          (package-refresh-contents)
          (dolist (pkg kickstart-packages)
            (unless (package-installed-p pkg) (package-install pkg))))
        ;; Jai 主模式不在上述包源中，使用内置 package-vc 从上游安装。
        (unless (package-installed-p 'jai-mode)
          (require 'package-vc)
          (package-vc-install
           '(jai-mode :url "https://github.com/valignatev/jai-mode")))
        (message "扩展已安装。请重启 Emacs 加载完整配置。"))
    (error
     (display-warning
      'kickstart
      (format "安装未完成：%s。基础编辑仍可用；联网后运行 M-x kickstart-install-packages 重试。"
              (error-message-string err))
      :warning)
     (when noninteractive (signal (car err) (cdr err))))))

(let ((missing (seq-filter (lambda (pkg) (not (package-installed-p pkg)))
                           (append kickstart-packages '(jai-mode)))))
  (when missing
    (message "尚未安装 %s；运行 M-x kickstart-install-packages，基础编辑现在即可使用。"
             (mapconcat #'symbol-name missing ", "))))

;;; 3. 外观与基础编辑

(add-to-list 'custom-theme-load-path (expand-file-name "themes/" kickstart-directory))
(load-theme 'everforest-zed t)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
;; 菜单保留：忘记键位时可以先用鼠标寻找命令。
(menu-bar-mode 1)
(defun kickstart-setup-font (&optional frame)
  "为图形 FRAME 选择系统已有字体，不要求另外安装字体。"
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (let ((family (seq-find
                     (lambda (name) (find-font (font-spec :family name)))
                     '("Cascadia Mono" "Consolas" "Menlo" "DejaVu Sans Mono"))))
        (when family (set-face-attribute 'default nil :family family)))
      (set-face-attribute 'default nil :height kickstart-font-height)
      (when (find-font (font-spec :family "Microsoft YaHei"))
        (set-fontset-font t 'han (font-spec :family "Microsoft YaHei") nil 'prepend)))))
(kickstart-setup-font)
(add-hook 'after-make-frame-functions #'kickstart-setup-font)

;; 新文件偏好 UTF-8；读取已有文件仍尊重检测到的编码与换行。
(prefer-coding-system 'utf-8-unix)
(setq-default indent-tabs-mode nil tab-width 4 fill-column 100)
(setq use-short-answers t
      sentence-end-double-space nil
      ring-bell-function #'ignore
      scroll-margin 3
      scroll-conservatively 101
      tab-always-indent 'complete
      save-interprogram-paste-before-kill t
      require-final-newline t
      initial-scratch-message
      ";; 欢迎！C-h t 学习 Emacs，C-g 取消，M-x 执行命令。\n;; C-c h 打开入门指南，C-c e 阅读配置，C-c n 打开个人笔记目录。\n\n")
(delete-selection-mode 1)
(column-number-mode 1)
(show-paren-mode 1)
(global-hl-line-mode 1)
(global-auto-revert-mode 1)
(setq auto-revert-verbose nil)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;; Zed 的 TODO/error 注释强调：只匹配注释，字符串和普通标识符不变色。
(defun kickstart-match-comment-alert (limit)
  "在 LIMIT 前寻找注释中的 TODO、FIXME 或 ERROR。"
  (let ((case-fold-search nil) found)
    (while (and (not found)
                (re-search-forward "\\<\\(TODO\\|FIXME\\|ERROR\\)\\>" limit t))
      (when (save-excursion (nth 4 (syntax-ppss (match-beginning 0))))
        (setq found t)))
    found))
(defun kickstart-highlight-comment-alerts ()
  "在当前编程缓冲区突出重要注释。"
  (font-lock-add-keywords
   nil '((kickstart-match-comment-alert (0 'everforest-zed-comment-alert prepend))) t))
(add-hook 'prog-mode-hook #'kickstart-highlight-comment-alerts)

;; 备份与自动保存是不同的保护：两者都保留，统一放到 var/。
(dolist (name '("backups/" "auto-save/"))
  (make-directory (expand-file-name name kickstart-state-directory) t))
(setq backup-directory-alist
      `(("." . ,(expand-file-name "backups/" kickstart-state-directory)))
      auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" kickstart-state-directory) t))
      auto-save-list-file-prefix
      (expand-file-name "auto-save/.saves-" kickstart-state-directory)
      backup-by-copying t version-control t
      kept-new-versions 6 kept-old-versions 2 delete-old-versions t
      savehist-file (expand-file-name "history" kickstart-state-directory)
      save-place-file (expand-file-name "places" kickstart-state-directory)
      recentf-save-file (expand-file-name "recentf" kickstart-state-directory)
      bookmark-default-file (expand-file-name "bookmarks" kickstart-state-directory)
      project-list-file (expand-file-name "projects" kickstart-state-directory)
      tramp-persistency-file-name (expand-file-name "tramp" kickstart-state-directory)
      url-configuration-directory (expand-file-name "url/" kickstart-state-directory)
      org-persist-directory (expand-file-name "org-persist/" kickstart-state-directory)
      url-history-file (expand-file-name "url-history" kickstart-state-directory)
      savehist-additional-variables '(search-ring regexp-search-ring))
(savehist-mode 1)
(save-place-mode 1)
(recentf-mode 1)

(use-package which-key
  :ensure nil
  :custom (which-key-idle-delay 0.7)
  :config (which-key-mode 1))

;;; 4. 搜索与补全：保持 Emacs 原有命令，只改善交互

(setq completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-buffer-completion-ignore-case t)
(use-package vertico
  :if (package-installed-p 'vertico)
  :config (vertico-mode 1))
(use-package orderless
  :if (package-installed-p 'orderless)
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion))))
  (completion-pcm-leading-wildcard t))
(use-package marginalia
  :if (package-installed-p 'marginalia)
  :config (marginalia-mode 1))
(use-package consult
  :if (package-installed-p 'consult)
  :bind (([remap switch-to-buffer] . consult-buffer)
         ("M-s l" . consult-line)
         ("M-s r" . consult-ripgrep)
         ("M-g i" . consult-imenu)
         ("M-g g" . consult-goto-line))
  :custom (consult-preview-key "M-."))
(use-package corfu
  :if (package-installed-p 'corfu)
  ;; C-M-i 调用 Emacs 的 completion-at-point；Corfu 只负责显示候选。
  :custom (corfu-auto nil)
  :config (global-corfu-mode 1))

;; Dired 是内置文件管理器；project.el 提供 C-x p 前缀下的项目操作。
(use-package dired
  :ensure nil
  :custom (dired-dwim-target t)
  :config
  (when (eq system-type 'windows-nt)
    (require 'ls-lisp)
    (setq ls-lisp-use-insert-directory-program nil)))
(use-package project :ensure nil :defer t)

;;; 5. Org：先把笔记当作普通文件

(use-package org
  :ensure nil
  :defer t
  :custom
  (org-startup-indented t)
  (org-hide-emphasis-markers nil)
  (org-src-fontify-natively t)
  :hook (org-mode . visual-line-mode))

(defun kickstart-open-notes ()
  "打开 org-directory。首次使用时创建目录，笔记不会写进配置仓库。"
  (interactive)
  (make-directory org-directory t)
  (dired org-directory))
(defun kickstart-open-guide ()
  "打开可在 Emacs 中直接阅读和练习的中文入门指南。"
  (interactive)
  (find-file (expand-file-name "guide.org" kickstart-directory)))
(defun kickstart-open-config ()
  "打开主配置。"
  (interactive)
  (find-file (expand-file-name "init.el" kickstart-directory)))
(global-set-key (kbd "C-c h") #'kickstart-open-guide)
(global-set-key (kbd "C-c e") #'kickstart-open-config)
(global-set-key (kbd "C-c n") #'kickstart-open-notes)

;;; 6. Jai：语言专用的小模块，Emacs 标准编辑方式保持不变

(require 'kickstart-jai)
(use-package jai-mode
  :if (package-installed-p 'jai-mode)
  :mode "\\.jai\\'")

;; Customize 的交互设置最后加载。local.el 适合路径；常用设置建议直接读改本文。
(load custom-file t t)

;;; init.el ends here
