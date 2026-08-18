;;; codex-ide-org-tests.el --- Tests for codex-ide-org -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'org)
(require 'codex-ide-org)

(defvar codex-ide-status-mode--global-p)
(defvar codex-ide-status-mode-hook)

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

(ert-deftest codex-ide-org-lazy-project-index-switch-does-not-notify-status ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-switch-" t))
         (project-one (expand-file-name "one" temporary-directory))
         (project-two (expand-file-name "two" temporary-directory))
         (codex-ide-org-file-function
          (lambda (directory) (expand-file-name "tasks.org" directory)))
         (notifications 0)
         (codex-ide-org-index-updated-hook
          (list (lambda () (setq notifications (1+ notifications))))))
    (unwind-protect
        (progn
          (make-directory project-one t)
          (make-directory project-two t)
          (with-temp-file (expand-file-name "tasks.org" project-one)
            (insert "* WIP One\n:PROPERTIES:\n:CODEX_THREAD_ID: one\n:END:\n"))
          (with-temp-file (expand-file-name "tasks.org" project-two)
            (insert "* TODO Two\n:PROPERTIES:\n:CODEX_THREAD_ID: two\n:END:\n"))
          (codex-ide-org--ensure-current-index project-one)
          (should (eq (plist-get (codex-ide-org-thread-state "one" project-one)
                                 :status)
                      'linked))
          (codex-ide-org--ensure-current-index project-two)
          (should (eq (plist-get (codex-ide-org-thread-state "two" project-two)
                                 :status)
                      'linked))
          (should (= notifications 0)))
      (dolist (file (list (expand-file-name "tasks.org" project-one)
                          (expand-file-name "tasks.org" project-two)))
        (when-let* ((buffer (get-file-buffer file)))
          (kill-buffer buffer)))
      (delete-directory temporary-directory t))))

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

(ert-deftest codex-ide-org-open-thread-at-point-uses-id-and-directory-snapshot ()
  (codex-ide-org-test-with-file
      "* TODO Open\n:PROPERTIES:\n:CODEX_THREAD_ID: open-me\n:CODEX_CWD: /stale/snapshot\n:END:\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let (opened)
        (cl-letf (((symbol-function 'codex-ide-open-thread)
                   (lambda (&rest args) (setq opened args))))
          (codex-ide-org-open-thread-at-point))
        (should (equal opened '("open-me" "/stale/snapshot")))))))

(ert-deftest codex-ide-org-archive-commands-use-linked-id-without-changing-workflow ()
  (codex-ide-org-test-with-file
      "* HOLD Parked task\n:PROPERTIES:\n:CODEX_THREAD_ID: parked-thread\n:CODEX_CWD: /tmp/parked\n:END:\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let (calls)
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _args) t))
                  ((symbol-function 'codex-ide-archive-thread)
                   (lambda (thread-id &rest args)
                     (push (list 'archive thread-id args) calls)))
                  ((symbol-function 'codex-ide-unarchive-thread)
                   (lambda (thread-id &rest args)
                     (push (list 'unarchive thread-id args) calls))))
          (codex-ide-org-archive-thread-at-point)
          (codex-ide-org-unarchive-thread-at-point))
        (should (equal (nreverse calls)
                       '((archive "parked-thread" (:directory "/tmp/parked"))
                         (unarchive "parked-thread" (:directory "/tmp/parked")))))
        (should (equal (org-get-todo-state) "HOLD"))))))

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

(ert-deftest codex-ide-org-link-command-chooses-from-project-inventory ()
  (codex-ide-org-test-with-file "* TODO Choose thread\n"
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (goto-char (point-min))
      (let ((row '(:thread-id "global-choice"
                   :title "Global choice"
                   :directory "/tmp/global")))
        (cl-letf (((symbol-function 'codex-ide-list-thread-rows)
                   (lambda (&rest args)
                     (should (equal args (list :directory default-directory)))
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

(ert-deftest codex-ide-org-thread-selection-can-opt-in-to-global-inventory ()
  (let ((codex-ide-org-thread-list-scope 'global))
    (cl-letf (((symbol-function 'codex-ide-list-thread-rows)
               (lambda (&rest args)
                 (should (equal args '(:global t)))
                 (list '(:thread-id "global" :directory "/tmp/global")))))
      (should (equal (plist-get (car (codex-ide-org--thread-rows)) :thread-id)
                     "global")))))

(ert-deftest codex-ide-org-project-files-keep-project-indexes-separate ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-projects-" t))
         (project-one (expand-file-name "one" temporary-directory))
         (project-two (expand-file-name "two" temporary-directory))
         (codex-ide-org-file-function
          (lambda (directory)
            (expand-file-name ".codex-ide/tasks.org" directory)))
         buffers)
    (unwind-protect
        (progn
          (make-directory project-one t)
          (make-directory project-two t)
          (dolist (row `((:thread-id "one-thread" :directory ,project-one)
                         (:thread-id "two-thread" :directory ,project-two)))
            (push (marker-buffer
                   (codex-ide-org-create-task-for-row row "Project task"))
                  buffers))
          (should (eq (plist-get
                       (codex-ide-org-thread-state "one-thread" project-one)
                       :status)
                      'linked))
          (should (eq (plist-get
                       (codex-ide-org-thread-state "one-thread" project-two)
                       :status)
                      'missing))
          (should (file-exists-p
                   (expand-file-name ".codex-ide/tasks.org" project-one)))
          (should (file-exists-p
                   (expand-file-name ".codex-ide/tasks.org" project-two))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer) (kill-buffer buffer)))
      (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-project-file-alist-overrides-one-project ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-paths-" t))
         (special-project (expand-file-name "special" temporary-directory))
         (regular-project (expand-file-name "regular" temporary-directory))
         (codex-ide-org-project-file-name "project/tasks.org")
         (codex-ide-org-project-file-alist
          `((,(regexp-quote special-project) . "planning/codex.org"))))
    (unwind-protect
        (progn
          (make-directory special-project t)
          (make-directory regular-project t)
          (should (equal (codex-ide-org-project-file special-project)
                         (expand-file-name "planning/codex.org"
                                           special-project)))
          (should (equal (codex-ide-org-project-file regular-project)
                         (expand-file-name "project/tasks.org"
                                           regular-project))))
      (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-created-project-task-immediately-annotates-row ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-annotation-" t))
         (codex-ide-org-file-function
          (lambda (directory)
            (expand-file-name ".codex-ide/tasks.org" directory)))
         (row `(:thread-id "fresh-thread" :directory ,temporary-directory))
         buffer)
    (unwind-protect
        (progn
          (setq buffer
                (marker-buffer
                 (codex-ide-org-create-task-for-row row "Fresh task")))
          (should (equal (substring-no-properties
                          (codex-ide-org-status-annotation row))
                         "TODO")))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-reopens-killed-task-buffer-before-status-lookup ()
  (let* ((temporary-directory (make-temp-file "codex-ide-org-reopen-" t))
         (codex-ide-org-file-function
          (lambda (directory)
            (expand-file-name ".codex-ide/tasks.org" directory)))
         (row `(:thread-id "reopened-thread" :directory ,temporary-directory))
         (marker (codex-ide-org-create-task-for-row row "Reopen task"))
         (buffer (marker-buffer marker)))
    (unwind-protect
        (progn
          (kill-buffer buffer)
          (should-not (marker-buffer marker))
          (should (equal (substring-no-properties
                          (codex-ide-org-status-annotation row))
                         "TODO"))
          (should (codex-ide-org--row-navigable-p row))
          (should-not (codex-ide-org--row-missing-p row)))
      (when-let* ((task-buffer
                   (get-file-buffer
                    (expand-file-name ".codex-ide/tasks.org"
                                      temporary-directory))))
        (kill-buffer task-buffer))
      (delete-directory temporary-directory t))))

(ert-deftest codex-ide-org-create-task-rechecks-file-before-writing ()
  (codex-ide-org-test-with-file
      "* TODO Existing\n:PROPERTIES:\n:CODEX_THREAD_ID: on-disk\n:END:\n"
    (codex-ide-org--clear-index)
    (should-error
     (codex-ide-org-create-task-for-row
      '(:thread-id "on-disk" :directory "/tmp/project") "Duplicate")
     :type 'user-error)
    (with-current-buffer (get-file-buffer codex-ide-org-file)
      (should (= (how-many "^\\* TODO Existing$" (point-min) (point-max)) 1)))))

(ert-deftest codex-ide-org-global-status-annotation-is-opt-in ()
  (let ((codex-ide-status-mode--global-p t)
        (codex-ide-org-annotate-global-status nil))
    (should-not
     (codex-ide-org-status-annotation
      '(:thread-id "not-read" :directory "/tmp/project")))))

(ert-deftest codex-ide-org-status-annotation-separates-workflow-from-runtime ()
  (codex-ide-org-test-with-file
      "* REVIEW Review linked\n:PROPERTIES:\n:CODEX_THREAD_ID: linked-row\n:END:\n* TODO First duplicate\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-row\n:END:\n* HOLD Second duplicate\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-row\n:END:\n"
    (should (equal (codex-ide-org-status-annotation
                    '(:thread-id "linked-row" :technical-status "running"))
                   "REVIEW"))
    (should (equal (codex-ide-org-status-annotation
                    '(:thread-id "linked-row" :technical-status "stored"))
                   "REVIEW"))
    (should (equal (codex-ide-org-status-annotation
                    '(:thread-id "missing-row" :technical-status "running"))
                   "UNLINKED"))
    (should (equal (codex-ide-org-status-annotation
                    '(:thread-id "duplicate-row" :technical-status "idle"))
                   "DUPLICATE"))))

(ert-deftest codex-ide-org-status-integration-registers-context-actions ()
  (let ((codex-ide-status-before-title-functions nil)
        (codex-ide-status-actions nil)
        (codex-ide-status-mode-hook nil)
        (codex-ide-org-index-updated-hook nil)
        (codex-ide-org-status-integration-enabled-p nil))
    (cl-letf (((symbol-function 'codex-ide-status-notify-annotations-changed)
               #'ignore)
              ((symbol-function 'codex-ide-org--row-link-state)
               (lambda (row)
                 (list :status (plist-get row :org-status)))))
      (should (codex-ide-org-register-status-integration))
      (should (memq #'codex-ide-org-status-annotation
                    codex-ide-status-before-title-functions))
      (should (memq #'codex-ide-org--status-index-updated
                    codex-ide-org-index-updated-hook))
      (should (memq #'codex-ide-org--configure-status-keys-buffer
                    codex-ide-status-mode-hook))
      (should (codex-ide-org-register-status-integration))
      (should (= (length codex-ide-status-before-title-functions) 1))
      (should (= (length codex-ide-status-actions) 3))
      (should (equal
               (mapcar (lambda (action) (plist-get action :name))
                       (codex-ide-status-available-actions
                        '(:thread-id "missing" :org-status missing)))
               '("Org: Create task")))
      (should (equal
               (mapcar (lambda (action) (plist-get action :name))
                       (codex-ide-status-available-actions
                        '(:thread-id "linked" :org-status linked)))
               '("Org: Go to task" "Org: Set workflow state")))
      (should (equal
               (mapcar (lambda (action) (plist-get action :name))
                       (codex-ide-status-available-actions
                        '(:thread-id "duplicate" :org-status duplicate)))
               '("Org: Go to task" "Org: Set workflow state")))
      (should-not (codex-ide-org-unregister-status-integration))
      (should-not codex-ide-status-before-title-functions)
      (should-not codex-ide-status-actions)
      (should-not codex-ide-status-mode-hook)
      (should-not codex-ide-org-index-updated-hook))))

(ert-deftest codex-ide-org-set-thread-workflow-is-explicit-and-persistent ()
  (codex-ide-org-test-with-file
      "* TODO Change state\n:PROPERTIES:\n:CODEX_THREAD_ID: state-thread\n:END:\n"
    (let ((marker (codex-ide-org-set-thread-workflow "state-thread" "REVIEW")))
      (should (equal (codex-ide-org-marker-workflow-state marker) "REVIEW"))
      (with-current-buffer (marker-buffer marker)
        (should-not (buffer-modified-p))))
    (should-error (codex-ide-org-set-thread-workflow
                   "state-thread" "TECHNICALLY-RUNNING")
                  :type 'user-error)))

(ert-deftest codex-ide-org-status-set-workflow-offers-configured-states ()
  (codex-ide-org-test-with-file
      "* WIP Pick state\n:PROPERTIES:\n:CODEX_THREAD_ID: pick-state\n:END:\n"
    (let (offered initial)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices _predicate _require-match
                                  _initial-input _history default)
                   (setq offered choices
                         initial default)
                   "HOLD")))
        (codex-ide-org--status-set-workflow '(:thread-id "pick-state")))
      (should (equal initial "WIP"))
      (should (equal offered
                     '("PLAN" "TODO" "WIP" "REVIEW" "HOLD"
                       "DONE" "CANCELLED")))
      (should (equal
               (codex-ide-org-marker-workflow-state
                (codex-ide-org-require-thread-marker "pick-state"))
               "HOLD")))))

(ert-deftest codex-ide-org-status-set-workflow-resolves-duplicate-once ()
  (codex-ide-org-test-with-file
      "* TODO First\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-state\n:END:\n* REVIEW Second\n:PROPERTIES:\n:CODEX_THREAD_ID: duplicate-state\n:END:\n"
    (let ((marker-selections 0))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt choices &rest _)
                   (if (consp (car choices))
                       (progn
                         (setq marker-selections (1+ marker-selections))
                         (car (cadr choices)))
                     "DONE"))))
        (codex-ide-org--status-set-workflow
         '(:thread-id "duplicate-state")))
      (should (= marker-selections 1))
      (let ((markers (plist-get
                      (codex-ide-org-thread-state "duplicate-state") :markers)))
        (should (equal (codex-ide-org-marker-workflow-state (cadr markers))
                       "DONE"))))))

(ert-deftest codex-ide-org-status-classify-creates-and-classifies-archived-row ()
  (codex-ide-org-test-with-file ""
    (let ((row `(:thread-id "archived-unlinked"
                 :title "Classify from archive"
                 :directory ,temporary-directory
                 :archived t)))
      (codex-ide-org-classify-status-row row "REVIEW")
      (let ((marker (codex-ide-org-require-thread-marker
                     "archived-unlinked" temporary-directory)))
        (should (equal (codex-ide-org-marker-workflow-state marker) "REVIEW"))
        (should (equal (org-with-point-at marker
                         (org-get-heading t t t t))
                       "Classify from archive")))
      (should (equal
               (codex-ide-org-status-annotation row)
               "REVIEW")))))

(ert-deftest codex-ide-org-status-classify-reuses-linked-task ()
  (codex-ide-org-test-with-file
      "* TODO Existing task\n:PROPERTIES:\n:CODEX_THREAD_ID: linked-classification\n:END:\n"
    (codex-ide-org-classify-status-row
     '(:thread-id "linked-classification" :title "Ignored title") "HOLD")
    (let ((state (codex-ide-org-thread-state "linked-classification")))
      (should (eq (plist-get state :status) 'linked))
      (should (= (length (plist-get state :markers)) 1))
      (should (equal
               (codex-ide-org-marker-workflow-state (plist-get state :marker))
               "HOLD")))))

(ert-deftest codex-ide-org-status-classify-reads-second-key-and-stays-put ()
  (codex-ide-org-test-with-file
      "* WIP Keyboard task\n:PROPERTIES:\n:CODEX_THREAD_ID: keyboard-classification\n:END:\n"
    (with-temp-buffer
      (let ((status-buffer (current-buffer)))
        (cl-letf (((symbol-function 'read-key) (lambda (_prompt) ?r))
                  ((symbol-function 'codex-ide-status-row-at-point)
                   (lambda () '(:thread-id "keyboard-classification"))))
          (codex-ide-org-status-classify))
        (should (eq (current-buffer) status-buffer))))
    (should (equal
             (codex-ide-org-marker-workflow-state
              (codex-ide-org-require-thread-marker "keyboard-classification"))
             "REVIEW"))))

(ert-deftest codex-ide-org-status-classify-rejects-unassigned-key ()
  (codex-ide-org-test-with-file ""
    (cl-letf (((symbol-function 'read-key) (lambda (_prompt) ?x))
              ((symbol-function 'codex-ide-status-row-at-point)
               (lambda () '(:thread-id "must-not-exist"))))
      (should-error (codex-ide-org-status-classify) :type 'user-error))
    (should (eq (plist-get (codex-ide-org-thread-state "must-not-exist")
                           :status)
                'missing))))

(ert-deftest codex-ide-org-status-keys-mode-provides-classification-prefix ()
  (with-temp-buffer
    (codex-ide-org-status-keys-mode 1)
    (should (eq (key-binding (kbd "C-t"))
                #'codex-ide-org-status-classify))
    (codex-ide-org-status-keys-mode -1)
    (should-not codex-ide-org-status-keys-mode)))

(ert-deftest codex-ide-org-technical-events-do-not-change-workflow ()
  (codex-ide-org-test-with-file
      "* PLAN Remains planned\n:PROPERTIES:\n:CODEX_THREAD_ID: event-thread\n:END:\n"
    (let ((codex-ide-org-status-integration-enabled-p t)
          (notifications 0))
      (cl-letf (((symbol-function 'codex-ide-status-notify-annotations-changed)
                 (lambda () (setq notifications (1+ notifications)))))
        (codex-ide-org--status-index-updated))
      (should (= notifications 1))
      (should (equal
               (codex-ide-org-marker-workflow-state
                (codex-ide-org-require-thread-marker "event-thread"))
               "PLAN")))))

(provide 'codex-ide-org-tests)

;;; codex-ide-org-tests.el ends here
