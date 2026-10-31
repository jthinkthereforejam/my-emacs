;;; kickstart-jai-test.el --- Tests for the Jai integration -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'kickstart-jai)

(defmacro kickstart-jai-test--with-directory (binding &rest body)
  "Bind BINDING to a temporary directory, evaluate BODY, then remove it."
  (declare (indent 1))
  `(let ((,binding (make-temp-file "kickstart-jai test " t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(ert-deftest kickstart-jai-project-without-git ()
  (kickstart-jai-test--with-directory root
    (let ((source (expand-file-name "src/nested/" root)))
      (make-directory source t)
      (write-region "[project]\nentry = [\"main.jai\"]\n" nil
                    (expand-file-name "jacket.toml" root) nil 'silent)
      (let ((project (project-current nil source)))
        (should project)
        (should (file-equal-p (project-root project) root))))))

(ert-deftest kickstart-jai-contact-keeps-spaces-and-arguments-separate ()
  (kickstart-jai-test--with-directory directory
    (let* ((kickstart-jacket-directory directory)
           (server (expand-file-name
                    (if (eq system-type 'windows-nt) "jailsp.exe" "jailsp")
                    directory)))
      (write-region "" nil server nil 'silent)
      (set-file-modes server #o755)
      (should (equal (kickstart-jai--eglot-contact)
                     (list server "--stdio"))))))

(ert-deftest kickstart-jai-tools-stay-in-one-toolchain ()
  (kickstart-jai-test--with-directory directory
    (let* ((kickstart-jacket-directory nil)
           (server (expand-file-name "jailsp" directory)))
      (cl-letf (((symbol-function 'executable-find)
                 (lambda (name)
                   (if (equal name "jailsp") server "/other/jaifmt"))))
        ;; Do not silently pick a different version of the formatter on PATH.
        (should-not (kickstart-jai--tool "jaifmt"))))))

(ert-deftest kickstart-jai-missing-tools-and-standalone-files-stay-editable ()
  (with-temp-buffer
    (setq buffer-file-name (expand-file-name "standalone.jai" temporary-file-directory))
    (let ((started nil))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'eglot-ensure) (lambda () (setq started t))))
        (kickstart-jai--maybe-eglot)
        (should-not started))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) '(transient . "/")))
                ((symbol-function 'kickstart-jai--tool) (lambda (_) nil))
                ((symbol-function 'eglot-ensure) (lambda () (setq started t))))
        (kickstart-jai--maybe-eglot)
        (should-not started)
        (should-not (kickstart-jai--eglot-contact))))))

(ert-deftest kickstart-jai-local-project-starts-eglot-without-changing-environment ()
  (with-temp-buffer
    (setq buffer-file-name (expand-file-name "main.jai" temporary-file-directory))
    (let ((original-environment (copy-sequence process-environment))
          (started nil))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) '(transient . "/")))
                ((symbol-function 'kickstart-jai--tool) (lambda (_) "/tools/jailsp"))
                ((symbol-function 'eglot-ensure) (lambda () (setq started t))))
        (kickstart-jai--maybe-eglot)
        (should started)
        (should (equal process-environment original-environment))))))

(ert-deftest kickstart-jai-format-failure-preserves-buffer ()
  (with-temp-buffer
    (insert "main :: () { broken }")
    (buffer-enable-undo)
    (setq buffer-undo-list nil)
    (goto-char 6)
    (set-buffer-modified-p nil)
    (cl-letf (((symbol-function 'kickstart-jai--tool) (lambda (_) "/tools/jaifmt"))
              ((symbol-function 'call-process-region)
               (lambda (_start _end _program _delete destination _display &rest _args)
                 (with-current-buffer (car destination) (insert "partial output"))
                 (write-region "parse error" nil (cadr destination) nil 'silent)
                 2)))
      (should-error (kickstart-jai-format-buffer) :type 'user-error)
      (should (equal (buffer-string) "main :: () { broken }"))
      (should (= (point) 6))
      (should-not (buffer-modified-p))
      (should-not buffer-undo-list))))

(ert-deftest kickstart-jai-format-success-is-one-undo-step ()
  (with-temp-buffer
    (insert "main :: () {\nprint(1);\n}\n")
    (buffer-enable-undo)
    (setq buffer-undo-list nil)
    (goto-char 5)
    (cl-letf (((symbol-function 'kickstart-jai--tool) (lambda (_) "/tools with spaces/jaifmt"))
              ((symbol-function 'call-process-region)
               (lambda (start end program delete destination _display &rest args)
                 (should (equal program "/tools with spaces/jaifmt"))
                 (should-not delete)
                 (should (equal args '("--stdin")))
                 (should (equal (buffer-substring-no-properties start end)
                                "main :: () {\nprint(1);\n}\n"))
                 (with-current-buffer (car destination)
                   (insert "main :: () {\n    print(1);\n}\n"))
                 0)))
      (kickstart-jai-format-buffer)
      (should (= (point) 5))
      (should (equal (buffer-string) "main :: () {\n    print(1);\n}\n"))
      (undo-only 1)
      (should (equal (buffer-string) "main :: () {\nprint(1);\n}\n")))))

(ert-deftest kickstart-jai-format-real-tool-in-directory-with-spaces ()
  ;; This test runs when the actual toolchain is available; no user files are used.
  (let ((formatter (kickstart-jai--tool "jaifmt")))
    (skip-unless formatter)
    (kickstart-jai-test--with-directory directory
      (let* ((kickstart-jacket-directory directory)
             (default-directory (file-name-as-directory directory))
             (copy (expand-file-name (file-name-nondirectory formatter) directory)))
        (copy-file formatter copy)
        (set-file-modes copy #o755)
        (with-temp-buffer
          (insert "main :: () {\nprint(1);\n}\n")
          (kickstart-jai-format-buffer)
          (should (equal (buffer-string) "main :: () {\n    print(1);\n}\n")))))))

(provide 'kickstart-jai-test)
;;; kickstart-jai-test.el ends here
