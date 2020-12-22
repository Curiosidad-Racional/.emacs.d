(require 'cl-lib)
;; [ Package cl is deprecated
;; (eval-when-compile
;;   (require 'cl))
;; ]

;;;;;;;;;;;;;;;;
;; My library ;;
;;;;;;;;;;;;;;;;
(defun remove-nth-element (nth list)
  "Efficient remove NTH element in LIST."
  (if (zerop nth) (cdr list)
    (let ((last (nthcdr (1- nth) list)))
      (setcdr last (cddr last))
      list)))

(defun assoc-keys (keys alist &optional test-fun)
  "Recursively find KEYS in ALIST using TEST-FUN."
  (if keys
      (cond
       ((listp alist)
        (assoc-keys (cdr keys) (cdr (assoc (car keys) alist test-fun)) test-fun))
       ((vectorp alist)
        (mapcar (lambda (al)
                  (assoc-keys (cdr keys) (cdr (assoc (car keys) al test-fun)) test-fun)) alist)))
    alist))

(defun eval-string (string)
  "Evaluate elisp code stored in a string."
  (eval (car (read-from-string string))))

;; keymaps
(defun keymap-symbol (keymap)
  "Return the symbol to which KEYMAP is bound, or nil if no such symbol exists."
  (catch 'gotit
    (mapatoms (lambda (sym)
                (and (boundp sym)
                     (eq (symbol-value sym) keymap)
                     (not (eq sym 'keymap))
                     (throw 'gotit sym)))
              obarray)))

(defun keymaps-with-binding (key)
  (let (keymaps)
    (mapatoms (lambda (ob) (if (boundp ob)
                          (let ((keymap (symbol-value ob)))
                            (if (keymapp keymap)
                                (let ((m (lookup-key keymap key)))
                                  (if (and m (or (symbolp m) (keymapp m)))
                                      (push keymap keymaps)))))))
              obarray)
    keymaps))

(defun locate-key-binding (key)
  "Determine keymaps KEY is defined"
  (interactive "kPress key: ")
  (let ((key-str (key-description key)))
    (mapatoms (lambda (ob) (when (and (boundp ob) (keymapp (symbol-value ob)))
                        (let ((m (lookup-key (symbol-value ob) key)))
                          (when m
                            (message "key: %s, keymap: %S, bind: %s" key-str ob m)))))
              obarray)))

;; Recursive byte compile
(defun byte-compile-force-recompile-recursively (directory)
  "Force recompile '.el' when '.elc' file exists and compile when
does not exist.  Files in subdirectories of DIRECTORY are processed also."
  (interactive "DByte compile and force recompile recursively directory: ")
  (byte-recompile-directory directory 0 t))

(defun byte-compile-emacs-config (&optional force)
  "Recompile '.el' when '.elc' is out of date or does not exist.
'init.el' file and 'el/' folder are processed recursively."
  (interactive)
  (let ((emacs-el-directory (expand-file-name "el/" user-emacs-directory)))
    (save-some-buffers
     nil (lambda ()
          (let ((file (buffer-file-name)))
            (and file
                 (string-match-p emacs-lisp-file-regexp file)
                 (file-in-directory-p file emacs-el-directory)))))
    (force-mode-line-update)
    (with-current-buffer (get-buffer-create byte-compile-log-buffer)
      (setq default-directory (expand-file-name user-emacs-directory))
      ;; compilation-mode copies value of default-directory.
      (unless (derived-mode-p 'compilation-mode)
        (emacs-lisp-compilation-mode))
      (let ((default-directory emacs-el-directory))
        (let ((directories (list default-directory))
              (skip-count 0)
              (fail-count 0)
              (file-count 0)
              (dir-count 0)
              directory
              last-dir)
          (displaying-byte-compile-warnings
           (dolist (file '(user-init-file early-init-file
                           package-quickstart-file custom-file))
             (when (and (boundp file)
                        (setq file (symbol-value file))
                        (file-exists-p file))
               (cl-incf
                (pcase (byte-recompile-file
                        file force 0)
                  ('no-byte-compile skip-count)
                  ('t file-count)
                  (_
                   (message "Failed %s" file)
                   fail-count)))))
           (while directories
             (setq directory (car directories))
             ;; (message "Checking %s..." directory)
             (dolist (file (directory-files directory))
               (let ((source (expand-file-name file directory)))
                 (if (file-directory-p source)
                     (and (not (member file '("RCS" "CVS")))
                          (not (eq ?\. (aref file 0)))
                          (not (file-symlink-p source))
                          ;; This file is a subdirectory.  Handle them differently.
                          (setcdr (last directories) (list source)))
                   ;; It is an ordinary file.  Decide whether to compile it.
                   (if (and (string-match emacs-lisp-file-regexp source)
                            ;; The next 2 tests avoid compiling lock files
                            (file-readable-p source)
                            (not (string-match "\\`\\.#" file))
                            (not (auto-save-file-name-p source))
                            (not (string-equal dir-locals-file
                                               (file-name-nondirectory source))))
                       (progn (cl-incf
                               (pcase (byte-recompile-file source force 0)
                                 ('no-byte-compile skip-count)
                                 ('t file-count)
                                 (_
                                  (message "Failed %s" source)
                                  fail-count)))
                              (if (not (eq last-dir directory))
                                  (setq last-dir directory
                                        dir-count (1+ dir-count))))))))
             (setq directories (cdr directories))))
          (message "Done (Total of %d file%s compiled%s%s%s)"
                   file-count (if (= file-count 1) "" "s")
                   (if (> fail-count 0) (format ", %d failed" fail-count) "")
                   (if (> skip-count 0) (format ", %d skipped" skip-count) "")
                   (if (> dir-count 1)
                       (format " in %d directories" dir-count) "")))))))

;; [ counting visual lines
(defun count-visual-lines-in-line (line max-cols)
  (let ((line-len (length line))
        pos
        (visual-lines 1))
    (while (< max-cols line-len)
      (cl-incf visual-lines)
      (setq pos (1+ (or (cl-position
                         ?  line :end max-cols :from-end t)
                        max-cols))
            line (substring line pos)
            line-len (- line-len pos)))
    visual-lines))

(defun count-visual-lines-in-string (string max-cols)
  (apply '+ (mapcar (lambda (line)
                      (count-visual-lines-in-line line max-cols))
                    (split-string string "\n"))))
;; ]

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
    (cl-delete-if-not 'car frames)))

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

;; Return function that check bound before
(defmacro lambda-bound-and-eval (func &rest args)
  "Return lambda that ensures FUNC exist and eval with ARGS."
  `(lambda () (and (fboundp ,func) (apply ,func (quote ,args)))))

;; write message in *Messages* buffer with colors
(defun message-log (format-string &rest args)
  (with-current-buffer "*Messages*"
    (save-excursion
      (goto-char (point-max))
      (let ((inhibit-read-only t))
        (unless (zerop (current-column)) (insert "\n"))
        (insert (apply 'format format-string args))
        (insert "\n")))))

(defun message-color (format-string &rest args)
  "Acts like `message' but preserves string properties in the *Messages* buffer."
  (let ((message-log-max nil))
    (apply 'message format-string args))
  (apply 'message-log format-string args))

;; Silent messages
;; Usage:
;; (advice-add '<orig-fun> :around #'message-silent-advice)
(defun message-silent-advice (orig-fun &rest args)
  "Silent and eval ORIG-FUN with ARGS."
  (let ((message-log-max nil)
        (inhibit-message t))
    (apply orig-fun args)))

;; Inhibit messages on echo
;; Usage:
;; (advice-add '<orig-fun> :around #'message-inhibit-advice)
(defun message-inhibit-advice (orig-fun &rest args)
  "Inhibit message and eval ORIG-FUN with ARGS."
  (let ((inhibit-message t))
    (apply orig-fun args)))

;; Truncate messages
;; Usage:
;; (advice-add '<orig-fun> :around #'message-truncate-advice)
(defun message-truncate-advice (orig-fun &rest args)
  "Stablish `message-truncate-lines' and eval ORIG-FUN with ARGS."
  (let ((message-truncate-lines t))
    (apply orig-fun args)))

(defmacro eval-and-when-daemon (frame &rest body)
  "When starting daemon wait FRAME ready before BODY."
  (declare (indent defun))
  (cons 'if
        (cons
         (list 'daemonp)
         (nconc
          (list (list 'add-hook (quote 'after-make-frame-functions)
                      (cons 'lambda (cons (list (if frame frame 'frame)) body))))
          (list (list 'funcall
                      (cons 'lambda (cons (list (if frame frame 'frame)) body))
                      (list 'selected-frame)))))))

;; Load all libraries in directory
(defun load-all-in-directory (dir)
  "`load' all elisp libraries in directory DIR which are not already loaded."
  (interactive "D")
  (let ((libraries-loaded (mapcar #'file-name-sans-extension
                                  (delq nil (mapcar #'car load-history)))))
    (dolist (file (directory-files dir t ".+\\.elc?$"))
      (let ((library (file-name-sans-extension file)))
        (unless (member library libraries-loaded)
          (load library nil t)
          (push library libraries-loaded))))))

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
    (setq safe-local-variable-values (nconc safe-local-variable-values (cdr item))))
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

(defun comint-truncate-buffers (regexp &optional verbose)
  (dolist (buffer (buffer-list))
    (let ((name (buffer-name buffer)))
      (when (and name (not (string-equal name ""))
                 (string-match-p regexp name))
        (with-current-buffer buffer
          (save-excursion
            (goto-char (point-max))
            (forward-line (- comint-buffer-maximum-size))
            (beginning-of-line)
            (let ((lines (1- (line-number-at-pos))))
              (when (< 0 lines)
                (when verbose
                  (message "Truncating %s lines in buffer `%s'"
                           lines name))
                (let ((inhibit-read-only t))
                  (delete-region (point-min) (point)))))))))))

;;;;;;;;;;
;; Bugs ;;
;;;;;;;;;;
(defun bug-check-function-bytecode (function bytecode-base64 &optional inhibit-log)
  "Check if FUNCTION has BYTECODE-BASE64.  If INHIBIT-LOG is non-nil inhibit log when differs."
  (let ((current-bytecode-base64
         (condition-case nil
             (base64-encode-string (aref (symbol-function function) 1) t)
           (error
            (unless inhibit-log
              (message-color #("WARN missing function bytecode, maybe %s is a built-in function in 'C source code' or not bytecompiled"
                               0 4 (face warning)) function))))))
    (if (string-equal
         current-bytecode-base64
         bytecode-base64)
        t
      (unless inhibit-log
        (message-color #("WARN bug fixed for different version of %s with b64 %s see %s"
                         0 4 (face warning))
                       (if (fboundp 'find-function-library)
                           (find-function-library function)
                         (symbol-name function))
                       current-bytecode-base64
                       load-file-name))
      nil)))


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

;;;;;;;;;;;;
;; Errors ;;
;;;;;;;;;;;;
;; Protect from errors
(defun rollback-on-error-inc ()
  "Increment `rollback-on-error-counter' fake variable."
  (cl-incf rollback-on-error-counter))
(defun rollback-on-error-advice (orig-fun &rest args)
  "Rollback (ORIG-FUN ARGS) evaluation on error.

Example: (advice-add 'mt-interchange-thing-up :around #'rollback-on-error-advice)"
  ;; (undo-boundary)  ; <undo>
  (advice-add 'undo-boundary :before #'rollback-on-error-inc)
  (unwind-protect
      (let ((rollback-on-error-counter 1))
        (condition-case-unless-debug raised-error
            (apply orig-fun args)
          (error (primitive-undo rollback-on-error-counter
                                 buffer-undo-list)
                 (error "%s: %s rolled back (%i)"
                        orig-fun
                        (error-message-string raised-error)
                        rollback-on-error-counter))))
    (advice-remove 'undo-boundary #'rollback-on-error-inc)))


;;;;;;;;;;;;;;;
;; Processes ;;
;;;;;;;;;;;;;;;
(defun process-get-attrs (pid attrs-process)
  (let ((process-attrs (process-attributes pid)))
    (cons `(pid . ,pid) (mapcar (lambda (attr)
                                  (assoc attr process-attrs))
                                attrs-process))))

(defun processes-named (names attrs-processes)
  (cl-remove-if-not (lambda (attrs-process)
                      (member (cdr (assoc 'comm attrs-process)) names))
                    attrs-processes))

(defun processes-children (pid attrs-processes)
  (cl-remove-if-not (lambda (attrs-process)
                      (let ((ppid (cdr (assoc 'ppid attrs-process))))
                        (and (integerp ppid) (= pid ppid))))
                    attrs-processes))

(defun processes-children-all (pid attrs-processes)
  (let ((pids (list pid))
        children processes)
    (while pids
      (setq children nil)
      (mapc (lambda (pid) (setq children (nconc children (processes-children pid attrs-processes)))) pids)
      (setq processes (nconc processes children))
      (setq pids (mapcar (lambda (attrs-process) (cdr (assoc 'pid attrs-process))) children)))
    processes))

(defmacro processes-run-with-timer-cond-body (secs repeat process-names
                                                 processes-number-variable
                                                 processes-number-condition
                                                 &rest body)
  (declare (indent 5))
  `(run-with-timer
    ,secs ,repeat
    (lambda ()
      ;; [ Limit python's processes of all emacs
      ;; (let ((attrs-processes (mapcar (lambda (x) (process-get-attrs x '(ppid comm))) (list-system-processes)))
      ;;       (emacs-processes))
      ;;   (mapc (lambda (x) (nconc emacs-processes (processes-children-all (cdr (assoc 'pid x)) attrs-processes))) (processes-named "emacs.exe" attrs-processes))
      ;;   (processes-named "python.exe" emacs-processes))
      ;; ]
      ;; Limit python's processes of every emacs
      (let ((,processes-number-variable
             (length (processes-named
                      ,process-names
                      (processes-children-all
                       (emacs-pid)
                       (mapcar (lambda (x) (process-get-attrs x '(ppid comm)))
                               (list-system-processes)))))))
        (when
            ,processes-number-condition
          ,@body)))))

(defun random-goto-line ()
  (interactive)
  (goto-char (point-min))
  (forward-line (random (count-lines (point-min) (point-max)))))

(defun random-goto-char ()
  (interactive)
  (goto-char (random (- (point-max) (point-min)))))

;;;;;;;;;;;;;;;
;; Clipboard ;;
;;;;;;;;;;;;;;;
(defun copy-buffer-file-name ()
  (interactive)
  (kill-new (abbreviate-file-name buffer-file-name)))

(defun copy-buffer-file-name-nondirectory ()
  (interactive)
  (kill-new (file-name-nondirectory buffer-file-name)))

(defun copy-buffer-file-name-directory ()
  (interactive)
  (kill-new (file-name-directory buffer-file-name)))

;;;;;;;;;;;;;;;;;;;;;;;;
;; Backup & Auto save ;;
;;;;;;;;;;;;;;;;;;;;;;;;
;; create the autosave dir if necessary, since emacs won't.
;; with backup directory is not necessary
(let ((backup-directory (expand-file-name "~/.emacs.d/backup/")))
  (make-directory backup-directory t)

  (setq undo-limit (eval-when-compile
                     (* 1024 1024))
        backup-directory-alist
        `((".*" . ,backup-directory))
        ;; auto-save-file-name-transforms
        ;; '((".*" "~/.emacs.d/backup/" t))
        ;; 10 input events #<file-name>#
        auto-save-interval 10
        ;; 10 seconds
        auto-save-timeout 10
        ;; create local .#<file-name> to avoid collisions
        create-lockfiles nil))

;;;;;;;;;;
;; Math ;;
;;;;;;;;;;
(defun round-on-region (start end arg)
  "Rounds the numbers of the region."
  (interactive "r\nP")
  (save-restriction
    (narrow-to-region start end)
    (goto-char 1)
    (let ((case-fold-search nil))
      (while (search-forward-regexp "\\([0-9]+\\.[0-9]+\\)" nil t)
        (replace-match
         (format
          (concat "%0." (if arg (number-to-string arg) "0") "f")
          (string-to-number (match-string 1))) t t)))))

;;;;;;;;;;;;;;;;
;; Mode utils ;;
;;;;;;;;;;;;;;;;
(defun reload-current-major-mode ()
  "Reloads the current major mode."
  (interactive)
  (let ((mode major-mode))
    (message "%s is going to be unloaded" mode)
    (unload-feature mode t)
    (message "%s unloaded" mode)
    (funcall-interactively mode)
    (message "%s loaded" mode)))

;; [ custom
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(load custom-file)
;; ]

(load (expand-file-name "config.el" user-emacs-directory) t)

;; utf8 symbols for modes
;; - abbrev-mode      "ⓐ"
;; - company-mode     "Ⓒ"
;; - flyspell-mode    "ⓕ"
;; - helm-mode        "Ⓗ"
;; - helm-cscope-mode "ⓢ"
;; - helm-gtags-mode  "ⓣ"
;; - yas-minor-mode   "ⓨ"
;; - undo-tree-mode   "ⓤ"

;; Remove minor mode from minor-mode-alist
;; (setq minor-mode-alist
;;       (cl-delete '<minor-mode> minor-mode-alist :key 'car))
;; or
;; (setq minor-mode-alist
;;       (assq-delete-all '<minor-mode> minor-mode-alist))

;; (require 'mini-modeline)                                       ;; + with mini-modeline
;; (setcar (cdr (assq 'mini-modeline-mode minor-mode-alist)) nil)  ;; + with mini-modeline

;;;;;;;;;;;
;; Faces ;;
;;;;;;;;;;;
(defface mode-line-correct
  '((t :foreground "green4"))
  "Correct" :group 'mode-line)
(defface mode-line-notready
  '((t :foreground "brown4"))
  "Correct" :group 'mode-line)
(defface mode-line-warning
  '((t :foreground "yellow4"))
  "Warning" :group 'mode-line)
(defface mode-line-error
  '((t :foreground "red4"))
  "Error" :group 'mode-line)

(defface mode-line-outside-modified
  '((t :foreground "#ffffff" :background "#c82829"))
  "Outside modified" :group 'mode-line)

(defface mode-line-modified
  '((t :foreground "Red" :weight bold))
  "Modified" :group 'mode-line)

(defface mode-line-read-only
  '((t :foreground "Yellow"))
  "Read only" :group 'mode-line)

(defface mode-line-not-modified
  '((t :foreground "Green"))
  "Not modified" :group 'mode-line)

(defface mode-line-coding-system
  '((t :foreground "SaddleBrown"))
  "Coding system" :group 'mode-line)

(defface mode-line-eol
  '((t  :foreground "DarkOliveGreen"))
  "End of line" :group 'mode-line)

(defface mode-line-percentage
  '((t :foreground "DodgerBlue"))
  "Percentage" :group 'mode-line)

(defface mode-line-battery
  '((t :foreground "DodgerBlue3"))
  "Column number" :group 'mode-line)

(defface mode-line-major-mode
  '((t :foreground "DarkBlue" :weight ultra-bold))
  "Major mode" :group 'mode-line)

(defface mode-line-project-name
  '((t :foreground "SaddleBrown" :weight bold))
  "Project name" :group 'mode-line)

(defface mode-line-abbrev-mode
  '((t :foreground "light slate blue" :weight bold))
  "Project name" :group 'mode-line)

(with-eval-after-load 'abbrev
  (setcar (cdr (assq 'abbrev-mode minor-mode-alist))
          (propertize "A" 'face 'mode-line-abbrev-mode)))
(with-eval-after-load 'compile
  (setcar (cdr (assq 'compilation-shell-minor-mode minor-mode-alist)) "Cs")
  (setcar (cdr (assq 'compilation-minor-mode minor-mode-alist)) "Cp"))
(with-eval-after-load 'autorevert
  (setq auto-revert-mode-text "Ar"))

;;;;;;;;;;;;;;;;;;;;;;
;; Sort minor modes ;;
;;;;;;;;;;;;;;;;;;;;;;
(defun mode-line-sort-minors ()
  (interactive)
  (dolist (minor '(abbrev-mode yas-minor-mode company-mode caps-lock-show-mode))
    (let ((pos (cl-position-if (lambda (x) (eq minor (car x))) minor-mode-alist)))
      (when pos
       (setcdr (last minor-mode-alist) (list (elt minor-mode-alist pos)))
       (setq minor-mode-alist
             (remove-nth-element pos minor-mode-alist))))))
(dolist (package '("abbrev" "yasnippet" "company"))
  (with-eval-after-load package
    (mode-line-sort-minors)))

;;;;;;;;;;;;;;;;;;;;;;;
;; Battery mode line ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; (require 'battery)
;; (bug-check-function-bytecode
;;  'battery-update
;;  "CIUGAAggGcbHCZ5BIUAayAuDJgAKp4MmAAoMWIMmAMkLCSKCJwDKywqnhTQACg1YhTQAzM3OJRYQKs8ghw==")
;; (eval-and-when-daemon frame
;;   (display-battery-mode)
;;   (setq battery-mode-line-format "%p%L")
;;   (defun battery-update ()
;;     "Update battery status information in the mode line."
;;     (let ((data (and battery-status-function (funcall battery-status-function))))
;;       (let ((percentage (car (read-from-string (cdr (assq ?p data)))))
;;             (supplier (cdr (assq ?L data)))
;;             percentage-str
;;             percentage-face)
;;         (if (numberp percentage)
;;             (setq percentage-str (int-to-string (truncate percentage))
;;                   percentage-face (if (<= percentage battery-load-critical)
;;                                       '(:foreground "red")
;;                                     `(:foreground ,(format "#%02i%02i00"
;;                                                            (- 100 percentage)
;;                                                            (- percentage 1)))))
;;           (setq percentage-str percentage
;;                 percentage-face '(:foreground "yellow")))
;;         (setq battery-mode-line-string
;;               (propertize (concat
;;                            percentage-str
;;                            (cond ((string-equal supplier "AC")
;;                                   (if (display-graphic-p) "🔌" ":"))
;;                                  ((string-equal supplier "BAT")
;;                                   (if (display-graphic-p) "🔋" "!"))
;;                                  ((string-equal supplier "N/A")
;;                                   "?")
;;                                  (t supplier)))
;;                           'font-lock-face
;;                           percentage-face
;;                           'help-echo "Battery status information"))))
;;     (force-mode-line-update)))

;;;;;;;;;;;;;;;;;;;;;;
;; Define mode line ;;
;;;;;;;;;;;;;;;;;;;;;;
(setq eol-mnemonic-unix "LF"
      eol-mnemonic-dos "CRLF"
      eol-mnemonic-mac "CR")

(defvar-local mode-line-cached nil)
(defvar-local mode-line-identification nil)

(line-number-mode -1)
(defvar-local mode-line-display-line-number "%l")
(defun mode-line-set-line-number-format ()
  (setq mode-line-display-line-number
        (if (memq display-line-numbers '(relative visual))
            "" "%l")))
(add-hook 'display-line-numbers-mode-hook 'mode-line-set-line-number-format)

(setq-default
 ;; #     #
 ;; ##   ## #    # #      ######
 ;; # # # # #    # #      #
 ;; #  #  # #    # #      #####
 ;; #     # #    # #      #
 ;; #     # #    # #      #
 ;; #     #  ####  ###### ######
 mode-line-mule-info
 `(""
   (current-input-method
    (:propertize ("" current-input-method-title)
                 help-echo (concat
                            ,(purecopy "Current input method: ")
                            current-input-method
                            ,(purecopy "\n\
mouse-2: Disable input method\n\
mouse-3: Describe current input method"))
                 local-map ,mode-line-input-method-map
                 mouse-face mode-line-highlight))
   ,(propertize
     "%z"
     'face 'mode-line-coding-system
     'help-echo 'mode-line-mule-info-help-echo
     'mouse-face 'mode-line-highlight
     'local-map mode-line-coding-system-map)
   (:propertize
    (:eval (mode-line-eol-desc))
    face mode-line-eol))
 ;; #     #
 ;; ##   ##  ####  #####  # ###### # ###### #####
 ;; # # # # #    # #    # # #      # #      #    #
 ;; #  #  # #    # #    # # #####  # #####  #    #
 ;; #     # #    # #    # # #      # #      #    #
 ;; #     # #    # #    # # #      # #      #    #
 ;; #     #  ####  #####  # #      # ###### #####
 mode-line-modified
 '(:eval
   (cond
    ((not (or (and (buffer-file-name) (file-remote-p buffer-file-name))
              (verify-visited-file-modtime (current-buffer))))
     (propertize "M" 'face 'mode-line-outside-modified
                 'help-echo "Modified outside Emacs!\nRevert first!"))
    ((buffer-modified-p)
     (propertize (if buffer-read-only
                     "R"
                   "×")
                 'face 'mode-line-modified
                 'help-echo (if (and (buffer-file-name) (not (file-remote-p buffer-file-name)))
                                (format-time-string
                                 "Modified on %T %Y-%m-%d."
                                 (nth 5 (file-attributes (buffer-file-name))))
                              "Buffer Modified")
                 'local-map '(keymap (mode-line keymap (mouse-1 . save-buffer)))))
    (buffer-read-only (propertize "R"
                                  'face 'mode-line-read-only
                                  'help-echo "Read-Only Buffer"))
    (t ""
       ;; (propertize "-" 'face 'mode-line-not-modified)
       )))
 ;; ######
 ;; #     #  ####   ####  # ##### #  ####  #    #
 ;; #     # #    # #      #   #   # #    # ##   #
 ;; ######  #    #  ####  #   #   # #    # # #  #
 ;; #       #    #      # #   #   # #    # #  # #
 ;; #       #    # #    # #   #   # #    # #   ##
 ;; #        ####   ####  #   #   #  ####  #    #
 mode-line-position
 `((:propertize
    (:eval mode-line-display-line-number)
    face line-number-current-line)
   (:propertize
    ":%c "
     local-map mode-line-column-line-number-mode-map
     mouse-face mode-line-highlight
     help-echo "Line number and Column number\n\
mouse-1: Display Line and Column Mode Menu")
   (:propertize
    mode-line-percent-position
    face mode-line-percentage
    local-map ,mode-line-column-line-number-mode-map
    mouse-face mode-line-highlight
    ;; XXX needs better description
    help-echo "Size indication mode\n\
mouse-1: Display Line and Column Mode Menu")
   (size-indication-mode
    ,(propertize
        " %I"
        'local-map mode-line-column-line-number-mode-map
        'mouse-face 'mode-line-highlight
        ;; XXX needs better description
        'help-echo "Size indication mode\n\
mouse-1: Display Line and Column Mode Menu")))
 ;; #     #
 ;; ##   ##  ####  #####  ######  ####
 ;; # # # # #    # #    # #      #
 ;; #  #  # #    # #    # #####   ####
 ;; #     # #    # #    # #           #
 ;; #     # #    # #    # #      #    #
 ;; #     #  ####  #####  ######  ####
 mode-line-modes
 (let ((recursive-edit-help-echo "Recursive edit, type C-M-c to get out"))
   (list (propertize "%[" 'help-echo recursive-edit-help-echo)
         " "
         `(:propertize ("" mode-name)
                       face mode-line-major-mode
                       help-echo "Major mode\n\
mouse-1: Display major mode menu\n\
mouse-2: Show help for major mode\n\
mouse-3: Toggle minor modes"
                       mouse-face mode-line-highlight
                       local-map ,mode-line-major-mode-keymap)
         '("" mode-line-process)
         `(:propertize ("" minor-mode-alist)
                       mouse-face mode-line-highlight
                       help-echo "Minor mode\n\
mouse-1: Display minor mode menu\n\
mouse-2: Show help for minor mode\n\
mouse-3: Toggle minor modes"
                       local-map ,mode-line-minor-mode-keymap)
         (propertize "%n" 'help-echo "mouse-2: Remove narrowing from buffer"
                     'mouse-face 'mode-line-highlight
                     'local-map (make-mode-line-mouse-map
                                 'mouse-2 #'mode-line-widen))
         (propertize "%]" 'help-echo recursive-edit-help-echo)
         " "))
 ;; #     #                         #
 ;; ##   ##  ####  #####  ######    #       # #    # ######
 ;; # # # # #    # #    # #         #       # ##   # #
 ;; #  #  # #    # #    # #####     #       # # #  # #####
 ;; #     # #    # #    # #         #       # #  # # #
 ;; #     # #    # #    # #         #       # #   ## #
 ;; #     #  ####  #####  ######    ####### # #    # ######
 mode-line-format  ;; -  without mini-modeline
 ;; mini-modeline-r-format  ;; +  with mimi-modeline
 `("%e"
   mode-line-position
   ;; mode-line-front-space  ;; display-graphic-p
   mode-line-mule-info
   mode-line-client
   mode-line-modified
   mode-line-remote
   ;; mode-line-frame-identification
   (:eval (mode-line-buffer-identification-shorten))  ;; - without mini-modeline
   ;; (:eval (mini-modeline-buffer-identification-shorten))  ;; + with mini-modeline
   mode-line-modes
   mode-line-misc-info
   ;; mode-line-end-spaces
   ))

;; [ mini-modeline options
;; (setq mini-modeline-truncate-p nil
;;       mini-modeline-echo-duration 5)
;; (mini-modeline-mode t)  ;; + with mini-modeline
;; ]

(defun mode-line-abbreviate-file-name ()
  (when-let ((name (buffer-file-name)))
    (let ((dominating-file (locate-dominating-file default-directory ".git/"))
          (abbrev-name (abbreviate-file-name name)))
      (if dominating-file
          (concat (propertize
                   (file-name-nondirectory
                   (directory-file-name
                    (file-name-directory dominating-file)))
                   'face 'mode-line-project-name)
                  (substring abbrev-name (1- (length dominating-file))))
        abbrev-name))))

(defun abbrev-string-try (len string)
  (let ((old ""))
    (while (and (< len (string-width string))
                (not (string-equal string old)))
      (setq old string
            string (replace-regexp-in-string
                    "\\(\\([A-Za-z]\\{3\\}\\)[A-Za-z]+\\).*\\'"
                    "\\2"
                    string t nil 1))))
  string)

(defvar mode-line-filename-replacements
  `(("test"     . ,(propertize "T" 'face 'hi-red-b))
    ("config"   . ,(propertize "C" 'face 'hi-red-b))
    ("class"    . ,(propertize "C" 'face 'hi-green-b))
    ("object"   . ,(propertize "O" 'face 'hi-green-b))
    ("api"      . ,(propertize "A" 'face 'hi-green-b))
    ("util"     . ,(propertize "U" 'face 'hi-green-b))
    ("bug"      . ,(propertize "B" 'face 'hi-green-b))
    ("library"  . ,(propertize "L" 'face 'hi-green-b))
    ("librarie" . ,(propertize "L" 'face 'hi-green-b))
    ("invoice"  . ,(propertize "I" 'face 'hi-red-b))
    ("resource" . ,(propertize "R" 'face 'hi-red-b)))
  "Mode line file name replacements")

(defun abbrev-strings-try (len string &rest strings)
  (let ((i -1)
        (len-list (length strings))
        (len-short (- len (string-width string)))
        len-strings)
    (while (and (< (cl-incf i) len-list)
                (< len-short (setq len-strings (apply '+ (mapcar 'string-width strings)))))
      (let ((len-i (- (string-width (nth i strings)) (- len-strings len-short)))
            (old ""))
        (while (and (< len-i (string-width (nth i strings)))
                    (not (string-equal (nth i strings) old)))
          (setq old (nth i strings))
          (let ((istring (nth i strings)))
            (if (string-match "\\(\\([A-Za-z]\\{2\\}\\)[A-Za-z]+\\).*\\'"
                              istring)
                (setcar (nthcdr i strings)
                        (concat
                         (substring istring 0 (match-beginning 1))
                         (let ((isubtext (substring istring
                                                    (match-beginning 2)
                                                    (match-end 2))))
                         (propertize
                          isubtext
                          'face
                          `(:weight bold :slant italic
                                    :inherit ,(get-text-property 0 'face isubtext))
                          'help-echo (substring istring
                                                (match-beginning 1)
                                                (match-end 1))))
                         (substring istring (match-end 1)))))))))
    (if (< 0 (setq len-strings (- len (apply '+ (mapcar 'string-width strings)))))
        (let ((len-list (length mode-line-filename-replacements))
              (i -1))
          (while (and (< len-strings (string-width string))
                      (< i len-list))
            (let ((replacement (nth i mode-line-filename-replacements)))
              (let ((pos (string-match-p (car replacement) string)))
                (if pos
                    (setq string
                          (concat
                           (substring string 0 pos)
                           (cdr replacement)
                           (substring string (+ pos (length (car replacement))))))
                  (cl-incf i))))))))
  `(,string ,@strings))

(defun abbrev-string (len string)
  (if (< len (string-width string))
      (let ((len/2 (max 1 (/ len 2))))
        (concat
         (substring string 0 (- len/2 1))
         (propertize "…"
                     'face 'error
                     'help-echo (buffer-file-name))
         (substring string (- len/2))))
    string))

(defvar mode-line-mock nil)
(defun mode-line-buffer-identification-shorten ()
  (if mode-line-mock
      ""
    (let ((total-len (window-total-width)))
      (if (equal mode-line-cached total-len)
          mode-line-identification
        (prog1
            (let ((others-len (string-width
                               (let ((mode-line-mock t))
                                 (format-mode-line mode-line-format)))))
              (let ((len (- total-len others-len)) ;; with 3 margin (len (- total-len others-len 3))
                    (vc-name (or vc-mode ""))
                    (final-name (or (mode-line-abbreviate-file-name) (buffer-name))))
                (if (< len (+ (string-width final-name) (string-width vc-name)))
                    (if (string-match "\\`\\(.*/\\)\\([^/]*\\)\\'" final-name)
                        (let ((dir-name (match-string 1 final-name))
                              (base-name (match-string 2 final-name)))
                          (if vc-mode
                              (let ((result (abbrev-strings-try
                                             len base-name dir-name vc-name)))
                                (setq vc-name (car (cdr (cdr result)))
                                      len (- len (string-width vc-name))
                                      final-name (abbrev-string
                                                  len (concat
                                                       (car (cdr result))
                                                       (car result)))))
                            (let ((result (abbrev-strings-try
                                           len base-name dir-name)))
                              (setq final-name (abbrev-string
                                                len (concat
                                                     (car (cdr result))
                                                     (car result)))))))
                      (if vc-mode
                          (let ((result (abbrev-strings-try len "" final-name vc-name)))
                            (setq vc-name (car (cdr (cdr result)))
                                  len (- len (string-width vc-name))
                                  final-name (abbrev-string len (car (cdr result)))))
                        (setq final-name (abbrev-string
                                          len (abbrev-string-try len final-name)))))
                  (setq len (- len (string-width vc-name))))
                (setq mode-line-identification
                      (concat
                       (format (concat "%-" (int-to-string (max len 0)) "s") final-name)
                                                vc-name))))
          (setq mode-line-cached total-len))))))

;;;;;;;;;;;;;;;;
;; Projectile ;;
;;;;;;;;;;;;;;;;
(with-eval-after-load 'projectile
  (defun projectile-mode-menu (event)
    (interactive "@e")
    (let ((minor-mode 'projectile-mode))
      (let* ((map (cdr-safe (assq minor-mode minor-mode-map-alist)))
             (menu (and (keymapp map) (lookup-key map [menu-bar]))))
        (if menu
            (popup-menu (mouse-menu-non-singleton menu))
          (message "No menu available")))))

  (defvar mode-line-projectile-mode-keymap
    (let ((map (make-sparse-keymap)))
      (define-key map [mode-line down-mouse-1] 'projectile-mode-menu)
      (define-key map [mode-line mouse-2] 'mode-line-minor-mode-help)
      (define-key map [mode-line down-mouse-3] mode-line-mode-menu)
      (define-key map [header-line down-mouse-3] mode-line-mode-menu)
      map) "\
Keymap to display projectile options.")

  (defun mode-line-perform-projectile-replacement (in)
    "If path IN is inside a project, use its name as a prefix."
    (let ((proj (projectile-project-p)))
      (if (stringp proj)
          (let* ((replacement (propertize
                               (funcall projectile-mode-line-function)
                               'face 'mode-line-project-name
                               'mouse-face 'mode-line-highlight
                               'help-echo "Minor mode\n\
mouse-1: Display minor mode menu\n\
mouse-2: Show help for minor mode\n\
mouse-3: Toggle minor modes"
                               'local-map mode-line-projectile-mode-keymap))
                 (short (replace-regexp-in-string
                         (concat "^" (regexp-quote (abbreviate-file-name proj)))
                         replacement
                         in t t)))
            (if (string= short in)
                (let* ((true-in (abbreviate-file-name (file-truename in)))
                       (true-short
                        (replace-regexp-in-string
                         (concat "^" (regexp-quote (abbreviate-file-name (file-truename proj))))
                         replacement true-in t t)))
                  (if (string= true-in true-short) in true-short))
              short))
        in)))

  (defun mode-line-abbreviate-file-name ()
    (let ((name (buffer-file-name)))
      (if name
          (mode-line-perform-projectile-replacement (abbreviate-file-name name))))))

;;;;;;;;;;;;;;;;;;;;;
;; Version control ;;
;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'vc-hooks
  (defun vc-mode-line-advice (file &optional backend)
    "Colorize and abbrev `vc-mode'."
    (when (stringp vc-mode)
      (let ((noback (replace-regexp-in-string
                     (concat "^ " (regexp-quote (symbol-name backend)))
                     " " vc-mode t t)))
        (setq vc-mode
              (propertize noback
                          'face (cl-case (elt noback 1)
                                  (?- 'mode-line-not-modified)
                                  ((?: ?@) 'mode-line-read-only)
                                  ((?! ?\\ ??) 'mode-line-modified)))))))
  (advice-add 'vc-mode-line :after 'vc-mode-line-advice))

;; set a default font
;; $(sudo fc-cache -rfv)
(setq inhibit-compacting-font-caches t)
(eval-and-when-daemon frame
  (when (display-graphic-p frame)
    (with-selected-frame frame
      (cond
       ((member "Monaco" (font-family-list))
        (set-face-attribute 'default nil
                            :family "Fira Code"
                            :height 90
                            :foundry "unknown"
                            :weight 'regular
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: Fira Code Family"))
       ((member "Fira Code" (font-family-list))
        (set-face-attribute 'default nil
                            :family "Fira Code"
                            :height 90
                            :foundry "unknown"
                            :weight 'regular
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: Fira Code Family"))
       ((member "Hack" (font-family-list))
        (set-face-attribute 'default nil
                            :family "Hack"
                            :height 90
                            :foundry "unknown"
                            :weight 'regular
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: Hack Family"))
       ((member "DejaVu Sans Mono" (font-family-list))
        (set-face-attribute 'default nil
                            :family "DejaVu Sans Mono"
                            :height 100
                            :foundry "unknown"
                            :weight 'regular
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: DejaVu Sans Mono Family"))
       ((member "Iosevka Term" (font-family-list)) ;; Iosevka case
        (set-face-attribute 'default nil
                            :family "Iosevka Term"
                            :height 100
                            :foundry "unknown"
                            :weight 'light
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: Iosevka Term Family"))
       ((member "-outline-Iosevka Term Light-light-normal-normal-mono-*-*-*-*-c-*-iso8859-1"
                (x-list-fonts "*" nil (selected-frame)))
        (set-face-attribute 'default nil
                            :font "-outline-Iosevka Term Light-light-normal-normal-mono-*-*-*-*-c-*-iso8859-1"
                            :height 100)
        (message "Monospace font: Iosevka Term Light"))
       ((member "-outline-Unifont-normal-normal-normal-*-*-*-*-*-p-*-iso8859-1"
                (x-list-fonts "*" nil (selected-frame)))
        (set-face-attribute 'default nil
                            :font "-outline-Unifont-normal-normal-normal-*-*-*-*-*-p-*-iso8859-1"
                            :height 100)
        (message "Monospace font: Unifont"))
       ;; sudo apt install fonts-mononoki
       ((member "mononoki" (font-family-list))
        (set-face-attribute 'default nil
                            :family "Mononoki"
                            :height 90
                            :foundry "unknown"
                            :weight 'regular
                            :slant 'normal
                            :width 'normal)
        (message "Monospace font: Mononoki Family"))
       (t ;; default case
        (message "Monospace font not found")
        (set-face-attribute 'default nil
                            :height 100
                            :weight 'light
                            :slant 'normal
                            :width 'normal)))
      ;; [ Iosevka 3.0.0 supports unicode
      ;; (let ((font-spec-args
      ;;        (cond
      ;;         ((member "DejaVu Sans Mono monospacified for Iosevka Term Light"
      ;;                  (font-family-list))
      ;;          '(:family "DejaVu Sans Mono monospacified for Iosevka Term Light"))
      ;;         ((member "-outline-DejaVu Sans Mono monospacified -normal-normal-normal-mono-*-*-*-*-c-*-iso8859-1"
      ;;                  (x-list-fonts "*" nil (selected-frame)))
      ;;          '(:name "-outline-DejaVu Sans Mono monospacified -normal-normal-normal-mono-*-*-*-*-c-*-iso8859-1"))
      ;;         ((member "-outline-Unifont-normal-normal-normal-*-*-*-*-*-p-*-iso8859-1"
      ;;                  (x-list-fonts "*" nil (selected-frame)))
      ;;          '(:name "-outline-Unifont-normal-normal-normal-*-*-*-*-*-p-*-iso8859-1")))))
      ;;   (if (null font-spec-args)
      ;;       (message "Monospace utf-8 font not found.")
      ;;     (dolist (range '((#x2100 . #x230F)
      ;;                        (#x2380 . #x23F3)
      ;;                        (#x2420 . #x2424)
      ;;                        (#x25A0 . #x25FF)
      ;;                        (#x2610 . #x2613)
      ;;                        (#x2692 . #x26A0)
      ;;                        (#x26D2 . #x26D4)
      ;;                        (#x2709 . #x270C)))
      ;;         (set-fontset-font "fontset-default" range
      ;;                           (apply 'font-spec font-spec-args)))
      ;;     (message "Monospace utf-8 font: %s" (or (plist-get font-spec-args :family)
      ;;                                             (plist-get font-spec-args :name)))))
      ;; ]
      )))

(eval-and-compile
  (let ((default-directory "~/.emacs.d/el"))
    (normal-top-level-add-subdirs-to-load-path)))

(unless (display-graphic-p)
  (xterm-mouse-mode 1)
  (xclip-mode 1))
;; [ don't work properly and cpu expensive
;; (setq blink-cursor-blinks 0)
;; (eval-and-when-daemon frame
;;   (blink-cursor-mode t))
;; <xor>
(eval-and-when-daemon frame
  (blink-cursor-mode -1))
;; ]

(set-face-attribute 'line-number-current-line nil
                    :weight 'bold
                    :foreground "#fe3")

(setq-default
 ;; t -   long lines go away from window width, ei, continuation lines
 ;; nil - soft wrap lines
 truncate-lines nil ;; so-long-variable-overrides doc
 ;; ignore case searching
 case-fold-search t)
;; [ Demasiado agresivo, mejor con ido
;; Cambia todas las preguntas yes-or-no-p por y-or-n-p
;; (fset 'yes-or-no-p 'y-or-n-p)
;; ]
;; Option 2
;; (defun yes-or-no-p (prompt)
;;   (interactive)
;;   (pcase (downcase (read-string (concat prompt "(yes, no) ")))
;;     ("y" t)
;;     ("ye" t)
;;     ("yes" t)
;;     (_ nil)))
(defun yes-or-no-p (prompt)
  (interactive)
  (string-equal
   "yes"
   (completing-read prompt '("yes" "no") nil t nil nil "no")))

(defun insert-utf8 (&optional name)
  (interactive)
  (let ((utf8-hash-table (ucs-names)))
    (insert (gethash (completing-read
                      "Unicode character name: "
                      (hash-table-keys utf8-hash-table)
                      nil t)
                     utf8-hash-table))))

(setq echo-keystrokes 0.5
      ;; jit-lock-defer-time 0
      ;; jit-lock-context-time 0.5
      ;; ;; when idle fontifies portions not yet displayed
      ;; jit-lock-stealth-time 10
      ;; jit-lock-stealth-nice 0.5
      ;; jit-lock-stealth-load 50
      ;; jit-lock-chunk-size 100
      column-number-mode t
      isearch-lazy-count t
      isearch-allow-scroll 'unlimited
      completion-cycle-threshold 3
      completion-show-help nil
      ;; kill-ring
      kill-do-not-save-duplicates t
      ;; mark-ring
      set-mark-command-repeat-pop t
      mark-ring-max 32
      global-mark-ring-max 128
      ;; Deshabilita insertar una nueva linea al final de los ficheros
      ;; para que las plantillas de 'yasnippet' no añadan nueva liena
      mode-require-final-newline nil)
;; (push 'substring completion-styles)

;;;;;;;;;;;;;;;;;;;
;; Coding system ;;
;;;;;;;;;;;;;;;;;;;
;; [ utf8 default in last versions
;; (set-default-coding-systems 'utf-8)
;; (set-clipboard-coding-system 'utf-8)

;; (prefer-coding-system 'utf-8)
;; (setq locale-coding-system 'utf-8
;;       unibyte-display-via-language-environment t
;;       default-process-coding-system '(utf-8-unix . utf-8-unix)
;;       file-name-coding-system 'utf-8)
;; (set-terminal-coding-system 'utf-8-unix)

;; (eval-and-when-daemon frame
;;   (with-selected-frame frame
;;     (unless window-system
;;       (set-keyboard-coding-system 'utf-8))))

;; (set-selection-coding-system 'utf-8)
;; (set-next-selection-coding-system 'utf-8)
;; (set-buffer-file-coding-system 'utf-8-unix)
;; (set-language-environment 'UTF-8)
;; (require 'iso-transl)
;; ]
;;(set-buffer-process-coding-system 'utf-8-unix 'utf-8-unix) ; error: No process
;;(add-to-list 'auto-coding-regexp-alist '("^\xEF\xBB\xBF" . utf-8) t)
;;(add-to-list 'auto-coding-regexp-alist '("\\`\240..." . latin-1))
;;(add-to-list 'process-coding-system-alist '("gud" . utf-8))

;; Toggle coding systems
(defun toggle-buffer-coding-system ()
  (interactive)
  (if (or (equal buffer-file-coding-system 'utf-8-unix)
          (equal buffer-file-coding-system 'utf-8))
      (let ((process (get-buffer-process (current-buffer))))
        (set-buffer-file-coding-system 'iso-8859-1-unix)
        (set-keyboard-coding-system 'iso-8859-1-unix)
        (when process
          (set-process-coding-system process 'iso-8859-1-unix 'iso-8859-1-unix)))
    (let ((process (get-buffer-process (current-buffer))))
      (set-buffer-file-coding-system 'utf-8-unix)
      (set-keyboard-coding-system 'utf-8)
      (when process
        (set-process-coding-system process 'utf-8-unix 'utf-8-unix)))))

;; Busca caracteres no representables
(defun find-next-unsafe-char (&optional coding-system)
  "Find the next character in the buffer that cannot be encoded by
coding-system. If coding-system is unspecified, default to the coding
system that would be used to save this buffer. With prefix argument,
prompt the user for a coding system."
  (interactive "Zcoding-system: ")
  (if (stringp coding-system) (setq coding-system (intern coding-system)))
  (if coding-system nil
    (setq coding-system
          (or save-buffer-coding-system buffer-file-coding-system)))
  (let ((found nil) (char nil) (csets nil) (safe nil))
    (setq safe (coding-system-get coding-system 'safe-chars))
    ;; some systems merely specify the charsets as ones they can encode:
    (setq csets (coding-system-get coding-system 'safe-charsets))
    (save-excursion
      ;;(message "zoom to <")
      (let ((end  (point-max))
            (here (point    ))
            (char  nil))
        (while (and (< here end) (not found))
          (setq char (char-after here))
          (if (or (eq safe t)
                  (< char ?\177)
                  (and safe  (aref safe char))
                  (and csets (memq (char-charset char) csets)))
              nil ;; safe char, noop
            (setq found (cons here char)))
          (setq here (1+ here))) ))
    (and found (goto-char (1+ (car found))))
    found))

;; from ascii to utf8
(defun ascii-to-utf8-forward (beg end)
  (interactive (list (point) (point-max)))
  (save-excursion
    (let ((case-fold-search nil))
      (dolist (map '(("\\\240" . "á")
                     ("\\\202" . "é")
                     ("\\\241" . "í")
                     ("\\\242" . "ó")
                     ("\\\243" . "ú")
                     ("\\\244" . "ñ")
                     ("\\\245" . "Ñ")
                     ("\\\265" . "Á")
                     ("\\\220" . "É")
                     ("\\\326" . "Í")
                     ("\\\340" . "Ó")
                     ("\\\351" . "Ú")
                     ("\\\204" . "ä")
                     ("\\\211" . "ë")
                     ("\\\213" . "ï")
                     ("\\\224" . "ö")
                     ("\\\201" . "ü")
                     ("\\\216" . "Ä")
                     ("\\\323" . "Ë")
                     ("\\\330" . "Ï")
                     ("\\\231" . "Ö")
                     ("\\\232" . "Ü")))
        (goto-char beg)
        (while (search-forward (car map) end t 1)
          (replace-match (cdr map) t t))))))

(defun utf8-fix-wrong-ascii (beg end)
  (interactive (list (point) (point-max)))
  (save-excursion
    (let ((case-fold-search nil))
      (dolist (map '(("›" . "â\x0080º") ;; \200
                     ("🐜" . "ð\x009f\x0090\x009c"))) ;; \237\220\234
        (goto-char beg)
        (while (search-forward (cdr map) end t 1)
          (replace-match (car map) t t))))))

(defun utf8-fix-wrong-latin (beg end)
  (interactive (list (point) (point-max)))
  (save-excursion
    (let ((case-fold-search nil))
      (dolist (map '(("À" . "Ã€")
                     ("Â" . "Ã‚")
                     ("Ã" . "Ãƒ")
                     ("Ä" . "Ã„")
                     ("Å" . "Ã…")
                     ("Æ" . "Ã†")
                     ("Ç" . "Ã‡")
                     ("È" . "Ãˆ")
                     ("É" . "Ã‰")
                     ("Ê" . "ÃŠ")
                     ("Ë" . "Ã‹")
                     ("Ì" . "ÃŒ")
                     ("Î" . "ÃŽ")
                     ("Ñ" . "Ã‘")
                     ("Ò" . "Ã’")
                     ("Ó" . "Ã“")
                     ("Ô" . "Ã”")
                     ("Õ" . "Ã•")
                     ("Ö" . "Ã–")
                     ("×" . "Ã—")
                     ("Ø" . "Ã˜")
                     ("Ù" . "Ã™")
                     ("Ú" . "Ãš")
                     ("Û" . "Ã›")
                     ("Ü" . "Ãœ")
                     ("Þ" . "Ãž")
                     ("ß" . "ÃŸ")
                     ("á" . "Ã¡")
                     ("â" . "Ã¢")
                     ("ã" . "Ã£")
                     ("ä" . "Ã¤")
                     ("å" . "Ã¥")
                     ("æ" . "Ã¦")
                     ("ç" . "Ã§")
                     ("è" . "Ã¨")
                     ("é" . "Ã©")
                     ("ê" . "Ãª")
                     ("ë" . "Ã«")
                     ("ì" . "Ã¬")
                     ("í" . "Ã­")
                     ("î" . "Ã®")
                     ("ï" . "Ã¯")
                     ("ð" . "Ã°")
                     ("ñ" . "Ã±")
                     ("ò" . "Ã²")
                     ("ó" . "Ã³")
                     ("ô" . "Ã´")
                     ("õ" . "Ãµ")
                     ("ö" . "Ã¶")
                     ("÷" . "Ã·")
                     ("ø" . "Ã¸")
                     ("ù" . "Ã¹")
                     ("ú" . "Ãº")
                     ("û" . "Ã»")
                     ("ü" . "Ã¼")
                     ("ý" . "Ã½")
                     ("þ" . "Ã¾")
                     ("ÿ" . "Ã¿")
                     ("Á" . "Ã")))
        (goto-char beg)
        (while (search-forward (cdr map) end t 1)
          (replace-match (car map) t t))))))

;; remove latin1 characters
(defun remove-tildes (string)
  (let ((case-fold-search t))
    (dolist (map '(("á" . "a")
                   ("é" . "e")
                   ("í" . "i")
                   ("ó" . "o")
                   ("ú" . "u")
                   ("ñ" . "n")
                   ("ä" . "a")
                   ("ë" . "e")
                   ("ï" . "i")
                   ("ö" . "o")
                   ("ü" . "u")) string)
      (set 'string (replace-regexp-in-string (car map) (cdr map) string nil t)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keyboard translations ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
(when (executable-find "setxkbmap")
  (defun xkb-swap-ctrl-caps (&optional arg)
    (interactive "P")
    (if arg
        (start-process " *setxkbmap" nil
                       "setxkbmap" "-option")
      (start-process " *setxkbmap" nil
                     "setxkbmap" "-option" "ctrl:swapcaps")))
  (defun xkb-swap-ctrl-win (&optional arg)
    (interactive "P")
    (if arg
        (start-process " *setxkbmap" nil
                       "setxkbmap" "-option")
      (start-process " *setxkbmap" nil
                     "setxkbmap" "-option" "ctrl:swap_lwin_lctl"))))

(when (executable-find "xkbcomp")
  (defun xkb-swap-ralt-ctrl (&optional arg)
    (interactive "P")
    (let ((xkb-path (expand-file-name "~/.emacs.d/cache/xkb")))
     (if arg
         (start-process " *xkbcomp" nil
                        "xkbcomp" (concat "-I" xkb-path)
                        (concat xkb-path "/keymap/kbd")
                        (getenv "DISPLAY"))
       (start-process " *xkbcomp" nil
                      "xkbcomp" (concat "-I" xkb-path)
                      (concat xkb-path "/keymap/kbd_swap_ralt_ctrl")
                      (getenv "DISPLAY")))))
  (when (display-graphic-p)
    (xkb-swap-ralt-ctrl)))

(defun swap-for-programming-keys (&optional arg)
  (interactive "P")
  (if arg
      (setq keyboard-translate-table nil)
    (setq keyboard-translate-table
          (make-char-table 'keyboard-translate-table))
    ;; Swap º and \
    (aset keyboard-translate-table ?º ?\\)
    (aset keyboard-translate-table ?\\ ?º)))

(defun apple-keyboard-toggle-fn-key (&optional arg)
  ;; * permanent change
  ;; 1. edit or create: /etc/modprobe.d/hid_apple.conf
  ;; 2. append line:    options hid_apple fnmode=2
  ;; 3. shell command:  sudo update-initramfs -u -k all
  ;; 4. reboot.
  (interactive "P")
  (if (eq last-command 'apple-keyboard-toggle-fn-key)
      (user-error "Ignoring repeated call")
    (setq arg  (number-to-string
                (if (numberp arg)
                    (if (and (<= arg 2)
                             (>= arg 0))
                        arg
                      (user-error "Invalid number %i" arg))
                  (cl-case (string-to-number
                            (shell-command-to-string
                             "cat /sys/module/hid_apple/parameters/fnmode"))
                    (0 2)
                    (1 2)
                    (2 0)
                    (otherwise 2)))))
    (unwind-protect
        (with-temp-buffer
          (cd "/sudo::/")
          (shell-command
           (concat "echo " arg " | tee /sys/module/hid_apple/parameters/fnmode")))
      (discard-input)
      (setq unread-command-events nil))))
(global-set-key (kbd "<M-XF86MonBrightnessDown>") 'apple-keyboard-toggle-fn-key)
(global-set-key (kbd "<M-f1>") 'apple-keyboard-toggle-fn-key)

;;;;;;;;;;;;;;;;;
;; Indentation ;;
;;;;;;;;;;;;;;;;;
;; Only spaces without tabs
(setq-default indent-tabs-mode nil
              tab-width 4
              sh-indent-for-case-label 0
              sh-indent-for-case-alt '+)
(setq tab-always-indent 'complete
      ;; styles
      c-default-style "linux"
      tab-width 4
      indent-tabs-mode nil
      c-basic-offset 4
      python-indent-offset 4
      js-indent-level 4)

(c-set-offset 'innamespace '0)
(c-set-offset 'inextern-lang '0)
(c-set-offset 'inline-open '0)
(c-set-offset 'label '*)
(c-set-offset 'case-label '0)
(c-set-offset 'access-label '/)

(define-key indent-rigidly-map (kbd "M-f") #'indent-rigidly-right-to-tab-stop)
(define-key indent-rigidly-map (kbd "M-b") #'indent-rigidly-left-to-tab-stop)
(define-key indent-rigidly-map (kbd "C-f") #'indent-rigidly-right)
(define-key indent-rigidly-map (kbd "C-b") #'indent-rigidly-left)

(defmacro save-line (&rest body)
  `(let* ((origin (point))
         (line (count-lines 1 origin)))
    ,@body
    (unless (= line (count-lines 1 (point)))
      (goto-char origin))))

;; unescape line
(defun join-lines-unescaping-new-lines ()
  (interactive)
  (save-excursion
    (end-of-line)
    (while (char-equal (char-before) ?\\)
      (left-char)
      (delete-char 2)
      (when (char-equal (char-after) ? )
        (fixup-whitespace))
      (end-of-line))))

(defun break-line-escaping-new-lines ()
  (interactive)
  (save-excursion
    (while (= (1+ whitespace-line-column)
              (move-to-column (1+ whitespace-line-column)))
      (left-char)
      (save-line
       (backward-word))
      (let ((column (current-column)))
        (when (or (< column (/ whitespace-line-column 2))
                  (> column (- whitespace-line-column 2)))
          (move-to-column (- whitespace-line-column 2))))
      (insert "\\")
      (call-interactively #'newline))))

;; Mostrar parentesis (ya lo hace show-smartparents-mode)
(show-paren-mode 1)
(electric-pair-mode 1)
;; Narrow enabled
(put 'narrow-to-region 'disabled nil)

;; No lo activamos por ser muy engorroso
;;(put 'scroll-left 'disabled nil)

;;;;;;;;;;;;;;;;;
;; Copy things ;;
;;;;;;;;;;;;;;;;;
(setq yank-excluded-properties t)

(defun duplicate-region (arg beg end &optional orig)
  "Duplicates ARG times region from BEG to END."
  (let ((origin (or orig end))
        (neg (> 0 arg))
        (argument (abs arg))
        (region (buffer-substring-no-properties beg end)))
    (if neg
        (dotimes (i argument)
          (goto-char end)
          (newline)
          (insert region)
          (setq end (point)))
      (dotimes (i argument)
        (goto-char end)
        (insert region)
        (setq end (point)))
      (set 'origin (- origin argument)))
    (goto-char (+ origin (* (length region) argument) argument))))

(defun duplicate-rectangle-region (arg beg end)
  (let ((region (sort (list beg end) '<)))
    (let ((rectangle (extract-rectangle (cl-first region)
                                        (cl-second region)))
          (bounds (extract-rectangle-bounds (cl-first region)
                                            (cl-second region))))
      (cond
       ((or (= end (cdr (car bounds)))
            (= end (cdr (car (last bounds)))))
        (dotimes (i arg)
            (goto-char (car region))
            (insert-rectangle rectangle)))
       ((= end (car (car bounds)))
        (let ((column (current-column))
              (lines (length bounds))
              backward-lines)
          (setq backward-lines (- 1 (* 2 lines))
                lines (- 1 lines))
          (forward-line lines)
          (dotimes (i arg)
            (unless (= 0 (forward-line backward-lines))
              (error "Not enough lines above"))
            (move-to-column column)
            (insert-rectangle rectangle))
          (forward-line lines)
          (move-to-column column)))
       ((= end (car (car (last bounds))))
        (let ((column (current-column)))
          (dotimes (i arg)
            (let ((line (line-number-at-pos)))
              (forward-line)
              (if (= line (line-number-at-pos))
                  (insert "\n")))
            (move-to-column column)
            (insert-rectangle rectangle))
          (move-to-column column)))))))

(defun duplicate-current-line-or-region (arg)
  "Duplicates the current line or region ARG times.
If there's no region, the current line will be duplicated. However, if
there's a region, all lines that region covers will be duplicated."
  (interactive "p")
  (if (use-region-p)
      (if rectangle-mark-mode
          (duplicate-rectangle-region arg (mark) (point))
        (let ((region (sort (list (mark) (point)) '<)))
          (duplicate-region arg
                            (cl-first region)
                            (cl-second region)
                            (point))))
    (duplicate-region (- arg)
                      (line-beginning-position)
                      (line-end-position)
                      (point))))
;;;;;;;;;;;
;; Mouse ;;
;;;;;;;;;;;

;; (require 'ffap) autoloaded functions
(global-set-key [S-mouse-3] 'ffap-at-mouse)
(global-set-key [C-S-mouse-3] 'ffap-menu)
(global-set-key "\C-xf" 'find-file-at-point)

;; (global-set-key "\C-x\C-f" 'find-file-at-point)
;; (global-set-key "\C-x\C-r" 'ffap-read-only)
;; (global-set-key "\C-x\C-v" 'ffap-alternate-file)

;; (global-set-key "\C-x4f"   'ffap-other-window)
;; (global-set-key "\C-x5f"   'ffap-other-frame)
;; (global-set-key "\C-x4r"   'ffap-read-only-other-window)
;; (global-set-key "\C-x5r"   'ffap-read-only-other-frame)

;; (global-set-key "\C-xd"    'dired-at-point)
;; (global-set-key "\C-x4d"   'ffap-dired-other-window)
;; (global-set-key "\C-x5d"   'ffap-dired-other-frame)
;; (global-set-key "\C-x\C-d" 'ffap-list-directory)

;; (add-hook 'gnus-summary-mode-hook 'ffap-gnus-hook)
;; (add-hook 'gnus-article-mode-hook 'ffap-gnus-hook)
;; (add-hook 'vm-mode-hook 'ffap-ro-mode-hook)
;; (add-hook 'rmail-mode-hook 'ffap-ro-mode-hook))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                        ;;
;;     Nuevas teclas      ;;
;;                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;
;; Idiomas español e inglés

;; [ Liberamos la combinación de teclas M-f
;; (global-unset-key (kbd "M-f"))
;; copiado y pegado
;; (global-unset-key (kbd "M-w"))
;; (global-unset-key (kbd "C-w"))
;; (global-unset-key (kbd "C-y"))
;; (global-unset-key (kbd "C-c"))
;; (global-unset-key (kbd "C-x"))
;; (global-unset-key (kbd "C-v"))
;; ;; ]
;; ;; [ Teclas de copiado y pegado universales
;; (global-set-key (kbd "C-c") 'kill-ring-save)
;; (global-set-key (kbd "C-x") 'kill)
;; (global-set-key (kbd "C-c") 'yank)
;; ]
;;;;;;;


;; Activa imath-mode
;(global-set-key (kbd "M-n M-m") 'imath-mode)

;; Bookmark handling
;;
;; (global-set-key (kbd "<C-f5>") '(lambda () (interactive) (progn (message "Bookmark f5 added") (bookmark-set "BookMark_f5"))))
;; (global-set-key (kbd "<f5>") '(lambda () (interactive) (bookmark-jump "BookMark_f5")))
;; (global-set-key (kbd "<C-f6>") '(lambda () (interactive) (progn (message "Bookmark f6 added") (bookmark-set "BookMark_f6"))))
;; (global-set-key (kbd "<f6>") '(lambda () (interactive) (bookmark-jump "BookMark_f6")))
;; (global-set-key (kbd "<C-f7>") '(lambda () (interactive) (progn (message "Bookmark f7 added") (bookmark-set "BookMark_f7"))))
;; (global-set-key (kbd "<f7>") '(lambda () (interactive) (bookmark-jump "BookMark_f7")))
;; (global-set-key (kbd "<C-f8>") '(lambda () (interactive) (progn (message "Bookmark f8 added") (bookmark-set "BookMark_f8"))))
;; (global-set-key (kbd "<f8>") '(lambda () (interactive) (bookmark-jump "BookMark_f8")))

(define-key key-translation-map (kbd "M-s M-u <down>") (kbd "↓"))
(define-key key-translation-map (kbd "M-s M-u <left>") (kbd "←"))
(define-key key-translation-map (kbd "M-s M-u <right>") (kbd "→"))
(define-key key-translation-map (kbd "M-s M-u <up>") (kbd "↑"))
(define-key key-translation-map (kbd "M-s M-u TAB") (kbd "↹"))
(define-key key-translation-map (kbd "M-s M-u RET") (kbd "↵"))
(define-key key-translation-map (kbd "M-s M-u a") (kbd "α"))
(define-key key-translation-map (kbd "M-s M-u A") (kbd "Α"))
(define-key key-translation-map (kbd "M-s M-u b") (kbd "β"))
(define-key key-translation-map (kbd "M-s M-u B") (kbd "Β"))
(define-key key-translation-map (kbd "M-s M-u g") (kbd "γ"))
(define-key key-translation-map (kbd "M-s M-u G") (kbd "Γ"))
(define-key key-translation-map (kbd "M-s M-u d") (kbd "δ"))
(define-key key-translation-map (kbd "M-s M-u D") (kbd "Δ"))
(define-key key-translation-map (kbd "M-s M-u e") (kbd "ε"))
(define-key key-translation-map (kbd "M-s M-u E") (kbd "Ε"))
(define-key key-translation-map (kbd "M-s M-u z") (kbd "ζ"))
(define-key key-translation-map (kbd "M-s M-u Z") (kbd "Ζ"))
(define-key key-translation-map (kbd "M-s M-u h") (kbd "η"))
(define-key key-translation-map (kbd "M-s M-u H") (kbd "Η"))
(define-key key-translation-map (kbd "M-s M-u q") (kbd "θ"))
(define-key key-translation-map (kbd "M-s M-u Q") (kbd "Θ"))
(define-key key-translation-map (kbd "M-s M-u i") (kbd "ι"))
(define-key key-translation-map (kbd "M-s M-u I") (kbd "Ι"))
(define-key key-translation-map (kbd "M-s M-u k") (kbd "κ"))
(define-key key-translation-map (kbd "M-s M-u K") (kbd "Κ"))
(define-key key-translation-map (kbd "M-s M-u l") (kbd "λ"))
(define-key key-translation-map (kbd "M-s M-u L") (kbd "Λ"))
(define-key key-translation-map (kbd "M-s M-u m") (kbd "μ"))
(define-key key-translation-map (kbd "M-s M-u M") (kbd "Μ"))
(define-key key-translation-map (kbd "M-s M-u n") (kbd "ν"))
(define-key key-translation-map (kbd "M-s M-u N") (kbd "Ν"))
(define-key key-translation-map (kbd "M-s M-u p") (kbd "π"))
(define-key key-translation-map (kbd "M-s M-u P") (kbd "Π"))
(define-key key-translation-map (kbd "M-s M-u r") (kbd "ρ"))
(define-key key-translation-map (kbd "M-s M-u R") (kbd "Ρ"))
(define-key key-translation-map (kbd "M-s M-u s") (kbd "σ"))
(define-key key-translation-map (kbd "M-s M-u S") (kbd "Σ"))
(define-key key-translation-map (kbd "M-s M-u t") (kbd "τ"))
(define-key key-translation-map (kbd "M-s M-u T") (kbd "Τ"))
(define-key key-translation-map (kbd "M-s M-u y") (kbd "υ"))
(define-key key-translation-map (kbd "M-s M-u Y") (kbd "Υ"))
(define-key key-translation-map (kbd "M-s M-u f") (kbd "φ"))
(define-key key-translation-map (kbd "M-s M-u F") (kbd "Φ"))
(define-key key-translation-map (kbd "M-s M-u x") (kbd "χ"))
(define-key key-translation-map (kbd "M-s M-u X") (kbd "Χ"))
(define-key key-translation-map (kbd "M-s M-u v") (kbd "Ψ"))
(define-key key-translation-map (kbd "M-s M-u V") (kbd "ψ"))
(define-key key-translation-map (kbd "M-s M-u w") (kbd "ω"))
(define-key key-translation-map (kbd "M-s M-u W") (kbd "Ω"))
(define-key key-translation-map (kbd "M-s M-u *") (kbd "×"))
(define-key key-translation-map (kbd "M-s M-u /") (kbd "÷"))
(define-key key-translation-map (kbd "M-s M-u .") (kbd "…"))
(define-key key-translation-map (kbd "M-s M-u +") (kbd "∞"))
(define-key key-translation-map (kbd "M-s M-u =") (kbd "≠"))
(define-key key-translation-map (kbd "M-s M-u -") (kbd "±"))
(define-key key-translation-map (kbd "M-s M-u 0") (kbd "ℵ"))
(define-key key-translation-map (kbd "M-s M-u \\") (kbd "∀"))
(define-key key-translation-map (kbd "M-s M-u !") (kbd "∃"))
(define-key key-translation-map (kbd "M-s M-u |") (kbd "∄"))
(define-key key-translation-map (kbd "M-s M-u º") (kbd "∅"))
(define-key key-translation-map (kbd "M-s M-u /") (kbd "∈"))
(define-key key-translation-map (kbd "M-s M-u %") (kbd "∝"))
(define-key key-translation-map (kbd "M-s M-u ç") (kbd "⊆"))
(define-key key-translation-map (kbd "M-s M-u Ç") (kbd "⊂"))
(define-key key-translation-map (kbd "M-s M-u ñ") (kbd "⊇"))
(define-key key-translation-map (kbd "M-s M-u Ñ") (kbd "⊃"))

;;;;;;;;;;;;;;;;;;;;
;; Big movements  ;;
;;;;;;;;;;;;;;;;;;;;
(defun window-width-without-margin (&optional window pixelwise)
  (- (window-width window pixelwise)
     hscroll-margin
     (if display-line-numbers
         (if (numberp display-line-numbers-width)
             display-line-numbers-width
           3)
       0)))

(defvar recenter-horizontal-last-op nil)
(defvar recenter-horizontal-positions '(middle left right))

(defun recenter-horizontal (&optional arg)
  "Make the ARG or point horizontally centered in the window."
  (interactive "P")
  (setq arg (or arg (current-column))
        recenter-horizontal-last-op (if (eq this-command last-command)
                                        (car (or (cdr (member
                                                       recenter-horizontal-last-op
                                                       recenter-horizontal-positions))
                                                 recenter-horizontal-positions))
                                      (car recenter-horizontal-positions)))
  (pcase recenter-horizontal-last-op
    ('middle
     (let ((mid (/ (window-width-without-margin) 2)))
       (if (< mid arg)
           (set-window-hscroll (selected-window)
                               (- arg mid)))))
    ('left
     (set-window-hscroll (selected-window) arg))
    ('right
     (let ((width (window-width-without-margin)))
       (if (< width arg)
           (set-window-hscroll (selected-window)
                               (- arg width)))))))

(defvar horizontal-alt 15)

(defun forward-alt ()
  (interactive)
  (forward-char horizontal-alt))

(defun backward-alt ()
  (interactive)
  (backward-char horizontal-alt))

(defun hscroll-right (arg)
  (interactive "p")
  (let ((width (window-width-without-margin))
        (col (current-column)))
    (let ((pos (max 0 (* (+ (/ col width) arg) width))))
      (move-to-column (+ pos hscroll-margin 1))
      (set-window-hscroll (selected-window) pos))))

(defun hscroll-left (arg)
  (interactive "p")
  (hscroll-right (- arg)))

;;;;;;;;;;;;
;; Prompt ;;
;;;;;;;;;;;;
;(advice-add 'read-from-minibuffer :around #'message-inhibit-advice)

(defun minibuffer-try-pre ()
  "By default typing out of input area raise an error.
This function avoid error and insert character at the end."
  (when (memq this-command '(self-insert-command
                             y-or-n-p-insert-y
                             y-or-n-p-insert-n))
    (setq this-command
          `(lambda () (interactive)
             (setq this-command (quote ,this-command))
             (condition-case-unless-debug _
                 (call-interactively (quote ,this-command))
               (text-read-only (goto-char (point-max))
                               ,(cl-case this-command
                                  (self-insert-command
                                   '(self-insert-command
                                     (prefix-numeric-value current-prefix-arg)
                                     last-command-event))
                                  (otherwise
                                   (list this-command))))
               ((beginning-of-buffer
                 end-of-buffer)
                (goto-char (point-max)))
               (end-of-buffer (goto-char (point-max))))))))

(defun minibuffer-try-add-hooks ()
  (add-hook 'pre-command-hook 'minibuffer-try-pre))
(defun minibuffer-try-remove-hooks ()
  (remove-hook 'pre-command-hook 'minibuffer-try-pre))

(add-hook 'minibuffer-setup-hook 'minibuffer-try-add-hooks)
(add-hook 'minibuffer-exit-hook 'minibuffer-try-remove-hooks)

;;;;;;;;;;;;;;;
;; Kill ring ;;
;;;;;;;;;;;;;;;
(defun kill-ring-insert ()
  (interactive)
  (let ((to_insert (completing-read "Yank: "
                                    (cl-delete-duplicates kill-ring :test #'equal)
                                    nil t)))
    (when (and to_insert (region-active-p))
      ;; the currently highlighted section is to be replaced by the yank
      (delete-region (region-beginning) (region-end)))
    (insert to_insert)))

;;;;;;;;;;;;
;; Cycles ;;
;;;;;;;;;;;;
(require 'rotate-text)
(require 'string-inflection)

(defun rotate-or-inflection (arg)
  (interactive (list (if (consp current-prefix-arg)
                         -1
                       (prefix-numeric-value current-prefix-arg))))
  (condition-case nil
      (rotate-text arg)
    (error (string-inflection-all-cycle))))

(defun scroll-down-or-completions (&optional arg)
  (interactive "^P")
  (if (get-buffer-window "*Completions*")
      (switch-to-completions)
    (scroll-down-command arg)))
;;;;;;;;;;
;; Sexp ;;
;;;;;;;;;;
(defun sp-or-forward-sexp (&optional arg)
  (interactive "^p")
  (if (fboundp 'sp-forward-sexp)
      (sp-forward-sexp arg)
    (forward-sexp arg)))

(defun sp-or-backward-sexp (&optional arg)
  (interactive "^p")
  (if (fboundp 'sp-backward-sexp)
      (sp-backward-sexp arg)
    (backward-sexp arg)))

(defun sp-or-backward-kill-sexp (&optional arg)
  (interactive "^p")
  (if (fboundp 'sp-backward-sexp)
      (let ((opoint (point)))
        (sp-backward-sexp arg)
        (kill-region opoint (point)))
    (backward-kill-sexp arg)))

(defun surround-delete-pair (&optional arg escape-strings no-syntax-crossing)
  (interactive "^p\nd\nd")
  (save-excursion
    (backward-up-list arg escape-strings no-syntax-crossing)
    (delete-pair 1)))

(defun surround-change-pair (&optional arg escape-strings no-syntax-crossing)
  (interactive "^p\nd\nd")
  (let ((alist '((?\( . ?\))
                 (?\[ . ?\])
                 (?{ . ?})
                 (?< . ?>)
                 (?¡ . ?!)
                 (?¿ . ??)
                 (?« . ?»)
                 (?“ . ?”)))
        (char (read-char "Left delimiter: ")))
   (save-excursion
    (backward-up-list arg escape-strings no-syntax-crossing)
    (save-excursion
      (forward-sexp 1)
      (delete-char -1)
      (insert (or (alist-get char alist nil nil 'char-equal)
                  char)))
    (delete-char 1)
    (insert char))))

;;;;;;;;;;;;;;;;;;;;;
;; Keyboard macros ;;
;;;;;;;;;;;;;;;;;;;;;
(defun select-kbd-macro ()
  (interactive)
  (unless (kmacro-ring-empty-p)
    (let* ((ring-alist (mapcar (lambda (ring-item)
                                 (cons (format-kbd-macro (car ring-item))
                                       (car ring-item)))
                               kmacro-ring))
           (kbd-macro (cdr (assoc (completing-read
                                   "Select kbd macro: "
                                   ring-alist nil t nil nil
                                   (format-kbd-macro last-kbd-macro)) ring-alist))))
      (when kbd-macro
        (cl-delete-if (lambda (ring-item) (equal kbd-macro (car ring-item))) kmacro-ring)
        (kmacro-push-ring)
        (setq last-kbd-macro kbd-macro)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Next-Previous thing like this ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'thing-cmds)
(defvar thgcmd--last-like-this nil)

(defun buffer-substring-no-properties-thing (thing)
  (let* ((use-near-p  (and (boundp 'thgcmd-use-nearest-thing-flag)
                           thgcmd-use-nearest-thing-flag))
         (bds         (if use-near-p
                          (tap-bounds-of-thing-nearest-point
                           (intern thing))
                        (thgcmd-bounds-of-thing-at-point
                         (intern thing))))
         (start       (car bds))
         (end         (cdr bds)))
    (cond ((and start  end)
           (buffer-substring-no-properties start end))
          (t
           (message "No `%s' %s point"
                    thing (if use-near-p 'near 'at))
           (setq deactivate-mark  nil)
           nil))))

(defun next-thing-like-this (this)
  (interactive (list
                (cond
                 ((and current-prefix-arg
                       thgcmd--last-like-this)
                  thgcmd--last-like-this)
                 ((memq last-command '(next-thing-like-this
                                       previous-thing-like-this))
                  (buffer-substring-no-properties-thing
                   (symbol-name thgcmd-last-thing-type)))
                 (t
                  (buffer-substring-no-properties-thing
                   (let* ((icicle-sort-function  nil)
                          (def (symbol-name thgcmd-last-thing-type))
                          (thing
                           (completing-read
                            (concat "Thing (" def "): ")
                            (thgcmd-things-alist) nil t nil nil
                            def)))
                     (setq thgcmd-last-thing-type  (intern thing))
                     thing))))))
  (when this
    (setq thgcmd--last-like-this this)
    (if (re-search-forward "\\_>" nil t)
        (goto-char (1- (match-end 0))))
    (if (null (re-search-forward (format "\\_<%s\\_>"
                                         (regexp-quote this)) nil t))
        (message "No next match")
      (goto-char (match-beginning 0))
      (mapc (lambda (ov)
              (overlay-put ov 'invisible nil))
            (overlays-at (point))))))

(defun previous-thing-like-this (this)
  (interactive (list
                (cond
                 ((and current-prefix-arg
                       thgcmd--last-like-this)
                  thgcmd--last-like-this)
                 ((memq last-command '(next-thing-like-this
                                       previous-thing-like-this))
                  (buffer-substring-no-properties-thing
                   (symbol-name thgcmd-last-thing-type)))
                 (t
                  (buffer-substring-no-properties-thing
                   (let* ((icicle-sort-function  nil)
                          (def (symbol-name thgcmd-last-thing-type))
                          (thing
                           (completing-read
                            (concat "Thing (" def "): ")
                            (thgcmd-things-alist) nil t nil nil
                            def)))
                     (setq thgcmd-last-thing-type  (intern thing))
                     thing))))))
  (when this
    (setq thgcmd--last-like-this this)
    (if (null (re-search-backward (format "\\_<%s\\_>"
                                          (regexp-quote this)) nil t))
        (message "No previous match")
      (goto-char (match-beginning 0))
      (mapc (lambda (ov)
              (overlay-put ov 'invisible nil))
            (overlays-at (point))))))

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
;; (global-set-key (kbd "M-y") #'kill-ring-insert)
(global-set-key (kbd "C-M-º") #'indent-region)
(global-set-key (kbd "M-s º") #'indent-region)
(global-set-key (kbd "C-x <C-tab>") #'align-regexp)
(global-set-key (kbd "C-:") 'next-thing-like-this)
(global-set-key (kbd "C-;") 'previous-thing-like-this)
(global-set-key (kbd "C-(") 'surround-change-pair)
(global-set-key (kbd "C-)") 'surround-delete-pair)
(define-key prog-mode-map (kbd "C-c C-f") #'rotate-text)
(define-key prog-mode-map (kbd "C-c C-b") #'rotate-text-backward)
(define-key prog-mode-map (kbd "C-c C-u") #'string-inflection-all-cycle)
;; (global-set-key (kbd "ŧ") #'rotate-text)                            ;; AltGr-t
;; (global-set-key (kbd "→") #'string-inflection-all-cycle)            ;; AltGr-i
;; (global-set-key (kbd "ħ") #'pulse-momentary-highlight-current-line) ;; AltGr-h
;; (global-set-key (kbd "½") #'query-replace-regexp)                   ;; AltGr-5
;; (global-set-key (kbd "ð") #'kill-sexp)                              ;; AltGr-d
;; (global-set-key (kbd "ĸ") #'kill-whole-line)                        ;; AltGr-k
;; (global-set-key (kbd "“") #'scroll-other-window)                    ;; AltGr-v
;; (global-set-key (kbd "”") 'sp-or-backward-sexp)                     ;; AltGr-b
;; (global-set-key (kbd "đ") 'sp-or-forward-sexp)                      ;; AltGr-f
;; (global-set-key (kbd "€") 'end-of-defun)                            ;; AltGr-e
;; (global-set-key (kbd "æ") 'beginning-of-defun)                      ;; AltGr-a
(global-set-key (kbd "M-s 7 d") #'toggle-debug-on-error)
(global-set-key (kbd "M-s 7 b") #'toggle-enable-multibyte-characters)
(global-set-key (kbd "M-s 7 c") #'toggle-buffer-coding-system)
(global-set-key (kbd "M-s 7 i") #'toggle-case-fold-search)
(global-set-key (kbd "M-s k w") #'backward-kill-word)
(global-set-key (kbd "M-n") #'forward-paragraph)
(global-set-key (kbd "M-p") #'backward-paragraph)
(global-set-key (kbd "M-v") 'scroll-down-or-completions)
(global-set-key (kbd "C-<left>") #'left-word)
(global-set-key (kbd "C-<right>") #'right-word)
(global-set-key (kbd "<S-delete>") #'kill-sexp)
(global-set-key (kbd "<C-M-backspace>") #'sp-or-backward-kill-sexp)
;; (global-set-key (kbd "M-s DEL") #'backward-kill-sexp)
;; (global-set-key (kbd "S-<delete>") #'kill-sexp)
(global-set-key [?\C-x ?u] #'undo-propose)
(global-set-key (kbd "M-s <deletechar>") #'kill-sexp)
(global-set-key (kbd "C-*") #'duplicate-current-line-or-region)
(global-set-key (kbd "M-s *") #'duplicate-current-line-or-region)
;; (global-set-key (kbd "M-s SPC") #'set-mark-command)
(global-set-key (kbd "M-s SPC") #'fixup-whitespace)
(global-set-key (kbd "C-S-<backspace>") #'kill-whole-line)
(global-set-key (kbd "M-s k l") #'kill-whole-line)
(global-set-key (kbd "M-s <insertchar>") #'kill-whole-line)
(global-set-key (kbd "<M-dead-circumflex>") #'delete-indentation)
(global-set-key (kbd "S-<next>") #'scroll-other-window)
(global-set-key (kbd "S-<prior>") #'scroll-other-window-down)
(global-set-key (kbd "C-<next>") #'hscroll-right)
(global-set-key (kbd "M-s <next>") #'hscroll-right)
(global-set-key (kbd "C-x >") #'hscroll-right)
(global-set-key (kbd "C-<prior>") #'hscroll-left)
(global-set-key (kbd "M-s <prior>") #'hscroll-left)
(global-set-key (kbd "C-x <") #'hscroll-left)
(global-set-key (kbd "M-<right>") #'forward-alt)
(global-set-key (kbd "M-<left>") #'backward-alt)
(global-set-key (kbd "C-ñ") 'find-next-unsafe-char)
(global-set-key (kbd "C-x C-k C-i") 'select-kbd-macro)
(global-set-key (kbd "C-x M-l") 'recenter-horizontal)
;; Case
(global-set-key (kbd "M-c") #'capitalize-dwim)
(global-set-key (kbd "M-l") #'downcase-dwim)
(global-set-key (kbd "M-u") #'upcase-dwim)
;; thingatpt+
(global-set-key (kbd "C-M-SPC") #'select-thing)
(global-set-key (kbd "M-s m") #'select-things)
(global-set-key (kbd "M-s 6 s") #'cycle-select-something)
(global-set-key (kbd "M-s l") #'select-enclosing-list)
(global-set-key (kbd "M-s f") #'select-enclosing-list-forward)
(global-set-key (kbd "M-s b") #'select-enclosing-list-backward)
(global-set-key (kbd "M-s n") #'next-visible-thing-repeat)
(global-set-key (kbd "M-s p") #'previous-visible-thing-repeat)
(global-set-key (kbd "C-c l") #'display-line-numbers-mode)

(global-set-key (kbd "M-g f") #'find-dired)

(define-key minibuffer-local-map (kbd "C-c C-l") 'helm-minibuffer-history)

;; Usa el clipboard del sistema
;; (global-set-key [(shift delete)] 'clipboard-kill-region)
;; (global-set-key [(control insert)] 'clipboard-kill-ring-save)
;; (global-set-key [(shift insert)] 'clipboard-yank)

(setq revert-without-query '("\\.calc\\.py\\'"))

(defun buffers-from-file (&optional frame)
  "Get buffers from file in FRAME."
  (let ((tmp-list '()))
    (dolist (buffer (buffer-list frame))
      (when (buffer-file-name buffer)
        (setq tmp-list (cons buffer tmp-list))))
    tmp-list))

(defun kill-buffers-from-file (&optional frame)
  "Kill buffers from file in FRAME."
  (interactive (list (if current-prefix-arg
                         (read-from-minibuffer "Frame: ")
                       nil)))
  (let ((file-list (buffers-from-file frame)))
    (when file-list
      (mapc #'kill-buffer file-list))))

(defun kill-buffer-or-buffers-from-file (&optional frame)
  "Kill buffers or buffers from file in FRAME."
  (interactive (list (if current-prefix-arg
                         (selected-frame)
                       nil)))
  (if frame
      (kill-buffers-from-file frame)
    (kill-buffer)))

(defun buffers-with-window (&optional frame)
  "Get buffers with window in FRAME."
  (let ((tmp-list '()))
    (dolist (window (window-list frame))
      (let ((buffer (window-buffer window)))
        (when (buffer-file-name buffer)
          (setq tmp-list (cons buffer tmp-list)))))
    (delete-dups tmp-list)))

;; Kill all file buffers with window
(defun kill-buffers-with-window (&optional frame)
  "Kill all buffers from file with window in FRAME."
  (interactive (list (if current-prefix-arg
                         (read-from-minibuffer "Frame: ")
                       nil)))
  (let ((file-list (buffers-with-window frame)))
    (when file-list
      (mapc 'kill-buffer file-list))))

;; Kill buffer if you wish when close frame.
(defun kill-buffers-group-choice (&optional frame)
  "Kill buffers if you wish when close FRAME."
  (interactive (list (if current-prefix-arg
                         (read-from-minibuffer "Frame: ")
                       nil)))
  (when (buffers-with-window)
    (cl-case (read-char-choice "Kill buffers [c]urrent/[f]iles/[w]indows/[n]othing? "
                            (append "cCfFwWnNqQ" nil))
      ((?c ?C)
       (kill-buffer))
      ((?f ?F)
       (kill-buffers-from-file frame))
      ((?w ?W)
       (kill-buffers-with-window frame)))))

(defun list-all-buffers (&optional files-only)
  "Display a list of names of existing buffers.
The list is displayed in a buffer named `*Buffer List*'.
Non-null optional arg FILES-ONLY means mention only file buffers.

For more information, see the function `buffer-menu'."
  (interactive "P")
  (select-window
   (display-buffer (list-buffers-noselect files-only (buffer-list)))))

(define-key global-map [remap list-buffers] 'ibuffer)
(define-key global-map (kbd "C-x B") 'ibuffer-list-buffers)

;; display left rotating anticlockwise
(defun display-buffer-tiling-anticlockwise (buffer alist)
  (rotate-frame-anticlockwise)
  (display-buffer-in-direction buffer (cons '(direction . leftmost) alist)))

;; display right
(defun display-buffer-help-condition (buffer-name action)
  (with-current-buffer buffer-name
    (derived-mode-p 'help-mode)))

(defun display-buffer-at-right (buffer alist)
  (display-buffer-in-direction buffer (cons '(direction . rightmost) alist)))

;; (push '(display-buffer-help-condition
;;         display-buffer-at-right)
;;       display-buffer-alist)

;; display bottom
(defun display-buffer-term-condition (buffer-name action)
  (with-current-buffer buffer-name
    (derived-mode-p 'term-mode 'shell-mode 'eshell-mode
                    'docker-container-mode)))

;; (push '(display-buffer-term-condition
;;         display-buffer-at-bottom)
;;       display-buffer-alist)

;; display left
(defun display-buffer-main-condition (buffer-name action)
  (with-current-buffer buffer-name
    (derived-mode-p 'prog-mode 'org-mode)))

(defun display-buffer-at-left (buffer alist)
  (display-buffer-in-direction buffer (cons '(direction . leftmost) alist)))

;; (push '(display-buffer-main-condition
;;         display-buffer-at-left)
;;       display-buffer-alist)

;; split window
(defun split-window-mode-sensibly (&optional window)
  (or window (setq window (selected-window)))
  (cond
   ((with-selected-window window
      (derived-mode-p 'prog-mode 'org-mode 'help-mode))
    (let ((split-height-threshold nil)
          (split-width-threshold 140))
      (split-window-sensibly window)))
   ((with-selected-window window
      (derived-mode-p 'term-mode 'shell-mode 'eshell-mode
                      'docker-container-mode))
    (let ((split-height-threshold 20))
      (split-window-sensibly window)))
   (t
    (split-window-sensibly window))))

(defvar hscroll-aggressive nil)
(setq fit-window-to-buffer-horizontally nil
      register-preview-delay nil
      split-window-preferred-function 'split-window-mode-sensibly
      message-truncate-lines nil
      ;; Vertical Scroll
      ;; scroll-preserve-screen-position 'always
      ;; scroll-margin 2
      ;; scroll-step 2
      ;; [ Nil means display update is paused when input is detected
      ;; obsolete variable, annoying hold down key if nil
      ;; redisplay-dont-pause t
      ;; ]
      ;; Dangerous, annoying scroll holding next-line
      ;; fast-but-imprecise-scrolling t
      ;; mouse-wheel-progressive-speed nil
      ;; > 100 Never recenter point
      ;; scroll-conservatively 101
      ;; Horizontal Scroll
      ;;hscroll-margin 2
      ;;hscroll-step (* 2 hscroll-margin)
      auto-window-vscroll nil)

(add-hook 'term-mode-hook
          (lambda ()
            (set (make-local-variable 'scroll-margin) 0)))

(defun toggle-message-truncate-lines ()
  "Toggle truncate lines in messages."
  (interactive)
  (setq message-truncate-lines (not message-truncate-lines)))

(defun toggle-hscroll-aggressive ()
  "Toggle hscroll aggressive."
  (interactive)
  (if hscroll-aggressive
      (progn
        (setq  hscroll-margin 2
               hscroll-step 1
               hscroll-aggressive nil))
    (progn
      (setq  hscroll-margin 10
             hscroll-step 25
             hscroll-aggressive t))))
;; [ filter annoying messages
;; (defvar message-filter-regexp-list '("^Starting new Ispell process \\[.+\\] \\.\\.\\.$"
;;                                      "^Ispell process killed$")
;;   "filter formatted message string to remove noisy messages")
;; (defadvice message (around message-filter-by-regexp activate)
;;   (if (not (ad-get-arg 0))
;;       ad-do-it
;;     (let ((formatted-string (apply 'format (ad-get-args 0))))
;;       (if (and (stringp formatted-string)
;;                (some (lambda (re) (string-match re formatted-string)) message-filter-regexp-list))
;;           (save-excursion
;;             (set-buffer "*Messages*")
;;             (goto-char (point-max))
;;             (insert formatted-string "\n"))
;;         (progn
;;           (ad-set-args 0 `("%s" ,formatted-string))
;;           ad-do-it)))))
;; ]
;; message timestamp
;; thanks to: https://emacs.stackexchange.com/questions/32150/how-to-add-a-timestamp-to-each-entry-in-emacs-messages-buffer
(defun message-timestamp-advice (format-string &rest args)
  "Advice to run before `message' with FORMAT-STRING ARGS that prepend a timestamp to each message."
  (unless (string-equal format-string "%s%s")
    (let ((deactivate-mark nil)
          (inhibit-read-only t))
      (with-current-buffer "*Messages*"
        (goto-char (point-max))
        (if (not (bolp))
            (newline))
        (let* ((nowtime (current-time))
               (now-ms (nth 2 nowtime)))
          (insert (format-time-string "[%Y-%m-%d %T" nowtime)
                  (format ".%06d]" now-ms) " "))))))
(defvar message-advice-timestamp nil)
(defun advice-message-timestamp ()
  (interactive)
  (set 'message-advice-timestamp t))
(defun unadvice-message-timestamp ()
  (interactive)
  (set 'message-advice-timestamp nil))
;; not necesary, included in message-filter
;; (advice-add 'message :before 'message-timestamp-advice)
(defun signal-timestamp-advice (error-symbol data)
  "Advice to run before `signal' with ERROR-SYMBOL DATA that prepend a timestamp to each message."
  (let ((deactivate-mark nil)
        (inhibit-read-only t))
    (with-current-buffer "*Messages*"
      (goto-char (point-max))
      (if (not (bolp))
          (newline))
      (let* ((nowtime (current-time))
             (now-ms (nth 2 nowtime)))
        (insert (format-time-string "<%Y-%m-%d %T" nowtime)
                (format ".%06d>" now-ms) " " (if data (format "%s" data)))))))
(defun advice-signal-timestamp ()
  (interactive)
  (advice-add 'signal :before 'signal-timestamp-advice))
(defun unadvice-signal-timestamp ()
  (interactive)
  (advice-remove 'signal 'signal-timestamp-advice))
;; Truncate lines in messages and filter messages buffer
(defvar message-nillog-filter-functions '()) ;; (lambda (str) (string-match-p "oading" str))
(defvar message-inhibit-filter-functions '())
(defun message-filter (orig-fun msg &rest args)
  "Advice ORIG-FUN with args MSG and ARGS.  Filter arguments."
  (if (and
       message-log-max
       (not inhibit-message)
       msg)
      (let ((msg-str (apply #'format msg args)))
        (let ((inhibit-message
               (and
                message-inhibit-filter-functions
                (cl-some #'(lambda (func)
                             (funcall func msg-str)) message-inhibit-filter-functions)))
              (message-log-max
               (if (and
                    message-nillog-filter-functions
                    (cl-some #'(lambda (func)
                                 (funcall func msg-str)) message-nillog-filter-functions))
                   nil
                 message-log-max)))
          (if message-advice-timestamp (message-timestamp-advice msg))
          (apply orig-fun msg args)))
    (apply orig-fun msg args)))
;;(advice-add 'message :around #'message-filter)

;; Don't show on windows buffers currently showed
;; (defun diplay-buffer-advice (orig-fun buffer-or-name &optional action frame)
;;   (let ((window (funcall orig-fun buffer-or-name action frame)))
;;     (when (and (windowp window)
;;                (window-live-p window))
;;       (select-window window))))
;; (advice-add 'display-buffer :around 'diplay-buffer-advice)

;; (with-selected-window window
;;   (pulse-momentary-highlight-region (window-start window)
;;                                     (window-end window)))

(defun display-buffer-if-not-showed (orig-fun buffer-or-name &rest args)
  "Advice ORIG-FUN with args BUFFER-OR-NAME and ARGS.
Don't show on windows buffers currently showed."
  (let ((window (get-buffer-window buffer-or-name 0)))
    (if (windowp window)
        window
      (apply orig-fun buffer-or-name args))))
(advice-add 'display-buffer :around #'display-buffer-if-not-showed)

;; Thanks to: https://superuser.com/questions/132225/how-to-get-back-to-an-active-minibuffer-prompt-in-emacs-without-the-mouse
(defun switch-to-minibuffer-window ()
  "switch to minibuffer window (if active)"
  (interactive)
  (if (and (bound-and-true-p mini-frame-frame)
           (frame-live-p mini-frame-frame)
           (frame-visible-p mini-frame-frame))
      (select-frame mini-frame-frame)
    (when-let (minibuffer-window (active-minibuffer-window))
      (if (window-minibuffer-p)
          (switch-to-completions)
        (select-frame-set-input-focus (window-frame minibuffer-window))
        (select-window minibuffer-window)))))

;; undo and redo window distributions
(setq winner-dont-bind-my-keys t)
(winner-mode)

(require 'windmove)
;;(windmove-default-keybindings 'meta)

(require 'find-file)
(defun switch-to-other-buffer ()
  "Switch to dual buffer whether exists."
  (interactive)
  (let ((ignore ff-ignore-include)
        (create ff-always-try-to-create))
    (setq ff-ignore-include t)
    (setq ff-always-try-to-create nil)
    (unless (or (not (fboundp 'ff-find-the-other-file))
                (ff-find-the-other-file))
      (let ((file-list (buffers-from-file)))
        (if file-list
            (switch-to-buffer (cl-first file-list))
          (switch-to-prev-buffer))))
    (setq ff-ignore-include ignore)
    (setq ff-always-try-to-create create)))

(defun vsplit-last-buffer (&optional size)
  "Split last buffer vertically."
  (interactive "P")
  (split-window-vertically size)
  (other-window 1)
  (switch-to-other-buffer))

(defun hsplit-last-buffer (&optional size)
  "Split last buffer horizontally."
  (interactive "P")
  (split-window-horizontally size)
  (other-window 1)
  (switch-to-other-buffer))

;; Desbalancea el split vertical
;;(defadvice split-window-vertically
;;   (after my-window-splitting-advice activate)
;;    (enlarge-window (truncate (/ (window-body-height) 2))))

(defun halve-other-window-height ()
  "Expand current window to use half of the other window's lines."
  (interactive)
  (balance-windows)
  (enlarge-window (truncate (/ (window-height) 2))))

;; use Shift+arrow_keys to move cursor around split panes
;;(windmove-default-keybindings)

;; when cursor is on edge, move to the other side, as in a toroidal space
;;(setq windmove-wrap-around t )

(defun window-dedicate-this ()
  "Dedicate focus window."
  (interactive)
  (set-window-dedicated-p (selected-window) t))

(defun window-undedicate-this ()
  "Dedicate focus window."
  (interactive)
  (set-window-dedicated-p (selected-window) nil))

(defun window-dedicate-all (&optional frame)
  "Dedicate all windows in the presente FRAME."
  (interactive)
  (dolist (window (window-list frame))
    (set-window-dedicated-p window t)))

(defun window-undedicate-all (&optional frame)
  "Dedicate all windows in the presente FRAME."
  (interactive)
  (dolist (window (window-list frame))
    (set-window-dedicated-p window nil)))

;; Switch window
(defun switch-to-window (arg)
  (interactive "P")
  (let ((windows (pcase arg
                   ('()
                    (window-list))
                   ('(4)
                    (apply #'append (mapcar #'window-list (visible-frame-list))))
                   ('(16)
                    (apply #'append (mapcar #'window-list (frame-list)))))))
    (setq windows (delq (selected-window) windows))
    (pcase (length windows)
      (0)
      (1 (select-window (car windows)))
      (_
       (let* ((windows-strings (mapcar #'buffer-name (mapcar #'window-buffer windows)))
              (windows-alist (cl-mapcar #'cons windows-strings windows))
              (option (completing-read
                       "Switch to: "
                       `(,@windows-strings windmove-left windmove-right windmove-up windmove-down)
                       nil t nil nil (car windows-strings)))
              (window-assoc (assoc option windows-alist)))
         (if window-assoc
             (select-window (cdr window-assoc))
           (funcall (intern option))))))))

;; window resize
(defun window-resize-width (arg &optional window max-width min-width preserve-size)
  "ARG nil Fit WINDOW according to its buffer's width.
WINDOW, MAX-WIDTH and MIN-WIDTH have the same meaning as in
`fit-window-to-buffer'.

ARG non-nil resize window to ARG width."
  (interactive "P")
  (if arg
      (window-resize (or window (selected-window)) (- arg (window-width)) t)
    (let ((fit-window-to-buffer-horizontally 'only))
      (fit-window-to-buffer window nil nil max-width min-width preserve-size))))

(defun window-resize-height (arg &optional window max-height min-height preserve-size)
  "ARG nil Fit WINDOW according to its buffer's height.
WINDOW, MAX-HEIGHT and MIN-HEIGHT have the same meaning as in
`fit-window-to-buffer'.

ARG non-nil resize window to ARG height."
  (interactive "P")
  (if arg
      (window-resize (or window (selected-window)) (- arg (window-height)))
    (let ((fit-window-to-buffer-horizontally nil))
      (fit-window-to-buffer window max-height min-height nil nil preserve-size))))

(defun window-preserve-width (&optional window)
  (interactive)
  (window-preserve-size window t t))

(defun window-resize-equal (arg size)
  (interactive "P\nnSize: ")
  (let ((window (selected-window))
        (horizontal (not arg)))
    (window-resize window (- (if (< 0 size) size 80)
                             (window-size window horizontal))
                   horizontal)))

(defun window-resize-delta (arg delta)
  (interactive "P\nnDelta: ")
  (window-resize (selected-window) delta (not arg)))

(defun window-resize-factor (arg factor)
  (interactive "P\nnFactor: ")
  (let ((window (selected-window))
        (horizontal (not arg)))
    (window-resize window (round
                           (* (window-size window horizontal)
                              (1- factor)))
                   horizontal)))

;; autoresize
(setq resize-mini-windows t
      max-mini-window-height 0.7)
(defvar-local window-autoresize-size nil)

(defun window-autoresize (window)
  (when (and window-autoresize-size
             (not (active-minibuffer-window)))
    (let ((width-heigth (cdr (assoc (if (eq window (selected-window))
                                        'selected
                                      'unselected)
                                    window-autoresize-size))))
      (if width-heigth
          (let ((width (car width-heigth))
                (height (cdr width-heigth)))
            (if (numberp width)
                (let ((delta-width (- width (window-size window t))))
                  (if (and (/= 0 delta-width)
                           (/= 0 (setq delta-width
                                       (window-resizable
                                        window
                                        delta-width
                                        t))))
                      (window-resize window
                                     delta-width
                                     t))))
            (if (numberp height)
                (let ((delta-height (- height (window-size window))))
                  (if (and (/= 0 delta-height)
                           (/= 0 (setq delta-height
                                       (window-resizable
                                        window
                                        delta-height))))
                      (window-resize window
                                     delta-height)))))))))
(add-hook 'pre-redisplay-functions 'window-autoresize)

(defun window-autoresize-set-size (selected-width selected-height
                                                  unselected-width unselected-height)
  (interactive
   "xWidth selected: \nxHeight selected: \nxWidth unselected: \nxHeight unselected: ")
  (setq window-autoresize-size
        (list (cons 'selected (cons selected-width selected-height))
              (cons 'unselected (cons unselected-width unselected-height)))))

(defun window-autoresize-set-default (unselected-width)
  (interactive "p")
  (cond
   ((or (derived-mode-p 'org-mode)
        (derived-mode-p 'python-mode))
    (let ((numbers-margin (if display-line-numbers
                              (if (numberp display-line-numbers-width)
                                  display-line-numbers-width
                                3)
                            0)))
      (window-autoresize-set-size
       (+ 82 numbers-margin)
       30
       (if (<= unselected-width 1)
           (+ 19 numbers-margin)
         (+ 2 unselected-width numbers-margin))
       4)))))

(defun window-autoresize-unset ()
  (interactive)
  (setq window-autoresize-size nil))

;; [ Visual line mode
(defun toggle-continuation-lines (&optional arg)
  (interactive "P")
  (if (if (numberp arg)
          (< 0 arg)
        (or visual-line-mode
            (null truncate-lines)))
      (progn
        (visual-line-mode -1)
        (toggle-truncate-lines 1))
    (unless (default-value 'truncate-lines)
      (toggle-truncate-lines -1))
    (when global-visual-line-mode
      (visual-line-mode 1))))

(with-eval-after-load 'simple
  (setq minor-mode-alist (assq-delete-all 'visual-line-mode minor-mode-alist))

  ;; slow performance
  ;; (global-visual-line-mode 1)
  (add-hook 'minibuffer-setup-hook 'visual-line-mode))
;; ]

;; winner
(require 'winner)
(with-eval-after-load 'hydra
  (defhydra hydra-win (:foreign-keys warn)
    "WIN"
    ("C-<right>" (lambda () (interactive)
                   (enlarge-window-horizontally 1)
                   (message "Width: %i" (window-width))))
    ("S-<right>" (lambda () (interactive)
                   (enlarge-window-horizontally 10)
                   (message "Width: %i" (window-width))) "↔+")
    ("C-<left>" (lambda () (interactive)
                  (shrink-window-horizontally 1)
                  (message "Width: %i" (window-width))))
    ("S-<left>" (lambda () (interactive)
                  (shrink-window-horizontally 10)
                  (message "Width: %i" (window-width))) "↔-")
    ("C-<up>" (lambda () (interactive)
                (enlarge-window 1)
                (message "Height: %i" (window-height))))
    ("S-<up>" (lambda () (interactive)
                (enlarge-window 10)
                (message "Height: %i" (window-height))) "↕+")
    ("C-<down>" (lambda () (interactive)
                  (shrink-window 1)
                  (message "Height: %i" (window-height))))
    ("S-<down>" (lambda () (interactive)
                  (shrink-window 10)
                  (message "Height: %i" (window-height))) "↕-")
    ("C-p" winner-undo "undo")
    ("C-n" winner-redo "redo")
    ("M-q" nil "quit"))
  (global-set-key (kbd "C-c w m") 'hydra-win/body))
(global-set-key (kbd "M-s 0") 'switch-to-minibuffer-window)
(global-set-key (kbd "M-s 7 w") 'toggle-continuation-lines)
(global-set-key (kbd "M-s 7 v") #'visual-line-mode)
(global-set-key (kbd "C-x `") 'shrink-window)

;; (setq initial-frame-alist (nconc '((minibuffer . only)) initial-frame-alist)
;;       default-frame-alist (nconc '((minibuffer . nil)) default-frame-alist)
;;       minibuffer-auto-raise t)
;; (add-hook 'minibuffer-exit-hook 'lower-frame)
;; Ajusta el tamaño de la ventana a la resolución.
;; (defun set-frame-size-according-to-resolution ()
;;   (interactive)
;;   (if window-system
;;   (progn
;;     ;; use 100 char wide window for largeish displays
;;     ;; and smaller 80 column windows for smaller displays
;;     ;; pick whatever numbers make sense for you
;;     (if (> (x-display-pixel-width) 1280)
;;            (add-to-list 'default-frame-alist (cons 'width 100))
;;            (add-to-list 'default-frame-alist (cons 'width 80)))
;;     ;; for the height, subtract a couple hundred pixels
;;     ;; from the screen height (for panels, menubars and
;;     ;; whatnot), then divide by the height of a char to
;;     ;; get the height we want
;;     (add-to-list 'default-frame-alist
;;          (cons 'height (/ (- (x-display-pixel-height) 250)
;;                              (+ (frame-char-height) 1)))))))
;;
;; (set-frame-size-according-to-resolution)

;; Call last keyboard macro in windows
(defun kmacro-call-other-windows-all-frames (window &optional all-frames)
  "Call last keyboard macro in windows other than WINDOW.

Optional argument ALL-FRAMES nil or omitted means consider all windows
on WINDOW’s frame, plus the minibuffer window if specified by the
MINIBUF argument.  If the minibuffer counts, consider all windows on all
frames that share that minibuffer too.  The following non-nil values of
ALL-FRAMES have special meanings:

- t means consider all windows on all existing frames.

- ‘visible’ means consider all windows on all visible frames.

- 0 (the number ero) means consider all windows on all visible and
  iconified frames.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on WINDOW’s frame and no
others."
  (interactive (list (selected-window) 'visible))
  (save-selected-window
    (dolist (other-window (cdr (window-list-1 window 0 all-frames)))
      (select-window other-window)
      (kmacro-call-macro 1))))

(defun kmacro-call-all-windows-all-frames (&optional all-frames)
  "Call last keyboard macro in windows other than WINDOW.

Optional argument ALL-FRAMES nil or omitted means consider all windows
on WINDOW’s frame, plus the minibuffer window if specified by the
MINIBUF argument.  If the minibuffer counts, consider all windows on all
frames that share that minibuffer too.  The following non-nil values of
ALL-FRAMES have special meanings:

- t means consider all windows on all existing frames.

- ‘visible’ means consider all windows on all visible frames.

- 0 (the number zero) means consider all windows on all visible and
  iconified frames.

- A frame means consider all windows on that frame only.

Anything else means consider all windows on WINDOW’s frame and no
others."
  (interactive (list 'visible))
  (save-selected-window
    (dolist (window (window-list-1 nil 0 all-frames))
      (select-window window)
      (kmacro-call-macro 1))))

(defun kmacro-call-other-windows-in-frame (&optional frame window)
  "Call last keyboard macro in FRAME's windows other than WINDOW."
  (interactive (list (selected-frame) (selected-window)))
  (save-selected-window
    (dolist (other-window (cdr (window-list frame 0 window)))
      (select-window other-window)
      (kmacro-call-macro 1))))

(defun kmacro-call-all-windows-in-frame (&optional frame)
  "Call last keyboard macro in FRAME's windows."
  (interactive (list (selected-frame)))
  (save-selected-window
    (dolist (window (window-list frame 0))
      (select-window window)
      (kmacro-call-macro 1))))

;;(add-hook 'delete-frame-functions #'kill-buffers-group-choice)
(require 'server)
(defun save-buffers-kill-terminal-with-choice (&optional arg)
  "Exit Emacs with ARG option."
  (interactive "P")
  (cond
   ((not (frame-parameter nil 'client))
    (save-buffers-kill-emacs arg))
   ((equal arg '(4))
    (save-buffers-kill-terminal arg))
   ((equal arg '(16))
    (save-buffers-kill-emacs arg))
   (t
    (progn
      (save-some-buffers arg)
      (kill-buffers-group-choice)
      (let ((proc (frame-parameter nil 'client)))
        (cond ((eq proc 'nowait)
               ;; Nowait frames have no client buffer list.
               (if (cdr (frame-list))
                   (delete-frame)
                 ;; If we're the last frame standing, kill Emacs.
                 (save-buffers-kill-emacs arg)))
              ((processp proc)
               (let ((buffers (process-get proc 'buffers)))
                 ;; If client is bufferless, emulate a normal Emacs exit
                 ;; and offer to save all buffers.  Otherwise, offer to
                 ;; save only the buffers belonging to the client.
                 (save-some-buffers
                  arg (if buffers
                          (lambda () (memq (current-buffer) buffers))
                        t))
                 (server-delete-client proc)))
              (t (error "Invalid client frame"))))))))

(require 'transpose-frame)
;; [ Frames layouts
(defun shell-3-window-frame ()
  "Development window format."
  (interactive)
  (delete-other-windows)
  (split-window-horizontally)
  (split-window-vertically)
  (shrink-window (truncate (/ (* (window-height) 2) 5)))
  (other-window 1)
  (other-window 1)
  (shell)
  (other-window 2)
  (switch-to-other-buffer))

(defun shell-2-window-frame ()
  "Test window format."
  (interactive)
  (delete-other-windows)
  (split-window-horizontally)
  (other-window 1)
  (shell))
;; ]
;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
(global-set-key (kbd "C-c <left>") 'windmove-left)
(global-set-key (kbd "C-c <right>") 'windmove-right)
(global-set-key (kbd "C-c <up>") 'windmove-up)
(global-set-key (kbd "C-c <down>") 'windmove-down)
(global-set-key (kbd "C-c w b") 'windmove-left)
(global-set-key (kbd "C-c w f") 'windmove-right)
(global-set-key (kbd "C-c w p") 'windmove-up)
(global-set-key (kbd "C-c w n") 'windmove-down)
(global-set-key (kbd "C-c b p") #'previous-buffer)
(global-set-key (kbd "C-c b n") #'next-buffer)
(global-set-key (kbd "C-x C-b") 'list-all-buffers)

;; (defhydra hydra-win (global-map "C-c")
;;   "WIN"
;;   ("<left>" windmove-left)
;;   ("<right>" windmove-right)
;;   ("<up>" windmove-up)
;;   ("<down>" windmove-down))

(global-set-key (kbd "C-c M-r") #'revert-buffer)
(global-set-key (kbd "C-x C-c") 'save-buffers-kill-terminal-with-choice)
(global-set-key (kbd "C-x k") 'kill-buffer-or-buffers-from-file)

(global-set-key (kbd "C-c b t") #'toggle-tool-bar-mode-from-frame)
(global-set-key (kbd "C-c b m") #'toggle-menu-bar-mode-from-frame)
(global-set-key (kbd "M-s 7 e") 'toggle-message-truncate-lines)

;; (global-set-key (kbd "C-x o") 'switch-to-window)
;; (global-set-key (kbd "C-x 2") 'vsplit-last-buffer)
;; (global-set-key (kbd "C-x 3") 'hsplit-last-buffer)


(define-key winner-mode-map [(control c) left] nil)
(define-key winner-mode-map [(control c) right] nil)
(define-key winner-mode-map (kbd "C-c w -") #'winner-undo)
(define-key winner-mode-map (kbd "<s-f11>") #'winner-undo)
(define-key winner-mode-map (kbd "C-c w _") #'winner-redo)
(define-key winner-mode-map (kbd "<s-f12>") #'winner-redo)
(global-set-key (kbd "<s-f10>") #'window-configuration-to-register)
(global-set-key (kbd "<s-f9>") #'jump-to-register)
(global-set-key (kbd "C-c w =") 'window-resize-equal)
(global-set-key (kbd "C-c w +") 'window-resize-delta)
(global-set-key (kbd "C-c w *") 'window-resize-factor)
(global-set-key (kbd "C-c w t") #'transpose-frame)
(global-set-key (kbd "C-c w h") #'flop-frame)
(global-set-key (kbd "C-c w v") #'flip-frame)
(global-set-key (kbd "C-c w r") #'rotate-frame-clockwise)
(global-set-key (kbd "C-c w C-r") #'rotate-frame-anticlockwise)
(global-set-key (kbd "C-c w 2") 'shell-2-window-frame)
(global-set-key (kbd "C-c w 3") 'shell-3-window-frame)
(global-set-key (kbd "C-c w a") 'toggle-hscroll-aggressive)
(global-set-key (kbd "C-c w o") 'halve-other-window-height)
(global-set-key (kbd "C-c w d a") 'window-dedicate-all)
(global-set-key (kbd "C-c w u a") 'window-undedicate-all)
(global-set-key (kbd "C-c w d t") 'window-dedicate-this)
(global-set-key (kbd "C-c w u t") 'window-undedicate-this)
(global-set-key (kbd "C-c w A d") 'window-autoresize-set-default)
(global-set-key (kbd "C-c w A s") 'window-autoresize-set-size)
(global-set-key (kbd "C-c w A u") 'window-autoresize-unset)
(global-set-key (kbd "C-c w P w") 'window-preserve-width)
(global-set-key (kbd "C-c w C-h") 'window-resize-height)
(global-set-key (kbd "C-c w C-w") 'window-resize-width)
(global-set-key (kbd "C-c w S") 'balance-windows-area)

(when exwm-p
  ;; Below are configurations for EXWM.
  (message "Importing exwm-startup-config")
  ;; Add paths (not required if EXWM is installed from GNU ELPA).
                                        ;(add-to-list 'load-path "/path/to/xelb/")
                                        ;(add-to-list 'load-path "/path/to/exwm/")

  ;; Load EXWM.
  (require 'exwm)

  ;; Fix problems with Ido (if you use it).
  ;; (require 'exwm-config)
  ;; (exwm-config-ido)
  (require 'exwm-randr)

  ;; Inhibit dangerous functions
  (with-eval-after-load 'frame
    (defun suspend-frame ()
      (interactive)
      (message "Command `suspend-frame' is dangerous in EXWM.")))

;;;;;;;;;;;
;; Faces ;;
;;;;;;;;;;;
  (defface exwm-record-face
    '((t :foreground "red2"))
    "Basic face used to highlight errors and to denote failure."
    :group 'exwm)

;;;;;;;;;;;;;;;
;; Variables ;;
;;;;;;;;;;;;;;;
  (defvar exwm-close-window-on-kill nil
    "EXWM close window when kill buffer.")

  (defvar exwm-exclude-transparency '("totem" "vlc" "darkplaces" "doom" "gzdoom")
    "EXWM instances without transparency.")

  (defvar exwm-default-transparency 0.85
    "EXWM default transparency.")

  ;; example: export EXWM_MONITOR_ORDER="eDP-1 HDMI-1 DP-1"
  (defvar exwm-default-monitor-order
    (let ((monitor-order (getenv "EXWM_MONITOR_ORDER")))
      (if monitor-order
          (condition-case nil
              (split-string monitor-order  " ")
            (error nil))))
    "EXWM default monitor order.")

  ;; example: export EXWM_MONITOR_RESOLUTION="HDMI-1 1280x720 DP-1 800x600"
  (defvar exwm-default-monitor-resolution
    (let ((monitor-resolution (getenv "EXWM_MONITOR_RESOLUTION")))
      (if monitor-resolution
          (condition-case nil
              (split-string monitor-resolution  " ")
            (error nil))))
    "EXWM default monitor resolution.")

  ;; example: export EXWM_MINIBUFFER_NUMBER="1"
  ;; example: export EXWM_MINIBUFFER_NUMBER="eDP-1"
  (defvar exwm-default-minibuffer-workspace-or-screen
    (let ((workspace-or-screen
           (getenv "EXWM_MINIBUFFER_WORKSPACE_OR_SCREEN")))
      (if workspace-or-screen
          (or (cl-parse-integer
               workspace-or-screen :junk-allowed t)
              workspace-or-screen)
        0))
    "EXWM default minibuffer workspace number.")

  (defvar exwm-default-wallpaper-folder "~/Pictures/backgrounds/"
    "EXWM default wallpaper folder.")

  (defvar exwm-screensaver-process nil
    "EXWM screensaver process.")

  (defvar exwm-record-process nil
    "EXWM record process when recording.")

  (defvar exwm-record-recording (propertize "⏺" 'face 'exwm-record-face)
    "EXWM recording text displayed while recording")

;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;
  (eval-and-compile
    (require 'xcb))
  (defun exwm-set-border-color (color &optional buffer)
    "Set BUFFER border COLOR color."
    (when-let ((id (car (rassoc (or buffer (current-buffer))
                                exwm--id-buffer-alist))))
      (xcb:+request exwm--connection
          (make-instance 'xcb:ChangeWindowAttributes
                         :window id
                         :value-mask xcb:CW:BorderPixel
                         :border-pixel (exwm--color->pixel color)))))

  (defun exwm-set-border-width (border-width &optional buffer)
    "Set BUFFER border BORDER-WIDTH width."
    (when-let (id (car (rassoc (or buffer (current-buffer))
                               exwm--id-buffer-alist)))
      (xcb:+request exwm--connection
          (make-instance 'xcb:ConfigureWindow
                         :window id
                         :value-mask xcb:ConfigWindow:BorderWidth
                         :border-width border-width))))

  (defvar exwm-gap-monitor 20)
  (defun exwm-gap-toggle ()
    (interactive)
    (let* ((result (if exwm-randr--compatibility-mode
                       (exwm-randr--get-outputs)
                     (exwm-randr--get-monitors)))
           (primary-monitor (elt result 0))
           (monitor-geometry-alist (elt result 1))
           (monitor (plist-get exwm-randr-workspace-monitor-plist 0))
           (frame (elt exwm-workspace--list 0))
           (geometry (cdr (assoc monitor monitor-geometry-alist))))
      (unless geometry
        (setq geometry (cdr (assoc primary-monitor
                                   monitor-geometry-alist))))
      (if (equal geometry (frame-parameter frame 'exwm-geometry))
          (exwm-randr-refresh)
        (let ((exwm-gap-monitor 0))
          (exwm-randr-refresh)))))



  (defun exwm-record-stop ()
    (interactive)
    (when exwm-record-process
      (interrupt-process exwm-record-process)
      (message "EXWM Record process interrupted")))

  (defun exwm-record-start (monitor pcm-device)
    (interactive (list (let ((monitors (exwm-xrandr-parse)))
                         (gethash (completing-read
                                   "Select monitor: "
                                   (hash-table-keys monitors)
                                   nil t)
                                  monitors))
                       (completing-read
                        "Select audio input: "
                        (split-string
                         (shell-command-to-string
                          "arecord -L | grep -v -E \"^[[:space:]]\"")
                         "\n" t)
                        nil t nil nil "default")))
    (setq exwm-record-process
          (start-process
           "*exwm-record-process*" (if current-prefix-arg "*ffmpeg output*")
           "ffmpeg" "-thread_queue_size" "512"
           "-nostats" "-hide_banner"
           "-loglevel" (if current-prefix-arg "warning" "quiet")
           ;; video input
           "-video_size" (gethash 'resolution monitor)
           "-framerate" "20"
           "-probesize" "30M"
           "-f" "x11grab"
           "-i" (concat ":0.0+" (gethash 'x monitor) "," (gethash 'y monitor))
           ;; audio imput
           "-f" "pulse" "-ac" "2" "-i" pcm-device
           ;; audio codec
           "-codec:a" "copy"
           ;; video codec
           "-codec:v" "libx264"
           ;; options
           "-crf" "0" "-preset" "ultrafast"
           "-threads" "4"
           (expand-file-name (concat
                              "Capture_"
                              (gethash 'resolution monitor)
                              (format-time-string "_%Y-%m-%d_%H.%M.%S.mkv"))
                             (if (file-directory-p "~/Videos/")
                                 "~/Videos/"
                               "~/"))))
    (if (eq 'run (process-status exwm-record-process))
        (message "EXWM Record process started")
      (message "EXWM Record process failed")))

  (defun exwm-record-toggle ()
    (interactive)
    (if exwm-record-process
        (if (eq 'run (process-status exwm-record-process))
            (exwm-record-stop)
          (call-interactively 'exwm-record-start))
      (call-interactively 'exwm-record-start)))

  (defun exwm-screensaver-lock ()
    (interactive)
    (when (not (setq exwm-screensaver-process
                     (car
                      (member "xscreensaver"
                              (mapcar
                               (lambda (item) (cdr (assoc 'comm item)))
                               (mapcar 'process-attributes (list-system-processes)))))))
      (setq exwm-screensaver-process
            (start-process " *xscreensaver" nil "xscreensaver" "-no-splash"))
      (sit-for 1))
    (start-process " *xscreensaver-command" nil "xscreensaver-command" "-lock"))

  (defun exwm-screensaver-interrupt ()
    (interactive)
    (when exwm-screensaver-process
      (interrupt-process exwm-screensaver-process)))

  (defun exwm-screenshot ()
    (interactive)
    (start-process " *screenshot" nil "gnome-screenshot"))

  (defun exwm-set-random-wallpaper (path &optional reason)
    (interactive (list (read-directory-name "Random image from: "
                                            exwm-default-wallpaper-folder)))
    (let* ((paths (directory-files path t "^[^.]"))
           (random-picture (nth (random (length paths)) paths)))
      (start-process " *feh" " *feh outputs*" "feh" "--bg-fill"
                     random-picture)
      (let ((inhibit-message t))
        (message "EXWM wallpaper%s: %s" (if reason
                                            (concat " (" reason ")")
                                          "")
                 (abbreviate-file-name random-picture)))))

  (defun exwm-set-window-transparency (buffer &optional opacity)
    (interactive (list (current-buffer)
                       (read-number "Opacity: " exwm-default-transparency)))
    (let ((window-id (exwm--buffer->id buffer)))
      (if window-id
          (start-process " *transset" " *transset outputs*"
                         "transset" "--id"
                         (int-to-string window-id)
                         (int-to-string (or opacity exwm-default-transparency)))
        (message "Buffer %s without window." (buffer-name buffer)))))

  (defun exwm-toggle-transparency ()
    (interactive)
    (if (= 1 exwm-default-transparency)
        (progn
          (setq exwm-default-transparency 0.85)
          (mapc (lambda (buffer)
                  (with-current-buffer buffer
                    (unless (member exwm-instance-name exwm-exclude-transparency)
                      (exwm-set-window-transparency
                       buffer
                       exwm-default-transparency))))
                (exwm-buffer-list)))
      (setq exwm-default-transparency 1)
      (mapc 'exwm-set-window-transparency (exwm-buffer-list))))

  (defun exwm-xrandr-parse ()
    (let ((monitors (make-hash-table :test 'equal)))
      (with-temp-buffer
        (call-process "xrandr" nil t nil)
        (goto-char (point-min))
        (while (re-search-forward "\n\\([^ ]+\\) connected " nil 'noerror)
          (let ((monitor (make-hash-table :test 'eq))
                (monitor-name (match-string 1)))
            (let ((primary (string-equal "primary" (thing-at-point 'word))))
              (puthash 'primary primary monitor)
              (when primary
                (forward-word)
                (forward-char)))
            (let* ((resolution-pos (thing-at-point 'sexp))
                   (values (split-string resolution-pos "+")))
              (puthash 'resolution (nth 0 values) monitor)
              (puthash 'x (nth 1 values) monitor)
              (puthash 'y (nth 2 values) monitor))
            (forward-line)
            (forward-word)
            (puthash 'max (thing-at-point 'sexp) monitor)
            (puthash monitor-name monitor monitors))))
      monitors))

  (defun exwm-get-default-monitor-resolution (monitor)
    (let ((pos (cl-position monitor exwm-default-monitor-resolution :test 'string-equal)))
      (if pos
          (nth (1+ pos) exwm-default-monitor-resolution))))

  (eval-and-compile
    (require 'crm))
  (defun exwm-update-screens ()
    (interactive)
    (when (null (member
                 "arandr"
                 (mapcar (lambda (pid)
                           (cdr (assq 'comm (process-get-attrs pid '(comm)))))
                         (list-system-processes))))
      (let* ((monitors (exwm-xrandr-parse))
             (names (hash-table-keys monitors)))
        (if (called-interactively-p 'interactive)
            (setq exwm-default-monitor-order
                  (or (completing-read-multiple
                       (concat
                        "External monitor order (" crm-separator "): ")
                       names
                       nil t)
                      exwm-default-monitor-order)))
        (if (null exwm-default-monitor-order)
            (setq exwm-default-monitor-order
                  (list
                   (cl-some (lambda (name)
                              (if (gethash 'primary (gethash name monitors))
                                  name))
                            names))))
        (let* ((names (cl-remove-if-not (lambda (name)
                                          (member name names))
                                        exwm-default-monitor-order))
               (posx 0)
               (gety-lambda
                (lambda (name)
                  (string-to-number
                   (nth 1 (split-string
                           (or
                            (exwm-get-default-monitor-resolution name)
                            (gethash 'max (gethash name monitors))) "x")))))
               (ymax
                (apply 'max
                       (mapcar
                        gety-lambda
                        names)))
               (args
                (apply
                 'nconc
                 (mapcar
                  (lambda (name)
                    (let* ((monitor (gethash name monitors))
                           (resolution
                            (or
                             (exwm-get-default-monitor-resolution name)
                             (gethash 'max monitor))))
                      (prog1
                          (list "--output" name
                                "--mode" resolution
                                "--pos" (concat (number-to-string posx)
                                                "x"
                                                (number-to-string
                                                 (- ymax (funcall gety-lambda name))))
                                "--rotate" "normal")
                        (setq posx (+ posx
                                      (string-to-number
                                       (nth 0 (split-string
                                               (or
                                                (exwm-get-default-monitor-resolution name)
                                                (gethash 'max monitor)) "x"))))))))
                  names))))
          (apply 'call-process "xrandr" nil nil nil args)
          (if exwm-randr-workspace-monitor-plist
              (exwm-set-random-wallpaper exwm-default-wallpaper-folder "update"))
          (setq exwm-randr-workspace-monitor-plist nil)
          (let ((monitor-number -1))
            (mapc (lambda (name)
                    (setq exwm-randr-workspace-monitor-plist
                          (nconc exwm-randr-workspace-monitor-plist
                                 (list (cl-incf monitor-number) name))))
                  names)
            (setq exwm-workspace-number (1+ monitor-number)))))))

  (defun exwm-update-minibuffer-monitor ()
    (interactive)
    (cond
     ((and (numberp exwm-default-minibuffer-workspace-or-screen)
           (< 0 exwm-default-minibuffer-workspace-or-screen)
           (> exwm-workspace-number exwm-default-minibuffer-workspace-or-screen))
      (exwm-workspace-swap (exwm-workspace--workspace-from-frame-or-index 0)
                           (exwm-workspace--workspace-from-frame-or-index
                            exwm-default-minibuffer-workspace-or-screen)))
     ((and
       (stringp exwm-default-minibuffer-workspace-or-screen)
       (let* ((pos (cl-position exwm-default-minibuffer-workspace-or-screen
                                exwm-randr-workspace-monitor-plist
                                :test 'equal))
              (workspace (nth (1- pos) exwm-randr-workspace-monitor-plist)))
         (if (and pos (/= pos 0)
                  workspace (/= workspace 0))
             (progn
               (exwm-workspace-swap (exwm-workspace--workspace-from-frame-or-index 0)
                                    (exwm-workspace--workspace-from-frame-or-index
                                     (nth (1- pos) exwm-randr-workspace-monitor-plist)))
               t)))))))
  (add-hook 'exwm-init-hook 'exwm-update-minibuffer-monitor 91)

  (defun exwm-screen-count ()
    (let ((monitor-number 0))
      (with-temp-buffer
        (call-process "xrandr" nil t nil)
        (goto-char (point-min))
        (while (re-search-forward "\n\\([^ ]+\\) connected " nil 'noerror)
          (cl-incf monitor-number)
          (forward-line)))
      monitor-number))

  (defun exwm-workspace-index-plus (arg)
    (let* ((workspace-count (exwm-workspace--count))
           (remainer (% (+ arg exwm-workspace-current-index) workspace-count)))
      (if (< remainer 0)
          (+ remainer workspace-count)
        remainer)))

  (defun exwm-workspace-next ()
    (interactive)
    (exwm-workspace-switch (exwm-workspace-index-plus 1)))

  (defun exwm-workspace-prev ()
    (interactive)
    (exwm-workspace-switch (exwm-workspace-index-plus -1)))

  (defun exwm-randr-workspace-move (workspace monitor)
    (setq exwm-randr-workspace-monitor-plist
          (plist-put exwm-randr-workspace-monitor-plist workspace monitor)))

  (defun exwm-randr-workspace-move-current (monitor)
    (interactive (list (let* ((result (if exwm-randr--compatibility-mode
                                          (exwm-randr--get-outputs)
                                        (exwm-randr--get-monitors)))
                              (primary-monitor (elt result 0))
                              (monitor-list (mapcar 'car (elt result 2))))
                         (completing-read "Move to monitor: "
                                          monitor-list nil t nil nil primary-monitor))))
    (exwm-randr-workspace-move exwm-workspace-current-index monitor)
    (exwm-randr-refresh))

  (defun exwm-buffer-p (buffer-or-name)
    (with-current-buffer buffer-or-name
      (derived-mode-p 'exwm-mode)))

  (defun exwm-buffer-list ()
    (cl-remove-if-not 'exwm-buffer-p (buffer-list)))

  (defun exwm-display-buffer-condition (buffer-name action)
    (and (exwm-buffer-p buffer-name)
         (let ((buf (current-buffer)))
           (and (null (eq buf (get-buffer buffer-name)))
                (exwm-buffer-p buf)))))

  (defun exwm-display-buffer-biggest (buffer alist)
    (let ((avaible-window-list
           (cl-remove-if
            #'window-dedicated-p
            (delete
             (selected-window)
             (apply #'append (mapcar #'window-list (visible-frame-list)))))))
      (if avaible-window-list
          (if (< 1 (length avaible-window-list))
              (let* ((window-width-list (mapcar (lambda (w)
                                                  (+ (* (window-width w) 10) (window-height w)))
                                                avaible-window-list))
                     (window (nth (cl-position
                                   (seq-max window-width-list)
                                   window-width-list) avaible-window-list)))
                (select-frame (window-frame window))
                (set-window-buffer window buffer))
            (select-frame (window-frame (car avaible-window-list)))
            (set-window-buffer (car avaible-window-list) buffer))
        (display-buffer-pop-up-window buffer alist))))

  (defun exwm-display-buffer-tiling-anticlockwise (buffer alist)
    (rotate-frame-anticlockwise)
    (display-buffer-in-direction buffer (cons '(direction . leftmost) alist))
    (with-current-buffer buffer
      (set (make-local-variable 'exwm-close-window-on-kill)
           (get-buffer-window buffer))))

  (defun exwm-display-buffer-cycle (&optional arg)
    (interactive "P")
    (let ((funcs '(exwm-display-buffer-biggest
                   exwm-display-buffer-tiling-anticlockwise
                   ;; display-buffer-pop-up-window
                   ;; display-buffer-at-bottom
                   ;; display-buffer-below-selected
                   ;; display-buffer-in-side-window
                   ;; display-buffer-in-direction
                   ;; display-buffer-same-window
                   )))
      (when arg
        (setq funcs (nreverse funcs)))
      (let* ((display-funcs (cdr (assoc 'exwm-display-buffer-condition
                                        display-buffer-alist)))
             (func (car display-funcs)))
        (if (null func)
            (message "`display-buffer-alist' without EXWM case.")
          (let ((new-func (or (car (cdr (memq func funcs)))
                              (car funcs))))
            (setcar display-funcs new-func)
            (message "EXWM display function: `%s'" new-func))))))

  (defun exwm-windows-processes ()
    (cl-remove-if-not (lambda (p)
                        (and (eq 'run (process-status p))
                             (process-tty-name p)
                             (null (process-buffer p))))
                      (process-list)))

  (defun exwm-kill-emacs-query-function ()
    (mapc (lambda (p)
            (let ((sigcgt (string-to-number
                           (substring
                            (string-trim-right
                             (shell-command-to-string
                              (concat "cat /proc/"
                                      (number-to-string (process-id p))
                                      "/status | grep SigCgt | cut -f2")))
                            -1)
                           16)))
              (cond ((= 1 (mod sigcgt 2))
                     (message "Sending `sighup' to `%s' with cgt %i"
                              (process-name p) sigcgt)
                     (signal-process p 'sighup))
                    ((= 1 (mod (/ sigcgt 2) 2))
                     (message "Sending `sigint' to `%s' with cgt %i"
                              (process-name p) sigcgt)
                     (interrupt-process p))
                    (t
                     (message "Sending `sigkill' to `%s' with cgt %i"
                              (process-name p) sigcgt)
                     (kill-process p)))))
          (exwm-windows-processes))
    (let ((times 30)
          last-procs)
      (while (and (<= 0 (cl-decf times))
                  (let ((procs (exwm-windows-processes)))
                    (unless (equal last-procs procs)
                      (setq last-procs procs)
                      (message "Waiting processes: %s"
                               (mapconcat #'process-name procs ", ")))
                    procs))
        (sit-for 0.1))
      (if last-procs
          (progn
            (message "Interrupting processes failed.")
            nil)
        (message "All processes closed.")
        t)))

  (defun exwm-start-process (command)
    (interactive (list (read-shell-command "> ")))
    (cond ((string-match-p "\\\\ " command)
           (start-process-shell-command command nil command))
          ((string-match-p "\"" command)
           (let ((split (split-string-and-unquote command)))
             (apply #'start-process (car split) nil (pop split) split)))
          (t
           (let ((split (split-string command)))
             (apply #'start-process (car split) nil (pop split) split)))))

  (defun exwm-start-terminal (arg)
    (interactive "P")
    (if arg
        (cond ((executable-find "tmux")
               (cond ((executable-find "st")
                      (message "Starting st with tmux")
                      (start-process "st" nil "st" "-e" "tmux"))
                     ((executable-find "urxvt")
                      (message "Starting urxvt with tmux")
                      (start-process "urxvt" nil "urxvt" "-e" "tmux"))))
              ((executable-find "screen")
               (cond ((executable-find "st")
                      (message "Starting st with screen")
                      (start-process "st" nil "st" "-e" "screen"))
                     ((executable-find "urxvt")
                      (message "Starting urxvt with screen")
                      (start-process "urxvt" nil "urxvt" "-e" "screen"))))
              (t (message "Terminal multiplexer not found")))
      (cond ((executable-find "alacritty")
             (message "Starting alacritty")
             (start-process "alacritty" nil "alacritty"))
            ((executable-find "urxvt")
             (message "Starting urxvt")
             (start-process "urxvt" nil "urxvt"))
            ((executable-find "xterm")
             (message "Starting xterm")
             (start-process "xterm" nil "xterm")))))

  (defun exwm-start-emacs (filepath)
    (interactive (list (buffer-file-name)))
    (cond ((or current-prefix-arg
               (null filepath))
           (start-process "emacs" nil "emacs"))
          ((and (stringp filepath)
                (file-exists-p filepath))
           (start-process "emacs" nil
                          "emacs" (concat
                                   "+" (number-to-string (line-number-at-pos))
                                   ":" (number-to-string (1+ (current-column))))
                          filepath))
          (t
           (message "File not found: %s" filepath))))

  (defun exwm-ace-window (arg)
    (interactive "p")
    (if (and (derived-mode-p 'exwm-mode)
             (eq exwm--input-mode 'char-mode))
        (let ((id (exwm--buffer->id (window-buffer))))
          (exwm-input-grab-keyboard id)
          (unwind-protect
              (ace-window arg)
            (exwm-input-release-keyboard id)))
      (ace-window arg)))

  (defun exwm-shutdown (&optional arg)
    (interactive "P")
    (add-hook 'kill-emacs-hook
              (lambda ()
                (call-process "systemctl" nil nil nil "poweroff")) t)
    (save-buffers-kill-terminal-with-choice arg))

  (defun exwm-close-window-if-exwm-mode ()
    (when (and (derived-mode-p 'exwm-mode)
               (< 1 (length (window-list)))
               exwm-close-window-on-kill)
      (if (null (eq exwm-close-window-on-kill (get-buffer-window (current-buffer))))
          (delete-window)
        (delete-window)
        (when (eq (car (cdr (assoc 'exwm-display-buffer-condition
                                   display-buffer-alist)))
                  'exwm-display-buffer-tiling-anticlockwise)
          (rotate-frame-clockwise)))))

  (defun exwm-input-mode-change-color ()
    (cl-case exwm--input-mode
      (line-mode (exwm-set-border-color "blue"))
      (char-mode (exwm-set-border-color "red"))))

  (defun exwm-selected-window-advice (&rest _args)
    (when (derived-mode-p 'exwm-mode)
      (exwm-set-border-width 1)))
  (advice-add 'select-frame :after 'exwm-selected-window-advice)
  (advice-add 'select-window :after 'exwm-selected-window-advice)

  (defun exwm-unselected-window-advice (&rest _args)
    (when (derived-mode-p 'exwm-mode)
      (exwm-set-border-width 0)))
  (advice-add 'select-frame :before 'exwm-unselected-window-advice)
  (advice-add 'select-window :before 'exwm-unselected-window-advice)

;;;;;;;;;;;;;
;; layouts ;;
;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;
;; Customizations ;;
;;;;;;;;;;;;;;;;;;;;
  (add-hook 'exwm-input-input-mode-change-hook
            'exwm-input-mode-change-color)

  ;; display buffer rules
  (push '(exwm-display-buffer-condition
          ;; exwm-display-buffer-biggest
          exwm-display-buffer-tiling-anticlockwise)
        display-buffer-alist)

  (add-hook 'kill-buffer-hook 'exwm-close-window-if-exwm-mode)

  ;; Turn on `display-time-mode' if you don't use an external bar.
  (setq display-time-default-load-average nil
        display-time-day-and-date t
        display-time-24hr-format t
        display-time-mail-string "✉")

  ;; You are strongly encouraged to enable something like `ido-mode' to alter
  ;; the default behavior of 'C-x b', or you will take great pains to switch
  ;; to or back from a floating frame (remember 'C-x 5 o' if you refuse this
  ;; proposal however).
  ;; You may also want to call `exwm-config-ido' later (see below).
  ;; (ido-mode 1)

  ;; Emacs server is not required to run EXWM but it has some interesting uses
  ;; (see next section).
  (server-start)
  (push 'exwm-kill-emacs-query-function kill-emacs-query-functions)

  ;; (require 'mini-modeline)                     ;; + with mini-modeline
  ;; (setq mini-modeline-frame (selected-frame))  ;; + with mini-modeline

  ;; Set the initial number of workspaces (they can also be created later).
  (setq exwm-workspace-number (exwm-screen-count)
        exwm-workspace-minibuffer-position nil
        exwm-workspace-show-all-buffers t
        exwm-layout-show-all-buffers t)

  ;; All buffers created in EXWM mode are named "*EXWM*". You may want to
  ;; change it in `exwm-update-class-hook' and `exwm-update-title-hook', which
  ;; are run when a new X window class name or title is available.  Here's
  ;; some advice on this topic:
  ;; + Always use `exwm-workspace-rename-buffer` to avoid naming conflict.
  ;; + For applications with multiple windows (e.g. GIMP), the class names of
                                        ;    all windows are probably the same.  Using window titles for them makes
  ;;   more sense.
  ;; In the following example, we use class names for all windows expect for
  ;; Java applications and GIMP.
  (defun exwm-update-class-defaults ()
    (unless (or (string-prefix-p "sun-awt-X11-" exwm-instance-name)
                (string-equal "gimp" exwm-instance-name))
      (exwm-workspace-rename-buffer exwm-class-name))
    (unless (member exwm-instance-name exwm-exclude-transparency)
      (exwm-set-window-transparency (current-buffer) exwm-default-transparency)))
  (add-hook 'exwm-update-class-hook 'exwm-update-class-defaults)

  (defun exwm-update-title-defaults ()
    (when (or (not exwm-instance-name)
              (string-prefix-p "sun-awt-X11-" exwm-instance-name)
              (string-equal "gimp" exwm-instance-name))
      (exwm-workspace-rename-buffer exwm-title)))
  (add-hook 'exwm-update-title-hook 'exwm-update-title-defaults)

  (with-eval-after-load 'exwm-input
    ;; line-mode prefix keys
    (push ?\M-o exwm-input-prefix-keys)
    (cl-pushnew 'XF86PowerOff exwm-input-prefix-keys)

    (global-set-key (kbd "<XF86PowerOff>") 'exwm-shutdown)
    ;; Global keybindings can be defined with `exwm-input-global-keys'.
    ;; Here are a few examples:
    (setq exwm-input-global-keys
          `(;; Universal argument
            ([?\s-u] . universal-argument)
            ;; Bind "s-r" to exit char-mode and fullscreen mode.
            ([?\s-r] . exwm-reset)
            ;; Bind "s-w" to switch workspace interactively.
            ([?\s-w] . exwm-workspace-switch)
            ;; Bind "s-1" to "s-0" to switch to a workspace by its index.
            ([?\s-0] . (lambda ()
                         (interactive)
                         (exwm-workspace-switch 9)))
            ,@(mapcar (lambda (i)
                        `(,(kbd (format "s-%d" (1+ i))) .
                          (lambda ()
                            (interactive)
                            (exwm-workspace-switch ,i))))
                      (number-sequence 0 8))
            (,(kbd "S-s-0") . (lambda ()
                                (interactive)
                                (exwm-workspace-switch-create 9)))
            ,@(mapcar (lambda (i)
                        `(,(kbd (format "S-s-%d" (1+ i))) .
                          (lambda ()
                            (interactive)
                            (exwm-workspace-switch-create ,i))))
                      (number-sequence 0 8))
            ;; Bind "s-&" to launch applications ('M-&' also works if the output
            ;; buffer does not bother you).
            ([?\s-&] . exwm-start-process)
            ;; New terminal
            ([s-return] . exwm-start-terminal)
            ([s-S-return] . exwm-start-emacs)
            ;; Bind "s-<f2>" to "slock", a simple X display locker.
            ([s-f2] . (lambda ()
                        (interactive)
                        (start-process "" nil "/usr/bin/slock")))
            ;; Toggle char-line modes
            ([?\s-q] . exwm-input-toggle-keyboard)
            ([?\s-Q] . (lambda ()
                         (interactive)
                         (message "Actual input mode: %s" exwm--input-mode)))
            ;; Display datetime
            ([?\s-a] . display-time-mode)
            ;; Workspaces
            ([?\s-n] . exwm-workspace-next)
            ([?\s-p] . exwm-workspace-prev)
            ([?\s-S] . exwm-workspace-swap)
            ([?\s-M] . exwm-randr-workspace-move-current)
            ;; windows
            ([?\s-f] . exwm-layout-toggle-fullscreen)
            ([?\s-s ?6] . exwm-display-buffer-cycle)
            ([?\s-s ?7 ?g] . exwm-gap-toggle)
            ([?\s-s ?7 ?m] . exwm-layout-toggle-mode-line)
            ([?\s-s ?7 ?f] . exwm-floating-toggle-floating)
            ;; ace-window
            ([?\s-o] . exwm-ace-window)
            ;; Switch to minibuffer window
            ([?\s-s ?0] . switch-to-minibuffer-window)
            ;; switch buffer
            ([?\s-b] . switch-to-buffer)
            ;; Bind lock screen
            (,(kbd "<s-escape>") . exwm-screensaver-lock)
            (,(kbd "<C-s-escape>") . exwm-screensaver-interrupt)
            ;; Screenshot
            (,(kbd "<s-print>") . exwm-screenshot)
            ;; Record audio and video
            (,(kbd "<S-s-print>") . exwm-record-toggle)
            ;; Execute command menu
            ([?\s-x] . ,(if (featurep 'helm) 'helm-M-x 'execute-extended-command))
            ;; shutdown computer
            (,(kbd "<s-end>") . exwm-shutdown))))

  (with-eval-after-load 'exwm-manage
    (setq exwm-manage-configurations
          '(((member exwm-class-name
                     '("Emacs" "st-256color" "Alacritty" "URxvt" "XTerm"))
             char-mode t
             tiling-mode-line nil
             floating-mode-line nil)
            ((member exwm-class-name
                     '("darkplaces" "doom" "gzdoom"))
             floating nil
             tiling-mode-line nil
             floating-mode-line nil)
            (t tiling-mode-line nil
               floating-mode-line nil))))

  ;; To add a key binding only available in line-mode, simply define it in
  ;; `exwm-mode-map'.  The following example shortens 'C-c q' to 'C-q'.
  (define-key exwm-mode-map [?\C-q] #'exwm-input-send-next-key)

  ;; The following example demonstrates how to use simulation keys to mimic
  ;; the behavior of Emacs.  The value of `exwm-input-simulation-keys` is a
  ;; list of cons cells (SRC . DEST), where SRC is the key sequence you press
  ;; and DEST is what EXWM actually sends to application.  Note that both SRC
  ;; and DEST should be key sequences (vector or string).
  (setq exwm-input-simulation-keys
        `(;; movement
          ([?\C-b] . [left])
          ([?\M-b] . [C-left])
          ([?\C-f] . [right])
          ([?\M-f] . [C-right])
          ([?\C-p] . [up])
          ([?\C-n] . [down])
          (,(kbd "C-a") . [home])
          ([?\M-<] . [C-home])
          ([?\C-e] . [end])
          ([?\M->] . [C-end])
          ([?\M-v] . [prior])
          ([?\C-v] . [next])
          ([?\C-d] . [delete])
          ([?\C-k] . [S-end delete])
          ;; jumps
          (,(kbd "M-g M-g") . [?\C-g])
          (,(kbd "M-g M-n") . ,(kbd "<f8>"))
          (,(kbd "M-g M-p") . ,(kbd "<S-f8>"))
          (,(kbd "M-.") . ,(kbd "<C-f12>"))
          (,(kbd "C-,") . ,(kbd "C-S--"))
          (,(kbd "C-.") . ,(kbd "C-M--"))
          (,(kbd "C-x C-SPC") . ,(kbd "C-M--"))
          ;; comments
          (,(kbd "M-;") . ,(kbd "M-S-a"))
          ;; select
          ([?\C-x ?h] . [?\C-a])
          ;; cut/paste
          ([?\C-w] . [?\C-x])
          ([?\M-w] . [?\C-c])
          ([?\C-y] . [?\C-v])
          ;; search
          ([?\C-s] . [?\C-f])
          ;; files
          ([?\C-x ?\C-s] . [?\C-s])
          ;; undo redo
          (,(kbd "C-_") . [?\C-z])
          (,(kbd "M-_") . [?\C-y])
          ;; format
          (,(kbd "M-SPC") . ,(kbd "C-S-i"))))

  ;; You can hide the minibuffer and echo area when they're not used, by
  ;; uncommenting the following line.
                                        ;(setq exwm-workspace-minibuffer-position 'bottom)

  ;; Do not forget to enable EXWM. It will start by itself when things are
  ;; ready.  You can put it _anywhere_ in your configuration.
  ;; (exwm-enable)

  ;; Multi-monitor
  (add-hook 'exwm-randr-screen-change-hook 'exwm-update-screens)
  (exwm-randr-enable)

  ;; System tray
  (require 'exwm-systemtray)
  (exwm-systemtray-enable)

  ;; System monitor
  (eval-and-compile
    (require 'symon))
  ;; (defun message-advice (orig-fun format-string &rest args)
  ;;   (if format-string
  ;;       (apply orig-fun format-string args)))
  ;; (advice-add #'message :around 'message-advice)

  ;; (defvar symon--minibuffer-window
  ;;   (minibuffer-window (car exwm-workspace--list)))
  ;; (defun symon-message-trick (format-string &rest args)
  ;;   (if (not (cdr exwm-workspace--list))
  ;;       (apply #'message format-string args)
  ;;     (if (null symon--minibuffer-window)
  ;;         (setq symon--minibuffer-window
  ;;               (minibuffer-window (car exwm-workspace--list))))
  ;;     (with-selected-window symon--minibuffer-window
  ;;       (delete-region (minibuffer-prompt-end) (point-max))
  ;;       (insert (apply #'format-message format-string args)))))

  (defvar symon--datetime-monitor-pulse nil)
  (define-symon-monitor symon-current-datetime-monitor
    :interval 10
    :display (if (setq symon--datetime-monitor-pulse
                       (null symon--datetime-monitor-pulse))
                 (format-time-string "%e %b %H:%M.")
               (format-time-string "%e %b %H:%M ")))

  (define-symon-monitor symon-org-clock-in-monitor
    :interval 10
    :display (if (bound-and-true-p org-clock-mode-line-timer)
                 org-mode-line-string))

  (define-symon-monitor symon-venv-current-name-monitor
    :interval 10
    :display (if (and (boundp 'venv-current-name)
                      venv-current-name
                      (not (string-empty-p venv-current-name)))
                 (concat "[" (propertize venv-current-name 'face 'mode-line-correct) "]")))

  (define-symon-monitor symon-recording-monitor
    :display (if (and exwm-record-process
                      (eq 'run (process-status exwm-record-process)))
                 exwm-record-recording))

  (setcdr (last symon-monitors)
          `(,(cond ((memq system-type '(gnu/linux cygwin))
                    'symon-linux-battery-monitor)
                   ((memq system-type '(darwin))
                    'symon-darwin-battery-monitor)
                   ((memq system-type '(windows-nt))
                    'symon-windows-battery-monitor))
            symon-current-datetime-monitor))

  (push 'symon-org-clock-in-monitor symon-monitors)
  (push 'symon-venv-current-name-monitor symon-monitors)
  (push 'symon-recording-monitor symon-monitors)

  (setq symon-refresh-rate 4
        symon-sparkline-type 'bounded
        symon-sparkline-thickness 1
        symon-history-size 24
        symon-sparkline-width 24
        symon-total-spark-width 12)

  (add-hook 'exwm-init-hook 'symon-mode 91)

  ;; Background
  (defvar exwm-timer-random-wallpaper nil
    "Random wallpaper timer")

  (defun exwm-start-random-wallpaper ()
    (interactive)
    (if exwm-timer-random-wallpaper
        (message "Exists previous random wallpaper timer")
      (setq exwm-timer-random-wallpaper
            (run-at-time 600 600
                         'exwm-set-random-wallpaper
                         exwm-default-wallpaper-folder
                         "timer"))))
  (exwm-start-random-wallpaper)

  (defun exwm-cancel-random-wallpaper ()
    (interactive)
    (if (null exwm-timer-random-wallpaper)
        (message "Nil random wallpaper timer")
      (cancel-timer exwm-timer-random-wallpaper)
      (setq exwm-timer-random-wallpaper nil)))

  ;; Applications
  (add-hook 'exwm-init-hook
            (lambda ()
              (dolist (program-and-args-list '(("compton")
                                               ("volumeicon")
                                               ("nm-applet")))
                (let ((executable (car program-and-args-list)))
                  (if (executable-find executable)
                      (apply 'start-process
                             (concat " *" executable)
                             (concat " *" executable " outputs*")
                             program-and-args-list)
                    (message "Unable to find `%s' executable." executable)))))
            92)

  (when (load "helm-exwm" t t)
    (setq helm-exwm-emacs-buffers-source (helm-exwm-build-emacs-buffers-source)
          helm-exwm-source (helm-exwm-build-source)
          helm-mini-default-sources `(helm-exwm-emacs-buffers-source
                                      helm-exwm-source
                                      helm-source-recentf)))

  (when (featurep 'helm-posframe)
    (defvar exwm-helm-posframe-display-buffer nil)
    (defun helm-posframe-display-advice (&rest args)
      (let ((buffer (current-buffer)))
        (when (exwm-buffer-p buffer)
          (exwm-set-window-transparency buffer 0.2)
          (setq exwm-helm-posframe-display-buffer buffer))))
    (advice-add 'helm-posframe-display :before 'helm-posframe-display-advice)

    (defun helm-posframe-cleanup-advice (&rest args)
      (when exwm-helm-posframe-display-buffer
        (with-current-buffer exwm-helm-posframe-display-buffer
          (exwm-set-window-transparency
           exwm-helm-posframe-display-buffer
           (if (member exwm-instance-name exwm-exclude-transparency)
               1 exwm-default-transparency)))
        (setq exwm-helm-posframe-display-buffer nil)))
    (advice-add 'helm-posframe-cleanup :after 'helm-posframe-cleanup-advice))

  (when (featurep 'winum)
    (defun exwm-winum-bindings ()
      (if winum-mode
          (winum--define-keys exwm-mode-map)
        (winum--undefine-keys exwm-mode-map)))
    (exwm-winum-bindings)
    (add-hook 'winum-mode-hook 'exwm-winum-bindings))

  (when (featurep 'ace-window)
    (defun aw-select-advice (orig-fun &rest args)
      (let ((exwm-buffer-list (exwm-buffer-list)))
        (mapc (lambda (buffer)
                (exwm-set-window-transparency buffer 0.2))
              exwm-buffer-list)
        (unwind-protect
            (apply orig-fun args)
          (mapc (lambda (buffer)
                  (exwm-set-window-transparency buffer exwm-default-transparency))
                exwm-buffer-list))))
    (advice-add 'aw-select :around 'aw-select-advice))

  ;; gaps
  ;; (let ((color (face-attribute 'default :background)))
  ;;   (set-face-attribute 'window-divider nil :foreground color)
  ;;   (set-face-attribute 'window-divider-first-pixel nil :foreground "#353024")
  ;;   (set-face-attribute 'window-divider-last-pixel nil :foreground "#353024"))
  ;; (window-divider-mode)


  ;; minibuffer
  (when (load "mini-frame" t t)
    (setq mini-frame-show-parameters
          (if (featurep 'helm)
              '((left . -1) (top . -1) (width . 0.75) (height . 1) (alpha . 75)
                (border-width . 0) (internal-border-width . 0)
                (background-color . "black"))
            (setq mini-frame-completions-show-parameters
                  (defun mini-frame-completions-show-parameters-dwim ()
                    (let ((workarea (nth exwm-workspace-current-index
                                         exwm-workspace--workareas)))
                      `((parent-frame . nil)
                        (z-group . above)
                        (left . ,(+ (aref workarea 0) 20))
                        ;; (height . ,(cons 'text-pixels (round (* (aref workarea 3) 0.3))))
                        (height . ,(round (* (aref workarea 3) (default-font-height) 0.001)))
                        ;; [ in this fuction 'text-pixels then white mini frame
                        (width . ,(round (* (aref workarea 2) (default-font-width) 0.0186)))
                        ;; (width . ,(cons 'text-pixels (- (aref workarea 2) 60)))
                        ;; ]
                        (background-color . "black")))))
            (defun mini-frame-show-parameters-dwim ()
              (let* ((workarea (nth exwm-workspace-current-index
                                    exwm-workspace--workareas))
                     (workarea-width (aref workarea 2)))
                `((parent-frame . nil)
                  (z-group . above)
                  (top . ,(+ (aref workarea 1) 10))
                  (left . ,(round (+ (aref workarea 0) (* workarea-width 0.05))))
                  (height . 1)
                  (width . ,(round (* workarea-width (default-font-width) 0.018)))
                  ;; (width . ,(cons 'text-pixels (round (* workarea-width 0.9))))
                  (background-color . "black")))))
          mini-frame-resize t  ;; nil when icomplete-exhibit advice
          ;; fix not resizing mini frame on gnome
          ;; x-gtk-resize-child-frames 'resize-mode
          resize-mini-frames t
          mini-frame-ignore-commands '(debugger-eval-expression
                                       objed-ipipe
                                       "edebug-eval-expression"
                                       "exwm-workspace-"))

    (defun mini-frame--resize-mini-frame (frame)
      (when (and (eq mini-frame-frame frame)
                 (frame-live-p mini-frame-frame))
        (modify-frame-parameters
         mini-frame-frame
         `((height
            .
            ,(min
              40
              (count-visual-lines-in-string
               (concat
                (minibuffer-prompt)
                (with-selected-window (minibuffer-window mini-frame-frame)
                  (minibuffer-contents-no-properties))
                (when (and icomplete-mode
                           (icomplete-simple-completing-p))
                  (overlay-get icomplete-overlay 'after-string)))
               (frame-width mini-frame-frame))))))
        (when (and (frame-live-p mini-frame-completions-frame)
                   (frame-visible-p mini-frame-completions-frame))
          (modify-frame-parameters
           mini-frame-completions-frame
           `((top
              .
              ,(+ (* 2 (frame-parameter mini-frame-frame 'internal-border-width))
                  (frame-parameter mini-frame-frame 'top)
                  (cdr (window-text-pixel-size
                        (frame-selected-window mini-frame-frame))))))))))

    (add-hook 'exwm-init-hook 'mini-frame-mode 91)

    ;; [ fix not resizing mini frame
    ;; (defun mini-frame-icomplete-exhibit-advice ()
    ;;   (when (and (bound-and-true-p mini-frame-frame)
    ;;              (frame-live-p mini-frame-frame)
    ;;              (frame-visible-p mini-frame-frame))
    ;;     (modify-frame-parameters
    ;;      mini-frame-frame
    ;;      `((height . ,(count-visual-lines-in-string
    ;;                    (concat
    ;;                     (buffer-substring-no-properties (point-min) (point-max))
    ;;                     (overlay-get icomplete-overlay 'after-string))
    ;;                    (frame-width mini-frame-frame)))))
    ;;     (when (and (frame-live-p mini-frame-completions-frame)
    ;;                (frame-visible-p mini-frame-completions-frame))
    ;;       (modify-frame-parameters
    ;;        mini-frame-completions-frame
    ;;        `((top
    ;;           .
    ;;           ,(+ (* 2 (frame-parameter mini-frame-frame 'internal-border-width))
    ;;               (frame-parameter mini-frame-frame 'top)
    ;;               (cdr (window-text-pixel-size
    ;;                     (frame-selected-window mini-frame-frame))))))))))
    ;; (advice-add 'icomplete-exhibit :after 'mini-frame-icomplete-exhibit-advice)
    ;; ]

    (defun mini-frame-toggle-resize ()
      (interactive)
      (if (setq mini-frame-resize (null mini-frame-resize))
          (advice-remove 'icomplete-exhibit 'mini-frame-icomplete-exhibit-advice)
        (advice-add 'icomplete-exhibit :after 'mini-frame-icomplete-exhibit-advice))
      (message "Custom mini frame resize: %s" (nu mini-frame-resize)))
    (global-set-key (kbd "M-s 7 0") 'mini-frame-toggle-resize)


    ;; only one minibuffer
    (defun common-minibuffer-all-frames ()
      (let ((frame (car (minibuffer-frame-list))))
        (setf (alist-get 'minibuffer default-frame-alist)
              (if frame nil t))))
    (add-hook 'before-make-frame-hook 'common-minibuffer-all-frames))


  ;; systemtray hold
  (defun exwm-systemtray--on-workspace-switch-advice (orig-fun &rest args)
    (if (eq exwm-workspace--current (window-frame (minibuffer-window)))
        (apply orig-fun args)))
  (advice-add #'exwm-systemtray--on-workspace-switch :around 'exwm-systemtray--on-workspace-switch-advice)

  ;; helm integration
  (when (featurep 'helm)
    (when (bug-check-function-bytecode
           'helm-resolve-display-function
           "csYgcYgIKYY5AIkJPoQ0AAqDHADHyAshIYQ0AAyDLAANhCwAySBHylaENAAODssgnYQ2AMyHzcAhhw==")
      (defun helm-resolve-display-function (com)
        (or (with-helm-buffer helm-display-function)
            (default-value 'helm-display-function))))

    (when (bug-check-function-bytecode
           'helm-display-mode-line
           "xsAhiMcCPIMRAMjJBCKGFADKwCEDIhDLAiGEKgAJhSsAyMwDIgqdhSsAzQuFXQDIzAQiC86JiQM6g1kAA0CyA8jMBEAisgIBBZiDUgACAUKyAQNBsgSCNwCJn7aFCIOhAM/Q0dDSBgbQ0wYIhXkA1NXWBgtHItfYI0TT2QzaQkJE20JCQkJCQkJC3EJCFd0IPIOaAAhBQIKbAAghFiaCpQDKxSEVDieDswDesgPfIIiC1gAOKIPWAMcEPIXDAMjgBgYiBSLh4iDjItTQAwNR1+QjFim2ArYCiYXeAOUghw==")
      (defun helm-display-mode-line (source &optional force)
        "Set up mode line and header line for `helm-buffer'.

SOURCE is a Helm source object.

Optional argument FORCE forces redisplay of the Helm buffer's
mode and header lines."
        (set (make-local-variable 'helm-mode-line-string)
             (helm-interpret-value (or (and (listp source) ; Check if source is empty.
                                            (assoc-default 'mode-line source))
                                       (default-value 'helm-mode-line-string))
                                   source))
        (let ((follow (and (or (helm-follow-mode-p source)
                               (and helm-follow-mode-persistent
                                    (member (assoc-default 'name source)
                                            helm-source-names-using-follow)))
                           " (HF)"))
              (marked (and helm-marked-candidates
                           (cl-loop with cur-name = (assoc-default 'name source)
                                    for c in helm-marked-candidates
                                    for name = (assoc-default 'name (car c))
                                    when (string= name cur-name)
                                    collect c))))
          ;; Setup mode-line.
          (if helm-mode-line-string
              (setq mode-line-format
                    `(:propertize
                      ;; (" " mode-line-buffer-identification " "  ;; -
                      (                                            ;; +
                       (:eval (format "L%-3d" (helm-candidate-number-at-point)))
                       ,follow
                       " "
                       (:eval ,(and marked
                                    (propertize
                                     (format "M%d" (length marked))
                                     'face 'helm-visible-mark)))
                       (:eval (when ,helm--mode-line-display-prefarg
                                (let ((arg (prefix-numeric-value
                                            (or prefix-arg current-prefix-arg))))
                                  (unless (= arg 1)
                                    (propertize (format " [prefarg:%s]" arg)
                                                'face 'helm-prefarg)))))
                       " "
                       (:eval (with-helm-buffer
                               (helm-show-candidate-number
                                (car-safe helm-mode-line-string))))
                       " " helm--mode-line-string-real " "
                       (:eval (make-string (window-width) ? )))
                      keymap (keymap (mode-line keymap
                                                (mouse-1 . ignore)
                                                (down-mouse-1 . ignore)
                                                (drag-mouse-1 . ignore)
                                                (mouse-2 . ignore)
                                                (down-mouse-2 . ignore)
                                                (drag-mouse-2 . ignore)
                                                (mouse-3 . ignore)
                                                (down-mouse-3 . ignore)
                                                (drag-mouse-3 . ignore))))
                    helm--mode-line-string-real
                    (substitute-command-keys (if (listp helm-mode-line-string)
                                                 (cadr helm-mode-line-string)
                                               helm-mode-line-string)))
            (setq mode-line-format (default-value 'mode-line-format)))
          ;; Setup header-line.
          (cond (helm-echo-input-in-header-line
                 (setq force t)
                 (helm--set-header-line))
                (helm-display-header-line
                 (let ((hlstr (helm-interpret-value
                               (and (listp source)
                                    (assoc-default 'header-line source))
                               source))
                       (endstr (make-string (window-width) ? )))
                   (setq header-line-format
                         (propertize (concat " " hlstr endstr)
                                     'face 'helm-header))))))
        (when force (force-mode-line-update)))))

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
  (global-set-key (kbd "M-s 7 T") 'exwm-toggle-transparency))

;; sudo apt install fd-find
;; sudo apt install ripgrep

(require 'icomplete)
;; (when (bug-check-function-bytecode
;;        'icomplete-force-complete-and-exit
;;        "wyDEIFaEFAAIhBAACYQUAAqDFwDFIIfGIIc=")
;;   (defun icomplete-force-complete-and-exit ()
;;     "Complete the minibuffer with the longest possible match and exit.
;; Use the first of the matches if there are any displayed, and use
;; the default otherwise."
;;     (interactive)
;;     ;; This function is tricky.  The mandate is to "force", meaning we
;;     ;; should take the first possible valid completion for the input.
;;     ;; However, if there is no input and we can prove that that
;;     ;; coincides with the default, it is much faster to just call
;;     ;; `minibuffer-complete-and-exit'.  Otherwise, we have to call
;;     ;; `minibuffer-force-complete-and-exit', which needs the full
;;     ;; completion set and is potentially slow and blocking.  Do the
;;     ;; latter if:
;;     (if (and (null completion-cycling)
;;              (or
;;               ;; there's some input, meaning the default in off the table by
;;               ;; definition; OR
;;               (> (icomplete--field-end) (icomplete--field-beg))
;;               ;; there's no input, but there's also no minibuffer default
;;               ;; (and the user really wants to see completions on no input,
;;               ;; meaning he expects a "force" to be at least attempted); OR
;;               (and (not minibuffer-default)
;;                    icomplete-show-matches-on-no-input)
;;               ;; there's no input but the full completion set has been
;;               ;; calculated, This causes the first cached completion to
;;               ;; be taken (i.e. the one that the user sees highlighted)
;;               completion-all-sorted-completions))
;;         (minibuffer-force-complete-and-exit)
;;       ;; Otherwise take the faster route...
;;       (minibuffer-complete-and-exit))))
;; (when (bug-check-function-bytecode
;;        'icomplete--sorted-completions
;;        "CIagAMMgxCDAAgIiCYMjAAk7gyMAxCDDIFWDIwDFxkSCNQAKhTUACT+FNQDHIMg9hTUAyUPKy8oDOoOVAANAsgMEysvKAzqDggADQTqDggADQUCyAwYGAyGDdwADiYlBQaG2AswGCwYLBQYMQiOyAcqJsgOCeADLg4IAA0GyBIJFALaDibICP4myA4OVAANBsgSCOAABg50ABIKeAIm2h4c=")
;;   (defun icomplete--sorted-completions ()
;;     (or completion-all-sorted-completions
;;         (cl-loop
;;          with beg = (icomplete--field-beg)
;;          with end = (icomplete--field-end)
;;          with all = (completion-all-sorted-completions beg end)
;;          for fn in (cond ((and minibuffer-default
;;                                (stringp minibuffer-default) ; bug#38992
;;                                (= (icomplete--field-end) (icomplete--field-beg)))
;;                           ;; When we have a non-nil string default and
;;                           ;; no input whatsoever: we want to make sure
;;                           ;; that default is bubbled to the top so that
;;                           ;; `icomplete-force-complete-and-exit' will
;;                           ;; select it (do that even if the match
;;                           ;; doesn't match the completion perfectly.
;;                           `(,(lambda (comp)
;;                                (equal minibuffer-default comp))))
;;                          ((and fido-mode
;;                                (not minibuffer-default)
;;                                (eq (icomplete--category) 'file))
;;                           ;; `fido-mode' has some extra file-sorting
;;                           ;; semantics even if there isn't a default,
;;                           ;; which is to bubble "./" to the top if it
;;                           ;; exists.  This makes M-x dired RET RET go to
;;                           ;; the directory of current file, which is
;;                           ;; what vanilla Emacs and `ido-mode' both do.
;;                           `(,(lambda (comp)
;;                                (string= "./" comp)))))
;;          thereis (cl-loop
;;                   for l on all
;;                   while (consp (cdr l))
;;                   for comp = (cadr l)
;;                   when (funcall fn comp)
;;                   do (setf (cdr l) (cddr l))
;;                   and return
;;                   (completion--cache-all-sorted-completions beg end (cons comp all)))
;;          finally return all))))

(require 'icomplete-vertical)
(require 'completing-read-at-point)
(require 'orderless)
(when (bug-check-function-bytecode
       'orderless-try-completion
       "wAUFBSOJhA0AwYIqAIlBhCcAwgYGBgYGBiNAAUBQiQFHQrIBgioABQNChw==")
  (defun orderless-try-completion (string table pred point &optional _metadata)
    "Complete STRING to unique matching entry in TABLE.
This uses `orderless-all-completions' to find matches for STRING
in TABLE among entries satisfying PRED.  If there is only one
match, it completes to that match.  If there are no matches, it
returns nil.  In any other case it \"completes\" STRING to
itself, without moving POINT.
This function is part of the `orderless' completion style."
    (let ((all (orderless-filter string table pred)))
      (cond
       ((null all) nil)
       ((null (cdr all))
        (let ((full (concat
                     (car (orderless--prefix+pattern string table pred))
                     (car all))))
          (cons full (length full))))
       (t
        (completion-flex-try-completion string table pred point))))))

;; this file overides completion-category-defaults
(require 'message)

(set-face-attribute 'icomplete-first-match nil :foreground "#cafd32")

(add-hook 'minibuffer-exit-hook
          #'orderless-remove-transient-configuration)

;; Another functions override this variables, then
;; set every time enter minibuffer
(setq
 ;; icomplete
 icomplete-prospects-height 4
 icomplete-separator " · "
 ;; orderless
 orderless-matching-styles '(orderless-regexp orderless-flex)
 orderless-component-separator ",+"
 orderless-style-dispatchers nil)
(defun icomplete--fido-mode-setup ()
  "Setup `fido-mode''s minibuffer."
  (when (and icomplete-mode (icomplete-simple-completing-p))
    (use-local-map (make-composed-keymap icomplete-fido-mode-map
                                         (current-local-map)))
    (setq-local
     ;; fido
     icomplete-tidy-shadowed-file-names t
     icomplete-show-matches-on-no-input t
     icomplete-hide-common-prefix nil
     completion-styles '(orderless)
     completion-flex-nospace nil
     completion-category-defaults nil
     completion-ignore-case t
     read-buffer-completion-ignore-case t
     read-file-name-completion-ignore-case t)
    ;; [ fix bugs
    (when completion-cycling
      (funcall (prog1 completion-cycling (setq completion-cycling nil))))
    ;; ]
    ))

(cond ((executable-find "fdfind")
       (setq fd-dired-program "fdfind"
             projectile-generic-command "fdfind . -0 --type f --color=never"))
      ((executable-find "fd-find")
       (setq fd-dired-program "fd-find"
             projectile-generic-command "fd-find . -0 --type f --color=never"))
      ((executable-find "fd")
       (setq fd-dired-program "fd")))

(with-eval-after-load 'rg
  (rg-enable-default-bindings (kbd "M-g a")))

;; Functions
(defun orderless-first-regexp (pattern index _total)
  (if (= index 0) 'orderless-regexp))

(defun orderless-first-literal (pattern index _total)
  (if (= index 0) 'orderless-literal))

(defun orderless-match-components-cycle ()
  "Components match regexp for the rest of the session."
  (interactive)
  (cl-case (car orderless-transient-matching-styles)
    ;; last in cycle
    (orderless-flex
     (orderless-remove-transient-configuration))
    ;; middle in cycle
    (orderless-regexp
     (setq orderless-transient-matching-styles '(orderless-flex)))
    ;; first in cycle
    (otherwise
     (setq orderless-transient-matching-styles '(orderless-regexp)
           orderless-transient-style-dispatchers '(ignore))))
  (completion--flush-all-sorted-completions)
  (icomplete-pre-command-hook)
  (icomplete-post-command-hook))

(defun nmcli-connect-vpn (up-down name)
  (interactive
   (list
    (completing-read "Choose up/down(up): " '("up" "down") nil t nil nil "up")
    (completing-read "Choose VPN:"
                     (split-string
                      (shell-command-to-string
                       "nmcli --colors no -t -f name con")
                      "\n" t)
                     nil t)))
  (shell-command
   (concat "nmcli --ask --colors no -t con " up-down " \"" name "\"")))

(defun icomplete-vertical-kill-ring-insert (&optional arg)
  "Insert item from kill-ring, selected with completion."
  (interactive "*p")
  (if (or (eq last-command 'yank)
          (if (active-minibuffer-window)
              (setq last-command 'yank)))
      (yank-pop arg)
    (icomplete-vertical-do
        (:separator 'dotted-line :height 20)
      (let ((candidate
             (completing-read
              "Yank: "
              (lambda (string pred action)
                (if (eq action 'metadata)
                    '(metadata (display-sort-function . identity)
                               (cycle-sort-function . identity))
                  (complete-with-action action kill-ring string pred)))
              nil t)))
        (when (and candidate (region-active-p))
          ;; the currently highlighted section is to be replaced by the yank
          (delete-region (region-beginning) (region-end)))
        (insert candidate)))))

(defun completing-read-advice (orig-fun prompt collection &optional
                                        predicate require-match initial-input
                                        hist def inherit-input-method)
  (funcall orig-fun (propertize prompt
                                'face
                                (cl-case require-match
                                  (nil 'hi-green-b)
                                  (t 'hi-red-b)
                                  (confirm 'hi-magenta-b)
                                  (confirm-after-completion 'hi-magenta-b)
                                  (otherwise 'hi-yellow-b)))
           collection predicate require-match initial-input
           hist def inherit-input-method))
(advice-add 'completing-read :around 'completing-read-advice)
(with-eval-after-load 'crm
  (advice-add 'completing-read-multiple :around 'completing-read-advice))

(if (null (require 'noccur nil 'noerror)) ;; noccur--find-files noccur-project
    (message-color #("ERROR missing package `noccur'"
                     0 5 (face error)))
  (when (bug-check-function-bytecode
         'noccur--find-files
         "wyCDCQDEggoAxRjGxwgJIxrIyQohyiIqhw==")
    (require 'pcre2el) ;; rxt-elisp-to-pcre
    (if (executable-find "rg")
        (defun noccur--find-files (regexp)
          (split-string (shell-command-to-string
                         (concat
                          "rg --no-heading --color=never -lH \""
                          (rxt-elisp-to-pcre regexp) "\""))
                        "\n" t))
      (defun noccur--find-files (regexp)
        (let* ((listing-command (if (noccur--within-git-repository-p)
                                    "git ls-files -z"
                                  "find . -type f -print0"))
               (command (format "%s | xargs -0 grep -l \"%s\""
                                listing-command
                                (rxt-elisp-to-pcre regexp))))
          (split-string (shell-command-to-string command) "\n")))))

  (defun occur-project (regexp &optional nlines)
    (interactive (occur-read-primary-args))
    (noccur-project regexp nlines
                        (if (require 'projectile nil 'noerror)
                            (projectile-ensure-project
                             (projectile-project-root))
                          (cdr (project-current))))))


;; Keys
(with-eval-after-load 'simple
  (define-key minibuffer-local-shell-command-map (kbd "M-v")
    'switch-to-completions)
  (define-key read-expression-map (kbd "M-v") 'switch-to-completions))

(define-key minibuffer-local-completion-map (kbd "C-v")
  'orderless-match-components-cycle)

(define-key icomplete-minibuffer-map (kbd "C-k") 'icomplete-fido-kill)
(define-key icomplete-minibuffer-map (kbd "C-d") 'icomplete-fido-delete-char)
(define-key icomplete-minibuffer-map (kbd "RET") 'icomplete-fido-ret)
(define-key icomplete-fido-mode-map (kbd "C-m") nil)
(define-key icomplete-minibuffer-map (kbd "DEL") 'icomplete-fido-backward-updir)
(define-key icomplete-minibuffer-map (kbd "C-j") 'icomplete-fido-exit)
(define-key icomplete-fido-mode-map (kbd "C-j") 'icomplete-fido-exit)
(define-key icomplete-fido-mode-map (kbd "M-j") nil)
(define-key icomplete-minibuffer-map (kbd "C-s") 'icomplete-forward-completions)
(define-key icomplete-minibuffer-map (kbd "C-r") 'icomplete-backward-completions)
(define-key icomplete-minibuffer-map (kbd "C-|") 'icomplete-vertical-toggle)
(define-key icomplete-fido-mode-map (kbd "C-|") 'icomplete-vertical-toggle)
(global-set-key (kbd "M-g M-a") 'occur-project)
(global-set-key (kbd "M-g M-f") 'project-find-file)
(global-set-key (kbd "M-y") 'icomplete-vertical-kill-ring-insert)
(global-set-key (kbd "M-g f") 'fd-dired)
(global-set-key (kbd "M-s O") 'multi-occur)
(global-set-key (kbd "M-s M-o") 'noccur-project)
(global-set-key (kbd "M-s C-o") 'noccur-dired)
(global-set-key
 (kbd "<f12>")
 (lambda ()
   (interactive)
   (message "log: %s" (list completion-cycling minibuffer-default))))

(fido-mode)
(completing-read-at-point-mode)

;;;;;;;;;;;;;;;
;; Show caps ;;
;;;;;;;;;;;;;;;
(require 'dash)
(require 's)

(defun x-led-mask ()
  "Get the current status of the LED mask from X."
  (with-temp-buffer
    (call-process "xset" nil t nil "q")
    (let ((led-mask-string
           (->> (buffer-string)
                s-lines
                (--first (s-contains? "LED mask" it))
                s-split-words
                -last-item)))
      (string-to-number led-mask-string 16))))

(defun caps-lock-on (led-mask)
  "Return non-nil if LED-MASK means caps lock is on."
  (eq (logand led-mask 1) 1))

(define-minor-mode caps-lock-show-mode
  "Display whether caps lock is on."
  :global t
  :lighter (:propertize "⇪" font-lock-face
                        (:foreground "violet" :weight bold))
  (if caps-lock-show-mode
      (set-cursor-color "violet")
    (set-cursor-color "red")))

;;;;;;;;;;;;;;;;
;; Force caps ;;
;;;;;;;;;;;;;;;;
(defun caps-find-bind (key)
  ;; (message "active maps: %s" (mapcar 'keymap-symbol (current-active-maps t)))
  (cl-some (lambda (keymap)
             ;; (message "looking keymap: `%s'" (or (keymap-symbol keymap) keymap))
             (unless (eq keymap modal-mode-map)
               ;; (message "keymap accepted")
               (let ((binding (lookup-key keymap key)))
                 (if (commandp binding)
                     ;; (progn
                     ;;   (message "bind `%s' found in keymap: `%s'" binding (keymap-symbol keymap))
                     binding
                     ;;   )
                   ))))
           (current-active-maps)))

(defun caps-lock--upcase ()
  ;; (message "last-command-event: %s" last-command-event)
  (when (and (characterp last-command-event)
             (< last-command-event 123)
             (< 96 last-command-event))
    (setq last-command-event (upcase last-command-event))
    (unless isearch-mode
      (let ((binding (caps-find-bind (vector last-command-event))))
        (if binding
            (setq real-this-command binding
                  this-original-command binding
                  this-command binding))))))

(defvar caps--post-command-countdown nil)

(define-minor-mode caps-lock-mode
  "Make self-inserting keys invert the capitalization."
  :global t
  :lighter (:propertize "⇪" font-lock-face
                        (:foreground "red" :weight bold))
  (if caps-lock-mode
      (progn
        (when caps--post-command-countdown
          (remove-hook 'post-command-hook 'caps--enable-mode-and-remove-from-hook)
          (setq caps--post-command-countdown nil))
        (add-hook 'pre-command-hook 'caps-lock--upcase))
    (when caps--post-command-countdown
      (remove-hook 'post-command-hook 'caps--disable-mode-and-remove-from-hook)
      (setq caps--post-command-countdown nil))
    (remove-hook 'pre-command-hook 'caps-lock--upcase)))

(defun caps--enable-mode-and-remove-from-hook ()
  (if (< 0 caps--post-command-countdown)
      (cl-decf caps--post-command-countdown)
    (caps-lock-mode 1)))

(defun caps--disable-mode-and-remove-from-hook ()
  (if (< 0 caps--post-command-countdown)
      (cl-decf caps--post-command-countdown)
    (caps-lock-mode 0)))

(defun caps-lock-mode-post-command (times)
  (interactive "p")
  (if caps--post-command-countdown
      (setq caps--post-command-countdown (+ caps--post-command-countdown times 1))
    (when (and (numberp times)
               (< 0 times))
      (if caps-lock-mode
          (progn
            (caps-lock-mode 0)
            (add-hook 'post-command-hook 'caps--enable-mode-and-remove-from-hook))
        (caps-lock-mode 1)
        (add-hook 'post-command-hook 'caps--disable-mode-and-remove-from-hook))
      (setq caps--post-command-countdown times))))

(require 'subword)
(setq minor-mode-alist (assq-delete-all 'subword-mode minor-mode-alist))

(set-face-attribute 'region nil
                    :foreground 'unspecified
                    :background "DarkSlateGray"
                    :box '(:line-width -1 :color "CadetBlue" :style nil))

;; Thanks to: stackoverflow.com/questions/11130546/search-and-replace-inside-a-rectangle-in-emacs
(require 'rect)

(defun rectangle-search-replace
  (start end search-pattern replacement search-function literal)
  "Replace all instances of SEARCH-PATTERN (as found by SEARCH-FUNCTION)
with REPLACEMENT, in each line of the rectangle established by the START
and END buffer positions.

SEARCH-FUNCTION should take the same BOUND and NOERROR arguments as
`search-forward' and `re-search-forward'.

The LITERAL argument is passed to `replace-match' during replacement.

If `case-replace' is nil, do not alter case of replacement text."
  (apply-on-rectangle
   (lambda (start-col end-col search-function search-pattern replacement)
     (move-to-column start-col)
     (let ((bound (min (+ (point) (- end-col start-col))
                       (line-end-position)))
           (fixedcase (not case-replace)))
       (while (funcall search-function search-pattern bound t)
         (replace-match replacement fixedcase literal))))
   start end search-function search-pattern replacement))

(defun rectangle-replace-regexp-read-args (regexp-flag)
  "Interactively read arguments for `rectangle-replace-regexp'
or `rectangle-replace-string' (depending upon REGEXP-FLAG)."
  (let ((args (query-replace-read-args
               (concat "Replace"
                       (if current-prefix-arg " word" "")
                       (if regexp-flag " regexp" " string"))
               regexp-flag)))
    (list (region-beginning) (region-end)
          (nth 0 args) (nth 1 args) (nth 2 args))))

(defun rectangle-replace-regexp
  (start end regexp to-string &optional delimited)
  "Perform a regexp search and replace on each line of a rectangle
established by START and END (interactively, the marked region),
similar to `replace-regexp'.

Optional arg DELIMITED (prefix arg if interactive), if non-nil, means
replace only matches surrounded by word boundaries.

If `case-replace' is nil, do not alter case of replacement text."
  (interactive (rectangle-replace-regexp-read-args t))
  (when delimited
    (setq regexp (concat "\\b" regexp "\\b")))
  (rectangle-search-replace
   start end regexp to-string 're-search-forward nil))

(defun rectangle-replace-string
  (start end from-string to-string &optional delimited)
  "Perform a string search and replace on each line of a rectangle
established by START and END (interactively, the marked region),
similar to `replace-string'.

Optional arg DELIMITED (prefix arg if interactive), if non-nil, means
replace only matches surrounded by word boundaries.

If `case-replace' is nil, do not alter case of replacement text."
  (interactive (rectangle-replace-regexp-read-args nil))
  (let ((search-function 'search-forward))
    (when delimited
      (setq search-function 're-search-forward
            from-string (concat "\\b" (regexp-quote from-string) "\\b")))
    (rectangle-search-replace
     start end from-string to-string search-function t)))

(setq password-cache t
      password-cache-expiry 3600
      auth-sources '((:source "~/.emacs.d/authinfo.gpg"))
      tramp-default-method "ssh"
      auth-source-save-behavior nil)

(defun icomplete-recentf-find-file (arg)
  "Show a list of recent files."
  (interactive "P")
  (require 'recentf)
  (--> recentf-list
       (mapcar #'substring-no-properties it)
       (mapcar #'abbreviate-file-name it)
       (cl-remove-duplicates it :test #'string-equal)
       (let ((minibuffer-completing-file-name t))
         (completing-read "Recent Files: " it nil t))
       (if arg (find-file-other-window it) (find-file it))))
(global-set-key "\C-x\ \C-r" 'icomplete-recentf-find-file)

(with-eval-after-load 'recentf
  (recentf-cleanup)

  ;; (with-eval-after-load 'machine-config
  ;;   (cl-letf (((symbol-function 'sit-for)
  ;;              (lambda (secs))))
  ;;     (let ((tramp-message-show-message nil))
  ;;       (recentf-mode 1))))
  (require 'tramp)
  (defun recentf-remove-sudo-tramp-prefix (path)
    "Remove sudo from path.  Argument PATH is path."
    (if (tramp-tramp-file-p path)
        (let ((tx (tramp-dissect-file-name path)))
          (pcase (tramp-file-name-method tx)
            ("sudo" (tramp-file-name-localname tx))
            ("docker" (if (featurep 'docker) path
                        (tramp-file-name-localname path)))
            (_ path)))
      path))

  (defun local-file-exists-p (filename)
    (file-exists-p (recentf-remove-sudo-tramp-prefix filename)))

  (defun recentf-file-truename (filename)
    (let* ((local-file-name (recentf-remove-sudo-tramp-prefix filename))
           (local-file-truename (file-truename local-file-name)))
      (concat (substring filename 0 (- (length local-file-name))) local-file-truename)))

  (setq recentf-max-saved-items 500
        recentf-max-menu-items 30
        recentf-exclude '("\\.emacs\\.d/elpa/.*\\.el\\'" "\\.el\\.gz\\'")
        recentf-filename-handlers '(recentf-file-truename
                                    abbreviate-file-name)
        recentf-keep '(local-file-exists-p)
        tool-bar-max-label-size 12
        recentf-auto-cleanup 'never
        tool-bar-style 'image)

  (recentf-mode 1))

(savehist-mode 1)

;;  #####
;; #     #  ####  #####  ######
;; #       #    # #    # #
;; #       #    # #    # #####
;; #       #    # #####  #
;; #     # #    # #   #  #
;;  #####   ####  #    # ######
;; (fset 'mt-bounds-of-thing-at-point
;;       (if (require 'thingatpt+ nil t)
;;           #'tap-bounds-of-thing-at-point
;;         #'bounds-of-thing-at-point))
(fset 'mt--bounds-of-thing-at-point
      #'bounds-of-thing-at-point)

(require 'rect)
(require 'ring)
(defvar mt-things
  '((word     . "'w")
    (symbol   . "'s")
    (sexp     . "'e")
    (list     . "'t")
    (defun    . "'d")
    (filename . "'f")
    (url      . "'u")
    (email    . "'m")
    (line     . "'l")))

;; Check list sorted
(defun sorted-p (list op)
  (let ((copy (cl-copy-list list)))
    (equal (sort copy op) list)))

;; [ to
(defvar mt--to-thing-ring nil)
(let ((to-things mt-things))
  (set 'mt--to-thing-ring (make-ring (length to-things)))
  (dolist (elem to-things) (ring-insert mt--to-thing-ring (car elem))))

(defvar mt--to-thing (ring-ref mt--to-thing-ring 0))

(defun mt--cycle-to-things ()
  "Cycle to-things in ring."
  (let ((to-thing (ring-ref mt--to-thing-ring -1)))
    (ring-insert mt--to-thing-ring to-thing)
    (set 'mt--to-thing to-thing)))
;; ]

;; [ from
(defvar mt--from-thing-ring nil)
(let ((from-things mt-things))
  (set 'mt--from-thing-ring (make-ring (length from-things)))
  (dolist (elem from-things) (ring-insert mt--from-thing-ring (car elem))))

(defvar mt--from-thing (ring-ref mt--from-thing-ring 0))

(defun mt--cycle-from-things ()
  "Cycle from-things in ring."
  (let ((from-thing (ring-ref mt--from-thing-ring -1)))
    (ring-insert mt--from-thing-ring from-thing)
    (setq mt--from-thing from-thing
          mt--to-thing from-thing)
    from-thing))
;; ]

(defun mt--bounds-of-thing-at-point-or-region (thing)
  (if (use-region-p)
      (let ((positions (sort (list (mark) (point)) '<)))
        (if rectangle-mark-mode
            (let ((columns (sort (list (progn (goto-char (car positions))
                                              (current-column))
                                       (progn (goto-char (car (cdr positions)))
                                              (current-column))) '<)))
              (cons 'rectangle
                    (cons (progn (goto-char (car positions))
                                 (move-to-column (car columns))
                                 (point))
                          (progn (goto-char (car (cdr positions)))
                                 (move-to-column (car (cdr columns)))
                                 (point)))))
          (cons 'region
                (cons (car positions) (car (cdr positions))))))
    (cons 'bounds
          (mt--bounds-of-thing-at-point thing))))

;;  #####                                               #     #
;; #     #  ####  #    # #    #   ##   #    # #####     #     #  ####   ####  #    #
;; #       #    # ##  ## ##  ##  #  #  ##   # #    #    #     # #    # #    # #   #
;; #       #    # # ## # # ## # #    # # #  # #    #    ####### #    # #    # ####
;; #       #    # #    # #    # ###### #  # # #    #    #     # #    # #    # #  #
;; #     # #    # #    # #    # #    # #   ## #    #    #     # #    # #    # #   #
;;  #####   ####  #    # #    # #    # #    # #####     #     #  ####   ####  #    #
(defvar mt-movement-commands
  #s(hash-table
     size 83
     test eq
     data (
           previous-line t
           next-line t
           right-char t
           right-word t
           forward-char t
           forward-word t
           left-char t
           left-word t
           backward-char t
           backward-word t
           forward-paragraph t
           backward-paragraph t
           forward-list t
           backward-list t
           end-of-buffer t
           end-of-defun t
           end-of-line t
           end-of-sexp t
           end-of-visual-line t
           exchange-point-and-mark t
           move-end-of-line t
           beginning-of-buffer t
           beginning-of-defun t
           beginning-of-line t
           beginning-of-sexp t
           beginning-of-visual-line t
           move-beginning-of-line t
           back-to-indentation t
           subword-forward t
           subword-backward t
           subword-mark t
           subword-kill t
           subword-backward-kill t
           subword-transpose t
           subword-capitalize t
           subword-upcase t
           subword-downcase t
           sp-forward-sexp t
           sp-backward-sexp t
           smart-forward t
           smart-backward t
           smart-up t
           smart-down t
           org-shifttab t
           org-shiftleft t
           org-shiftright t
           org-shiftup t
           org-shiftdown t
           org-shiftcontrolleft t
           org-shiftcontrolright t
           org-shiftcontrolup t
           org-shiftcontroldown t
           org-shiftmetaleft t
           org-shiftmetaright t
           org-shiftmetaup t
           org-shiftmetadown t
           avy-goto-char t
           avy-goto-char-2 t
           avy-goto-char-2-above t
           avy-goto-char-2-below t
           avy-goto-char-in-line t
           avy-goto-char-timer t
           avy-goto-end-of-line t
           avy-goto-line t
           avy-goto-line-above t
           avy-goto-line-below t
           avy-goto-subword-0 t
           avy-goto-subword-1 t
           avy-goto-symbol-1 t
           avy-goto-symbol-1-above t
           avy-goto-symbol-1-below t
           avy-goto-word-0 t
           avy-goto-word-0-above t
           avy-goto-word-0-below t
           avy-goto-word-0-regexp t
           avy-goto-word-1 t
           avy-goto-word-1-above t
           avy-goto-word-1-below t
           avy-goto-word-or-subword-1 t
           magit-previous-line t
           magit-next-line t
           magit-section-backward t
           magit-section-forward t
           magit-section-backward-sibling t
           magit-section-forward-sibling t
           ))
  "Default set of movement commands.")

(defvar mt-interchange-things nil)

(defvar mt--marker nil
  "Beginning of from region marker.")

(defun mt--post-command ()
  (when (and (gethash this-original-command mt-movement-commands)
             (marker-position mt--marker))
    (condition-case raised-error
        (let ((from-bounds (save-excursion
                             (switch-to-buffer (marker-buffer mt--marker))
                             (goto-char (marker-position mt--marker))
                             (mt--bounds-of-thing-at-point mt--from-thing))))
          ;; (message "From %s" from-bounds)
          (if from-bounds
              (if mt-interchange-things
                  (let ((to-bounds (mt--bounds-of-thing-at-point
                                    mt--to-thing)))
                    ;; (message "To %s" to-bounds)
                    (if to-bounds
                        (if (or (<= (cdr from-bounds) (car to-bounds))
                                (<= (cdr to-bounds) (car from-bounds)))
                            (let ((thing (mt--kill-bounds to-bounds)))
                              (save-excursion
                                (switch-to-buffer (marker-buffer mt--marker))
                                (goto-char (marker-position mt--marker))
                                (setq thing (prog1
                                                (mt--kill-bounds
                                                 (mt--bounds-of-thing-at-point mt--from-thing))
                                              (insert thing))))
                              (insert thing))
                          (message "From %s To %s intersect" from-bounds to-bounds))
                      (message "To %s not found" mt--to-thing)))
                (save-excursion
                  (switch-to-buffer (marker-buffer mt--marker))
                  (setq thing (mt--kill-bounds from-bounds)))
                (insert thing))
            (message "From %s not found" mt--from-thing)))
      (error (message "Moving thing: %s" (error-message-string raised-error))))
    (set-marker mt--marker nil)
    (setq mt--mode-line-face 'mt--unselected-face)
    (force-mode-line-update)))

;; #     #
;; ##   ##  ####  #####  ######
;; # # # # #    # #    # #
;; #  #  # #    # #    # #####
;; #     # #    # #    # #
;; #     # #    # #    # #
;; #     #  ####  #####  ######
(defface mt--selected-face
  '((((class color) (background dark))
     (:background "#AAAA33"))
    (((class color) (background light))
     (:background "#FFFFAA")))
  "Correct" :group 'mt-mode)
(defface mt--unselected-face
  '((t :foreground "white" :inherit (mode-line)))
  "Correct" :group 'mode-line)

(defvar mt--mode-line-face 'mt--unselected-face)


(defgroup move-thing ()
  "Move thing minor mode."
  :group 'editing
  :prefix "mt-")

(defcustom mt-mode-line
  '(:eval (propertize
           (concat (cdr (assoc mt--from-thing mt-things))
                   (if mt-interchange-things
                       (cdr (assoc mt--to-thing mt-things))))
           'face mt--mode-line-face))
  "Show current selected thing."
  :group 'move-thing
  :risky t
  :type 'sexp)

(defvar mt-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-j") 'mt-cycle-things)
    (define-key map (kbd "M-k") 'mt-cycle-to-things)
    (define-key map (kbd "M-h") 'mt-toggle-interchange-things)
    ;; (define-key map (kbd "C-p") 'mt-move-up)
    ;; (define-key map (kbd "C-n") 'mt-move-down)
    ;; (define-key map (kbd "C-b") 'mt-move-left)
    ;; (define-key map (kbd "C-f") 'mt-move-right)
    ;; (define-key map (kbd "<up>")     'mt-up)
    ;; (define-key map (kbd "<down>")   'mt-down)
    ;; (define-key map (kbd "<left>")   'mt-backward)
    ;; (define-key map (kbd "<right>")  'mt-forward)
    ;; (define-key map (kbd "<prior>")  'mt-shift-mc-left)
    ;; (define-key map (kbd "<next>")   'mt-shift-mc-right)
    map))

(define-minor-mode mt-mode
  "Toggle Move thing mode."
  :init-value nil
  :lighter mt-mode-line
  :group 'move-thing
  :keymap mt-mode-map
  :global t
  (if mt-mode
      (progn
        (add-hook 'post-command-hook 'mt--post-command)
        (setq mt--marker (make-marker)))
    (setq mt--marker nil)
    (remove-hook 'post-command-hook 'mt--post-command)))

;;              #
;; #####       #  #    #
;; #    #     #   #    #
;; #    #    #    #    #
;; #####    #     # ## #
;; #   #   #      ##  ##
;; #    # #       #    #
(defun mt-insert-rectangle (rectangle arg &optional col)
  (let ((lines (if (<= 0 arg) rectangle (nreverse rectangle)))
        (column (or col (current-column))))
    ;; (undo-boundary)  ; <undo>
    (insert (car lines))
    (setq lines (cdr lines))
    (while lines
      (forward-line arg)
      (or (bolp) (insert ?\n))
      (move-to-column column t)
      (insert (car lines))
      (setq lines (cdr lines)))))

(defun mt-kill-rectangle-or-bounds (arg)
  (unless (cdr arg)
    (error "%s not found, kill imposible" arg))
  (cl-case (car arg)
    (rectangle
     ;; (undo-boundary)  ; <undo>
     (delete-extract-rectangle (car (cdr arg)) (cdr (cdr arg))))
    ((region bounds)
     (prog1
         (list (buffer-substring-no-properties (car (cdr arg)) (cdr (cdr arg))))
       ;; (undo-boundary)  ; <undo>
       (delete-region (car (cdr arg)) (cdr (cdr arg)))))))

(defun mt--kill-bounds (bounds)
  (let ((beg (car bounds))
        (end (cdr bounds)))
    (prog1
        (buffer-substring-no-properties beg end)
      ;; (undo-boundary)  ; <undo>
      (unless buffer-read-only
        (delete-region beg end)))))

(defun mt-kill-bounds (arg)
  (unless arg
    (error "Thing not found, kill imposible"))
  (prog1
      (buffer-substring-no-properties (car arg) (cdr arg))
    ;; (undo-boundary)  ; <undo>
    (delete-region (car arg) (cdr arg))))

;; #     #
;; ##    #   ##   #    # #  ####    ##   ##### #  ####  #    #
;; # #   #  #  #  #    # # #    #  #  #    #   # #    # ##   #
;; #  #  # #    # #    # # #      #    #   #   # #    # # #  #
;; #   # # ###### #    # # #  ### ######   #   # #    # #  # #
;; #    ## #    #  #  #  # #    # #    #   #   # #    # #   ##
;; #     # #    #   ##   #  ####  #    #   #   #  ####  #    #
(defun mt-forward-line (arg &optional column)
  (unless (and (not column) (= 0 arg))
    (or column (setq column (current-column)))
    (unless (= 0 (forward-line arg))
      (error "Buffer limit reached"))
    (= column (move-to-column column))))

(defun mt-exists-thing-at-point (thing)
  (let ((bounds (mt--bounds-of-thing-at-point thing)))
    (and bounds
         (let ((str (buffer-substring-no-properties
                     (car bounds) (cdr bounds))))
           (not (string-equal str "\n"))))))

(defun mt-up-thing (arg &optional column thing)
  (setq arg (- (abs arg))
        thing (or thing mt--to-thing))
  (mt-forward-line arg column)
  (while (not (mt-exists-thing-at-point thing))
    (cl-decf arg)
    (mt-forward-line -1 column))
  (- arg))

(defun mt-down-thing (arg &optional column thing)
  (setq arg (abs arg)
        thing (or thing mt--to-thing))
  (mt-forward-line arg column)
  (while (not (mt-exists-thing-at-point thing))
    (cl-incf arg)
    (mt-forward-line 1 column))
  arg)

(defun mt-forward-thing (arg &optional thing delimiter len)
  (setq thing (or thing mt--to-thing)
        len (or len 1))
  (let (bounds
        pos
        (pos-ini (point)))
    (if delimiter
        (dotimes (i arg)
          (while (not (and
                       (set 'bounds (mt--bounds-of-thing-at-point thing))
                       (set 'pos (point))
                       (not (= pos (cdr bounds)))
                       (< pos-ini pos)
                       (string-match-p delimiter
                                       (buffer-substring-no-properties
                                        (car bounds)
                                        (+ len (car bounds))))))
            (forward-char 1))
          (goto-char (cdr bounds)))
      (dotimes (i arg)
        (while (not (and
                     (set 'bounds (mt--bounds-of-thing-at-point thing))
                     (set 'pos (point))
                     (not (= pos (cdr bounds)))
                     (< pos-ini pos)))
          (forward-char 1))
        (goto-char (cdr bounds))))
    bounds))

(defun mt-backward-thing (arg &optional thing delimiter len)
  (setq thing (or thing mt--to-thing)
        len (or len 1))
  (let (bounds
        pos
        (pos-ini (point)))
    (if delimiter
        (dotimes (i arg)
          (while (not (and
                       (set 'bounds (mt--bounds-of-thing-at-point thing))
                       (set 'pos (point))
                       (not (= pos (car bounds)))
                       (> pos-ini pos)
                       (string-match-p delimiter
                                       (buffer-substring-no-properties
                                        (car bounds)
                                        (+ len (car bounds))))))
            (backward-char 1))
          (goto-char (car bounds)))
      (dotimes (i arg)
        (while (not (and
                     (set 'bounds (mt--bounds-of-thing-at-point thing))
                     (not (= (point) (car bounds)))))
          (backward-char 1))
        (goto-char (car bounds))))
    bounds))


;; #     #
;; ##   ##  ####  #    # ###### #    # ###### #    # #####
;; # # # # #    # #    # #      ##  ## #      ##   #   #
;; #  #  # #    # #    # #####  # ## # #####  # #  #   #
;; #     # #    # #    # #      #    # #      #  # #   #
;; #     # #    #  #  #  #      #    # #      #   ##   #
;; #     #  ####    ##   ###### #    # ###### #    #   #
(defun mt-newline-ending (str)
  (char-equal ?\n (aref str (1- (length str)))))

(defun mt-push-mark (type)
  (cl-case type
    (rectangle
     (rectangle-mark-mode)
     (push-mark)
     (setq deactivate-mark nil))
    (region
     (push-mark)
     (setq deactivate-mark nil))))

(defun mt-push-mark-all (type)
  (cl-case type
    (rectangle
     (rectangle-mark-mode)
     (push-mark)
     (setq deactivate-mark nil))
    (region
     (push-mark)
     (setq deactivate-mark nil))
    (bounds
     (set-mark (point))
     (setq deactivate-mark nil))))

(defun mt-move-thing-up (arg)
  (mt-move-thing-down (- arg)))

(defun mt-move-thing-down (arg)
  (let* ((from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing))
         (from (mt-kill-rectangle-or-bounds from-sbs))
         (column (current-column)))
    (goto-char (car (cdr from-sbs)))
    (forward-line arg)
    (move-to-column column t)
    (let ((pos (point)))
      (mt-insert-rectangle from 1 column)
      (mt-push-mark-all (car from-sbs))
      (goto-char pos))))

(defun mt-move-thing-backward (arg)
  (mt-move-thing-forward (- arg)))

(defun mt-move-thing-forward (arg)
  (let* ((from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing))
         (from (mt-kill-rectangle-or-bounds from-sbs)))
    (goto-char (car (cdr from-sbs)))
    (forward-char arg)
    (let ((pos (point)))
      (mt-insert-rectangle from 1)
      (mt-push-mark-all (car from-sbs))
      (goto-char pos))))

(defun mt-interchange-thing-up (arg)
  (let* ((column (current-column))
         (from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing))
         (from (mt-kill-rectangle-or-bounds from-sbs)))
    (goto-char (car (cdr from-sbs)))
    (mt-up-thing arg column mt--to-thing)
    (let* ((to-bs (mt--bounds-of-thing-at-point mt--to-thing))
           (to (mt-kill-bounds to-bs)))
      (goto-char (- (car (cdr from-sbs)) (length to)))
      ;; (undo-boundary)  ; <undo>
      (insert to)
      (goto-char (car to-bs))
      (mt-insert-rectangle from 1 column)
      (mt-push-mark (car from-sbs))
      (goto-char (car to-bs)))))
(advice-add 'mt-interchange-thing-up :around #'rollback-on-error-advice)

(defun mt-interchange-thing-down (arg)
  (let* ((column (current-column))
         (from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing))
         (from (mt-kill-rectangle-or-bounds from-sbs)))
    (goto-char (car (cdr from-sbs)))
    (mt-forward-line (1- (length from)))
    (when (mt-newline-ending (car from))
      (cl-decf arg))
    (mt-down-thing arg column mt--to-thing)
    (let* ((to-bs (mt--bounds-of-thing-at-point mt--to-thing))
           (to (mt-kill-bounds to-bs)))
      (goto-char (car (cdr from-sbs)))
      ;; (undo-boundary)  ; <undo>
      (insert to)
      (let ((pos (+ (length to) (car to-bs))))
        (goto-char pos)
        (mt-insert-rectangle from 1 column)
        (mt-push-mark (car from-sbs))
        (goto-char pos)))))
(advice-add 'mt-interchange-thing-down :around #'rollback-on-error-advice)

(defun mt-interchange-thing-backward (arg)
  (let ((from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing)))
    (goto-char (car (cdr from-sbs)))
    (mt-backward-thing arg mt--to-thing
                       (and (eq mt--to-thing 'sexp)
                            (let* ((pos (car (cdr from-sbs)))
                                   (delimiter (buffer-substring-no-properties
                                               pos (1+ pos))))
                              (if (member
                                   delimiter
                                   '("\"" "'" "(" "{" "["))
                                  delimiter
                                "[^\"'({[]"))))
    (let* ((to-bs (mt--bounds-of-thing-at-point mt--to-thing))
           (from (mt-kill-rectangle-or-bounds from-sbs))
           (to (mt-kill-bounds to-bs)))
      (goto-char (- (car (cdr from-sbs)) (length to)))
      ;; (undo-boundary)  ; <undo>
      (insert to)
      (goto-char (car to-bs))
      (mt-insert-rectangle from 1)
      (mt-push-mark (car from-sbs))
      (goto-char (car to-bs)))))
(advice-add 'mt-interchange-thing-backward :around #'rollback-on-error-advice)

(defun mt-interchange-thing-forward (arg)
  (let* ((from-sbs (mt--bounds-of-thing-at-point-or-region mt--from-thing))
         (from (mt-kill-rectangle-or-bounds from-sbs)))
    (goto-char (car (cdr from-sbs)))
    (goto-char (car (mt-forward-thing arg mt--to-thing
                                      (and (eq mt--to-thing 'sexp)
                                           (let ((delimiter (substring (car from) 0 1)))
                                             (if (member
                                                  delimiter
                                                  '("\"" "'" "(" "{" "["))
                                                 delimiter
                                               "[^\"'({[]"))))))
    (let* ((to-bs (mt--bounds-of-thing-at-point mt--to-thing))
           (to (mt-kill-bounds to-bs)))
      (goto-char (car (cdr from-sbs)))
      ;; (undo-boundary)  ; <undo>
      (insert to)
      (let ((pos (+ (length to) (car to-bs))))
        (goto-char pos)
        (mt-insert-rectangle from 1)
        (mt-push-mark (car from-sbs))
        (goto-char pos)))))
(advice-add 'mt-interchange-thing-forward :around #'rollback-on-error-advice)

(defun mt-shift-points-left (bounds)
  (let* ((strings (mapcar
                   (lambda (b)
                     (buffer-substring-no-properties (car b) (cdr b)))
                   bounds))
         (item (pop strings))
         (last-correction 0)
         (lengths (mapcar (lambda (b) (- (cdr b) (car b))) bounds))
         (paste-lengths (cons 0 (cdr lengths)))
         (cut-lengths (cons 0 lengths))
         (positions (cl-mapcar
                     (lambda (b c p)
                       (setq last-correction (+ last-correction
                                                (- p c)))
                       (+ (car b) last-correction))
                     bounds
                     cut-lengths
                     paste-lengths))
         (new-bounds (cl-mapcar
                      (lambda (p l)
                        (cons p (+ p l)))
                      positions
                      (nconc (cdr lengths) (list (car lengths))))))
    (setq strings (nreverse strings)
          bounds (nreverse bounds))
    (push item strings)
    (while strings
      (let ((bound (pop bounds)))
        (delete-region (car bound) (cdr bound))
        (goto-char (car bound))
        (insert (pop strings))))
    new-bounds))

(defun mt-shift-points-right (bounds)
  (let* ((strings (mapcar
                   (lambda (b)
                     (buffer-substring-no-properties (car b) (cdr b)))
                   bounds))
         (last-correnction 0)
         (lengths (mapcar (lambda (b) (- (cdr b) (car b))) bounds))
         (cut-lengths (cons 0 lengths))
         (final-lengths (cons (car (last lengths)) lengths))
         (paste-lengths (cons 0 final-lengths))
         (positions (cl-mapcar
                     (lambda (b c p)
                       (setq last-correnction (+ last-correnction
                                                 (- p c)))
                       (+ (car b) last-correnction))
                     bounds
                     cut-lengths
                     paste-lengths))
         (new-bounds (cl-mapcar
                      (lambda (p l)
                        (cons p (+ p l)))
                      positions
                      final-lengths)))
    (push (elt strings (1- (length strings))) strings)
    (setq strings (nreverse strings)
          bounds (nreverse bounds))
    (pop strings)
    (while strings
      (let ((bound (pop bounds)))
        (delete-region (car bound) (cdr bound))
        (goto-char (car bound))
        (insert (pop strings))))
    new-bounds))

(defun mt-shift-points (points arg)
  (let ((bounds
         (mapcar
          (lambda (pos)
            (goto-char pos)
            (mt--bounds-of-thing-at-point mt--from-thing))
          (sort points '<)))
        (neg (> 0 arg))
        listed-bounds)
    (mapc (lambda (x)
            (push (car x) listed-bounds)
            (push (cdr x) listed-bounds)) bounds)
    (if (not (sorted-p listed-bounds '>))
        (error "move-thing: %s's bounds overlap" mt--from-thing)
      (if neg
          (dotimes (i (- arg) bounds)
            (setq bounds (mt-shift-points-left bounds)))
        (dotimes (i arg bounds)
          (setq bounds (mt-shift-points-right bounds)))))))
(advice-add 'mt-shift-points :around #'rollback-on-error-advice)

;; ###
;;  #  #    # ##### ###### #####    ##    ####  ##### # #    # ######
;;  #  ##   #   #   #      #    #  #  #  #    #   #   # #    # #
;;  #  # #  #   #   #####  #    # #    # #        #   # #    # #####
;;  #  #  # #   #   #      #####  ###### #        #   # #    # #
;;  #  #   ##   #   #      #   #  #    # #    #   #   #  #  #  #
;; ### #    #   #   ###### #    # #    #  ####    #   #   ##   ######
(defun mt-cycle-things (arg)
  "Cycle things in ring."
  (interactive "P")
  (setq mt--mode-line-face 'mt--selected-face)
  (force-mode-line-update)
  (set-marker mt--marker (point))
  (if (or (eq last-command 'mt-cycle-things) arg)
      (if (not (eql mt--from-thing mt--to-thing))
          (while (not (eql mt--from-thing mt--to-thing))
            (mt--cycle-to-things))
        (let ((init-thing (ring-ref mt--from-thing-ring 0))
              current-thing found)
          (while (not (or found
                          (eql init-thing current-thing)))
            (setq found t
                  current-thing (mt--cycle-from-things))
            (condition-case nil
                (let ((bounds (mt--bounds-of-thing-at-point current-thing)))
                  (pulse-momentary-highlight-region (car bounds) (cdr bounds)))
              (error (set 'found nil))))))
    (condition-case nil
        (let ((bounds (mt--bounds-of-thing-at-point mt--from-thing)))
          (pulse-momentary-highlight-region (car bounds) (cdr bounds)))
      (error (mt-cycle-things t)))))

(defun mt-cycle-to-things ()
  (interactive)
  (mt--cycle-to-things)
  (force-mode-line-update))

(defun mt-toggle-interchange-things ()
  (interactive)
  (set-marker mt--marker nil)
  (setq mt--mode-line-face 'mt--unselected-face)
  (setq mt-interchange-things (not mt-interchange-things))
  (force-mode-line-update))

(defun mt-shift-mc-left (arg)
  (interactive "p")
  (mt-shift-mc-right (- arg)))

(defun mt-shift-mc-right (arg)
  (interactive "p")
  (let* ((bounds (mt-shift-points
                 (cons (point)
                       (mapcar
                        (lambda (x)
                          (overlay-get x 'point))
                        (mc/all-fake-cursors)))
                 arg))
         (bound (pop bounds)))
    (mc/remove-fake-cursors)
    (dolist (b bounds)
      (goto-char (car b))
      (mc/create-fake-cursor-at-point))
    (goto-char (car bound))))

(defun mt-move-down (arg)
  (interactive "p")
  (if mt-interchange-things
      (mt-interchange-thing-down arg)
    (mt-move-thing-down arg)))

(defun mt-move-up (arg)
  (interactive "p")
  (if mt-interchange-things
      (mt-interchange-thing-up arg)
    (mt-move-thing-up arg)))

(defun mt-move-right (arg)
  (interactive "p")
  (if mt-interchange-things
      (mt-interchange-thing-forward arg)
    (mt-move-thing-forward arg)))

(defun mt-move-left (arg)
  (interactive "p")
  (if mt-interchange-things
      (mt-interchange-thing-backward arg)
    (mt-move-thing-backward arg)))

(defun mt-up (arg)
  (interactive "p")
  (mt-up-thing arg))

(defun mt-down (arg)
  (interactive "p")
  (mt-down-thing arg))

(defun mt-backward (arg)
  (interactive "p")
  (mt-backward-thing arg))

(defun mt-forward (arg)
  (interactive "p")
  (mt-forward-thing arg))

(defun push-mark--pre-command ()
  (when (and (null mark-active)
             (gethash this-original-command mt-movement-commands)
             (not (gethash last-command mt-movement-commands)))
    (push-mark nil t)))
(add-hook 'pre-command-hook 'push-mark--pre-command)

;; (defvar multiple-windows-mode-map
;;   (let (map (make-keymap))
;;     (set-char-table-range (nth 1 map) t #'multiple-windows--keypressed)
;;     (define-key map [escape] #'multiple-windows-mode)
;;     map))

(defvar multiple-windows--isearch-direction nil
  "Last isearch direction")

(defvar multiple-windows--default-cmds-prepare-alist
  '((isearch-forward . (setq multiple-windows--isearch-direction 'forward))
    (isearch-backward . (setq multiple-windows--isearch-direction 'backward))))

(defvar multiple-windows--default-cmds-remap-alist
  `((isearch-exit . ,(lambda ()
                       (interactive)
                       (isearch-repeat multiple-windows--isearch-direction))))
  "Default set of commands that should be mirrored by all cursors")

(defvar multiple-windows--default-cmds-to-run-for-all
  '(mc/keyboard-quit
    self-insert-command
    quoted-insert
    previous-line
    next-line
    newline
    newline-and-indent
    open-line
    delete-blank-lines
    transpose-chars
    transpose-lines
    transpose-paragraphs
    transpose-regions
    join-line
    right-char
    right-word
    forward-char
    forward-word
    left-char
    left-word
    backward-char
    backward-word
    forward-paragraph
    backward-paragraph
    upcase-word
    downcase-word
    capitalize-word
    forward-list
    backward-list
    hippie-expand
    hippie-expand-lines
    yank
    yank-pop
    append-next-kill
    kill-line
    kill-region
    kill-whole-line
    kill-word
    backward-kill-word
    backward-delete-char-untabify
    delete-char delete-forward-char
    delete-backward-char
    py-electric-backspace
    c-electric-backspace
    org-delete-backward-char
    cperl-electric-backspace
    python-indent-dedent-line-backspace
    paredit-backward-delete
    autopair-backspace
    just-one-space
    zap-to-char
    end-of-buffer
    end-of-defun
    end-of-line
    end-of-sexp
    set-mark-command
    exchange-point-and-mark
    cua-set-mark
    cua-replace-region
    cua-delete-region
    move-end-of-line
    beginning-of-buffer
    beginning-of-defun
    beginning-of-line
    beginning-of-sexp
    move-beginning-of-line
    kill-ring-save
    back-to-indentation
    subword-forward
    subword-backward
    subword-mark
    subword-kill
    subword-backward-kill
    subword-transpose
    subword-capitalize
    subword-upcase
    subword-downcase
    er/expand-region
    er/contract-region
    smart-forward
    smart-backward
    smart-up
    smart-down
    undo-tree-redo
    undo-tree-undo)
  "Default set of commands that should be mirrored by all cursors")

(defun multiple-windows--post-command ()
  (let ((prepare (alist-get this-original-command
                            multiple-windows--default-cmds-prepare-alist)))
    (if prepare (eval prepare)))
  (catch 'break
    (let ((cmd (or (alist-get this-original-command
                              multiple-windows--default-cmds-remap-alist)
                   (car (memq this-original-command
                              multiple-windows--default-cmds-to-run-for-all))
                   (throw 'break nil))))
      (save-selected-window
        (dolist (other-window (cdr (window-list (selected-frame) 0 (selected-window))))
          (select-window other-window)
          (condition-case-unless-debug raised-error
              (call-interactively cmd)
            (error (message "%s: %s %s"
                            cmd
                            (error-message-string raised-error)
                            other-window))))))))

(define-minor-mode multiple-windows-mode
  "Toggle Multiple Windows mode.
     With no argument, this command toggles the mode.
     Non-null prefix argument turns on the mode.
     Null prefix argument turns off the mode."
  :init-value nil
  :lighter "*"
  :group 'multiple-windows
  (if multiple-windows-mode
      (add-hook 'post-command-hook 'multiple-windows--post-command nil t)
    (remove-hook 'post-command-hook 'multiple-windows--post-command t)))

;; SMerge hydra menu
(with-eval-after-load 'hydra
  (eval-when-compile
    (require 'smerge-mode))
  (defhydra hydra-smerge
    (:foreign-keys run :hint nil :pre (smerge-mode 1))
    "
^Move^     ^Keep^     ^Diff^       ^Pair^
^^^^^^^^---------------------------------------------
_C-n_ext   _C-b_ase   _C-r_efine   _C-<_: base-upper
_C-p_rev   _C-u_pper  _C-e_diff    _C-=_: upper-lower
^   ^      _C-l_ower  _C-c_ombine  _C->_: base-lower
^   ^      _C-a_ll    _C-r_esolve
"
    ("C-RET" smerge-keep-current "current")
    ("C-c"   smerge-combine-with-next)
    ("C-e"   smerge-ediff)
    ("C-r"   smerge-refine)
    ("C-a"   smerge-keep-all)
    ("C-b"   smerge-keep-base)
    ("C-u"   smerge-keep-upper)
    ("C-n"   smerge-next)
    ("C-l"   smerge-keep-lower)
    ("C-p"   smerge-prev)
    ("C-r"   smerge-resolve)
    ("C-<"   smerge-diff-base-upper)
    ("C-="   smerge-diff-upper-lower)
    ("C->"   smerge-diff-base-lower)
    ("M-q" nil "quit"))

  (global-set-key (kbd "C-x v m") #'hydra-smerge/body))

(require 'hi-lock)
(setq minor-mode-alist (assq-delete-all 'hi-lock-mode minor-mode-alist))
(setcdr hi-lock-map nil)

(setq hi-lock-highlight-range 200000)
;;;;;;;;;;;
;; Faces ;;
;;;;;;;;;;;
(defface hi-yellow-b
  '((((min-colors 88)) (:weight bold :foreground "yellow1"))
    (t (:weight bold :foreground "yellow")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-yellow-l
  '((((min-colors 88)) (:weight light :foreground "yellow1"))
    (t (:weight light :foreground "yellow")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-magenta-b
  '((((min-colors 88)) (:weight bold :foreground "magenta1"))
    (t (:weight bold :foreground "magenta")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-magenta-l
  '((((min-colors 88)) (:weight light :foreground "magenta1"))
    (t (:weight light :foreground "magenta")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-blue-l
  '((((min-colors 88)) (:weight light :foreground "blue1"))
    (t (:weight light :foreground "blue")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-green-l
  '((((min-colors 88)) (:weight light :foreground "green1"))
    (t (:weight light :foreground "green")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-red-l
  '((((min-colors 88)) (:weight light :foreground "red1"))
    (t (:weight light :foreground "red")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;
(require 'pulse)
(setq pulse-flag t)
(defun pulse-momentary-highlight-current-line (delay)
  (interactive (list 1.2))
  (let ((pulse-delay (/ delay pulse-iterations)))
    (pulse-momentary-highlight-one-line (point))))


(defun hl-smaller-5 ()
  "Highlight nunbers smaller than 5."
  (interactive)
  (highlight-regexp " [0-4]\\.[0-9]* " 'hi-red-b))

(defun unhl-smaller-5 ()
  "Unhighlight nunbers smaller than 5."
  (interactive)
  (unhighlight-regexp " [0-4]\\.[0-9]* "))

(defun hl-advices ()
  "Highlight advices."
  (interactive)
  (highlight-regexp "\\_<error\\_>" 'hi-red-b)
  (highlight-regexp "\\_<warn\\_>" 'hi-yellow-b)
  (highlight-regexp "\\_<warning\\_>" 'hi-yellow-b)
  (highlight-regexp "\\_<debug\\_>" 'hi-green-l)
  (highlight-regexp "\\_<info\\_>" 'hi-blue-l)
  (highlight-regexp "\\_<information\\_>" 'hi-blue-l)
  (highlight-regexp "\\_<assertion\\_>" 'hi-yellow)
  (highlight-regexp "\\_<ERROR\\_>" 'hi-red-b)
  (highlight-regexp "\\_<WARN\\_>" 'hi-yellow-b)
  (highlight-regexp "\\_<WARNING\\_>" 'hi-yellow-b)
  (highlight-regexp "\\_<DEBUG\\_>" 'hi-green-l)
  (highlight-regexp "\\_<INFO\\_>" 'hi-blue-l)
  (highlight-regexp "\\_<INFORMATION\\_>" 'hi-blue-l)
  (highlight-regexp "\\_<ASSERTION\\_>" 'hi-yellow))

(defun unhl-advices ()
  "Unhighlight advices."
  (interactive)
  (unhighlight-regexp "\\_<error\\_>")
  (unhighlight-regexp "\\_<warn\\_>")
  (unhighlight-regexp "\\_<warning\\_>")
  (unhighlight-regexp "\\_<debug\\_>")
  (unhighlight-regexp "\\_<info\\_>")
  (unhighlight-regexp "\\_<information\\_>")
  (unhighlight-regexp "\\_<assertion\\_>")
  (unhighlight-regexp "\\_<ERROR\\_>")
  (unhighlight-regexp "\\_<WARN\\_>")
  (unhighlight-regexp "\\_<WARNING\\_>")
  (unhighlight-regexp "\\_<DEBUG\\_>")
  (unhighlight-regexp "\\_<INFO\\_>")
  (unhighlight-regexp "\\_<INFORMATION\\_>")
  (unhighlight-regexp "\\_<ASSERTION\\_>"))

(defun hl-apirest ()
  (interactive)
  (highlight-regexp "\\_<GET\\_>" 'hi-green-b)
  (highlight-regexp "\\_<POST\\_>" 'hi-green-b)
  (highlight-regexp "\\_<PUT\\_>" 'hi-green-b)
  (highlight-regexp "\\_<PATCH\\_>" 'hi-green-b)
  (highlight-regexp "\\_<DELETE\\_>" 'hi-green-b))

(defun unhl-apirest ()
  (interactive)
  (unhighlight-regexp "\\_<GET\\_>")
  (unhighlight-regexp "\\_<POST\\_>")
  (unhighlight-regexp "\\_<PUT\\_>")
  (unhighlight-regexp "\\_<PATCH\\_>")
  (unhighlight-regexp "\\_<DELETE\\_>"))

(defun hl-ip ()
  (interactive)
  (highlight-regexp "[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}" 'hi-magenta-l))

(defun unhl-ip ()
  (interactive)
  (unhighlight-regexp "[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}\\.[0-9]\\{1,3\\}"))

;; datetime
(defvar hl-datetime-today-last nil)
(make-variable-buffer-local 'hl-datetime-today-last)

(defun hl-datetime ()
  "Highlight today date."
  (interactive)
  (highlight-regexp "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" 'hi-yellow-l)
  (let ((date (format-time-string "%Y-%m-%d")))
    (if hl-datetime-today-last
        (unless (string-equal date hl-datetime-today-last)
          (unhighlight-regexp hl-datetime-today-last)
          (setq hl-datetime-today-last date))
      (setq hl-datetime-today-last date)))
  (highlight-regexp hl-datetime-today-last 'hi-yellow-b)
  (highlight-regexp "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]" 'hi-yellow-l))

(defun unhl-datetime ()
  "Highlight today date."
  (interactive)
  (if hl-datetime-today-last
      (unhighlight-regexp hl-datetime-today-last))
  (unhighlight-regexp "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]")
  (unhighlight-regexp "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]"))

(defun hl-log ()
  (interactive)
  (hl-ip)
  (hl-advices)
  (hl-datetime)
  (hl-apirest))

(defun unhl-log ()
  (interactive)
  (unhl-ip)
  (unhl-advices)
  (unhl-datetime)
  (unhl-apirest))

;; [ conflict with objed with (setq objed-use-hl nil)
(require 'hl-line+)
;; ]
(hl-line-when-idle-interval 0.3)
(toggle-hl-line-when-idle 1)

(require 'hl-line)
(set-face-attribute 'hl-line nil
                    :foreground 'unspecified
                    :background "#000000"
                    :overline 'unspecified
                    :underline 'unspecified
                    :box 'unspecified
                    :inherit 'unspecified)
(global-hl-line-mode 1)

(defun whitespace-case-mode-configuration ()
  (interactive)
  (cond
   ;; ‘mode-name’
   ;; Usually a string, but can use any of the constructs for
   ;; ‘mode-line-format’, which see.
   ;; Format with ‘format-mode-line’ to produce a string value.
   ;; Don't use ‘string-equal’ to compare
   ((derived-mode-p 'c-mode)
    (set (make-local-variable 'whitespace-line-column) 100)
    (setq tab-width 4))
   ((derived-mode-p 'python-mode)
    (set (make-local-variable 'whitespace-line-column) 79)
    (setq tab-width 4))
   ((derived-mode-p 'emacs-lisp-mode)
    (set (make-local-variable 'whitespace-line-column) 100)
    (set (make-local-variable 'whitespace-display-mappings)
         '((newline-mark 10   [8629 10] [36 10])
           (tab-mark     9    [8676 32 32 32 32 32 8677 32] [92 9])))
    (setq tab-width 8))
   ((derived-mode-p 'json-mode)
    (setq tab-width 2))
   (t
    (setq tab-width 4)))
  (whitespace-mode))
(add-hook 'prog-mode-hook #'whitespace-case-mode-configuration)
(add-hook 'csv-mode-hook #'whitespace-mode)

(defun whitespace-toggle-lines-tail ()
  (interactive)
  (if (bound-and-true-p whitespace-mode)
      (call-interactively #'whitespace-mode))
  (if (memq 'lines-tail whitespace-style)
      (setq whitespace-style (delq 'lines-tail whitespace-style))
    (push 'lines-tail whitespace-style))
  (call-interactively #'whitespace-mode))


;; ·  183   MIDDLE DOT
;; ¶  182   PILCROW SIGN
;; ↵  8629  DOWNWARDS ARROW WITH CORNER LEFTWARDS
;; ↩  8617  LEFTWARDS ARROW WITH HOOK
;; ⏎  9166  RETURN SYMBOL
;; ▷  9655  WHITE RIGHT POINTING TRIANGLE
;; ▶  9654  BLACK RIGHT-POINTING TRIANGLE
;; →  8594  RIGHTWARDS ARROW
;; ↦  8614  RIGHTWARDS ARROW FROM BAR
;; ⇤  8676  LEFTWARDS ARROW TO BAR
;; ⇥  8677  RIGHTWARDS ARROW TO BAR
;; ⇨  8680  RIGHTWARDS WHITE ARROW
(eval-and-when-daemon frame
  (setq whitespace-style '(face
                           tab
                           newline
                           tab-mark
                           newline-mark
                           ;; spaces
                           )
        ;; whitespace-space-regexp "\\( \\{2,\\}\\)"
        ;; whitespace-hspace-regexp "\\(\xA0\\{2,\\}\\)"
        whitespace-display-mappings
        '(;; (space-mark   ?\    [?.])
          ;; (space-mark   ?\xA0 [?_])
          (newline-mark 10    [8629 10] [36 10])
          (tab-mark     9     [8676 32 8677 32] [92 9]))))
(with-eval-after-load 'whitespace
  (dolist (mode '(whitespace-mode
                  global-whitespace-mode
                  global-whitespace-newline-mode
                  whitespace-newline-mode))
    (setq minor-mode-alist (assq-delete-all mode minor-mode-alist)))
  (set-face-attribute 'whitespace-space nil
                      :foreground 'unspecified
                      :background "grey40")
  (set-face-attribute 'whitespace-hspace nil
                      :foreground 'unspecified
                      :background "grey50"))

(defun whitespace-toggle-marks ()
  (interactive)
  (if (bound-and-true-p whitespace-mode)
      (call-interactively #'whitespace-mode))
  (if (member '(newline-mark 10   [36 10]) whitespace-display-mappings)
      (setq whitespace-display-mappings
            '((newline-mark 10   [8629 10] [36 10])
              (tab-mark     9    [8676 32 8677 32] [92 9])))
    (setq whitespace-display-mappings
          '((newline-mark 10   [36 10])
            (tab-mark     9    [46 95 46 32]))))
  (call-interactively #'whitespace-mode))

(global-set-key (kbd "M-s 7 l") #'whitespace-toggle-lines-tail)
(global-set-key (kbd "M-s 7 SPC") #'whitespace-toggle-marks)

;; [ expensive
(require 'display-line-numbers)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
;; ]
(with-eval-after-load 'display-line-numbers
  (setq line-number-display-limit large-file-warning-threshold
        line-number-display-limit-width 3000
        display-line-numbers-width-start t
        ;; t is expensive
        display-line-numbers-grow-only nil
        display-line-numbers-type 'visual)

  (defvar display-line-type-selected-last-buffer nil)
  (defun display-line-type-by-selected (window-or-frame)
    (when (buffer-live-p display-line-type-selected-last-buffer)
      (with-current-buffer display-line-type-selected-last-buffer
        (setq display-line-numbers t))
      (setq display-line-type-selected-last-buffer nil))
    (when (and display-line-numbers-mode
               (derived-mode-p 'prog-mode))
      (unless (eq display-line-numbers 'visual)
        (setq display-line-numbers 'visual))
      (setq display-line-type-selected-last-buffer (current-buffer))))
  (add-hook 'window-selection-change-functions 'display-line-type-by-selected))

(defvar language-url-builder #'language-url-wordreference)
(defvar language-phonemic-script-regex ">/\\([^/]*\\)/<")
(defvar language-translation-regex-wordreference "class='ToWrd' >\\([^<]*\\)<")
(defvar language-items-number 6)

(defun decode-coding-string-to-current (string)
  "Decode STRING to buffer file codings system."
  (decode-coding-string string buffer-file-coding-system))

(defun language-url-wordreference (word &optional from to)
  "Build url request for WORD translation from language FROM to language TO."
  (if to
      (if (string-equal from "en")
          (format "http://www.wordreference.com/%s/translation.asp?tranword=%s" to word)
        (format "http://www.wordreference.com/%s/%s/translation.asp?tranword=%s" from to word))
    (cond
     ((string-equal from "es")
      (concat "http://www.wordreference.com/definicion/" word))
     (t
      (concat "http://www.wordreference.com/definition/" word)))))

(defun language-url-request-to-buffer (word &optional from to)
  "Synchronous request translation of WORD from language FROM to language TO."
  (url-retrieve-synchronously
       (funcall language-url-builder word from to)))

(defun language-get-phonemic-script (word &optional from)
  "Get phonemic script of WORD in language FROM."
  (with-current-buffer
      (language-url-request-to-buffer word from)
    (goto-char (point-min))
    (if (re-search-forward language-phonemic-script-regex nil t)
        (match-string 1)
      (error "Phonemic script not found"))))

(defun language-get-translation (word from to &optional items)
  "Get items posible translations of WORD from FROM to TO.
If no ITEMS `language-items-number'."
  (with-current-buffer
      (language-url-request-to-buffer word from to)
    (goto-char (point-min))
    (let ((matches ())
          (items-number (or items language-items-number)))
      (while (and (re-search-forward language-translation-regex-wordreference nil t)
                  (< 0 items-number))
        (let ((item (string-trim (match-string 1))))
          (unless (member item matches)
            (cl-decf items-number)
            (push item matches))))
      (if matches
          (nreverse matches)
        (error "Translation not found")))))

;; (require 'subr-x)
;; (defun language-get-phonemic-script-and-translation (word from to &optional items)
;;   "Get ITEMS posible translations of WORD from FROM to TO, with phonemic script."
;;   (with-current-buffer
;;       (language-url-request-to-buffer word from to)
;;     (goto-char (point-min))
;;     (if (re-search-forward language-phonemic-script-regex nil t)
;;         (let ((matches ())
;;               (items-number (or items language-items-number))
;;               (phonemic-script (decode-coding-string (match-string 1) 'utf-8)))
;;           (while (and (re-search-forward language-translation-regex-wordreference nil t)
;;                       (< 0 items-number))
;;             (let ((item (string-trim (match-string 1))))
;;               (unless (member item matches)
;;                 (cl-decf items-number)
;;                 (push item matches))))
;;           (cons phonemic-script (nreverse matches)))
;;       (error "Phonemic script not found"))))

(defun language-goto-insertion-point ()
  "Goto proper insertion point."
  (let ((curr-char (char-after (point))))
    (condition-case-unless-debug nil
        (when (and curr-char
                   (memq (get-char-code-property curr-char 'general-category)
                         '(Ll Lu Lo Lt Lm Mn Mc Me Nl)))
          (right-word 1))
      (error nil))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interactive functions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'thingatpt)
;;(mapconcat 'identity matches ", ")

(defun language-en-es-translation-at-point (&optional items)
  "Get ITEMS translations of the word at point.
By default insert it, with prefix display a message with it."
  (interactive "P")
  (cond
   ((or (equal items '(4))
        buffer-read-only)
    (let ((translation
           (language-get-translation
            (thing-at-point 'word 'no-properties) "en" "es" 3)))
      (message (mapconcat 'decode-coding-string-to-current
                          translation ", "))))
   (t
    (let ((translation
           (language-get-translation
            (thing-at-point 'word 'no-properties) "en" "es" items)))
      (language-goto-insertion-point)
      (insert
       (concat " "
               (mapconcat 'decode-coding-string-to-current
                          translation ", ")))))))

(defun language-en-es-phonemic-script-and-translation-at-point (&optional items)
  "Get the phonemic script and ITEMS translations of the word at point.
By default insert it, with prefix display a message with it."
  (interactive "P")
  (cond
   ((or (equal items '(4))
        buffer-read-only)
    (let ((translation
           `(,(language-get-phonemic-script (thing-at-point 'word 'no-properties)) .
             ,(language-get-translation
               (thing-at-point 'word 'no-properties) "en" "es" 3))))
      (message
       (concat "/"
               (decode-coding-string-to-current (car translation))
               "/ "
               (mapconcat 'decode-coding-string-to-current
                          (cdr translation) ", ")))))
   (t
    (let ((translation
           `(,(language-get-phonemic-script (thing-at-point 'word 'no-properties)) .
             ,(language-get-translation
               (thing-at-point 'word 'no-properties) "en" "es" items))))
      (language-goto-insertion-point)
      (insert
       (concat " /"
               (decode-coding-string-to-current (car translation))
               "/ "
               (mapconcat 'decode-coding-string-to-current
                          (cdr translation) ", ")))))))

(defun language-phonemic-script-at-point (&optional paren)
  "Get the phonemic script of the word at point.
By default insert it, with prefix display a message with it."
  (interactive "P")
  (cond
   ((or (equal paren '(4))
        buffer-read-only)
    (message
     (concat "/"
             (decode-coding-string-to-current
              (language-get-phonemic-script (thing-at-point 'word 'no-properties)))
             "/")))
   (t
    (let ((parenthesis (or paren "/")))
      (language-goto-insertion-point)
      (insert
       (concat " "
               parenthesis
               (decode-coding-string-to-current
                (language-get-phonemic-script (thing-at-point 'word 'no-properties)))
               parenthesis))))))

(defvar language-text-to-speak-process nil)

(defun vi-transfer-file (filepath &optional nokill)
  (interactive (list (buffer-file-name) current-prefix-arg))
  (if (and (stringp filepath)
           (file-exists-p filepath))
      (let ((terminal (or (executable-find "alacritty")
                          (executable-find "urxvt")
                          (executable-find "xterm"))))
        (if (null terminal)
            (message
             "Terminal not found, install `alacritty', `urxvt' or `xterm'")
          (start-process
           (concat "*vi " filepath "*") nil terminal "-e"
           "vi"
           (concat
            "+call cursor(" (number-to-string (line-number-at-pos))
            "," (number-to-string (1+ (current-column))) ")")
           filepath)
          (unless nokill
            (when-let ((buffer (find-buffer-visiting filepath)))
              (kill-buffer buffer)
              (when (< 1 (length (window-list)))
                (delete-window))))))
    (message "File not found: %s" filepath)))

(global-set-key (kbd "M-RET") 'vi-transfer-file)

(with-eval-after-load 'nxml-mode
  (defun xml-format (start end)
    "Format xml START END region or entire buffer."
    (interactive
     (if (use-region-p)
         (list (region-beginning) (region-end))
       (list (point-min) (point-max))))
    (if (executable-find "xmllint")
        (shell-command-on-region start end
                                 "xmllint --format -" t t)
      (error "Cannot find xmllint command")))

  (define-key nxml-mode-map (kbd "C-c x f") #'xml-format))

(with-eval-after-load 'ediff
  (require 'ediff)
  (add-hook 'ediff-after-quit-hook-internal 'winner-undo)

  (face-spec-set 'diff-refine-changed
                 '((((class color) (min-colors 88) (background light))
                    :background "#888833")
                   (((class color) (min-colors 88) (background dark))
                    :background "#555511")
                   (t :inverse-video t)))
  (face-spec-set 'ediff-odd-diff-A '((t (:background "dark slate gray"))))
  (face-spec-set 'ediff-odd-diff-B '((t (:background "dark slate gray"))))
  (face-spec-set 'ediff-odd-diff-C '((t (:background "dark slate gray"))))
  (face-spec-set 'ediff-even-diff-A '((t (:background "dim gray"))))
  (face-spec-set 'ediff-even-diff-B '((t (:background "dim gray"))))
  (face-spec-set 'ediff-even-diff-C '((t (:background "dim gray"))))
  (face-spec-set 'ediff-fine-diff-A '((t (:background "brown"))))
  (face-spec-set 'ediff-fine-diff-B '((t (:background "brown"))))
  (face-spec-set 'ediff-fine-diff-C '((t (:background "brown"))))
  (face-spec-set 'ediff-current-diff-A '((t (:foreground "White" :background "dark green"))))
  (face-spec-set 'ediff-current-diff-B '((t (:foreground "White" :background "dark green"))))
  (face-spec-set 'ediff-current-diff-C '((t (:foreground "White" :background "dark green"))))

  (setq-default ediff-forward-word-function 'forward-char)

  (setq ediff-window-setup-function 'ediff-setup-windows-plain
        ediff-split-window-function 'split-window-horizontally
        ediff-diff-ok-lines-regexp
        "^\\([0-9,]+[acd][0-9,]+
?$\\|[<>] \\|---\\|.*Warning *:\\|.*No +newline\\|.*missing +newline\\|.*No +hay +ningún +carácter +de +nueva +línea +al +final +del +fichero\\|^
?$\\)")

  (require 'vdiff)
  (defun diff-revert-buffer-with-file (&optional arg)
    "Compare the current modified buffer with the saved version.
ARG - `C-u' differ with prompted file.
    - `C-u' `C-u' force revert."
    (interactive "P")
    (cond
     ((equal arg '(16))
      (revert-buffer))
     ((equal arg '(4))
      (let ((diff-switches "-u")) ;; unified diff
        (diff-buffer-with-file (current-buffer))))
     (t
      (vdiff-current-file))))

  (defun vdiff-hydra-or-diff (&optional arg)
    (interactive "P")
    (condition-case-unless-debug nil
        (call-interactively 'vdiff-hydra/body)
      (error
       (cond
        ((equal arg '(64))
         (call-interactively 'vdiff-files3))
        ((equal arg '(16))
         (call-interactively 'vdiff-buffers3))
        ((equal arg '(4))
         (call-interactively 'vdiff-files))
        (t
         (call-interactively 'vdiff-buffers)))
       (call-interactively 'vdiff-hydra/body)))))

(global-set-key (kbd "C-c d R") 'diff-revert-buffer-with-file)
(global-set-key (kbd "C-c d 3 f") 'vdiff-files3)
(global-set-key (kbd "C-c d m") 'vdiff-hydra-or-diff)
(global-set-key (kbd "C-c d f") 'vdiff-files)
(global-set-key (kbd "C-c d 3 b") 'vdiff-buffers3)
(global-set-key (kbd "C-c d b") 'vdiff-buffers)

(with-eval-after-load 'shell
  (message "Importing shell config")
  (setq shell-file-name "bash")
;;;;;;;;;;;;
;; Colors ;;
;;;;;;;;;;;;
  (setq comint-output-filter-functions
        (remove 'ansi-color-process-output comint-output-filter-functions))

  (add-hook 'shell-mode-hook
            (lambda () (add-hook 'comint-preoutput-filter-functions 'xterm-color-filter nil t)))
  (setenv "TERM" "xterm-256color")
;;;;;;;;;;;;;
;; Filters ;;
;;;;;;;;;;;;;
  ;; Make URLs clickable
  (add-hook 'shell-mode-hook (lambda () (goto-address-mode 1)))
  ;; Make file paths clickable
  (add-hook 'shell-mode-hook 'compilation-shell-minor-mode)
  ;; Update 'default-directory' parsing prompt
  (add-hook 'shell-mode-hook #'dirtrack-mode)

;;;;;;;;;;;;;
;; Options ;;
;;;;;;;;;;;;;
  (setq-default dirtrack-list '("\033\\[00;34m\\([^\033]+\\)" 1 nil))
  (require 'comint)
  (setq comint-scroll-to-bottom-on-input t  ; always insert at the bottom
        comint-scroll-to-bottom-on-output t ; always add output at the bottom
        comint-scroll-show-maximum-output t ; scroll to show max possible output
        comint-completion-autolist t        ; show completion list when ambiguous
        comint-input-ignoredups t           ; no duplicates in command history
        comint-completion-addsuffix t       ; insert space/slash after file completion
        )
  (add-hook 'shell-mode-hook #'ansi-color-for-comint-mode-on)
  (add-to-list 'comint-output-filter-functions 'ansi-color-process-output)
  (set-face-attribute 'comint-highlight-prompt nil
                      :inherit nil)

;;;;;;;;;;;;;;;;;;;;;
;; Bash Completion ;;
;;;;;;;;;;;;;;;;;;;;;
  ;; Conflict with helm
  ;; (require 'bash-completion)
  ;; (bash-completion-setup)

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Variables de entorno ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Locales
  (setenv "LANG" "es_ES.UTF-8")
  (setenv "LC_ALL" "")
  (setenv "PROMPT_COMMAND" "")

;;;;;;;;;;;;;
;; execute ;;
;;;;;;;;;;;;;
  ;; (defun execute (dir)
  ;;   (interactive
  ;;    (list
  ;;     (let ((dir (and (bound-and-true-p execute-directory)
  ;;                     (eval execute-directory))))
  ;;      (if (or (not dir) current-prefix-arg)
  ;;          (read-string "Execute directory: " dir)
  ;;        dir))))
  ;;   (let ((default-directory dir))
  ;;     (compilation-start (read-string "Execute command: "
  ;;                                     (and (bound-and-true-p execute-command)
  ;;                                          (eval execute-command))))))
  (defvar execute-list '(compile execute test check config convert copy move next previous extern generate clean recompile build rebuild))

  (defun execute (&optional arg)
    (interactive "P")
    (let* ((pair-list (cl-remove-if-not
                       #'boundp
                       execute-list))
           (pair (eval (intern (completing-read "Execute: " pair-list nil t))))
           (default-directory (if current-prefix-arg
                                  (read-string "Execute directory: " (eval (cdr pair)))
                                (eval (cdr pair)))))
      (save-some-buffers arg)
      (compilation-start (read-string "Execute command: " (eval (car pair))))))

  (defvar insert-from-function-alist '(("git branches" . vc-git-branches)
                                       ("text to rotate" . rotate-text-symbols)))

  (defun insert-from-function (arg)
    (interactive "P")
    (let* ((choices (mapcar 'car insert-from-function-alist))
           (result (cdr (assoc (completing-read "Choose: "
                                                choices nil t)
                               insert-from-function-alist))))
      (while (not (stringp result))
        ;; (message "not string %s" result)
        (cond
         ((json-alist-p result)
          ;; (message "alist %s" result)
          (cond
           ((cl-every (lambda (x) (consp (cdr x))) result)
            ;; (message "list list %s" result)
            (setq choices (mapcar 'car result)
                  result (assoc (completing-read "Choose list: " choices nil t) result)))
           ((cl-every (lambda (x) (functionp (cdr x))) result)
            ;; (message "alist function %s" result)
            (setq choices (mapcar 'car result)
                  result (funcall (cdr (assoc (completing-read "Choose function: " choices nil t) result)))))
           (t
            ;; (message "alist ¿? %s" result)
            (setq choices (mapcar 'car result)
                  result (cdr (assoc (completing-read "Choose: " choices nil t) result))))))
         ((consp result)
          (cond
           ((cl-every #'stringp result)
            ;; (message "list strings %s" result)
            (setq result (completing-read "Text to insert: " result)))
           ((cl-every #'functionp result)
            ;; (message "list function %s" result)
            (setq result (completing-read "Choose function: " result nil t)))
           (t
            (error "Unknown type in list"))))
         ((functionp result)
          ;; (message "function %s" result)
          (setq result (funcall result)))
         ((symbolp result)
          ;; (message "symbol %s" result)
          (setq result (eval result)))
         (t
          (error "Unknown type"))))
      (if arg
          (kill-new result)
        (insert result))))

;;;;;;;;;;;;;;;
;; Funciones ;;
;;;;;;;;;;;;;;;
  ;; Sustituye:
  ;; '$p' por el nombre del buffer con su ruta.
  ;; '$n' por el nombre del buffer.
  ;; '$b' por el nombre del buffer sin extensión.
  (defun shell-execute (command &optional output-buffer error-buffer)
    (interactive
     (list
      (read-shell-command "Shell command: " nil nil
                          (let ((filename
                                 (cond
                                  (buffer-file-name)
                                  ((eq major-mode 'dired-mode)
                                   (dired-get-filename nil t)))))
                            (and filename (file-relative-name filename))))
      current-prefix-arg
      shell-command-default-error-buffer))
    (let ((command-replaced command)
          (replacements
           (append (list (cons "%n" (concat "\"" (buffer-name) "\"")))
                   (if buffer-file-name
                       (list (cons "%p" (concat "\"" buffer-file-name "\""))
                             (cons "%b" (concat "\"" (file-name-nondirectory buffer-file-name) "\""))))))
          (case-fold-search nil))
      (dolist (replacement replacements)
        (set 'command-replaced (replace-regexp-in-string
                                (regexp-quote (car replacement)) (cdr replacement)
                                command-replaced
                                t t)))
      (funcall 'shell-command command-replaced output-buffer error-buffer)))

  ;; fish-mode
  (add-hook 'fish-mode-hook (lambda ()
                              (add-hook 'before-save-hook 'fish_indent-before-save)))
  ;; fish-completion-mode
  (when (and (executable-find "fish")
             (require 'fish-completion nil t))
    (global-fish-completion-mode))

  (global-set-key (kbd "C-M-!") #'insert-from-function)
  (global-set-key (kbd "M-!") #'shell-execute)
  (global-set-key (kbd "M-s RET") #'shell-execute)
  (global-set-key (kbd "C-!") #'execute)

  (with-eval-after-load 'shell
    (require 'term)
    (define-key shell-mode-map (kbd "C-c C-k") #'term-char-mode)
    (define-key shell-mode-map (kbd "C-c C-j") #'term-line-mode))
  (define-key shell-mode-map (kbd "C-c C-l") 'helm-comint-input-ring)

  ;; (global-set-key (kbd "M-!") 'shell-execute)
  ;; (global-set-key (kbd "M-s RET") 'shell-execute)

  ;; ansi-term con utf-8
  ;; (defadvice ansi-term (after advise-ansi-term-coding-system)
  ;;     (set-buffer-process-coding-system 'utf-8-unix 'utf-8-unix))
  ;; (ad-activate 'ansi-term)
  ;; another option
  ;; (add-hook 'term-exec-hook
  ;;           (function
  ;;            (lambda ()
  ;;              (set-buffer-process-coding-system 'utf-8-unix 'utf-8-unix))))

  ;; Habilita colores en la terminal
  ;; (require 'ansi-color)
  ;; (defadvice display-message-or-buffer (before ansi-color activate)
  ;;   "Process ANSI color codes in shell output."
  ;;   (let ((buf (ad-get-arg 0)))
  ;;     (and (bufferp buf)
  ;;          (string= (buffer-name buf) "*Compilation Output*")
  ;;          (with-current-buffer buf
  ;;            (ansi-color-apply-on-region (point-min) (point-max))))))
  ;; (add-hook 'shell-mode-hook 'ansi-color-for-comint-mode-on)
  ;; (add-to-list 'comint-output-filter-functions 'ansi-color-process-output)
  )

(defun eshell-vi-transfer-file (filepath &optional nokill)
  (interactive (list (buffer-file-name) current-prefix-arg))
  (cond ((and (stringp filepath)
              (file-exists-p filepath))
         (require 'em-term)
         (eshell-exec-visual
          "vi" (concat
                "+call cursor(" (number-to-string (line-number-at-pos))
                "," (number-to-string (1+ (current-column))) ")")
          filepath)
         (unless nokill
           (when-let ((buffer (find-buffer-visiting filepath)))
             (kill-buffer buffer))))
        (t
         (message "File not found: %s" filepath))))

(with-eval-after-load 'esh-mode
  (message "Importing eshell config")

  (require 'pcomplete)
  (with-eval-after-load 'esh-module
    (add-to-list 'eshell-modules-list 'eshell-tramp))

;;;;;;;;;;;;
;; Colors ;;
;;;;;;;;;;;;
  (require 'em-prompt)
  (set-face-attribute 'eshell-prompt nil
                      :foreground "SeaGreen"
                      :background 'unspecified
                      :weight 'bold)

  (add-to-list 'eshell-preoutput-filter-functions 'xterm-color-filter)
  (setq eshell-output-filter-functions (remove 'eshell-handle-ansi-color eshell-output-filter-functions))
  (setenv "TERM" "xterm-256color")
;;;;;;;;;;;;;;;;;
;; Emacs Shell ;;
;;;;;;;;;;;;;;;;;
  (with-eval-after-load 'em-term
    (add-to-list 'eshell-visual-commands "apt")
    (add-to-list 'eshell-visual-commands "htop")
    (add-to-list 'eshell-visual-commands "atop")
    (add-to-list 'eshell-visual-commands "top")
    (add-to-list 'eshell-visual-commands "vim")
    (add-to-list 'eshell-visual-commands "nvim")
    (add-to-list 'eshell-visual-commands "nano")
    (add-to-list 'eshell-visual-commands "unison")
    (add-to-list 'eshell-visual-options '("git" "--help" "--paginate"))
    (add-to-list 'eshell-visual-subcommands '("git" "help" "log" "diff" "show" "reflog")))
  (setq eshell-prefer-lisp-functions nil
        eshell-prefer-lisp-variables nil
        eshell-destroy-buffer-when-process-dies nil
        eshell-cmpl-cycle-completions nil)

  (with-eval-after-load 'esh-var
    (setcdr (assoc "COLUMNS" eshell-variable-aliases-list)
            '((lambda (indices) (window-width-without-margin)) t)))

;;;;;;;;;;;;;;;;;;;;;;
;; Custom functions ;;
;;;;;;;;;;;;;;;;;;;;;;
  (defun eshell-send-chars-interactive-process ()
    (interactive)
    (let ((char (read-key "Char (C-c exits): ")))
      (while (not (char-equal ?\C-c char))
        (process-send-string (eshell-interactive-process) (char-to-string char))
        (setq char (read-key "Char (C-c exits): ")))))

  (defun start-process-stderr (name buffer program &rest program-args)
    "Start PROGRAM with PROGRAM-ARGS process NAME sending stdout to BUFFER.

This command send stderr to *stderr* buffer, not BUFFER."
    (unless (fboundp 'make-process)
      (error "Emacs was compiled without subprocess support"))
    (apply #'make-process
           (nconc (list :name name :buffer buffer :stderr (get-buffer-create "*stderr*"))
                  (if program
                      (list :command (cons program program-args))))))

  (defun start-file-process-stderr (name buffer program &rest program-args)
    "Start a program in a subprocess.  Return the process object for it.

NAME, BUFFER, PROGRAM, PROGRAM-ARGS same as `start-file-process'.

Only stdout sent to BUFFER, stderr sent to *stderr* buffer."
    (let ((fh (find-file-name-handler default-directory 'start-file-process-stderr)))
      (if fh (apply fh 'start-file-process-stderr name buffer program program-args)
        (apply 'start-process-stderr name buffer program program-args))))

  (defun eshell-gather-process-output-stderr (command args)
    "Gather the output from COMMAND + ARGS.

Only stdout sent to eshell buffer, stderr sent to *stderr* buffer."
    (require 'esh-var)
    (declare-function eshell-environment-variables "esh-var" ())
    (unless (and (file-executable-p command)
                 (file-regular-p (file-truename command)))
      (error "%s: not an executable file" command))
    (let* ((delete-exited-processes
            (if eshell-current-subjob-p
                eshell-delete-exited-processes
              delete-exited-processes))
           (process-environment (eshell-environment-variables))
           proc decoding encoding changed)
      (cond
       ((fboundp 'start-file-process-stderr)
        (setq proc
              (let ((process-connection-type
                     (unless (eshell-needs-pipe-p command)
                       process-connection-type))
                    (command (file-local-name (expand-file-name command))))
                (apply #'start-file-process-stderr
                       (file-name-nondirectory command) nil command args)))
        (eshell-record-process-object proc)
        (set-process-buffer proc (current-buffer))
        (set-process-filter proc (if (eshell-interactive-output-p)
                                     #'eshell-output-filter
                                   #'eshell-insertion-filter))
        (set-process-sentinel proc #'eshell-sentinel)
        (run-hook-with-args 'eshell-exec-hook proc)
        (when (fboundp 'process-coding-system)
          (let ((coding-systems (process-coding-system proc)))
            (setq decoding (car coding-systems)
                  encoding (cdr coding-systems)))
          ;; If start-process decided to use some coding system for
          ;; decoding data sent from the process and the coding system
          ;; doesn't specify EOL conversion, we had better convert CRLF
          ;; to LF.
          (if (vectorp (coding-system-eol-type decoding))
              (setq decoding (coding-system-change-eol-conversion decoding 'dos)
                    changed t))
          ;; Even if start-process left the coding system for encoding
          ;; data sent from the process undecided, we had better use the
          ;; same one as what we use for decoding.  But, we should
          ;; suppress EOL conversion.
          (if (and decoding (not encoding))
              (setq encoding (coding-system-change-eol-conversion decoding 'unix)
                    changed t))
          (if changed
              (set-process-coding-system proc decoding encoding))))
       (t
        ;; No async subprocesses...
        (let ((oldbuf (current-buffer))
              (interact-p (eshell-interactive-output-p))
              lbeg lend line proc-buf exit-status)
          (and (not (markerp eshell-last-sync-output-start))
               (setq eshell-last-sync-output-start (point-marker)))
          (setq proc-buf
                (set-buffer (get-buffer-create eshell-scratch-buffer)))
          (erase-buffer)
          (set-buffer oldbuf)
          (run-hook-with-args 'eshell-exec-hook command)
          (setq exit-status
                (apply #'call-process-region
                       (append (list eshell-last-sync-output-start (point)
                                     command t
                                     eshell-scratch-buffer nil)
                               args)))
          ;; When in a pipeline, record the place where the output of
          ;; this process will begin.
          (and (bound-and-true-p eshell-in-pipeline-p)
               (set-marker eshell-last-sync-output-start (point)))
          ;; Simulate the effect of the process filter.
          (when (numberp exit-status)
            (set-buffer proc-buf)
            (goto-char (point-min))
            (setq lbeg (point))
            (while (eq 0 (forward-line 1))
              (setq lend (point)
                    line (buffer-substring-no-properties lbeg lend))
              (set-buffer oldbuf)
              (if interact-p
                  (eshell-output-filter nil line)
                (eshell-output-object line))
              (setq lbeg lend)
              (set-buffer proc-buf))
            (set-buffer oldbuf))
          (require 'esh-mode)
          (declare-function eshell-update-markers "esh-mode" (pmark))
          (defvar eshell-last-output-end)         ;Defined in esh-mode.el.
          (eshell-update-markers eshell-last-output-end)
          ;; Simulate the effect of eshell-sentinel.
          (eshell-close-handles (if (numberp exit-status) exit-status -1))
          (eshell-kill-process-function command exit-status)
          (or (bound-and-true-p eshell-in-pipeline-p)
              (setq eshell-last-sync-output-start nil))
          (if (not (numberp exit-status))
              (error "%s: external command failed: %s" command exit-status))
          (setq proc t))))
      proc))

  (defun eshell-key-up (arg)
    (interactive "p")
    (if (eq (point)
            (point-max))
        (progn
          (if (not (memq last-command '(eshell-key-up
                                        eshell-key-down
                                        eshell-key-alt-previous
                                        eshell-key-alt-next)))
              ;; Starting a new search
              (setq eshell-matching-input-from-input-string
                    (buffer-substring (save-excursion (eshell-bol) (point))
                                      (point))
                    eshell-history-index nil))
          (eshell-previous-matching-input
           (concat "^" (regexp-quote eshell-matching-input-from-input-string))
           arg))
      (line-move-1 (- arg))))

  (defun eshell-key-down (arg)
    (interactive "p")
    (eshell-key-up (- arg)))

  (defun eshell-key-alt-previous (arg)
    (interactive "p")
    (if (eq (point)
            (point-max))
        (progn
          (if (not (memq last-command '(eshell-key-up
                                        eshell-key-down
                                        eshell-key-alt-previous
                                        eshell-key-alt-next)))
              ;; Starting a new search
              (setq eshell-matching-input-from-input-string
                    (buffer-substring (save-excursion (eshell-bol) (point))
                                      (point))
                    eshell-history-index nil))
          (eshell-previous-matching-input
           (concat "^" (regexp-quote eshell-matching-input-from-input-string))
           arg))
      (forward-paragraph (- arg))))

  (defun eshell-key-alt-next (arg)
    (interactive "p")
    (eshell-key-alt-previous (- arg)))

  (with-eval-after-load 'em-hist
    (when (bug-check-function-bytecode
           'eshell-put-history
           "AYQHAAiyAomDEADBAgQih8ICBCKH")
      (defun eshell-put-history (input &optional ring at-beginning)
        "Put a new input line into the history ring."
        (unless ring (setq ring eshell-history-ring))
        (if at-beginning
            (if (or (ring-empty-p ring)
                    (not (string-equal input (ring-ref eshell-history-ring -1))))
                (ring-insert-at-beginning ring input))
          (if (or (ring-empty-p ring)
                  (not (string-equal input (ring-ref eshell-history-ring 0))))
              (ring-insert ring input)))))

    ;; eshell-next-input call this
    (defun eshell-previous-input (arg)
      "Cycle backwards through input history."
      (interactive "*p")
      (if (eq (point)
              (point-max))
          (eshell-previous-matching-input "." arg)
        (line-move-1 (- arg)))))

;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;
  (defun eshell-send-input-rename ()
    (interactive)
    (call-interactively 'eshell-send-input)
    (let ((proc-running (eshell-interactive-process)))
      (when proc-running
        (rename-buffer (format "*esh:%s>%s*"
                               (file-name-nondirectory (eshell/pwd))
                               (process-name proc-running)) t))))

  (defun eshell-send-input-rename-stderr ()
    "`eshell-send-input' but sending stderr to *stderr* buffer."
    (interactive)
    (cl-letf (((symbol-function 'eshell-gather-process-output)
               'eshell-gather-process-output-stderr))
      (call-interactively 'eshell-send-input))
    (let ((proc-running (eshell-interactive-process)))
      (when proc-running
        (rename-buffer (format "*esh:%s>%s*"
                               (file-name-nondirectory (eshell/pwd))
                               (process-name proc-running)) t))))
;;;;;;;;
;; ag ;;
;;;;;;;;
  (when (require 'ag nil 'noerror)
    (defun eshell/ag (&rest args)
      "Use Emacs grep facility instead of calling external grep."
      (ag/search (mapconcat #'shell-quote-argument args " ") default-directory)))
;;;;;;;;;;;;;
;; Filters ;;
;;;;;;;;;;;;;
  ;; Make URLs clickable & ag

  ;; Colorize advices
  ;; brute force...
  ;; (add-hook 'eshell-post-command-hook (lambda () (unhl-advices) (hl-advices)))

;;;;;;;;;;;;
;; Prompt ;;
;;;;;;;;;;;;
  (require 'dash)
  (require 's)
  (require 'vc-git)


  ;; pyvenv package
  (defvar pyvenv-virtual-env-name nil)
  ;; virtualenvwrapper package
  (defvar venv-current-name nil)

  (defvar eshell-current-command-start-time nil)
  ;; Below I implement a "prompt number" section
  (defvar esh-prompt-num 0)
  (add-hook 'eshell-mode-hook (lambda ()
                                (set-default (make-local-variable 'esh-prompt-num) 0)
                                (make-local-variable 'eshell-current-command-start-time)))

  (defun esh-prompt-func ()
    "Build `eshell-prompt-function'."
    (setq esh-prompt-num (cl-incf esh-prompt-num))
    (let ((prev-string? t))
      (-reduce-from (lambda (acc x)
                      (if (functionp x)
                          (--if-let (funcall x)
                              (if (null prev-string?)
                                  (concat acc esh-sep it)
                                (setq prev-string? nil)
                                (concat acc it))
                            acc)
                        (if (null prev-string?)
                            (setq prev-string? t))
                        (concat acc x)))
                    esh-header eshell-funcs)))

  (eval-when-compile
    (defmacro esh-section (NAME ICON FORM FACE)
      "Build eshell section NAME with ICON prepended to evaled FORM with PROPS."
      `(setq ,NAME
             (lambda ()
               (when ,FORM
                 (let ((text (concat ,ICON esh-section-delim ,FORM)))
                   (add-text-properties
                    0 (length text)
                    '(read-only t
                                font-lock-face ,FACE
                                front-sticky (font-lock-face read-only)
                                rear-nonsticky (font-lock-face read-only))
                    text)
                   text))))))

  (defface esh-dir
    '((t (:foreground "gold" :weight ultra-bold :underline t)))
    "EShell directory prompt face")
  (esh-section esh-dir
               (if (display-graphic-p) "📂" "δ")  ;  (faicon folder)
               (let ((name (eshell/pwd)))
                 (rename-buffer (format "*esh:%s*" (file-name-nondirectory name)) t)
                 (abbreviate-file-name name))
               esh-dir)

  (defface esh-git
    '((t (:foreground "pink")))
    "EShell git prompt face")
  (esh-section esh-git
               (if (display-graphic-p) "⎇" "β")  ;  (git icon)
               ;; (magit-get-current-branch)
               (car (vc-git-branches))
               esh-git)

  (defface esh-python
    '((t (:foreground "white")))
    "EShell python prompt face")
  (esh-section esh-python
               (if (display-graphic-p) "⛶" "π")  ;  (python icon)
               (or pyvenv-virtual-env-name venv-current-name)
               esh-python)

  (defface esh-clock
    '((t (:foreground "forest green")))
    "EShell clock prompt face")
  (esh-section esh-clock
               (if (display-graphic-p) "⏳" "τ")  ;  (clock icon)
               (format-time-string "%H:%M" (current-time))
               esh-clock)

  (defface esh-user
    '((t (:foreground "deep sky blue")))
    "EShell user prompt face")
  (esh-section esh-user
               (if (display-graphic-p) "👤" "υ")
               (eshell-user-name)
               esh-user)

  (defface esh-sysname
    '((t (:foreground "firebrick")))
    "EShell sysname prompt face")
  (esh-section esh-sysname
               (if (display-graphic-p) "💻" "σ")
               (system-name)
               esh-sysname)

  (defface esh-num
    '((t (:foreground "brown")))
    "EShell number prompt face")
  (esh-section esh-num
               (if (display-graphic-p) "☰" "n")  ;  (list icon)
               (number-to-string esh-prompt-num)
               esh-num)


  (setq
   eshell-highlight-prompt nil
   ;; Separator between esh-sections
   esh-sep "  "  ; or " | "

   ;; Separator between an esh-section icon and form
   esh-section-delim " "

   ;; Eshell prompt header
   esh-header "\n"  ; or "\n┌─"

   ;; Eshell prompt regexp and string. Unless you are varying the prompt by eg.
   ;; your login, these can be the same.
   eshell-prompt-string (let ((last-prompt "⊳ "))
                          (add-text-properties
                           0 (length last-prompt)
                           '(read-only t
                                       font-lock-face eshell-prompt
                                       front-sticky (font-lock-face read-only)
                                       rear-nonsticky (font-lock-face read-only))
                           last-prompt)
                          last-prompt)  ; or "└─> " or "└─» "
   eshell-prompt-regexp
   (concat "^" eshell-prompt-string "\\|^[a-z]*>\\{1,4\\} \\|^[^#$
]* [#$] ")  ; or "└─> "
   ;; Choose which eshell-funcs to enable
   eshell-funcs (list esh-python esh-git esh-user esh-sysname esh-clock esh-num
                      "\n" esh-dir
                      "\n" eshell-prompt-string)
   ;; Enable the new eshell prompt
   eshell-prompt-function 'esh-prompt-func
   eshell-banner-message (format
                          "%s\nEmacs version %s on %s. Compilation %s  %s\n"
                          system-configuration-features
                          emacs-version system-type system-configuration
                          system-configuration-options))

;;;;;;;;;;;;;;;;;
;; Post prompt ;;
;;;;;;;;;;;;;;;;;
  (defun eshell-current-command-start ()
    (setq eshell-current-command-start-time (current-time)))

  (defun eshell-current-command-stop ()
    (when eshell-current-command-start-time
      (eshell-interactive-print
       (propertize
        (format "\n>  Exit code: %i   Elapsed time: %.3fs  <"
                eshell-last-command-status
                (float-time
                 (time-subtract (current-time)
                                eshell-current-command-start-time)))
        'font-lock-face '(:foreground "goldenrod1")))
      (setq eshell-current-command-start-time nil)))

  (defun eshell-current-command-time-track ()
    (add-hook 'eshell-pre-command-hook #'eshell-current-command-start nil t)
    (add-hook 'eshell-post-command-hook #'eshell-current-command-stop nil t))
  (add-hook 'eshell-mode-hook #'eshell-current-command-time-track)

  ;; To uninstall
  ;; (remove-hook 'eshell-mode-hook #'eshell-current-command-time-track)

;;;;;;;;;;;;;;;;
;; Completion ;;
;;;;;;;;;;;;;;;;
  ;; [ <python completion>
  (when (executable-find "python")

    (defun pcmpl-python-commands ()
      (with-temp-buffer
        (call-process-shell-command "LC_ALL=C python --help" nil (current-buffer))
        (goto-char 0)
        (let (commands)
          (while (re-search-forward "^-\\([[:word:]-.]+\\)" nil t)
            (push (match-string 1) commands))
          (mapconcat 'identity commands ""))))

    (defconst pcmpl-python-commands (pcmpl-python-commands)
      "List of `python' commands.")

    (defun pcmpl-python-packages ()
      (with-temp-buffer
        (call-process-shell-command "python -m pip freeze" nil (current-buffer))
        (goto-char 0)
        (let (packages)
          (while (re-search-forward "^\\([[:word:]-.]+\\)=" nil t)
            (push (match-string 1) packages))
          (sort packages 'string<))))

    (defun pcomplete/python ()
      "Completion for `python'."
      ;; Completion for the command argument.
      (pcomplete-opt pcmpl-python-commands)
      (cond
       ((pcomplete-match "-m" 1)
        (pcomplete-here (pcmpl-python-packages)))
       (t
        (while (pcomplete-here (pcomplete-entries)))))))
  ;; ] <python completion>
  ;; [ <python3 completion>
  (when (executable-find "python3")

    (defun pcmpl-python3-commands ()
      (with-temp-buffer
        (call-process-shell-command "LC_ALL=C python3 --help" nil (current-buffer))
        (goto-char 0)
        (let (commands)
          (while (re-search-forward "^-\\([[:word:]-.]+\\)" nil t)
            (push (match-string 1) commands))
          (mapconcat 'identity commands ""))))

    (defconst pcmpl-python3-commands (pcmpl-python3-commands)
      "List of `python3' commands.")

    (defun pcmpl-python3-packages ()
      (with-temp-buffer
        (call-process-shell-command "python3 -m pip freeze" nil (current-buffer))
        (goto-char 0)
        (let (packages)
          (while (re-search-forward "^\\([[:word:]-.]+\\)=" nil t)
            (push (match-string 1) packages))
          (sort packages 'string<))))

    (defun pcomplete/python3 ()
      "Completion for `python3'."
      ;; Completion for the command argument.
      (pcomplete-opt pcmpl-python3-commands)
      (cond
       ((pcomplete-match "-m" 1)
        (pcomplete-here (pcmpl-python3-packages)))
       (t
        (while (pcomplete-here (pcomplete-entries)))))))
  ;; ] <python3 completion>
  ;; [ <Git Completion>
  (when (executable-find "git")

    (defun pcmpl-git-commands ()
      "Return the most common git commands by parsing the git output."
      (with-temp-buffer
        (call-process-shell-command "LC_ALL=C git --no-pager help --all" nil (current-buffer))
        (goto-char 0)
        (cond
         ((search-forward "available git commands in " nil t)
          (let (commands)
            (while (and (re-search-forward
                         "[[:blank:]]+\\([[:word:]-]+\\)"
                         nil t)
                        (not (string-equal (match-string 1) "commands")))
              (push (match-string 1) commands))
            (sort commands #'string<)))
         ((search-forward "Main Porcelain Commands" nil t)
          (let (commands)
            (while (re-search-forward
                    "^[[:blank:]]+\\([[:word:]-]+\\)"
                    nil t)
              (push (match-string 1) commands))
            (sort commands #'string<)))
         (t
          (message "Git command's help changed.")))))

    (defconst pcmpl-git-commands (pcmpl-git-commands)
      "List of `git' commands.")

    (defvar pcmpl-git-ref-list-cmd "git for-each-ref refs/ --format='%(refname)'"
      "The `git' command to run to get a list of refs.")

    (defun pcmpl-git-get-refs (type)
      "Return a list of `git' refs filtered by TYPE."
      (with-temp-buffer
        (insert (shell-command-to-string pcmpl-git-ref-list-cmd))
        (goto-char (point-min))
        (let (refs)
          (while (re-search-forward (concat "^refs/" type "/\\(.+\\)$") nil t)
            (push (match-string 1) refs))
          (nreverse refs))))

    (defun pcmpl-git-remotes ()
      "Return a list of remote repositories."
      (split-string (shell-command-to-string "git remote")))

    (defun pcomplete/git ()
      "Completion for `git'."
      ;; Completion for the command argument.
      (pcomplete-here* pcmpl-git-commands)
      (cond
       ((pcomplete-match "help" 1)
        (pcomplete-here* pcmpl-git-commands))
       ((pcomplete-match (regexp-opt '("pull" "push")) 1)
        (pcomplete-here (pcmpl-git-remotes)))
       ;; provide branch completion for the command `checkout'.
       ((pcomplete-match "checkout" 1)
        (pcomplete-here* (append (pcmpl-git-get-refs "heads")
                                 (pcmpl-git-get-refs "tags"))))
       (t
        (while (pcomplete-here (pcomplete-entries))))))

    (when (executable-find "ggit")

      (defun pcmpl-ggit-commands ()
        "Return the most common git commands by parsing the git output."
        (with-temp-buffer
          (call-process-shell-command "LC_ALL=C ggit --help" nil (current-buffer))
          (goto-char 0)
          (let (commands)
            (while (re-search-forward
                    "^[[:blank:]]+\\(--[[:word:]-]+\\)"
                    nil t)
              (push (match-string 1) commands))
            (sort commands #'string<))))

      (defconst pcmpl-ggit-commands (append (pcmpl-ggit-commands)
                                            pcmpl-git-commands)
        "List of `ggit' commands.")

      (defun pcomplete/ggit ()
        "Completion for `git'."
        ;; Completion for the command argument.
        (pcomplete-here* pcmpl-ggit-commands)
        (cond
         ((pcomplete-match "help" -1)
          (pcomplete-here* pcmpl-git-commands))
         ((pcomplete-match (regexp-opt '("pull" "push")) -1)
          (pcomplete-here (pcmpl-git-remotes)))
         ;; provide branch completion for the command `checkout'.
         ((pcomplete-match "checkout" -1)
          (pcomplete-here* (append (pcmpl-git-get-refs "heads")
                                   (pcmpl-git-get-refs "tags"))))
         (t
          (while (pcomplete-here (pcomplete-entries))))))))
  ;; ] <Git Completion>
  ;; [ <Bzr Completion>
  (when (executable-find "bzr")

    (defun pcmpl-bzr-commands ()
      "Return the most common bzr commands by parsing the bzr output."
      (with-temp-buffer
        (call-process-shell-command "LC_ALL=C bzr help commands" nil (current-buffer))
        (goto-char 0)
        (let (commands)
          (while (re-search-forward "^\\([[:word:]-]+\\)[[:blank:]]+" nil t)
            (push (match-string 1) commands))
          (sort commands #'string<))))

    (defconst pcmpl-bzr-commands (pcmpl-bzr-commands)
      "List of `bzr' commands.")

    (defun pcomplete/bzr ()
      "Completion for `bzr'."
      ;; Completion for the command argument.
      (pcomplete-here* pcmpl-bzr-commands)
      (cond
       ((pcomplete-match "help" 1)
        (pcomplete-here* pcmpl-bzr-commands))
       (t
        (while (pcomplete-here (pcomplete-entries)))))))
  ;; ] <Bzr Completion>
  ;; [ <Mercurial (hg) Completion>
  (when (executable-find "hg")

    (defun pcmpl-hg-commands ()
      "Return the most common hg commands by parsing the hg output."
      (with-temp-buffer
        (call-process-shell-command "LC_ALL=C hg -v help" nil (current-buffer))
        (goto-char 0)
        (search-forward "list of commands:")
        (let (commands
              (bound (save-excursion
                       (re-search-forward "^[[:alpha:]]")
                       (forward-line 0)
                       (point))))
          (while (re-search-forward
                  "^[[:blank:]]\\([[:word:]]+\\(?:, [[:word:]]+\\)*\\)" bound t)
            (let ((match (match-string 1)))
              (if (not (string-match "," match))
                  (push (match-string 1) commands)
                (dolist (c (split-string match ", ?"))
                  (push c commands)))))
          (sort commands #'string<))))

    (defconst pcmpl-hg-commands (pcmpl-hg-commands)
      "List of `hg' commands.")

    (defun pcomplete/hg ()
      "Completion for `hg'."
      ;; Completion for the command argument.
      (pcomplete-here* pcmpl-hg-commands)
      (cond
       ((pcomplete-match "help" 1)
        (pcomplete-here* pcmpl-hg-commands))
       (t
        (while (pcomplete-here (pcomplete-entries)))))))
  ;; ] <Mercurial (hg) Completion>
  ;; [ <sudo completion>
  (defun pcomplete/sudo ()
    "Completion rules for the `sudo' command."
    (let ((pcomplete-ignore-case t))
      (pcomplete-here (funcall pcomplete-command-completion-function))
      (while (pcomplete-here (pcomplete-entries)))))
  ;; ] <sudo completion>
  ;; [ <systemctl completion>
  (defcustom pcomplete-systemctl-commands
    '("disable" "enable" "status" "start" "restart" "stop" "reenable"
      "list-units" "list-unit-files")
    "p-completion candidates for `systemctl' main commands"
    :type '(repeat (string :tag "systemctl command"))
    :group 'pcomplete)

  (defvar pcomplete-systemd-units
    (split-string
     (shell-command-to-string
      "(systemctl list-units --all --full --no-legend;systemctl list-unit-files --full --no-legend)|while read -r a b; do echo \" $a\";done;"))
    "p-completion candidates for all `systemd' units")

  (defvar pcomplete-systemd-user-units
    (split-string
     (shell-command-to-string
      "(systemctl list-units --user --all --full --no-legend;systemctl list-unit-files --user --full --no-legend)|while read -r a b;do echo \" $a\";done;"))
    "p-completion candidates for all `systemd' user units")

  (defun pcomplete/systemctl ()
    "Completion rules for the `systemctl' command."
    (pcomplete-here (append pcomplete-systemctl-commands '("--user")))
    (cond ((pcomplete-test "--user")
           (pcomplete-here pcomplete-systemctl-commands)
           (pcomplete-here pcomplete-systemd-user-units))
          (t (pcomplete-here pcomplete-systemd-units))))
  ;; ] <systemctl completion>
  ;; [ <man completion>
  (defvar pcomplete-man-user-commands
    (split-string
     (shell-command-to-string
      "apropos -s 1 .|while read -r a b; do echo \" $a\";done;"))
    "p-completion candidates for `man' command")

  (defun pcomplete/man ()
    "Completion rules for the `man' command."
    (pcomplete-here pcomplete-man-user-commands))
  ;; ] <man completion>

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;

  (defun eshell-cmpl-initialize-advice ()
    (define-key eshell-mode-map (kbd "<return>") 'eshell-send-input-rename)
    (when (featurep 'helm)
      (define-key eshell-mode-map [tab] #'helm-esh-pcomplete))
    (define-key eshell-mode-map (kbd "<S-return>") 'eshell-send-input-rename-stderr))
  (advice-add 'eshell-cmpl-initialize :after 'eshell-cmpl-initialize-advice)

  (defun eshell-hist-initialize-advice ()
    (when (featurep 'helm)
      (define-key eshell-command-map [(control ?l)] #'helm-eshell-history)))
  (advice-add 'eshell-hist-initialize :after 'eshell-hist-initialize-advice)

  (add-hook 'eshell-mode-hook (lambda ()
                                (goto-address-mode 1)
                                (define-key eshell-mode-map (kbd "<up>") 'eshell-key-up)
                                (define-key eshell-mode-map (kbd "<down>") 'eshell-key-down)
                                (define-key eshell-mode-map (kbd "M-p") 'eshell-key-alt-previous)
                                (define-key eshell-mode-map (kbd "M-n") 'eshell-key-alt-next)
                                (define-key eshell-mode-map (kbd "C-c C-k") 'eshell-send-chars-interactive-process)
                                ;; Make file paths clickable
                                (define-key eshell-mode-map (kbd "C-c c")
                                  (lambda (arg)
                                    (interactive "P")
                                    (if arg
                                        (compilation-shell-minor-mode -1)
                                      (if (null compilation-shell-minor-mode)
                                          (compilation-shell-minor-mode 1)
                                        (compilation-shell-minor-mode -1)
                                        (compilation-shell-minor-mode 1)))))
                                (add-to-list 'eshell-complex-commands "ag"))))

(with-eval-after-load 'ispell
  (message "Importing ispell-config")

  (let ((executable (file-name-nondirectory ispell-program-name)))
    (cond
     ((string-equal executable "aspell")
      (setq ispell-personal-dictionary
            (file-truename "~/.emacs.d/cache/aspell.spanish.pws"))
      (add-to-list 'ispell-extra-args "--sug-mode=ultra"))
     ((string-equal executable "hunspell")
      (setenv "DICPATH" (file-truename "~/.emacs.d/cache/hunspell/"))
      (add-to-list 'ispell-local-dictionary-alist `("es_ES"
                                                    "[a-zA-ZáéíóúÁÉÍÓÚÑüÜ]"
                                                    "[^a-zA-ZáéíóúÁÉÍÓÚÑüÜ]"
                                                    "[']"
                                                    t
                                                    ("-d" "es_ES")
                                                    nil
                                                    utf-8))
      (setq ispell-really-hunspell t
            ispell-personal-dictionary
            (file-truename "~/.emacs.d/cache/hunspell.spanish.pws")
            ispell-current-dictionary "es_ES"
            ispell-local-dictionary "es_ES"
            ispell-dictionary "es_ES")
      ;; Internal use
      ;; (add-to-list 'ispell-hunspell-dict-paths-alist `("spanish" ,(file-truename "~/.emacs.d/cache/hunspell/es_ES.aff")))
      )))
  ;; [ Cycle languages
  (require 'ring)
  (defvar spell-lang-ring nil)
  (let ((langs '("english" "spanish")))
    (setq spell-lang-ring (make-ring (length langs)))
    (dolist (elem langs) (ring-insert spell-lang-ring elem)))

  (defun spell-change-dictionary (dictionary)
    "Change dictionary file inserting DICTIONARY."
    (setq ispell-personal-dictionary
          (cond
           ((string-equal ispell-program-name "aspell")
            (concat "~/.emacs.d/cache/aspell." dictionary ".pws"))
           ((string-equal ispell-program-name "hunspell")
            (concat "~/.emacs.d/cache/hunspell." dictionary ".pws"))))
    (ispell-change-dictionary dictionary))

                                        ;(ispell-change-dictionary)
  (defun cycle-ispell-languages ()
    "Cycle languages in ring."
    (interactive)
    (let ((lang (ring-ref spell-lang-ring -1))
          (dict ispell-current-dictionary))
      (ring-insert spell-lang-ring lang)
      (if (equal dict lang)
          (let ((next-lang (ring-ref spell-lang-ring -1)))
            (ring-insert spell-lang-ring next-lang)
            (spell-change-dictionary next-lang))
        (spell-change-dictionary lang))))
  ;; ]

  ;; Selecciona una opción incluso cuando picas fuera del popup
  ;; (defun spell-emacs-popup-textual (event poss word)
  ;;       "A textual spell popup menu."
  ;;       (require 'popup)
  ;;       (let* ((corrects (if spell-sort-corrections
  ;;                            (sort (car (cdr (cdr poss))) 'string<)
  ;;                          (car (cdr (cdr poss)))))
  ;;              (cor-menu (if (consp corrects)
  ;;                            (mapcar (lambda (correct)
  ;;                                      (list correct correct))
  ;;                                    corrects)
  ;;                          '()))
  ;;              (affix (car (cdr (cdr (cdr poss)))))
  ;;              show-affix-info
  ;;              (base-menu  (let ((save (if (and (consp affix) show-affix-info)
  ;;                                          (list
  ;;                                           (list (concat "Save affix: " (car affix))
  ;;                                                 'save)
  ;;                                           '("Accept (session)" session)
  ;;                                           '("Accept (buffer)" buffer))
  ;;                                        '(("Save word" save)
  ;;                                          ("Accept (session)" session)
  ;;                                          ("Accept (buffer)" buffer)))))
  ;;                            (if (consp cor-menu)
  ;;                                (append cor-menu (cons "" save))
  ;;                              save)))
  ;;              (menu (mapcar
  ;;                     (lambda (arg) (if (consp arg) (car arg) arg))
  ;;                     base-menu)))
  ;;         (cadr (assoc (popup-menu* menu :scroll-bar t) base-menu))))
  (defun spanish-dictionary ()
    "Stablish spanish dictionary."
    (interactive)
    (spell-change-dictionary "spanish"))
  (defun english-dictionary ()
    "Stablish english dictionary."
    (interactive)
    (spell-change-dictionary "english")))

(add-hook 'prog-mode-hook #'hs-minor-mode)
(with-eval-after-load 'hideshow
  (message "Importing hideshow-config")

  (defface hideshow-overlay-face
    '((t (:foreground "purple" :box t)))
    "HideShow overlay face"
    :group 'hideshow)

  (setq minor-mode-alist (assq-delete-all 'hs-minor-mode minor-mode-alist)
        hs-set-up-overlay
        (lambda (ov)
          (when (eq 'code (overlay-get ov 'hs))
            (overlay-put ov 'display
                         (propertize
                          (format "… %d lines"
                                  (count-lines (overlay-start ov)
                                               (overlay-end ov)))
                          'face 'hideshow-overlay-face)))))

  (with-eval-after-load 'tex-mode
    (add-hook 'latex-mode-hook #'hs-minor-mode)
    (add-hook 'tex-mode-hook #'hs-minor-mode))
  (with-eval-after-load 'latex
    (add-hook 'LaTeX-mode-hook #'hs-minor-mode))
  (with-eval-after-load 'tex
    (add-hook 'TeX-mode-hook #'hs-minor-mode))

  ;; (define-key hs-minor-mode-map (kbd "<C-tab>") #'hs-toggle-hiding)
  )

(with-eval-after-load 'compile
  ;; process's default filter `comint-output-filter'
  (setq comint-scroll-to-bottom-on-output nil
        ;; compile-command "cbuild -g "
        compilation-scroll-output 'first-error)

  ;; (defun compilation-conditional-scroll-output ()
  ;;   (let ((name (buffer-name)))
  ;;     (if (and name
  ;;              (string-match-p "log" name))
  ;;         (set (make-local-variable 'compilation-scroll-output) nil))))
  ;; (add-hook 'compilation-mode-hook 'compilation-conditional-scroll-output)
  )

(with-eval-after-load 'prog-mode
  ;; Generate tags file:
  ;; # cd <project root path>
  ;; # rm ETAGS
  ;; # find <root code path> -type f -name "<source files pattern>" -print 2>/dev/null | xargs etags -o ETAGS --append
  (require 'etags)

  (defvar tags-default-file-name "ETAGS")

  (defun visit-tags-table-advice (orig-fun &optional file &rest args)
    (if file
        (apply orig-fun file args)
      (let ((tags-directory (locate-dominating-file default-directory tags-default-file-name)))
        (if tags-directory
            (let ((tags-path (expand-file-name tags-default-file-name tags-directory)))
              (message "%s file path: %s" tags-default-file-name tags-path)
              ;; (advice-remove 'visit-tags-table 'visit-tags-table-advice)
              (apply orig-fun tags-path args))
          (message "%s file not found." tags-default-file-name)))))
  (advice-add 'visit-tags-table :around 'visit-tags-table-advice)

  (defun visit-tags-table-buffer-advice (orig-fun &rest args)
    (advice-remove 'visit-tags-table-buffer 'visit-tags-table-buffer-advice)
    (visit-tags-table)
    (apply orig-fun args))
  (advice-add 'visit-tags-table-buffer :around 'visit-tags-table-buffer-advice)

  (defun tags-update-etags-file (extension)
    (interactive (list (read-string "File extension ."
                                    nil nil
                                    (file-name-extension (buffer-file-name)))))
    (if (stringp extension)
        (let ((tags-directory (locate-dominating-file default-directory
                                                      tags-default-file-name)))
          (if tags-directory
              (let ((default-directory tags-directory))
                (if (= 0
                       (shell-command
                        (concat
                         "rm " tags-default-file-name
                         " && find . ! -readable -prune -o -type f -name \"*."
                         extension
                         "\" -print -exec etags -o "
                         tags-default-file-name
                         " --append {} \\;")))
                    (message "%s file created with .%s files."
                             (expand-file-name tags-default-file-name tags-directory)
                             extension)
                  (message "%s file creation failed."
                           (expand-file-name tags-default-file-name tags-directory))))
            (message "%s file not found." tags-default-file-name)))
      (message "%s is not a valid extension." extension)))

  (defun tags-create-etags-file (directory)
    (interactive "DCreate etags file in path: ")
    (let ((tags-path (expand-file-name tags-default-file-name directory)))
      (if (file-exists-p tags-path)
          (message "%s file already exists in %s." tags-default-file-name directory)
        (let ((default-directory directory)
              (extension (file-name-extension (buffer-file-name))))
          (if (= 0
                 (shell-command (concat "find . ! -readable -prune -o -type f -name \"*."
                                        extension
                                        "\" -print -exec etags --append {} \\;")))
              (message "%s file created with .%s files." tags-path extension)
            (message "%s file creation failed." tags-path))))))

  (defun etags-xref-find-advice (orig-fun &rest args)
    (condition-case nil
        (apply orig-fun args)
      (error
       (let ((xref-backend-functions '(etags--xref-backend)))
         (call-interactively orig-fun)))))

  (advice-add 'xref-find-apropos :around 'etags-xref-find-advice)
  (advice-add 'xref-find-references :around 'etags-xref-find-advice)

  (advice-add 'xref-find-definitions :around 'etags-xref-find-advice)
  (advice-add 'xref-find-definitions-other-frame :around 'etags-xref-find-advice)
  (advice-add 'xref-find-definitions-other-window :around 'etags-xref-find-advice)



;;;;;;;;;;
  ;; Keys ;;
;;;;;;;;;;
  (with-eval-after-load 'hydra
    (defhydra hydra-xref (:foreign-keys run :hint nil)
      ("M-," #'xref-pop-marker-stack "pop")
      ("M-'" #'xref-find-references "ref")
      ("M-a" #'xref-find-apropos "apropos")
      ("M-." #'xref-find-definitions "def")
      ("M-W" #'xref-find-definitions-other-window "def win")
      ("M-F" #'xref-find-definitions-other-frame "def frame")
      ("M-s" #'tags-search "search")
      ("M-t" #'xref-query-replace-in-results "repl results")
      ("M-r" #'tags-query-replace "repl")
      ("M-c" #'fileloop-continue "cont")
      ("M-p" #'pop-tag-mark "pop tag")
      ("M-l" #'list-tags "list")
      ("M-q" nil "quit"))

    (global-set-key (kbd "M-Ç") 'hydra-xref/body)))

(with-eval-after-load 'ede
  (message "Importing ede-config")
  ;; ede is difficult for management
  ;; (require 'cedet)
  ;; (require 'ede/source)
  ;; (require 'ede/base)
  ;; (require 'ede/auto)
  ;; (require 'ede/proj)
  ;; (require 'ede/proj-archive)
  ;; (require 'ede/proj-aux)
  ;; (require 'ede/proj-comp)
  ;; (require 'ede/proj-elisp)
  ;; (require 'ede/proj-info)
  ;; (require 'ede/proj-misc)
  ;; (require 'ede/proj-obj)
  ;; (require 'ede/proj-prog)
  ;; (require 'ede/proj-scheme)
  ;; (require 'ede/proj-shared)

  ;; [ unstable
  ;; ;; advice 'projectile' functions to work with 'ede'
  ;; (defun ede-add-to-projectile-project-root (orig-fun &rest args)
  ;;   (condition-case nil
  ;;       (file-name-directory (oref (ede-current-project) file))
  ;;     (error (apply orig-fun args))))
  ;; (advice-add 'projectile-project-root :around
  ;;             #'ede-add-to-projectile-project-root)

  ;; (defun ede-add-to-projectile-project-name (orig-fun &rest args)
  ;;   (condition-case nil
  ;;       (oref (ede-current-project) name)
  ;;     (error (apply orig-fun args))))
  ;; (advice-add 'projectile-project-name :around
  ;;             #'ede-add-to-projectile-project-name)
  ;; ]

  ;;(global-ede-mode 1)
  ;; Unknown error
  ;; (ede-enable-generic-projects)
  )

(with-eval-after-load 'eldoc
  (setq eldoc-minor-mode-string "")
  ;; (global-eldoc-mode -1)
  (global-set-key (kbd "C-h .") 'global-eldoc-mode))

;; first loaded
(add-hook 'emacs-lisp-mode-hook #'semantic-mode -91)
(add-hook 'lisp-mode-hook #'semantic-mode -91)
(with-eval-after-load 'semantic
  (message "Importing semantic-config")
  ;; [ Included by default
  ;; (add-to-list 'semantic-default-submodes 'global-semantic-idle-scheduler-mode)
  ;; (add-to-list 'semantic-default-submodes 'global-semanticdb-minor-mode)
  ;; ]
  (require 'semantic)
  ;;(setq-default semantic-symref-tool "grep")
  (setq semantic-default-submodes '(semantic-tag-folding-mode
                                    semantic-mru-bookmark-mode
                                    semantic-stickyfunc-mode
                                    semantic-idle-scheduler-mode
                                    semanticdb-minor-mode)
        semantic-stickyfunc-sticky-classes '(function type)
        ;; semantic-symref-tool "grep"
        ;; semantic-decoration-styles
        ;; '(("semantic-decoration-on-includes" . t)
        ;;   ("semantic-decoration-on-protected-members" . t)
        ;;   ("semantic-decoration-on-private-members" . t)
        ;;   ("semantic-tag-boundary" . t))
        semantic-idle-scheduler-idle-time 3)

  ;; Disabled, completions by company
  ;; (add-to-list 'semantic-default-submodes 'global-semantic-idle-completions-mode)
  ;; First line show current function
  ;;(add-to-list 'semantic-default-submodes 'global-semantic-stickyfunc-mode)
  ;; Most Recently Used tags
  ;;(add-to-list 'semantic-default-submodes 'global-semantic-mru-bookmark-mode)
  ;; Highlight symbol under cursor in page
  ;; (add-to-list 'semantic-default-submodes 'global-semantic-idle-local-symbol-highlight-mode)
  ;;(add-to-list 'semantic-default-submodes 'global-semantic-tag-folding-mode)
  ;; (add-to-list 'semantic-default-submodes 'global-semantic-decoration-mode)
  ;; Smart autocomplete
  (require 'semantic/ia)
  ;; SpeedBar
  (require 'semantic/sb)
  ;; (require 'semantic/wisent)
  ;; (require 'semantic/symref)
  ;; Include semantic-symref-results-mode-map and related
  (require 'semantic/symref/list)
  ;; [ Autocomplete with gcc headers
  ;; inside company-extensions-config.el
  ;; (require 'semantic/bovine/gcc)
  ;; ]
  ;; Not found
  ;;(require 'semantic/bovine/clang)
  ;; After 'require' and after update 'semantic-default-submodes' list
  ;;(semantic-mode 1)

  ;; Autocompletado usando los .h incluidos de librerías personales
  ;; [ Extremadamente lento para proyectos grandes
  ;; (semantic-add-system-include "~/Prog/c/lib" 'c++-mode)
  ;; ]
  ;; Java autocomplete
  ;;(require 'semantic/db-javap)
  ;;(require 'semantic-bug)

;;;;;;;;;;;;;;;;;;;;;;;;
;; Semantic parse dir ;;
;;;;;;;;;;;;;;;;;;;;;;;;
  (defvar semantic-parse-c-files-regex "\\.\\(c\\|cc\\|cpp\\|cxx\\|h\\|hpp\\|hxx\\)$"
    "A regular expression to match any c/c++ related files under a directory.")

  (defvar semantic-parse-exclude-files-regex "/\\.\\(hg\\|git\\)/")

  (defun semantic-parse-dir-regex (root regex &optional exclude)
    "Parse dirs in ROOT that match REGEX and exclude EXCLUDE."
    (dolist (file (cl-remove-if
                   (lambda (arg) (string-match-p
                                  (or exclude semantic-parse-exclude-files-regex)
                                  arg))
                   (directory-files-recursively
                    root
                    regex)))
      (semanticdb-file-table-object file)))

  (defun semantic-parse-dir (root)
    "Make Semantic parse all source files in directory ROOT, recursively."
    (interactive (list (read-directory-name "Root directory: "
                                            default-directory)))
    (semantic-parse-dir-regex root semantic-parse-c-files-regex))

  ;; (defun semantic-parse-dir (root regex)
  ;;   "This function is an attempt of mine to force semantic to
  ;;    parse all source files under a root directory. Arguments:
  ;;    -- root: The full path to the root directory
  ;;    -- regex: A regular expression against which to match all files in the directory"
  ;;   (let (
  ;;         ;;make sure that root has a trailing slash and is a dir
  ;;         (root (file-name-as-directory root))
  ;;         (files (directory-files root t ))
  ;;        )
  ;;     ;; remove current dir and parent dir from list
  ;;     (setq files (delete (format "%s." root) files))
  ;;     (setq files (delete (format "%s.." root) files))
  ;;     ;; remove any known version control directories
  ;;     (setq files (delete (format "%s.git" root) files))
  ;;     (setq files (delete (format "%s.hg" root) files))
  ;;     (while files
  ;;       (setq file (pop files))
  ;;       (if (not(file-accessible-directory-p file))
  ;;           ;;if it's a file that matches the regex we seek
  ;;           (progn (when (string-match-p regex file)
  ;;                    (save-excursion
  ;;                      (semanticdb-file-table-object file))
  ;;            ))
  ;;           ;;else if it's a directory
  ;;           (semantic-parse-dir file regex)
  ;;       )
  ;;      )
  ;;   )
  ;; )

  ;; (defun semantic-parse-current-dir (regex)
  ;;   "Parses all files under the current directory matching regex"
  ;;   (semantic-parse-dir (file-name-directory buffer-file-name) regex)
  ;; )
  
  ;; (defun semantic-parse-curdir-c ()
  ;;   "Parses all the c/c++ related files under the current directory
  ;;    and inputs their data into semantic"
  ;;   (interactive)
  ;;   (semantic-parse-current-dir semantic-parse-c-files-regex)
  ;; )
  
  ;; (defun semantic-parse-dir-c (dir)
  ;;   "Prompts the user for a directory and parses all c/c++ related files
  ;;    under the directory"
  ;;   (interactive (list (read-directory-name "Provide the directory to search in:")))
  ;;   (semantic-parse-dir (expand-file-name dir) semantic-parse-c-files-regex)
  ;; )

;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;
  (defun semantic-complete-jump-at-point (point)
    "Find definition/declaration of symbol at POINT.
Improve default ia jump at point."
    (interactive "d")
    (let* ((ctxt (semantic-analyze-current-context point))
           (pf (and ctxt (reverse (oref ctxt prefix))))
           (first-tag (car pf)))
      (if (semantic-tag-p first-tag)
          (semantic-ia--fast-jump-helper first-tag)
        (progn
          (semantic-error-if-unparsed)
          (let* ((tag (semantic-complete-read-tag-project "Jump to symbol: " first-tag first-tag)))
            (when (semantic-tag-p tag)
              (push-mark nil t)
              (semantic-go-to-tag tag)
              (switch-to-buffer (current-buffer))
              (semantic-momentary-highlight-tag tag)
              (message "%S: %s "
                       (semantic-tag-class tag)
                       (semantic-tag-name  tag))))))))

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
  ;; (bind-keys :map semantic-mode-map
  ;;            ([(control return)] . semantic-ia-complete-symbol)
  ;;            ("C-c , a" . semantic-complete-analyze-inline)
  ;;            ("C-c , s" . semantic-ia-show-summary)
  ;;            ("C-c , d" . semantic-ia-show-doc)
  ;;            ("C-c , c" . semantic-ia-describe-class)
  ;;            ("M-," . semantic-analyze-proto-impl-toggle) ; "C-c , p"
  ;;            ("M-." . ido-semantic-complete-jump) ; "C-c , j"
  ;;            ("M--" . semantic-analyze-possible-completions)
  ;;            ("M-Ç" . semantic-symref)
  ;;            ("M-ç" . semantic-symref-symbol)
  ;;            ;; senator
  ;;            ("C-c , +" . senator-fold-tag)
  ;;            ("C-c , -" . senator-unfold-tag)
  ;;            ("C-c , ." . senator-fold-tag-toggle))
  (define-key semantic-symref-results-mode-map "e" #'semantic-symref-list-expand-all)
  (define-key semantic-symref-results-mode-map "c" #'semantic-symref-list-contract-all)

  ;;(semantic-mode 1)

  (require 'srecode)
  ;;(global-srecode-minor-mode 1)

  ;; stickfunc improved
  (require 'stickyfunc-enhance))

(with-eval-after-load 'semantic
  (message "Importing gud config")

  (with-eval-after-load 'gud
    ;; ;; (setq gud-gdb-command-name "gdb --annotate=3 --fullname")

    ;; ;; [ <color> Add color to the current GUD line (by google)
    ;; ;; (defvar gud-overlay
    ;; ;;   (let* ((ov (make-overlay (point-min) (point-min))))
    ;; ;;     (overlay-put ov 'face 'secondary-selection)
    ;; ;;     ov)
    ;; ;;   "Overlay variable for GUD highlighting.")

    ;; ;; (defadvice gud-display-line (after my-gud-highlight act)
    ;; ;;            "Highlight current line."
    ;; ;;            (let* ((ov gud-overlay)
    ;; ;;                   (bf (gud-find-file true-file)))
    ;; ;;              (save-excursion
    ;; ;;                  (set-buffer bf)
    ;; ;;                    (move-overlay ov (line-beginning-position) (line-end-position)
    ;; ;;                                    (current-buffer)))))

    ;; ;; (defun gud-kill-buffer ()
    ;; ;;   (if (eq major-mode 'gud-mode)
    ;; ;;     (delete-overlay gud-overlay)))

    ;; ;; (add-hook 'kill-buffer-hook 'gud-kill-buffer)
    ;; ;; ] <color>


    ;; =================================
    ;; PDB configuration
    ;; =================================
    (defun pdb-advice (orig-fun &rest args)
      ;; don't change default directory
      (let ((gud-chdir-before-run nil)
            (default-directory
              (if current-prefix-arg
                  (read-directory-name "Default directory: " nil nil t)
                (or (and (featurep 'projectile)
                         (projectile-project-root))
                    default-directory))))
        (apply orig-fun args)))
    (advice-add 'pdb :around 'pdb-advice)
    (setq gud-pdb-command-name "python -m pdb"))
  ;; =================================
  ;; GDB configuration
  ;; =================================
  (with-eval-after-load 'gdb-mi

    ;; Dedicated windows except source window
    (defun gdb-dedicated-windows ()
      (dolist (window (window-list))
        (when
            (and
             (eq
              0
              (string-match
               "*gud\\|*stack\\|*locals\\|*registers\\|*input/output\\|*breakpoints"
               (buffer-name (window-buffer window))))
             (not (buffer-file-name (window-buffer window))))
          (set-window-dedicated-p window t))))
    (advice-add  'gdb-setup-windows :after #'gdb-dedicated-windows)

    ;; Window options
    (setq gdb-many-windows t
          gdb-use-separate-io-buffer t)

    (add-hook 'gdb-mode-hook 'gud-tooltip-mode)
    ;;(add-hook 'gdb-mode-hook '(lambda () (require 'gdb-highlight)))


    ;; [ <history> cycle command history
    ;; (add-hook 'gud-mode-hook
    ;;           '(lambda ()
    ;;             (local-set-key [home]        ; move to beginning of line, after prompt
    ;;              'comint-bol)
    ;;             (local-set-key [up]          ; cycle backward through command history
    ;;              '(lambda () (interactive)
    ;;                (if (comint-after-pmark-p)
    ;;                    (comint-previous-input 1)
    ;;                    (previous-line 1))))
    ;;             (local-set-key [down]        ; cycle forward through command history
    ;;              '(lambda () (interactive)
    ;;                (if (comint-after-pmark-p)
    ;;                    (comint-next-input 1)
    ;;                  (forward-line 1))))))
    ;; ] <history>

;;;;;;;;;;;;;;;;;;
    ;; New commands ;;
;;;;;;;;;;;;;;;;;;

    (defun gdb-new-commands (command-line)
      (gud-def gud-args "info args" "a" "Show args variables.")
      (gud-def gud-kill "kill" "k" "Kill running process.")
      (gud-def gud-quit "quit" "q" "Quit gdb."))
    (advice-add 'gdb :after #'gdb-new-commands)

;;;;;;;;;;
    ;; Keys ;;
;;;;;;;;;;

    (defhydra hydra-gud (:foreign-keys run);(gud-minor-mode-map "C-x C-a" :foreign-keys run)
      "GUD"
      ("<" gud-up "up")
      (">" gud-down "down")
      ("C-b" gud-break "break")
      ("C-d" gud-remove "remove")
      ("C-f" gud-finish "finish")
      ("C-j" gud-jump "jump")
      ("C-l" gud-refresh "refresh")
      ("C-n" gud-next "next")
      ("C-p" gud-print "print")
      ("C-c" gud-cont "continue")
      ("C-r" gud-run "run")
      ("C-s" gud-step "step")
      ;;("C-t" gud-tbreak "tbreak")
      ("C-u" gud-until "until")
      ("C-w" gud-watch "watch")
      ("C-a" gud-args "args")
      ("C-t" gud-tooltip-mode "tooltip")
      ("C-k" gud-kill "kill")
      ("C-q" gud-quit "quit" :color blue) ; blue color exec and quit hydra
      ("M-q" nil ""))
    (define-key gud-minor-mode-map (kbd "C-x C-a m") #'hydra-gud/body)
    (define-key gud-minor-mode-map (kbd "C-c C-t") #'gud-tooltip-mode)))

(defvar custom-lsp-startup-function 'eglot-ensure
  "'eglot-ensure or 'lsp-deferred")

(cl-case custom-lsp-startup-function
  ('eglot-ensure
   ;; eglot
   (with-eval-after-load 'eglot
     (require 'eglot-config)))
  ('lsp-deferred
   ;; lsp
   (with-eval-after-load 'lsp-mode
     (require 'lsp-config))
   ;; dap
   (with-eval-after-load 'dap-mode
     (require 'dap-config))))

(add-hook 'python-mode-hook custom-lsp-startup-function)
(setq python-shell-interpreter (or (executable-find "~/bin/python-emacs")
                                   (executable-find "~/bin/pypy3")
                                   (executable-find "~/bin/pypy")
                                   (executable-find "/usr/local/bin/python3")
                                   (executable-find "/usr/bin/python3")
                                   (executable-find "/usr/local/bin/python")
                                   (executable-find "/usr/bin/python")))
(with-eval-after-load 'python
  ;;  (require 'semantic/wisent/python)
  (require 'python-config)
  ;;  (add-hook 'python-mode-hook #'detect-python-project-version)
  (with-eval-after-load 'dap-mode
    (require 'dap-python)))

;; flymake
(add-hook 'emacs-lisp-mode-hook #'flymake-mode)
(with-eval-after-load 'flymake
  (message "Importing flymake-config")

  ;; If nil, never start checking buffer automatically like this.
  (setq flymake-no-changes-timeout 2.0)

  ;; thanks to: stackoverflow.com/questions/6110691/is-there-a-way-to-make-flymake-to-compile-only-when-i-save
  ;; (defun flymake-after-change-function (start stop len)
  ;;   "Start syntax check for current buffer if it isn't already running.
  ;; START and STOP and LEN are as in `after-change-functions'."
  ;;     ;; Do nothing, don't want to run checks until I save.
  ;;   )

  (when (require 'flymake-diagnostic-at-point nil 'noerror)
    (add-hook 'flymake-mode-hook #'flymake-diagnostic-at-point-mode)
    (setq flymake-diagnostic-at-point-timer-delay 2.0))

  ;; custom modeline
  (when (bug-check-function-bytecode
         'flymake--mode-line-format
         "CMVDxsfIycrLBgYhzCLNziUDIoiJop+2gs8g0CDRINIgAoUnAAM/0wUEIsbHyNTKywYIIdUi1tclCCKI2Nna29zd3gYNRyLd3wYNRyLd4AYNRyLhUuLjIOQB5QkjiOQB5ucjiImyAa8I6AYIhHMA6YKMAAKDgwDq693sBgZHIkWCjAADg4sA7YKMAO6JQAFBiUABQYlAAUEBBAYHiYW4AO/YAvAF3AYI4uMg5AHx8iOIibIBrwhEQ7aDtocEhsMABgk/P4UIAgXFQ8bHyMnKywYGIcwizc4lAyKIiaKftoLzxQE6g/oAAUCyAfQBBPX2JLIDAUGyAoLiAMW2gvcC+PX2JMWJiYkEOoPOAQRAsgT5BAYOIrID+gT7/COyAgKEOgEK/T2ExwEKgzYB9gQh/gohWYI3Af2DxwGJ2N3/BgZHIvAF2tvi4yAGDOQCy4FAAAsix4FBAIFCAMrLBgghgUMAIoFEAIFFAIFGACYGI4jkAsuBQAAMIseBQQCBQgDKywYIIYFHACKBRACBRQCBRgAmBiOIAbaC3N2BSACBSQDd/wYRRyLwBhAjgUkA3YFKAAYTIvAGESMj3YFLAAsMI1CvCkOksgEEQbIFggcBgUwA6ALFiYkDOoP9AQOyAwKJQbIEorICAQFCsgECg/YBgU0AAUKyAQNBsgSC1gGJn7aEgU4AIkK2hyJChw==")
    (defun flymake--mode-line-format ()
      "Produce a pretty minor mode indicator."
      (let* ((known (hash-table-keys flymake--backend-state))
             (running (flymake-running-backends))
             (disabled (flymake-disabled-backends))
             (reported (flymake-reporting-backends))
             (diags-by-type (make-hash-table))
             (all-disabled (and disabled (null running)))
             (some-waiting (cl-set-difference running reported)))
        (maphash `(lambda (_b state)
                    (mapc (lambda (diag)
                            (push diag
                                  (gethash (flymake--diag-type diag)
                                           ,diags-by-type)))
                          (flymake--backend-state-diags state)))
                 flymake--backend-state)
        `((:propertize "!"
                       mouse-face mode-line-highlight
                       help-echo
                       ,(concat (format "%s known backends\n" (length known))
                                (format "%s running\n" (length running))
                                (format "%s disabled\n" (length disabled))
                                "mouse-1: Display minor mode menu\n"
                                "mouse-2: Show help for minor mode")
                       keymap
                       ,(let ((map (make-sparse-keymap)))
                          (define-key map [mode-line down-mouse-1]
                            flymake-menu)
                          (define-key map [mode-line mouse-2]
                            (lambda ()
                              (interactive)
                              (describe-function 'flymake-mode)))
                          map))
          ,@(pcase-let ((`(,ind ,face ,explain)
                         (cond ((null known)
                                '("?" mode-line "No known backends"))
                               (some-waiting
                                `("…" compilation-mode-line-run
                                  ,(format "Waiting for %s running backend(s)"
                                           (length some-waiting))))
                               (all-disabled
                                '("!" compilation-mode-line-run
                                  "All backends disabled"))
                               (t
                                '(nil nil nil)))))
              (when ind
                `(((:propertize ,ind
                                face ,face
                                help-echo ,explain
                                keymap
                                ,(let ((map (make-sparse-keymap)))
                                   (define-key map [mode-line mouse-1]
                                     'flymake-switch-to-log-buffer)
                                   map))))))
          ,@(unless (or all-disabled
                        (null known))
              (cl-loop
               with types = (hash-table-keys diags-by-type)
               with _augmented = (cl-loop for extra in '(:error :warning)
                                          do (cl-pushnew extra types
                                                         :key #'flymake--severity))
               for type in (cl-sort types #'> :key #'flymake--severity)
               for diags = (gethash type diags-by-type)
               for face = (flymake--lookup-type-property type
                                                         'mode-line-face
                                                         'compilation-error)
               when (or diags
                        (cond ((eq flymake-suppress-zero-counters t)
                               nil)
                              (flymake-suppress-zero-counters
                               (>= (flymake--severity type)
                                   (warning-numeric-level
                                    flymake-suppress-zero-counters)))
                              (t t)))
               collect `(:propertize
                         ,(format "%d" (length diags))
                         face ,face
                         mouse-face mode-line-highlight
                         keymap
                         ,(let ((map (make-sparse-keymap))
                                (type type))
                            (define-key map (vector 'mode-line
                                                    mouse-wheel-down-event)
                              `(lambda (event)
                                 (interactive "e")
                                 (with-selected-window (posn-window (event-start event))
                                   (flymake-goto-prev-error 1 (list ,type) t))))
                            (define-key map (vector 'mode-line
                                                    mouse-wheel-up-event)
                              `(lambda (event)
                                 (interactive "e")
                                 (with-selected-window (posn-window (event-start event))
                                   (flymake-goto-next-error 1 (list ,type) t))))
                            map)
                         help-echo
                         ,(concat (format "%s diagnostics of type %s\n"
                                          (propertize (format "%d"
                                                              (length diags))
                                                      'face face)
                                          (propertize (format "%s" type)
                                                      'face face))
                                  (format "%s/%s: previous/next of this type"
                                          mouse-wheel-down-event
                                          mouse-wheel-up-event)))
               into forms
               finally return
               `((:propertize "{")
                 ,@(cl-loop for (a . rest) on forms by #'cdr
                            collect a when rest collect
                            '(:propertize " "))
                 (:propertize "}"))))))))

  (define-key flymake-mode-map (kbd "M-g n") #'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "M-g M-n") #'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "M-g p") #'flymake-goto-prev-error)
  (define-key flymake-mode-map (kbd "M-g M-p") #'flymake-goto-prev-error)
  (define-key flymake-mode-map (kbd "C-c ! c") #'flymake-start))

;; Disabled because annoying cursor movement
;; (require 'flyspell-lazy)

;; [ better call `flyspell-buffer' C-c i c
;; (dolist (hook '(text-mode-hook))
;;   (add-hook hook (lambda () (flyspell-mode 1))))
;; (dolist (hook '(change-log-mode-hook log-edit-mode-hook))
;;   (add-hook hook (lambda () (flyspell-mode -1))))

;; (dolist (hook '(prog-mode-hook))
;; ;;  (add-hook hook #'flyspell-lazy-mode)
;;   (add-hook hook 'flyspell-prog-mode))
;; ]

(with-eval-after-load 'flyspell
  (message "Importing flyspell config")

  (setq flyspell-use-meta-tab nil)
  (setq flyspell-mode-line-string "")
;;;;;;;;;;;
;; Faces ;;
;;;;;;;;;;;
  (set-face-attribute 'flyspell-incorrect nil
                      :underline "red1")
  (set-face-attribute 'flyspell-duplicate nil
                      :underline "magenta")

;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;

  ;; move point to previous error
  ;; based on code by hatschipuh at
  ;; http://emacs.stackexchange.com/a/14912/2017
  (defun flyspell-goto-previous-error (arg)
    "Go to ARG previous spelling error."
    (interactive "p")
    (while (not (= 0 arg))
      (let ((pos (point))
            (min (point-min)))
        (if (and (eq (current-buffer) flyspell-old-buffer-error)
                 (eq pos flyspell-old-pos-error))
            (progn
              (if (= flyspell-old-pos-error min)
                  ;; goto beginning of buffer
                  (progn
                    (message "Restarting from end of buffer")
                    (goto-char (point-max)))
                (backward-word 1))
              (setq pos (point))))
        ;; seek the next error
        (while (and (> pos min)
                    (let ((ovs (overlays-at pos))
                          (r '()))
                      (while (and (not r) (consp ovs))
                        (if (flyspell-overlay-p (car ovs))
                            (setq r t)
                          (setq ovs (cdr ovs))))
                      (not r)))
          (backward-word 1)
          (setq pos (point)))
        ;; save the current location for next invocation
        (setq arg (1- arg))
        (setq flyspell-old-pos-error pos)
        (setq flyspell-old-buffer-error (current-buffer))
        (goto-char pos)
        (if (= pos min)
            (progn
              (message "No more miss-spelled word!")
              (setq arg 0))))))

;;;;;;;;;;
  ;; Keys ;;
;;;;;;;;;;
  (define-key flyspell-mouse-map (kbd "<C-down-mouse-2>") #'flyspell-correct-word)
  (define-key flyspell-mouse-map (kbd "<C-mouse-2>") #'undefined)
  (define-key flyspell-mouse-map [down-mouse-2] nil)
  (define-key flyspell-mouse-map [mouse-2] nil)
  (define-key flyspell-mode-map [?\C-c ?$] nil)
  (define-key flyspell-mode-map flyspell-auto-correct-binding nil)
  (define-key flyspell-mode-map [(control ?\,)] nil)
  (define-key flyspell-mode-map [(control ?\.)] nil)
  (define-key flyspell-mode-map (kbd "C-M-i") nil)
  (define-key flyspell-mode-map (kbd "C-c i c") #'flyspell-buffer)
  (define-key flyspell-mode-map (kbd "C-c i n") #'flyspell-goto-next-error)
  (define-key flyspell-mode-map (kbd "C-c i p") #'flyspell-goto-previous-error)
  (define-key flyspell-mode-map (kbd "C-c i a") #'flyspell-auto-correct-word)
  (define-key flyspell-mode-map (kbd "C-c i A") #'flyspell-auto-correct-previous-word)
  (if (load "helm-flyspell" t)
      (progn
        (define-key flyspell-mode-map (kbd "C-c i .") #'helm-flyspell-correct)
        (define-key flyspell-mode-map (kbd "C-c i ,") #'helm-flyspell-correct))
    (define-key flyspell-mode-map (kbd "C-c i .") #'flyspell-correct-at-point)
    (define-key flyspell-mode-map (kbd "C-c i ,") #'flyspell-correct-word-before-point))

  ;; Change mouse over help text
  (let ((item (aref (aref (symbol-function 'make-flyspell-overlay) 2) 12)))
    (if (and (stringp item)
             (string-equal item "mouse-2: correct word at point"))
        (aset (aref (symbol-function 'make-flyspell-overlay) 2)
              12 "C-mouse-2: correct word at point")))

  ;;(fset 'flyspell-emacs-popup 'flyspell-emacs-popup-textual)
  (defhydra hydra-spell (:foreign-keys warn)
    "SPELL"
    ("C-b" flyspell-buffer "buffer")
    ("C-n" flyspell-goto-next-error "next")
    ("C-p" flyspell-goto-previous-error "previous")
    ("C-c" flyspell-correct-word-before-point "correct")
    ("C-a" flyspell-auto-correct-word "auto")
    ("M-q" nil "quit"))
  (define-key flyspell-mode-map (kbd "C-c i m") 'hydra-spell/body)
  (define-key flyspell-mode-map (kbd "C-c i >") 'cycle-ispell-languages)
  (define-key flyspell-mode-map (kbd "C-c i s") 'spanish-dictionary)
  (define-key flyspell-mode-map (kbd "C-c i e") 'english-dictionary))

(when (require 'cyphejor nil t)
  (setq cyphejor-rules
        '(:upcase
          ("bookmark"    "→")
          ("buffer"      "β")
          ("c"           "ȼ")
          ("csv"         ",")
          ("diff"        "Δ")
          ("dired"       "δ")
          ("elfeed"      "📰")
          ("emacs"       "ε")
          ("emms"        "♪")
          ("eshell"      "ε∫" :postfix)
          ("exwm"        "χ")
          ("fish"        "φ")
          ("fundamental" "∅")
          ("help"        "?")
          ("inferior"    "i" :prefix)
          ("interaction" "i" :prefix)
          ("interactive" "i" :prefix)
          ("lisp"        "λ" :postfix)
          ("menu"        "▤" :postfix)
          ("mode"        "")
          ("nim"         "ℵ")
          ("org"         "Ω")
          ("package"     "↓")
          ("python"      "π")
          ("rust"        "⚙")
          ("search"      "🔍")
          ("sh"          "$")
          ("shell"       "∫" :postfix)
          ("show"        "✓")
          ("text"        "ξ")
          ("tsv"         "↹")
          ("wdired"      "↯δ")
          ("web"         "ω")
          ("yaml"        "Ⲩ")
          ))
  (cyphejor-mode))

(when (load "company" t)
  ;; [ required
  ;; sudo apt-get install libclang-3.4-dev clang-3.4 clang-format-3.4 clang-modernize-3.4 clang
  ;; ]
  ;;(add-to-list 'load-path "~/.emacs.d/elpa/company-0.8.12")
  ;;(add-to-list 'load-path "~/.emacs.d/elpa/elpa/company-c-headers-20150801.901")
  (if (null (require 'company-template nil 'noerror))
      (message-color #("ERROR missing package `company-template'"
                       0 5 (face error)))
    (define-key company-template-nav-map [(shift tab)]
      (lookup-key company-template-nav-map [tab]))
    (define-key company-template-nav-map (kbd "<backtab>")
      (lookup-key company-template-nav-map (kbd "TAB")))
    (define-key company-template-nav-map [tab] nil)
    (define-key company-template-nav-map (kbd "TAB") nil))
  ;; [
  ;;(require 'company-capf)
  ;; ]
  ;;(require 'company-c-headers)
  ;;(require 'company-yasnippet)

  (defface mode-line-company-mode
    '((t :foreground "slate blue" :weight bold))
    "Project name" :group 'mode-line)
  (setcar (cdr (assq 'company-mode minor-mode-alist))
          (propertize "C" 'face 'mode-line-company-mode))
  (add-hook 'after-init-hook 'global-company-mode)

  ;; Colors
  (face-spec-set 'company-preview '((t (:foreground "darkgray" :underline t))))
  (face-spec-set 'company-preview-common '((t (:inherit company-preview))))
  (face-spec-set 'company-tooltip '((t (:background "lightgray" :foreground "black"))))
  (face-spec-set 'company-tooltip-selection '((t (:background "steelblue" :foreground "white"))))
  (face-spec-set 'company-tooltip-common '((((type x)) (:inherit company-tooltip :weight bold))
                                           (t (:inherit company-tooltip))))
  (face-spec-set 'company-tooltip-common-selection
                 '((((type x)) (:inherit company-tooltip-selection :weight bold))
                   (t (:inherit company-tooltip-selection))))


  ;; [ disable slow 'company-semantic'. comment with ede-project
  ;;(delete 'company-semantic company-backends)
  ;; ]
  (setq company-tooltip-minimum-width 20
        company-tooltip-minimum 2
        company-selection-wrap-around t
        company-minimum-prefix-length 1
        company-idle-delay 0.2
        company-tooltip-idle-delay 0.2)

  (defun toggle-company-semantic ()
    "Toggle semantic backend."
    (interactive)
    (if (memq 'company-semantic company-backends)
        (progn
          (delete 'company-semantic company-backends)
          (message "`company-semantic' removed from company backends"))
      (push 'company-semantic company-backends)
      (message "`company-semantic' added to company backends")))

  ;; company-c-headers
  ;; (add-to-list 'company-backends 'company-c-headers)
  ;; company c++ system headers
  ;; (with-eval-after-load 'cc-mode
  ;;   (require 'semantic/bovine/gcc)
  ;;   (let ((dirs (semantic-gcc-get-include-paths "c++")))
  ;;     (dolist (dir dirs)
  ;;       (add-to-list 'company-c-headers-path-system (concat dir "/"))))
  ;;   (delete-dups company-c-headers-path-system))
  ;; company c++ user headers
  ;; (with-eval-after-load 'c-c++-config
  ;;   (dolist (path c-c++-include-paths)
  ;;     (add-to-list 'company-c-headers-path-user path)))
  ;; hs-minor-mode for folding source code
  ;;(add-hook 'c-mode-common-hook 'hs-minor-mode)

  ;; Available C style:
  ;; “gnu”: The default style for GNU projects
  ;; “k&r”: What Kernighan and Ritchie, the authors of C used in their book
  ;; “bsd”: What BSD developers use, aka “Allman style” after Eric Allman.
  ;; “whitesmith”: Popularized by the examples that came with Whitesmiths C, an early commercial C compiler.
  ;; “stroustrup”: What Stroustrup, the author of C++ used in his book
  ;; “ellemtel”: Popular C++ coding standards as defined by “Programming in C++, Rules and Recommendations,” Erik Nyquist and Mats Henricson, Ellemtel
  ;; “linux”: What the Linux developers use for kernel development
  ;; “python”: What Python developers use for extension modules
  ;; “java”: The default style for java-mode (see below)
  ;; “user”: When you want to define your own style
  ;; (setq
  ;;  c-default-style "linux" ;; set style to "linux"
  ;;  )

  (with-eval-after-load 'company-dabbrev
    (setq company-dabbrev-downcase nil))

;;;;;;;;;;;;;;
;; Posframe ;;
;;;;;;;;;;;;;;
  (when (and (display-graphic-p) (load "company-posframe" t))
    (setq company-posframe-lighter "")
    (add-hook 'company-mode-hook #'company-posframe-mode))

;;;;;;;;;;;;
;; Auxtex ;;
;;;;;;;;;;;;
  (with-eval-after-load 'auctex
    (require 'company-auctex)
    (company-auctex-init))

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
  ;; (define-key c-mode-map  [(tab)] 'company-complete)
  ;; (define-key c++-mode-map  [(tab)] 'company-complete)
  (define-key company-active-map [return] nil)
  (define-key company-active-map (kbd "RET") nil)
  (define-key company-active-map [tab] #'company-complete-selection)
  (define-key company-active-map (kbd "TAB") #'company-complete-selection)
  (define-key company-active-map (kbd "<backtab>") #'company-complete-common-or-cycle)
  (define-key company-active-map [?\C-o] #'company-other-backend)
  (define-key company-active-map [?\C-t] #'company-begin-backend)
  ;;(define-key company-mode-map [(control tab)] 'company-complete)
  ;; `company-complete` conflicts with `company-template-forward-field` with TAB #515

  (global-set-key (kbd "M-s 7 ,") 'toggle-company-semantic)
  (global-set-key (kbd "C-c y") #'company-yasnippet)
  (global-set-key (kbd "C-c c c") #'company-complete)
  (global-set-key (kbd "C-c c b") #'company-begin-backend))

(require 'ace-window)
(set-face-attribute 'aw-mode-line-face nil
                    :weight 'bold
                    :foreground "mint cream")
(set-face-attribute 'aw-leading-char-face nil
                    :weight 'bold
                    :foreground "green"
                    :height 170)

(defun aw-real-move-window (window)
  "Real move the current buffer to WINDOW.
Switch the current window to the previous buffer."
  (let ((buffer (current-buffer)))
    (delete-window (selected-window))
    (aw-switch-to-window window)
    (switch-to-buffer buffer)))


(push " *which-key*" aw-ignored-buffers)
(setq minor-mode-alist
      (assq-delete-all 'ace-window-mode minor-mode-alist)
      aw-scope 'global
      aw-dispatch-alist
      '((?R aw-refresh "Refresh mode-line")
        (?X aw-delete-window "Delete Window")
        (?S aw-swap-window "Swap Windows")
        (?M aw-real-move-window "Move Window")
        (?C aw-copy-window "Copy Window")
        (?J aw-switch-buffer-in-window "Select Buffer")
        (?N aw-flip-window)
        (?U aw-switch-buffer-other-window "Switch Buffer Other Window")
        (?E aw-execute-command-other-window "Execute Command Other Window")
        (?F aw-split-window-fair "Split Fair Window")
        (?V aw-split-window-vert "Split Vert Window")
        (?B aw-split-window-horz "Split Horz Window")
        (?O delete-other-windows "Delete Other Windows")
        (?T aw-transpose-frame "Transpose Frame")
        ;; ?i ?r ?t are used by hyperbole.el
        (?? aw-show-dispatch-help))
      aw-keys
      (let ((keys
             '(?a ?b ?c ?d ?e ?f ?g ?h ;; ?i
                  ?j ?k ?l ?m ?n ?o ?p ?q ;; ?r
                  ?s ;; ?t
                  ?u ?v ?w ?x ?y ?z)))
        (dolist (dispatch aw-dispatch-alist)
          (setq keys (delete (car dispatch) keys)))
        keys)
      aw-dispatch-always t
      aw-minibuffer-flag t
      aw-background t)

(defun aw-refresh ()
  (interactive)
  (aw-update)
  (force-mode-line-update t))

(ace-window-display-mode)

(global-set-key (kbd "M-o") 'ace-window)
(global-set-key (kbd "M-O") 'aw-refresh)

(require 'hydra)
(setq hydra-head-format "%s ")

(require 'operate-on-number)

(defhydra hydra-operate (:foreign-keys nil)
  "OPERATE"
  ("+"  apply-operation-to-number-at-point)
  ("-"  apply-operation-to-number-at-point)
  ("*"  apply-operation-to-number-at-point)
  ("/"  apply-operation-to-number-at-point)
  ("\\" apply-operation-to-number-at-point)
  ("^"  apply-operation-to-number-at-point)
  ("<"  apply-operation-to-number-at-point)
  (">"  apply-operation-to-number-at-point)
  ("#"  apply-operation-to-number-at-point)
  ("%"  apply-operation-to-number-at-point)
  ("'"  operate-on-number-at-point))

(global-set-key (kbd "C-c o m") #'hydra-operate/body)
(global-set-key (kbd "C-c o o") #'operate-on-number-at-point-or-region)

(require 'avy)
(require 'link-hint)

(setq avy-dispatch-alist
      '((?M . avy-action-kill-move)
        (?K . avy-action-kill-stay)
        (?T . avy-action-teleport)
        (?  . avy-action-mark)
        (?C . avy-action-copy)
        (?Y . avy-action-yank)
        (?L . avy-action-yank-line)
        (?I . avy-action-ispell)
        (?Z . avy-action-zap-to-char))
      avy-keys
      (let ((keys
             '(?q ?w ?e ?r ?t ?y ?u ?i ?o ?p
                  ?a ?s ?d ?f ?g ?h ?j ?k ?l
                  ?z ?x ?c ?v ?b ?n ?m)))
        (dolist (dispatch avy-dispatch-alist)
          (setq keys (delete (car dispatch) keys)))
        keys)
      avy-single-candidate-jump t)

(defmacro avy-prefix-all-windows (avy-fun)
  `(defun ,(intern (concat (symbol-name avy-fun)
                           "-prefix-all-windows"))
       (arg)
     (interactive "p")
     (let ((current-prefix-arg nil)
           (avy-all-windows (cl-case arg
                             (1 nil)
                             ((2 4) t)
                             ((3 5 16) 'all-frames)
                             (otherwise avy-all-windows))))
       (call-interactively (quote ,avy-fun)))))

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
(global-set-key (kbd "M-g c") (avy-prefix-all-windows
                               avy-goto-char))
(global-set-key (kbd "M-g C") (avy-prefix-all-windows
                               avy-goto-char-2))
(global-set-key (kbd "M-g s") (avy-prefix-all-windows
                               avy-goto-char-timer))
(global-set-key (kbd "M-g l") (avy-prefix-all-windows
                               avy-goto-line))
(global-set-key (kbd "M-g w") (avy-prefix-all-windows
                               avy-goto-word-1))
(global-set-key (kbd "M-g W") (avy-prefix-all-windows
                               avy-goto-word-0))
(global-set-key (kbd "M-z")   (avy-prefix-all-windows
                               avy-goto-word-or-subword-1))
(global-set-key (kbd "M-Z")   (avy-prefix-all-windows
                               avy-resume))
(global-set-key (kbd "M-g k") (avy-prefix-all-windows
                               link-hint-open-link))
(global-set-key (kbd "M-g K") (avy-prefix-all-windows
                               link-hint-copy-link))
(global-set-key (kbd "M-g SPC") 'avy-pop-mark)

(setq bookmark-default-file "~/.emacs.d/cache/bookmarks")

(require 'bookmark+)

(setq bmkp-auto-light-when-jump 'all-in-buffer
      bmkp-auto-light-when-set 'all-in-buffer
      bmkp-last-as-first-bookmark-file nil
      ;;bmkp-light-style-autonamed 'lfringe
      ;;bmkp-light-style-non-autonamed 'lfringe
      bmkp-bmenu-commands-file "~/.emacs.d/cache/bmk-bmenu-commands.el"
      bmkp-bmenu-state-file "~/.emacs.d/cache/bmk-bmenu-state.el")

(set-face-background 'bmkp-light-non-autonamed "DarkSlateGray")
(set-face-background 'bmkp-light-autonamed "DimGray")

(require 'which-key)

(setq which-key-lighter ""
      ;; Allow C-h to trigger which-key before it is done automatically
      which-key-show-early-on-C-h t
      ;; Set the time delay (in seconds) for the which-key popup to appear.
      which-key-idle-delay 1.0

      ;; Set the maximum length (in characters) for key descriptions (commands or
      ;; prefixes). Descriptions that are longer are truncated and have ".." added.
      which-key-max-description-length 30

      ;; Use additonal padding between columns of keys. This variable specifies the
      ;; number of spaces to add to the left of each column.
      which-key-add-column-padding 0

      ;; Set the separator used between keys and descriptions. Change this setting to
      ;; an ASCII character if your font does not show the default arrow. The second
      ;; setting here allows for extra padding for Unicode characters. which-key uses
      ;; characters as a means of width measurement, so wide Unicode characters can
      ;; throw off the calculation.
      which-key-separator " → "
      which-key-unicode-correction 3

      ;; Set the prefix string that will be inserted in front of prefix commands
      ;; (i.e., commands that represent a sub-map).
      which-key-prefix-prefix "+"

      ;; Set to t to show the count of keys shown vs. total keys in the mode line.
      which-key-show-remaining-keys nil
      ;; which-key-special-keys nil
      ;; Location
      which-key-popup-type 'side-window
      which-key-side-window-location '(right bottom)
      which-key-show-prefix 'top)

(if (display-graphic-p)
    (progn
      (push '(("ESC" . nil) . ("⎋" . nil)) which-key-replacement-alist)
      (push '(("TAB" . nil) . ("↹" . nil)) which-key-replacement-alist)
      (push '(("RET" . nil) . ("↵" . nil)) which-key-replacement-alist)
      (push '(("DEL" . nil) . ("⇤" . nil)) which-key-replacement-alist)
      (push '(("SPC" . nil) . ("␣" . nil)) which-key-replacement-alist)
      (setq which-key-special-keys '("⎋" "↹" "↵" "⇤" "␣"))
      (set-face-attribute 'which-key-special-key-face nil
                      :bold t
                      :inverse-video 'unspecified
                      :inherit 'unspecified
                      :foreground "#78e56d")
      (when (require 'which-key-posframe nil t)
        (setq which-key-posframe-poshandler 'posframe-poshandler-frame-center)
        (which-key-posframe-mode)))
  ;; Set the special keys. These are automatically truncated to one character and
  ;; have which-key-special-key-face applied. Disabled by default. An example
  ;; setting is
  (setq which-key-special-keys '("SPC" "TAB" "RET" "ESC" "DEL"))
  (set-face-attribute 'which-key-special-key-face nil
                      :foreground "#78e56d"))

(global-set-key (kbd "C-h C-h") 'which-key-show-top-level)
(which-key-mode)

(require 'expand-region)

(setq expand-region-autocopy-register "º"
      expand-region-smart-cursor t
      expand-region-subword-enabled t)

(global-subword-mode)

(global-set-key (kbd "M-s r") #'er/expand-region)
(global-set-key (kbd "M-s s") #'er/mark-symbol)
(global-set-key (kbd "M-s d") #'mark-defun)
(global-set-key (kbd "M-s S") #'swap-regions)

(setq xterm-color-preserve-properties t)
(require 'xterm-color)

(if (daemonp)
    (setenv "EDITOR" "emacsclient -c -n")
  (setenv "EDITOR" "emacs"))
;; (setenv "PAGER" "cat")

(require 'rebox2)

(rebox-register-template 227 728
                         '("//,----------"
                           "//| box123456"
                           "//`----------"))

(setq rebox-style-loop '(41 27 23 21 11))

;;;;;;;;;
;; C++ ;;
;;;;;;;;;
(rebox-register-template 247 748
                         '("// ---------"
                           "// box123456"
                           "// ---------"))

(defun my-c++-setup ()
  "Override comment c and c++ defaults."
  (setq comment-start "/* "
        comment-end " */"
        rebox-min-fill-column 90)
  (unless (memq 46 rebox-style-loop)
    (make-local-variable 'rebox-style-loop)
    (setcdr (last rebox-style-loop) '(46 47))))
(add-hook 'c++-mode-hook #'my-c++-setup)

;;(global-set-key [(shift meta q)] 'rebox-dwim)
;;(global-set-key [(meta q)] 'rebox-cycle)

(defhydra hydra-rebox (:foreign-keys run)
  "BOX"
  ("C-+" (lambda () (interactive) (cl-incf rebox-min-fill-column 10) (rebox-fill) (message "Fill column: %i" rebox-min-fill-column)) "+10")
  ("C--" (lambda () (interactive) (cl-decf rebox-min-fill-column 10) (rebox-fill) (message "Fill column: %i" rebox-min-fill-column)) "-10")
  ("C-*" (lambda () (interactive) (cl-incf rebox-min-fill-column 1) (rebox-fill) (message "Fill column: %i" rebox-min-fill-column)) "+1")
  ("C-/" (lambda () (interactive) (cl-decf rebox-min-fill-column 1) (rebox-fill) (message "Fill column: %i" rebox-min-fill-column)) "-1")
  ("C-<left>" (lambda () (interactive) (rebox-cycle '(-1))))
  ("C-<right>" rebox-cycle "cycle")
  ("C-d" rebox-dwim "dwim")
  ("C-f" rebox-fill "fill")
  ("M-q" nil "quit"))

(global-set-key (kbd "C-c ; m") 'hydra-rebox/body)
(global-set-key (kbd "C-c ; l") 'comment-line)

(require 'thing-cmds-autoloads)

(require 'rotate-text)

(add-to-list 'rotate-text-symbols
             '("trace" "debug" "info" "warning" "error" "fatal"))
(add-to-list 'rotate-text-symbols
             '("unsigned" "signed"))
(add-to-list 'rotate-text-symbols
             '("void" "bool" "char" "wchar_t" "short" "int"
               "long" "size_t" "float" "double"))
(add-to-list 'rotate-text-symbols
             '("red" "green" "blue" "black" "white" "orange"
               "yellow" "cyan" "violet" "magenta" "brown"
               "salmon" "golden" "pink"))
(add-to-list 'rotate-text-symbols
             '("==" "!=" "<" ">" "<=" ">="))
(add-to-list 'rotate-text-symbols
             '("&&" "||"))
(add-to-list 'rotate-text-symbols
             '("=" "+=" "-=" "*=" "/=" "%=" "<<=" ">>=" "&="
               "^=" "|="))
(add-to-list 'rotate-text-symbols
             '("static_cast" "dynamic_cast" "const_cast" "reinterpret_cast"))
(add-to-list 'rotate-text-symbols
             '("false" "true"))
(add-to-list 'rotate-text-symbols
             '("None" "False" "True"))


(global-set-key (kbd "M-<up>") #'rotate-text)
(global-set-key (kbd "M-<down>") #'rotate-text-backward)

(require 'multiple-cursors)

(setq mc/list-file (expand-file-name "cache/mc-lists.el" user-emacs-directory))
;; Add a cursor to each line in active region
(global-set-key (kbd "C-S-c C-S-c") 'mc/edit-lines)

;; Add a cursor based on keywords in the buffer
;; (global-set-key (kbd "C->") 'mc/mark-next-like-this)
;; (global-set-key (kbd "C-<") 'mc/mark-previous-like-this)

(global-set-key (kbd "C-<") #'mc/mark-previous-like-this)
(global-set-key (kbd "C->") #'mc/mark-next-like-this)
(global-set-key (kbd "C-c C-<") #'mc/mark-all-like-this-dwim)
(global-set-key (kbd "C-S-<mouse-1>") #'mc/add-cursor-on-click)


;; [ Add a cursor win mouse
;; another option
;; (global-unset-key (kbd "M-<down-mouse-1>"))
;; (global-set-key (kbd "M-<mouse-1>") 'mc/add-cursor-on-click)
;; ]

(require 'vlf-setup)

(setq vlf-batch-size (eval-when-compile (* 1024 1024)))

(defun find-file-check-make-large-file-read-only-hook ()
  "If a file is over a given size, make the buffer read only."
  (when (> (buffer-size) vlf-batch-size)
    (setq buffer-read-only t)
    (buffer-disable-undo)
    (fundamental-mode)
    (message "Big file: %s. Read-only, fundamental mode & undo disabled."
             (buffer-file-name))))
(add-hook 'find-file-hook 'find-file-check-make-large-file-read-only-hook)

(require 'figlet)

(setq figlet-default-font "banner"
      figlet-options
      '("-w" "90"))

(require 'guess-language)

;; (add-hook 'text-mode-hook 'guess-language-mode)

(defface guess-language-mode-line
  '((t  (:foreground "#822")))
  "Face used in search mode for titles."
  :group 'guess-language)

(setcar (cdr (assq 'guess-language-mode minor-mode-alist))
        '(:eval
          (propertize (format "%s" (or guess-language-current-language "∅"))
                      'face 'guess-language-mode-line)))

(setq guess-language-languages '(en es)
      guess-language-min-paragraph-length 35)

(defun language-text-to-speak-region (start end)
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list (point) (point-max))))
  (let ((string (buffer-substring-no-properties start end))
        (language (symbol-name (guess-language-region start end))))
    (setq language-text-to-speak-process
          (cond
           ((executable-find "espeak")
            (start-process "*espeak-process*" nil
                           "espeak" "--stdin" "-v" language))
           ((executable-find "festival")
            (make-process
             :name "*festival-process*"
             :command (list "festival" "--tts" "--language"
                            (pcase language
                              ("es" "spanish")
                              ("en" "english")))
             :coding 'latin-1))))
    (process-send-string language-text-to-speak-process (concat string "\n"))
    (process-send-eof language-text-to-speak-process)))

(defun language-text-to-speak-stop ()
  (interactive)
  (if language-text-to-speak-process
      (interrupt-process language-text-to-speak-process)))

(mapc (lambda (x)
        (global-set-key
         (kbd (concat "C-c g " (car x))) (cdr x)))
      '(("p" . language-phonemic-script-at-point)
        ("t" . language-en-es-translation-at-point)
        ("b" . language-en-es-phonemic-script-and-translation-at-point)
        ("R" . language-text-to-speak-region)
        ("S" . language-text-to-speak-stop)))

(with-eval-after-load 'minimap
  (setq minor-mode-alist (assq-delete-all 'minimap-mode minor-mode-alist))

  ;; (add-hook 'minimap-sb-mode-hook
  ;;           (lambda ()
  ;;             (setq mode-line-format nil)
  ;;             (set-window-fringes (minimap-get-window) 0 0 nil)))

  ;;(minimap-mode 1)

  ;;    ###    ########  ####
  ;;   ## ##   ##     ##  ##
  ;;  ##   ##  ##     ##  ##
  ;; ##     ## ########   ##
  ;; ######### ##         ##
  ;; ##     ## ##         ##
  ;; ##     ## ##        ####

  ;; (set-face-attribute 'minimap-font-face nil
  ;;                     :family "Iosevka Term")

  (unless (face-foreground 'minimap-current-line-face)
    (set-face-attribute 'minimap-current-line-face nil
                        :foreground "yellow"))

  (setq minimap-window-location 'right
        minimap-width-fraction 0.0 ;; always minimum width 
        minimap-minimum-width 15
        minimap-update-delay 0.3
        minimap-always-recenter nil
        minimap-recenter-type 'relative
        minimap-display-semantic-overlays nil ;; heavy old parser
        minimap-tag-only nil
        minimap-hide-scroll-bar t
        minimap-hide-fringes t
        minimap-enlarge-certain-faces nil
        minimap-sync-overlay-properties '(invisible)
        minimap-major-modes '(prog-mode text-mode))

  ;; minimap version 1.2
  ;; (defun minimap-toggle ()
  ;;   "Toggle minimap for current buffer."
  ;;   (interactive)
  ;;   (if (minimap-get-window)
  ;;       (minimap-kill)
  ;;     (minimap-create)))
  ;; (global-set-key (kbd "M-s 7 m") 'minimap-toggle)
  )
(global-set-key (kbd "M-s 7 m") 'minimap-mode)

(require 'csv-mode-autoloads)
(with-eval-after-load 'csv-mode
  (setq csv-separators '("," ";" "	" "|")
        csv-field-quotes '("\"")  ;; ("\"" "'" "`")
        csv-comment-start-default nil  ;; "#"
        csv-comment-start nil  ;; "#"
        csv-align-style 'auto
        csv-align-padding 1
        csv-header-lines 1
        csv-invisibility-default nil)

  (defun count-occurrences-in-current-line (char)
    "Count occurrences of CHAR in current line."
    (cl-count char (buffer-substring-no-properties (line-beginning-position) (line-end-position))))

  (defun csv-count-occurrences-separators-in-current-line ()
    "Return list of count occurrences of csv separators in current line."
    (mapcar #'count-occurrences-in-current-line (mapcar #'string-to-char (default-value 'csv-separators))))

  (defun csv-separators-max (&optional line)
    "Return max occurrence separator."
    (save-excursion
      (goto-char (point-min))
      (if line (forward-line (1- line)))
      (let* ((frec (csv-count-occurrences-separators-in-current-line))
             (assoc-list (cl-mapcar #'cons frec (default-value 'csv-separators))))
        (while (and (cl-every (lambda (number)
                                (= 0 number))
                              frec)
                    (= 0 (forward-line 1)))
          (setq frec (csv-count-occurrences-separators-in-current-line)
                assoc-list (cl-mapcar #'cons frec (default-value 'csv-separators))))
        (if (cl-every (lambda (number)
                        (= 0 number))
                      frec)
            nil
          (cdr (assoc (seq-max frec) assoc-list))))))

  (defun csv-detect-separator (&optional line)
    "Detect csv separator in current buffer and update csv variables."
    (interactive (list (line-number-at-pos)))
    ;; (make-local-variable 'csv-separators)
    (let ((csv-sep-max (csv-separators-max line)))
      (if (not csv-sep-max)
          (message "CSV separator not found, call `csv-detect-separator' or restart `csv-mode'")
        (csv-set-comment-start nil)
        (setq-local csv-separators (list csv-sep-max))
        (setq-local csv-separator-chars (mapcar #'string-to-char csv-separators))
        (setq-local csv--skip-regexp (concat "^\n" csv-separator-chars))
        (setq-local csv-separator-regexp (concat "[" csv-separator-chars "]"))
        (setq-local csv-font-lock-keywords (list (list csv-separator-regexp '(0 'csv-separator-face))))
        (message "CSV separator detected: %s" csv-separators))))

  ;;(add-hook 'csv-mode-hook #'csv-detect-separator)

  ;; Keys
  (define-key csv-mode-map (kbd "<tab>") 'csv-forward-field)
  (define-key csv-mode-map (kbd "<backtab>") 'csv-backward-field))

(with-eval-after-load 'markdown-mode
  (message "Importing markdown-mode+")

  (require 'markdown-mode+))

(add-to-list 'auto-mode-alist '("\\.yml\\'" . yaml-mode))
(with-eval-after-load 'yaml-mode
  (define-key yaml-mode-map "\C-m" 'newline-and-indent))

(with-eval-after-load 'rst
  (message "Importing rst config")

  (with-eval-after-load 'sphinx-doc
    (require 'sphinx-frontend-config)))

(when (locate-library "smartscan")
  (add-hook 'prog-mode-hook #'smartscan-mode)
  (with-eval-after-load 'smartscan
    (advice-add 'smartscan-symbol-goto :around #'message-silent-advice)
    (setq smartscan-symbol-selector "symbol")

    (defun smartscan-symbol-go-forward (arg)
      "Jumps forward to the next symbol at point"
      (interactive "P")
      (smartscan-symbol-goto (if arg
                                 smartscan-last-symbol-name
                               (smartscan-symbol-at-pt 'end)) 'forward))

    (defun smartscan-symbol-go-backward (arg)
      "Jumps backward to the previous symbol at point"
      (interactive "P")
      (smartscan-symbol-goto (if arg
                                 smartscan-last-symbol-name
                               (smartscan-symbol-at-pt 'beginning)) 'backward))

    (define-key smartscan-map (kbd "M-n") nil)
    (define-key smartscan-map (kbd "C-c C-n") 'smartscan-symbol-go-forward)
    (define-key smartscan-map (kbd "M-p") nil)
    (define-key smartscan-map (kbd "C-c C-p") 'smartscan-symbol-go-backward)
    (define-key smartscan-map (kbd "M-'") nil)
    (define-key smartscan-map (kbd "C-c C-r") 'smartscan-symbol-replace)))

(add-hook 'prog-mode-hook #'rainbow-delimiters-mode)
(with-eval-after-load 'rainbow-delimiters
  (with-current-buffer "*scratch*"
    (lisp-interaction-mode))
  (message "Importing rainbow-delimiters-config")
  ;; [
  ;; (require 'cl-lib)
  ;; (require 'color)
  ;; (cl-loop
  ;;  for index from 1 to rainbow-delimiters-max-face-count
  ;;  do
  ;;  (let ((face (intern (format "rainbow-delimiters-depth-%d-face" index))))
  ;;    (cl-callf color-saturate-name (face-foreground face) 30)))
  ;; <xor>
  (set-face-attribute 'rainbow-delimiters-depth-1-face nil
                      :foreground "#999999")
  (set-face-attribute 'rainbow-delimiters-depth-2-face nil
                      :foreground "#8891ff")
  (set-face-attribute 'rainbow-delimiters-depth-3-face nil
                      :foreground "#88fbff")
  (set-face-attribute 'rainbow-delimiters-depth-4-face nil
                      :foreground "#f4ff88")
  (set-face-attribute 'rainbow-delimiters-depth-5-face nil
                      :foreground "#ff88d6")
  (set-face-attribute 'rainbow-delimiters-depth-6-face nil
                      :foreground "#8cff88")
  (set-face-attribute 'rainbow-delimiters-depth-7-face nil
                      :foreground "#c088ff")
  (set-face-attribute 'rainbow-delimiters-depth-8-face nil
                      :foreground "#ffd488")
  (set-face-attribute 'rainbow-delimiters-depth-9-face nil
                      :foreground "#b388ff")
  ;; ]

  (set-face-attribute 'rainbow-delimiters-unmatched-face nil
                      :foreground 'unspecified
                      :inherit 'error
                      :strike-through t))

(when (locate-library "smartparens")
  (add-hook 'prog-mode-hook #'smartparens-mode)
  (add-hook 'prog-mode-hook #'show-smartparens-mode)
  (add-hook 'org-mode-hook #'smartparens-mode)
  (add-hook 'org-mode-hook #'show-smartparens-mode)
  (with-eval-after-load 'smartparens
    (message "Importing smartparens config")

    (setcar (cdr (assq 'smartparens-mode minor-mode-alist)) nil)

    (unless (require 'smartparens-org nil 'noerror)
      (message-color #("ERROR missing package `smartparens-org'"
                       0 5 (face error))))
    (setq ;;sp-autoinsert-pair nil
     sp-highlight-pair-overlay nil)


    (defun my-open-block-c-mode (id action context)
      "Insert a c block of code when ID ACTION CONTEXT."
      (let* ((current-pos (point))
             (next-char (char-after (1+ current-pos)))
             (pre-pre-char (char-after (- current-pos 3))))
        (when (and
               next-char pre-pre-char
               (eq action 'insert)
               (eq context 'code)
               (char-equal 10 next-char)
               (or (char-equal ?\) pre-pre-char)
                   (save-excursion
                     (beginning-of-line)
                     (looking-at "[[:space:]]*..$"))))
          (indent-according-to-mode)
          (newline)
          (newline)
          (indent-according-to-mode)
          (forward-line -1)
          (indent-according-to-mode))))
    
    (defun my-double-angle-c-mode (id action context)
      "Delete closed angles when ID ACTION CONTEXT."
      (let* ((current-pos (point))
             (next-char (char-after current-pos))
             (next-next-char (char-after (1+ current-pos)))
             (pre-char (char-before (1- current-pos)))
             (pre-pre-char (char-before (- current-pos 2))))
        (when (and
               next-char next-next-char pre-char pre-pre-char
               (eq action 'insert)
               (eq context 'code)
               (char-equal ?> next-char)
               (char-equal ?> next-next-char)
               (char-equal ?< pre-char)
               (not (char-equal ?< pre-pre-char)))
          (delete-char 2))))

    (defun my-double-angle-post (id action context)
      "Unwrap angles and insert single angle when ID ACTION CONTEXT."
      (when (and
             (eq action 'insert)
             (eq context 'code))
        (sp-unwrap-sexp)
        (insert "<")
        ;; (when (bound-and-true-p rainbow-delimiters-mode)
        ;;   (rainbow-delimiters-mode-disable)
        ;;   (rainbow-delimiters-mode-enable))
        ))

    (defun my-double-angle-p (id action context)
      "Check whether a double angle is a c++ operator when ID ACTION CONTEXT."
      (let* ((current-pos (point))
             (pre-char (char-before (1- current-pos)))
             (post-char (char-after current-pos)))
        (if (and
             (eq context 'code)
             (or (and pre-char (char-equal ?< pre-char))
                 (and post-char (char-equal ?< post-char))))
            t
          nil)))

    (defun my-pre-text-code-p (id action context)
      "Check whether precesor is text when ID ACTION CONTEXT."
      (if (eq context 'code) ;; 'comment 'string
          (let ((pos (1- (point))))
            (if (< 0 pos)
                (let ((char (char-before pos)))
                  (if char
                      (if (memq (get-char-code-property char 'general-category)
                                '(Ll Lu Lo Lt Lm Mn Mc Me Nl))
                          t
                        nil)
                    t))
              t))
        t))

    (defun my-c-include-line-p (id action context)
      "Check whether current line is an include when ID ACTION CONTEXT."
      (if (eq context 'code)
          (save-excursion
            (beginning-of-line)
            (if (looking-at "# *include")
                t
              nil))
        nil))

    (defun remove-c-<-as-paren-syntax-backward ()
      "Remove wrong colored angle."
      (interactive)
      (let ((pos (point)))
        (while (<= 0 pos)
          (when (eq (get-char-property pos 'category) 'c-<-as-paren-syntax)
            (remove-text-properties pos (1+ pos) '(category nil))
            (setq pos 0))
          (cl-decf pos))))

    (defun my-org-not-abbrev-p (id action context)
      "Check whether current line isn't an abbrev when ID ACTION CONTEXT."
      (if (eq context 'code)
          (save-excursion
            (beginning-of-line)
            (if (looking-at "[\t ]*<$")
                nil
              t))
        nil))

    (sp-pair "<" ">" :actions '(wrap insert autoskip))
    ;;(sp-local-pair 'c++-mode "<" nil :when '(sp-in-comment-p))
    (sp-local-pair 'shell-script-mode "<" nil :post-handlers '(("[d1]" "SPC")))
    (sp-local-pair 'lisp-mode "'" nil :actions nil)
    (sp-local-pair 'common-lisp-mode "'" nil :actions nil)
    (sp-local-pair 'lisp-interaction-mode "'" nil :actions nil)
    (sp-local-pair 'emacs-lisp-mode "'" nil :actions nil)
    (sp-with-modes '(org-mode)
                   (sp-local-pair "<" nil :post-handlers '(("[d1]" "<") ("[d1]" "SPC"))
                                  :when '(my-org-not-abbrev-p)))
    (sp-with-modes '(c-mode c++-mode)
                   (sp-local-pair "{" nil
                                  :post-handlers '(:add my-open-block-c-mode))
                   (sp-local-pair "/*" "*/" :post-handlers '((" | " "SPC") ("* ||\n[i]" "RET")))
                   (sp-local-pair "<" nil :post-handlers '(("[d1]" "<") ("[d1]" "SPC"))
                                  :when '(my-c-include-line-p my-pre-text-code-p)))

    (defhydra hydra-sp-change (:foreign-keys run)
      "SP"
      ("C-t"            sp-transpose-hybrid-sexp "tr")
      ("S-<left>"       sp-backward-slurp-sexp "←(")
      ("S-<right>"      sp-backward-barf-sexp "(→")
      ("C-<left>"       sp-forward-barf-sexp "←)")
      ("C-<right>"      sp-slurp-hybrid-sexp ")→")
      ("C-<backspace>"  sp-backward-unwrap-sexp "(-)←")
      ("C-<delete>"     sp-unwrap-sexp "(-)")
      ("C-s"            sp-swap-enclosing-sexp "swap")
      ("\""  (lambda () (interactive) (sp-rewrap-sexp '("\"" . "\""))))
      ("\\\""  (lambda () (interactive) (sp-rewrap-sexp '("\\\"" . "\\\""))))
      ("'"  (lambda () (interactive) (sp-rewrap-sexp '("'" . "'"))))
      ("`"  (lambda () (interactive) (sp-rewrap-sexp '("`" . "`"))))
      ("("  (lambda () (interactive) (sp-rewrap-sexp '("(" . ")"))))
      ("["  (lambda () (interactive) (sp-rewrap-sexp '("[" . "]"))))
      ("{"  (lambda () (interactive) (sp-rewrap-sexp '("{" . "}"))))
      ("<"  (lambda () (interactive) (sp-rewrap-sexp '("<" . ">"))))
      ("M-q" nil "quit"))

    (defun kill-to-end-of-sexp ()
      "Delete forward sexp region with kill."
      (interactive)
      (set-mark (point))
      (sp-end-of-sexp)
      (kill-region (point) (mark)))

    (defun kill-to-begin-of-sexp ()
      "Delete backward sexp region with kill."
      (interactive)
      (set-mark (point))
      (sp-beginning-of-sexp)
      (kill-region (point) (mark)))

    (defun toggle-sp-angle-pair ()
      "Toggle angle as pair."
      (interactive)
      (if (member "<" (mapcar (lambda (x) (plist-get x :open)) sp-local-pairs))
          (sp-local-pair major-mode "<" nil :actions nil)
        (sp-local-pair major-mode "<" ">" :actions '(wrap insert autoskip)
                       :post-handlers '(("[d1]" "<") ("[d1]" "SPC"))
                       :when '(my-c-include-line-p my-pre-text-code-p))))

    ;; (defun sp-dwim-of-previous-sexp ()
    ;;   (interactive)
    ;;   (let ((to-beg (- (point) (save-excursion (sp-beginning-of-sexp) (point))))
    ;;         (to-end (- (save-excursion (sp-end-of-sexp) (point)) (point))))
    ;;     (if (<= to-beg to-end)
    ;;         (sp-beginning-of-previous-sexp)
    ;;       (sp-end-of-previous-sexp))))

    ;; (defun sp-dwim-of-next-sexp ()
    ;;   (interactive)
    ;;   (let ((to-beg (- (point) (save-excursion (sp-beginning-of-sexp) (point))))
    ;;         (to-end (- (save-excursion (sp-end-of-sexp) (point)) (point))))
    ;;     (if (<= to-beg to-end)
    ;;         (sp-beginning-of-next-sexp)
    ;;       (sp-end-of-next-sexp))))

    (defun sp-dwim-beginning-of-sexp (&optional arg)
      "Smart beginning of sexp ARG times."
      (interactive "^P")
      (when (= (point) (progn (sp-beginning-of-sexp arg) (point)))
        (sp-beginning-of-previous-sexp arg)))

    (defun sp-dwim-end-of-sexp (&optional arg)
      "Smart end of sexp ARG times."
      (interactive "^P")
      (when (= (point) (progn (sp-end-of-sexp arg) (point)))
        (sp-end-of-next-sexp arg)))


    (defun sp-local-equal-length (str)
      (let ((pos (point))
            (len (length str))
            (it 0)
            (check))
        (while (and (< 0 len)
                    (not (set 'check
                              (string-equal
                               str
                               (buffer-substring-no-properties
                                (- pos len)
                                (min (+ pos it) (point-max)))))))
          (cl-decf len)
          (cl-incf it))
        (if check
            len
          nil)))

    (defun sp-unwrap-sexp-lc ()
      (interactive)
      (let ((ends (sort (mapcar 'cdr sp-pair-list) (lambda (x y) (> (length x) (length y)))))
            (check))
        (while (and ends
                    (not (set 'check (sp-local-equal-length (pop ends))))))
        (if check (left-char check)))
      (call-interactively 'sp-unwrap-sexp))

    (defun sp-rewrap-sexp-lc ()
      (interactive)
      (let ((ends (sort (mapcar 'cdr sp-pair-list) (lambda (x y) (> (length x) (length y)))))
            (check))
        (while (and ends
                    (not (set 'check (sp-local-equal-length (pop ends))))))
        (if check (left-char check)))
      (call-interactively 'sp-rewrap-sexp))

;;;;;;;;;;
    ;; Keys ;;
;;;;;;;;;;
    (define-key smartparens-mode-map (kbd "S-<left>") #'sp-backward-sexp)
    (define-key smartparens-mode-map (kbd "S-<right>") #'sp-forward-sexp)
    (define-key smartparens-mode-map (kbd "M-a") #'sp-backward-up-sexp)
    (define-key smartparens-mode-map (kbd "S-<down>") #'sp-down-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<left>") #'sp-dwim-beginning-of-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<right>") #'sp-dwim-end-of-sexp)
    (define-key smartparens-mode-map (kbd "M-e") #'sp-up-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<down>") #'sp-down-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<delete>") #'kill-to-end-of-sexp)
    (define-key smartparens-mode-map (kbd "M-s <delete>") #'kill-to-end-of-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<insert>") #'kill-to-begin-of-sexp)
    (define-key smartparens-mode-map (kbd "M-s <insert>") #'kill-to-begin-of-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<home>") #'sp-forward-barf-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<end>") #'sp-slurp-hybrid-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<prior>") #'sp-backward-slurp-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<next>") #'sp-backward-barf-sexp)
    (define-key smartparens-mode-map (kbd "C-)") #'sp-unwrap-sexp)
    (define-key smartparens-mode-map (kbd "C-(") #'sp-rewrap-sexp)
    (define-key smartparens-mode-map (kbd "C-\"") #'sp-swap-enclosing-sexp)
    (define-key smartparens-mode-map (kbd "C-S-<return>") #'sp-split-sexp)
    (define-key smartparens-mode-map (kbd "C-c ( m") #'hydra-sp-change/body)
    (define-key smartparens-mode-map (kbd "C-c ( <") #'remove-c-<-as-paren-syntax-backward)
    (define-key smartparens-mode-map (kbd "M-s 7 <") #'toggle-sp-angle-pair)

    ;; (define-key smartparens-mode-map (kbd "C-M-b") 'sp-backward-sexp)
    ;; (define-key smartparens-mode-map (kbd "C-M-f") 'sp-forward-sexp)

    (global-set-key (kbd "M-s 7 (") #'smartparens-mode)))

(with-eval-after-load 'polymode
  (message "Importing polymode config")

  (setcar (cdr (assq 'polymode-minor-mode minor-mode-alist)) "◱")

  (with-eval-after-load 'poly-org
    (setcar (cdr (assq 'poly-org-mode minor-mode-alist)) "◱"))

  (defun polymode-disable-semantic-modes ()
    (semantic-mode -1)
    (semantic-idle-scheduler-mode -1))
  (add-hook 'polymode-minor-mode-hook 'polymode-disable-semantic-modes)

  (define-key polymode-minor-mode-map (kbd "C-'")
    (lookup-key polymode-minor-mode-map "\M-n"))
  (define-key polymode-minor-mode-map "\M-n" nil))

(with-eval-after-load 'magit
  (require 'multi-magit-autoloads)

  (with-eval-after-load 'magit-mode
    ;; Refresh mode line branch
    (defun vc-refresh-buffers ()
      (interactive)
      (dolist (buffer (buffers-from-file))
        (with-current-buffer buffer
          (setq mode-line-cached nil)
          (vc-refresh-state))))
    (advice-add 'magit-refresh :after 'vc-refresh-buffers)
    (require 'magit-todos)
    (add-hook 'magit-mode-hook 'magit-todos-mode)
    (require 'multi-magit)
    (setq multi-magit-repolist-columns '(("Name" 25 multi-magit-repolist-column-repo nil)
                                         ("Dirty" 5 multi-magit-repolist-column-status
                                          ((:right-align t)
                                           (:help-echo "N - untracked, U - unstaged, S - staged")))
                                         ("Branch" 25 magit-repolist-column-branch nil)
                                         ("Version" 25 magit-repolist-column-version nil)
                                         ("#B~" 3 magit-repolist-column-stashes
                                          ((:right-align t)
                                           (:help-echo "Number of stashes")))
                                         ("B<U" 3 magit-repolist-column-unpulled-from-upstream
                                          ((:right-align t)
                                           (:help-echo "Upstream changes not in branch")))
                                         ("B>U" 3 magit-repolist-column-unpushed-to-upstream
                                          ((:right-align t)
                                           (:help-echo "Local changes not in upstream")))
                                         ("B<R" 3 magit-repolist-column-unpulled-from-pushremote
                                          ((:right-align t)
                                           (:help-echo "Push branch changes not in current branch")))
                                         ("B>R" 3 magit-repolist-column-unpushed-to-pushremote
                                          ((:right-align t)
                                           (:help-echo "Current branch changes not in push branch")))
                                         ("Path" 99 magit-repolist-column-path nil))))

  ;; (with-eval-after-load 'magit-status
  ;;   (define-key magit-status-mode-map (kbd "M-g c") #'avy-goto-char)
  ;;   (define-key magit-status-mode-map (kbd "M-g C") #'avy-goto-char-2)
  ;;   (define-key magit-status-mode-map (kbd "M-g s") #'avy-goto-char-timer)
  ;;   (define-key magit-status-mode-map (kbd "M-g l") #'avy-goto-line)
  ;;   (define-key magit-status-mode-map (kbd "M-g w") #'avy-goto-word-1)
  ;;   (define-key magit-status-mode-map (kbd "M-g W") #'avy-goto-word-0)
  ;;   (define-key magit-status-mode-map (kbd "M-z")   #'avy-goto-char-timer)
  ;;   (define-key magit-status-mode-map (kbd "M-g k") #'link-hint-open-link)
  ;;   (define-key magit-status-mode-map (kbd "M-g K") #'link-hint-copy-link))
  ;; (with-eval-after-load 'magit-process
  ;;   (define-key magit-process-mode-map (kbd "M-g c") #'avy-goto-char)
  ;;   (define-key magit-process-mode-map (kbd "M-g C") #'avy-goto-char-2)
  ;;   (define-key magit-process-mode-map (kbd "M-g s") #'avy-goto-char-timer)
  ;;   (define-key magit-process-mode-map (kbd "M-g l") #'avy-goto-line)
  ;;   (define-key magit-process-mode-map (kbd "M-g w") #'avy-goto-word-1)
  ;;   (define-key magit-process-mode-map (kbd "M-g W") #'avy-goto-word-0)
  ;;   (define-key magit-process-mode-map (kbd "M-z")   #'avy-goto-char-timer)
  ;;   (define-key magit-process-mode-map (kbd "M-g k") #'link-hint-open-link)
  ;;   (define-key magit-process-mode-map (kbd "M-g K") #'link-hint-copy-link))
  )

(with-eval-after-load 'magit-repos
  (setq magit-repolist-columns '(("Name" 25 magit-repolist-column-ident nil)
                                 ("Branch" 25 magit-repolist-column-branch nil)
                                 ("Version" 25 magit-repolist-column-version nil)
                                 ("#B~" 3 magit-repolist-column-stashes
                                  ((:right-align t)
                                   (:help-echo "Number of stashes")))
                                 ("B<U" 3 magit-repolist-column-unpulled-from-upstream
                                  ((:right-align t)
                                   (:help-echo "Upstream changes not in branch")))
                                 ("B>U" 3 magit-repolist-column-unpushed-to-upstream
                                  ((:right-align t)
                                   (:help-echo "Local changes not in upstream")))
                                 ("B<R" 3 magit-repolist-column-unpulled-from-pushremote
                                  ((:right-align t)
                                   (:help-echo "Push branch changes not in current branch")))
                                 ("B>R" 3 magit-repolist-column-unpushed-to-pushremote
                                  ((:right-align t)
                                   (:help-echo "Current branch changes not in push branch")))
                                 ("Path" 99 magit-repolist-column-path nil))))

(with-eval-after-load 'magit-section
  (face-spec-set 'magit-section-highlight '((((type tty)) :background "grey20"))))

(with-eval-after-load 'magit-popup
  (message "Importing magit-popup config")

  (face-spec-set 'magit-popup-argument
                 '((t (:foreground "forest green" :weight bold))))
  ;; (face-spec-set 'magit-popup-disabled-argument
  ;;                '((t (:foreground "slate gray" :weight light))))
  (define-key magit-popup-mode-map "\M-q" 'magit-popup-quit))

(dolist (el-file '(docker docker-container))
  (with-eval-after-load el-file
    (message "Importing docker-config")
    (eval-when-compile
      (require 'docker-utils))

    (docker-utils-transient-define-prefix
     docker-container-logs ()
     "Transient for showing containers logs."
     :man-page "docker-container-logs"
     :value '("--tail 150" "-f" "--timestamps")
     ["Arguments"
      ("-f" "Follow" "-f")
      ("-s" "Since" "--since " read-string)
      ("-t" "Tail" "--tail " read-string)
      ("-u" "Until" "--until " read-string)
      ("-T" "Timestamps" "--timestamps")]
     [:description docker-utils-generic-actions-heading
                   ("L" "Logs" docker-utils-generic-action-async)])

    ;; (setq docker-container-logs-arguments '("-f" "-t" "--tail=150")
    ;;       docker-container-logs-popup
    ;;       (list :variable 'docker-container-logs-arguments
    ;;             :man-page "docker-logs"
    ;;             :switches '((?f "Follow" "-f") (?t "Timestamps" "-t"))
    ;;             :options  '((?T "Tail" "--tail="))
    ;;             :actions  '((?L "Logs" docker-container-logs-selection))
    ;;             :default-arguments '("-f" "-t" "--tail=150")
    ;;             :setup-function #'docker-utils-setup-popup))
    ;; (magit-define-popup docker-container-logs-popup
    ;;   "Popup for showing containers logs."
    ;;   'docker-container
    ;;   :man-page "docker-logs"
    ;;   :switches '((?f "Follow" "-f") (?t "Timestamps" "-t"))
    ;;   :options  '((?T "Tail" "--tail="))
    ;;   :actions  '((?L "Logs" docker-container-logs-selection))
    ;;   :default-arguments '("-f" "-t" "--tail=150")
    ;;   :setup-function #'docker-utils-setup-popup)

;;;;;;;;;;
;; Keys ;;
;;;;;;;;;;
    ;; (dolist (map-symbol '(docker-container-mode-map
    ;;                       docker-image-mode-map
    ;;                       docker-machine-mode-map
    ;;                       docker-network-mode-map
    ;;                       docker-volume-mode-map))
    ;;   (let ((map (eval map-symbol)))
    ;;     ;; (with-eval-after-load (intern (replace-regexp-in-string "-mode-map" "" (symbol-name map-symbol) t 'literal))
    ;;     (modal-add-first-parent map)
    ;;     ;; )
    ;;     ))
    ))

(with-eval-after-load 'transient
  (message "Importing transient-config")

  (face-spec-set 'transient-argument
                 '((t (:foreground "forest green" :weight bold))))
  (face-spec-set 'transient-value
                 '((t (:inherit font-lock-string-face :weight bold)))))

(when (locate-library "origami")
  (add-hook 'emacs-lisp-mode-hook #'origami-mode)
  (with-eval-after-load 'origami
    (message "Importing origami-config")

    (set-face-attribute 'origami-fold-replacement-face nil
                        :inherit 'unspecified
                        :underline 'unspecified
                        :weight 'bold
                        :foreground "yellow1"
                        :background "DimGray")

    (setq origami-fold-replacement "···")


    (define-key origami-mode-map (kbd "<C-tab>") 'origami-recursively-toggle-node)
    (define-key origami-mode-map (kbd "C-c <tab> n") 'origami-forward-fold-same-level)
    (define-key origami-mode-map (kbd "C-c <tab> N") 'origami-forward-toggle-node)
    (define-key origami-mode-map (kbd "C-c <tab> p") 'origami-backward-fold-same-level)
    (define-key origami-mode-map (kbd "C-c <tab> a") 'origami-close-all-nodes)
    (define-key origami-mode-map (kbd "C-c <tab> A") 'origami-open-all-nodes)
    (define-key origami-mode-map (kbd "C-c <tab> s") 'origami-show-only-node)))

;; cmake-mode
(setq auto-mode-alist
      (nconc '(;;("CMakeLists\\.txt\\'" . cmake-mode) ; por defecto
               ;;("\\.cmake\\'" . cmake-mode) ; por defecto
               ("[Mm]akefile\\." . makefile-mode))
             auto-mode-alist))
;; cmake highlight
(autoload 'cmake-font-lock-activate "cmake-font-lock" nil t)
(add-hook 'cmake-mode-hook #'cmake-font-lock-activate)

(with-eval-after-load 'flycheck
  (message "Importing flycheck-config")
;;;;;;;;;;;
;; Julia ;;
;;;;;;;;;;;
  (with-eval-after-load 'julia-mode
    (require 'flycheck-julia)
    (flycheck-julia-setup))
;;;;;;;;;;;;;;
;; Flycheck ;;
;;;;;;;;;;;;;;
  ;; Enable flycheck globaly
  ;;(add-hook 'after-init-hook #'global-flycheck-mode)
  ;; Enable flycheck localy
  ;;(add-hook 'prog-mode-hook 'flycheck-mode)
  (add-hook 'c++-mode-hook
            (lambda ()
              (setq flycheck-gcc-language-standard "c++11"
                    flycheck-clang-language-standard "c++11")))

  (setq flycheck-idle-change-delay 2.0
        ;; flycheck-check-syntax-automatically '(save mode-enabled)
        ;; sudo apt install php-codesniffer
        flycheck-phpcs-standard "PSR2")

  ;; (require 'semantic)
  ;; (setq flycheck-clang-system-path (list))
  ;; (require 'semantic/bovine/gcc)
  ;; (let ((dirs (semantic-gcc-get-include-paths "c++")))
  ;;     (dolist (dir dirs)
  ;;       (add-to-list 'flycheck-clang-system-path dir)))

  ;; ;; Disable clang check, gcc check works better
  ;; (setq-default flycheck-disabled-checkers
  ;;               (append flycheck-disabled-checkers
  ;;                       '(c/c++-clang)))
  (with-eval-after-load 'c-c++-config
    (dolist (path c-c++-include-paths)
      (add-to-list 'flycheck-gcc-include-path path)
      (add-to-list 'flycheck-clang-include-path path)))

  ;; hide 'In included' messages
  (defconst flycheck-fold-include-levels-include
    (symbol-function 'flycheck-fold-include-levels))

  (defun flycheck-fold-include-levels-exclude (errors sentinel-message)
    "Exclude ERRORS with SENTINEL-MESSAGE from included files."
    (unless (or (stringp sentinel-message) (functionp sentinel-message))
      (error "Sentinel must be string or function: %S" sentinel-message))
    (let ((sentinel (if (functionp sentinel-message)
                        sentinel-message
                      (lambda (err)
                        (string-match-p sentinel-message
                                        (flycheck-error-message err))))))
      (setq errors (cl-remove-if sentinel errors)))
    errors)
  (defconst flycheck-fold-include-levels-exclude
    (symbol-function 'flycheck-fold-include-levels-exclude))

  (defun flycheck-toggle-includes ()
    "Toggle errors in included files."
    (interactive)
    (if (eq (symbol-function 'flycheck-fold-include-levels)
            (indirect-function flycheck-fold-include-levels-include))
        (fset 'flycheck-fold-include-levels flycheck-fold-include-levels-exclude)
      (fset 'flycheck-fold-include-levels flycheck-fold-include-levels-include))
    (flycheck-buffer))

  ;; warning options
  (defun flycheck-toggle-warnings ()
    "Toggle warnings."
    (interactive)
    (if (member "extra" flycheck-clang-warnings)
        (delete "extra" flycheck-clang-warnings)
      (add-to-list 'flycheck-clang-warnings "extra"))
    (if (member "extra" flycheck-gcc-warnings)
        (delete "extra" flycheck-gcc-warnings)
      (add-to-list 'flycheck-gcc-warnings "extra"))
    (flycheck-buffer))

  (when (member "extra" flycheck-clang-warnings)
    (delete "extra" flycheck-clang-warnings))
  (when (member "extra" flycheck-gcc-warnings)
    (delete "extra" flycheck-gcc-warnings))

  ;; Mode-line
  (when (bug-check-function-bytecode
         'flycheck-mode-line-status-text
         "iYYFAAiJw7eCTgDEgk8AxYJPAMaCTwDHgk8AyAkhyQGeQcoCnkEBhC4AiYM+AMvMA4Y1AM0DhjoAzSOCPwDEtoKyAYJPAM6CTwDPgk8A0LIB0QoCUYc=")
    (defun flycheck-mode-line-status-text (&optional status)
      "Get a text describing STATUS for use in the mode line.

STATUS defaults to `flycheck-last-status-change' if omitted or
nil."
      (pcase (or status flycheck-last-status-change)
        ('not-checked '(:propertize "{}" face mode-line-inactive))
        ('no-checker '(:propertize "{∅}" face mode-line-notready))
        ('running '(:propertize "{↻}" face mode-line-correct))
        ('errored '(:propertize "{✘}" face mode-line-error))
        ('finished `((:propertize "{")
                     ,@(let-alist (flycheck-count-errors flycheck-current-errors)
                         (let (accumulate)
                           (if .warning (push `(:propertize ,
                                                (format "⚠%d" .warning)
                                                face flycheck-error-list-warning)
                                              accumulate))
                           (if .error (push `(:propertize
                                              ,(format "🚫%d" .error)
                                              face flycheck-error-list-error)
                                            accumulate))
                           (or accumulate '((:propertize
                                             "✓"
                                             face flycheck-error-list-info)))))
                     (:propertize "}")))
        ('interrupted '(:propertize "{.}" face mode-line-error))
        ('suspicious '(:propertize "{?}" face mode-line-warning)))))

;;;;;;;;;;;;;;
;; Posframe ;;
;;;;;;;;;;;;;;
  (when (and (display-graphic-p) (load "flycheck-posframe" t))
    (add-hook 'flycheck-mode-hook #'flycheck-posframe-mode))

  ;; Keys
  (define-key flycheck-mode-map (kbd "C-c ! t w") 'flycheck-toggle-warnings)
  (define-key flycheck-mode-map (kbd "C-c ! t i") 'flycheck-toggle-includes)
  (define-key flycheck-mode-map (kbd "M-g n") #'flycheck-next-error)
  (define-key flycheck-mode-map (kbd "M-g M-n") #'flycheck-next-error)
  (define-key flycheck-mode-map (kbd "M-g p") #'flycheck-previous-error)
  (define-key flycheck-mode-map (kbd "M-g M-p") #'flycheck-previous-error))

(with-eval-after-load 'lua-mode
  (message "Importing lua-config")
  (setq lua-indent-level 4))

(with-eval-after-load 'virtualenvwrapper
  (message "Importing virtualenvwrapper config")

  (venv-initialize-interactive-shells) ;; if you want interactive shell support
  (venv-initialize-eshell) ;; if you want eshell support
  ;; note that setting `venv-location` is not necessary if you
  ;; use the default location (`~/.virtualenvs`), or if the
  ;; the environment variable `WORKON_HOME` points to the right place
  (setq venv-location "~/.virtualenvs"))

(add-to-list 'auto-mode-alist '("\\.phtml\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.tpl\\.php\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.[agj]sp\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.as[cp]x\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.erb\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.mustache\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.djhtml\\'" . web-mode))
(add-to-list 'auto-mode-alist '("\\.html?\\'" . web-mode))

(add-to-list 'auto-mode-alist '("\\.tpl\\'" . web-mode))
(with-eval-after-load 'web-mode
  (message "Importing web-config")

  (setq web-mode-enable-auto-indentation nil))

;; Enable plantuml-mode for PlantUML files
;; (add-to-list 'auto-mode-alist '("\\.plantuml\\'" . plantuml-mode))
(with-eval-after-load 'plantuml-mode
  (message "Importing plantuml-mode")

  (setq plantuml-default-exec-mode 'jar
        plantuml-jar-path (expand-file-name 
                           "~/.emacs.d/cache/java/plantuml.jar")))

(with-eval-after-load 'edit-server
  (message "Importing edit-server-config")

  (setcar (cdr (assq 'edit-server-edit-mode minor-mode-alist)) "Es")

  (setq edit-server-url-major-mode-alist
        '(("github\\.com" . markdown-mode)
          ("gitlab\\."    . markdown-mode))))

(with-eval-after-load 'emms
  (message "Importing emms-config")

  (require 'emms-setup)
  (emms-all)
  (emms-default-players)

  (global-set-key (kbd "C-c e P") 'emms-pause)
  (global-set-key (kbd "C-c e s") 'emms-stop)
  (global-set-key (kbd "C-c e p") 'emms-previous)
  (global-set-key (kbd "C-c e n") 'emms-next)

  (global-set-key (kbd "<XF86AudioPlay>") 'emms-pause)
  (global-set-key (kbd "<XF86AudioStop>") 'emms-stop)
  (global-set-key (kbd "<XF86AudioPrev>") 'emms-previous)
  (global-set-key (kbd "<XF86AudioNext>") 'emms-next))

(global-set-key (kbd "C-x w") 'elfeed)
(with-eval-after-load 'elfeed
  (message "Importing elfeed-config")

  (defface elfeed-search-science-title-face
    '((((class color) (background light)) (:foreground "#fd0"))  ;; gold
      (((class color) (background dark))  (:foreground "#fd0")))
    "Face used in search mode for titles."
    :group 'elfeed)

  (defface elfeed-search-arxiv-title-face
    '((((class color) (background light)) (:foreground "#ad3" :underline t))  ;; yellow green
      (((class color) (background dark))  (:foreground "#ad3" :underline t)))
    "Face used in search mode for titles."
    :group 'elfeed)

  (defface elfeed-search-health-title-face
    '((((class color) (background light)) (:foreground "#fcd"))  ;; pink
      (((class color) (background dark))  (:foreground "#fcd")))
    "Face used in search mode for titles."
    :group 'elfeed)

  (defface elfeed-search-audio-title-face
    '((t  (:background "#3d3")))  ;; lime green
    "Face used in search mode for titles."
    :group 'elfeed)

  (defface elfeed-search-image-title-face
    '((t  (:background "#ad3")))  ;; yellow green
    "Face used in search mode for titles."
    :group 'elfeed)

  (defface elfeed-search-video-title-face
    '((t  (:background "#a33")))  ;; brown
    "Face used in search mode for titles."
    :group 'elfeed)

  (push '(aud elfeed-search-audio-title-face) elfeed-search-face-alist)
  (push '(img elfeed-search-image-title-face) elfeed-search-face-alist)
  (push '(vid elfeed-search-video-title-face) elfeed-search-face-alist)
  (push '(science elfeed-search-science-title-face) elfeed-search-face-alist)
  (push '(arxiv elfeed-search-arxiv-title-face) elfeed-search-face-alist)
  (push '(health elfeed-search-health-title-face) elfeed-search-face-alist)

  (defun elfeed-youtube-expand (id)
    (format
     (pcase (substring id 0 2)
       ("UC" "https://www.youtube.com/feeds/videos.xml?channel_id=%s")
       ("PL" "https://www.youtube.com/feeds/videos.xml?playlist_id=%s")
       (_    "https://www.youtube.com/feeds/videos.xml?user=%s"))
     id))

  (setq elfeed-feeds
        `(("https://e00-expansion.uecdn.es/rss/portada.xml" expansion es txt)
          ("http://estaticos.elmundo.es/elmundo/rss/espana.xml" elmundo spain es txt)
          ("http://estaticos.elmundo.es/elmundo/rss/internacional.xml" elmundo world es txt)
          ("http://www.abc.es/rss/feeds/abc_EspanaEspana.xml" abc spain es txt)
          ("http://www.abc.es/rss/feeds/abc_Internacional.xml" abc world es txt)
          ("https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada" elpais spain es txt)
          ("https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/section/internacional/portada" elpais world es txt)
          ;; english
          ("http://feeds.bbci.co.uk/news/rss.xml?edition=int" bbc world en txt)
          ("https://www.theguardian.com/international/rss" theguardian world en txt)
          ("https://rss.nytimes.com/services/xml/rss/nyt/World.xml" nytimes world en txt)
          ;; science
          ("http://rss.sciam.com/ScientificAmerican-Global" SA science en txt)
          ("https://www.sciencenews.org/feed" sciencenews science en txt)
          ;; arxiv papers
          ,@(mapcar (lambda (category)
                      (list (concat "http://arxiv.org/rss/" (symbol-name category))
                            'arxiv category 'en 'txt))
                    '(astro-ph cond-mat cs econ eess gr-qc hep-ex hep-lat
                               hep-ph hep-th math math-ph nlin nucl-ex nucl-th
                               physics q-bio q-fin quant-ph stat))
          ;; health
          ("https://www.who.int/rss-feeds/news-english.xml" oms health es txt)
          ;; podcast
          ("https://podcasts.files.bbci.co.uk/p02pc9ny.rss" bbc en aud)
          ("https://www.theguardian.com/news/series/todayinfocus/podcast.xml" theguardian en aud)
          ;; images
          ("https://xkcd.com/atom.xml" xkcd en img)
          ;; video
          (,(elfeed-youtube-expand "UCHnyfMqiRRG1u-2MsSQLbXA") veritasium science en vid)
          (,(elfeed-youtube-expand "UCW3iqZr2cQFYKdO9Kpa97Yw") utbh es vid))
        elfeed-db-directory (expand-file-name "elfeed" user-emacs-directory)
        elfeed-search-filter "@1-month-ago +unread"
        elfeed-search-date-format '("%Y-%m-%d %H:%M" 16 :left)
        elfeed-search-trailing-width 30
        elfeed-search-title-min-width 20
        elfeed-search-title-max-width 100)

  (setq elfeed-search--tags
        (let ((tags #s(hash-table size 30 test eq data (unread t))))
          (dolist (item elfeed-feeds)
            (if (listp item)
                (mapc (lambda (tag) (puthash tag t tags))
                      (cdr item))))
          (mapcar 'symbol-name
                  (hash-table-keys tags))))

  (defun elfeed-search-filter-tags-selection (arg)
    (interactive "P")
    (let ((tag (completing-read "Select tag: " elfeed-search--tags nil t)))
      (elfeed-search-set-filter
       (if (string-match (concat "\\( ?\\)\\([-+]\\)" tag) elfeed-search-filter)
           (replace-match (if arg
                              (concat
                               (match-string 1 elfeed-search-filter)
                               (if (string-equal "+" (match-string
                                                      2 elfeed-search-filter))
                                   "-"
                                 "+")
                               tag)
                            "")
                          t t elfeed-search-filter)
         (concat elfeed-search-filter " " (if arg "-" "+") tag)))))

  (define-key elfeed-show-mode-map "h" nil)
  (define-key elfeed-show-mode-map "?" #'describe-mode)
  (define-key elfeed-show-mode-map "R" #'language-text-to-speak-region)
  (define-key elfeed-show-mode-map "S" #'language-text-to-speak-stop)

  (define-key elfeed-search-mode-map "h" nil)
  (define-key elfeed-search-mode-map "?" #'describe-mode)
  (define-key elfeed-search-mode-map "t" 'elfeed-search-filter-tags-selection)
  )

(with-eval-after-load 'ein-core
  (message "Importing ein-config")

  (setq ein:output-area-inlined-images t))

;;;;;;;;;;;;;;;;;
;; Programming ;;
;;;;;;;;;;;;;;;;;
(add-to-list 'auto-mode-alist '("\\.h\\'" . c++-mode))

;; [ cc-mode
(add-hook 'c-mode-hook   custom-lsp-startup-function)
(add-hook 'c++-mode-hook custom-lsp-startup-function)
(defun c-c++-config ()
  ;; run only once
  (remove-hook 'c-mode-hook 'c-c++-config)
  (remove-hook 'c++-mode-hook 'c-c++-config)
  (require 'c-c++-config)
  ;; After semantic
  ;; After ede-projects-config
  (require 'cmake-make-config))
(add-hook 'c-mode-hook   'c-c++-config)
(add-hook 'c++-mode-hook 'c-c++-config)
;; ]

;; [ rust
;; rustic has automatic configuration
(with-eval-after-load 'rustic
  (require 'rustic-config))
(with-eval-after-load 'rust-mode
  (add-hook 'rust-mode-hook custom-lsp-startup-function)
  (require 'rust-config))
;; ]

;; [ java
(add-hook 'java-mode-hook (lambda ()
                            (if (eq custom-lsp-startup-function 'lsp-deferred)
                                (when (require 'lsp-java nil t)
                                  (lsp-deferred))
                              (eglot-ensure))))
(defun load-once-java-stuff ()
  (with-eval-after-load 'dap-mode
    (require 'dap-java))
  (remove-hook 'java-mode-hook 'load-once-java-stuff))
(add-hook 'java-mode-hook 'load-once-java-stuff)
;; ]

;; [ javascript
(defun language-server-protocol-js-cond ()
  (unless (or (derived-mode-p 'ein:ipynb-mode)
              (derived-mode-p 'json-mode))
    (funcall custom-lsp-startup-function)))
(add-hook 'js-mode-hook #'language-server-protocol-js-cond)
(with-eval-after-load 'js
  (with-eval-after-load 'dap-mode
    (require 'dap-firefox)
    (dap-firefox-setup)))
;; ]

;; [ php
(add-hook 'php-mode-hook custom-lsp-startup-function)
(with-eval-after-load 'php-mode
  (with-eval-after-load 'dap-mode
    (require 'dap-php))
  (require 'php-config))
;; ]

;; TODO: implementar la función python-integrated-mode dentro de python-integrated.el
;(autoload 'python-integrated-mode "python-integrated" "Python everywhere" t)
;(add-to-list 'auto-mode-alist '("\\.py\\." . python-integrated-mode))
;(require 'python-integrated)

(add-to-list 'auto-mode-alist '("\\.ptx\\'" . latex-mode))
(with-eval-after-load 'latex
  (require 'latex-config))

;; [ org
(setq org-replace-disputed-keys t)
(unless (fboundp 'org-mode)
  (message "`org-mode' not found")
  (autoload 'org-mode "org"))
(with-eval-after-load 'org
  (require 'org-config)
  (require 'org-super-agenda-config)
  (require 'org-appt)
  (require 'gitlab-api)
  (require 'redmine-api))
(add-hook 'org-mode-hook #'org-super-agenda-mode)
(with-eval-after-load 'org-brain
  (require 'org-brain-config))
;; ]

;; <ahk> AutoHotKey programming
(add-to-list 'auto-mode-alist '("\\.ahk\\'" . xahk-mode))

;; ] <Not always required>

;; ---------- ;;
;; Hide modes ;;
;; ---------- ;;
;; Last config file
(require 'machine-config)

;; Usage: emacs --exwm
;; first of all in command-switch-alist
(defun argument--exwm (switch)
  "Command line arg `--exwm'.  SWITCH ignored."
  (exwm-enable))
(add-to-list 'command-switch-alist '("--exwm" . argument--exwm))

(defun argument--all (switch)
  "Command line arg `--all'.  SWITCH ignored."
  (require 'semantic)
  (require 'ede)
  (require 'cc-mode)
  (require 'latex)
  (require 'org)
  (require 'yasnippet))
(add-to-list 'command-switch-alist '("--all" . argument--all))
(defun argument--agenda (switch)
  "Command line arg `--agenda'.  SWITCH ignored."
  (require 'org))
(add-to-list 'command-switch-alist '("--agenda" . argument--agenda))
(defun argument--edit-server (switch)
  "Command line arg `--edit-server'.  SWITCH ignored."
  (require 'edit-server)
  (edit-server-start))
(add-to-list 'command-switch-alist '("--edit-server" . argument--edit-server))
;; Usage: emacs --diff file/dir1 file/dir2
(defun argument--diff (switch)
  "Command line arg `--diff'.  SWITCH ignored."
  (let ((arg1 (pop command-line-args-left))
        (arg2 (pop command-line-args-left))
        (arg3 (pop command-line-args-left)))
    (cond
     ((and
       (file-directory-p arg1)
       (file-directory-p arg2))
      (ediff-directories arg1 arg2 arg3))
     ((and
       (file-exists-p arg1)
       (file-exists-p arg2))
      (ediff-files arg1 arg2))
     (t
      (message "Files or directories required")))))
(add-to-list 'command-switch-alist '("--diff" . argument--diff))
;; Usage: emacs --debug-on-entry el-file func-name
(defun argument--debug-on-entry (switch)
  "Command line arg `--debug-on-entry'.  SWITCH ignored."
  (let ((arg1 (pop command-line-args-left))
        (arg2 (pop command-line-args-left)))
    (eval `(with-eval-after-load ,arg1
             (message "Debugging: %s::%s" ,arg1
                      (debug-on-entry (intern ,arg2)))))))
(add-to-list 'command-switch-alist '("--debug-on-entry" . argument--debug-on-entry))

(put 'list-timers 'disabled nil)

(with-eval-after-load 'gud-config
  (add-hook 'gdb-mode-hook (lambda () (gud-basic-call "set print sevenbit-strings off"))))

(with-eval-after-load 'ace-window
  (when (bug-check-function-bytecode
         'aw-update
         "xInFGBkaxsfIIAsiySIrhw==")
    (defun aw-update ()
      "Update ace-window-path window parameter for all windows.

Ensure all windows are labeled so the user can select a specific
one, even from the set of windows typically ignored when making a
window list."
      (unless prefix-arg        ;; +
        (let (;; (aw-ignore-on) ;; -
              (aw-ignore-current)
              (ignore-window-parameters t))
          (avy-traverse
           (avy-tree (aw-window-list) aw-keys)
           (lambda (path leaf)
             (set-window-parameter
              leaf 'ace-window-path
              (propertize
               (apply #'string (reverse path))
               'face 'aw-mode-line-face)))))))))

(with-eval-after-load 'comint
  (when (bug-check-function-bytecode
         'comint-term-environment
         "wsAhgxYACIMWAMPECSLFw8bHICJFh8jDyccgIkSH")

    (defun comint-term-environment ()
      (if (and (boundp 'system-uses-terminfo) system-uses-terminfo)
          (list (format "TERM=%s" comint-terminfo-terminal)
                "TERMCAP="
                (format "COLUMNS=%d" (window-width-without-margin)))
        (list "TERM=emacs"
              (format "TERMCAP=emacs:co#%d:tc=unknown:" (window-width-without-margin)))))))

(with-eval-after-load 'ellocate
  (when (bug-check-function-bytecode
         'ellocate
         "CIYFAAkZxcYKIkFAiYMgAMcLIcjJAgQGBiMhsgGCOwDFygwiiYMvAMsBIYiCOADMzSGDOADNIIiIziAphw==")
    (defun ellocate-db ()
      (let* ((config-dir (completing-read
                          "Select folder: "
                          (mapcar 'car ellocate-scan-dirs)
                          nil t))
             (dir (expand-file-name config-dir))
             (search (nth 1 (cl-find-if (lambda (list)
                                          (file-in-directory-p
                                           dir (nth 0 list)))
                                        ellocate-scan-cache))))
        (if search
            (find-file
             (ellocate-completing-read
              dir
              search
              t))
          (ellocate-cache-dir (assoc config-dir ellocate-scan-dirs))
          (find-file
           (ellocate-completing-read
            dir
            (car (cdr (assoc dir ellocate-scan-cache)))
            t)))))

    (defun ellocate (&optional ignore-scope)
      "Displays any files below the current dir.
If IGNORE-SCOPE is non-nil, search the entire database instead of just every
file under the current directory."
      (interactive "P")
      (let ((gc-cons-threshold (or ellocate-gc-mem gc-cons-threshold)))
        (if (equal ignore-scope '(16))
            (ellocate-db)
          (let ((search
                 ;; Load data from cached search corresponding to this default-directory
                 (nth 1 (cl-find-if (lambda (list)
                                      (file-in-directory-p
                                       default-directory (nth 0 list)))
                                    ellocate-scan-cache)))
                (dir (expand-file-name default-directory)))
            (if search
                (find-file
                 (ellocate-completing-read dir search ignore-scope))
              (let ((found-dir (cl-find-if
                                (lambda (list)
                                  (file-in-directory-p dir (nth 0 list)))
                                ellocate-scan-dirs)))
                (if found-dir
                    (progn
                      (ellocate-cache-dir found-dir)
                      (find-file
                       (ellocate-completing-read
                        dir
                        ;; re-search
                        (nth 1 (cl-find-if (lambda (list)
                                             (file-in-directory-p
                                              default-directory (nth 0 list)))
                                           ellocate-scan-cache))
                        ignore-scope)))
                  (if (fboundp 'counsel-file-jump)
                      (counsel-file-jump)
                    (ellocate-db)))))))))))

(with-eval-after-load 'em-cmpl
  (when (bug-check-function-bytecode
         'eshell-complete-parse-arguments
         "CIMRAAmDEQDDxCGIxcbHIojIIIrJIIhgKcdDyokKyz6DNwDMzQUGByOIAwVVgzMAyn+IyCCyBc4yRADKzwUGByKyAzCJsgKDfACJQNA+g2EAiUFAVLIEzwQGBiKyAoJ8AIlA0T2DcwDSIIjFxsciiIJ8AMPEIYjFxsciiNMFU9Qig40Aw8QhiMXGxyKIA4kGBleDqADTAdUig6EAAwFDpIiJVLIBgo4AiAJBsgMBRwNHVYS5ANbXIYgB2MoCg9wAAkA6g9EAAkBA2T2D0QABsgECQbIDAVSyAoK8AImD7QCJVAWbsgWJVAYGm7IGtgMBRwNHVYT7ANbaIYgBgyMBBIYEAWBTZnrbPYMjAQRThhIBYFNm3D2EIwEB3UOkiAJgQ6SI3t8DIgNChw==")
    (defun eshell-complete-parse-arguments ()
      "Parse the command line arguments for `pcomplete-argument'."
      (when (and eshell-no-completion-during-jobs
                 (eshell-interactive-process))
        ;; (insert-and-inherit "\t") ;; -
        (throw 'pcompleted t))
      (let ((end (point-marker))
            (begin (save-excursion (eshell-bol) (point)))
            (posns (list t))
            args delim)
        (when (memq this-command '(pcomplete-expand
                                   pcomplete-expand-and-complete))
          (run-hook-with-args 'eshell-expand-input-functions begin end)
          (if (= begin end)
              (end-of-line))
          (setq end (point-marker)))
        (if (setq delim
                  (catch 'eshell-incomplete
                    (ignore
                     (setq args (eshell-parse-arguments begin end)))))
            (cond ((memq (car delim) '(?\{ ?\<))
                   (setq begin (1+ (cadr delim))
                         args (eshell-parse-arguments begin end)))
                  ((eq (car delim) ?\()
                   (eshell-complete-lisp-symbol)
                   (throw 'pcompleted t))
                  (t
                   ;; (insert-and-inherit "\t") ;; -
                   (throw 'pcompleted t))))
        (when (get-text-property (1- end) 'comment)
          ;; (insert-and-inherit "\t") ;; -
          (throw 'pcompleted t))
        (let ((pos begin))
          (while (< pos end)
            (if (get-text-property pos 'arg-begin)
                (nconc posns (list pos)))
            (setq pos (1+ pos))))
        (setq posns (cdr posns))
        (cl-assert (= (length args) (length posns)))
        (let ((a args)
              (i 0)
              l)
          (while a
            (if (and (consp (car a))
                     (eq (caar a) 'eshell-operator))
                (setq l i))
            (setq a (cdr a) i (1+ i)))
          (and l
               (setq args (nthcdr (1+ l) args)
                     posns (nthcdr (1+ l) posns))))
        (cl-assert (= (length args) (length posns)))
        (when (and args (eq (char-syntax (char-before end)) ? )
                   (not (eq (char-before (1- end)) ?\\)))
          (nconc args (list ""))
          (nconc posns (list (point))))
        (cons (mapcar
               (function
                (lambda (arg)
                  (let ((val
                         (if (listp arg)
                             (let ((result
                                    (eshell-do-eval
                                     (list 'eshell-commands arg) t)))
                               (cl-assert (eq (car result) 'quote))
                               (cadr result))
                           arg)))
                    (if (numberp val)
                        (setq val (number-to-string val)))
                    (or val ""))))
               args)
              posns)))))

(cl-eval-when 'compile
  (require 'esh-util)) ;; eshell-condition-case
(with-eval-after-load 'esh-mode
  (when (bug-check-function-bytecode
         'eshell-send-input
         "CIUGAAE/xokZGomFFADHCCHIPT8/hVUBiYQiAGALWYMoAGRiiIIzAMkEIQtiiMoBIbYCAYRDAAyDPwCJhEMAy8whiImDawDNCyGIDIRWAA0OJVWDYgABP4VVAc4IzyKCVQHQCA0OJSOCVQELYFWDdwDR0iGCVQHT1DEMAdUxywDWC2BTIrIB19gLYFMjiNkLYFMiiYXEAM0LIYjWDQ4lUyKyAtHaIYjbMr8A09wCIYO5AN0CIYiCvgDeAgQiiDCFxADfILIBMDCCUwEwxmRiiOAgFeAgFiXgIBYmYBYn4CATigtiiG6G8ADP4dMCIrIBKYiJP4X9ANHSIYhkYrYC0dIhiOLj0yKyAYJTAcZkYojgIBXgIBYl4CAWJmAWJ+AgE4oLYohuhjABz+HTAiKyASmIiT+FPQHR0iGIZGK2AuQBIc9Q4dMCIrYC0dIhiMoCIbIBsgEqhw==")
    (defun eshell-send-input (&optional use-region queue-p no-newline)
      "Send the input received to Eshell for parsing and processing.
After `eshell-last-output-end', sends all text from that marker to
point as input.  Before that marker, calls `eshell-get-old-input' to
retrieve old input, copies it to the end of the buffer, and sends it.

If USE-REGION is non-nil, the current region (between point and mark)
will be used as input.

If QUEUE-P is non-nil, input will be queued until the next prompt,
rather than sent to the currently active process.  If no process, the
input is processed immediately.

If NO-NEWLINE is non-nil, the input is sent without an implied final
newline."
      (interactive "P")
      ;; Note that the input string does not include its terminal newline.
      (let ((proc-running-p (and (eshell-interactive-process)
                                 (not queue-p)))
            (inhibit-point-motion-hooks t)
            (inhibit-modification-hooks t))
        (unless (and proc-running-p
                     (not (eq (process-status
                               (eshell-interactive-process))
                              'run)))
          (if (or proc-running-p
                  (>= (point) eshell-last-output-end))
              (goto-char (point-max))
            (let ((copy (eshell-get-old-input use-region)))
              (goto-char eshell-last-output-end)
              (insert-and-inherit copy)))
          (unless (or no-newline
                      (and eshell-send-direct-to-subprocesses
                           proc-running-p))
            (insert-before-markers-and-inherit ?\n))
          (if proc-running-p
              (progn
                (eshell-update-markers eshell-last-output-end)
                (if (or eshell-send-direct-to-subprocesses
                        (= eshell-last-input-start eshell-last-input-end))
                    (unless no-newline
                      (process-send-string (eshell-interactive-process) "\n"))
                  (process-send-region (eshell-interactive-process)
                                       eshell-last-input-start
                                       eshell-last-input-end)
                  (run-hooks 'eshell-input-filter-functions))) ;; +
            (if (= eshell-last-output-end (point))
                (run-hooks 'eshell-post-command-hook)
              (let (input)
                (eshell-condition-case err
                    (progn
                      (setq input (buffer-substring-no-properties
                                   eshell-last-output-end (1- (point))))
                      (run-hook-with-args 'eshell-expand-input-functions
                                          eshell-last-output-end (1- (point)))
                      (let ((cmd (eshell-parse-command-input
                                  eshell-last-output-end (1- (point)))))
                        (when cmd
                          (eshell-update-markers eshell-last-output-end)
                          (setq input (buffer-substring-no-properties
                                       eshell-last-input-start
                                       (1- eshell-last-input-end)))
                          (run-hooks 'eshell-input-filter-functions)
                          (and (catch 'eshell-terminal
                                 (ignore
                                  (if (eshell-invoke-directly cmd)
                                      (eval cmd)
                                    (eshell-eval-command cmd input))))
                               (eshell-life-is-too-much)))))
                  (quit
                   (eshell-reset t)
                   (run-hooks 'eshell-post-command-hook)
                   (signal 'quit nil))
                  (error
                   (eshell-reset t)
                   (eshell-interactive-print
                    (concat (error-message-string err) "\n"))
                   (run-hooks 'eshell-post-command-hook)
                   (insert-and-inherit input)))))))))))

(with-eval-after-load 'em-term
  (when (bug-check-function-bytecode
         'eshell-exec-visual
         "xRjGAUACQSKJQMfIA0EFQSLJygIisgEhy8zNBCHMUSFwcs4CIYjPIIjQwiGICRLQwyGIiRPRAgWJxQYHJYjSAiGJg1UA0wEh1D2DVQDVAdYiiIJZANfYIYiI2SCIDINlANrbIYgqtgXFhw==")
    ;; thanks to: https://gist.github.com/ralt/a36288cd748ce185b26237e6b85b27bb
    (defun eshell-exec-visual (&rest args)
      "Run the specified PROGRAM in a terminal emulation buffer.
 ARGS are passed to the program.  At the moment, no piping of input is
 allowed."
      (let* (eshell-interpreter-alist
             (original-args args)
             (interp (eshell-find-interpreter (car args) (cdr args)))
             (in-ssh-tramp (and (tramp-tramp-file-p default-directory)
                                (equal (tramp-file-name-method
                                        (tramp-dissect-file-name default-directory))
                                       "ssh")))
             (program (if in-ssh-tramp
                          "ssh"
                        (car interp)))
             (args (if in-ssh-tramp
                       (let ((dir-name (tramp-dissect-file-name default-directory)))
                         (eshell-flatten-list
                          (list
                           "-t"
                           (tramp-file-name-host dir-name)
                           (format
                            "export TERM=xterm-256color; cd %s; exec %s"
                            (tramp-file-name-localname dir-name)
                            (string-join
                             (append
                              (list (tramp-file-name-localname (tramp-dissect-file-name (car interp))))
                              (cdr args))
                             " ")))))
                     (eshell-flatten-list
                      (eshell-stringify-list (append (cdr interp)
                                                     (cdr args))))))
             (term-buf
              (generate-new-buffer
               (concat "*"
                       (if in-ssh-tramp
                           (format "%s %s" default-directory (string-join original-args " "))
                         (file-name-nondirectory program))
                       "*")))
             (eshell-buf (current-buffer)))
        (save-current-buffer
          (switch-to-buffer term-buf)
          (term-mode)
          (set (make-local-variable 'term-term-name) eshell-term-name)
          (make-local-variable 'eshell-parent-buffer)
          (setq eshell-parent-buffer eshell-buf)
          (term-exec term-buf program program nil args)
          (let ((proc (get-buffer-process term-buf)))
            (if (and proc (eq 'run (process-status proc)))
                (set-process-sentinel proc 'eshell-term-sentinel)
              (error "Failed to invoke visual command")))
          (term-char-mode)
          (if eshell-escape-control-x
              (term-set-escape-char ?\C-x))))
      nil)))

(with-eval-after-load 'find-dired
  (when (bug-check-function-bytecode
         'find-dired
         "CBjGxwMhIbICyAIhhBQAycoDIojLzM0hIYjOcCGJg1IAzwEh0D2DMQDR0tMhIYNMANQxRADVASGI1tchiNgBITCCSACIglIAiIJSAMnZ2iAiiIh+iNsgiNwR3SCIARKJEwzeAt+Yg20A34J5AODhIeIE4uDjIeKwBuTlDUAig5EA5ufo1w1AIuDpIQ5AJIKTAA1AUrIB6gHrUHAiiOwCDUEiiO0g7gHvICKI8AHx8iOI8wEhtgL09SGI9hY19PchiPj5+gQLRUUWN/v8IYPWAPwgiILhAPT9IYgK/iBCQxY99P8hiA5BFj/cEYFDAAKBRACxA4hggUMAAoFFALEDiIFGAAFgIrYC9hHOcCGBRwABgUgAIoiBSQABgUoAIoiBSwABIWBwk7YCgUwAiRZCKYc=")
    (defun find-dired (dir args)
      "Run `find' and go into Dired mode on a buffer of the output.
The command run (after changing into DIR) is essentially

    find . \\( ARGS \\) -ls

except that the car of the variable `find-ls-option' specifies what to
use in place of \"-ls\" as the final argument."
      (interactive (list (read-directory-name "Run find in directory: " nil "" t)
                         (read-string "Run find (with args): " find-args
                                      '(find-args-history . 1))))
      (let ((dired-buffers dired-buffers))
        ;; Expand DIR ("" means default-directory), and make sure it has a
        ;; trailing slash.
        (setq dir (file-name-as-directory (expand-file-name dir)))
        ;; Check that it's really a directory.
        (or (file-directory-p dir)
            (error "find-dired needs a directory: %s" dir))
        (pop-to-buffer-same-window (get-buffer-create "*Find*"))

        ;; See if there's still a `find' running, and offer to kill
        ;; it first, if it is.
        (let ((find (get-buffer-process (current-buffer))))
          (when find
            (if (or (not (eq (process-status find) 'run))
                    (yes-or-no-p
                     (format-message "A `find' process is running; kill it? ")))
                (condition-case nil
                    (progn
                      (interrupt-process find)
                      (sit-for 1)
                      (delete-process find))
                  (error nil))
              (error "Cannot have two processes in `%s' at once" (buffer-name)))))

        (widen)
        (kill-all-local-variables)
        (setq buffer-read-only nil)
        (erase-buffer)
        (setq default-directory dir
              find-args args              ; save for next interactive call
              args (concat find-program " . ! -readable -prune -o "
                           (if (string= args "")
                               ""
                             (concat
                              (shell-quote-argument "(")
                              " " args " "
                              (shell-quote-argument ")")
                              " "))
                           (if (string-match "\\`\\(.*\\) {} \\(\\\\;\\|\\+\\)\\'"
                                             (car find-ls-option))
                               (format "%s %s %s"
                                       (match-string 1 (car find-ls-option))
                                       (shell-quote-argument "{}")
                                       find-exec-terminator)
                             (car find-ls-option))))
        ;; Start the find process.
        (shell-command (concat args "&") (current-buffer))
        ;; The next statement will bomb in classic dired (no optional arg allowed)
        (dired-mode dir (cdr find-ls-option))
        (let ((map (make-sparse-keymap)))
          (set-keymap-parent map (current-local-map))
          (define-key map "\C-c\C-k" 'kill-find)
          (use-local-map map))
        (make-local-variable 'dired-sort-inhibit)
        (setq dired-sort-inhibit t)
        (set (make-local-variable 'revert-buffer-function)
             `(lambda (ignore-auto noconfirm)
                (find-dired ,dir ,find-args)))
        ;; Set subdir-alist so that Tree Dired will work:
        (if (fboundp 'dired-simple-subdir-alist)
            ;; will work even with nested dired format (dired-nstd.el,v 1.15
            ;; and later)
            (dired-simple-subdir-alist)
          ;; else we have an ancient tree dired (or classic dired, where
          ;; this does no harm)
          (set (make-local-variable 'dired-subdir-alist)
               (list (cons default-directory (point-min-marker)))))
        (set (make-local-variable 'dired-subdir-switches) find-ls-subdir-switches)
        (setq buffer-read-only nil)
        ;; Subdir headlerline must come first because the first marker in
        ;; subdir-alist points there.
        (insert "  " dir ":\n")
        ;; Make second line a ``find'' line in analogy to the ``total'' or
        ;; ``wildcard'' line.
        (let ((point (point)))
          (insert "  " args "\n")
          (dired-insert-set-properties point (point)))
        (setq buffer-read-only t)
        (let ((proc (get-buffer-process (current-buffer))))
          (set-process-filter proc (function find-dired-filter))
          (set-process-sentinel proc (function find-dired-sentinel))
          ;; Initialize the process marker; it is used by the filter.
          (move-marker (process-mark proc) (point) (current-buffer)))
        (setq mode-line-process '(":%s"))))))

(with-eval-after-load 'ido-completing-read+
  (when (bug-check-function-bytecode
         'ido-completing-read@ido-cr+-replace
         "CMIgWYQLAAmEEADDAgIih8PEAiKH")
    (defun ido-completing-read@ido-cr+-replace (orig-fun prompt choices &optional
                                                         predicate require-match
                                                         initial-input hist def
                                                         inherit-input-method)
      "This advice allows ido-cr+ to completely replace `ido-completing-read'.

See the varaible `ido-cr+-replace-completely' for more information."
      (if (or (ido-cr+-active)
              (not ido-cr+-replace-completely))
          ;; ido-cr+ has either already activated or isn't going to
          ;; activate, so just run the function as normal
          (if def
              (let ((result (funcall orig-fun prompt choices predicate require-match
                                     initial-input hist def inherit-input-method)))
                (if (or (null result)
                        (and (seqp result)
                             (= 0 (length result))))
                    def
                  result))
           (funcall orig-fun prompt choices predicate require-match
                    initial-input hist def inherit-input-method))
        ;; Otherwise, we need to activate ido-cr+.
        (funcall #'ido-completing-read+ prompt choices predicate require-match
                 initial-input hist def inherit-input-method))))

  (when (bug-check-function-bytecode
         'ido-completing-read+
         "BgcGBwYHBgcGBwYHBgcGB68IGMYJIQQ6gyAABECCOAAEO4MpAASCOAAEhDEAx4I4AMjJygYHRCLLGgs/hUgAzAYJIYVIAAYIHMsdDINdAM3OIYNdAM7P0CEhgl4A0B5ADINyAM3OIYNyAM7P0SEhgnMA0R5BDkI/y9IxBQUEg4sADkODiwDI09QiiMwGCyGDqgHVBgshg7IABgo5g6wAyNPW1wYOIkMiiIKyAMjT2EMiiAGE3gDZBgshg94ABgo5g8sA1toGDCKCzADbyw5EhdkA3N3eBFADI7YD37ICBgiDqgEFhKoBDkXL38sDOoN+AQNAsgMCg3MBAjmDNAECBg89hGkB4DEQAc8DITCCEgGIy+ExHgHPBhAhMIIgAYjLiYUvAQGFLwHPAiHPAiE9toKCZgECO4NTAQYOOYNzAQLiBhAhy98eRuMDAwMjKbaDgmYB5OUERA5EhWMB3N3eBFADI7YDy4NzAQKyAcuJsgOCdAHfg34BA0GyBILsAAE/hYQBibaEg6oBBgo5g5cB1uYGDCKCmAHnyw5EhaUB3N3eBFADI7YD37IBDIO5AQ5AAwYMBgwjgsAB0ccGDAYMI7ILBgpH6FWD0wEMhNMByNPpIogOR4PrAQYKRw5HVoPrAcjT1uoORyJDIojrIIMiBA5IDklEywE6g/MCAUCyAdUBIYMMAsjT7ANEIogDhCoC2QEhgyoC7QFDDkSFJQLc3d4EUAMjtgPfsgQGCoPsAgYHhOwCAoTsAg5Fy9/LAzqDzQIDQLIDAoPCAgI5g4QCAgU9hLgC7jFgAs8DITCCYgKIy+8xbgLPBgYhMIJwAojLiYV/AgGFfwLPAiHPAiE9toKCtQICO4OiAgQ5g8ICAuIGBiHL3x5G4wMDAyMptoOCtQLk5QREDkSFsgLc3d4EUAMjtgPLg8ICArIBy4myA4LDAt+DzQIDQbIEgj0CAT+F0wKJtoSD7ALwAUMORIXnAtzd3gRQAyO2A9+yAwFBsgKC9gG2AvHL8gLzIkFAsgGJgyAEzwEh9D6EIATVASGDIwPI0wI5gx8D1vUEIoIgA/ZDIogDhEwD2QEhg0wDiTmDOQPW9wIigjoD+MsORIVHA9zd3gRQAyO2A9+yBAYKgxkEBgeEGQQChBkEDkXL38sDOoPvAwNAsgMCg+QDAjmDpgMCBT2E2gP5MYIDzwMhMIKEA4jL+jGQA88GBiEwgpIDiMuJhaEDAYWhA88CIc8CIT22goLXAwI7g8QDBDmD5AMC4gYGIcvfHkbjAwMDIym2g4LXA+TlBEQORIXUA9zd3gRQAyO2A8uD5AMCsgHLibIDguUD34PvAwNBsgSCXwMBP4X1A4m2hIMZBIk5gwYE1vsCIoIHBPzLDkSFFATc3d4EUAMjtgPfsgMBVLICgvcCtgIBhCwEyNP9QyKIBgiDYAQFhGAEiYNMBP7LDkSFRwTc3d4EUAMjtgOCYAT/yw5EhVoE3N3eBFADI7YDx0OyBgU8hGkEBUOyBgWDjgSBUQCBUgDWgVMAIgYHIrIGgVQAgVUABgcGDSIhsgvLsgYOSoOtBIFWAA5LgVcAIoOtBMcGC52DrQTI04FYACKIBgc6g8gEgVYADkuBWQAig8gEBgeJAUFUobYCgVoAIFTL38sbHkweTR5OgVsAjoFcAAYMBgwGDAYMBgwGDAYMBgwmCC0OT4FdAD2DAQXI04FeACKIMII/BQTLGxmJDkSFNQWJPIMgBYlA0z2DIAWJQUCyAYFfAA5QAkQORIUzBdzd3gRQAyO2grYC3A5QCCIqsgEuBoc=")
    (defun ido-completing-read+ (prompt collection &optional predicate
                                        require-match initial-input
                                        hist def inherit-input-method)
      "ido-based method for reading from the minibuffer with completion.

See `completing-read' for the meaning of the arguments.

This function is a wrapper for `ido-completing-read' designed to
be used as the value of `completing-read-function'. Importantly,
it detects edge cases that ido cannot handle and uses normal
completion for them."
      (let* (;; Save the original arguments in case we need to do the
             ;; fallback
             (ido-cr+-orig-completing-read-args
              (list prompt collection predicate require-match
                    initial-input hist def inherit-input-method))
             ;; Need to save a copy of this since activating the
             ;; minibuffer once will clear out any temporary minibuffer
             ;; hooks, which need to get restored before falling back so
             ;; that they will trigger again when the fallback function
             ;; uses the minibuffer. We make a copy in case the original
             ;; list gets modified in place.
             (orig-minibuffer-setup-hook (cl-copy-list minibuffer-setup-hook))
             ;; Need just the string part of INITIAL-INPUT
             (initial-input-string
              (cond
               ((consp initial-input)
                (car initial-input))
               ((stringp initial-input)
                initial-input)
               ((null initial-input)
                "")
               (t
                (signal 'wrong-type-argument (list 'stringp initial-input)))))
             (ido-cr+-active-restrictions nil)
             ;; If collection is a function, save it for later, unless
             ;; instructed not to
             (ido-cr+-dynamic-collection
              (when (and (not ido-cr+-assume-static-collection)
                         (functionp collection))
                collection))
             (ido-cr+-last-dynamic-update-text nil)
             ;; Only memoize if the collection is dynamic.
             (ido-cr+-all-prefix-completions-memoized
              (if (and ido-cr+-dynamic-collection (featurep 'memoize))
                  (memoize (indirect-function 'ido-cr+-all-prefix-completions))
                'ido-cr+-all-prefix-completions))
             (ido-cr+-all-completions-memoized
              (if (and ido-cr+-dynamic-collection (featurep 'memoize))
                  (memoize (indirect-function 'all-completions))
                'all-completions))
             ;; If the whitelist is empty, everything is whitelisted
             (whitelisted (not ido-cr+-function-whitelist))
             ;; If non-nil, we need alternate nil DEF handling
             (alt-nil-def nil))
        (condition-case sig
            (progn
              ;; Check a bunch of fallback conditions
              (when (and inherit-input-method current-input-method)
                (signal 'ido-cr+-fallback
                        '("ido cannot handle alternate input methods")))

              ;; Check for black/white-listed collection function
              (when (functionp collection)
                ;; Blacklist
                (when (ido-cr+-function-is-blacklisted collection)
                  (if (symbolp collection)
                      (signal 'ido-cr+-fallback
                              (list (format "collection function `%S' is blacklisted" collection)))
                    (signal 'ido-cr+-fallback
                            (list "collection function is blacklisted"))))
                ;; Whitelist
                (when (and (not whitelisted)
                           (ido-cr+-function-is-whitelisted collection))
                  (ido-cr+--debug-message
                   (if (symbolp collection)
                       (format "Collection function `%S' is whitelisted" collection)
                     "Collection function is whitelisted"))
                  (setq whitelisted t))
                ;; nil DEF list
                (when (and
                       require-match (null def)
                       (ido-cr+-function-is-in-list
                        collection
                        ido-cr+-nil-def-alternate-behavior-list))
                  (ido-cr+--debug-message
                   (if (symbolp collection)
                       (format "Using alternate nil DEF handling for collection function `%S'" collection)
                     "Using alternate nil DEF handling for collection function"))
                  (setq alt-nil-def t)))

              ;; Expand all currently-known completions.
              (setq collection
                    (if ido-cr+-dynamic-collection
                        (funcall ido-cr+-all-prefix-completions-memoized
                                 initial-input-string collection predicate)
                      (all-completions "" collection predicate)))
              ;; No point in using ido unless there's a collection
              (when (and (= (length collection) 0)
                         (not ido-cr+-dynamic-collection))
                (signal 'ido-cr+-fallback '("ido is not needed for an empty collection")))
              ;; Check for excessively large collection
              (when (and ido-cr+-max-items
                         (> (length collection) ido-cr+-max-items))
                (signal 'ido-cr+-fallback
                        (list
                         (format
                          "there are more than %i items in COLLECTION (see `ido-cr+-max-items')"
                          ido-cr+-max-items))))

              ;; If called from `completing-read', check for
              ;; black/white-listed commands/callers
              (when (ido-cr+--called-from-completing-read)
                ;; Check calling command and `ido-cr+-current-command'
                (cl-loop
                 for cmd in (list this-command ido-cr+-current-command)

                 if (ido-cr+-function-is-blacklisted cmd)
                 do (signal 'ido-cr+-fallback
                            (list "calling command `%S' is blacklisted" cmd))

                 if (and (not whitelisted)
                         (ido-cr+-function-is-whitelisted cmd))
                 do (progn
                      (ido-cr+--debug-message "Command `%S' is whitelisted" cmd)
                      (setq whitelisted t))

                 if (and
                     require-match (null def) (not alt-nil-def)
                     (ido-cr+-function-is-in-list
                      cmd ido-cr+-nil-def-alternate-behavior-list))
                 do (progn
                      (ido-cr+--debug-message
                       "Using alternate nil DEF handling for command `%S'" cmd)
                      (setq alt-nil-def t)))

                ;; Check every function in the call stack starting after
                ;; `completing-read' until to the first
                ;; `funcall-interactively' (for a call from the function
                ;; body) or `call-interactively' (for a call from the
                ;; interactive form, in which the function hasn't actually
                ;; been called yet, so `funcall-interactively' won't be on
                ;; the stack.)
                (cl-loop for i upfrom 1
                         for caller = (cadr (backtrace-frame i 'completing-read))
                         while caller
                         while (not (memq (indirect-function caller)
                                          '(internal--funcall-interactively
                                            (indirect-function 'call-interactively))))

                         if (ido-cr+-function-is-blacklisted caller)
                         do (signal 'ido-cr+-fallback
                                    (list (if (symbolp caller)
                                              (format "calling function `%S' is blacklisted" caller)
                                            "a calling function is blacklisted")))

                         if (and (not whitelisted)
                                 (ido-cr+-function-is-whitelisted caller))
                         do (progn
                              (ido-cr+--debug-message
                               (if (symbolp caller)
                                   (format "Calling function `%S' is whitelisted" caller)
                                 "A calling function is whitelisted"))
                              (setq whitelisted t))

                         if (and require-match (null def) (not alt-nil-def)
                                 (ido-cr+-function-is-in-list
                                  caller ido-cr+-nil-def-alternate-behavior-list))
                         do (progn
                              (ido-cr+--debug-message
                               (if (symbolp caller)
                                   (format "Using alternate nil DEF handling for calling function `%S'" caller)
                                 "Using alternate nil DEF handling for a calling function"))
                              (setq alt-nil-def t))))

              (unless whitelisted
                (signal 'ido-cr+-fallback
                        (list "no functions or commands matched the whitelist for this call")))

              (when (and require-match (null def))
                ;; Replace nil with "" for DEF if match is required, unless
                ;; alternate nil DEF handling is enabled
                (if alt-nil-def
                    (ido-cr+--debug-message
                     "Leaving the default at nil because alternate nil DEF handling is enabled.")
                  (ido-cr+--debug-message
                   "Adding \"\" as the default completion since no default was provided.")
                  (setq def (list ""))))

              ;; In ido, the semantics of "default" are simply "put it at
              ;; the front of the list". Furthermore, ido can't handle a
              ;; list of defaults, nor can it handle both DEF and
              ;; INITIAL-INPUT being non-nil. So, just pre-process the
              ;; collection to put the default(s) at the front and then
              ;; set DEF to nil in the call to ido to avoid these issues.
              (unless (listp def)
                ;; Ensure DEF is a list
                (setq def (list def)))
              (when def
                ;; Ensure DEF are strings
                (setq def (mapcar (apply-partially #'format "%s") def))
                ;; Prepend DEF to COLLECTION and remove duplicates
                (setq collection (delete-dups (append def collection))
                      ;; def nil))     ;; -
                      def (car def)))  ;; +

              ;; Check for a specific bug
              (when (and ido-enable-dot-prefix
                         (version< emacs-version "26.1")
                         (member "" collection))
                (signal 'ido-cr+-fallback
                        '("ido cannot handle the empty string as an option when `ido-enable-dot-prefix' is non-nil; see https://debbugs.gnu.org/cgi/bugreport.cgi?bug=26997")))

              ;; Fix ido's broken handling of cons-style INITIAL-INPUT on
              ;; Emacsen older than 27.1.
              (when (and (consp initial-input)
                         (version< emacs-version "27.1"))
                ;; `completing-read' uses 0-based index while
                ;; `read-from-minibuffer' uses 1-based index.
                (cl-incf (cdr initial-input)))

              ;; Finally ready to do actual ido completion
              (prog1
                  (let ((ido-cr+-minibuffer-depth (1+ (minibuffer-depth)))
                        (ido-cr+-dynamic-update-timer nil)
                        (ido-cr+-exhibit-pending t)
                        ;; Reset this for recursive calls to ido-cr+
                        (ido-cr+-assume-static-collection nil))
                    (unwind-protect
                        (ido-completing-read
                         prompt collection
                         predicate require-match initial-input hist def
                         inherit-input-method)
                      (when ido-cr+-dynamic-update-timer
                        (cancel-timer ido-cr+-dynamic-update-timer)
                        (setq ido-cr+-dynamic-update-timer nil))))
                ;; This detects when the user triggered fallback mode
                ;; manually.
                (when (eq ido-exit 'fallback)
                  (signal 'ido-cr+-fallback '("user manually triggered fallback")))))

          ;; Handler for ido-cr+-fallback signal
          (ido-cr+-fallback
           (let (;; Reset `minibuffer-setup-hook' to original value
                 (minibuffer-setup-hook orig-minibuffer-setup-hook)
                 ;; Reset this for recursive calls to ido-cr+
                 (ido-cr+-assume-static-collection nil))
             (ido-cr+--explain-fallback sig)
             (apply ido-cr+-fallback-function ido-cr+-orig-completing-read-args))))))))

(with-eval-after-load 'magit-log
  (require 'magit-wip))

(with-eval-after-load 'ox-odt
  (when (bug-check-function-bytecode
         'org-odt-verbatim
         "wMHCw8QGB4k7gxYAxcYDAyO2goIeAMcBQUADIraCISOH")
    (defun org-odt-verbatim (verbatim contents info)
      "Transcode a VERBATIM object from Org to ODT.
CONTENTS is nil.  INFO is a plist used as a communication
channel."
      (format "<text:span text:style-name=\"%s\">%s</text:span>"
              "OrgVerbatim" (org-odt--encode-plain-text
                             (org-element-property :value verbatim))))))

(with-eval-after-load 'posframe
  (when (bug-check-function-bytecode
         'posframe-show
         "xAHFIkFAxALGIkFAxAPHIkFAxATIIkFAxAXJIkFAxAYGyiJBQMQGB8siQUDEBgjMIkFAxAYJzSJBQMQGCs4iQUDEBgvPIkFAxAYM0CJBQMQGDdEiQUDEBg7SIkFAxAYP0yJBQMQGENQiQUDEBhHVIkFAxAYS1iJBQMQGE9ciQUDEBhTYIkFAxAYV2SJBQMQGFtoiQUDEBhfbIkFAxAYY3CJBQMQGGd0iQUDEBhreIkFAxAYb3yJBQAgGHcYGHCOGwwBgCAYexwYcIwgGH8gGHCMIBiDJBhwjCAYhygYcI4bjAOAIBiLLBhwjhu4A4AgGI8wGHCOG+QDhCAYkzQYcI4YEAeEIBiXOBhwjCAYmzwYcIwgGJ9AGHCMIBijRBhwjCAYp0gYcIwgGKtMGHCMIBivUBhwjCAYs1QYcIwgGLdYGHCMIBi7XBhwjCAYv2AYcIwgGMNkGHCMIBjHaBhwjCAYy2wYcIwgGM9wGHCMIBjTdBhwjCAY13gYcIwgGNt8GHCPiBjch4yDkASHlAiHmAyHnBCEGH6iDowHoBiAGBiKCpQEGH+kGBiHqASHrAiHsIHLtBgohcYjuBiUhKe8g5/AgIfEGDSHy8yGD0gHzIILTAeH0GfVyBhBxiAqE7QEGGfIBIYPsAYkgiPQSiPYGEdIGIfcGDs4GKc8GKtAGK9EGLNMGLNQGLdkGKtoGK9UGMtYGM9sGMN4GLyYdsgH4AfnhI4j6BgoCIoj7BkYGGiKI/AEGKQYoBiwGKyWI/QH+xgYu/wYQxwYxgUAABg+BQQAGEoFCAAYOgUMA6gYRIYFEAOsGEyGBRQAGJPcGH4FGAAYggUcABiGBSAAGK4FJAAYsgUoABi2BSwAGLoFMAAYvgU0ABiqBTgAGK4FPAAYsgVAABi3MBlLNBlOvLiEGCwYLJIiBUQABBhYiiIFSAAEGFQYqBikGLQYsJgaIgVMAgVQACyHhIoiBVQALIYjtBhAhgVYAASH4C4FXAAYWI4j4C4FYAAMFQiO2Ayq2qoc=")
    (cl-defun posframe-show (buffer-or-name
                             &key
                             string
                             position
                             poshandler
                             width
                             height
                             min-width
                             min-height
                             x-pixel-offset
                             y-pixel-offset
                             left-fringe
                             right-fringe
                             internal-border-width
                             internal-border-color
                             font
                             foreground-color
                             background-color
                             respect-header-line
                             respect-mode-line
                             initialize
                             no-properties
                             keep-ratio
                             lines-truncate
                             override-parameters
                             timeout
                             refresh
                             accept-focus
                             hidehandler
                             &allow-other-keys)
      "Pop up a posframe and show STRING at POSITION.

POSITION can be:
1. An integer, meaning point position.
2. A cons of two integers, meaning absolute X and Y coordinates.
3. Other type, in which case the corresponding POSHANDLER should be
   provided.

POSHANDLER is a function of one argument returning an actual
position.  Its argument is a plist of the following form:

  (:position xxx
   :position-info xxx
   :poshandler xxx
   :font-height xxx
   :font-width xxx
   :posframe xxx
   :posframe-width xxx
   :posframe-height xxx
   :posframe-buffer xxx
   :parent-frame xxx
   :parent-window-left xxx
   :parent-window-top xxx
   :parent-frame-width xxx
   :parent-frame-height xxx
   :parent-window xxx
   :parent-window-width  xxx
   :parent-window-height xxx
   :minibuffer-height
   :mode-line-height
   :header-line-height
   :tab-line-height
   :x-pixel-offset xxx
   :y-pixel-offset xxx)

By default, poshandler is auto-selected based on the type of POSITION,
but the selection can be overridden using the POSHANDLER argument.
The builtin poshandler functions are listed below:

1.  `posframe-poshandler-frame-center'
2.  `posframe-poshandler-frame-top-center'
3.  `posframe-poshandler-frame-top-left-corner'
4.  `posframe-poshandler-frame-top-right-corner'
5.  `posframe-poshandler-frame-bottom-center'
6.  `posframe-poshandler-frame-bottom-left-corner'
7.  `posframe-poshandler-frame-bottom-right-corner'
8.  `posframe-poshandler-window-center'
9.  `posframe-poshandler-window-top-center'
10. `posframe-poshandler-window-top-left-corner'
11. `posframe-poshandler-window-top-right-corner'
12. `posframe-poshandler-window-bottom-center'
13. `posframe-poshandler-window-bottom-left-corner'
14. `posframe-poshandler-window-bottom-right-corner'
15. `posframe-poshandler-point-top-left-corner'
16. `posframe-poshandler-point-bottom-left-corner'
17. `posframe-poshandler-point-bottom-left-corner-upward'

This posframe's buffer is BUFFER-OR-NAME, which can be a buffer
or a name of a (possibly nonexistent) buffer.

If NO-PROPERTIES is non-nil, The STRING's properties will
be removed before being shown in posframe.

WIDTH, MIN-WIDTH, HEIGHT and MIN-HEIGHT, specify bounds on the
new total size of posframe.  MIN-HEIGHT and MIN-WIDTH default to
the values of ‘window-min-height’ and ‘window-min-width’
respectively.  These arguments are specified in the canonical
character width and height of posframe.

If LEFT-FRINGE or RIGHT-FRINGE is a number, left fringe or
right fringe with be shown with the specified width.

By default, posframe shows no borders, but users can specify
borders by setting INTERNAL-BORDER-WIDTH to a positive number.
Border color can be specified by INTERNAL-BORDER-COLOR
or via the ‘internal-border’ face.

Posframe's font as well as foreground and background colors are
derived from the current frame by default, but can be overridden
using the FONT, FOREGROUND-COLOR and BACKGROUND-COLOR arguments,
respectively.

By default, posframe will display no header-line, mode-line and
tab-line.  In case a header-line, mode-line or tab-line is
desired, users can set RESPECT-HEADER-LINE and RESPECT-MODE-LINE
to t.

INITIALIZE is a function with no argument.  It will run when
posframe buffer is first selected with `with-current-buffer'
in `posframe-show', and only run once (for performance reasons).

If LINES-TRUNCATE is non-nil, then lines will truncate in the
posframe instead of wrap.

OVERRIDE-PARAMETERS is very powful, *all* the frame parameters
used by posframe's frame can be overridden by it.

TIMEOUT can specify the number of seconds after which the posframe
will auto-hide.

If REFRESH is a number, posframe's frame-size will be re-adjusted
every REFRESH seconds.

When ACCEPT-FOCUS is non-nil, posframe will accept focus.
be careful, you may face some bugs when set it to non-nil.

HIDEHANDLER is a function, when it return t, posframe will be
hide when `post-command-hook' is executed, this function has a
plist argument:

  (:posframe-buffer xxx
   :posframe-parent-buffer xxx)

The builtin hidehandler functions are listed below:

1. `posframe-hidehandler-when-buffer-switch'


You can use `posframe-delete-all' to delete all posframes."
      (let* ((position (or (funcall posframe-arghandler buffer-or-name :position position) (point)))
             (poshandler (funcall posframe-arghandler buffer-or-name :poshandler poshandler))
             (width (funcall posframe-arghandler buffer-or-name :width width))
             (height (funcall posframe-arghandler buffer-or-name :height height))
             (min-width (or (funcall posframe-arghandler buffer-or-name :min-width min-width) 1))
             (min-height (or (funcall posframe-arghandler buffer-or-name :min-height min-height) 1))
             (x-pixel-offset (or (funcall posframe-arghandler buffer-or-name :x-pixel-offset x-pixel-offset) 0))
             (y-pixel-offset (or (funcall posframe-arghandler buffer-or-name :y-pixel-offset y-pixel-offset) 0))
             (left-fringe (funcall posframe-arghandler buffer-or-name :left-fringe left-fringe))
             (right-fringe (funcall posframe-arghandler buffer-or-name :right-fringe right-fringe))
             (internal-border-width (funcall posframe-arghandler buffer-or-name :internal-border-width internal-border-width))
             (internal-border-color (funcall posframe-arghandler buffer-or-name :internal-border-color internal-border-color))
             (font (funcall posframe-arghandler buffer-or-name :font font))
             (foreground-color (funcall posframe-arghandler buffer-or-name :foreground-color foreground-color))
             (background-color (funcall posframe-arghandler buffer-or-name :background-color background-color))
             (respect-header-line (funcall posframe-arghandler buffer-or-name :respect-header-line respect-header-line))
             (respect-mode-line (funcall posframe-arghandler buffer-or-name :respect-mode-line respect-mode-line))
             (initialize (funcall posframe-arghandler buffer-or-name :initialize initialize))
             (no-properties (funcall posframe-arghandler buffer-or-name :no-properties no-properties))
             (keep-ratio (funcall posframe-arghandler buffer-or-name :keep-ratio keep-ratio))
             (lines-truncate (funcall posframe-arghandler buffer-or-name :lines-truncate lines-truncate))
             (override-parameters (funcall posframe-arghandler buffer-or-name :override-parameters override-parameters))
             (timeout (funcall posframe-arghandler buffer-or-name :timeout timeout))
             (refresh (funcall posframe-arghandler buffer-or-name :refresh refresh))
             (accept-focus (funcall posframe-arghandler buffer-or-name :accept-focus accept-focus))
             (hidehandler (funcall posframe-arghandler buffer-or-name :hidehandler hidehandler))
             ;;-----------------------------------------------------
             (buffer (get-buffer-create buffer-or-name))
             (parent-window (selected-window))
             (parent-window-top (window-pixel-top parent-window))
             (parent-window-left (window-pixel-left parent-window))
             (parent-window-width (window-pixel-width parent-window))
             (parent-window-height (window-pixel-height parent-window))
             (position-info
              (if (integerp position)
                  (posn-at-point position parent-window)
                position))
             (parent-frame (window-frame parent-window))
             (parent-frame-width (frame-pixel-width parent-frame))
             (parent-frame-height (frame-pixel-height parent-frame))
             (font-width (default-font-width))
             (font-height (with-current-buffer (window-buffer parent-window)
                            (posframe--get-font-height position)))
             (mode-line-height (window-mode-line-height))
             (minibuffer-height (window-pixel-height (minibuffer-window)))
             (header-line-height (window-header-line-height parent-window))
             (tab-line-height (if (functionp 'window-tab-line-height)
                                  (window-tab-line-height)
                                0))
             (frame-resize-pixelwise t)
             posframe)

        (with-current-buffer buffer

          ;; Initialize
          (unless posframe--initialized-p
            (let ((func initialize))
              (when (functionp func)
                (funcall func)
                (setq posframe--initialized-p t))))

          ;; Create posframe
          (setq posframe
                (posframe--create-posframe
                 buffer
                 :font font
                 :parent-frame parent-frame
                 :left-fringe left-fringe
                 :right-fringe right-fringe
                 :internal-border-width internal-border-width
                 :internal-border-color internal-border-color
                 :foreground-color foreground-color
                 :background-color background-color
                 :keep-ratio keep-ratio
                 :lines-truncate lines-truncate
                 :respect-header-line respect-header-line
                 :respect-mode-line respect-mode-line
                 :override-parameters override-parameters
                 :accept-focus accept-focus))

          ;; Remove tab-bar always.
          (set-frame-parameter posframe 'tab-bar-lines 0)

          ;; Move mouse to (0 . 0)
          (posframe--mouse-banish parent-frame posframe)

          ;; Insert string into the posframe buffer
          (posframe--insert-string string no-properties)

          ;; Set posframe's size
          (posframe--set-frame-size
           posframe height min-height width min-width)

          ;; Move posframe
          (posframe--set-frame-position
           posframe
           (posframe-run-poshandler
            ;; All poshandlers will get info from this plist.
            (list :position position
                  :position-info position-info
                  :poshandler poshandler
                  :font-height font-height
                  :font-width font-width
                  :posframe posframe
                  :posframe-width (frame-pixel-width posframe)
                  :posframe-height (frame-pixel-height posframe)
                  :posframe-buffer buffer
                  :parent-frame parent-frame
                  :parent-frame-width parent-frame-width
                  :parent-frame-height parent-frame-height
                  :parent-window parent-window
                  :parent-window-top parent-window-top
                  :parent-window-left parent-window-left
                  :parent-window-width parent-window-width
                  :parent-window-height parent-window-height
                  :mode-line-height mode-line-height
                  :minibuffer-height minibuffer-height
                  :header-line-height header-line-height
                  :tab-line-height tab-line-height
                  :x-pixel-offset x-pixel-offset
                  :y-pixel-offset y-pixel-offset))
           parent-frame-width parent-frame-height)

          ;; Delay hide posframe when timeout is a number.
          (posframe--run-timeout-timer posframe timeout)

          ;; Re-adjust posframe's size when buffer's content has changed.
          (posframe--run-refresh-timer
           posframe refresh height min-height width min-width)

          ;; Make sure not hide buffer's content for scroll down.
          (let ((window (frame-root-window posframe--frame)))
            (if (window-live-p window)
                (set-window-point window 0)))

          ;; Force raise the current posframe.
          (raise-frame posframe--frame)

          ;; Hide posframe when switch buffer
          (let* ((parent-buffer (window-buffer parent-window))
                 (parent-buffer-name (buffer-name parent-buffer)))
            (set-frame-parameter posframe--frame 'posframe-hidehandler hidehandler)
            (set-frame-parameter posframe--frame 'posframe-parent-buffer
                                 (cons parent-buffer-name parent-buffer)))

          ;; Return posframe
          posframe)))))

(with-eval-after-load 'simple
  (when (bug-check-function-bytecode
         'repeat-complex-command
         "iVMIOMUBgzQAxQPGIFQZGhvHjsjJygQhDMvABghCJSyyAczAAiKIzc4CQM/QBUEiI4JCAAiDPwDR0gQigkIA0dMhhw==")
    (defun repeat-complex-command (arg)
      "Edit and re-evaluate last complex command, or ARGth from last.
A complex command is one that used the minibuffer.
The command is placed in the minibuffer as a Lisp form for editing.
The result is executed, repeating the command as changed.
If the command has been changed or is not the most recent previous
command it is added to the front of the command history.
You can use the minibuffer history commands \
\\<minibuffer-local-map>\\[next-history-element] and \\[previous-history-element]
to get different commands to edit and resubmit."
      (interactive "p")
      (let ((elt (nth (1- arg) command-history))
            newcmd)
        (if elt
            (progn
              (setq newcmd
                    (let ((print-level nil)
                          (minibuffer-completing-symbol t)
                          (minibuffer-history-position arg)
                          (minibuffer-history-sexp-flag (1+ (minibuffer-depth))))
                      (unwind-protect
                          (minibuffer-with-setup-hook
                              (lambda ()
                                ;; FIXME: call emacs-lisp-mode (see also
                                ;; `eldoc--eval-expression-setup')?
                                (add-hook 'completion-at-point-functions
                                          #'elisp-completion-at-point nil t)
                                (run-hooks 'eval-expression-minibuffer-setup-hook))
                            (read-from-minibuffer
                             "Redo: " (prin1-to-string elt) read-expression-map t
                             (cons 'command-history arg)))

                        ;; If command was added to command-history as a
                        ;; string, get rid of that.  We want only
                        ;; evaluable expressions there.
                        (when (stringp (car command-history))
                          (pop command-history)))))

              (add-to-history 'command-history newcmd)
              (apply #'funcall-interactively
                     (car newcmd)
                     (mapcar (lambda (e) (eval e t)) (cdr newcmd))))
          (if command-history
              (error "Argument %d is beyond length of command history" arg)
            (error "There are no previous complex commands to repeat")))))))

(with-eval-after-load 'virtualenvwrapper
  (eval-when-compile
    (require 'virtualenvwrapper))
  (when (bug-check-function-bytecode
         'venv-mkvirtualenv-using
         "xiCICIMNAMfIIYIOAAkaCzuDHADJygshIYIdAAwdCoUlAMsKUB4gDiGDMQAOIYI1AMzNIUOJHiHOHiKJHiODtQAOI0AeJM/QIA4kIoNTANHSIYjT1CGI1Q4l1g4g1g0OJLAGIYgLPIOBAA0OJFCJHiYLnYN7AAuIgoAADiYLQhMpDA4nHigeKdcOJCGI2A4qIYjZjtPaIYgr29whg6YA3d4OJFAhiCkOIlQWIg4jQYkWI4RBACrX3w4hIUAhLIc=")
    (defun venv-mkvirtualenv-using (interpreter &rest names)
      "Create new virtualenvs NAMES using INTERPRETER. If venv-location
is a single directory, the new virtualenvs are made there; if it
is a list of directories, the new virtualenvs are made in the
current `default-directory'."
      (interactive '(nil))
      (venv--check-executable)
      (let* ((interpreter (if (or current-prefix-arg
                                  (null interpreter))
                              (read-string "Python executable: ")
                            interpreter))
             (parent-dir (if (stringp venv-location)
                             (file-name-as-directory
                              (expand-file-name venv-location))
                           default-directory))
             (python-exe-arg (when interpreter
                               (concat "--python=" interpreter)))
             (names (if names names
                      (list (read-from-minibuffer "New virtualenv: ")))))
        ;; map over all the envs we want to make
        (--each names
          ;; error if this env already exists
          (when (-contains? (venv-get-candidates) it)
            (error "A virtualenv with this name already exists!"))
          (run-hooks 'venv-premkvirtualenv-hook)
          (shell-command (concat venv-virtualenv-command " " python-exe-arg " " parent-dir it))
          (when (listp venv-location)
            (add-to-list 'venv-location (concat parent-dir it)))
          (venv-with-virtualenv it
                                (run-hooks 'venv-postmkvirtualenv-hook))
          (when (called-interactively-p 'interactive)
            (message (concat "Created virtualenv: " it))))
        ;; workon the last venv we made
        (venv-workon (car (last names)))))))

;; (move-to-column arg t) problems with whitespace-mode
(with-eval-after-load 'whitespace
  (defun avoid-whitespace-mode-advice (orig-fun column &optional force)
    (if (and force
             (< (current-column) column)
             (bound-and-true-p whitespace-mode))
        (prog2
            (call-interactively #'whitespace-mode)
            (funcall orig-fun column force)
          (call-interactively #'whitespace-mode))
      (funcall orig-fun column force)))

  (advice-add 'move-to-column :around #'avoid-whitespace-mode-advice))

(with-eval-after-load 'exwm-layout
  (eval-when-compile
    (require 'exwm-core))
  (when (bug-check-function-bytecode
         'exwm-layout-toggle-fullscreen
         "wzJKAAiDHADExQmDEwAJIIIUAMbHBIYaAMgkiImEKwDJyiGEKwDLw8wiiImFSQByic0BCiJBsgFxiM4gg0UAzwEhgkgA0AEhKTCH")
    (cl-defun exwm-layout-toggle-fullscreen (&optional id)
      "Toggle fullscreen mode."
      (interactive (list (exwm--buffer->id (window-buffer))))
      (exwm--log "id=#x%x" (or id 0))
      (unless (or id (derived-mode-p 'exwm-mode))
        (cl-return-from exwm-layout-toggle-fullscreen))
      (when id
        (with-current-buffer (exwm--id->buffer id)
          (if (exwm-layout--fullscreen-p)
              (progn
                (exwm-randr-refresh)
                (exwm-layout-unset-fullscreen id))
            (let ((exwm-gap-monitor 0))
              (exwm-randr-refresh))
            (exwm-layout-set-fullscreen id))))))

  (when (bug-check-function-bytecode
         'exwm-layout-unset-fullscreen
         "xjKcAAiDHADHyAmDEwAJIIIUAMnKBIYaAMskiImEJgDMzSGDKwDOIIQwAM/G0CKIcomDQACJ0QEKIkGyAYJCANIgcYjTCwwiFA2DWADUDiXVDSEiiIKAANYOJtfY2Q4l2tsOJw4oItwOKd0OKiYJIoje0N8iiYN/ANQOJQIiiIjgASGI4Q4mIYji3iDQIogOK+M9hZoA5A4lISkwhw==")
    (cl-defun exwm-layout-unset-fullscreen (&optional id)
      "Restore window from fullscreen state."
      (interactive)
      (exwm--log "id=#x%x" (or id 0))
      (unless (and (or id (derived-mode-p 'exwm-mode))
                   (exwm-layout--fullscreen-p))
        (cl-return-from exwm-layout-unset-fullscreen))
      (with-current-buffer (if id (exwm--id->buffer id) (window-buffer))
        (setq exwm--ewmh-state
              (delq xcb:Atom:_NET_WM_STATE_FULLSCREEN exwm--ewmh-state))
        (if exwm--floating-frame
            (exwm-layout--show exwm--id (frame-root-window exwm--floating-frame))
          (xcb:+request exwm--connection
              (make-instance 'xcb:ConfigureWindow
                             :window exwm--id
                             :value-mask (logior xcb:ConfigWindow:Sibling
                                                 xcb:ConfigWindow:StackMode)
                             :sibling exwm--guide-window
                             :stack-mode xcb:StackMode:Above))
          (let ((window (get-buffer-window nil t)))
            (when window
              (exwm-layout--show exwm--id window))))
        (xcb:+request exwm--connection
            (make-instance 'xcb:ewmh:set-_NET_WM_STATE
                           :window exwm--id
                           :data exwm--ewmh-state))
        (xcb:flush exwm--connection)
        (set-window-dedicated-p (get-buffer-window) nil))))

  (when (bug-check-function-bytecode
         'exwm-layout-set-fullscreen
         "xjKdAAiDHADHyAmDEwAJIIIUAMnKBIYaAMskiImEJgDMzSGDKwDOIIMwAM/G0CKIcomDQACJ0QEKIkGyAYJCANIgcYjTCyHUDNUD1iLVBNci1QXYItUGBtkiJbYC2g3b3N0M3t8OKQ4qIuDL4Q4rJgkiiA4s4gEOLSKDgwAOLYiCiQCJDi1CFi2I4wEhiOQNIYjl5iDnIojoDCEpMIc=")
    (cl-defun exwm-layout-set-fullscreen (&optional id)
      "Make window ID fullscreen."
      (interactive)
      (exwm--log "id=#x%x" (or id 0))
      (unless (and (or id (derived-mode-p 'exwm-mode))
                   (not (exwm-layout--fullscreen-p)))
        (cl-return-from exwm-layout-set-fullscreen))
      (with-current-buffer (if id (exwm--id->buffer id) (window-buffer))
        ;; Expand the X window to fill the whole screen.
        (with-slots (x y width height) (exwm-workspace--get-geometry exwm--frame)
          (exwm--set-geometry exwm--id x y width height))
        ;; Raise the X window.
        (xcb:+request exwm--connection
            (make-instance 'xcb:ConfigureWindow
                           :window exwm--id
                           :value-mask (logior xcb:ConfigWindow:BorderWidth
                                               xcb:ConfigWindow:StackMode)
                           :border-width 0
                           :stack-mode xcb:StackMode:Above))
        (cl-pushnew xcb:Atom:_NET_WM_STATE_FULLSCREEN exwm--ewmh-state)
        (xcb:+request exwm--connection
            (make-instance 'xcb:ewmh:set-_NET_WM_STATE
                           :window exwm--id
                           :data exwm--ewmh-state))
        (exwm-layout--set-ewmh-state id)
        (xcb:flush exwm--connection)
        (set-window-dedicated-p (get-buffer-window) t)))))

(with-eval-after-load 'exwm-randr
  (when (bug-check-function-bytecode
         'exwm-randr-refresh
         "CIMTAMbHCYMPAAkgghAAyMkjiAqDHADKIIIeAMsgicycAc2cAs6cz4kEhRsBA4UbAQuDNwDMEwxHzIkCV4OXAInQDQIi0QEGCSJBDAOc0gHTIgKDYQDRBAYLIkGyBIJuAAYLsgTRBgwGDCJBsgOJ1AUhQkMGCaSyCYkCQkMGCKSyCNUC1gYGI4jVAtcFI7YGiVSyAYI6ALYC2CCIDImDrgCJQNkBIYgBQbaCgp0AiNoOLCGI2yCDwQDcIIPBAN0giN4giAyJg9cAiUDfAc8iiAFBtoKCxQCI4OHiDizjDizk5eYOLSMizyNA5yIhiYMSAYlAiQSeQYmDCgHoAQYGIrIF3wIFnkHpIoiIAUG2goLtAIjaDiwhiOrrIYc=")
    (defun exwm-randr-refresh ()
      "Refresh workspaces according to the updated RandR info."
      (interactive)
      (exwm--log)
      (let* ((result (if exwm-randr--compatibility-mode
                         (exwm-randr--get-outputs)
                       (exwm-randr--get-monitors)))
             (primary-monitor (elt result 0))
             (monitor-geometry-alist (elt result 1))
             (monitor-alias-alist (elt result 2))
             container-monitor-alist container-frame-alist)
        (when (and primary-monitor monitor-geometry-alist)
          (when exwm-workspace--fullscreen-frame-count
            ;; Not all workspaces are fullscreen; reset this counter.
            (setq exwm-workspace--fullscreen-frame-count 0))
          (dotimes (i (exwm-workspace--count))
            (let* ((monitor (plist-get exwm-randr-workspace-monitor-plist i))
                   (geometry (cdr (assoc monitor monitor-geometry-alist)))
                   (frame (elt exwm-workspace--list i))
                   (container (frame-parameter frame 'exwm-container)))
              (if geometry
                  ;; Unify monitor names in case it's a mirroring setup.
                  (setq monitor (cdr (assoc monitor monitor-alias-alist)))
                ;; Missing monitors fallback to the primary one.
                (setq monitor primary-monitor
                      geometry (cdr (assoc primary-monitor
                                           monitor-geometry-alist))))
              (setq container-monitor-alist (nconc
                                             `((,container . ,(intern monitor)))
                                             container-monitor-alist)
                    container-frame-alist (nconc `((,container . ,frame))
                                                 container-frame-alist))
              (set-frame-parameter frame 'exwm-randr-monitor monitor)
              (set-frame-parameter
               frame 'exwm-geometry
               (with-slots (x y width height) geometry
                 (make-instance 'xcb:RECTANGLE
                                :x (and x (+ x exwm-gap-monitor))
                                :y (and y (+ y exwm-gap-monitor))
                                :width (and width
                                            (- width
                                               (* 2 exwm-gap-monitor)))
                                :height (and height
                                             (- height
                                                (* 2 exwm-gap-monitor))))))))
          ;; Update workareas.
          (exwm-workspace--update-workareas)
          ;; Resize workspace.
          (dolist (f exwm-workspace--list)
            (exwm-workspace--set-fullscreen f))
          (xcb:flush exwm--connection)
          ;; Raise the minibuffer if it's active.
          (when (and (active-minibuffer-window)
                     (exwm-workspace--minibuffer-own-frame-p))
            (exwm-workspace--show-minibuffer))
          ;; Set _NET_DESKTOP_GEOMETRY.
          (exwm-workspace--set-desktop-geometry)
          ;; Update active/inactive workspaces.
          (dolist (w exwm-workspace--list)
            (exwm-workspace--set-active w nil))
          ;; Mark the workspace on the top of each monitor as active.
          (dolist (xwin
                   (reverse
                    (slot-value (xcb:+request-unchecked+reply exwm--connection
                                    (make-instance 'xcb:QueryTree
                                                   :window exwm--root))
                                'children)))
            (let ((monitor (cdr (assq xwin container-monitor-alist))))
              (when monitor
                (setq container-monitor-alist
                      (rassq-delete-all monitor container-monitor-alist))
                (exwm-workspace--set-active (cdr (assq xwin container-frame-alist))
                                            t))))
          (xcb:flush exwm--connection)
          (run-hooks 'exwm-randr-refresh-hook))))))
