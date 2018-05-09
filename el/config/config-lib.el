;;; config-lib.el --- Library for configurations

;;; Commentary:

;; Usage:
;; (require 'config-lib)

;;; Code:

(require 'cl-lib)
;; [ get current function name
;; thanks to: https://emacs.stackexchange.com/a/2312
(defun call-stack ()
  "Return the current call stack frames."
  (let ((frames)
        (frame)
        (index 5))
    (while (setq frame (backtrace-frame index))
      (push frame frames)
      (cl-incf index))
    (cl-remove-if-not 'car frames)))

(defmacro compile-time-function-name ()
  "Get the name of calling function at expansion time."
  (symbol-name
   (cl-cadadr
    (cl-caddr
     (cl-find-if (lambda (frame)
                (ignore-errors (equal (car (cl-caddr frame)) 'defalias)))
              (reverse (call-stack)))))))
;; ]

;; Converts calls to COMPOSE to lambda forms with everything written
;; out and some things written as direct function calls.
;; Example: (compose #'1+ #'2* #'-) => (LAMBDA (X) (1+ (2* (- X))))
(cl-define-compiler-macro compose (&rest functions)
  (cl-labels ((sharp-quoted-p (x)
                           (and (listp x)
                                (eql (cl-first x) 'function)
                                (symbolp (cl-second x)))))
    `(lambda (x) ,(cl-reduce #'(lambda (fun arg)
                         (if (sharp-quoted-p fun)
                             (list (cl-second fun) arg)
                           (list 'funcall fun arg)))
                     functions
                     :initial-value 'x
                     :from-end t))))

;; Eval checking bound before
(defmacro bound-and-eval (func &rest args)
  "Ensures FUNC exist and eval with ARGS."
  (list 'and (list 'fboundp func) (list 'apply func (list 'quote args))))

;; write message in *Messages* buffer with colors
;; Thanks to: https://emacs.stackexchange.com/a/20178
(defun message-color (format &rest args)
  "Acts like `message' but preserves string properties in the *Messages* buffer."
  (let ((message-log-max nil))
    (apply 'message format args))
  (with-current-buffer (get-buffer "*Messages*")
    (save-excursion
      (goto-char (point-max))
      (let ((inhibit-read-only t))
        (unless (zerop (current-column)) (insert "\n"))
        (insert (apply 'format format args))
        (insert "\n")))))

;; Silent messages
;; Usage:
;; (advice-add '<orig-fun> :around #'message-silent-advice)
(defun message-silent-advice (orig-fun &rest args)
  "Silent and eval ORIG-FUN with ARGS."
  (let ((message-log-max nil)
        (inhibit-message t))
    (apply orig-fun args)))

;; Truncate messages
;; Usage:
;; (advice-add '<orig-fun> :around #'message-truncate-advice)
(defun message-truncate-advice (orig-fun &rest args)
  "Stablish `message-truncate-lines' and eval ORIG-FUN with ARGS."
  (let ((message-truncate-lines t))
    (apply orig-fun args)))

(require 'server)
(defmacro eval-and-when-daemon (frame &rest body)
  "When starting daemon wait FRAME ready before BODY."
  (declare (indent defun))
  (cons 'if
        (cons
         (list 'daemonp)
         (append
          (list (list 'add-hook (quote 'after-make-frame-functions)
                      (cons 'lambda (cons (list (if frame frame 'frame)) body))))
          (list (list 'funcall
                      (cons 'lambda (cons (list (if frame frame 'frame)) body))
                      (list 'selected-frame)))))))

;; Establish safe dir-locals variables
(defun safe-dir-locals (dir list &optional class)
  "Set local variables for directory.
DIR directory.
LIST list of local variables.
CLASS optional class name, DIR default."
  (unless class
    (setq class dir))
  (dir-locals-set-class-variables class list)
  (dir-locals-set-directory-class dir class)
  (dolist (item list)
    (setq safe-local-variable-values (append safe-local-variable-values (cdr item))))
  class)


;; regex inside each file in list
;; return first occurence
(defun re-search-in-files (regex files &optional first)
  "Search REGEX match inside the files of FILES list.
If FIRST is not-nil return first file in files with regex match.
Otherwise return a list of files which regex match."
  (let ((matched '()))
    (while (and
            files
            (not (and first matched)))
      (let* ((file (pop files))
             (buffer (get-file-buffer file)))
        (if buffer
            (with-current-buffer buffer
              (save-excursion
                (goto-char (point-min))
                (when (re-search-forward regex nil t)
                  (push file matched))))
          (let ((buffer (find-file-noselect file t t)))
            (with-current-buffer buffer
              (when (re-search-forward regex nil t)
                (push file matched)))
            (kill-buffer buffer)))))
    (if first
        (car matched)
      matched)))


(defun bug-check-function-bytecode (function bytecode-base64 &optional inhibit-log)
  "Check if FUNCTION has BYTECODE-BASE64.  If INHIBIT-LOG is non-nil inhibit log when differs."
  (if (string-equal
       (condition-case nil
           (base64-encode-string (aref (symbol-function function) 1) t)
         (error
          (user-error "Missing function bytecode, maybe %s is a built-in function in 'C source code' or not bytecompiled" function)))
       bytecode-base64)
      t
    (unless inhibit-log
      (message-color #("WARN bug fixed for different version of %s see %s"
                       0 4 (face warning))
                     (find-function-library function)
                     load-file-name))
    nil))


(require 'help-fns)
(defun bug-function-bytecode-into-base64 (function)
  "Write the bytecode of FUNCTION (a symbol).
When called from lisp, FUNCTION may also be a function object."
  (interactive
   (let* ((fn (function-called-at-point))
          (enable-recursive-minibuffers t)
          (val (completing-read
                (if fn
                    (format "Bytecode of function (default %s): " fn)
                  "Bytecode of function: ")
                #'help--symbol-completion-table
                (lambda (f) (fboundp f))
                t nil nil
                (and fn (symbol-name fn)))))
     (unless (equal val "")
       (setq fn (intern val)))
     (unless (and fn (symbolp fn))
       (user-error "You didn't specify a function symbol"))
     (unless (fboundp fn) 
       (user-error "Symbol's function definition is void: %s" fn))
     (list fn)))
  (insert "\""
          (condition-case nil
              (base64-encode-string (aref (symbol-function function) 1) t)
            (error
             (user-error "Missing function bytecode, maybe %s is a built-in function in 'C source code' or not bytecompiled" function)))
          "\""))

;; escape special characters
;; (let ((print-escape-newlines t))
;;   (prin1-to-string "..."))



(provide 'config-lib)
;;; config-lib.el ends here
