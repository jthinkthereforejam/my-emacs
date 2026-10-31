;;; kickstart-jai-integration.el --- Real Jacket/Eglot checks -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from the repository after installing packages and configuring local.el:
;; emacs -Q --batch -l init.el -l tests/kickstart-jai-integration.el
;;       -f ert-run-tests-batch-and-exit
;; The test uses only temporary Jai files and the selected local toolchain.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'xref)
(require 'flymake)
(require 'kickstart-jai)

(defun kickstart-jai-integration--wait (predicate &optional seconds)
  "Wait at most SECONDS (default 20) for PREDICATE to return non-nil."
  (let ((deadline (+ (float-time) (or seconds 20))) result)
    (while (and (not (setq result (funcall predicate)))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    result))

(defun kickstart-jai-integration--symbol (name)
  "Move point to the first occurrence of NAME in the current buffer."
  (goto-char (point-min))
  (search-forward name)
  (backward-char (length name)))

(ert-deftest kickstart-jai-real-eglot-workflow ()
  "Exercise real Eglot commands against an installed Jacket toolchain."
  (skip-unless (and (locate-library "jai-mode")
                    (kickstart-jai--tool "jailsp")
                    (kickstart-jai--tool "jaifmt")))
  (let* ((root (file-name-as-directory
                (make-temp-file "kickstart Jai integration " t)))
         (main (expand-file-name "main.jai" root))
         (library (expand-file-name "lib.jai" root))
         (default-directory root)
         (eglot-sync-connect t)
         (eglot-connect-timeout 20)
         (eglot-confirm-server-initiated-edits nil)
         (eglot-autoshutdown t)
         main-buffer server)
    (unwind-protect
        (progn
          (write-region "[project]\nentry = [\"main.jai\"]\n" nil
                        (expand-file-name "jacket.toml" root) nil 'silent)
          (write-region
           "Counter :: struct { value: s32; }\nhelper :: (value: s32) -> s32 { return value + 1; }\n"
           nil library nil 'silent)
          (write-region
           "#load \"lib.jai\";\nmain :: () {\n    counter: Counter;\n    counter.value = helper(1);\n}\n"
           nil main nil 'silent)
          (setq main-buffer (find-file-noselect main))
          (with-current-buffer main-buffer
            (should (derived-mode-p 'jai-mode))
            (should (file-equal-p (project-root (project-current)) root))
            ;; The mode hook queues eglot-ensure for the next user command.
            (run-hooks 'post-command-hook)
            (should (kickstart-jai-integration--wait #'eglot-managed-p))
            (setq server (eglot-current-server))
            (should server)
            (should-not eglot-inlay-hints-mode)
            ;; The interactive M-x eglot route must select the same command.
            (eglot-shutdown server nil 20)
            (setq server nil)
            (call-interactively #'eglot)
            (should (kickstart-jai-integration--wait #'eglot-managed-p))
            (setq server (eglot-current-server))
            (should server)

            ;; Completion uses Emacs's actual CAPF table, as Corfu does.
            (kickstart-jai-integration--symbol "counter.value")
            (search-forward "val")
            (let* ((capf (eglot-completion-at-point))
                   (candidates (all-completions "val" (nth 2 capf))))
              (should (seq-some (lambda (item) (string-prefix-p "value" item))
                                candidates)))

            ;; Eldoc uses this same Eglot hover request; request synchronously
            ;; here because a batch buffer has no visible echo area/window.
            (kickstart-jai-integration--symbol "helper")
            (let ((hover (eglot--request
                          server :textDocument/hover
                          (eglot--TextDocumentPositionParams) :timeout 20)))
              (should (string-match-p "s32" (prin1-to-string hover))))

            (let ((definitions (xref-backend-definitions 'eglot "helper"))
                  (references (xref-backend-references 'eglot "helper")))
              (should (= (length definitions) 1))
              (should (file-equal-p
                       (xref-file-location-file
                        (xref-item-location (car definitions))) library))
              (should (>= (length references) 2)))

            ;; Apply a real workspace edit across both temporary files.
            (eglot-rename "increment")
            (should (string-match-p "increment(1)" (buffer-string)))
            (with-current-buffer (find-buffer-visiting library)
              (should (string-match-p "increment ::" (buffer-string))))

            ;; A real type error must reach the built-in Flymake UI backend.
            (goto-char (point-max))
            (forward-line -1)
            (insert "    broken: s32 = \"wrong\";\n")
            (eglot--signal-textDocument/didChange)
            (flymake-start nil t)
            (should
             (kickstart-jai-integration--wait
              (lambda ()
                (seq-some (lambda (diagnostic)
                            (eq (get (flymake-diagnostic-type diagnostic)
                                     'flymake-category)
                                'flymake-error))
                          (flymake-diagnostics))) 20))

            ;; Formatting is external to LSP and must be an explicit action.
            (goto-char (point-min))
            (search-forward "    counter.value")
            (beginning-of-line)
            (delete-horizontal-space)
            (let ((before (buffer-string)))
              (buffer-enable-undo)
              (setq buffer-undo-list nil)
              (kickstart-jai-format-buffer)
              (should-not (equal before (buffer-string)))
              (undo-only 1)
              (should (equal before (buffer-string))))
            (message "Jai integration: automatic/manual Eglot, completion, hover, definitions, references, rename, Flymake diagnostics and manual format/undo passed")))
      (when (and server (jsonrpc-running-p server))
        (ignore-errors (eglot-shutdown server nil 20)))
      ;; Rename can open additional file buffers.  Discard fixture changes.
      (dolist (buffer (buffer-list))
        (when-let* ((filename (buffer-file-name buffer)))
          (when (file-in-directory-p filename root)
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (delete-directory root t))))

(provide 'kickstart-jai-integration)
;;; kickstart-jai-integration.el ends here
