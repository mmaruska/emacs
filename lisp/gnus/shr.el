;;; shr.el --- Simple HTML Renderer

;; Copyright (C) 2010-2011 Free Software Foundation, Inc.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>
;; Keywords: html

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package takes a HTML parse tree (as provided by
;; libxml-parse-html-region) and renders it in the current buffer.  It
;; does not do CSS, JavaScript or anything advanced: It's geared
;; towards rendering typical short snippets of HTML, like what you'd
;; find in HTML email and the like.

;;; Code:

(eval-when-compile (require 'cl))
(require 'browse-url)

(defgroup shr nil
  "Simple HTML Renderer"
  :group 'mail)

(defcustom shr-max-image-proportion 0.9
  "How big pictures displayed are in relation to the window they're in.
A value of 0.7 means that they are allowed to take up 70% of the
width and height of the window.  If they are larger than this,
and Emacs supports it, then the images will be rescaled down to
fit these criteria."
  :version "24.1"
  :group 'shr
  :type 'float)

(defcustom shr-blocked-images nil
  "Images that have URLs matching this regexp will be blocked."
  :version "24.1"
  :group 'shr
  :type 'regexp)

(defcustom shr-table-horizontal-line ? 
  "Character used to draw horizontal table lines."
  :group 'shr
  :type 'character)

(defcustom shr-table-vertical-line ? 
  "Character used to draw vertical table lines."
  :group 'shr
  :type 'character)

(defcustom shr-table-corner ? 
  "Character used to draw table corners."
  :group 'shr
  :type 'character)

(defcustom shr-hr-line ?-
  "Character used to draw hr lines."
  :group 'shr
  :type 'character)

(defcustom shr-width fill-column
  "Frame width to use for rendering.
May either be an integer specifying a fixed width in characters,
or nil, meaning that the full width of the window should be
used."
  :type '(choice (integer :tag "Fixed width in characters")
		 (const   :tag "Use the width of the window" nil))
  :group 'shr)

(defvar shr-content-function nil
  "If bound, this should be a function that will return the content.
This is used for cid: URLs, and the function is called with the
cid: URL as the argument.")

;;; Internal variables.

(defvar shr-folding-mode nil)
(defvar shr-state nil)
(defvar shr-start nil)
(defvar shr-indentation 0)
(defvar shr-inhibit-images nil)
(defvar shr-list-mode nil)
(defvar shr-content-cache nil)
(defvar shr-kinsoku-shorten nil)
(defvar shr-table-depth 0)
(defvar shr-stylesheet nil)

(defvar shr-map
  (let ((map (make-sparse-keymap)))
    (define-key map "a" 'shr-show-alt-text)
    (define-key map "i" 'shr-browse-image)
    (define-key map "I" 'shr-insert-image)
    (define-key map "u" 'shr-copy-url)
    (define-key map "v" 'shr-browse-url)
    (define-key map "o" 'shr-save-contents)
    (define-key map "\r" 'shr-browse-url)
    map))

;; Public functions and commands.

(defun shr-visit-file (file)
  (interactive "fHTML file name: ")
  (pop-to-buffer "*html*")
  (erase-buffer)
  (shr-insert-document
   (with-temp-buffer
     (insert-file-contents file)
     (libxml-parse-html-region (point-min) (point-max)))))

;;;###autoload
(defun shr-insert-document (dom)
  (setq shr-content-cache nil)
  (let ((shr-state nil)
	(shr-start nil)
	(shr-width (or shr-width (window-width))))
    (shr-descend (shr-transform-dom dom))))

(defun shr-copy-url ()
  "Copy the URL under point to the kill ring.
If called twice, then try to fetch the URL and see whether it
redirects somewhere else."
  (interactive)
  (let ((url (get-text-property (point) 'shr-url)))
    (cond
     ((not url)
      (message "No URL under point"))
     ;; Resolve redirected URLs.
     ((equal url (car kill-ring))
      (url-retrieve
       url
       (lambda (a)
	 (when (and (consp a)
		    (eq (car a) :redirect))
	   (with-temp-buffer
	     (insert (cadr a))
	     (goto-char (point-min))
	     ;; Remove common tracking junk from the URL.
	     (when (re-search-forward ".utm_.*" nil t)
	       (replace-match "" t t))
	     (message "Copied %s" (buffer-string))
	     (copy-region-as-kill (point-min) (point-max)))))))
     ;; Copy the URL to the kill ring.
     (t
      (with-temp-buffer
	(insert url)
	(copy-region-as-kill (point-min) (point-max))
	(message "Copied %s" url))))))

(defun shr-show-alt-text ()
  "Show the ALT text of the image under point."
  (interactive)
  (let ((text (get-text-property (point) 'shr-alt)))
    (if (not text)
	(message "No image under point")
      (message "%s" text))))

(defun shr-browse-image ()
  "Browse the image under point."
  (interactive)
  (let ((url (get-text-property (point) 'image-url)))
    (if (not url)
	(message "No image under point")
      (message "Browsing %s..." url)
      (browse-url url))))

(defun shr-insert-image ()
  "Insert the image under point into the buffer."
  (interactive)
  (let ((url (get-text-property (point) 'image-url)))
    (if (not url)
	(message "No image under point")
      (message "Inserting %s..." url)
      (url-retrieve url 'shr-image-fetched
		    (list (current-buffer) (1- (point)) (point-marker))
		    t))))

;;; Utility functions.

(defun shr-transform-dom (dom)
  (let ((result (list (pop dom))))
    (dolist (arg (pop dom))
      (push (cons (intern (concat ":" (symbol-name (car arg))) obarray)
		  (cdr arg))
	    result))
    (dolist (sub dom)
      (if (stringp sub)
	  (push (cons 'text sub) result)
	(push (shr-transform-dom sub) result)))
    (nreverse result)))

(defun shr-descend (dom)
  (let ((function (intern (concat "shr-tag-" (symbol-name (car dom))) obarray))
	(style (cdr (assq :style (cdr dom))))
	(shr-stylesheet shr-stylesheet)
	(start (point)))
    (when style
      (if (string-match "color" style)
	  (setq shr-stylesheet (nconc (shr-parse-style style)
				      shr-stylesheet))
	(setq style nil)))
    (if (fboundp function)
	(funcall function (cdr dom))
      (shr-generic (cdr dom)))
    ;; If style is set, then this node has set the color.
    (when style
      (shr-colorize-region start (point)
			   (cdr (assq 'color shr-stylesheet))
			   (cdr (assq 'background-color shr-stylesheet))))))

(defun shr-generic (cont)
  (dolist (sub cont)
    (cond
     ((eq (car sub) 'text)
      (shr-insert (cdr sub)))
     ((listp (cdr sub))
      (shr-descend sub)))))

(defmacro shr-char-breakable-p (char)
  "Return non-nil if a line can be broken before and after CHAR."
  `(aref fill-find-break-point-function-table ,char))
(defmacro shr-char-nospace-p (char)
  "Return non-nil if no space is required before and after CHAR."
  `(aref fill-nospace-between-words-table ,char))

;; KINSOKU is a Japanese word meaning a rule that should not be violated.
;; In Emacs, it is a term used for characters, e.g. punctuation marks,
;; parentheses, and so on, that should not be placed in the beginning
;; of a line or the end of a line.
(defmacro shr-char-kinsoku-bol-p (char)
  "Return non-nil if a line ought not to begin with CHAR."
  `(aref (char-category-set ,char) ?>))
(defmacro shr-char-kinsoku-eol-p (char)
  "Return non-nil if a line ought not to end with CHAR."
  `(aref (char-category-set ,char) ?<))
(unless (shr-char-kinsoku-bol-p (make-char 'japanese-jisx0208 33 35))
  (load "kinsoku" nil t))

(defun shr-insert (text)
  (when (and (eq shr-state 'image)
	     (not (string-match "\\`[ \t\n]+\\'" text)))
    (insert "\n")
    (setq shr-state nil))
  (cond
   ((eq shr-folding-mode 'none)
    (insert text))
   (t
    (when (and (string-match "\\`[ \t\n]" text)
	       (not (bolp))
	       (not (eq (char-after (1- (point))) ? )))
      (insert " "))
    (dolist (elem (split-string text))
      (when (and (bolp)
		 (> shr-indentation 0))
	(shr-indent))
      ;; No space is needed behind a wide character categorized as
      ;; kinsoku-bol, between characters both categorized as nospace,
      ;; or at the beginning of a line.
      (let (prev)
	(when (and (> (current-column) shr-indentation)
		   (eq (preceding-char) ? )
		   (or (= (line-beginning-position) (1- (point)))
		       (and (shr-char-breakable-p
			     (setq prev (char-after (- (point) 2))))
			    (shr-char-kinsoku-bol-p prev))
		       (and (shr-char-nospace-p prev)
			    (shr-char-nospace-p (aref elem 0)))))
	  (delete-char -1)))
      ;; The shr-start is a special variable that is used to pass
      ;; upwards the first point in the buffer where the text really
      ;; starts.
      (unless shr-start
	(setq shr-start (point)))
      (insert elem)
      (let (found)
	(while (and (> (current-column) shr-width)
		    (progn
		      (setq found (shr-find-fill-point))
		      (not (eolp))))
	  (when (eq (preceding-char) ? )
	    (delete-char -1))
	  (insert "\n")
	  (unless found
	    (put-text-property (1- (point)) (point) 'shr-break t)
	    ;; No space is needed at the beginning of a line.
	    (when (eq (following-char) ? )
	      (delete-char 1)))
	  (when (> shr-indentation 0)
	    (shr-indent))
	  (end-of-line))
	(insert " ")))
    (unless (string-match "[ \t\n]\\'" text)
      (delete-char -1)))))

(defun shr-find-fill-point ()
  (when (> (move-to-column shr-width) shr-width)
    (backward-char 1))
  (let ((bp (point))
	failed)
    (while (not (or (setq failed (= (current-column) shr-indentation))
		    (eq (preceding-char) ? )
		    (eq (following-char) ? )
		    (shr-char-breakable-p (preceding-char))
		    (shr-char-breakable-p (following-char))
		    (if (eq (preceding-char) ?')
			(not (memq (char-after (- (point) 2))
				   (list nil ?\n ? )))
		      (and (shr-char-kinsoku-bol-p (preceding-char))
			   (shr-char-breakable-p (following-char))
			   (not (shr-char-kinsoku-bol-p (following-char)))))
		    (shr-char-kinsoku-eol-p (following-char))))
      (backward-char 1))
    (if (and (not (or failed (eolp)))
	     (eq (preceding-char) ?'))
	(while (not (or (setq failed (eolp))
			(eq (following-char) ? )
			(shr-char-breakable-p (following-char))
			(shr-char-kinsoku-eol-p (following-char))))
	  (forward-char 1)))
    (if failed
	;; There's no breakable point, so we give it up.
	(let (found)
	  (goto-char bp)
	  (unless shr-kinsoku-shorten
	    (while (and (setq found (re-search-forward
				     "\\(\\c>\\)\\| \\|\\c<\\|\\c|"
				     (line-end-position) 'move))
			(eq (preceding-char) ?')))
	    (if (and found (not (match-beginning 1)))
		(goto-char (match-beginning 0)))))
      (or
       (eolp)
       ;; Don't put kinsoku-bol characters at the beginning of a line,
       ;; or kinsoku-eol characters at the end of a line.
       (cond
	(shr-kinsoku-shorten
	 (while (and (not (memq (preceding-char) (list ?\C-@ ?\n ? )))
		     (shr-char-kinsoku-eol-p (preceding-char)))
	   (backward-char 1))
	 (when (setq failed (= (current-column) shr-indentation))
	   ;; There's no breakable point that doesn't violate kinsoku,
	   ;; so we look for the second best position.
	   (while (and (progn
			 (forward-char 1)
			 (<= (current-column) shr-width))
		       (progn
			 (setq bp (point))
			 (shr-char-kinsoku-eol-p (following-char)))))
	   (goto-char bp)))
	((shr-char-kinsoku-eol-p (preceding-char))
	 (if (shr-char-kinsoku-eol-p (following-char))
	     ;; There are consecutive kinsoku-eol characters.
	     (setq failed t)
	   (let ((count 4))
	     (while
		 (progn
		   (backward-char 1)
		   (and (> (setq count (1- count)) 0)
			(not (memq (preceding-char) (list ?\C-@ ?\n ? )))
			(or (shr-char-kinsoku-eol-p (preceding-char))
			    (shr-char-kinsoku-bol-p (following-char)))))))
	   (if (setq failed (= (current-column) shr-indentation))
	       ;; There's no breakable point that doesn't violate kinsoku,
	       ;; so we go to the second best position.
	       (if (looking-at "\\(\\c<+\\)\\c<")
		   (goto-char (match-end 1))
		 (forward-char 1)))))
	(t
	 (if (shr-char-kinsoku-bol-p (preceding-char))
	     ;; There are consecutive kinsoku-bol characters.
	     (setq failed t)
	   (let ((count 4))
	     (while (and (>= (setq count (1- count)) 0)
			 (shr-char-kinsoku-bol-p (following-char))
			 (shr-char-breakable-p (following-char)))
	       (forward-char 1))))))
       (when (eq (following-char) ? )
	 (forward-char 1))))
    (not failed)))

(defun shr-ensure-newline ()
  (unless (zerop (current-column))
    (insert "\n")))

(defun shr-ensure-paragraph ()
  (unless (bobp)
    (if (<= (current-column) shr-indentation)
	(unless (save-excursion
		  (forward-line -1)
		  (looking-at " *$"))
	  (insert "\n"))
      (if (save-excursion
	    (beginning-of-line)
	    (looking-at " *$"))
	  (insert "\n")
	(insert "\n\n")))))

(defun shr-indent ()
  (when (> shr-indentation 0)
    (insert (make-string shr-indentation ? ))))

(defun shr-fontize-cont (cont &rest types)
  (let (shr-start)
    (shr-generic cont)
    (dolist (type types)
      (shr-add-font (or shr-start (point)) (point) type))))

;; Add an overlay in the region, but avoid putting the font properties
;; on blank text at the start of the line, and the newline at the end,
;; to avoid ugliness.
(defun shr-add-font (start end type)
  (save-excursion
    (goto-char start)
    (while (< (point) end)
      (when (bolp)
	(skip-chars-forward " "))
      (let ((overlay (make-overlay (point) (min (line-end-position) end))))
	(overlay-put overlay 'face type))
      (if (< (line-end-position) end)
	  (forward-line 1)
	(goto-char end)))))

(defun shr-browse-url ()
  "Browse the URL under point."
  (interactive)
  (let ((url (get-text-property (point) 'shr-url)))
    (cond
     ((not url)
      (message "No link under point"))
     ((string-match "^mailto:" url)
      (browse-url-mailto url))
     (t
      (browse-url url)))))

(defun shr-save-contents (directory)
  "Save the contents from URL in a file."
  (interactive "DSave contents of URL to directory: ")
  (let ((url (get-text-property (point) 'shr-url)))
    (if (not url)
	(message "No link under point")
      (url-retrieve (shr-encode-url url)
		    'shr-store-contents (list url directory)))))

(defun shr-store-contents (status url directory)
  (unless (plist-get status :error)
    (when (or (search-forward "\n\n" nil t)
	      (search-forward "\r\n\r\n" nil t))
      (write-region (point) (point-max)
		    (expand-file-name (file-name-nondirectory url)
				      directory)))))

(defun shr-image-fetched (status buffer start end)
  (when (and (buffer-name buffer)
	     (not (plist-get status :error)))
    (url-store-in-cache (current-buffer))
    (when (or (search-forward "\n\n" nil t)
	      (search-forward "\r\n\r\n" nil t))
      (let ((data (buffer-substring (point) (point-max))))
        (with-current-buffer buffer
	  (save-excursion
	    (let ((alt (buffer-substring start end))
		  (inhibit-read-only t))
	      (delete-region start end)
	      (goto-char start)
	      (shr-put-image data alt)))))))
  (kill-buffer (current-buffer)))

(defun shr-put-image (data alt)
  (if (display-graphic-p)
      (let ((image (ignore-errors
                     (shr-rescale-image data))))
        (when image
	  ;; When inserting big-ish pictures, put them at the
	  ;; beginning of the line.
	  (when (and (> (current-column) 0)
		     (> (car (image-size image t)) 400))
	    (insert "\n"))
	  (insert-image image (or alt "*"))))
    (insert alt)))

(defun shr-rescale-image (data)
  (if (or (not (fboundp 'imagemagick-types))
	  (not (get-buffer-window (current-buffer))))
      (create-image data nil t)
    (let* ((image (create-image data nil t))
	   (size (image-size image t))
	   (width (car size))
	   (height (cdr size))
	   (edges (window-inside-pixel-edges
		   (get-buffer-window (current-buffer))))
	   (window-width (truncate (* shr-max-image-proportion
				      (- (nth 2 edges) (nth 0 edges)))))
	   (window-height (truncate (* shr-max-image-proportion
				       (- (nth 3 edges) (nth 1 edges)))))
	   scaled-image)
      (when (> height window-height)
	(setq image (or (create-image data 'imagemagick t
				      :height window-height)
			image))
	(setq size (image-size image t)))
      (when (> (car size) window-width)
	(setq image (or
		     (create-image data 'imagemagick t
				   :width window-width)
		     image)))
      (when (and (fboundp 'create-animated-image)
		 (eq (image-type data nil t) 'gif))
	(setq image (create-animated-image data 'gif t)))
      image)))

;; url-cache-extract autoloads url-cache.
(declare-function url-cache-create-filename "url-cache" (url))
(autoload 'mm-disable-multibyte "mm-util")
(autoload 'browse-url-mailto "browse-url")

(defun shr-get-image-data (url)
  "Get image data for URL.
Return a string with image data."
  (with-temp-buffer
    (mm-disable-multibyte)
    (when (ignore-errors
	    (url-cache-extract (url-cache-create-filename (shr-encode-url url)))
	    t)
      (when (or (search-forward "\n\n" nil t)
		(search-forward "\r\n\r\n" nil t))
	(buffer-substring (point) (point-max))))))

(defun shr-image-displayer (content-function)
  "Return a function to display an image.
CONTENT-FUNCTION is a function to retrieve an image for a cid url that
is an argument.  The function to be returned takes three arguments URL,
START, and END.  Note that START and END should be merkers."
  `(lambda (url start end)
     (when url
       (if (string-match "\\`cid:" url)
	   ,(when content-function
	      `(let ((image (funcall ,content-function
				     (substring url (match-end 0)))))
		 (when image
		   (goto-char start)
		   (shr-put-image image
				  (buffer-substring-no-properties start end))
		   (delete-region (point) end))))
	 (url-retrieve url 'shr-image-fetched
		       (list (current-buffer) start end)
		       t)))))

(defun shr-heading (cont &rest types)
  (shr-ensure-paragraph)
  (apply #'shr-fontize-cont cont types)
  (shr-ensure-paragraph))

(autoload 'widget-convert-button "wid-edit")

(defun shr-urlify (start url &optional title)
  (widget-convert-button
   'url-link start (point)
   :help-echo (if title (format "%s (%s)" url title) url)
   :keymap shr-map
   url)
  (put-text-property start (point) 'shr-url url))

(defun shr-encode-url (url)
  "Encode URL."
  (browse-url-url-encode-chars url "[)$ ]"))

(autoload 'shr-color-visible "shr-color")
(autoload 'shr-color->hexadecimal "shr-color")

(defun shr-color-check (fg bg)
  "Check that FG is visible on BG.
Returns (fg bg) with corrected values.
Returns nil if the colors that would be used are the default
ones, in case fg and bg are nil."
  (when (or fg bg)
    (let ((fixed (cond ((null fg) 'fg)
                       ((null bg) 'bg))))
      ;; Convert colors to hexadecimal, or set them to default.
      (let ((fg (or (shr-color->hexadecimal fg)
                    (frame-parameter nil 'foreground-color)))
            (bg (or (shr-color->hexadecimal bg)
                    (frame-parameter nil 'background-color))))
        (cond ((eq fixed 'bg)
               ;; Only return the new fg
               (list nil (cadr (shr-color-visible bg fg t))))
              ((eq fixed 'fg)
               ;; Invert args and results and return only the new bg
               (list (cadr (shr-color-visible fg bg t)) nil))
              (t
               (shr-color-visible bg fg)))))))

(defun shr-colorize-region (start end fg &optional bg)
  (when (or fg bg)
    (let ((new-colors (shr-color-check fg bg)))
      (when new-colors
	(when fg
	  (shr-put-color start end :foreground (cadr new-colors)))
	(when bg
	  (shr-put-color start end :background (car new-colors))))
      new-colors)))

;; Put a color in the region, but avoid putting colors on on blank
;; text at the start of the line, and the newline at the end, to avoid
;; ugliness.  Also, don't overwrite any existing color information,
;; since this can be called recursively, and we want the "inner" color
;; to win.
(defun shr-put-color (start end type color)
  (save-excursion
    (goto-char start)
    (while (< (point) end)
      (when (and (bolp)
		 (not (eq type :background)))
	(skip-chars-forward " "))
      (when (> (line-end-position) (point))
	(shr-put-color-1 (point) (min (line-end-position) end) type color))
      (if (< (line-end-position) end)
	  (forward-line 1)
	(goto-char end)))
    (when (and (eq type :background)
	       (= shr-table-depth 0))
      (shr-expand-newlines start end color))))

(defun shr-expand-newlines (start end color)
  (save-restriction
    ;; Skip past all white space at the start and ends.
    (goto-char start)
    (skip-chars-forward " \t\n")
    (beginning-of-line)
    (setq start (point))
    (goto-char end)
    (skip-chars-backward " \t\n")
    (forward-line 1)
    (setq end (point))
    (narrow-to-region start end)
    (let ((width (shr-natural-width))
	  column)
      (goto-char (point-min))
      (while (not (eobp))
	(end-of-line)
	(when (and (< (setq column (current-column)) width)
		   (< (setq column (shr-previous-newline-padding-width column))
		      width))
	  (let ((overlay (make-overlay (point) (1+ (point)))))
	    (overlay-put overlay 'before-string
			 (concat
			  (mapconcat
			   (lambda (overlay)
			     (let ((string (plist-get
					    (overlay-properties overlay)
					    'before-string)))
			       (if (not string)
				   ""
				 (overlay-put overlay 'before-string "")
				 string)))
			   (overlays-at (point))
			   "")
			  (propertize (make-string (- width column) ? )
				      'face (list :background color))))))
	(forward-line 1)))))

(defun shr-previous-newline-padding-width (width)
  (let ((overlays (overlays-at (point)))
	(previous-width 0))
    (if (null overlays)
	width
      (dolist (overlay overlays)
	(setq previous-width
	      (+ previous-width
		 (length (plist-get (overlay-properties overlay)
				    'before-string)))))
      (+ width previous-width))))

(defun shr-put-color-1 (start end type color)
  (let* ((old-props (get-text-property start 'face))
	 (do-put (not (memq type old-props)))
	 change)
    (while (< start end)
      (setq change (next-single-property-change start 'face nil end))
      (when do-put
	(put-text-property start change 'face
			   (nconc (list type color) old-props)))
      (setq old-props (get-text-property change 'face))
      (setq do-put (not (memq type old-props)))
      (setq start change))
    (when (and do-put
	       (> end start))
      (put-text-property start end 'face
			 (nconc (list type color old-props))))))

;;; Tag-specific rendering rules.

(defun shr-tag-body (cont)
  (let* ((start (point))
	 (fgcolor (cdr (or (assq :fgcolor cont)
                           (assq :text cont))))
	 (bgcolor (cdr (assq :bgcolor cont)))
	 (shr-stylesheet (list (cons 'color fgcolor)
			       (cons 'background-color bgcolor))))
    (shr-generic cont)
    (shr-colorize-region start (point) fgcolor bgcolor)))

(defun shr-tag-style (cont)
  )

(defun shr-tag-script (cont)
  )

(defun shr-tag-label (cont)
  (shr-generic cont)
  (shr-ensure-paragraph))

(defun shr-tag-p (cont)
  (shr-ensure-paragraph)
  (shr-indent)
  (shr-generic cont)
  (shr-ensure-paragraph))

(defun shr-tag-div (cont)
  (shr-ensure-newline)
  (shr-indent)
  (shr-generic cont)
  (shr-ensure-newline))

(defun shr-tag-b (cont)
  (shr-fontize-cont cont 'bold))

(defun shr-tag-i (cont)
  (shr-fontize-cont cont 'italic))

(defun shr-tag-em (cont)
  (shr-fontize-cont cont 'bold))

(defun shr-tag-strong (cont)
  (shr-fontize-cont cont 'bold))

(defun shr-tag-u (cont)
  (shr-fontize-cont cont 'underline))

(defun shr-tag-s (cont)
  (shr-fontize-cont cont 'strike-through))

(defun shr-parse-style (style)
  (when style
    (save-match-data
      (when (string-match "\n" style)
        (setq style (replace-match " " t t style))))
    (let ((plist nil))
      (dolist (elem (split-string style ";"))
	(when elem
	  (setq elem (split-string elem ":"))
	  (when (and (car elem)
		     (cadr elem))
	    (let ((name (replace-regexp-in-string "^ +\\| +$" "" (car elem)))
		  (value (replace-regexp-in-string "^ +\\| +$" "" (cadr elem))))
	      (when (string-match " *!important\\'" value)
		(setq value (substring value 0 (match-beginning 0))))
	      (push (cons (intern name obarray)
			  value)
		    plist)))))
      plist)))

(defun shr-tag-a (cont)
  (let ((url (cdr (assq :href cont)))
        (title (cdr (assq :title cont)))
	(start (point))
	shr-start)
    (shr-generic cont)
    (shr-urlify (or shr-start start) url title)))

(defun shr-tag-object (cont)
  (let ((start (point))
	url)
    (dolist (elem cont)
      (when (eq (car elem) 'embed)
	(setq url (or url (cdr (assq :src (cdr elem))))))
      (when (and (eq (car elem) 'param)
		 (equal (cdr (assq :name (cdr elem))) "movie"))
	(setq url (or url (cdr (assq :value (cdr elem)))))))
    (when url
      (shr-insert " [multimedia] ")
      (shr-urlify start url))
    (shr-generic cont)))

(defun shr-tag-video (cont)
  (let ((image (cdr (assq :poster cont)))
	(url (cdr (assq :src cont)))
	(start (point)))
    (shr-tag-img nil image)
    (shr-urlify start url)))

(defun shr-tag-img (cont &optional url)
  (when (or url
	    (and cont
		 (cdr (assq :src cont))))
    (when (and (> (current-column) 0)
	       (not (eq shr-state 'image)))
      (insert "\n"))
    (let ((alt (cdr (assq :alt cont)))
	  (url (or url (cdr (assq :src cont)))))
      (let ((start (point-marker)))
	(when (zerop (length alt))
	  (setq alt "*"))
	(cond
	 ((or (member (cdr (assq :height cont)) '("0" "1"))
	      (member (cdr (assq :width cont)) '("0" "1")))
	  ;; Ignore zero-sized or single-pixel images.
	  )
	 ((and (not shr-inhibit-images)
	       (string-match "\\`cid:" url))
	  (let ((url (substring url (match-end 0)))
		image)
	    (if (or (not shr-content-function)
		    (not (setq image (funcall shr-content-function url))))
		(insert alt)
	      (shr-put-image image alt))))
	 ((or shr-inhibit-images
	      (and shr-blocked-images
		   (string-match shr-blocked-images url)))
	  (setq shr-start (point))
	  (let ((shr-state 'space))
	    (if (> (string-width alt) 8)
		(shr-insert (truncate-string-to-width alt 8))
	      (shr-insert alt))))
	 ((url-is-cached (shr-encode-url url))
	  (shr-put-image (shr-get-image-data url) alt))
	 (t
	  (insert alt)
	  (ignore-errors
	    (url-retrieve (shr-encode-url url) 'shr-image-fetched
			  (list (current-buffer) start (point-marker))
			  t))))
	(put-text-property start (point) 'keymap shr-map)
	(put-text-property start (point) 'shr-alt alt)
	(put-text-property start (point) 'image-url url)
	(put-text-property start (point) 'image-displayer
			   (shr-image-displayer shr-content-function))
	(put-text-property start (point) 'help-echo alt)
	(setq shr-state 'image)))))

(defun shr-tag-pre (cont)
  (let ((shr-folding-mode 'none))
    (shr-ensure-newline)
    (shr-indent)
    (shr-generic cont)
    (shr-ensure-newline)))

(defun shr-tag-blockquote (cont)
  (shr-ensure-paragraph)
  (shr-indent)
  (let ((shr-indentation (+ shr-indentation 4)))
    (shr-generic cont))
  (shr-ensure-paragraph))

(defun shr-tag-ul (cont)
  (shr-ensure-paragraph)
  (let ((shr-list-mode 'ul))
    (shr-generic cont))
  (shr-ensure-paragraph))

(defun shr-tag-ol (cont)
  (shr-ensure-paragraph)
  (let ((shr-list-mode 1))
    (shr-generic cont))
  (shr-ensure-paragraph))

(defun shr-tag-li (cont)
  (shr-ensure-paragraph)
  (shr-indent)
  (let* ((bullet
	  (if (numberp shr-list-mode)
	      (prog1
		  (format "%d " shr-list-mode)
		(setq shr-list-mode (1+ shr-list-mode)))
	    "* "))
	 (shr-indentation (+ shr-indentation (length bullet))))
    (insert bullet)
    (shr-generic cont)))

(defun shr-tag-br (cont)
  (unless (bobp)
    (insert "\n")
    (shr-indent))
  (shr-generic cont))

(defun shr-tag-h1 (cont)
  (shr-heading cont 'bold 'underline))

(defun shr-tag-h2 (cont)
  (shr-heading cont 'bold))

(defun shr-tag-h3 (cont)
  (shr-heading cont 'italic))

(defun shr-tag-h4 (cont)
  (shr-heading cont))

(defun shr-tag-h5 (cont)
  (shr-heading cont))

(defun shr-tag-h6 (cont)
  (shr-heading cont))

(defun shr-tag-hr (cont)
  (shr-ensure-newline)
  (insert (make-string shr-width shr-hr-line) "\n"))

(defun shr-tag-title (cont)
  (shr-heading cont 'bold 'underline))

(defun shr-tag-font (cont)
  (let* ((start (point))
         (color (cdr (assq :color cont)))
         (shr-stylesheet (nconc (list (cons 'color color))
				shr-stylesheet)))
    (shr-generic cont)
    (when color
      (shr-colorize-region start (point) color
			   (cdr (assq 'background-color shr-stylesheet))))))

;;; Table rendering algorithm.

;; Table rendering is the only complicated thing here.  We do this by
;; first counting how many TDs there are in each TR, and registering
;; how wide they think they should be ("width=45%", etc).  Then we
;; render each TD separately (this is done in temporary buffers, so
;; that we can use all the rendering machinery as if we were in the
;; main buffer).  Now we know how much space each TD really takes, so
;; we then render everything again with the new widths, and finally
;; insert all these boxes into the main buffer.
(defun shr-tag-table-1 (cont)
  (setq cont (or (cdr (assq 'tbody cont))
		 cont))
  (let* ((shr-inhibit-images t)
	 (shr-table-depth (1+ shr-table-depth))
	 (shr-kinsoku-shorten t)
	 ;; Find all suggested widths.
	 (columns (shr-column-specs cont))
	 ;; Compute how many characters wide each TD should be.
	 (suggested-widths (shr-pro-rate-columns columns))
	 ;; Do a "test rendering" to see how big each TD is (this can
	 ;; be smaller (if there's little text) or bigger (if there's
	 ;; unbreakable text).
	 (sketch (shr-make-table cont suggested-widths))
	 (sketch-widths (shr-table-widths sketch suggested-widths)))
    ;; This probably won't work very well.
    (when (> (+ (loop for width across sketch-widths
		      summing (1+ width))
		shr-indentation 1)
	     (frame-width))
      (setq truncate-lines t))
    ;; Then render the table again with these new "hard" widths.
    (shr-insert-table (shr-make-table cont sketch-widths t) sketch-widths))
  ;; Finally, insert all the images after the table.  The Emacs buffer
  ;; model isn't strong enough to allow us to put the images actually
  ;; into the tables.
  (when (zerop shr-table-depth)
    (dolist (elem (shr-find-elements cont 'img))
      (shr-tag-img (cdr elem)))))

(defun shr-tag-table (cont)
  (shr-ensure-paragraph)
  (let* ((caption (cdr (assq 'caption cont)))
	 (header (cdr (assq 'thead cont)))
	 (body (or (cdr (assq 'tbody cont)) cont))
	 (footer (cdr (assq 'tfoot cont)))
         (bgcolor (cdr (assq :bgcolor cont)))
	 (start (point))
	 (shr-stylesheet (nconc (list (cons 'background-color bgcolor))
				shr-stylesheet))
	 (nheader (if header (shr-max-columns header)))
	 (nbody (if body (shr-max-columns body)))
	 (nfooter (if footer (shr-max-columns footer))))
    (shr-tag-table-1
     (nconc
      (if caption `((tr (td ,@caption))))
      (if header
	  (if footer
	      ;; hader + body + footer
	      (if (= nheader nbody)
		  (if (= nbody nfooter)
		      `((tr (td (table (tbody ,@header ,@body ,@footer)))))
		    (nconc `((tr (td (table (tbody ,@header ,@body)))))
			   (if (= nfooter 1)
			       footer
			     `((tr (td (table (tbody ,@footer))))))))
		(nconc `((tr (td (table (tbody ,@header)))))
		       (if (= nbody nfooter)
			   `((tr (td (table (tbody ,@body ,@footer)))))
			 (nconc `((tr (td (table (tbody ,@body)))))
				(if (= nfooter 1)
				    footer
				  `((tr (td (table (tbody ,@footer))))))))))
	    ;; header + body
	    (if (= nheader nbody)
		`((tr (td (table (tbody ,@header ,@body)))))
	      (if (= nheader 1)
		  `(,@header (tr (td (table (tbody ,@body)))))
		`((tr (td (table (tbody ,@header))))
		  (tr (td (table (tbody ,@body))))))))
	(if footer
	    ;; body + footer
	    (if (= nbody nfooter)
		`((tr (td (table (tbody ,@body ,@footer)))))
	      (nconc `((tr (td (table (tbody ,@body)))))
		     (if (= nfooter 1)
			 footer
		       `((tr (td (table (tbody ,@footer))))))))
	  (if caption
	      `((tr (td (table (tbody ,@body)))))
	    body)))))
    (when bgcolor
      (shr-colorize-region start (point) (cdr (assq 'color shr-stylesheet))
			   bgcolor))))

(defun shr-find-elements (cont type)
  (let (result)
    (dolist (elem cont)
      (cond ((eq (car elem) type)
	     (push elem result))
	    ((consp (cdr elem))
	     (setq result (nconc (shr-find-elements (cdr elem) type) result)))))
    (nreverse result)))

(defun shr-insert-table (table widths)
  (shr-insert-table-ruler widths)
  (dolist (row table)
    (let ((start (point))
	  (height (let ((max 0))
		    (dolist (column row)
		      (setq max (max max (cadr column))))
		    max)))
      (dotimes (i height)
	(shr-indent)
	(insert shr-table-vertical-line "\n"))
      (dolist (column row)
	(goto-char start)
	(let ((lines (nth 2 column))
	      (overlay-lines (nth 3 column))
	      overlay overlay-line)
	  (dolist (line lines)
	    (setq overlay-line (pop overlay-lines))
	    (end-of-line)
	    (insert line shr-table-vertical-line)
	    (dolist (overlay overlay-line)
	      (let ((o (make-overlay (- (point) (nth 0 overlay) 1)
				     (- (point) (nth 1 overlay) 1)))
		    (properties (nth 2 overlay)))
		(while properties
		  (overlay-put o (pop properties) (pop properties)))))
	    (forward-line 1))
	  ;; Add blank lines at padding at the bottom of the TD,
	  ;; possibly.
	  (dotimes (i (- height (length lines)))
	    (end-of-line)
	    (let ((start (point)))
	      (insert (make-string (string-width (car lines)) ? )
		      shr-table-vertical-line)
	      (when (nth 4 column)
		(shr-put-color start (1- (point)) :background (nth 4 column))))
	    (forward-line 1)))))
    (shr-insert-table-ruler widths)))

(defun shr-insert-table-ruler (widths)
  (when (and (bolp)
	     (> shr-indentation 0))
    (shr-indent))
  (insert shr-table-corner)
  (dotimes (i (length widths))
    (insert (make-string (aref widths i) shr-table-horizontal-line)
	    shr-table-corner))
  (insert "\n"))

(defun shr-table-widths (table suggested-widths)
  (let* ((length (length suggested-widths))
	 (widths (make-vector length 0))
	 (natural-widths (make-vector length 0)))
    (dolist (row table)
      (let ((i 0))
	(dolist (column row)
	  (aset widths i (max (aref widths i)
			      (car column)))
	  (aset natural-widths i (max (aref natural-widths i)
				      (cadr column)))
	  (setq i (1+ i)))))
    (let ((extra (- (apply '+ (append suggested-widths nil))
		    (apply '+ (append widths nil))))
	  (expanded-columns 0))
      (when (> extra 0)
	(dotimes (i length)
	  ;; If the natural width is wider than the rendered width, we
	  ;; want to allow the column to expand.
	  (when (> (aref natural-widths i) (aref widths i))
	    (setq expanded-columns (1+ expanded-columns))))
	(dotimes (i length)
	  (when (> (aref natural-widths i) (aref widths i))
	    (aset widths i (min
			    (1+ (aref natural-widths i))
			    (+ (/ extra expanded-columns)
			       (aref widths i))))))))
    widths))

(defun shr-make-table (cont widths &optional fill)
  (let ((trs nil))
    (dolist (row cont)
      (when (eq (car row) 'tr)
	(let ((tds nil)
	      (columns (cdr row))
	      (i 0)
	      column)
	  (while (< i (length widths))
	    (setq column (pop columns))
	    (when (or (memq (car column) '(td th))
		      (null column))
	      (push (shr-render-td (cdr column) (aref widths i) fill)
		    tds)
	      (setq i (1+ i))))
	  (push (nreverse tds) trs))))
    (nreverse trs)))

(defun shr-render-td (cont width fill)
  (with-temp-buffer
    (let ((bgcolor (cdr (assq :bgcolor cont)))
	  (fgcolor (cdr (assq :fgcolor cont)))
	  (style (cdr (assq :style cont)))
	  (shr-stylesheet shr-stylesheet)
	  overlays actual-colors)
      (when style
	(setq style (and (string-match "color" style)
			 (shr-parse-style style))))
      (when bgcolor
	(setq style (nconc (list (cons 'background-color bgcolor)) style)))
      (when fgcolor
	(setq style (nconc (list (cons 'color fgcolor)) style)))
      (when style
	(setq shr-stylesheet (append style shr-stylesheet)))
      (let ((cache (cdr (assoc (cons width cont) shr-content-cache))))
	(if cache
	    (progn
	      (insert (car cache))
	      (let ((end (length (car cache))))
		(dolist (overlay (cadr cache))
		  (let ((new-overlay
			 (make-overlay (1+ (- end (nth 0 overlay)))
				       (1+ (- end (nth 1 overlay)))))
			(properties (nth 2 overlay)))
		    (while properties
		      (overlay-put new-overlay
				   (pop properties) (pop properties)))))))
	  (let ((shr-width width)
		(shr-indentation 0))
	    (shr-descend (cons 'td cont)))
	  (delete-region
	   (point)
	   (+ (point)
	      (skip-chars-backward " \t\n")))
	  (push (list (cons width cont) (buffer-string)
		      (shr-overlays-in-region (point-min) (point-max)))
		shr-content-cache)))
      (goto-char (point-min))
      (let ((max 0))
	(while (not (eobp))
	  (end-of-line)
	  (setq max (max max (current-column)))
	  (forward-line 1))
	(when fill
	  (goto-char (point-min))
	  ;; If the buffer is totally empty, then put a single blank
	  ;; line here.
	  (if (zerop (buffer-size))
	      (insert (make-string width ? ))
	    ;; Otherwise, fill the buffer.
	    (while (not (eobp))
	      (end-of-line)
	      (when (> (- width (current-column)) 0)
		(insert (make-string (- width (current-column)) ? )))
	      (forward-line 1)))
	  (when style
	    (setq actual-colors
		  (shr-colorize-region
		   (point-min) (point-max)
		   (cdr (assq 'color shr-stylesheet))
		   (cdr (assq 'background-color shr-stylesheet))))))
	(if fill
	    (list max
		  (count-lines (point-min) (point-max))
		  (split-string (buffer-string) "\n")
		  (shr-collect-overlays)
		  (car actual-colors))
	  (list max
		(shr-natural-width)))))))

(defun shr-natural-width ()
  (goto-char (point-min))
  (let ((current 0)
	(max 0))
    (while (not (eobp))
      (end-of-line)
      (setq current (+ current (current-column)))
      (unless (get-text-property (point) 'shr-break)
	(setq max (max max current)
	      current 0))
      (forward-line 1))
    max))

(defun shr-collect-overlays ()
  (save-excursion
    (goto-char (point-min))
    (let ((overlays nil))
      (while (not (eobp))
	(push (shr-overlays-in-region (point) (line-end-position))
	      overlays)
	(forward-line 1))
      (nreverse overlays))))

(defun shr-overlays-in-region (start end)
  (let (result)
    (dolist (overlay (overlays-in start end))
      (push (list (if (> start (overlay-start overlay))
		      (- end start)
		    (- end (overlay-start overlay)))
		  (if (< end (overlay-end overlay))
		      0
		    (- end (overlay-end overlay)))
		  (overlay-properties overlay))
	    result))
    (nreverse result)))

(defun shr-pro-rate-columns (columns)
  (let ((total-percentage 0)
	(widths (make-vector (length columns) 0)))
    (dotimes (i (length columns))
      (setq total-percentage (+ total-percentage (aref columns i))))
    (setq total-percentage (/ 1.0 total-percentage))
    (dotimes (i (length columns))
      (aset widths i (max (truncate (* (aref columns i)
				       total-percentage
				       (- shr-width (1+ (length columns)))))
			  10)))
    widths))

;; Return a summary of the number and shape of the TDs in the table.
(defun shr-column-specs (cont)
  (let ((columns (make-vector (shr-max-columns cont) 1)))
    (dolist (row cont)
      (when (eq (car row) 'tr)
	(let ((i 0))
	  (dolist (column (cdr row))
	    (when (memq (car column) '(td th))
	      (let ((width (cdr (assq :width (cdr column)))))
		(when (and width
			   (string-match "\\([0-9]+\\)%" width))
		  (aset columns i
			(/ (string-to-number (match-string 1 width))
			   100.0))))
	      (setq i (1+ i)))))))
    columns))

(defun shr-count (cont elem)
  (let ((i 0))
    (dolist (sub cont)
      (when (eq (car sub) elem)
	(setq i (1+ i))))
    i))

(defun shr-max-columns (cont)
  (let ((max 0))
    (dolist (row cont)
      (when (eq (car row) 'tr)
	(setq max (max max (+ (shr-count (cdr row) 'td)
			      (shr-count (cdr row) 'th))))))
    max))

(provide 'shr)

;;; shr.el ends here
