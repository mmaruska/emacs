;;; diff.el --- Run `diff' in compilation-mode.

;; Copyright (C) 1992 Free Software Foundation, Inc.

;; Keyword: unix, tools

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Code:

(require 'compile)

(defvar diff-switches nil
  "*A string or list of strings specifying switches to be be passed to diff.")

(defvar diff-regexp-alist
  '(
    ;; -u format: @@ -OLDSTART,OLDEND +NEWSTART,NEWEND @@
    ("^@@ -\\([0-9]+\\),[0-9]+ \\+\\([0-9]+\\),[0-9]+ @@$" 1 2)
  
    ;; -c format: *** OLDSTART,OLDEND ****
    ("^\\*\\*\\* \\([0-9]+\\),[0-9]+ \\*\\*\\*\\*$" 1 nil)
    ;;            --- NEWSTART,NEWEND ----
    ("^--- \\([0-9]+\\),[0-9]+ ----$" nil 1)

    ;; plain diff format: OLDSTART[,OLDEND]{a,d,c}NEWSTART[,NEWEND]
    ("^\\([0-9]+\\)\\(,[0-9]+\\)?[adc]\\([0-9]+\\)\\(,[0-9]+\\)?$" 1 3)

    ;; -e (ed) format: OLDSTART[,OLDEND]{a,d,c}
    ("^\\([0-9]+\\)\\(,[0-9]+\\)?[adc]$" 1)

    ;; -f format: {a,d,c}OLDSTART[ OLDEND]
    ;; -n format: {a,d,c}OLDSTART LINES-CHANGED
    ("^[adc]\\([0-9]+\\)\\( [0-9]+\\)?$" 1)
    )
  "Alist (REGEXP OLD-IDX NEW-IDX) of regular expressions to match difference 
sections in \\[diff] output.  If REGEXP matches, the OLD-IDX'th
subexpression gives the line number in the old file, and NEW-IDX'th
subexpression gives the line number in the new file.  If OLD-IDX or NEW-IDX
is nil, REGEXP matches only half a section.")

;; See compilation-parse-errors-function (compile.el).
(defun diff-parse-differences (limit-search find-at-least)
  (setq compilation-error-list nil)
  (message "Parsing differences...")

  ;; Don't reparse diffs already seen at last parse.
  (goto-char compilation-parsing-end)

  ;; Construct in REGEXP a regexp composed of all those in dired-regexp-alist.
  (let ((regexp (mapconcat (lambda (elt)
			     (concat "\\(" (car elt) "\\)"))
			   diff-regexp-alist
			   "\\|"))
	;; (GROUP-IDX OLD-IDX NEW-IDX)
	(groups (let ((subexpr 1))
		  (mapcar (lambda (elt)
			    (prog1
				(cons subexpr
				      (mapcar (lambda (n)
						(and n
						     (+ subexpr n)))
					      (cdr elt)))
			      (setq subexpr (+ subexpr 1
					       (count-regexp-groupings
						(car elt))))))
			  diff-regexp-alist)))

	(new-error
	 (function (lambda (file subexpr)
		     (setq compilation-error-list
			   (cons
			    (cons (set-marker (make-marker)
					      (match-beginning subexpr)
					      (current-buffer))
				  (let ((line (string-to-int
					       (buffer-substring
						(match-beginning subexpr)
						(match-end subexpr)))))
				    (save-excursion
				      (set-buffer (find-file-noselect file))
				      (save-excursion
					(goto-line line)
					(point-marker)))))
			    compilation-error-list)))))

	(found-desired nil)
	g)

    (while (and (not found-desired)
		;; We don't just pass LIMIT-SEARCH to re-search-forward
		;; because we want to find matches containing LIMIT-SEARCH
		;; but which extend past it.
		(re-search-forward regexp nil t))

      ;; Find which individual regexp matched.
      (setq g groups)
      (while (and g (null (match-beginning (car (car g)))))
	(setq g (cdr g)))
      (setq g (car g))

      (if (nth 1 g)			;OLD-IDX
	  (funcall new-error diff-old-file (nth 1 g)))
      (if (nth 2 g)			;NEW-IDX
	  (funcall new-error diff-new-file (nth 2 g)))

      (if (or (and find-at-least (>= nfound find-at-least))
	      (and limit-search (>= (point) limit-search)))
	      ;; We have found as many new errors as the user wants,
	      ;; or the user wanted a specific diff, and we're past it.
	  (setq found-desired t)))
    (if found-desired
	(setq compilation-parsing-end (point))
      ;; Set to point-max, not point, so we don't perpetually
      ;; parse the last bit of text when it isn't a diff header.
      (setq compilation-parsing-end (point-max))
      (message "Parsing differences...done")))
  (setq compilation-error-list (nreverse compilation-error-list)))

;;;###autoload
(defun diff (old new &optional switches)
  "Find and display the differences between OLD and NEW files.
Interactively the current buffer's file name is the default for for NEW
and a backup file for NEW is the default for OLD.
With prefix arg, prompt for diff switches."
  (interactive
   (nconc
    (let (oldf newf)
      (nreverse
       (list
	(setq newf (buffer-file-name)
	      newf (if (and newf (file-exists-p newf))
		       (read-file-name
			(concat "Diff new file: ("
				(file-name-nondirectory newf) ") ")
			nil newf t)
		     (read-file-name "Diff new file: " nil nil t)))
	(setq oldf (file-newest-backup newf)
	      oldf (if (and oldf (file-exists-p oldf))
		       (read-file-name
			(concat "Diff original file: ("
				(file-name-nondirectory oldf) ") ")
			(file-name-directory oldf) oldf t)
		     (read-file-name "Diff original file: "
				     (file-name-directory newf) nil t))))))
    (if current-prefix-arg
	(list (read-string "Diff switches: "
			   (if (stringp diff-switches)
			       diff-switches
			     (mapconcat 'identity diff-switches " "))))
      nil)))
  (message "Comparing files %s %s..." new old)
  (setq new (expand-file-name new)
	old (expand-file-name old))
  (let ((old-alt (diff-prepare old new))
	(new-alt (diff-prepare new old))
	buf)
    (unwind-protect
	(let ((command
	       (mapconcat 'identity
			  (append '("diff")
				  (if (consp diff-switches)
				      diff-switches
				    (list diff-switches))
				  (if (or old-alt new-alt)
				      (list "-L" old "-L" new))
				  (list (or old-alt old))
				  (list (or new-alt new)))
			  " ")))
	  (setq buf
		(compile-internal command
				  "No more differences" "Diff"
				  'diff-parse-differences)))
	  (save-excursion
	    (set-buffer buf)
	    (set (make-local-variable 'diff-old-file) old)
	    (set (make-local-variable 'diff-new-file) new))
	  buf)
      (if old-alt (delete-file old-alt))
      (if new-alt (delete-file new-alt)))))

;; Copy the file FILE into a temporary file if that is necessary
;; for comparison.  (This is only necessary if the file name has a handler.)
;; OTHER is the other file to be compared.
(defun diff-prepare (file other)
  (let (handler handlers)
    (setq handlers file-name-handler-alist)
    (while (and (consp handlers) (null handler))
      (if (and (consp (car handlers))
	       (stringp (car (car handlers)))
	       (string-match (car (car handlers)) file))
	  (setq handler (cdr (car handlers))))
      (setq handlers (cdr handlers)))
    (if handler
	(funcall handler 'diff-prepare file other)
      nil)))

;;;###autoload
(defun diff-backup (file &optional switches)
  "Diff this file with its backup file or vice versa.
Uses the latest backup, if there are several numerical backups.
If this file is a backup, diff it with its original.
The backup file is the first file given to `diff'."
  (interactive (list (read-file-name "Diff (file with backup): ")
		     (if current-prefix-arg
			 (read-string "Diff switches: "
				      (if (stringp diff-switches)
					  diff-switches
					(mapconcat 'identity
						   diff-switches " ")))
		       nil)))
  (let (bak ori)
    (if (backup-file-name-p file)
	(setq bak file
	      ori (file-name-sans-versions file))
      (setq bak (or (diff-latest-backup-file file)
		    (error "No backup found for %s" file))
	    ori file))
    (diff bak ori switches)))

(defun diff-latest-backup-file (fn)	; actually belongs into files.el
  "Return the latest existing backup of FILE, or nil."
  ;; First try simple backup, then the highest numbered of the
  ;; numbered backups.
  ;; Ignore the value of version-control because we look for existing
  ;; backups, which maybe were made earlier or by another user with
  ;; a different value of version-control.
  (setq fn (expand-file-name fn))
  (or
   (let ((bak (make-backup-file-name fn)))
     (if (file-exists-p bak) bak))
   (let* ((dir (file-name-directory fn))
	  (base-versions (concat (file-name-nondirectory fn) ".~"))
	  (bv-length (length base-versions)))
     (concat dir
	     (car (sort
		   (file-name-all-completions base-versions dir)
		   ;; bv-length is a fluid var for backup-extract-version:
		   (function
		    (lambda (fn1 fn2)
		      (> (backup-extract-version fn1)
			 (backup-extract-version fn2))))))))))

;;; diff.el ends here
