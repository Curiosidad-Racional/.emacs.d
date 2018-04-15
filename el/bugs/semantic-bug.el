;; [ Limit semantic parser
;; (defvar semantic-fetch-tags-limit-default 15)
;; (defvar semantic-fetch-tags-limit semantic-fetch-tags-limit-default)
;; (run-with-idle-timer 120 60 #'(lambda ()
;;                                 (set 'semantic-fetch-tags-limit semantic-fetch-tags-limit-default)))
;; (defun semantic-fetch-tags-advice (orig-fun &rest args)
;;   "Only advice `semantic-fetch-tags' ORIG-FUN.  ARGS have to be nil."
;;   (if (and
;;        (semantic-parse-tree-needs-rebuild-p)
;;        (not noninteractive))
;;       (progn
;;         (cl-decf semantic-fetch-tags-limit)
;;         (if (< semantic-fetch-tags-limit 0)
;;             (let ((number (read-number "Limit reached. New limit: "
;;                                        semantic-fetch-tags-limit-default)))
;;               (if (<= number 0)
;;                   (progn
;;                     (set 'semantic-fetch-tags-limit semantic-fetch-tags-limit-default)
;;                     (error "Parsing limit reached"))
;;                 (set 'semantic-fetch-tags-limit number))))))
;;   (apply orig-fun args))
;; <xor>

(when (bug-check-function-bytecode
       'semantic-fetch-tags
       "\203\260 \306\307!\203\260 \306\310!\203\260 	\311=\204\260 	\203\260 \n\312]\313\211\314 \210	\315\267\202\257 \316 	\317=\203: \320 \210\202B \321 \210\322\323\f\"\210\313\202\257 $\203T \324ed\"\202\224 d%Y\205\202 &\325=\205\202 \326\327 '\330'\205r \331\332'\"(\205| \331\333(\"\334R)\335\336#)\324ed\")\203\223 \337)!\210)\313\211\211*+,\340 \210+\f-\341\342-\"\210)\343\f!\210+.\207")
  (defun semantic-fetch-tags-advice (orig-fun &rest args)
    "Only advice `semantic-fetch-tags' ORIG-FUN.  ARGS have to be nil."
    (if (and
         (semantic-parse-tree-needs-rebuild-p)
         (not noninteractive))
        (let ((event (read-event nil nil 0.001)))
          (when event
            (push event unread-command-events)
            (error "Parsing while typing"))))
    (apply orig-fun args)
    (advice-add 'semantic-fetch-tags :around #'semantic-fetch-tags-advice)))
;; ]


(provide 'semantic-bug)