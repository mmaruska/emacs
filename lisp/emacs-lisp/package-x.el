;;; package-x.el --- Package extras

;; Copyright (C) 2007-2011 Free Software Foundation, Inc.

;; Author: Tom Tromey <tromey@redhat.com>
;; Created: 10 Mar 2007
;; Version: 0.9
;; Keywords: tools
;; Package: package

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This file currently contains parts of the package system most
;; people won't need, such as package uploading.

;;; Code:

(require 'package)
(defvar gnus-article-buffer)

;; Note that this only works if you have the password, which you
;; probably don't :-).
(defvar package-archive-upload-base nil
  "Base location for uploading to package archive.")

(defvar package-update-news-on-upload nil
  "Whether package upload should also update NEWS and RSS feeds.")

(defun package--encode (string)
  "Encode a string by replacing some characters with XML entities."
  ;; We need a special case for translating "&" to "&amp;".
  (let ((index))
    (while (setq index (string-match "[&]" string index))
      (setq string (replace-match "&amp;" t nil string))
      (setq index (1+ index))))
  (while (string-match "[<]" string)
    (setq string (replace-match "&lt;" t nil string)))
  (while (string-match "[>]" string)
    (setq string (replace-match "&gt;" t nil string)))
  (while (string-match "[']" string)
    (setq string (replace-match "&apos;" t nil string)))
  (while (string-match "[\"]" string)
    (setq string (replace-match "&quot;" t nil string)))
  string)

(defun package--make-rss-entry (title text archive-url)
  (let ((date-string (format-time-string "%a, %d %B %Y %T %z")))
    (concat "<item>\n"
	    "<title>" (package--encode title) "</title>\n"
	    ;; FIXME: should have a link in the web page.
	    "<link>" archive-url "news.html</link>\n"
	    "<description>" (package--encode text) "</description>\n"
	    "<pubDate>" date-string "</pubDate>\n"
	    "</item>\n")))

(defun package--make-html-entry (title text)
  (concat "<li> " (format-time-string "%B %e") " - "
	  title " - " (package--encode text)
	  " </li>\n"))

(defun package--update-file (file location text)
  (save-excursion
    (let ((old-buffer (find-buffer-visiting file)))
      (with-current-buffer (let ((find-file-visit-truename t))
			     (or old-buffer (find-file-noselect file)))
	(goto-char (point-min))
	(search-forward location)
	(forward-line)
	(insert text)
	(let ((file-precious-flag t))
	  (save-buffer))
	(unless old-buffer
	  (kill-buffer (current-buffer)))))))

(defun package--archive-contents-from-url (archive-url)
  "Parse archive-contents file at ARCHIVE-URL.
Return the file contents, as a string, or nil if unsuccessful."
  (ignore-errors
    (when archive-url
      (let* ((buffer (url-retrieve-synchronously
		      (concat archive-url "archive-contents"))))
	(set-buffer buffer)
	(package-handle-response)
	(re-search-forward "^$" nil 'move)
	(forward-char)
	(delete-region (point-min) (point))
	(prog1 (package-read-from-string
		(buffer-substring-no-properties (point-min) (point-max)))
	  (kill-buffer buffer))))))

(defun package--archive-contents-from-file (file)
  "Parse the given archive-contents file."
  (if (not (file-exists-p file))
      ;; no existing archive-contents, possibly a new ELPA repo.
      (list package-archive-version)
    (let ((dont-kill (find-buffer-visiting file)))
      (with-current-buffer (let ((find-file-visit-truename t))
			     (find-file-noselect file))
	(prog1
	    (package-read-from-string
	     (buffer-substring-no-properties (point-min) (point-max)))
	  (unless dont-kill
	    (kill-buffer (current-buffer))))))))

(defun package-maint-add-news-item (title description archive-url)
  "Add a news item to the ELPA web pages.
TITLE is the title of the news item.
DESCRIPTION is the text of the news item.
You need administrative access to ELPA to use this."
  (interactive "sTitle: \nsText: ")
  (package--update-file (concat package-archive-upload-base "elpa.rss")
			"<description>"
			(package--make-rss-entry title description archive-url))
  (package--update-file (concat package-archive-upload-base "news.html")
			"New entries go here"
			(package--make-html-entry title description)))

(defun package--update-news (package version description archive-url)
  "Update the ELPA web pages when a package is uploaded."
  (package-maint-add-news-item (concat package " version " version)
			       description
			       archive-url))

(defun package-upload-buffer-internal (pkg-info extension &optional archive-url)
  "Upload a package whose contents are in the current buffer.
PKG-INFO is the package info, see `package-buffer-info'.
EXTENSION is the file extension, a string.  It can be either
\"el\" or \"tar\".

The variable `package-archive-upload-base' specifies the upload
destination.  If this is nil, signal an error.

Optional arg ARCHIVE-URL is the URL of the destination archive.
If it is non-nil, compute the new \"archive-contents\" file
starting from the existing \"archive-contents\" at that URL.  In
addition, if `package-update-news-on-upload' is non-nil, call
`package--update-news' to add a news item at that URL.

If ARCHIVE-URL is nil, compute the new \"archive-contents\" file
from the \"archive-contents\" at `package-archive-upload-base',
if it exists."
  (unless package-archive-upload-base
    (error "No destination specified in `package-archive-upload-base'"))
  (save-excursion
    (save-restriction
      (let* ((file-type (cond
			 ((equal extension "el") 'single)
			 ((equal extension "tar") 'tar)
			 (t (error "Unknown extension `%s'" extension))))
	     (file-name (aref pkg-info 0))
	     (pkg-name (intern file-name))
	     (requires (aref pkg-info 1))
	     (desc (if (string= (aref pkg-info 2) "")
		       (read-string "Description of package: ")
		     (aref pkg-info 2)))
	     (pkg-version (aref pkg-info 3))
	     (commentary (aref pkg-info 4))
	     (split-version (version-to-list pkg-version))
	     (pkg-buffer (current-buffer)))

	;; Get archive-contents from ARCHIVE-URL if it's non-nil, or
	;; from `package-archive-upload-base' otherwise.
	(let ((contents (or (package--archive-contents-from-url archive-url)
			    (package--archive-contents-from-file
			     (concat package-archive-upload-base
				     "archive-contents"))))
	      (new-desc (vector split-version requires desc file-type)))
	  (if (> (car contents) package-archive-version)
	      (error "Unrecognized archive version %d" (car contents)))
	  (let ((elt (assq pkg-name (cdr contents))))
	    (if elt
		(if (version-list-<= split-version
				     (package-desc-vers (cdr elt)))
		    (error "New package has smaller version: %s" pkg-version)
		  (setcdr elt new-desc))
	      (setq contents (cons (car contents)
				   (cons (cons pkg-name new-desc)
					 (cdr contents))))))

	  ;; Now CONTENTS is the updated archive contents.  Upload
	  ;; this and the package itself.  For now we assume ELPA is
	  ;; writable via file primitives.
	  (let ((print-level nil)
		(print-length nil))
	    (write-region (concat (pp-to-string contents) "\n")
			  nil
			  (concat package-archive-upload-base
				  "archive-contents")))

	  ;; If there is a commentary section, write it.
	  (when commentary
	    (write-region commentary nil
			  (concat package-archive-upload-base
				  (symbol-name pkg-name) "-readme.txt")))

	  (set-buffer pkg-buffer)
	  (write-region (point-min) (point-max)
			(concat package-archive-upload-base
				file-name "-" pkg-version
				"." extension)
			nil nil nil 'excl)

	  ;; Write a news entry.
	  (and package-update-news-on-upload
	       archive-url
	       (package--update-news (concat file-name "." extension)
				     pkg-version desc archive-url))

	  ;; special-case "package": write a second copy so that the
	  ;; installer can easily find the latest version.
	  (if (string= file-name "package")
	      (write-region (point-min) (point-max)
			    (concat package-archive-upload-base
				    file-name "." extension)
			    nil nil nil 'ask)))))))

(defun package-upload-buffer ()
  "Upload the current buffer as a single-file Emacs Lisp package.
The variable `package-archive-upload-base' specifies the upload
destination."
  (interactive)
  (save-excursion
    (save-restriction
      ;; Find the package in this buffer.
      (let ((pkg-info (package-buffer-info)))
	(package-upload-buffer-internal pkg-info "el")))))

(defun package-upload-file (file)
  "Upload the Emacs Lisp package FILE to the package archive.
Interactively, prompt for FILE.  The package is considered a
single-file package if FILE ends in \".el\", and a multi-file
package if FILE ends in \".tar\".

The variable `package-archive-upload-base' specifies the upload
destination."
  (interactive "fPackage file name: ")
  (with-temp-buffer
    (insert-file-contents-literally file)
    (let ((info (cond
		 ((string-match "\\.tar$" file) (package-tar-file-info file))
		 ((string-match "\\.el$" file) (package-buffer-info))
		 (t (error "Unrecognized extension `%s'"
			   (file-name-extension file))))))
      (package-upload-buffer-internal info (file-name-extension file)))))

(defun package-gnus-summary-upload ()
  "Upload a package contained in the current *Article* buffer.
This should be invoked from the gnus *Summary* buffer."
  (interactive)
  (with-current-buffer gnus-article-buffer
    (package-upload-buffer)))

(provide 'package-x)

;;; package.el ends here
