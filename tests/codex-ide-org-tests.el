;;; codex-ide-org-tests.el --- Tests for codex-ide-org -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'org)
(require 'codex-ide-org)

(defmacro codex-ide-org-test-with-file (contents &rest body)
  "Create a temporary Org file containing CONTENTS and evaluate BODY."
  (declare (indent 1) (debug t))
  `(let* ((temporary-directory (make-temp-file "codex-ide-org-test-" t))
          (codex-ide-org-file (expand-file-name "tasks.org" temporary-directory)))
     (unwind-protect
         (progn
           (with-temp-file codex-ide-org-file
             (insert ,contents))
           (codex-ide-org-rebuild-index)
           ,@body)
       (when-let* ((buffer (get-file-buffer codex-ide-org-file)))
         (kill-buffer buffer))
       (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-default-file-uses-emacs-configuration-directory ()
  (let ((user-emacs-directory "/tmp/codex-emacs-config/"))
    (should (equal (locate-user-emacs-file "codex-ide/tasks.org")
                   "/tmp/codex-emacs-config/codex-ide/tasks.org"))))

(ert-deftest codex-ide-org-rebuild-index-finds-linked-heading ()
  (codex-ide-org-test-with-file
      "* WIP Implement index\n:PROPERTIES:\n:CODEX_THREAD_ID: thread-one\n:CODEX_CWD: /tmp/project\n:END:\n"
    (let* ((state (codex-ide-org-thread-state "thread-one"))
           (marker (plist-get state :marker)))
      (should (eq (plist-get state :status) 'linked))
      (should (markerp marker))
      (should (equal (codex-ide-org-marker-directory marker) "/tmp/project"))
      (should (equal (codex-ide-org-marker-workflow-state marker) "WIP")))))

(ert-deftest codex-ide-org-workflow-keywords-are-buffer-local ()
  (let ((org-default (default-value 'org-todo-keywords)))
    (codex-ide-org-test-with-file "* PLAN Planned task\n"
      (let ((buffer (get-file-buffer codex-ide-org-file)))
        (should (local-variable-p 'org-todo-keywords buffer))
        (with-current-buffer buffer
          (should (member "WIP(w)" (car codex-ide-org-todo-keywords)))
          (goto-char (point-min))
          (should (equal (org-get-todo-state) "PLAN"))))
      (should (equal (default-value 'org-todo-keywords) org-default)))))

(ert-deftest codex-ide-org-thread-state-reports-missing-link ()
  (codex-ide-org-test-with-file "* TODO Unlinked parent\n"
    (let ((state (codex-ide-org-thread-state "missing-thread")))
      (should (eq (plist-get state :status) 'missing))
      (should-not (plist-get state :markers)))
    (should-error (codex-ide-org-require-thread-marker "missing-thread")
                  :type 'codex-ide-org-missing-link)))

(ert-deftest codex-ide-org-thread-state-reports-duplicate-link ()
  (codex-ide-org-test-with-file
      "* TODO First\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate\n:CODEX_CWD: /tmp/one\n:END:\n* HOLD Second\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate\n:CODEX_CWD: /tmp/two\n:END:\n"
    (let ((state (codex-ide-org-thread-state "duplicate")))
      (should (eq (plist-get state :status) 'duplicate))
      (should (= (length (plist-get state :markers)) 2))
      (should (= (length (codex-ide-org-index-conflicts)) 1)))
    (should-error (codex-ide-org-require-thread-marker "duplicate")
                  :type 'codex-ide-org-duplicate-link)))

(ert-deftest codex-ide-org-cwd-does-not-participate-in-identity ()
  (codex-ide-org-test-with-file
      "* TODO First\n:PROPERTIES:\n:CODEX_THREAD_ID: same-thread\n:CODEX_CWD: /tmp/one\n:END:\n* TODO Second\n:PROPERTIES:\n:CODEX_THREAD_ID: same-thread\n:CODEX_CWD: /tmp/two\n:END:\n"
    (should (eq (plist-get (codex-ide-org-thread-state "same-thread") :status)
                'duplicate))))

(ert-deftest codex-ide-org-index-rebuilds-after-configured-file-save ()
  (codex-ide-org-test-with-file
      "* TODO Existing\n:PROPERTIES:\n:CODEX_THREAD_ID: existing\n:END:\n"
    (let ((generation codex-ide-org-index-generation)
          (buffer (find-file-noselect codex-ide-org-file)))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert "* REVIEW Added\n:PROPERTIES:\n:CODEX_THREAD_ID: added\n:END:\n")
        (save-buffer))
      (should (> codex-ide-org-index-generation generation))
      (should (eq (plist-get (codex-ide-org-thread-state "added") :status)
                  'linked)))))

(ert-deftest codex-ide-org-package-load-does-not-create-configured-file ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-missing-" t))
         (codex-ide-org-file (expand-file-name "missing/tasks.org"
                                               temporary-directory)))
    (unwind-protect
        (progn
          (codex-ide-org-rebuild-index)
          (should-not (file-exists-p codex-ide-org-file)))
      (delete-directory temporary-directory t))))

(provide 'codex-ide-org-tests)

;;; codex-ide-org-tests.el ends here
