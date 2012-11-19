
(require 'info)
;; Place the flavor-specific info directory ahead of the general one.
(catch 'done
  (let ((cur Info-default-directory-list))
    (while cur
      (when (string= (car cur) "/usr/share/info/")
        (setcdr cur (cons (car cur) (cdr cur)))
        (setcar cur "/usr/share/info/emacs-snapshot/")
        (throw 'done t))
      (setq cur (cdr cur)))))
