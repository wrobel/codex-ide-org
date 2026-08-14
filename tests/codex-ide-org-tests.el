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

(ert-deftest codex-ide-org-link-heading-persists-explicit-properties ()
  (codex-ide-org-test-with-file "* TODO Link me\n"
    (let ((buffer (get-file-buffer codex-ide-org-file)))
      (with-current-buffer buffer
        (goto-char (point-min))
        (cl-letf (((symbol-function
                    'codex-ide-status-notify-annotations-changed)
                   #'ignore))
          (codex-ide-org-link-heading "thread-link" "/tmp/link"))
        (should (equal (org-entry-get nil "CODEX_THREAD_ID") "thread-link"))
        (should (equal (org-entry-get nil "CODEX_CWD") "/tmp/link"))
        (should-not (buffer-modified-p)))
      (should (eq (plist-get (codex-ide-org-thread-state "thread-link") :status)
                  'linked)))))

(ert-deftest codex-ide-org-link-heading-refuses-existing-other-task ()
  (codex-ide-org-test-with-file
      "* TODO Existing\n:PROPERTIES:\n:CODEX_THREAD_ID: taken\n:END:\n* TODO Target\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (outline-next-heading)
      (should-error (codex-ide-org-link-heading "taken") :type 'user-error)
      (should-not (org-entry-get nil "CODEX_THREAD_ID")))))

(ert-deftest codex-ide-org-link-heading-can-leave-change-unsaved ()
  (codex-ide-org-test-with-file "* TODO Keep buffer change\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let ((codex-ide-org-save-after-change nil))
        (cl-letf (((symbol-function 'codex-ide-status-notify-annotations-changed)
                   #'ignore))
          (codex-ide-org-link-heading "unsaved")))
      (should (buffer-modified-p))
      (should (eq (plist-get (codex-ide-org-thread-state "unsaved") :status)
                  'linked)))))

(ert-deftest codex-ide-org-link-heading-requires-explicit-replacement ()
  (codex-ide-org-test-with-file
      "* TODO Existing\n:PROPERTIES:\n:CODEX_THREAD_ID: old\n:END:\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (should-error (codex-ide-org-link-heading "new") :type 'user-error)
      (cl-letf (((symbol-function 'codex-ide-status-notify-annotations-changed)
                 #'ignore))
        (codex-ide-org-link-heading "new" "/tmp/new" t))
      (should (equal (org-entry-get nil "CODEX_THREAD_ID") "new")))))

(ert-deftest codex-ide-org-unlink-current-heading-confirms-and-persists ()
  (codex-ide-org-test-with-file
      "* WIP Linked\n:PROPERTIES:\n:CODEX_THREAD_ID: unlink-me\n:CODEX_CWD: /tmp/old\n:END:\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'codex-ide-status-notify-annotations-changed)
                 #'ignore))
        (codex-ide-org-unlink-current-heading))
      (should-not (org-entry-get nil "CODEX_THREAD_ID"))
      (should-not (org-entry-get nil "CODEX_CWD"))
      (should-not (buffer-modified-p)))
    (should (eq (plist-get (codex-ide-org-thread-state "unlink-me") :status)
                'missing))))

(ert-deftest codex-ide-org-open-thread-at-point-uses-canonical-id ()
  (codex-ide-org-test-with-file
      "* TODO Open\n:PROPERTIES:\n:CODEX_THREAD_ID: open-me\n:CODEX_CWD: /stale/snapshot\n:END:\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let (opened)
        (cl-letf (((symbol-function 'codex-ide-open-thread)
                   (lambda (&rest args) (setq opened args))))
          (codex-ide-org-open-thread-at-point))
        (should (equal opened '("open-me")))))))

(ert-deftest codex-ide-org-resolve-thread-marker-asks-on-duplicate ()
  (codex-ide-org-test-with-file
      "* TODO First\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-choice\n:END:\n* HOLD Second\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-choice\n:END:\n"
    (let* ((markers (plist-get (codex-ide-org-thread-state "duplicate-choice")
                               :markers))
           (second-marker (cadr markers)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices &rest _)
                   (car (rassoc second-marker choices)))))
        (should (eq (codex-ide-org-resolve-thread-marker "duplicate-choice")
                    second-marker))))))

(ert-deftest codex-ide-org-resolve-thread-marker-explains-missing-link ()
  (codex-ide-org-test-with-file "* TODO Unlinked\n"
    (should-error (codex-ide-org-resolve-thread-marker "not-linked")
                  :type 'user-error)))

(ert-deftest codex-ide-org-create-task-is-the-explicit-file-creation-path ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-create-" t))
         (codex-ide-org-file (expand-file-name "nested/tasks.org"
                                               temporary-directory))
         (row '(:thread-id "created-thread"
                :title "Original title"
                :directory "/tmp/created")))
    (unwind-protect
        (progn
          (should-not (file-exists-p codex-ide-org-file))
          (let ((marker (codex-ide-org-create-task-for-row
                         row "Created\nOrg task")))
            (should (file-exists-p codex-ide-org-file))
            (org-with-point-at marker
              (should (equal (org-get-heading t t t t) "Created Org task"))
              (should (equal (org-entry-get nil "CODEX_THREAD_ID")
                             "created-thread"))
              (should (equal (org-entry-get nil "CODEX_CWD") "/tmp/created"))))
          (should (eq (plist-get
                       (codex-ide-org-thread-state "created-thread") :status)
                      'linked)))
      (when-let* ((buffer (get-file-buffer codex-ide-org-file)))
        (kill-buffer buffer))
      (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-create-task-refuses-an-existing-link ()
  (codex-ide-org-test-with-file
      "* TODO Existing\n:PROPERTIES:\n:CODEX_THREAD_ID: existing-task\n:END:\n"
    (should-error
     (codex-ide-org-create-task-for-row
      '(:thread-id "existing-task" :title "Duplicate") "Duplicate")
     :type 'user-error)))

(ert-deftest codex-ide-org-link-command-chooses-from-global-inventory ()
  (codex-ide-org-test-with-file "* TODO Choose thread\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let ((row '(:thread-id "global-choice"
                   :title "Global choice"
                   :directory "/tmp/global")))
        (cl-letf (((symbol-function 'codex-ide-list-thread-rows)
                   (lambda (&rest args)
                     (should (equal args '(:global t)))
                     (list row)))
                  ((symbol-function 'completing-read)
                   (lambda (_prompt choices &rest _)
                     (caar choices)))
                  ((symbol-function
                    'codex-ide-status-notify-annotations-changed)
                   #'ignore))
          (codex-ide-org-link-current-heading)))
      (should (equal (org-entry-get nil "CODEX_THREAD_ID") "global-choice"))
      (should (equal (org-entry-get nil "CODEX_CWD") "/tmp/global")))))

(provide 'codex-ide-org-tests)

;;; codex-ide-org-tests.el ends here
