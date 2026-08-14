;;; codex-ide-org.el --- Org workflow data for Codex IDE -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Gunnar Wrobel

;; Author: Gunnar Wrobel
;; URL: https://github.com/wrobel/codex-ide-org
;; Version: 0.1.0
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

(add-hook 'org-mode-hook #'codex-ide-org--install-save-hook)
(codex-ide-org-rebuild-index)

(provide 'codex-ide-org)

;;; codex-ide-org.el ends here
