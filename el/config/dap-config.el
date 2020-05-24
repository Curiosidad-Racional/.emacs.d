;;; dap-config.el --- Configure and improve dap

;;; Commentary:

;; Usage:
;; (with-eval-after-load 'dap-mode
;;   (require 'dap-config))
;; never:
;; (require 'dap-config)

;; Do not include in this file:
;; (require 'dap-mode)

;;; Code:

(message "Importing dap-config")

(setq dap-python-terminal "xterm -e "
      dap-auto-configure-features nil
      ;; or '(sessions locals breakpoints expressions)
      )

(dap-ui-mode)


(provide 'dap-config)
;;; dap-config.el ends here
