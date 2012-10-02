;;; xterm-color.el --- ANSI & XTERM 256 color support

;; Copyright (C) 2010 xristos@sdf.lonestar.org
;; All rights reserved

;; Version: 1.0 - 2012-07-07
;; Author: xristos@sdf.lonestar.org
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;
;;   * Redistributions of source code must retain the above copyright
;;     notice, this list of conditions and the following disclaimer.
;;
;;   * Redistributions in binary form must reproduce the above
;;     copyright notice, this list of conditions and the following
;;     disclaimer in the documentation and/or other materials
;;     provided with the distribution.
;;
;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

;;; Commentary:
;;
;; Translates ANSI control sequences into text properties.
;;
;; * Regular ANSI
;; * XTERM 256 color
;;
;; xterm-color.el should perform much better than ansi-color.el
;;
;;; Install/Uninstall (comint):
;;
;; 
;; (progn (add-hook 'comint-preoutput-filter-functions 'xterm-color-filter)
;;        (setq comint-output-filter-functions (remove 'ansi-color-process-output comint-output-filter-functions))
;;        (setq font-lock-unfontify-region-function 'xterm-color-unfontify-region))
;; 
;; (progn (remove-hook 'comint-preoutput-filter-functions 'xterm-color-filter)
;;        (add-to-list 'comint-output-filter-functions 'ansi-color-process-output)
;;        (setq font-lock-unfontify-region-function 'font-lock-default-unfontify-region))
;;
;; 
;;; Test:
;;
;; M-x shell
;; wget http://www.frexx.de/xterm-256-notes/data/256colors2.pl
;; wget http://www.frexx.de/xterm-256-notes/data/xterm-colortest
;; perl xterm-colortest && perl 256colors2.pl
;;
;;; Code:

(require 'cl)

(defgroup xterm-color nil
  "Translates ANSI control sequences to text properties."
  :prefix "xterm-color-"
  :group 'processes)

;;
;; CUSTOM
;;

(defcustom xterm-color-debug t
  "Print ANSI state machine debug information in *Messages* if T.
  This becomes buffer-local whenever it is set."
  :type 'boolean
  :group 'xterm-color)

(make-variable-buffer-local 'xterm-color-debug)

(defcustom xterm-color-names
  ;; black     red       green    yellow    blue      magenta    cyan     gray
  ["#000000" "#c23621" "#25bc24" "#adad27" "#492ee1" "#d338d3" "#33bbc8" "#cbcccd"]
  "The default colors to use for regular ANSI colors."
  :type '(vector string string string string string string string string)
  :group 'xterm-color)

(defcustom xterm-color-names-bright
  ;; dark gray  red     green     yellow    blue      magenta   cyan      white
  ["#818383" "#fc391f" "#31e722" "#eaec23" "#5833ff" "#f935f8" "#14f0f0" "#e9ebeb"]
  "The default colors to use for bright ANSI colors."
  :type '(vector string string string string string string string string)
  :group 'xterm-color)

;;
;; Buffer locals, used by state machine
;; 

(defvar xterm-color-current nil
  "Hash table with current ANSI color (fg, bg).")

(make-variable-buffer-local 'xterm-color-current)

(defvar xterm-color-char-buffer ""
  "Buffer with characters that the current ANSI color applies to.
In order to avoid having per-character text properties, we grow this
buffer dynamically until we encounter an ANSI reset sequence.

Once that happens, we generate a single text property for the entire string.")

(make-variable-buffer-local 'xterm-color-char-buffer)

(defvar xterm-color-csi-buffer ""
  "Buffer with current ANSI CSI sequence bytes.")

(make-variable-buffer-local 'xterm-color-csi-buffer)

(defvar xterm-color-osc-buffer ""
  "Buffer with current ANSI OSC sequence bytes.")

(make-variable-buffer-local 'xterm-color-osc-buffer)

(defvar xterm-color-state :char
  "The current state of the ANSI sequence state machine.")

(make-variable-buffer-local 'xterm-color-state)

(defvar xterm-color-attributes 0)

(make-variable-buffer-local 'xterm-color-attributes)

(defconst +xterm-color-bright+    1)
(defconst +xterm-color-italic+    2)
(defconst +xterm-color-underline+ 4)
(defconst +xterm-color-strike+    8)
(defconst +xterm-color-negative+  16)


;;
;; Functions
;; 


(defun xterm-color-message (format-string &rest args)
  "Call `message' with FORMAT-STRING and ARGS if `xterm-color-debug' is T."
  (when xterm-color-debug
    (let ((message-truncate-lines t))
      (apply 'message format-string args)
      (message nil))))

(defun xterm-color-unfontify-region (beg end)
  "Replacement function for `font-lock-default-unfontify-region'.
When font-lock is active in a buffer, you cannot simply add
face text properties to the buffer.  Font-lock will remove the face
text property using `font-lock-unfontify-region-function'.  If you want
to insert the string returned by `xterm-color-filter' into such buffers,
you must set `font-lock-unfontify-region-function' to
`xterm-color-unfontify-region'.  This function will not remove all face
text properties unconditionally.  It will keep the face text properties
if the property `xterm-color' is set. A possible way to install this would be:

\(add-hook 'font-lock-mode-hook
	  \(function (lambda ()
		      \(setq font-lock-unfontify-region-function
			    'xterm-color-unfontify-region))))"
  (when (boundp 'font-lock-syntactic-keywords)
    (remove-text-properties beg end '(syntax-table nil)))
  (while (setq beg (text-property-not-all beg end 'face nil))
    (setq beg (or (text-property-not-all beg end 'xterm-color t) end))
    (when (get-text-property beg 'face)
      (let ((end-face (or (text-property-any beg end 'face nil)
			  end)))
	(remove-text-properties beg end-face '(face nil))
	(setq beg end-face)))))


(defun xterm-color-dispatch-csi (csi)
  (labels ((is-set? (attrib)
              (> (logior attrib xterm-color-attributes) 0))
            (dispatch-SGR (elems)
              (let ((init (first elems)))
                (cond ((= 0 init)
                       ;; Reset
                       (clrhash xterm-color-current)
                       (setq xterm-color-attributes 0)
                       (rest elems))
                      ((= 38 init)
                       ;; XTERM 256 FG color
                       (setf (gethash 'foreground-color xterm-color-current) (xterm-color-256 (third elems)))
                       (cdddr elems))
                      ((= 48 init)
                       ;; XTERM 256 BG color
                       (setf (gethash 'background-color xterm-color-current) (xterm-color-256 (third elems)))
                       (cdddr elems))
                      ((= 39 init)
                       ;; Reset to default FG color
                       (remhash 'foreground-color xterm-color-current)
                       (cdr elems))
                      ((= 49 init)
                       ;; Reset to default BG color
                       (remhash 'background-color xterm-color-current)
                       (cdr elems))
                      ((and (>= init 30)
                            (<= init 37))
                       ;; ANSI FG color
                       (setf (gethash 'foreground-color xterm-color-current) (- init 30))
                       (cdr elems))
                      ((and (>= init 40)
                            (<= init 47))
                       ;; ANSI BG color
                       (setf (gethash 'background-color xterm-color-current) (- init 40))
                       (cdr elems))
                      ((= 1 init)
                       ;; Bright color
                       (setq xterm-color-attributes (logior xterm-color-attributes
                                                            +xterm-color-bright+))
                       (cdr elems))
                      ((= 2 init)
                       ;; Faint color, emulated as normal intensity
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-bright+)))
                       (cdr elems))
                      ((= 3 init)
                       ;; Italic
                       (setq xterm-color-attributes (logior xterm-color-attributes
                                                            +xterm-color-italic+))
                       (cdr elems))
                      ((= 4 init)
                       ;; Underline
                       (setq xterm-color-attributes (logior xterm-color-attributes
                                                            +xterm-color-underline+))
                       (cdr elems))
                      ((= 7 init)
                       ;; Negative
                       (setq xterm-color-attributes (logior xterm-color-attributes
                                                            +xterm-color-negative+))
                       (cdr elems))
                      ((= 9 init)
                       ;; Strike
                       (setq xterm-color-attributes (logior xterm-color-attributes
                                                            +xterm-color-strike+))
                       (cdr elems))
                      ((= 22 init)
                       ;; Normal intensity
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-bright+)))
                       (cdr elems))
                      ((= 23 init)
                       ;; No italic
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-italic+)))
                       (cdr elems))
                      ((= 24 init)
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-underline+)))
                       (cdr elems))
                      ((= 27 init)
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-negative+)))
                       (cdr elems))
                      ((= 29 init)
                       (setq xterm-color-attributes (logand xterm-color-attributes
                                                            (lognot +xterm-color-strike+)))
                       (cdr elems))
                      (t (xterm-color-message "xterm-color: not implemented SGR attribute %s" init)
                         (cdr elems))))))
    (let* ((len (length csi))
           (term (aref csi (1- len))))
      (cond ((= ?m term)
             ;; SGR
             (if (= len 1)
                 (setq csi "0")
               (setq csi (substring csi 0 (1- len))))
             (let ((elems (mapcar 'string-to-number (split-string csi ";"))))
               (while elems
                 (setq elems (dispatch-SGR elems)))))
            ((= ?J term)
             ;; Clear screen
             (xterm-color-message "xterm-color: %s CSI not implemented (clear screen)" csi))
            ((= ?C term)
             (let ((num (string-to-number (substring csi 0 (1- len)))))
               (setq xterm-color-char-buffer
                     (concat xterm-color-char-buffer
                             (make-string num 32)))))
            (t
             (xterm-color-message "xterm-color: %s CSI not implemented" csi))))))


(defun xterm-color-dispatch-osc (osc)
  ;; Do nothing, for now
  )

(defun xterm-color-256 (color)
  (cond ((and (>= color 232)
              (<= color 255))
         ;; Greyscale
         (let ((val (+ 8 (* (- color 232) 10))))
           (format "#%02x%02x%02x"
                   val val val)))
        ((<= color 7)
         ;; Normal ANSI color
         (aref xterm-color-names color))
        ((and (>= color 8)
              (<= color 15))
         ;; Bright ANSI color
         (aref xterm-color-names-bright (- color 8)))
        (t (let* ((color-table [0 #x5f #x87 #xaf #xd7 #xff])
                  (color (- color 16))
                  (red (/ color 36))
                  (color (mod color 36))
                  (green (/ color 6))
                  (color (mod color 6))
                  (blue color))
             ;; XTERM 256 color
             (format "#%02x%02x%02x"
                     (aref color-table red)
                     (aref color-table green)
                     (aref color-table blue))))))

(defun xterm-color-make-property ()
  (let ((ret nil)
        (fg (gethash 'foreground-color xterm-color-current))
        (bg (gethash 'background-color xterm-color-current)))
    (macrolet ((get-color (color)
                `(if (stringp ,color)
                     ,color
                   (aref xterm-color-names ,color))))
      (when fg
        (push `(foreground-color . ,(get-color fg)) ret))
      (when bg
        (push `(background-color . ,(get-color bg)) ret)))
    ret))

(defun xterm-color-filter (string)
  "Translate ANSI color sequences in STRING into text properties.
Returns new STRING with text properties applied.

This can be inserted into `comint-preoutput-filter-functions'.
Also see `xterm-color-unfontify-region'."
  (when (null xterm-color-current)
    (setq xterm-color-current (make-hash-table)))
  (let ((result nil))
    (macrolet ((insert (x) `(push ,x result))
               (update (x place) `(setq ,place (concat ,place (string ,x))))
               (new-state (state) `(setq xterm-color-state ,state))
               (has-color? () `(or (> (hash-table-count xterm-color-current) 0)
                                   (not (= xterm-color-attributes 0))))
               (maybe-fontify ()
                `(when (> (length xterm-color-char-buffer) 0)
                   (if (has-color?)
                       (insert (propertize xterm-color-char-buffer 'xterm-color t
                                           'face (xterm-color-make-property)))
                    (insert xterm-color-char-buffer))
                  (setq xterm-color-char-buffer ""))))
      (loop for char across string do
            (case xterm-color-state
              (:char
               (cond
                ((= char 27)            ; ESC
                 (maybe-fontify)
                 (new-state :ansi-esc))
                (t
                 (if (has-color?)
                     (update char xterm-color-char-buffer)
                   (insert (string char))))))
              (:ansi-esc
               (cond ((= char ?\[)
                      (new-state :ansi-csi))
                     ((= char ?\])
                      (new-state :ansi-osc))
                     (t
                      (update char xterm-color-char-buffer)
                      (new-state :char))))
              (:ansi-csi
               (update char xterm-color-csi-buffer)
               (when (and (>= char #x40)
                          (<= char #x7e))
                 ;; Dispatch
                 (xterm-color-dispatch-csi xterm-color-csi-buffer)
                 (setq xterm-color-csi-buffer "")
                 (new-state :char)))
              (:ansi-osc
               ;; Read entire sequence
               (update char xterm-color-osc-buffer)
               (cond ((= char 7)
                      ;; BEL
                      (xterm-color-dispatch-osc xterm-color-osc-buffer)
                      (setq xterm-color-osc-buffer "")
                      (new-state :char))
                     ((= char 27)
                      ;; ESC
                      (new-state :ansi-osc-esc))))
              (:ansi-osc-esc
               (update char xterm-color-osc-buffer)
               (cond ((= char ?\\)
                      (xterm-color-dispatch-osc xterm-color-osc-buffer)
                      (setq xterm-color-osc-buffer "")
                      (new-state :char))
                     (t (new-state :ansi-osc))))))
      (when (eq xterm-color-state :char) (maybe-fontify)))
    (mapconcat 'identity (nreverse result) "")))

(provide 'xterm-color)
;;; xterm-color.el ends here
