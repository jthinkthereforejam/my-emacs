;;; check-startup.el --- Verify a real GUI startup and exit -*- lexical-binding: t; -*-

;; Load this after normal startup with --eval, never with -Q or --batch.
;; KICKSTART_CHECK_OUTPUT may select a separate JSON result for another run.

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defconst kickstart-check--root
  (file-name-as-directory
   (file-truename
    (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))
  "Repository derived from this test file, independently of init.el.")
(defvar kickstart-check--results nil)
(defvar kickstart-check--exit-code 0)

(defun kickstart-check--assert (condition description)
  "Signal an error with DESCRIPTION unless CONDITION is non-nil."
  (unless condition (error "%s" description)))

(defun kickstart-check--run (name function)
  "Record whether FUNCTION completes the check named NAME."
  (condition-case err
      (let ((details (funcall function)))
        (push `((name . ,name) (ok . t) (details . ,(format "%s" (or details "passed"))))
              kickstart-check--results))
    (error
     (setq kickstart-check--exit-code 1)
     (push `((name . ,name) (ok . :json-false)
             (details . ,(error-message-string err)))
           kickstart-check--results))))

(defun kickstart-check--true-path (path)
  "Return the true PATH, or nil if it cannot be resolved."
  (when (and (stringp path) (not (string-empty-p path)))
    (condition-case nil (file-truename path) (error nil))))

