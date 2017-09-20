;;; move-token.el --- Move words and sexps with cursors

;;; Commentary:

;; Usage:
;; (require 'move-token)

;;; Code:

;;;;;;;;;;;;;;;
;; Word-Word ;;
;;;;;;;;;;;;;;;
(defun move-word-up ()
  (let* ((token-1-end (progn (right-word 1) (point)))
         (token-1-beg (progn (left-word 1) (point)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (line-move -1)
    (let ((moves -1)
          (line (line-number-at-pos)))
      (right-word 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-decf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (right-word 1)))
    (let* ((token-2-end (point))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-word-down ()
  (let* ((token-1-end (progn (right-word 1) (point)))
         (token-1-beg (progn (left-word 1) (point)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (line-move 1)
    (let ((moves 1)
          (line (line-number-at-pos)))
      (right-word 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-incf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (right-word 1)))    
    (let* ((token-2-end (point))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

(defun move-word-left ()
  (let* ((token-1-end (progn (right-word 1) (point)))
         (token-1-beg (progn (left-word 1) (point)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (left-word 1)
    (let* ((token-2-end (progn (right-word 1) (point)))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-word-right ()
  (let* ((token-1-end (progn (right-word 1) (point)))
         (token-1-beg (progn (left-word 1) (point)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (right-word 1)
    (let* ((token-2-end (progn (right-word 1) (point)))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

;;;;;;;;;;;;;;;;;
;; Region-Word ;;
;;;;;;;;;;;;;;;;;
(defun move-region-word-up ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (line-move -1)
    (let ((moves -1)
          (line (line-number-at-pos)))
      (right-word 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-decf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (right-word 1)))
    (let* ((token-2-end (point))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-region-word-down ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (line-move 1)
    (let ((moves 1)
          (line (line-number-at-pos)))
      (right-word 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-incf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (right-word 1)))    
    (let* ((token-2-end (point))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

(defun move-region-word-left ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (left-word 1)
    (let* ((token-2-end (progn (right-word 1) (point)))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-region-word-right ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (goto-char token-1-end)
    (right-word 1)
    (let* ((token-2-end (progn (right-word 1) (point)))
           (token-2-beg (progn (left-word 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))


;;;;;;;;;;;;;;;
;; SExp-SExp ;;
;;;;;;;;;;;;;;;
(defun move-sexp-up ()
  (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
         (token-1-beg (progn (sp-backward-sexp 1) (point)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (line-move -1)
    (let ((moves -1)
          (line (line-number-at-pos)))
      (sp-forward-sexp 1)
      (sp-backward-sexp 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-decf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (sp-forward-sexp 1)
        (sp-backward-sexp 1)))
    (let* ((token-2-beg (point))
           (token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-sexp-down ()
  (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
         (token-1-beg (progn (sp-backward-sexp 1) (point)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (line-move 1)
    (let ((moves 1)
          (line (line-number-at-pos)))
      (sp-forward-sexp 1)
      (sp-backward-sexp 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-incf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (sp-forward-sexp 1)
        (sp-backward-sexp 1)))
    (let* ((token-2-beg (point))
           (token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

(defun move-sexp-left ()
  (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
         (token-1-beg (progn (sp-backward-sexp 1) (point)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (sp-backward-sexp 1)
    (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-beg (progn (sp-backward-sexp 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-sexp-right ()
  (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
         (token-1-beg (progn (sp-backward-sexp 1) (point)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (sp-forward-sexp 1)
    (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-beg (progn (sp-backward-sexp 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))


;;;;;;;;;;;;;;;;;
;; Region-SExp ;;
;;;;;;;;;;;;;;;;;
(defun move-region-sexp-up ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (line-move -1)
    (let ((moves -1)
          (line (line-number-at-pos)))
      (sp-forward-sexp 1)
      (sp-backward-sexp 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-decf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (sp-forward-sexp 1)
        (sp-backward-sexp 1)))
    (let* ((token-2-beg (point))
           (token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-region-sexp-down ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (line-move 1)
    (let ((moves 1)
          (line (line-number-at-pos)))
      (sp-forward-sexp 1)
      (sp-backward-sexp 1)
      (while (not (= line (line-number-at-pos)))
        (goto-char token-1-beg)
        (cl-incf moves)
        (line-move moves)
        (set 'line (line-number-at-pos))
        (sp-forward-sexp 1)
        (sp-backward-sexp 1)))
    (let* ((token-2-beg (point))
           (token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

(defun move-region-sexp-left ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
    (goto-char token-1-beg)
    (sp-backward-sexp 1)
    (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-beg (progn (sp-backward-sexp 1) (point)))
           (token-2-str (buffer-substring token-2-beg token-2-end)))
      (goto-char token-1-beg)
      (insert token-2-str)
      (delete-region token-2-beg token-2-end)
      (goto-char token-2-beg)
      (insert token-1-str)
      (goto-char token-2-beg))))

(defun move-region-sexp-right ()
  (let* ((token-1-end (max (point) (mark)))
         (token-1-beg (min (point) (mark)))
         (token-1-str (buffer-substring token-1-beg token-1-end)))
    (goto-char token-1-end)
    (sp-forward-sexp 1)
    (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
           (token-2-beg (progn (sp-backward-sexp 1) (point)))
           (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
      (insert token-1-str)
      (goto-char token-1-beg)
      (delete-region token-1-beg token-1-end)
      (goto-char token-1-beg)
      (insert token-2-str)
      (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Depth SExp-Depth SExp ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; (defun move-depth-sexp-up ()
;;   (let* ((token-1-end (progn (sp-end-of-sexp 1) (point)))
;;          (token-1-beg (progn (sp-beginning-of-sexp 1) (point)))
;;          (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
;;     (line-move -1)
;;     (let ((moves -1)
;;           (line (line-number-at-pos)))
;;       (sp-beginning-of-sexp 1)
;;       (while (not (= line (line-number-at-pos)))
;;         (goto-char token-1-beg)
;;         (cl-decf moves)
;;         (line-move moves)
;;         (set 'line (line-number-at-pos))
;;       (sp-beginning-of-sexp 1)))
;;     (let* ((token-2-beg (point))
;;            (token-2-end (progn (sp-end-of-sexp 1) (point)))
;;            (token-2-str (buffer-substring token-2-beg token-2-end)))
;;       (goto-char token-1-beg)
;;       (insert token-2-str)
;;       (delete-region token-2-beg token-2-end)
;;       (goto-char token-2-beg)
;;       (insert token-1-str)
;;       (goto-char token-2-beg))))

;; (defun move-depth-sexp-down ()
;;   (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
;;          (token-1-beg (progn (sp-backward-sexp 1) (point)))
;;          (token-1-str (buffer-substring token-1-beg token-1-end)))
;;     (line-move 1)
;;     (let ((moves 1)
;;           (line (line-number-at-pos)))
;;       (sp-forward-sexp 1)
;;       (sp-backward-sexp 1)
;;       (while (not (= line (line-number-at-pos)))
;;         (goto-char token-1-beg)
;;         (cl-incf moves)
;;         (line-move moves)
;;         (set 'line (line-number-at-pos))
;;         (sp-forward-sexp 1)
;;         (sp-backward-sexp 1)))
;;     (let* ((token-2-beg (point))
;;            (token-2-end (progn (sp-forward-sexp 1) (point)))
;;            (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
;;       (insert token-1-str)
;;       (goto-char token-1-beg)
;;       (delete-region token-1-beg token-1-end)
;;       (goto-char token-1-beg)
;;       (insert token-2-str)
;;       (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))

;; (defun move-depth-sexp-left ()
;;   (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
;;          (token-1-beg (progn (sp-backward-sexp 1) (point)))
;;          (token-1-str (delete-and-extract-region token-1-beg token-1-end)))
;;     (sp-backward-sexp 1)
;;     (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
;;            (token-2-beg (progn (sp-backward-sexp 1) (point)))
;;            (token-2-str (buffer-substring token-2-beg token-2-end)))
;;       (goto-char token-1-beg)
;;       (insert token-2-str)
;;       (delete-region token-2-beg token-2-end)
;;       (goto-char token-2-beg)
;;       (insert token-1-str)
;;       (goto-char token-2-beg))))

;; (defun move-depth-sexp-right ()
;;   (let* ((token-1-end (progn (sp-forward-sexp 1) (point)))
;;          (token-1-beg (progn (sp-backward-sexp 1) (point)))
;;          (token-1-str (buffer-substring token-1-beg token-1-end)))
;;     (sp-forward-sexp 1)
;;     (let* ((token-2-end (progn (sp-forward-sexp 1) (point)))
;;            (token-2-beg (progn (sp-backward-sexp 1) (point)))
;;            (token-2-str (delete-and-extract-region token-2-beg token-2-end)))
;;       (insert token-1-str)
;;       (goto-char token-1-beg)
;;       (delete-region token-1-beg token-1-end)
;;       (goto-char token-1-beg)
;;       (insert token-2-str)
;;       (goto-char (+ token-2-beg (- (length token-2-str) (length token-1-str)))))))


;;;;;;;;;;;;;;;;;
;; * or Region ;;
;;;;;;;;;;;;;;;;;
(defun move-word-or-region-up ()
  (interactive)
  (if mark-active
      (move-region-word-up)
    (move-word-up)))

(defun move-word-or-region-down ()
  (interactive)
  (if mark-active
      (move-region-word-down)
    (move-word-down)))

(defun move-word-or-region-left ()
  (interactive)
  (if mark-active
      (move-region-word-left)
    (move-word-left)))

(defun move-word-or-region-right ()
  (interactive)
  (if mark-active
      (move-region-word-right)
    (move-word-right)))

(defun move-sexp-or-region-up ()
  (interactive)
  (if mark-active
      (move-region-sexp-up)
    (move-sexp-up)))

(defun move-sexp-or-region-down ()
  (interactive)
  (if mark-active
      (move-region-sexp-down)
    (move-sexp-down)))

(defun move-sexp-or-region-left ()
  (interactive)
  (if mark-active
      (move-region-sexp-left)
    (move-sexp-left)))

(defun move-sexp-or-region-right ()
  (interactive)
  (if mark-active
      (move-region-sexp-right)
    (move-sexp-right)))


;;;;;;;;;;;
;; Lines ;;
;;;;;;;;;;;
(defun move-text-internal (arg)
   (cond
    ((and mark-active transient-mark-mode)
     (if (> (point) (mark))
            (exchange-point-and-mark))
     (let ((column (current-column))
              (text (delete-and-extract-region (point) (mark))))
       (forward-line arg)
       (move-to-column column t)
       (set-mark (point))
       (insert text)
       (exchange-point-and-mark)
       (setq deactivate-mark nil)))
    (t
     (beginning-of-line)
     (when (or (> arg 0) (not (bobp)))
       (forward-line)
       (if (= 0 (current-column))
           (when (or (< arg 0) (not (eobp)))
             (transpose-lines arg))
         (when (or (< arg 0) (not (eobp)))
           (insert "\n")
           (forward-line)
           (transpose-lines arg)))
       (forward-line -1)))))


(defun move-text-down (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines down."
   (interactive "*p")
   (move-text-internal arg))

(defun move-text-up (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines up."
   (interactive "*p")
   (move-text-internal (- arg)))

(global-set-key [\C-\M-\S-up] 'move-text-up)
(global-set-key [\C-\M-\S-down] 'move-text-down)

(bind-keys
 ("M-C-<up>"            . move-word-or-region-up)
 ("M-C-<down>"          . move-word-or-region-down)
 ("M-C-<left>"          . move-word-or-region-left)
 ("M-C-<right>"         . move-word-or-region-right)
 ("M-S-<up>"            . move-sexp-or-region-up)
 ("M-S-<down>"          . move-sexp-or-region-down)
 ("M-S-<left>"          . move-sexp-or-region-left)
 ("M-S-<right>"         . move-sexp-or-region-right))


(provide 'move-token)
;;; move-token.el ends here
