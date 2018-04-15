;;; projectile-config.el --- Configure projectile

;;; Commentary:

;; Usage:
;; (require 'projectile-config)

;;; Code:

(message "Importing projectile-config")
;;;;;;;;;;;;;;;;
;; Projectile ;;
;;;;;;;;;;;;;;;;

;;;;;;;;;;
;; Bugs ;;
;;;;;;;;;;
;; (eval-after-load "projectile"
;;   '(progn
;;      (defun projectile-get-other-files (current-file project-file-list &optional flex-matching)
;;        "Narrow to files with the same names but different extensions.
;; Returns a list of possible files for users to choose.

;; With FLEX-MATCHING, match any file that contains the base name of current file"
;;        (let* ((file-ext-list (projectile-associated-file-name-extensions current-file))
;;               (fulldirname  (if (file-name-directory current-file)
;;                                 (file-name-directory current-file) "./"))
;;               (dirname  (file-name-nondirectory (directory-file-name fulldirname)))
;;               (filename (projectile--file-name-sans-extensions current-file))
;;               (file-list (mapcar (lambda (ext)
;;                                    (if flex-matching
;;                                        (concat ".*" filename ".*" "\." ext "\\'")
;;                                      (concat "^" filename
;;                                              (unless (equal ext "")
;;                                                (concat  "\." ext))
;;                                              "\\'")))
;;                                  file-ext-list))
;;               (candidates (-filter (lambda (project-file)
;;                                      (string-match filename project-file))
;;                                    project-file-list))
;;               (candidates
;;                (-flatten (mapcar
;;                           (lambda (file)
;;                             (-filter (lambda (project-file)
;;                                        (string-match file
;;                                                      (concat (file-name-base project-file)
;;                                                              (unless (equal (file-name-extension project-file) nil)
;;                                                                (concat  "\." (file-name-extension project-file))))))
;;                                      candidates))
;;                           file-list)))
;;               (candidates
;;                (-sort (lambda (file _)
;;                         (let ((candidate-dirname (condition-case nil
;;                                                      (file-name-nondirectory (directory-file-name (file-name-directory file)))
;;                                                    (error nil))
;;                                                  ))
;;                           (unless (equal fulldirname (file-name-directory file))
;;                             (equal dirname candidate-dirname))))
;;                       candidates)))
;;          candidates))
;;      (defun projectile-get-ext-command()
;;        projectile-generic-command)
;;      (defun bug-projectile-get-other-files (orig-fun &rest args)
;;        (if (projectile-project-p)
;;            (apply orig-fun args)
;;          (list (file-name-nondirectory (ff-other-file-name)))))
;;      (advice-add 'projectile-get-other-files :around #'bug-projectile-get-other-files)))
;;;;;;;;;;
;;;;;
(require 'projectile)
;;(require 'projectile-bug)

(require 'helm-projectile)
;; [ Sólo requerido para algunos ficheros
;;(projectile-global-mode)
;; ]

(setq projectile-globally-ignored-file-suffixes
      '(".o" ".d" ".crt" ".key" ".txt" "~")
      ;projectile-indexing-method 'native
      ;projectile-enable-caching nil
      ;projectile-file-exists-remote-cache-expire nil
      ;projectile-require-project-root nil
      projectile-find-dir-includes-top-level t ; el bug
      projectile-project-root-files-top-down-recurring
      '("Makefile" "makefile" "CMakeLists.txt" "makefile.linux")
      projectile-project-root-files-functions
      '(projectile-root-local
        projectile-root-top-down-recurring
        projectile-root-bottom-up
        projectile-root-top-down)
      projectile-completion-system 'helm
      projectile-switch-project-action 'helm-projectile)
(helm-projectile-on)


(provide 'projectile-config)
;;; projectile-config.el ends here