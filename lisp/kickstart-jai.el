;;; kickstart-jai.el --- Jai with the Jacket toolchain -*- lexical-binding: t; -*-

;;; Commentary:
;; jai-mode 负责编辑；Emacs 内置的 Eglot 负责语言服务。
;; Jacket 与它的 stdlib 保持在同一个安装目录，无需改系统 PATH。
;; 主配置先加载 local.el，再加载这个文件。

;;; Code:

(require 'eglot)
(require 'project)
(require 'subr-x)

(defgroup kickstart-jai nil
  "Jai editing with Jacket."
  :group 'languages)

(defcustom kickstart-jacket-directory nil
  "Jacket toolchain directory, containing jailsp, jaifmt and stdlib.
When nil, find the tools on PATH.  Set this in local.el for this machine."
  :type '(choice (const :tag "Find on PATH" nil) directory)
  :group 'kickstart-jai)

(defcustom kickstart-jai-inlay-hints nil
  "Whether Eglot shows inline type and parameter hints in Jai buffers."
  :type 'boolean
  :group 'kickstart-jai)

(defun kickstart-jai--tool (name)
  "Find executable NAME in the selected Jacket toolchain.
When jailsp is on PATH, use its sibling tools so versions stay together."
  (let* ((directory
          (or kickstart-jacket-directory
              (when-let* ((server (executable-find "jailsp")))
                (file-name-directory server))))
         (filename (if (eq system-type 'windows-nt)
                       (concat name ".exe")
                     name)))
    (if directory
        (let ((program (expand-file-name filename directory)))
          (and (file-executable-p program) program))
      (executable-find name))))

(defun kickstart-jai--eglot-contact (&optional _interactive _project)
  "Return the Jacket language server command, if it is installed."
  (when-let* ((server (kickstart-jai--tool "jailsp")))
    ;; A list passes paths with spaces directly; no shell quoting is involved.
    ;; jailsp finds its matching stdlib beside its executable.
    (list server "--stdio")))

(defun kickstart-jai--maybe-eglot ()
  "Start language services for a local Jai project when Jacket is available."
  (setq-local js-indent-level 4)
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (project-current nil)
             (kickstart-jai--tool "jailsp"))
    (eglot-ensure)))

(defun kickstart-jai--configure-eglot ()
  "Apply Jai display preferences after Eglot connects."
  (when (and (derived-mode-p 'jai-mode) (eglot-managed-p))
    (eglot-inlay-hints-mode (if kickstart-jai-inlay-hints 1 -1))))

(defun kickstart-jai-format-buffer ()
  "Format the current buffer with Jacket's jaifmt, as one undo step.
Use this command explicitly: saving a file never invokes the formatter.
If formatting fails, leave the buffer unchanged and report its error."
  (interactive)
  (barf-if-buffer-read-only)
  (when (file-remote-p default-directory)
    (user-error "Jacket formatting is configured for local files"))
  (let ((formatter (or (kickstart-jai--tool "jaifmt")
                       (user-error "Cannot find jaifmt; set kickstart-jacket-directory in local.el")))
        (output (generate-new-buffer " *jaifmt output*"))
        (stderr (make-temp-file "jaifmt-error-"))
        (coding-system-for-read 'utf-8-unix)
        (coding-system-for-write 'utf-8-unix))
    (unwind-protect
        (save-restriction
          (widen)
          ;; --stdin reads this buffer, including unsaved edits.  jaifmt looks
          ;; for jacket.toml above default-directory for formatting options.
          (let ((status (call-process-region
                         (point-min) (point-max) formatter nil
                         (list output stderr) nil "--stdin")))
            (unless (eq status 0)
              (user-error "jaifmt failed: %s"
                          (or (with-temp-buffer
                                (insert-file-contents stderr)
                                (let ((details (string-trim (buffer-string))))
                                  (unless (string-empty-p details) details)))
                              (format "exit status %s" status))))
            ;; Replace by diff to retain cursor/marker positions.  Group all
            ;; edits so a single C-/ restores the text before formatting.
            (undo-boundary)
            (atomic-change-group
              (replace-region-contents (point-min) (point-max) output))
            (undo-boundary)))
      (kill-buffer output)
      (delete-file stderr))))

;; This also recognizes ordinary folders without Git as projects.
(add-to-list 'project-vc-extra-root-markers "jacket.toml")
(add-to-list 'eglot-server-programs '(jai-mode . kickstart-jai--eglot-contact))
(add-hook 'jai-mode-hook #'kickstart-jai--maybe-eglot)
(add-hook 'eglot-managed-mode-hook #'kickstart-jai--configure-eglot)

(provide 'kickstart-jai)
;;; kickstart-jai.el ends here
