;;; ediff-config.el --- Configure ediff

;;; Commentary:

;;; Code:

(require 'ediff)
(add-hook 'ediff-after-quit-hook-internal 'winner-undo)

(custom-set-faces
 '(ediff-odd-diff-A ((t (:background "dark slate gray"))))
 '(ediff-odd-diff-B ((t (:background "dark slate gray"))))
 '(ediff-odd-diff-C ((t (:background "dark slate gray"))))
 '(ediff-even-diff-A ((t (:background "dim gray"))))
 '(ediff-even-diff-B ((t (:background "dim gray"))))
 '(ediff-even-diff-C ((t (:background "dim gray"))))
 '(ediff-fine-diff-A ((t (:background "brown"))))
 '(ediff-fine-diff-B ((t (:background "brown"))))
 '(ediff-fine-diff-C ((t (:background "brown"))))
 '(ediff-current-diff-A ((t (:foreground "White" :background "dark green"))))
 '(ediff-current-diff-B ((t (:foreground "White" :background "dark green"))))
 '(ediff-current-diff-C ((t (:foreground "White" :background "dark green")))))

(setq-default ediff-forward-word-function 'forward-char)

(setq ediff-window-setup-function 'ediff-setup-windows-plain
      ediff-split-window-function 'split-window-horizontally
      ediff-diff-ok-lines-regexp
      "^\\([0-9,]+[acd][0-9,]+?$\\|[<>] \\|---\\|.*Warning *:\\|.*No +newline\\|.*missing +newline\\|.*No +hay +ningún +carácter +de +nueva +línea +al +final +del +fichero\\|^?$\\)")

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
    (ediff-current-file))))

(bind-keys
 ("C-c D"     . diff-revert-buffer-with-file))


(provide 'ediff-config)
;;; ediff-config.el ends here
