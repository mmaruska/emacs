;;; ruby-mode-tests.el --- Test suite for ruby-mode

;; Copyright (C) 2012  Free Software Foundation, Inc.

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

;;; Code:

(require 'ruby-mode)

(defun ruby-should-indent (content column)
  "Assert indentation COLUMN on the last line of CONTENT."
  (with-temp-buffer
    (insert content)
    (ruby-mode)
    (ruby-indent-line)
    (should (= (current-indentation) column))))

(defun ruby-should-indent-buffer (expected content)
  "Assert that CONTENT turns into EXPECTED after the buffer is re-indented.

The whitespace before and including \"|\" on each line is removed."
  (with-temp-buffer
    (insert (ruby-test-string content))
    (ruby-mode)
    (indent-region (point-min) (point-max))
    (should (string= (ruby-test-string expected) (buffer-string)))))

(defun ruby-test-string (s &rest args)
  (apply 'format (replace-regexp-in-string "^[ \t]*|" "" s) args))

(defun ruby-assert-state (content &rest values-plist)
  "Assert syntax state values at the end of CONTENT.

VALUES-PLIST is a list with alternating index and value elements."
  (with-temp-buffer
    (insert content)
    (ruby-mode)
    (syntax-propertize (point))
    (while values-plist
      (should (eq (nth (car values-plist)
                       (parse-partial-sexp (point-min) (point)))
                  (cadr values-plist)))
      (setq values-plist (cddr values-plist)))))

(defun ruby-assert-face (content pos face)
  (with-temp-buffer
    (insert content)
    (ruby-mode)
    (font-lock-fontify-buffer)
    (should (eq face (get-text-property pos 'face)))))

(ert-deftest ruby-indent-after-symbol-made-from-string-interpolation ()
  "It can indent the line after symbol made using string interpolation."
  (ruby-should-indent "def foo(suffix)\n  :\"bar#{suffix}\"\n"
                      ruby-indent-level))

(ert-deftest ruby-indent-after-js-style-symbol-with-block-beg-name ()
  "JS-style hash symbol can have keyword name."
  (ruby-should-indent "link_to \"home\", home_path, class: \"foo\"\n" 0))

(ert-deftest ruby-discern-singleton-class-from-heredoc ()
  (ruby-assert-state "foo <<asd\n" 3 ?\n)
  (ruby-assert-state "class <<asd\n" 3 nil))

(ert-deftest ruby-heredoc-font-lock ()
  (let ((s "foo <<eos.gsub('^ *', '')"))
    (ruby-assert-face s 9 font-lock-string-face)
    (ruby-assert-face s 10 nil)))

(ert-deftest ruby-singleton-class-no-heredoc-font-lock ()
  (ruby-assert-face "class<<a" 8 nil))

(ert-deftest ruby-deep-indent ()
  (let ((ruby-deep-arglist nil)
        (ruby-deep-indent-paren '(?\( ?\{ ?\[ ?\] t)))
    (ruby-should-indent "foo = [1,\n2" 7)
    (ruby-should-indent "foo = {a: b,\nc: d" 7)
    (ruby-should-indent "foo(a,\nb" 4)))

(ert-deftest ruby-deep-indent-disabled ()
  (let ((ruby-deep-arglist nil)
        (ruby-deep-indent-paren nil))
    (ruby-should-indent "foo = [\n1" ruby-indent-level)
    (ruby-should-indent "foo = {\na: b" ruby-indent-level)
    (ruby-should-indent "foo(\na" ruby-indent-level)))

(ert-deftest ruby-indent-after-keyword-in-a-string ()
  (ruby-should-indent "a = \"abc\nif\"\n  " 0)
  (ruby-should-indent "a = %w[abc\n       def]\n  " 0)
  (ruby-should-indent "a = \"abc\n      def\"\n  " 0))

(ert-deftest ruby-indent-simple ()
  (ruby-should-indent-buffer
   "if foo
   |  bar
   |end
   |zot
   |"
   "if foo
   |bar
   |  end
   |    zot
   |"))

(ert-deftest ruby-indent-keyword-label ()
  (ruby-should-indent-buffer
   "bar(class: XXX) do
   |  foo
   |end
   |bar
   |"
   "bar(class: XXX) do
   |     foo
   |  end
   |    bar
   |"))

(ert-deftest ruby-indent-method-with-question-mark ()
  (ruby-should-indent-buffer
   "if x.is_a?(XXX)
   |  foo
   |end
   |"
   "if x.is_a?(XXX)
   | foo
   |   end
   |"))

(ert-deftest ruby-indent-expr-in-regexp ()
  (ruby-should-indent-buffer
   "if /#{foo}/ =~ s
   |  x = 1
   |end
   |"
   "if /#{foo}/ =~ s
   | x = 1
   |  end
   |"))

(ert-deftest ruby-indent-singleton-class ()
  (ruby-should-indent-buffer
   "class<<bar
   |  foo
   |end
   |"
   "class<<bar
   |foo
   |   end
   |"))

(ert-deftest ruby-indent-inside-heredoc-after-operator ()
  (ruby-should-indent-buffer
   "b=<<eos
   |     42"
   "b=<<eos
   |     42"))

(ert-deftest ruby-indent-inside-heredoc-after-space ()
  (ruby-should-indent-buffer
   "foo <<eos.gsub(' ', '*')
   |     42"
   "foo <<eos.gsub(' ', '*')
   |     42"))

(ert-deftest ruby-indent-array-literal ()
  (let ((ruby-deep-indent-paren nil))
    (ruby-should-indent-buffer
     "foo = [
     |  bar
     |]
     |"
     "foo = [
     | bar
     |  ]
     |"))
  (ruby-should-indent-buffer
   "foo do
   |  [bar]
   |end
   |"
   "foo do
   |[bar]
   |  end
   |"))

(ert-deftest ruby-indent-begin-end ()
  (ruby-should-indent-buffer
   "begin
   |  a[b]
   |end
   |"
   "begin
   | a[b]
   |  end
   |"))

(ert-deftest ruby-indent-array-after-paren-and-space ()
  (ruby-should-indent-buffer
   "class A
   |  def foo
   |    foo( [])
   |  end
   |end
   |"
   "class A
   | def foo
   |foo( [])
   |end
   |  end
   |"))

(ert-deftest ruby-move-to-block-stops-at-indentation ()
  (with-temp-buffer
    (insert "def f\nend")
    (beginning-of-line)
    (ruby-mode)
    (ruby-move-to-block -1)
    (should (looking-at "^def"))))

(ert-deftest ruby-toggle-block-to-do-end ()
  (with-temp-buffer
    (insert "foo {|b|\n}")
    (ruby-mode)
    (beginning-of-line)
    (ruby-toggle-block)
    (should (string= "foo do |b|\nend" (buffer-string)))))

(ert-deftest ruby-toggle-block-to-brace ()
  (let ((pairs '((16 . "foo {|b| b + 2 }")
                 (15 . "foo {|b|\n  b + 2\n}"))))
    (dolist (pair pairs)
      (with-temp-buffer
        (let ((fill-column (car pair)))
          (insert "foo do |b|\n  b + 2\nend")
          (ruby-mode)
          (beginning-of-line)
          (ruby-toggle-block)
          (should (string= (cdr pair) (buffer-string))))))))

(ert-deftest ruby-toggle-block-to-multiline ()
  (with-temp-buffer
    (insert "foo {|b| b + 1}")
    (ruby-mode)
    (beginning-of-line)
    (ruby-toggle-block)
    (should (string= "foo do |b|\n  b + 1\nend" (buffer-string)))))

(ert-deftest ruby-recognize-symbols-starting-with-at-character ()
  (ruby-assert-face ":@abc" 3 font-lock-constant-face))

(ert-deftest ruby-hash-character-not-interpolation ()
  (ruby-assert-face "\"This is #{interpolation}\"" 15
                    font-lock-variable-name-face)
  (ruby-assert-face "\"This is \\#{no interpolation} despite the #\""
                    15 font-lock-string-face)
  (ruby-assert-face "\n#@comment, not ruby code" 5 font-lock-comment-face)
  (ruby-assert-state "\n#@comment, not ruby code" 4 t)
  (ruby-assert-face "# A comment cannot have #{an interpolation} in it"
                    30 font-lock-comment-face)
  (ruby-assert-face "# #{comment}\n \"#{interpolation}\"" 16
                    font-lock-variable-name-face))

(ert-deftest ruby-interpolation-suppresses-syntax-inside ()
  (let ((s "\"<ul><li>#{@files.join(\"</li><li>\")}</li></ul>\""))
    (ruby-assert-state s 8 nil)
    (ruby-assert-face s 9 font-lock-string-face)
    (ruby-assert-face s 10 font-lock-variable-name-face)
    (ruby-assert-face s 41 font-lock-string-face)))

(ert-deftest ruby-interpolation-inside-percent-literal-with-paren ()
  :expected-result :failed
  (let ((s "%(^#{\")\"}^)"))
    (ruby-assert-face s 3 font-lock-string-face)
    (ruby-assert-face s 4 font-lock-variable-name-face)
    (ruby-assert-face s 10 font-lock-string-face)
    ;; It's confused by the closing paren in the middle.
    (ruby-assert-state s 8 nil)))

(ert-deftest ruby-add-log-current-method-examples ()
  (let ((pairs '(("foo" . "#foo")
                 ("C.foo" . ".foo")
                 ("self.foo" . ".foo"))))
    (loop for (name . value) in pairs
          do (with-temp-buffer
               (insert (ruby-test-string
                        "module M
                        |  class C
                        |    def %s
                        |    end
                        |  end
                        |end"
                        name))
               (ruby-mode)
               (search-backward "def")
               (forward-line)
               (should (string= (ruby-add-log-current-method)
                                (format "M::C%s" value)))))))

(defvar ruby-block-test-example
  (ruby-test-string
   "class C
   |  def foo
   |    1
   |  end
   |
   |  def bar
   |    2
   |  end
   |
   |  def baz
   |    some do
   |    end
   |  end
   |end"))

(defmacro ruby-deftest-move-to-block (name &rest body)
  `(ert-deftest ,(intern (format "ruby-move-to-block-%s" name)) ()
     (with-temp-buffer
       (insert ruby-block-test-example)
       (ruby-mode)
       ,@body)))

(put 'ruby-deftest-move-to-block 'lisp-indent-function 'defun)

(ruby-deftest-move-to-block works-on-do
  (goto-line 11)
  (ruby-end-of-block)
  (should (= 12 (line-number-at-pos)))
  (ruby-beginning-of-block)
  (should (= 11 (line-number-at-pos))))

(ruby-deftest-move-to-block zero-is-noop
  (goto-line 5)
  (ruby-move-to-block 0)
  (should (= 5 (line-number-at-pos))))

(ruby-deftest-move-to-block ok-with-three
  (goto-line 2)
  (ruby-move-to-block 3)
  (should (= 13 (line-number-at-pos))))

(ruby-deftest-move-to-block ok-with-minus-two
  (goto-line 10)
  (ruby-move-to-block -2)
  (should (= 2 (line-number-at-pos))))

(provide 'ruby-mode-tests)

;;; ruby-mode-tests.el ends here