(defun kickstart-check--same-path (left right)
  "Compare true LEFT and RIGHT paths, ignoring Windows path case."
  (let ((left (kickstart-check--true-path left))
        (right (kickstart-check--true-path right)))
    (and left right
         ;; Windows Emacs does not resolve NTFS junctions in file-truename.
         ;; Compare filesystem identity before comparing path spellings.
         (or (file-equal-p left right)
             (if (eq system-type 'windows-nt)
             (string-equal (downcase (directory-file-name left))
                           (downcase (directory-file-name right)))
               (string-equal (directory-file-name left) (directory-file-name right)))))))

(defun kickstart-check--org-file (path)
  "Verify PATH opens in Org mode with UTF-8 Chinese content."
  (kickstart-check--assert (file-exists-p path) (format "Missing Org file: %s" path))
  (let ((buffer (find-file-noselect path)))
    (unwind-protect
        (with-current-buffer buffer
          (kickstart-check--assert (derived-mode-p 'org-mode) "Org mode did not activate")
          (kickstart-check--assert (eq (coding-system-base buffer-file-coding-system) 'utf-8)
                                  (format "Unexpected file encoding: %s" buffer-file-coding-system))
          (goto-char (point-min))
          (kickstart-check--assert (re-search-forward "[一-鿿]" nil t)
                                  "Chinese text was not decoded correctly")
          (format "%s (%s)" (file-truename path) buffer-file-coding-system))
      (kill-buffer buffer))))

(let* ((result-path (or (getenv "KICKSTART_CHECK_OUTPUT")
                        (expand-file-name "var/test-results/startup.json" kickstart-check--root)))
       (sample-path (expand-file-name "var/test-results/中文启动检查.org" kickstart-check--root)))
  (kickstart-check--run
   "normal-gui-startup"
   (lambda ()
     (kickstart-check--assert (not noninteractive) "The check requires a normal interactive process")
     (kickstart-check--assert (display-graphic-p) "The check requires an actual GUI frame")
     (kickstart-check--assert after-init-time "Initialization has not finished")
     (kickstart-check--assert (not init-file-had-error) "init.el signaled a startup error")
     (format "Emacs %s, %s" emacs-version window-system)))
  (kickstart-check--run
   "repository-paths"
   (lambda ()
     (dolist (pair `((,user-init-file . ,(expand-file-name "init.el" kickstart-check--root))
                     (,early-init-file . ,(expand-file-name "early-init.el" kickstart-check--root))
                     (,user-emacs-directory . ,kickstart-check--root)))
       (kickstart-check--assert (kickstart-check--same-path (car pair) (cdr pair))
                               (format "Wrong startup path: %S; expected %s" (car pair) (cdr pair))))
     kickstart-check--root))
  (kickstart-check--run
   "theme"
   (lambda ()
     (kickstart-check--assert (memq 'everforest-zed custom-enabled-themes) "The expected theme is disabled")
     (format "%S" custom-enabled-themes)))
  (kickstart-check--run
   "completion-packages"
   (lambda ()
     (dolist (package '(vertico orderless marginalia consult corfu))
       (kickstart-check--assert (package-installed-p package) (format "Package is missing: %s" package))
       (require package))
     (dolist (mode '(vertico-mode marginalia-mode global-corfu-mode which-key-mode))
       (kickstart-check--assert (and (boundp mode) (symbol-value mode))
                               (format "Mode is disabled: %s" mode)))
     (kickstart-check--assert (memq 'orderless completion-styles) "Orderless completion is disabled")
     (kickstart-check--assert (eq (command-remapping 'switch-to-buffer) 'consult-buffer)
                             "Consult buffer switching is not configured")
     "Five packages load; Vertico, Marginalia, Corfu, Orderless, Consult and Which-key are enabled"))
  (kickstart-check--run
   "native-keys-and-commands"
   (lambda ()
     (dolist (binding '(("C-x C-f" . find-file) ("C-x C-s" . save-buffer)
                        ("C-g" . keyboard-quit) ("M-x" . execute-extended-command)
                        ("C-h k" . describe-key) ("C-h t" . help-with-tutorial)
                        ("C-c h" . kickstart-open-guide) ("C-c e" . kickstart-open-config)
                        ("C-c n" . kickstart-open-notes)))
       (kickstart-check--assert (eq (key-binding (kbd (car binding))) (cdr binding))
                               (format "Unexpected command for %s" (car binding))))
     (dolist (command '(consult-line consult-ripgrep project-find-file org-mode
                        kickstart-install-packages kickstart-jai-format-buffer))
       (kickstart-check--assert (commandp command) (format "Command is unavailable: %s" command)))
     "Native navigation, editing, help and local entry commands are available"))
  (kickstart-check--run
   "guide-utf8-org"
   (lambda () (kickstart-check--org-file (expand-file-name "guide.org" kickstart-check--root))))
  (kickstart-check--run
   "sample-utf8-org"
   (lambda ()
     (make-directory (file-name-directory sample-path) t)
     (let ((coding-system-for-write 'utf-8-unix))
       (with-temp-file sample-path
         (insert "#+title: 中文启动检查\n\n* TODO 试着使用 Org\n正常读取中文，原生编辑按键保持可用。\n")))
     (kickstart-check--org-file sample-path)))
  (kickstart-check--run
   "runtime-state"
   (lambda ()
     (kickstart-check--assert
      (kickstart-check--same-path kickstart-state-directory
                                  (expand-file-name "var/" kickstart-check--root))
      "The active state directory must be the repository var/ directory")
     (dolist (variable '(custom-file savehist-file save-place-file recentf-save-file
                        bookmark-default-file project-list-file org-persist-directory))
       (kickstart-check--assert
        (file-in-directory-p (symbol-value variable) kickstart-state-directory)
        (format "%s must stay inside var/: %s" variable (symbol-value variable))))
     (kickstart-check--assert
      (seq-every-p (lambda (package) (memq package package-selected-packages))
                   '(vertico orderless marginalia consult corfu jai-mode))
      "Starter packages must be protected from package-autoremove")
     "History, recovery and Org caches stay under var/; starter packages are selected"))
  (condition-case err
      (progn
        (make-directory (file-name-directory (expand-file-name result-path)) t)
        (let ((coding-system-for-write 'utf-8-unix)
              (report
               `((success . ,(if (zerop kickstart-check--exit-code) t :json-false))
                 (emacsVersion . ,emacs-version)
                 (interactive . ,(if noninteractive :json-false t))
                 (graphical . ,(if (display-graphic-p) t :json-false))
                 (repository . ,kickstart-check--root)
                 (userInitFile . ,user-init-file)
                 (userInitFileTrue . ,(kickstart-check--true-path user-init-file))
                 (earlyInitFile . ,early-init-file)
                 (earlyInitFileTrue . ,(kickstart-check--true-path early-init-file))
                 (userEmacsDirectory . ,user-emacs-directory)
                 (userEmacsDirectoryTrue . ,(kickstart-check--true-path user-emacs-directory))
                 (initFileHadError . ,(if init-file-had-error t :json-false))
                 (resultPath . ,(expand-file-name result-path))
                 (checks . ,(vconcat (nreverse kickstart-check--results))))))
          (with-temp-file result-path
            (insert (json-serialize report :false-object :json-false :null-object nil) "\n"))))
    (error
     (setq kickstart-check--exit-code 1)
     (message "Cannot write startup check result: %s" (error-message-string err))))
  (let ((confirm-kill-processes nil))
    (kill-emacs kickstart-check--exit-code)))

;;; check-startup.el ends here
