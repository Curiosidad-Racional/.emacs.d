(defun save-messages-buffer ()
  (with-current-buffer "*Messages*"
    (write-region (point-min) (point-max)
                  (expand-file-name "last-messages-buffer.txt"
                                    user-emacs-directory))))
(add-hook 'kill-emacs-hook 'save-messages-buffer 92)

(defvar exwm-p (member "--exwm" command-line-args))

(require 'package)

(setq package-enable-at-startup nil
      ;; call `package-quickstart-refresh' every time `package-load-list'
      ;; is modified
      package-quickstart t)

;; [ <repos> configure repositories
;; (add-to-list 'package-archives '("ELPA" . "http://tromey.com/elpa/"))
;; (add-to-list 'package-archives '("org" . "http://orgmode.org/elpa/"))

(let* ((protocol (if (and (memq system-type '(windows-nt ms-dos))
                          (not (gnutls-available-p)))
                     "http"
                   "https"))
       (repos '(("org"          . "://orgmode.org/elpa/")
                ("melpa"        . "://melpa.org/packages/")
                ("melpa-stable" . "://stable.melpa.org/packages/")
                ;; package name conflict: `project'
                ;; ("marmalade"    . "://marmalade-repo.org/packages/")
                ("emacswiki"    . "://mirrors.tuna.tsinghua.edu.cn/elpa/emacswiki/"))))
  (mapc (lambda (p)
          (add-to-list
           'package-archives
           (cons (car p) (concat protocol (cdr p))) t))
        repos))

(package-initialize)
;; sort package list
(defun package--save-selected-packages-advice (orig-fun value)
  (funcall orig-fun (sort value 'string-lessp)))
(advice-add 'package--save-selected-packages :around #'package--save-selected-packages-advice)

(defun package-auto-install-remove ()
            ;; install packages in list
            (let ((list-of-boolean (mapcar #'package-installed-p package-selected-packages)))
              (if (cl-every #'identity list-of-boolean)
                  (message "Nothing to install")
                (progn
                  (package-refresh-contents)
                  (let ((list-of-uninstalled '()))
                    (cl-mapc #'(lambda (a b)
                                 (unless a
                                   (set 'list-of-uninstalled (cons b list-of-uninstalled))))
                             list-of-boolean package-selected-packages)
                    (mapc #'package-install list-of-uninstalled)))))
            ;; uninstall packages not in list
            ;;(mapc #'package-delete (set-difference package-activated-list package-selected-packages))
            (package-autoremove))

(add-hook (if exwm-p
              'exwm-init-hook
            'emacs-startup-hook)
          'package-auto-install-remove)

(defun package-emacswiki-update ()
  (interactive)
  ;; bookmark+
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-mac.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-mac.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-bmu.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-bmu.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-1.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-1.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-key.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-key.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-lit.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-lit.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-doc.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-doc.el" t)
  (url-copy-file "https://www.emacswiki.org/emacs/download/bookmark%2b-chg.el"
                 "~/.emacs.d/el/packages/bookmark+/bookmark+-chg.el" t)
  (byte-recompile-directory "~/.emacs.d/el/packages/bookmark+" 0 t)
  ;; thingatpt+
  (url-copy-file "https://www.emacswiki.org/emacs/download/thingatpt%2b.el"
                 "~/.emacs.d/el/packages/thingatpt+/thingatpt+.el" t)
  (byte-recompile-directory "~/.emacs.d/el/packages/thingatpt+" 0 t))

(add-hook (if exwm-p
              'exwm-init-hook
           'emacs-startup-hook)
          `(lambda ()
             (setq gc-cons-percentage ,gc-cons-percentage
                   gc-cons-threshold ,gc-cons-threshold))
          t)
(setq gc-cons-percentage 0.6
      gc-cons-threshold (eval-when-compile
                          (* 10 1024 1024)))

;; (defun gcmh-idle-garbage-collect-advice (orig-fun)
;;   (unless (or ;; cursor-in-echo-area
;;            prefix-arg
;;            (< 0 (length (this-single-command-keys)))
;;            (active-minibuffer-window))
;;     (funcall orig-fun)))
;; (advice-add 'gcmh-idle-garbage-collect :around 'gcmh-idle-garbage-collect-advice)

(add-hook 'after-init-hook
          (lambda ()
            (defun post-gc-truncate-buffers ()
              (comint-truncate-buffers "^\\*EGLOT (.*) \\(stderr\\|output\\)\\*$" t))
            (add-hook 'post-gc-hook 'post-gc-truncate-buffers)))

(add-hook 'after-init-hook
          `(lambda ()
             (setq file-name-handler-alist (quote ,file-name-handler-alist))))
(setq file-name-handler-alist nil)

(setq-default bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)
(global-so-long-mode 1)

(when (getenv "BENCHMARK")
  (defvar benchmark-last-time (current-time))
  (defvar benchmark-last-feature "early-init")
  (defvar benchmark-buffer (generate-new-buffer "*Benchmarks*"))
  (require 'time-date)
  (defun benchmark-require-advice (orig-fun feature &optional filename noerror)
    (let* ((time (float-time (time-since benchmark-last-time)))
           (initial-time (current-time))
           (result (funcall orig-fun feature filename noerror))
           (require-time (float-time (time-since initial-time))))
      (with-current-buffer benchmark-buffer
        (insert (format "%fs  between `%s' and `%s'\n%fs  loading `%s'\n"
                        time benchmark-last-feature feature
                        require-time feature)))
      (setq benchmark-last-time (current-time)
            benchmark-last-feature feature)
      result))
  (advice-add 'require :around 'benchmark-require-advice)
  (add-hook 'emacs-startup-hook
            (lambda ()
              (advice-remove 'require 'benchmark-require-advice))))

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
;; display hover help text in the echo area
(tooltip-mode -1)

;; (fringe-mode '(4 . 4))
(setq-default indicate-buffer-boundaries 'right)
(defface visual-line-fringe-face
  '((t :foreground "gold1"))
  "Visual line fringe face" :group 'visual-line)
(set-fringe-bitmap-face 'left-curly-arrow 'visual-line-fringe-face)
(set-fringe-bitmap-face 'right-curly-arrow 'visual-line-fringe-face)
(setq visual-line-fringe-indicators '(left-curly-arrow right-curly-arrow)
      frame-inhibit-implied-resize t)
;; (add-to-list 'default-frame-alist '(inhibit-double-buffering . t))

;; (set 'custom-enabled-themes 'wheatgrass)
(load-theme 'misterioso t)
(set-face-attribute 'mode-line nil :background "#003445")
(with-eval-after-load 'which-func
  (set-face-attribute 'which-func nil :foreground "#a040bb"))

;; (require 'cursor-chg)  ; Load this library
;; (change-cursor-mode 1) ; On for overwrite/read-only/input mode
;; (toggle-cursor-type-when-idle 1) ; On when idle
;; (setq curchg-idle-cursor-type 'hbar
;;       curchg-default-cursor-type 'bar
;;       curchg-overwrite/read-only-cursor-type 'box)
(add-to-list 'default-frame-alist '(cursor-color . "red"))
;; [ Cycle themes
(require 'ring)
(defvar theme-ring nil)
(let ((themes '(wombat whiteboard adwaita misterioso)))
  (setq theme-ring (make-ring (length themes)))
  (dolist (elem themes) (ring-insert theme-ring elem)))

(defun cycle-themes ()
  "Cycle themes in ring."
  (interactive)
  (let ((theme (ring-ref theme-ring -1)))
    (ring-insert theme-ring theme)
    (load-theme theme)
    (message "%s theme loaded" theme)))
;; ]

;; [ transparency
(defun toggle-transparency ()
   (interactive)
   (let ((alpha (frame-parameter nil 'alpha)))
     (set-frame-parameter
      nil 'alpha
      (if (eql (cond ((numberp alpha) alpha)
                     ((numberp (cdr alpha)) (cdr alpha))
                     ;; Also handle undocumented (<active> <inactive>) form.
                     ((numberp (cadr alpha)) (cadr alpha)))
               100)
          '(90 . 75) '(100 . 100)))))
(add-to-list 'default-frame-alist '(alpha . (90 . 75)))
;; (set-frame-parameter (selected-frame) 'alpha '(90 . 75))
;; ]

(defun unspecified-background (&optional frame)
  (let ((frame (or frame (selected-frame))))
    (unless (display-graphic-p frame)
      (set-face-background 'default "unspecified-bg" frame))))
(add-hook 'window-setup-hook 'unspecified-background)
(add-hook 'after-make-frame-functions 'unspecified-background)

(global-set-key (kbd "M-s 6 t") #'cycle-themes)
(global-set-key (kbd "M-s 7 t") #'toggle-transparency)

(setq initial-buffer-choice nil
      inhibit-startup-screen t
      initial-major-mode 'fundamental-mode
      visible-bell t
      history-delete-duplicates t
      debugger-bury-or-kill nil
      ;; avoids warnings
      ad-redefinition-action 'accept)
