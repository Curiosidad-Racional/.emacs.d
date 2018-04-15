;;; machine-config.el --- Configurations machine dependent

;;; Commentary:

;; Usage:
;; (require 'machine-config)

;;; Code:

(require 'config-lib)
;;;;;;;;;;;;;;;;;;
;; Machine name ;;
;;;;;;;;;;;;;;;;;;
(cond
 ;;;;;;;;;;;;;;;;;
 ;; JOB machine ;;
 ;;;;;;;;;;;;;;;;;
 ((string-equal (system-name) (getenv "JOB_MACHINE_NAME"))
  (bound-and-eval 'config-01))
 ;;;;;;;;;;;;;;;;;;;
 ;; Almis machine ;;
 ;;;;;;;;;;;;;;;;;;;
 ((string-equal (system-name) "madntb60")
  (bound-and-eval 'config-10))
 ;;;;;;;;;;;;;;;;;;;
 ;; OOOOO machine ;;
 ;;;;;;;;;;;;;;;;;;;
 ((string-equal (system-name) "OOOOO")
  (add-to-list 'default-frame-alist '(width . 90))
  (add-to-list 'default-frame-alist '(height . 30))
  (add-to-list 'initial-frame-alist '(width . 90))
  (add-to-list 'initial-frame-alist '(height . 30)))
 ;;;;;;;;;;;;;;;;;;;
 ;; OOOO  machine ;;
 ;;;;;;;;;;;;;;;;;;;
 ((string-equal (system-name) "OOOO")
  (add-to-list 'default-frame-alist '(width . 90))
  (add-to-list 'default-frame-alist '(height . 25))
  (add-to-list 'initial-frame-alist '(width . 90))
  (add-to-list 'initial-frame-alist '(height . 25)))
 ;;;;;;;;;;;;;;;;;;;;;;;
 ;; localhost machine ;;
 ;;;;;;;;;;;;;;;;;;;;;;;
 ((string-equal (system-name) "localhost")
  ;; (setq temporary-file-directory "~/tmp/")
  (with-eval-after-load 'python-mode
    (set 'py-temp-directory temporary-file-directory))
  (toggle-hscroll-aggressive)
  (remove-hook 'c++-mode-hook 'irony-mode)
  (remove-hook 'c-mode-hook 'irony-mode)
  (remove-hook 'objc-mode-hook 'irony-mode)
  (remove-hook 'c-mode-hook 'rtags-start-process-unless-running)
  (remove-hook 'c++-mode-hook 'rtags-start-process-unless-running)
  (require 'gtags-config)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Machine operating system ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(when (eq system-type 'cygwin)
  (add-to-list 'recentf-exclude "\\\\")
  ;; coding
  (defun get-buffer-file-coding-system-local (process)
    (if (ede-current-project)
        (buffer-local-value 'buffer-file-coding-system (find-file-noselect (oref (ede-current-project) file)))
      'utf-8-dos))
  (add-to-list 'process-coding-system-alist '("ag" . get-buffer-file-coding-system-local))
  (add-to-list 'process-coding-system-alist '("grep" . get-buffer-file-coding-system-local))
  (defun helm-ag--remove-carrige-returns ()
    (save-excursion
      ;; [ solve ^M at the end of the line
      (goto-char (point-min))
      (while (re-search-forward "\xd" nil t)
        (replace-match ""))
      ;; ]
      ;; <xor>
      ;; [ solve both ^M at end and acutes
      ;; but have any problems... I don't remember
      ;; (recode-region (point-min) (point-max) 'latin-1-dos 'utf-8-unix)
      ;; ]
      ))
  ;; correct ascii characters
  (defun ascii-to-utf8-compilation-filter ()
    (ascii-to-utf8-forward compilation-filter-start))
  (add-hook 'compilation-filter-hook 'ascii-to-utf8-compilation-filter)
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; obtain linux style paths ;;
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (defun path-style-windows-to-linux (filename)
    (if (string-match "\\([A-Z]\\):\\\\" filename)
        (replace-regexp-in-string
         "\\\\" "/"
         (replace-match
          (concat "/cygdrive/"
                  (downcase (match-string 1 filename))
                  "/") nil t filename) nil t)
      (replace-regexp-in-string "\\\\" "/" filename nil t)))
  ;; shell-command
  (defun shell-command-advice (orig-fun command &rest args)
    (if (string-match "^java" command)
        (apply orig-fun (replace-regexp-in-string
                         "\\([^<>]\\) +/"
                         "\\1 /cygwin64/"
                         command) args)
      (apply orig-fun command args)))
  (advice-add 'shell-command :around #'shell-command-advice)
  (advice-add 'org-babel-eval :around #'shell-command-advice)
  ;; find-file
  ;; (defun find-file-advice (orig-fun filename &rest args)
  ;;   (set 'filename (path-style-windows-to-linux filename))
  ;;   (apply orig-fun filename args))
  ;; (require 'files)
  ;; (advice-add 'find-file-noselect :around #'find-file-advice)
  ;; expand file name
  ;; (defun expand-file-name-advice (orig-fun filename &rest args)
  ;;   (if (string-match "^\\([A-Z]\\):\\\\" filename)
  ;;       filename
  ;;     (apply orig-fun filename args)))
  ;; (advice-add 'expand-file-name :around #'expand-file-name-advice)
  ;; file exist
  ;; (defun file-exists-p-advice (orig-fun filename &rest args)
  ;;   (apply orig-fun (path-style-windows-to-linux filename) args))
  ;; (advice-add 'file-exists-p :around #'file-exists-p-advice)
  ;; compile
  (defun compilation-find-file-advice (orig-fun maker filename &rest args)
    (set 'filename (path-style-windows-to-linux filename))
    (apply orig-fun maker filename args))
  (require 'compile)
  (advice-add 'compilation-find-file :around #'compilation-find-file-advice)
  ;; ffap
  (defun ffap-string-at-point-advice (orig-fun &rest args)
    (path-style-windows-to-linux (apply orig-fun args)))
  (require 'ffap)
  (advice-add 'ffap-string-at-point :around #'ffap-string-at-point-advice))


(provide 'machine-config)
;;; machine-config.el ends here