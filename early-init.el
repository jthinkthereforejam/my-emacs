;;; early-init.el --- 窗口出现前的少量设置 -*- lexical-binding: t; -*-

;; early-init 比包和 init.el 更早加载。这里只设置初始窗口，避免启动闪白；
;; 其余外观和功能都在 init.el 中，不做复杂的启动优化。
(setq frame-inhibit-implied-resize t)
(add-to-list 'default-frame-alist '(background-color . "#333c43"))
(add-to-list 'default-frame-alist '(foreground-color . "#d3c6aa"))
(add-to-list 'default-frame-alist '(width . 110))
(add-to-list 'default-frame-alist '(height . 38))

;;; early-init.el ends here
