(require 'recentf)
(setq recentf-max-saved-items 500
      recentf-max-menu-items 20
      recentf-exclude '("\\.emacs\\.d/elpa/.*\\.el\\'" "/\\.\\.\\\\")
      recentf-filename-handlers '(file-truename abbreviate-file-name))
(recentf-mode 1)
;; [ Se encarga helm
;;(global-set-key "\C-x\ \C-r" 'recentf-open-files)
;; ]
(set 'tool-bar-max-label-size 12)
(set 'tool-bar-style 'image)


(provide 'menu-config)
