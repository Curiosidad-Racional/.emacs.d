;;; eshell-config.el --- Configure and improve eshell

;;; Commentary:

;; Usage:
;; (with-eval-after-load 'esh-mode
;;   (require 'eshell-config))
;; never:
;; (require 'eshell-config)

;;; Code:

;;;;;;;;;;;;
;; Colors ;;
;;;;;;;;;;;;
(add-to-list 'eshell-preoutput-filter-functions 'xterm-color-filter)
(setq eshell-output-filter-functions (remove 'eshell-handle-ansi-color eshell-output-filter-functions))
(setenv "TERM" "xterm-256color")
;;;;;;;;;;;;;;;;;
;; Emacs Shell ;;
;;;;;;;;;;;;;;;;;
(with-eval-after-load 'em-term
  (add-to-list 'eshell-visual-commands "htop")
  (add-to-list 'eshell-visual-commands "ag")
  (add-to-list 'eshell-visual-options '("git" "--help" "--paginate"))
  (add-to-list 'eshell-visual-subcommands '("git" "log" "diff" "show")))
(setq eshell-prefer-lisp-functions nil
      eshell-destroy-buffer-when-process-dies nil
      eshell-cmpl-cycle-completions nil)

;;;;;;;;
;; ag ;;
;;;;;;;;
(defun eshell/ag (&rest args)
  "Use Emacs grep facility instead of calling external grep."
  (ag/search (mapconcat #'shell-quote-argument args " ") default-directory))
;;;;;;;;;;;;;
;; Filters ;;
;;;;;;;;;;;;;
;; Make URLs clickable & ag
(add-hook 'eshell-mode-hook (lambda ()
                              (goto-address-mode 1)
                              (define-key eshell-mode-map (kbd "<up>") 'eshell-key-up)
                              (define-key eshell-mode-map (kbd "<down>") 'eshell-key-down)
                              (add-to-list 'eshell-complex-commands "ag")))
;; Colorize advices
(add-hook 'eshell-post-command-hook (lambda () (unhl-advices) (hl-advices)))

;;;;;;;;;;;;
;; Prompt ;;
;;;;;;;;;;;;
(require 'dash)
(require 's)
(require 'vc-git)


(defvar pyvenv-virtual-env-name nil)

(defmacro with-face (STR &rest PROPS)
  "Return STR propertized with PROPS."
  `(propertize ,STR 'face (list ,@PROPS)))

(defmacro esh-section (NAME ICON FORM &rest PROPS)
  "Build eshell section NAME with ICON prepended to evaled FORM with PROPS."
  `(setq ,NAME
         (lambda () (when ,FORM
                 (-> ,ICON
                    (concat esh-section-delim ,FORM)
                    (with-face ,@PROPS))))))

(defun esh-acc (acc x)
  "Accumulator for evaluating and concatenating esh-sections."
  (--if-let (funcall x)
      (if (s-blank? acc)
          it
        (concat acc esh-sep it))
    acc))

;; Below I implement a "prompt number" section
(setq esh-prompt-num 0)
(add-hook 'eshell-mode-hook (lambda ()
                              (make-local-variable 'esh-prompt-num)
                              (setq-default esh-prompt-num 0)))

(defun esh-prompt-func ()
  "Build `eshell-prompt-function'"
  (setq esh-prompt-num (incf esh-prompt-num))
  (concat esh-header
          (-reduce-from 'esh-acc "" eshell-funcs)
          "\n"
          eshell-prompt-string))

(esh-section esh-dir
             (if (display-graphic-p) "📂" "")  ;  (faicon folder)
             (let ((name (eshell/pwd)))
               (rename-buffer (format "*esh:%s*" (file-name-nondirectory name)) t)
               (abbreviate-file-name name))
             '(:foreground "gold" :bold ultra-bold :underline t))

(esh-section esh-git
             "⎇"  ;  (git icon)
             ;; (magit-get-current-branch)
             (car (vc-git-branches))
             '(:foreground "pink"))

(esh-section esh-python
             "\xe928"  ;  (python icon)
             pyvenv-virtual-env-name)

(esh-section esh-clock
             (if (display-graphic-p) "⏳" "τ")  ;  (clock icon)
             (format-time-string "%H:%M" (current-time))
             '(:foreground "forest green"))

(esh-section esh-user
             (if (display-graphic-p) "👤" "υ")
             (eshell-user-name)
             '(:foreground "blue"))

(esh-section esh-sysname
             (if (display-graphic-p) "💻" "σ")
             (system-name)
             '(:foreground "red"))

(esh-section esh-num
             "☰"  ;  (list icon)
             (number-to-string esh-prompt-num)
             '(:foreground "brown"))


(setq ;; Separator between esh-sections
      esh-sep "  "  ; or " | "

      ;; Separator between an esh-section icon and form
      esh-section-delim " "

      ;; Eshell prompt header
      esh-header "\n┌─"  ; or "\n┌─"

      ;; Eshell prompt regexp and string. Unless you are varying the prompt by eg.
      ;; your login, these can be the same.
      eshell-prompt-string "└─» "   ; or "└─> "
      eshell-prompt-regexp (concat "^" eshell-prompt-string "\\|^[a-z]*>\\{1,4\\} ")   ; or "└─> "
      ;; Choose which eshell-funcs to enable
      eshell-funcs (list esh-dir esh-git esh-python esh-clock esh-user esh-sysname esh-num)
      ;; Enable the new eshell prompt
      eshell-prompt-function 'esh-prompt-func
      eshell-banner-message (format
                             "Emacs version %s on %s. Compilation %s  %s  %s
"
                             emacs-version system-type system-configuration system-configuration-options
                             system-configuration-features))

;;;;;;;;;;;;;;;;
;; Completion ;;
;;;;;;;;;;;;;;;;
;; [ <python completion>
(when (executable-find "python")

  (defun pcmpl-python-commands ()
    (with-temp-buffer
      (call-process-shell-command "python" nil (current-buffer) nil "--help")
      (goto-char 0)
      (let (commands)
        (while (re-search-forward "^-\\([[:word:]-.]+\\)" nil t)
          (push (match-string 1) commands))
        (mapconcat 'identity commands ""))))

  (defconst pcmpl-python-commands (pcmpl-python-commands)
    "List of `python' commands.")

  (defun pcmpl-python-packages ()
    (with-temp-buffer
      (call-process-shell-command "python" nil (current-buffer) nil "-m" "pip" "freeze")
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
      (call-process-shell-command "python3" nil (current-buffer) nil "--help")
      (goto-char 0)
      (let (commands)
        (while (re-search-forward "^-\\([[:word:]-.]+\\)" nil t)
          (push (match-string 1) commands))
        (mapconcat 'identity commands ""))))

  (defconst pcmpl-python3-commands (pcmpl-python3-commands)
    "List of `python3' commands.")

  (defun pcmpl-python3-packages ()
    (with-temp-buffer
      (call-process-shell-command "python3" nil (current-buffer) nil "-m" "pip" "freeze")
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
      (call-process-shell-command "git" nil (current-buffer) nil "help" "--all")
      (goto-char 0)
      (search-forward "available git commands in")
      (let (commands)
        (while (re-search-forward
                "^[[:blank:]]+\\([[:word:]-.]+\\)[[:blank:]]*\\([[:word:]-.]+\\)?"
                nil t)
          (push (match-string 1) commands)
          (when (match-string 2)
            (push (match-string 2) commands)))
        (sort commands #'string<))))

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
      (while (pcomplete-here (pcomplete-entries)))))))
;; ] <Git Completion>
;; [ <Bzr Completion>
(when (executable-find "bzr")

  (defun pcmpl-bzr-commands ()
    "Return the most common bzr commands by parsing the bzr output."
    (with-temp-buffer
      (call-process-shell-command "bzr" nil (current-buffer) nil "help" "commands")
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
      (call-process-shell-command "hg" nil (current-buffer) nil "-v" "help")
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
(defun eshell-key-up (arg)
  (interactive "p")
  (if (eq (point)
          (point-max))
      (progn
        (if (not (memq last-command '(eshell-key-up
                                      eshell-key-down
                                      eshell-previous-matching-input-from-input
                                      eshell-next-matching-input-from-input)))
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

(defun eshell-send-input-rename ()
  (interactive)
  (call-interactively 'eshell-send-input)
  (let ((proc-running (eshell-interactive-process)))
    (when proc-running
      (rename-buffer (format "*esh:%s·%s*"
                             (file-name-nondirectory (eshell/pwd))
                             (process-name proc-running)) t))))
(require 'eshell-ido-pcomplete)
(advice-add 'eshell-cmpl-initialize :after (lambda ()
                                             (define-key eshell-mode-map [tab] 'eshell-ido-pcomplete)
                                             (define-key eshell-mode-map (kbd "<return>") 'eshell-send-input-rename)
                                             (define-key eshell-mode-map (kbd "<C-return>") 'find-file-at-point)))


(provide 'eshell-config)
;;; eshell-config.el ends here
