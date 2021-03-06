;;; symon.el --- tiny graphical system monitor

;;; Commentary:

;; Load this script
;;
;;   (require 'symon)
;;
;; and turn on `symon-mode'.
;;
;;   (symon-mode)
;;
;; then a tiny system monitor is displayed in minibuffer, during idle.

;;; Code:

(require 'battery)
(require 'ring)
(require 'cl-macs)

(defconst symon-version "1.2.0")

(defgroup symon nil
  "tiny graphical system monitor"
  :group 'emacs)

;; + customs

;; core

(defcustom symon-refresh-rate 4
  "Refresh rate of symon display.
Set this option BEFORE enabling `symon-mode'."
  :group 'symon
  :type 'float)

(defcustom symon-history-size 50
  "Number of old values to keep.
Sparklines grow faster when set smaller. 
Set this option BEFORE enabling `symon-mode'."
  :group 'symon
  :type 'integer)

(defcustom symon-monitors
  (cond ((memq system-type '(gnu/linux cygwin))
         '(symon-linux-memory-monitor
           symon-linux-cpu-monitor
           symon-linux-network-rx-monitor
           symon-linux-network-tx-monitor))
        ((memq system-type '(darwin))
         '(symon-darwin-memory-monitor
           symon-darwin-cpu-monitor
           symon-darwin-network-rx-monitor
           symon-darwin-network-tx-monitor))
        ((memq system-type '(windows-nt))
         '(symon-windows-memory-monitor
           symon-windows-cpu-monitor
           symon-windows-network-rx-monitor
           symon-windows-network-tx-monitor)))
  "List of monitors used to read system statuses. This variable
  also can be a list of lists from version 1.2, that case
  monitors are displayed in multiple pages. *set this option
  BEFORE enabling `symon-mode'.*"
  :group 'symon
  :type 'list)

;; sparkline

(defcustom symon-sparkline-height 11
  "Height of sparklines."
  :group 'symon
  :type 'integer)

(defcustom symon-sparkline-width 80
  "Width of sparklines."
  :group 'symon
  :type 'integer)

(defcustom symon-sparkline-ascent 100
  "`:ascent' property for sparklines."
  :group 'symon
  :type 'integer)

(defcustom symon-sparkline-thickness 2
  "Line width of sparklines."
  :group 'symon
  :type 'integer)

(defcustom symon-sparkline-type 'gridded
  "Type of sparklines."
  :group 'symon
  :type 'symbol)

;; some darwin builds cannot render xbm images (foreground color is
;; always black), so convert to xpm before rendering.
(defcustom symon-sparkline-use-xpm (eq system-type 'darwin)
  "When non-nil, convert sparklines to xpm from xbm before
rendering."
  :group 'symon
  :type 'boolean)

;; network monitor

(defcustom symon-network-rx-upper-bound 300
  "Upper-bound of sparkline for network RX status."
  :group 'symon
  :type 'float)

(defcustom symon-network-tx-upper-bound 100
  "Upper-bound of sparkline for network TX status."
  :group 'symon
  :type 'float)

(defcustom symon-network-rx-lower-bound 0
  "Lower-bound of sparkline for network RX status."
  :group 'symon
  :type 'float)

(defcustom symon-network-tx-lower-bound 0
  "Lower-bound of sparkline for network TX status."
  :group 'symon
  :type 'float)

;; page-file monitor

(defcustom symon-windows-page-file-upper-bound 2000
  "Upper-bound of sparkline for page file usage."
  :group 'symon
  :type 'integer)

(defcustom symon-total-spark-width 10
  "Spark figures space."
  :group 'symon
  :type 'integer)

;; + utilities
;;   + general

(defun symon--flatten (lst)
  "Flatten LST."
  (if (consp lst)
      (apply 'nconc (mapcar 'symon--flatten lst))
    (list lst)))

;;   + sparkline generator

;; sparkline-types are internally a symbol with property
;; 'symon-sparkline-type associated to a function that generates a
;; 2d-bool-vector.

(defvar symon--sparkline-base-cache
  [nil symon-sparkline-width symon-sparkline-height nil])
(defun symon--get-sparkline-base ()
  (unless (and (eq (aref symon--sparkline-base-cache 0) symon-sparkline-type)
               (= (aref symon--sparkline-base-cache 1) symon-sparkline-width)
               (= (aref symon--sparkline-base-cache 2) symon-sparkline-height))
    (aset symon--sparkline-base-cache 0 symon-sparkline-type)
    (aset symon--sparkline-base-cache 1 symon-sparkline-width)
    (aset symon--sparkline-base-cache 2 symon-sparkline-height)
    (aset symon--sparkline-base-cache 3
          (funcall (get symon-sparkline-type 'symon-sparkline-type))))
  (copy-sequence (aref symon--sparkline-base-cache 3)))

(defun symon--make-sparkline (list &optional minimum maximum)
  "Make sparkline image from LIST."
  (let ((num-samples (length list)))
    (unless (zerop num-samples)
      (let* ((image-data (symon--get-sparkline-base))
             (maximum (if maximum (float maximum) 100.0))
             (minimum (if minimum (float minimum) 0.0))
             (topmargin (1- symon-sparkline-thickness))
             (height (- symon-sparkline-height topmargin))
             (height-per-point (/ height (1+ (- maximum minimum))))
             (width-per-sample (/ symon-sparkline-width (float num-samples)))
             (samples (apply 'vector list))
             sample y ix)
        (dotimes (x symon-sparkline-width)
          (setq sample (aref samples (floor (/ x width-per-sample))))
          (when (numberp sample)
            (setq y (floor (* (- sample minimum) height-per-point)))
            (when (and (<= 0 y) (< y height))
              (dotimes (dy symon-sparkline-thickness)
                (aset image-data
                      (+ (* (- symon-sparkline-height (+ y dy) 1) symon-sparkline-width) x)
                      t)))))
        `(image :type xbm :data ,image-data :ascent ,symon-sparkline-ascent
                :height ,symon-sparkline-height :width ,symon-sparkline-width)))))

(defun symon--convert-sparkline-to-xpm (sparkline)
  "Convert sparkline to an xpm image."
  (let ((data (plist-get (cdr sparkline) :data)))
    (with-temp-buffer
      (insert (format "/* XPM */
static char * sparkline_xpm[] = { \"%d %d 2 1\", \"@ c %s\", \". c none\""
                      symon-sparkline-width symon-sparkline-height
                      (face-foreground 'default)))
      (let ((ix 0))
        (dotimes (x symon-sparkline-height)
          (insert ",\n\"")
          (dotimes (y symon-sparkline-width)
            (insert (if (aref data ix) ?@ ?.))
            (setq ix (1+ ix)))
          (insert "\"")))
      (insert "};")
      `(image :type xpm :data ,(buffer-string) :ascent ,symon-sparkline-ascent
              :height ,symon-sparkline-height :width ,symon-sparkline-width))))

;;   + symon monitor generator

;; a symon monitor is internally a symbol with property 'symon-monitor
;; associated to a vector of 3 functions: [SETUP-FN CLEANUP-FN
;; DISPLAY-FN]. SETUP-FN is called on activation of `symon-mode', and
;; expected to setup Emacs to fetch status values in a specific
;; interval. CLEANUP-FN is called on deactivation and expected to tell
;; Emacs to stop fetching. DISPLAY-FN is called just before displaying
;; monitor, and must return display string for the monitor.

(defun symon--make-history-ring ()
  "Like (make-ring `symon-history-size') but filled with nil."
  (cons 0 (cons symon-history-size (make-vector symon-history-size nil))))

(defmacro define-symon-monitor (name &rest plist)
  "Define a new symon monitor NAME.
Following keywords are supoprted in PLIST:

:setup (default: nil)

    an expression evaluated when activating `symon-mode', and
    expected to do some preparation.

:cleanup (default: nil)

    an expression evaluated when deactivating `symon-mode', and
    expected to do some cleanup.

:fetch (default: nil)

    an expression that evaluates to the latest status value, the
    value must be a number (otherwise `N/A' is displayed as the
    value).

:interval (default: `symon-refresh-rate')

    fetch interval in seconds.

:index (default: \"\")

    string prepended to the status value (\"MEM:\" for memory
    monitor, for example).

:unit (default: \"\")

    string appended to the status value (\"%\" for memory
    monitor, for example).

:annotation (default: nil)

    an expression that evaluates to the annotation string for the
    metrics (\"xxxKB Swapped\" for memory monitor, for
    example). if this expression returns a non-nil value, it is
    surrounded with parentheses and appended to the status value.

:display (default: nil)

    an expression evaluated before updating symon display. when
    this expression evaluates to a non-nil value, it will be
    displayed instead of standard symon display format.

:sparkline (default: nil)

    when non-nil, sparklines are rendered.

:lower-bound (default: 100.0)

    upper bound of sparkline.

:upper-bound (default: 0.0)

    lower bound of sparkline."
  (let* ((symon-ring (make-symbol (concat (symbol-name name) "-ring")))
         (symon-timer (make-symbol (concat (symbol-name name) "-timer")))
         (sparkline (plist-get plist :sparkline))
         (interval (or (plist-get plist :interval) 'symon-refresh-rate))
         (display (plist-get plist :display))
         (update-fn
          `(lambda ()
             (ring-insert ,symon-ring ,(plist-get plist :fetch))))
         (setup-fn
          `(lambda ()
             (setq ,symon-ring (symon--make-history-ring))
             (setq ,symon-timer (run-with-timer 0 ,interval ,update-fn))
             ,(plist-get plist :setup)
             (funcall ,update-fn)))
         (cleanup-fn
          `(lambda ()
             (cancel-timer ,symon-timer)
             ,(plist-get plist :cleanup)))
         (display-fn
          (if display `(lambda () ,display)
            `(lambda ()
               (let* ((lst (ring-elements ,symon-ring))
                      (val (car lst)))
                 (concat ,(plist-get plist :index)
                         (if (not (numberp val)) "N/A"
                           (concat (format "%d%s" val ,(or (plist-get plist :unit) ""))
                                   (let ((annot ,(plist-get plist :annotation)))
                                     (when annot (concat "(" annot ")")))))
                         ,(when sparkline
                            `(when (window-system)
                               (let ((sparkline (symon--make-sparkline
                                                 lst
                                                 ,(plist-get plist :lower-bound)
                                                 ,(plist-get plist :upper-bound))))
                                 (when symon-sparkline-use-xpm
                                   (setq sparkline
                                         (symon--convert-sparkline-to-xpm sparkline)))
                                 (propertize " " 'display sparkline))))))))))
    `(defvar ,symon-ring nil)
    `(defvar ,symon-timer nil)
    `(put ',name 'symon-monitor (vector ,setup-fn ,cleanup-fn ,display-fn))))

;;   + process management

(defvar symon--process-buffer-name " *symon-process*")
(defvar symon--process-reference-count 0)

(defun symon--read-value-from-process-buffer (index)
  "Read a value from a specific buffer."
  (when (get-buffer symon--process-buffer-name)
    (with-current-buffer symon--process-buffer-name
      (when (save-excursion
              (search-backward-regexp (concat index ":\\([0-9]+\\)\\>") nil t))
        (read (match-string 1))))))

(defun symon--maybe-start-process (cmd)
  (setq symon--process-reference-count
        (1+ symon--process-reference-count))
  (unless (get-buffer symon--process-buffer-name)
    (let ((proc (start-process-shell-command
                 "symon-process" symon--process-buffer-name cmd))
          (filter (lambda (proc str)
                    (when (get-buffer symon--process-buffer-name)
                      (with-current-buffer symon--process-buffer-name
                        (when (and (string-match "-" str) (search-backward "----" nil t))
                          (delete-region 1 (point)))
                        (goto-char (1+ (buffer-size)))
                        (insert str))))))
      (set-process-query-on-exit-flag proc nil)
      (set-process-filter proc filter))))

(defun symon--maybe-kill-process ()
  (setq symon--process-reference-count
        (1- symon--process-reference-count))
  (when (and (zerop symon--process-reference-count)
             (get-buffer symon--process-buffer-name))
    (kill-buffer symon--process-buffer-name)))

;; + predefined monitors
;;   + linux monitors

(defun symon-linux--read-lines (file reader indices)
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char 1)
    (mapcar (lambda (index)
              (save-excursion
                (when (search-forward-regexp (concat "^" index "\\(.*\\)$") nil t)
                  (if reader
                      (funcall reader (match-string 1))
                    (match-string 1)))))
            indices)))

(defvar symon-linux--last-cpu-ticks nil)

(define-symon-monitor symon-linux-cpu-monitor
  :index "🖥" :unit "%" :sparkline t
  :setup (setq symon-linux--last-cpu-ticks nil)
  :fetch (cl-destructuring-bind (cpu)
             (symon-linux--read-lines
              "/proc/stat" (lambda (str) (mapcar 'read (split-string str nil t))) '("cpu"))
           (let ((total (apply '+ cpu)) (idle (nth 3 cpu)))
             (prog1 (when symon-linux--last-cpu-ticks
                      (let ((total-diff (- total (car symon-linux--last-cpu-ticks)))
                            (idle-diff (- idle (cdr symon-linux--last-cpu-ticks))))
                        (unless (zerop total-diff)
                          (/ (* (- total-diff idle-diff) 100) total-diff))))
               (setq symon-linux--last-cpu-ticks (cons total idle))))))

(define-symon-monitor symon-linux-memory-monitor
  :index "⛁" :unit "%" :sparkline t
  :fetch (cl-destructuring-bind (memtotal memavailable memfree buffers cached)
             (symon-linux--read-lines
              "/proc/meminfo" (lambda (str) (and str (read str)))
              '("MemTotal:" "MemAvailable:" "MemFree:" "Buffers:" "Cached:"))
           (if memavailable
               (/ (* (- memtotal memavailable) 100) memtotal)
             (/ (* (- memtotal (+ memfree buffers cached)) 100) memtotal)))
  :annotation (cl-destructuring-bind (swaptotal swapfree)
                  (symon-linux--read-lines
                   "/proc/meminfo" 'read '("SwapTotal:" "SwapFree:"))
                (let ((swapped (/ (- swaptotal swapfree) 1000)))
                  (unless (zerop swapped) (format "%dMB Swapped" swapped)))))

(defvar symon-linux-battery-symbol "🔋?")
(define-symon-monitor symon-linux-battery-monitor
  :index symon-linux-battery-symbol :unit "%" :sparkline t
  :fetch (when battery-status-function
           (let ((data (funcall battery-status-function)))
             (setq symon-linux-battery-symbol (pcase (cdr (assq ?L data))
                                                ("AC" "🔌")
                                                ("BAT" "🔋")
                                                (_ "🔋?")))
             (read (cdr (assoc ?p data))))))

(defvar symon-linux--last-network-rx nil)

(define-symon-monitor symon-linux-network-rx-monitor
  :index "↙" :unit "K/s" :sparkline t
  :upper-bound symon-network-rx-upper-bound
  :lower-bound symon-network-rx-lower-bound
  :setup (setq symon-linux--last-network-rx nil)
  :fetch (with-temp-buffer
           (insert-file-contents "/proc/net/dev")
           (goto-char 1)
           (let ((rx 0))
             (while (search-forward-regexp "^[\s\t]*\\(.*\\):" nil t)
               (unless (string= (match-string 1) "lo")
                 (setq rx (+ rx (read (current-buffer))))))
             (prog1 (when symon-linux--last-network-rx
                      (/ (- rx symon-linux--last-network-rx) symon-refresh-rate 1000))
               (setq symon-linux--last-network-rx rx)))))

(defvar symon-linux--last-network-tx nil)

(define-symon-monitor symon-linux-network-tx-monitor
  :index "↗" :unit "K/s" :sparkline t
  :upper-bound symon-network-tx-upper-bound
  :lower-bound symon-network-tx-lower-bound
  :setup (setq symon-linux--last-network-tx nil)
  :fetch (with-temp-buffer
           (insert-file-contents "/proc/net/dev")
           (goto-char 1)
           (let ((tx 0))
             (while (search-forward-regexp "^[\s\t]*\\(.*\\):" nil t)
               (unless (string= (match-string 1) "lo")
                 (forward-word 8)
                 (setq tx (+ tx (read (current-buffer))))))
             (prog1 (when symon-linux--last-network-tx
                      (/ (- tx symon-linux--last-network-tx) symon-refresh-rate 1000))
               (setq symon-linux--last-network-tx tx)))))

;;   + darwin monitors

(defun symon-darwin--maybe-start-process ()
  (symon--maybe-start-process (format "
while true; do
    echo \"----\"

    interface=`route get 0.0.0.0 | grep interface | awk '{print $2}'`
    s=`netstat -bi -I $interface | tail -1`;
    echo $s | awk '{print \"rx:\"$7}'
    echo $s | awk '{print \"tx:\"$8}'

    s=`hostinfo  | grep 'Load average' | awk '{print \"cpu:\"$3}' | sed 's/,//'`
    echo $s

    m1=`sysctl hw.memsize | sed 's/.*:\s*//'`
    m_active=`vm_stat | grep 'Pages active' | sed 's/.*: *//'`
    m_wired=`vm_stat | grep 'Pages wired' | sed 's/.*: *//'`

    s=`echo \"scale=2; (($m_active+$m_wired)*4096*100 / $m1)\"| bc -l`
    echo \"mem:$s\"

    sleep %d
done" symon-refresh-rate)))

(define-symon-monitor symon-darwin-cpu-monitor
  :index "CPU:" :unit "%" :sparkline t
  :setup (symon-darwin--maybe-start-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "cpu"))

(define-symon-monitor symon-darwin-memory-monitor
  :index "MEM:" :unit "%" :sparkline t
  :setup (symon-darwin--maybe-start-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "mem"))

(defvar symon-darwin--last-network-rx nil)

(define-symon-monitor symon-darwin-network-rx-monitor
  :index "RX:" :unit "KB/s" :sparkline t
  :upper-bound symon-network-rx-upper-bound
  :lower-bound symon-network-rx-lower-bound
  :setup (progn
           (symon-darwin--maybe-start-process)
           (setq symon-darwin--last-network-rx nil))
  :cleanup (symon--maybe-kill-process)
  :fetch (let ((rx (symon--read-value-from-process-buffer "rx")))
           (prog1 (when symon-darwin--last-network-rx
                    (/ (- rx symon-darwin--last-network-rx) symon-refresh-rate 1000))
             (setq symon-darwin--last-network-rx rx))))

(defvar symon-darwin--last-network-tx nil)

(define-symon-monitor symon-darwin-network-tx-monitor
  :index "TX:" :unit "KB/s" :sparkline t
  :upper-bound symon-network-tx-upper-bound
  :lower-bound symon-network-tx-lower-bound
  :setup (progn
           (symon-darwin--maybe-start-process)
           (setq symon-darwin--last-network-tx nil))
  :cleanup (symon--maybe-kill-process)
  :fetch (let ((tx (symon--read-value-from-process-buffer "tx")))
           (prog1 (when symon-darwin--last-network-tx
                    (/ (- tx symon-darwin--last-network-tx) symon-refresh-rate 1000))
             (setq symon-darwin--last-network-tx tx))))

(define-symon-monitor symon-darwin-battery-monitor
  :index "BAT:" :unit "%" :sparkline t
  :fetch (when battery-status-function
           (read (cdr (assoc ?p (funcall battery-status-function))))))

;;   + windows monitors

(defun symon-windows--maybe-start-wmi-process ()
  (symon--maybe-start-process (format "powershell -command          \
$last = 0;                                                          \
while(1)                                                            \
{                                                                   \
    echo ----;                                                      \
                                                                    \
    $t = (gwmi Win32_ComputerSystem).TotalPhysicalMemory / 1000;    \
    $f = (gwmi Win32_OperatingSystem).FreePhysicalMemory;           \
    echo mem:$(($t - $f) * 100 / $t);                               \
                                                                    \
    echo swap:$((gwmi Win32_PageFileUsage).CurrentUsage);           \
                                                                    \
    echo bat:$((gwmi Win32_Battery).EstimatedChargeRemaining);      \
                                                                    \
    $r = 0;                                                         \
    $t = 0;                                                         \
    $w = gwmi Win32_PerfRawData_Tcpip_NetworkInterface;             \
    foreach($x in $w){                                              \
        $r = $r + $x.BytesReceivedPersec;                           \
        $t = $t + $x.BytesSentPersec                                \
    }                                                               \
    echo rx:$($r / 1000);                                           \
    echo tx:$($t / 1000);                                           \
                                                                    \
    $p = (gwmi Win32_PerfRawData_Counters_ProcessorInformation)[0]; \
    if($last)                                                       \
    {                                                               \
        $dt = $p.Timestamp_Sys100NS - $last.Timestamp_Sys100NS;     \
        $dp = $p.PercentProcessorTime - $last.PercentProcessorTime; \
        echo cpu:$((1 - ($dp / $dt)) * 100);                        \
    }                                                               \
    $last = $p;                                                     \
                                                                    \
    sleep %d                                                        \
}" symon-refresh-rate)))

(define-symon-monitor symon-windows-cpu-monitor
  :index "CPU:" :unit "%" :sparkline t
  :setup (symon-windows--maybe-start-wmi-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "cpu"))

(define-symon-monitor symon-windows-memory-monitor
  :index "MEM:" :unit "%" :sparkline t
  :setup (symon-windows--maybe-start-wmi-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "mem"))

(define-symon-monitor symon-windows-page-file-monitor
  :index "PF:" :unit "MB" :sparkline t
  :upper-bound symon-windows-page-file-upper-bound
  :setup (symon-windows--maybe-start-wmi-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "swap"))

(define-symon-monitor symon-windows-battery-monitor
  :index "BAT:" :unit "%" :sparkline t
  :setup (symon-windows--maybe-start-wmi-process)
  :cleanup (symon--maybe-kill-process)
  :fetch (symon--read-value-from-process-buffer "bat"))

(defvar symon-windows--last-network-rx nil)

(define-symon-monitor symon-windows-network-rx-monitor
  :index "RX:" :unit "KB/s" :sparkline t
  :upper-bound symon-network-rx-upper-bound
  :lower-bound symon-network-rx-lower-bound
  :setup (progn
           (symon-windows--maybe-start-wmi-process)
           (setq symon-windows--last-network-rx nil))
  :cleanup (symon--maybe-kill-process)
  :fetch (let ((rx (symon--read-value-from-process-buffer "rx")))
           (prog1 (when symon-windows--last-network-rx
                    (/ (- rx symon-windows--last-network-rx) symon-refresh-rate))
             (setq symon-windows--last-network-rx rx))))

(defvar symon-windows--last-network-tx nil)

(define-symon-monitor symon-windows-network-tx-monitor
  :index "TX:" :unit "KB/s" :sparkline t
  :upper-bound symon-network-tx-upper-bound
  :lower-bound symon-network-tx-lower-bound
  :setup (progn
           (symon-windows--maybe-start-wmi-process)
           (setq symon-windows--last-network-tx nil))
  :cleanup (symon--maybe-kill-process)
  :fetch (let ((tx (symon--read-value-from-process-buffer "tx")))
           (prog1 (when symon-windows--last-network-tx
                    (/ (- tx symon-windows--last-network-tx) symon-refresh-rate))
             (setq symon-windows--last-network-tx tx))))

;;   + misc monitors

(define-symon-monitor symon-current-time-monitor
  :display (format-time-string "%H:%M"))

;; + predefined sparkline types

(defun symon--sparkline-draw-horizontal-grid (vec y)
  (dotimes (x/2 (/ symon-sparkline-width 2))
    (aset vec (+ (* y symon-sparkline-width) (* x/2 2)) t)))

(defun symon--sparkline-draw-vertical-grid (vec x)
  (dotimes (y/2 (/ symon-sparkline-height 2))
    (aset vec (+ (* (* y/2 2) symon-sparkline-width) x) t)))

(defun symon--make-plain-sparkline ()
  (make-bool-vector (* symon-sparkline-height symon-sparkline-width) nil))

(defun symon--make-bounded-sparkline ()
  (let ((vec (symon--make-plain-sparkline)))
    (symon--sparkline-draw-horizontal-grid vec 0)
    (symon--sparkline-draw-horizontal-grid vec (1- symon-sparkline-height))
    vec))

(defun symon--make-boxed-sparkline ()
  (let ((vec (symon--make-bounded-sparkline)))
    (symon--sparkline-draw-vertical-grid vec 0)
    (symon--sparkline-draw-vertical-grid vec (1- symon-sparkline-width))
    vec))

(defun symon--make-gridded-sparkline ()
  (let ((vec (symon--make-boxed-sparkline)))
    (symon--sparkline-draw-horizontal-grid vec (/ symon-sparkline-height 2))
    (symon--sparkline-draw-vertical-grid   vec (/ symon-sparkline-width 4))
    (symon--sparkline-draw-vertical-grid   vec (/ symon-sparkline-width 2))
    (symon--sparkline-draw-vertical-grid   vec (/ (* symon-sparkline-width 3) 4))
    vec))

(put 'plain 'symon-sparkline-type 'symon--make-plain-sparkline)
(put 'bounded 'symon-sparkline-type 'symon--make-bounded-sparkline)
(put 'boxed 'symon-sparkline-type 'symon--make-boxed-sparkline)
(put 'gridded 'symon-sparkline-type 'symon--make-gridded-sparkline)

;; + symon core

(defvar symon--cleanup-fns    nil)      ; List[Fn]
(defvar symon--display-fns    nil)      ; List[List[Fn]]
(defvar symon--active-page    -1)
(defvar symon--total-page-num nil)
(defvar symon--timer-object  nil)

(defvar symon--force-redisplay nil)
(defvar symon--symon-message "")
(defvar symon--last-frame-width 0)

(defun symon--initialize ()
  (unless symon-monitors
    (message "Warning: `symon-monitors' is empty."))
  (let* ((symon-monitors                ; for backward-compatibility
          (if (symbolp (car symon-monitors))
              (list symon-monitors)
            symon-monitors))
         (monitors
          (mapcar (lambda (lst)
                    (mapcar (lambda (s) (get s 'symon-monitor)) lst))
                  symon-monitors))
         (monitors-flattened
          (symon--flatten monitors)))
    (mapc (lambda (m) (funcall (aref m 0))) monitors-flattened) ; setup-fns
    (setq symon--cleanup-fns (mapcar
                              (lambda (m) (aref m 1))
                              monitors-flattened)
          symon--display-fns (mapcar
                              (lambda (l) (mapcar (lambda (m) (aref m 2)) l))
                              monitors)
          symon--total-page-num (length symon-monitors)
          symon--timer-object
          (run-with-timer 0 symon-refresh-rate 'symon--next-frame))
    (advice-add #'current-message :around #'symon--current-message-advice)
    (advice-add #'message :around #'symon--message-advice)

    (add-hook 'post-command-hook 'symon--force-redisplay)
    (add-hook 'kill-emacs-hook 'symon--cleanup)
    (if (boundp 'after-focus-change-function)
        (add-function :before after-focus-change-function 'symon-clean-echo-area)
      (add-hook 'focus-in-hook 'symon-clean-echo-area)
      (add-hook 'focus-out-hook 'symon-clean-echo-area))))

(defun symon--cleanup ()
  (remove-hook 'kill-emacs-hook 'symon--cleanup)
  (remove-hook 'post-command-hook 'symon--force-redisplay)
  (cancel-timer symon--timer-object)
  (mapc 'funcall symon--cleanup-fns)
  (if (boundp 'after-focus-change-function)
      (remove-function after-focus-change-function 'symon-clean-echo-area)
    (remove-hook 'focus-out-hook 'symon-clean-echo-area)
    (remove-hook 'focus-in-hook 'symon-clean-echo-area))
  (advice-remove #'message #'symon--message-advice)
  (advice-remove #'current-message #'symon--current-message-advice))

(defun symon-clean-echo-area (&optional _ign)
  (clear-minibuffer-message))

(defun symon--available-space (cur-frame-width)
  (- cur-frame-width (string-width symon--symon-message)
     symon-total-spark-width
     (* 2 (length (bound-and-true-p exwm-systemtray--list)))))

(defun symon--minibuffer-width ()
  (window-body-width (minibuffer-window)))

(defun symon-compose-message (msg)
  (let* ((cur-frame-width (symon--minibuffer-width))
         (available-space (symon--available-space cur-frame-width)))
    (if (not (string-empty-p msg))
        (let* ((last-newline-pos (cl-position ?\n msg :from-end t))
               (last-line (if last-newline-pos
                              (substring msg (1+ last-newline-pos))
                            msg))
               (last-line-width (string-width last-line))
               (sep (cond
                     ((< available-space last-line-width)
                      (concat "\n" (make-string (max 0 available-space) ? )))
                     ((string-empty-p last-line)
                      (make-string (max 0 available-space) ? ))
                     (t
                      (make-string (- available-space last-line-width) ? )))))
          (when (/= cur-frame-width symon--last-frame-width)
            (setq symon--last-frame-width cur-frame-width)
            (clear-minibuffer-message))
          (concat msg sep symon--symon-message))
      (when (/= cur-frame-width symon--last-frame-width)
        (setq symon--last-frame-width cur-frame-width)
        (clear-minibuffer-message))
      (concat (if (< 0 available-space)
                  (make-string available-space ? )
                "")
              symon--symon-message))))

(defun symon-clean-message (msg)
  (if msg
      (replace-regexp-in-string
       "[[:space:]]*\\'" ""
       ;; (let ((pos (cl-search symon--symon-message msg)))
       ;;   (if pos
       ;;       (substring msg 0 pos)
       ;;     ;; (when (< (length symon--symon-message) (length msg))
       ;;     ;;   (message-log "Symon msg: <%s>" symon--symon-message)
       ;;     ;;   (message-log "Curr. msg: <%s>" msg))
       ;;     msg))
       (if (string-match-p "🖥" msg)
           (substring msg 0 (- (min (length msg) (1+ (length symon--symon-message)))))
         msg))
    ""))

(defun symon--message-advice (orig-fun format-string &rest args)
  (cond
   ;; force redisplay
   (symon--force-redisplay
    (let ((message-log-max nil)
          (msg (apply #'format format-string args)))
      (funcall orig-fun "%s"
               (symon-compose-message msg))))
   ;; original (message format args...) without symon message
   ((or ;; cursor-in-echo-area
        prefix-arg
        (< 0 (length (this-single-command-keys)))
        (active-minibuffer-window))
    (apply orig-fun format-string args))
   ;; actual (message nil) with symon message
   ((null format-string)
    (funcall orig-fun nil)
    (let ((message-log-max nil))
      (funcall orig-fun
               (concat
                (make-string (symon--available-space (symon--minibuffer-width)) ? )
                "%s")
               symon--symon-message))
    ;; return value
    nil)
   ;; actual (message format args...) with symon message
   (t
    (if message-log-max
        (let ((inhibit-message t))
          (apply orig-fun format-string args)))
    (let ((message-log-max nil)
          (msg (apply #'format format-string args)))
      (funcall orig-fun "%s"
               (symon-compose-message msg))
      ;; return value
      msg))))

(defun symon--current-message-advice (orig-fun)
  (symon-clean-message (funcall orig-fun)))

(defun symon--display-update ()
  "Update symon display."
  (unless (or ;; cursor-in-echo-area
              prefix-arg
              ;; (benchmark 100 (this-single-command-keys))
              ;; "Elapsed time: 0.000004s"
              ;; (benchmark 100 (this-single-command-raw-keys))
              ;; "Elapsed time: 0.000009s"
              (< 0 (length (this-single-command-keys)))
              (active-minibuffer-window))
    (let ((message-log-max nil)  ; do not insert to *Messages* buffer
          (display-string nil)
          (page 0))
      (dolist (lst symon--display-fns)
        (if (= page symon--active-page)
            (let ((msg (current-message)))
              (setq symon--symon-message (apply 'concat (mapcar 'funcall lst)))
              (message "%s" msg))
          (mapc 'funcall lst))
        (setq page (1+ page))))))

(defun symon--force-redisplay ()
  "Redisplay last display."
  (unless (or prefix-arg
              (active-minibuffer-window))
    (let ((symon--force-redisplay t))
      (message "%s" (current-message)))))

(defun symon--next-frame ()
  "Update symon display with next frame."
  (setq symon--active-page (% (1+ symon--active-page) symon--total-page-num))
  (symon--display-update))

;;;###autoload
(define-minor-mode symon-mode
  "Tiny graphical system monitor"
  :init-value nil
  :global t
  (if symon-mode (symon--initialize) (symon--cleanup)))

;; + provide

(provide 'symon)

;;; symon.el ends here
