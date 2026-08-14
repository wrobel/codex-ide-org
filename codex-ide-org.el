;;; codex-ide-org.el --- Org workflow data for Codex IDE -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Gunnar Wrobel

;; Author: Gunnar Wrobel
;; URL: https://github.com/wrobel/codex-ide-org
;; Version: 0.3.0
;; Package-Requires: ((emacs "28.1") (org "9.5") (codex-ide "0.3.2"))
;; Keywords: codex, ai, agents, outlines

;;; Commentary:

;; Optional Org data model and index for Codex IDE threads.  Org owns the
;; workflow state; Codex IDE continues to own technical session state.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'seq)
(require 'subr-x)
(require 'codex-ide-status-api)

(defgroup codex-ide-org nil
  "Org workflow data for Codex IDE threads."
  :group 'org
  :prefix "codex-ide-org-")

(define-error 'codex-ide-org-link-error "Codex IDE Org link error")
(define-error 'codex-ide-org-missing-link
  "No Org task is linked to this Codex thread"
  'codex-ide-org-link-error)
(define-error 'codex-ide-org-duplicate-link
  "Multiple Org tasks are linked to this Codex thread"
  'codex-ide-org-link-error)

(defconst codex-ide-org-thread-id-property "CODEX_THREAD_ID"
  "Org property containing the canonical Codex thread identity.")

(defconst codex-ide-org-directory-property "CODEX_CWD"
  "Org property containing a non-canonical working-directory snapshot.")

(defvar codex-ide-org--index (make-hash-table :test #'equal)
  "Map Codex thread IDs to lists of Org heading markers.")

(defvar codex-ide-org--indexed-file nil
  "Expanded file name used for the current index contents.")

(defvar codex-ide-org-index-generation 0
  "Number of completed index rebuilds in this Emacs process.")

(defvar codex-ide-org-index-updated-hook nil
  "Hook run after `codex-ide-org-rebuild-index' completes.")

(defvar codex-ide-org-status-integration-enabled-p nil
  "Non-nil when Codex status annotations and actions are registered.")

(defconst codex-ide-org--status-action-names
  '("Org: Go to task" "Org: Set workflow state" "Org: Create task")
  "Names of status actions owned by this package.")

(defun codex-ide-org--set-file (symbol value)
  "Set SYMBOL to VALUE and rebuild an existing index."
  (set-default symbol value)
  (when (and (boundp 'codex-ide-org--index)
             (fboundp 'codex-ide-org-rebuild-index))
    (codex-ide-org-rebuild-index)))

(defcustom codex-ide-org-file
  (locate-user-emacs-file "codex-ide/tasks.org")
  "Org file containing tasks linked to Codex threads.

Loading this package never creates the file.  Later explicit task-creation
commands may create it."
  :type 'file
  :set #'codex-ide-org--set-file
  :group 'codex-ide-org)

(defcustom codex-ide-org-todo-keywords
  '((sequence "PLAN(p)" "TODO(t)" "WIP(w)" "REVIEW(r)" "HOLD(h)"
              "|" "DONE(d)" "CANCELLED(c)"))
  "Buffer-local workflow sequence for `codex-ide-org-file'."
  :type 'sexp
  :group 'codex-ide-org)

(defcustom codex-ide-org-save-after-change t
  "When non-nil, save the Org task file after explicit link changes."
  :type 'boolean
  :group 'codex-ide-org)

(defun codex-ide-org--expanded-file ()
  "Return the expanded configured Org file name."
  (expand-file-name codex-ide-org-file))

(defun codex-ide-org--same-file-p (left right)
  "Return non-nil when LEFT and RIGHT name the same expanded file."
  (and left right
       (equal (expand-file-name left) (expand-file-name right))))

(defun codex-ide-org--clear-index ()
  "Detach existing markers and clear the thread index."
  (maphash
   (lambda (_thread-id markers)
     (dolist (marker markers)
       (set-marker marker nil)))
   codex-ide-org--index)
  (clrhash codex-ide-org--index))

(defun codex-ide-org--configure-workflow ()
  "Configure the Org workflow in the current task buffer only.

Org derives its buffer-local TODO regular expressions from the default value
of `org-todo-keywords'.  Temporarily supplying our sequence while Org computes
those expressions keeps the resulting workflow local to the configured file."
  (setq-local org-todo-keywords codex-ide-org-todo-keywords)
  (let ((previous-default (default-value 'org-todo-keywords)))
    (unwind-protect
        (progn
          (set-default 'org-todo-keywords codex-ide-org-todo-keywords)
          (org-set-regexps-and-options))
      (set-default 'org-todo-keywords previous-default))))

(defun codex-ide-org--install-save-hook ()
  "Install index maintenance when visiting `codex-ide-org-file'."
  (when (and buffer-file-name
             (codex-ide-org--same-file-p buffer-file-name codex-ide-org-file))
    (codex-ide-org--configure-workflow)
    (add-hook 'after-save-hook #'codex-ide-org--after-save nil t)))

(defun codex-ide-org--after-save ()
  "Rebuild the index after saving the configured Org file."
  (when (and buffer-file-name
             (codex-ide-org--same-file-p buffer-file-name codex-ide-org-file))
    (codex-ide-org-rebuild-index)))

;;;###autoload
(defun codex-ide-org-rebuild-index ()
  "Rebuild the Codex thread-to-Org-heading index.

Only non-empty `CODEX_THREAD_ID' values are indexed.  Multiple headings with
the same value are retained so callers can report a duplicate conflict.  The
configured file is not created when it does not exist."
  (interactive)
  (codex-ide-org--clear-index)
  (setq codex-ide-org--indexed-file (codex-ide-org--expanded-file))
  (when (file-readable-p codex-ide-org--indexed-file)
    (let ((buffer (find-file-noselect codex-ide-org--indexed-file)))
      (with-current-buffer buffer
        (unless (derived-mode-p 'org-mode)
          (org-mode))
        (codex-ide-org--install-save-hook)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (let ((thread-id (org-entry-get nil
                                            codex-ide-org-thread-id-property
                                            nil)))
              (when (and (stringp thread-id)
                         (not (string-empty-p (string-trim thread-id))))
                (setq thread-id (string-trim thread-id))
                (puthash thread-id
                         (append (gethash thread-id codex-ide-org--index)
                                 (list (copy-marker (point))))
                         codex-ide-org--index))))
          nil
          'file)))))
  (setq codex-ide-org-index-generation (1+ codex-ide-org-index-generation))
  (run-hooks 'codex-ide-org-index-updated-hook)
  codex-ide-org--index)

(defun codex-ide-org--ensure-current-index ()
  "Rebuild when the configured file differs from the indexed file."
  (unless (codex-ide-org--same-file-p codex-ide-org--indexed-file
                                     codex-ide-org-file)
    (codex-ide-org-rebuild-index)))

(defun codex-ide-org-index-markers (thread-id)
  "Return live Org markers associated with THREAD-ID."
  (codex-ide-org--ensure-current-index)
  (seq-filter (lambda (marker)
                (and (markerp marker) (marker-buffer marker)))
              (copy-sequence (gethash thread-id codex-ide-org--index))))

(defun codex-ide-org-thread-state (thread-id)
  "Return the Org link state plist for THREAD-ID.

The `:status' value is `missing', `linked', or `duplicate'.  `:markers'
contains every live matching heading marker.  For a unique link, `:marker'
contains that marker as a convenience."
  (unless (and (stringp thread-id) (not (string-empty-p (string-trim thread-id))))
    (user-error "A non-empty Codex thread ID is required"))
  (let ((markers (codex-ide-org-index-markers (string-trim thread-id))))
    (cond
     ((null markers)
      (list :thread-id thread-id :status 'missing :markers nil :marker nil))
     ((null (cdr markers))
      (list :thread-id thread-id :status 'linked
            :markers markers :marker (car markers)))
     (t
      (list :thread-id thread-id :status 'duplicate
            :markers markers :marker nil)))))

(defun codex-ide-org-require-thread-marker (thread-id)
  "Return the unique Org marker for THREAD-ID or signal a link error."
  (let ((state (codex-ide-org-thread-state thread-id)))
    (pcase (plist-get state :status)
      ('linked (plist-get state :marker))
      ('missing (signal 'codex-ide-org-missing-link (list thread-id)))
      ('duplicate (signal 'codex-ide-org-duplicate-link
                          (list thread-id (plist-get state :markers)))))))

(defun codex-ide-org-index-conflicts ()
  "Return state plists for every duplicate thread link."
  (codex-ide-org--ensure-current-index)
  (let (conflicts)
    (maphash
     (lambda (thread-id _markers)
       (let ((state (codex-ide-org-thread-state thread-id)))
         (when (eq (plist-get state :status) 'duplicate)
           (push state conflicts))))
     codex-ide-org--index)
    (nreverse conflicts)))

(defun codex-ide-org-marker-directory (marker)
  "Return MARKER's `CODEX_CWD' snapshot, or nil."
  (org-with-point-at marker
    (org-entry-get nil codex-ide-org-directory-property nil)))

(defun codex-ide-org-marker-workflow-state (marker)
  "Return MARKER's Org TODO keyword, or nil."
  (org-with-point-at marker
    (org-get-todo-state)))

(defun codex-ide-org--require-task-heading ()
  "Move to and return the current heading in the configured task file."
  (unless (derived-mode-p 'org-mode)
    (user-error "This command must be used from an Org heading"))
  (unless (and buffer-file-name
               (codex-ide-org--same-file-p buffer-file-name codex-ide-org-file))
    (user-error "This heading is not in the configured Codex task file: %s"
                (codex-ide-org--expanded-file)))
  (org-back-to-heading t)
  (copy-marker (point)))

(defun codex-ide-org--notify-changed ()
  "Notify Codex status consumers that Org link data changed."
  (when (fboundp 'codex-ide-status-notify-annotations-changed)
    (codex-ide-status-notify-annotations-changed)))

(defun codex-ide-org--save-and-refresh ()
  "Persist or re-index the current task buffer and notify consumers."
  (if codex-ide-org-save-after-change
      (save-buffer)
    (codex-ide-org-rebuild-index))
  (codex-ide-org--notify-changed))

(defun codex-ide-org--row-label (row)
  "Return an unambiguous completion label for normalized thread ROW."
  (format "%s — %s — %s"
          (or (plist-get row :title) "Untitled")
          (or (plist-get row :directory) "no working directory")
          (plist-get row :thread-id)))

(defun codex-ide-org--global-thread-rows ()
  "Return global normalized rows that have a usable thread ID."
  (seq-filter
   (lambda (row)
     (let ((thread-id (plist-get row :thread-id)))
       (and (stringp thread-id) (not (string-empty-p thread-id)))))
   (codex-ide-list-thread-rows :global t)))

(defun codex-ide-org--read-thread-row (prompt &optional predicate)
  "Read a global thread row using PROMPT, optionally limited by PREDICATE."
  (let* ((rows (if predicate
                   (seq-filter predicate (codex-ide-org--global-thread-rows))
                 (codex-ide-org--global-thread-rows)))
         (choices (mapcar (lambda (row)
                            (cons (codex-ide-org--row-label row) row))
                          rows)))
    (unless choices
      (user-error "No matching Codex threads were found"))
    (cdr (assoc (completing-read prompt choices nil t) choices))))

(defun codex-ide-org--marker-at-current-heading-p (marker)
  "Return non-nil when MARKER identifies the current Org heading."
  (and (markerp marker)
       (eq (marker-buffer marker) (current-buffer))
       (= (marker-position marker) (point))))

(defun codex-ide-org-link-heading (thread-id &optional directory replace)
  "Link the current task heading to THREAD-ID and snapshot DIRECTORY.

THREAD-ID must not already identify another heading.  When the current heading
already has a different ID, REPLACE must be non-nil.  This function does not
infer links from titles or directories."
  (unless (and (stringp thread-id) (not (string-empty-p (string-trim thread-id))))
    (user-error "A non-empty Codex thread ID is required"))
  (setq thread-id (string-trim thread-id))
  (codex-ide-org--require-task-heading)
  (codex-ide-org-rebuild-index)
  (let* ((existing-id (org-entry-get nil codex-ide-org-thread-id-property nil))
         (markers (codex-ide-org-index-markers thread-id))
         (other-markers
          (seq-remove #'codex-ide-org--marker-at-current-heading-p markers)))
    (when other-markers
      (user-error "Codex thread %s is already linked to another Org task"
                  thread-id))
    (when (and existing-id
               (not (equal (string-trim existing-id) thread-id))
               (not replace))
      (user-error "This task is already linked to Codex thread %s" existing-id))
    (org-entry-put nil codex-ide-org-thread-id-property thread-id)
    (when (and (stringp directory) (not (string-empty-p directory)))
      (org-entry-put nil codex-ide-org-directory-property directory))
    (codex-ide-org--save-and-refresh)
    (codex-ide-org-require-thread-marker thread-id)))

;;;###autoload
(defun codex-ide-org-link-current-heading ()
  "Choose a global Codex thread and link it to the current Org heading."
  (interactive)
  (codex-ide-org--require-task-heading)
  (let* ((row (codex-ide-org--read-thread-row "Link Codex thread: "))
         (thread-id (plist-get row :thread-id))
         (existing-id (org-entry-get nil codex-ide-org-thread-id-property nil))
         (replace (or (null existing-id)
                      (equal existing-id thread-id)
                      (yes-or-no-p
                       (format "Replace existing Codex link %s? " existing-id)))))
    (unless replace
      (user-error "Codex thread link was not changed"))
    (codex-ide-org-link-heading thread-id (plist-get row :directory) replace)
    (message "Linked Org task to Codex thread %s" thread-id)))

;;;###autoload
(defun codex-ide-org-unlink-current-heading ()
  "Remove the current Org heading's Codex link after confirmation."
  (interactive)
  (codex-ide-org--require-task-heading)
  (let ((thread-id (org-entry-get nil codex-ide-org-thread-id-property nil)))
    (unless thread-id
      (user-error "This Org task is not linked to a Codex thread"))
    (unless (yes-or-no-p (format "Unlink Codex thread %s? " thread-id))
      (user-error "Codex thread link was not removed"))
    (org-entry-delete nil codex-ide-org-thread-id-property)
    (org-entry-delete nil codex-ide-org-directory-property)
    (codex-ide-org--save-and-refresh)
    (message "Unlinked Codex thread %s" thread-id)))

;;;###autoload
(defun codex-ide-org-open-thread-at-point ()
  "Open the Codex thread linked to the current Org heading."
  (interactive)
  (codex-ide-org--require-task-heading)
  (let ((thread-id (org-entry-get nil codex-ide-org-thread-id-property nil)))
    (unless thread-id
      (user-error "This Org task is not linked to a Codex thread"))
    ;; Resolve the current directory from Codex.  CODEX_CWD is only a snapshot.
    (codex-ide-open-thread thread-id)))

(defun codex-ide-org--marker-label (marker)
  "Return a completion label for an Org heading at MARKER."
  (org-with-point-at marker
    (format "%s — %s:%d"
            (org-get-heading t t t t)
            (or buffer-file-name (buffer-name))
            (line-number-at-pos))))

(defun codex-ide-org-resolve-thread-marker (thread-id)
  "Return an Org marker for THREAD-ID, asking when duplicates exist."
  (let* ((state (codex-ide-org-thread-state thread-id))
         (markers (plist-get state :markers)))
    (pcase (plist-get state :status)
      ('missing
       (user-error "No Org task is linked to Codex thread %s" thread-id))
      ('linked (car markers))
      ('duplicate
       (let ((choices (mapcar (lambda (marker)
                                (cons (codex-ide-org--marker-label marker) marker))
                              markers)))
         (cdr (assoc (completing-read
                      (format "Multiple Org tasks link %s; choose: " thread-id)
                      choices nil t)
                     choices)))))))

(defun codex-ide-org--display-marker (marker)
  "Display the Org heading at MARKER and return MARKER."
  (pop-to-buffer-same-window (marker-buffer marker))
  (goto-char marker)
  (if (fboundp 'org-fold-show-context)
      (org-fold-show-context)
    (with-no-warnings (org-show-context)))
  (if (fboundp 'org-fold-show-entry)
      (org-fold-show-entry)
    (with-no-warnings (org-show-entry)))
  marker)

;;;###autoload
(defun codex-ide-org-goto-thread-task (thread-id)
  "Jump to the Org task linked to Codex THREAD-ID.

Interactively, choose THREAD-ID from the global Codex inventory."
  (interactive
   (list (plist-get (codex-ide-org--read-thread-row "Go to Org task for: ")
                    :thread-id)))
  (codex-ide-org--display-marker
   (codex-ide-org-resolve-thread-marker thread-id)))

(defun codex-ide-org--task-title (title)
  "Return TITLE normalized for a single Org heading line."
  (let ((title (string-trim (replace-regexp-in-string "[\n\r]+" " " title))))
    (if (string-empty-p title) "Untitled Codex task" title)))

(defun codex-ide-org-create-task-for-row (row title)
  "Create and persist an Org task for unlinked Codex ROW using TITLE.

This is the only work-package-5 operation that may create
`codex-ide-org-file' and its parent directory."
  (let ((thread-id (plist-get row :thread-id))
        (directory (plist-get row :directory)))
    (unless (and (stringp thread-id) (not (string-empty-p thread-id)))
      (user-error "The Codex row has no usable thread ID"))
    (pcase (plist-get (codex-ide-org-thread-state thread-id) :status)
      ('linked (user-error "Codex thread %s already has an Org task" thread-id))
      ('duplicate (user-error "Codex thread %s has multiple Org tasks" thread-id)))
    (make-directory (file-name-directory (codex-ide-org--expanded-file)) t)
    (let ((buffer (find-file-noselect (codex-ide-org--expanded-file))))
      (with-current-buffer buffer
        (unless (derived-mode-p 'org-mode)
          (org-mode))
        (codex-ide-org--install-save-hook)
        (goto-char (point-max))
        (unless (or (= (point-min) (point-max)) (bolp))
          (insert "\n"))
        (insert "* TODO " (codex-ide-org--task-title title) "\n")
        (forward-line -1)
        (org-entry-put nil codex-ide-org-thread-id-property thread-id)
        (when (and (stringp directory) (not (string-empty-p directory)))
          (org-entry-put nil codex-ide-org-directory-property directory))
        ;; Explicit task creation is always persisted, independent of the
        ;; link-change preference.
        (save-buffer)
        (codex-ide-org--notify-changed)
        (codex-ide-org-require-thread-marker thread-id)))))

;;;###autoload
(defun codex-ide-org-create-thread-task ()
  "Choose an unlinked global Codex thread and create its Org task explicitly."
  (interactive)
  (let* ((row (codex-ide-org--read-thread-row
               "Create Org task for: "
               (lambda (candidate)
                 (eq (plist-get
                      (codex-ide-org-thread-state
                       (plist-get candidate :thread-id))
                      :status)
                     'missing))))
         (default-title (or (plist-get row :title) "Untitled Codex task"))
         (title (read-string "Org task title: " nil nil default-title))
         (marker (codex-ide-org-create-task-for-row row title)))
    (codex-ide-org--display-marker marker)
    (message "Created Org task for Codex thread %s"
             (plist-get row :thread-id))))

(defun codex-ide-org--row-thread-id (row)
  "Return ROW's usable Codex thread ID, or nil."
  (let ((thread-id (plist-get row :thread-id)))
    (and (stringp thread-id)
         (not (string-empty-p (string-trim thread-id)))
         (string-trim thread-id))))

(defun codex-ide-org--row-link-state (row)
  "Return the Org link state for normalized Codex ROW, or nil."
  (when-let* ((thread-id (codex-ide-org--row-thread-id row)))
    (codex-ide-org-thread-state thread-id)))

(defun codex-ide-org--workflow-face (state)
  "Return an Org face suitable for workflow STATE."
  (if (member state '("DONE" "CANCELLED")) 'org-done 'org-todo))

(defun codex-ide-org-status-annotation (row)
  "Return a clearly labelled Org workflow annotation for Codex ROW."
  (when-let* ((link-state (codex-ide-org--row-link-state row)))
    (pcase (plist-get link-state :status)
      ('missing
       (concat "Workflow: " (propertize "UNLINKED" 'face 'shadow)))
      ('duplicate
       (concat "Workflow: " (propertize "DUPLICATE" 'face 'error)))
      ('linked
       (let ((workflow
              (or (codex-ide-org-marker-workflow-state
                   (plist-get link-state :marker))
                  "NONE")))
         (concat "Workflow: "
                 (propertize workflow
                             'face (codex-ide-org--workflow-face workflow))))))))

(defun codex-ide-org--row-missing-p (row)
  "Return non-nil when Codex ROW has no linked Org task."
  (eq (plist-get (codex-ide-org--row-link-state row) :status) 'missing))

(defun codex-ide-org--row-navigable-p (row)
  "Return non-nil when Codex ROW has one or more linked Org tasks."
  (memq (plist-get (codex-ide-org--row-link-state row) :status)
        '(linked duplicate)))

(defun codex-ide-org--status-goto-task (row)
  "Status action that jumps from Codex ROW to its Org task."
  (codex-ide-org-goto-thread-task (codex-ide-org--row-thread-id row)))

(defun codex-ide-org--status-create-task (row)
  "Explicitly create and display a task for Codex ROW as a status action."
  (let ((marker (codex-ide-org-create-task-for-row
                 row (or (plist-get row :title) "Untitled Codex task"))))
    (codex-ide-org--display-marker marker)
    marker))

(defun codex-ide-org--marker-workflow-keywords (marker)
  "Return the available workflow keywords at Org MARKER."
  (org-with-point-at marker
    (copy-sequence org-todo-keywords-1)))

(defun codex-ide-org--set-marker-workflow (marker workflow)
  "Set Org MARKER to WORKFLOW explicitly and return a fresh marker."
  (unless (member workflow (codex-ide-org--marker-workflow-keywords marker))
    (user-error "Unknown Codex Org workflow state: %s" workflow))
  (org-with-point-at marker
    (org-back-to-heading t)
    (org-todo workflow)
    (codex-ide-org--save-and-refresh)
    ;; Saving rebuilds the index and deliberately detaches its old markers.
    ;; Return a fresh marker at the still-current heading.
    (copy-marker (point))))

(defun codex-ide-org-set-thread-workflow (thread-id workflow)
  "Set linked THREAD-ID's Org WORKFLOW state explicitly and return its marker."
  (codex-ide-org--set-marker-workflow
   (codex-ide-org-resolve-thread-marker thread-id)
   workflow))

(defun codex-ide-org--status-set-workflow (row)
  "Explicitly change the Org workflow for Codex ROW as a status action."
  (let* ((thread-id (codex-ide-org--row-thread-id row))
         (marker (codex-ide-org-resolve-thread-marker thread-id))
         (keywords (codex-ide-org--marker-workflow-keywords marker))
         (current (codex-ide-org-marker-workflow-state marker))
         (workflow (completing-read "Org workflow state: " keywords nil t
                                    nil nil current)))
    (codex-ide-org--set-marker-workflow marker workflow)))

(defun codex-ide-org--status-index-updated ()
  "Refresh Codex status buffers after an external Org index update."
  (when codex-ide-org-status-integration-enabled-p
    (codex-ide-status-notify-annotations-changed)))

;;;###autoload
(defun codex-ide-org-register-status-integration ()
  "Register Org workflow annotations and actions in Codex status views."
  (interactive)
  (unless codex-ide-org-status-integration-enabled-p
    (add-hook 'codex-ide-status-annotation-functions
              #'codex-ide-org-status-annotation)
    ;; Registration prepends entries, so register in reverse display order.
    (codex-ide-register-status-action
     "Org: Create task"
     #'codex-ide-org--status-create-task
     #'codex-ide-org--row-missing-p)
    (codex-ide-register-status-action
     "Org: Set workflow state"
     #'codex-ide-org--status-set-workflow
     #'codex-ide-org--row-navigable-p)
    (codex-ide-register-status-action
     "Org: Go to task"
     #'codex-ide-org--status-goto-task
     #'codex-ide-org--row-navigable-p)
    (add-hook 'codex-ide-org-index-updated-hook
              #'codex-ide-org--status-index-updated)
    (setq codex-ide-org-status-integration-enabled-p t)
    (codex-ide-status-notify-annotations-changed))
  codex-ide-org-status-integration-enabled-p)

;;;###autoload
(defun codex-ide-org-unregister-status-integration ()
  "Remove this package's annotations and actions from Codex status views."
  (interactive)
  (remove-hook 'codex-ide-status-annotation-functions
               #'codex-ide-org-status-annotation)
  (dolist (name codex-ide-org--status-action-names)
    (codex-ide-unregister-status-action name))
  (remove-hook 'codex-ide-org-index-updated-hook
               #'codex-ide-org--status-index-updated)
  (setq codex-ide-org-status-integration-enabled-p nil)
  (codex-ide-status-notify-annotations-changed)
  codex-ide-org-status-integration-enabled-p)

(add-hook 'org-mode-hook #'codex-ide-org--install-save-hook)
(codex-ide-org-rebuild-index)

(provide 'codex-ide-org)

;;; codex-ide-org.el ends here
