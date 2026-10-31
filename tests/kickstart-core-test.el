;;; kickstart-core-test.el --- Package setup and native editing contracts -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(ert-deftest kickstart-installer-is-idempotent-and-offline-when-installed ()
  (cl-letf (((symbol-function 'package-installed-p) (lambda (&rest _) t))
            ((symbol-function 'package-refresh-contents)
             (lambda () (ert-fail "Installed packages must not refresh archives")))
            ((symbol-function 'package-install)
             (lambda (&rest _) (ert-fail "Must not reinstall packages"))))
    (kickstart-install-packages)))

(ert-deftest kickstart-installer-network-failure-stops-and-explains-retry ()
  (let ((noninteractive nil) warning)
    (cl-letf (((symbol-function 'package-installed-p) (lambda (&rest _) nil))
              ((symbol-function 'package-refresh-contents) (lambda () (error "offline")))
              ((symbol-function 'package-install)
               (lambda (&rest _) (ert-fail "Must stop after failed refresh")))
              ((symbol-function 'display-warning)
               (lambda (_type message &rest _) (setq warning message))))
      (kickstart-install-packages)
      (should (string-match-p "offline" warning))
      (should (string-match-p "kickstart-install-packages" warning)))))

(ert-deftest kickstart-standard-keys-and-recovery-stay-available ()
  (should (eq (key-binding (kbd "M-x")) #'execute-extended-command))
  (should (eq (key-binding (kbd "C-x C-f")) #'find-file))
  (should (eq (key-binding (kbd "C-x C-s")) #'save-buffer))
  (should (eq (key-binding (kbd "C-g")) #'keyboard-quit))
  (should make-backup-files)
  (should auto-save-default)
  (should (file-in-directory-p (cdar backup-directory-alist) kickstart-state-directory)))

(ert-deftest kickstart-alerts-only-highlight-comments ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; TODO: 中文注释\n(setq TODO \"ERROR\")\n;; ERROR: something\n")
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "TODO")
    (should (memq 'everforest-zed-comment-alert
                  (ensure-list (get-text-property (1- (point)) 'face))))
    (search-forward "TODO")
    (should-not (memq 'everforest-zed-comment-alert
                      (ensure-list (get-text-property (1- (point)) 'face))))
    (search-forward "ERROR")
    (should-not (memq 'everforest-zed-comment-alert
                      (ensure-list (get-text-property (1- (point)) 'face))))
    (search-forward "ERROR")
    (should (memq 'everforest-zed-comment-alert
                  (ensure-list (get-text-property (1- (point)) 'face))))))

;;; kickstart-core-test.el ends here
