;;; xterm-color.el --- ANSI, XTERM 256 and Truecolor support -*- lexical-binding: t -*-

;; Copyright (C) 2010-2020 xristos@sdf.org
;; All rights reserved

;; Version: 1.9 - 2019-08-15
;; Author: xristos <xristos@sdf.org>
;; URL: https://github.com/atomontage/xterm-color
;; Package-Requires: ((cl-lib "0.5"))
;; Keywords: faces

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
;; ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

;;; Commentary:
;;
;; Translate ANSI control sequences into text properties.
;;
;; * Regular ANSI colors
;;
;; * XTERM 256 colors
;;
;; * Truecolor (24-bit)
;;
;; * AIXTERM bright foreground color
;;
;; * AIXTERM bright background color (since 1.8)
;;
;; * Use bold for bright (since 1.8)
;;
;; * Works with compilation-mode
;;
;; * Works with eshell
;;
;; * More accurate than ansi-color.el
;;
;; * Should perform much better than ansi-color.el
;;
;;; Usage:
;;
;; Interactively or from Emacs Lisp call xterm-color-colorize-buffer
;; to colorize an entire buffer.
;;
;; In Emacs Lisp, call xterm-color-filter to propertize strings that you can
;; then insert into a buffer. All state is kept in buffer-local variables
;; which means that control sequences can span xterm-color-filter calls.
;;
;; You may customize `xterm-color-debug' (default NIL, if T you will get warnings
;; in *Messages* when unsupported escape sequences are encountered),
;; `xterm-color-use-bold-for-bright' (default NIL), `xterm-color-names',
;; `xterm-color-names-bright'. Additionally, you may set `xterm-color-preserve-properties'
;; to T (default NIL, should be set to T if using xterm-color with eshell, see below).
;;
;; A buffer-local face attribute cache is used since 1.8 to improve performance.
;; This means that if changes are made to `xterm-color-names' or `xterm-color-names-bright'
;; or `xterm-color-use-bold-for-bright' at runtime, `xterm-color-clear-cache'
;; should be called in a buffer with activated xterm-color for changes to take
;; effect in that buffer.
;;
;; Example:
;;
;; (let ((buffer (generate-new-buffer "*xterm-color-test*")))
;;   (with-current-buffer buffer
;;     (insert (xterm-color-filter "\x1b[0;1;3;4"))
;;     (insert (xterm-color-filter ";35"))
;;     (insert (xterm-color-filter ";51mThis is only a test"))
;;     (insert (xterm-color-filter "\x1b[0m")))
;;   (switch-to-buffer buffer))
;;
;; * You can replace ansi-color.el with xterm-color for all comint buffers,
;;   but this may create problems with modes that propertize strings
;;   and feed them through comint-preoutput-filter-functions since xterm-color-filter
;;   will strip all text properties.
;;
;;   The recommended configuration is to remove ansi-color-process-output from
;;   comint-output-filter-functions and add xterm-color-filter as the *first*
;;   hook in the *buffer-local* comint-preoutput-filter-functions for any comint-based
;;   mode that you would like it to affect (e.g. shell-mode).
;;
;;   Additionally, it is recommended to disable font-locking for shell-mode buffers since
;;   it interacts badly with comint and drastically affects performance
;;   (https://github.com/atomontage/xterm-color/issues/28).
;;
;;   Font locking in shell-mode buffers is superfluous since xterm-color.el will handle
;;   faces fine by itself.
;;
;;   An example configuration for shell-mode (M-x shell) is shown below:
;;
;; (setq comint-output-filter-functions
;;       (remove 'ansi-color-process-output comint-output-filter-functions))
;;
;; (add-hook 'shell-mode-hook
;;           (lambda ()
;;             ;; Disable font-locking in this buffer to improve performance
;;             (font-lock-mode -1)
;;             ;; Prevent font-locking from being re-enabled in this buffer
;;             (make-local-variable 'font-lock-function)
;;             (setq font-lock-function (lambda (_) nil))
;;             (add-hook 'comint-preoutput-filter-functions 'xterm-color-filter nil t)))
;;
;; Also set TERM accordingly (xterm-256color) in the shell itself.
;;
;; * An example configuration for eshell
;;
;; (require 'eshell) ; or use with-eval-after-load
;;
;; (add-hook 'eshell-before-prompt-hook
;;           (lambda ()
;;             (setq xterm-color-preserve-properties t)))
;;
;;  (add-to-list 'eshell-preoutput-filter-functions 'xterm-color-filter)
;;  (setq eshell-output-filter-functions (remove 'eshell-handle-ansi-color eshell-output-filter-functions))
;;  (setenv "TERM" "xterm-256color")
;;
;; * Compilation buffers
;;
;; Using `compilation-shell-minor-mode' with shell-mode buffers that have xterm-color
;; enabled is NOT recommended, as `compilation-shell-minor-mode' depends on font-locking
;; and causes severe performance degradation. Omit the statements that disable
;; font-locking in the previously given shell-mode example configuration if you
;; need it.
;;
;; For standalone compilation-mode buffers use the following configuration:
;;
;; (setq compilation-environment '("TERM=xterm-256color"))
;;
;; (defun my/advice-compilation-filter (f proc string)
;;   (funcall f proc (xterm-color-filter string)))
;;
;; (advice-add 'compilation-filter :around #'my/advice-compilation-filter)
;;
;;; Notes:
;;
;; Unsupported SGR attributes: 5 (slow blink), 6 (rapid blink), 8 (conceal),
;; 10 (primary font), 11-19 (alternative font), 20 (fraktur), 21 (double underline),
;; 25 (blink off), 29 (reveal), 52 (encircled), 60-65 (ideogram)
;;
;; Most of these can not be mapped to Emacs face properties. The rest may be
;; supported in a future release.
;;
;; Supported SGR attributes: Look at `xterm-color--dispatch-SGR'.
;; SGR attribute 1 is rendered as bright unless `xterm-color-use-bold-for-bright'
;; is T which will, if current Emacs font has a bold variant, switch to bold.
;; SGR attributes 38 and 48 are supported in both their 256 color and truecolor
;; (24-bit) variants.

;;; Test:
;;
;; M-x xterm-color-test
;;
;; In shell or eshell:
;;
;; perl tests/xterm-colortest && perl tests/256colors2.pl
;;
;; printf "\x1b[0;1;3;4;35;51mThis is only a test\x1b[0m\n"
;;
;; Comparison with ansi-color.el:
;;
;; M-x xterm-color-test-raw then M-x xterm-color-colorize-buffer
;;
;; and contrast with
;;
;; M-x xterm-color-test-raw then M-: (ansi-color-apply-on-region (point-min) (point-max))
;;
;; Use `xterm-color--bench' for benchmarks during development.

;;; Code:

(require 'subr-x)
(require 'cl-lib)

(defgroup xterm-color nil
  "Translate ANSI control sequences to text properties."
  :prefix "xterm-color-"
  :group 'processes)


;;;
;;; CUSTOM
;;;


(defcustom xterm-color-debug nil
  "Print ANSI state machine debug information in *Messages* if not NIL."
  :type 'boolean
  :group 'xterm-color)

(defcustom xterm-color-use-bold-for-bright nil
  "Render bright foreground attribute as bold."
  :type 'boolean
  :group 'xterm-color)

(defcustom xterm-color-names
  ["#192033"    ; black
   "#A93F43"    ; red
   "#59963A"    ; green
   "#BE8A2D"    ; yellow
   "#4068A3"    ; blue
   "#7F60A7"    ; magenta
   "#4E9B9B"    ; cyan
   "#7E8A90"]   ; white
  "Default colors to use as regular ANSI colors."
  :type '(vector string string string string string string string string)
  :group 'xterm-color)

(defcustom xterm-color-names-bright
  ["#666666"    ; black
   "#EC6261"    ; red
   "#ADCF44"    ; green
   "#F0C649"    ; yellow
   "#63B4F6"    ; blue
   "#CB77F9"    ; magenta
   "#86D7DB"    ; cyan
   "#D3D2D1"]   ; white
  "Default colors to use as bright ANSI colors."
  :type '(vector string string string string string string string string)
  :group 'xterm-color)


;;;
;;; Buffer locals, used by state machine
;;;


(defvar xterm-color-preserve-properties nil
  "If T, preserve existing text properties on input about to be filtered.
This should be NIL most of the time. It is really meant for and works
ok with eshell.")

(make-variable-buffer-local 'xterm-color-preserve-properties)

(defvar xterm-color--current-fg nil)

(make-variable-buffer-local 'xterm-color--current-fg)

(defvar xterm-color--current-bg nil)

(make-variable-buffer-local 'xterm-color--current-bg)

(defvar xterm-color--char-list nil
  "List of characters that the current ANSI color applies to.
All characters are stored in reverse, LIFO, order.")

(make-variable-buffer-local 'xterm-color--char-list)

(defvar xterm-color--CSI-list nil
  "List of current ANSI CSI sequence bytes (characters).
All characters are stored in reverse, LIFO, order.")

(make-variable-buffer-local 'xterm-color--CSI-list)

(defvar xterm-color--state :char
  "Current state of ANSI sequence state machine.
Can be one of :char, :ansi-esc, :ansi-csi, :ansi-osc, :ansi-osc-esc.")

(make-variable-buffer-local 'xterm-color--state)

(defvar xterm-color--attributes 0
  "Bitvector that keeps track of bright, italic, underline, strike-through,
inverse-color, frame, overline SGR state machine bits.")

(make-variable-buffer-local 'xterm-color--attributes)

(defvar xterm-color--face-cache nil
  "Cache for auto-generated face attributes.")

(make-variable-buffer-local 'xterm-color--face-cache)

(defvar xterm-color--truecolor-face-cache nil
  "Cache for auto-generated face attributes.")

(make-variable-buffer-local 'xterm-color--truecolor-face-cache)


;;;
;;; Constants
;;;


(defconst +xterm-color--table-256+ [0 #x5f #x87 #xaf #xd7 #xff])


;;;
;;; Internal API
;;;

;; The face caching scheme requires an integer width of at least 56 bits
;; to cache faces derived from truecolor (24-bit) ANSI sequences. Truecolor
;; support is therefore disabled on e.g. machines with 32-bit integers.
(defvar xterm-color--support-truecolor (>= most-positive-fixnum (1- (expt 2 56.0))))

(cl-defun xterm-color--string-properties (string)
  (cl-loop
   with pos = 0 and result do
   (let ((next-pos (next-property-change pos string)))
     (if next-pos
         (progn
           (push (list pos (text-properties-at pos string) (substring string pos next-pos)) result)
           (setq pos next-pos))
       (push (list pos (text-properties-at pos string) (substring string pos)) result)
       (cl-return-from xterm-color--string-properties (nreverse result))))))

(defun xterm-color--convert-text-properties-to-overlays (beg end)
  "Delete face text properties between BEG and END, replacing with equivalent overlays."
  (save-excursion
    (goto-char beg)
    (let ((face-prop (if (or (get-text-property (point) 'font-lock-face)
                             (next-single-property-change (point) 'font-lock-face))
                         'font-lock-face 'face)))
      (while (< (point) end)
        (let* ((pos (point))
               (current-value (get-text-property pos face-prop))
               (next-change (next-single-property-change pos face-prop nil end)))
          (when current-value
            (let ((ov (make-overlay pos next-change)))
              (overlay-put ov face-prop current-value)
              (overlay-put ov 'xterm-color t)))
          (goto-char next-change)))
      (remove-text-properties beg end (list 'xterm-color nil face-prop nil)))))

(defun xterm-color--message (format-string &rest args)
  "Call `message' with FORMAT-STRING and ARGS if `xterm-color-debug' is not NIL."
  (when xterm-color-debug
    (let ((message-truncate-lines t))
      (message "xterm-color: %s" (apply 'format format-string args))
      (message nil))))


;;;
;;; SGR state machine
;;;


(cl-defmacro xterm-color--with-SGR-constants (&body body)
  (declare (indent defun))
  `(cl-symbol-macrolet
       ((+bright+           1)
        (+italic+           2)
        (+underline+        4)
        (+strike-through+   8)
        (+negative+        16)
        (+frame+           32)
        (+overline+        64))
     ,@body))

(cl-defmacro xterm-color--create-SGR-table ((attrib SGR-list) &body body)
  "Create an iteration/dispatch table based on provided rules that match SGR attributes.
For each attribute in SGR-LIST, check to see if it matches a rule in BODY and
evaluate the rule body if that is the case.

ATTRIB should be a symbol that will be bound to SGR-LIST attributes in BODY.
SGR-LIST should be a list of SGR attributes (integers) in LIFO order.
BODY should contain rules with each rule being a list of form:

 (:match (condition &key (skip 1)) rule-body-form..)

CONDITION should be a Lisp form which will be evaluated as part of a COND
condition clause. If it is an atom, it will be rewritten to (= CONDITION ATTRIB).
Otherwise it will be used as is. As per COND statement, if CONDITION evaluates
to T, rule body forms will be evaluated as part of the body of the COND clause.
SKIP, if given, should be an integer specifying the number of elements that should
be skipped before the next iteration. The default is 1, going down SGR-LIST
one element at a time."
  (declare (indent defun))
  `(xterm-color--with-SGR-constants
     (cl-macrolet
         ;; The following macros should be used in rule bodies
         ((set-a! (attr)   `(setq xterm-color--attributes
                                  (logior xterm-color--attributes ,attr)))
          (unset-a! (attr) `(setq xterm-color--attributes
                                  (logand xterm-color--attributes
                                          (logand #xff (lognot ,attr)))))

          (set-f! (fg-color) `(setq xterm-color--current-fg ,fg-color))
          (set-b! (bg-color) `(setq xterm-color--current-bg ,bg-color))

          (set-truecolor! (r g b current-color)
                          ;; We want a single integer to be able to
                          ;; hold and distinguish between:
                          ;;
                          ;; - 24bit truecolor values
                          ;; - ANSI colors
                          ;; - XTerm 256 colors
                          ;;
                          ;; The following packing scheme achieves that.
                          `(setq ,current-color
                                 (logior (ash r 25) (ash g 17) (ash b 9)
                                         #x100)))

          (reset! ()      `(setq xterm-color--current-fg nil
                                 xterm-color--current-bg nil
                                 xterm-color--attributes 0)))
       (cl-loop
        for ,attrib = (cl-first ,SGR-list)
        while ,SGR-list do
        (cond
         ,@(cl-loop
            for skip = 1
            for (tag (c . rest) . rule-body) in body
            when (not (eq tag :match)) do
            (error "Rule (%s (%s..)..) does not start with :match" tag c)
            when rest do
            (setq skip (plist-get rest :skip))
            (when (or (null skip) (cddr rest))
              (error "Rule (%s (%s..)..) has malformed arguments: %s" tag c rest))
            ;; Condition part of COND
            collect `(,(if (atom c) `(= ,c ,attrib) c)
                      ;; Body of COND
                      ,@rule-body
                      (setq ,SGR-list
                            ,(if (> skip 1)
                                 `(nthcdr ,skip ,SGR-list)
                               `(cdr ,SGR-list)))))
         (t (xterm-color--message "Not implemented SGR attribute %s" ,attrib)
            (setq ,SGR-list (cdr ,SGR-list))))))))

(defsubst xterm-color--dispatch-SGR (SGR-list)
  "Update state machine based on SGR-LIST which should be a list of SGR attributes (integers)."
  (xterm-color--create-SGR-table (elem SGR-list)
    (:match (0)  (reset!))                              ; RESET everything

    (:match ((<= 30 elem 37)) (set-f! (- elem 30)))     ; ANSI FG color
    (:match ((<= 40 elem 47)) (set-b! (- elem 40)))     ; ANSI BG color

    (:match (39) (set-f!   nil))                        ; RESET FG color (switch to default)
    (:match (49) (set-b!   nil))                        ; RESET BG color (switch to default)
    (:match (1)  (set-a!   +bright+))
    (:match (2)  (unset-a! +bright+))
    (:match (3)  (set-a!   +italic+))
    (:match (4)  (set-a!   +underline+))
    (:match (7)  (set-a!   +negative+))
    (:match (9)  (set-a!   +strike-through+))
    (:match (22) (unset-a! +bright+))
    (:match (23) (unset-a! +italic+))
    (:match (24) (unset-a! +underline+))
    (:match (27) (unset-a! +negative+))
    (:match (29) (unset-a! +strike-through+))

    (:match ((and (eq 38 (cl-first SGR-list))
                  (eq 2 (cl-second SGR-list)))          ; Truecolor (24-bit) FG color
             :skip 5)
            (when xterm-color--support-truecolor
              (if-let ((r (cl-third SGR-list))
                       (g (cl-fourth SGR-list))
                       (b (cl-fifth SGR-list)))
                  (if (or (> r 255) (> g 255) (> b 255))
                      (xterm-color--message "SGR 38;2;%s;%s;%s exceeds range"
                                            r g b)
                    (set-truecolor! r g b xterm-color--current-fg))
                (xterm-color--message "SGR 38;2;%s;%s;%s error, expected 38;2;R;G;B"
                                      r g b))))

    (:match ((and (eq 48 (cl-first SGR-list))
                  (eq 2 (cl-second SGR-list)))          ; Truecolor (24-bit) BG color
             :skip 5)
            (when xterm-color--support-truecolor
              (if-let ((r (cl-third SGR-list))
                       (g (cl-fourth SGR-list))
                       (b (cl-fifth SGR-list)))
                (if (or (> r 255) (> g 255) (> b 255))
                    (xterm-color--message "SGR 48;2;%s;%s;%s exceeds range"
                                          r g b)
                  (set-truecolor! r g b xterm-color--current-bg))
                (xterm-color--message "SGR 48;2;%s;%s;%s error, expected 48;2;R;G;B"
                                      r g b))))

    (:match ((and (eq 38 (cl-first SGR-list))
                  (eq 5 (cl-second SGR-list)))
             :skip 3)                                   ; XTERM 256 FG color
            (if-let ((color (cl-third SGR-list)))
                (if (> color 255)
                    (xterm-color--message "SGR 38;5;%s exceeds range" color)
                  (set-f! color))
              (xterm-color--message "SGR 38;5;%s error, expected 38;5;COLOR"
                                    color)))
    (:match ((and (eq 48 (cl-first SGR-list))
                  (eq 5 (cl-second SGR-list)))
             :skip 3)                                   ; XTERM 256 BG color
            (if-let ((color (cl-third SGR-list)))
              (if (> color 255)
                  (xterm-color--message "SGR 48;5;%s exceeds range" color)
                (set-b! color))
              (xterm-color--message "SGR 48;5;%s error, expected 48;5;COLOR"
                                    color)))

    (:match (51) (set-a!   +frame+))
    (:match (53) (set-a!   +overline+))
    (:match (54) (unset-a! +frame+))
    (:match (55) (unset-a! +overline+))
    (:match ((<= 90 elem 97))                           ; AIXTERM hi-intensity FG
            ;; Rather than setting bright, which would be wrong,
            ;; rescale color to fall within 8-15 so that it gets
            ;; mapped to xterm-color-names-bright by xterm-color-256
            (set-f! (- elem 82)))
    ;; Same for BG, rescale to 8-15
    (:match ((<= 100 elem 107)) (set-b! (- elem 92))))) ; AIXTERM hi-intensity BG

(defsubst xterm-color--SGR-attributes (list)
  "Convert LIFO list of SGR characters to FIFO list of SGR attributes (integers).

Returns FIFO list of SGR attributes or NIL on errors.

Characters should be in the ASCII set 0-9 (decimal 48 to 57) and are converted
to integer digits by subtracting 48 from each character. E.g. Character 48
is converted to integer digit 0, character 49 to integer digit1..
Character 59 (;) is not converted but signifies that all accumulated integer
digits should be reversed and combined into a single integer (SGR attribute).

Examples:

Given (48) return (0)
Given (59) return (0)
Given (48 49 50) return (210)
Given (48 49 50 59 50 50 59 48 49) return (10 22 210)"
  (cl-loop
   with mul = 1 and num = 0 and ret
   for c    = (car list) while c do
   (if (/= 59 c)
       (let ((e (- c 48)))
         (unless (<= 0 e 9)
           (xterm-color--message "Invalid SGR attribute %s" c)
           (cl-return nil))
         (cl-incf num (* mul e))
         (setq mul (* mul 10)))
     (push num ret)
     (setq num 0 mul 1))
   (setq list (cdr list))
   finally return (push num ret)))


;;;
;;; CSI state machine
;;;


(defsubst xterm-color--dispatch-CSI ()
  "Update state machine based on CSI parameters collected so far.
Parameters are taken from `xterm-color--CSI-list' which stores them
in LIFO order."
  (let* ((csi xterm-color--CSI-list)
         (term (car csi))               ; final parameter, terminator
         (params (cdr csi)))            ; rest of parameters, LIFO order
    (setq xterm-color--CSI-list nil)
    (cond ((= ?m term)
           ;; SGR
           (let ((SGR-list (if (null params) '(0)
                             (xterm-color--SGR-attributes params))))
             (when SGR-list
               (xterm-color--dispatch-SGR SGR-list))))
          (t
           (xterm-color--message "%s CSI not implemented" csi)))))

(defmacro xterm-color--with-ANSI-macro-helpers (&rest body)
  (declare (indent defun))
  `(xterm-color--with-SGR-constants
     (cl-symbol-macrolet ((fg           xterm-color--current-fg)
                          (bg           xterm-color--current-bg)
                          (attrs        xterm-color--attributes)
                          (bold-bright  xterm-color-use-bold-for-bright))
       (cl-macrolet
           ((out! (x)            `(push ,x result))
            (push-char! (c)      `(push ,c xterm-color--char-list))
            (push-csi! (c)       `(push ,c xterm-color--CSI-list))

            (state! (s)          `(setq state ,s))
            (graphics? ()        `(or fg bg (/= attrs 0)))
            (has? (attr)         `(/= (logand ,attr attrs) 0))
            (unpack (color)      `(ash ,color -9))
            (truecolor (color)   `(format "#%06x" (unpack ,color)))
            (256color  (color)   `(xterm-color-256 ,color))
            (face-cache-get ()   `(let ((f (or fg 0))
                                        (b (or bg 0)))
                                    (if (and (< f 256) (< b 256))
                                        ;; Not truecolor
                                        (gethash (logior (ash attrs 16) (ash b 8) f)
                                                 xterm-color--face-cache)
                                      ;; Truecolor
                                      (gethash (logior (ash attrs 48)
                                                       (ash (unpack b) 24)
                                                       (unpack f))
                                               xterm-color--truecolor-face-cache))))
            (face! (k v)         `(setq plistf (plist-put plistf ,k ,v)))
            (make-color-fg ()    `(if (and bold-bright
                                           (< fg 256)
                                           (or (has? +bright+) (<= 8 fg 15)))
                                      (progn (face! :weight 'bold)
                                             (face! :foreground
                                                    (256color (if (<= 8 fg) (- fg 8) fg))))
                                    (face! :foreground
                                           (if (> fg 255)
                                               (truecolor fg)
                                             (256color (if (and (<= fg 7) (has? +bright+))
                                                           (+ fg 8)
                                                         fg))))))
            (make-color-bg ()    `(face! :background (if (> bg 255)
                                                         (truecolor bg)
                                                       (256color bg))))
            (make-face ()        `(or (face-cache-get)
                                      (let (plistf)
                                        (when (has? +italic+)         (face! :slant 'italic))
                                        (when (has? +underline+)      (face! :underline t))
                                        (when (has? +strike-through+) (face! :strike-through t))
                                        (when (has? +negative+)       (face! :inverse-video t))
                                        (when (has? +overline+)       (face! :overline t))
                                        (when (has? +frame+)          (face! :box t))

                                        (if fg
                                            (make-color-fg)
                                          (when (and bold-bright (has? +bright+))
                                            (face! :weight 'bold)))

                                        (when bg (make-color-bg))
                                        (setf (face-cache-get) plistf))))
            (maybe-fontify ()    '(when xterm-color--char-list
                                    (let ((s (concat (nreverse xterm-color--char-list))))
                                      (when (graphics?)
                                        (add-text-properties
                                         0 (length s)
                                         (list 'xterm-color t (if font-lock-mode
                                                                  'font-lock-face
                                                                'face)
                                               (make-face))
                                         s))
                                      (out! s))
                                    (setq xterm-color--char-list nil))))
         ,@body))))


;;;
;;; Exports
;;;


;;;###autoload
(defun xterm-color-filter-strip (string)
  "Translate ANSI color sequences in STRING into text properties.
Return new STRING with text properties applied.

This function strips text properties that may be present in STRING."
  (unless xterm-color--face-cache
    (setq xterm-color--face-cache
          (make-hash-table :weakness 'value)))
  (unless xterm-color--truecolor-face-cache
    (setq xterm-color--truecolor-face-cache
          (make-hash-table :weakness 'value)))
  (xterm-color--with-ANSI-macro-helpers
    (cl-loop
     with state = xterm-color--state and result
     for char across string do
     (cl-case state
       (:char
        (cond
         ((= char 27)                    ; ESC
          (maybe-fontify)
          (state! :ansi-esc))
         (t
          (if (graphics?)
              (push-char! char)
            (out! (string char))))))
       (:ansi-esc
        (cond ((= char ?\[)
               (state! :ansi-csi))
              ((= char ?\])
               (state! :ansi-osc))
              (t
               (push-char! char)
               (state! :char))))
       (:ansi-csi
        (push-csi! char)
        (when (and (>= char #x40)
                   (<= char #x7e))
          (xterm-color--dispatch-CSI)
          (state! :char)))
       (:ansi-osc
        ;; OSC sequences are skipped
        (cond ((= char 7)
               (state! :char))
              ((= char 27)
               ;; ESC
               (state! :ansi-osc-esc))))
       (:ansi-osc-esc
        (cond ((= char ?\\)
               (state! :char))
              (t (state! :ansi-osc)))))
     finally return
     (progn (when (eq state :char) (maybe-fontify))
            (setq xterm-color--state state)
            (mapconcat 'identity (nreverse result) "")))))

;;;###autoload
(defun xterm-color-filter (string)
  "Translate ANSI color sequences in STRING into text properties.
Return new STRING with text properties applied.

This function will check if `xterm-color-preserve-properties' is
set to T and only call `xterm-color-filter-strip' on substrings
that do not have text properties applied (passing through the rest
unmodified). Preserving properties in this fashion is not very robust
as there may be situations where text properties are applied on ANSI
data, which will desync the state machine. Preserving properties works
ok and is really meant for eshell.

This can be inserted into `comint-preoutput-filter-functions'."
  (if (not xterm-color-preserve-properties)
      (xterm-color-filter-strip string)
    (cl-loop
     with result
     for (_ props substring) in (xterm-color--string-properties string) do
     (push (if props substring (xterm-color-filter-strip substring))
           result)
     finally return (mapconcat 'identity (nreverse result) ""))))

;;;###autoload
(defun xterm-color-256 (color)
  (cond ((and (>= color 232)
              (<= color 255))
         ;; Grayscale
         (let ((val (+ 8 (* (- color 232) 10))))
           (format "#%02x%02x%02x" val val val)))
        ((<= color 7)
         ;; Normal ANSI color
         (aref xterm-color-names color))
        ((and (>= color 8)
              (<= color 15))
         ;; Bright ANSI color
         (aref xterm-color-names-bright (- color 8)))
        (t (let* ((color  (- color 16))
                  (red    (/ color 36))
                  (color  (mod color 36))
                  (green  (/ color 6))
                  (color  (mod color 6))
                  (blue   color))
             ;; XTERM 256 color
             (format "#%02x%02x%02x"
                     (aref +xterm-color--table-256+ red)
                     (aref +xterm-color--table-256+ green)
                     (aref +xterm-color--table-256+ blue))))))


;;;
;;; Interactive
;;;


;;;###autoload
(cl-defun xterm-color-colorize-buffer (&optional use-overlays)
  "Apply `xterm-color-filter' to current buffer, and replace its contents.

The colors will be applied using 'font-lock-face, unless
font-lock-mode is inactive, in which case 'face will be used.

If USE-OVERLAYS is non-nil then the colors will be applied to
the buffer using overlays instead of text properties. A C-u
prefix arg causes overlays to be used."
  (interactive "P")
  (let ((read-only-p buffer-read-only))
    (when read-only-p
      (unless (y-or-n-p "Buffer is read only, continue colorizing? ")
        (cl-return-from xterm-color-colorize-buffer))
      (read-only-mode -1))
    (insert (xterm-color-filter (delete-and-extract-region (point-min) (point-max))))
    (when use-overlays
        (xterm-color--convert-text-properties-to-overlays (point-min) (point-max)))
    (goto-char (point-min))
    (when read-only-p (read-only-mode 1))))

;;;###autoload
(defun xterm-color-clear-cache ()
  "Clear xterm color face attribute cache.
You may want to call this if you change `xterm-color-names' or
`xterm-color-names-bright' at runtime and you want to see the changes
take place in a pre-existing buffer that has had xterm-color initialized.

Since the cache is buffer-local and created on-demand when needed, this has no
effect when called from a buffer that does not have a cache."
  (interactive)
  (and xterm-color--face-cache
       (clrhash xterm-color--face-cache)
       (xterm-color--message "Cleared face attribute cache"))
  (and xterm-color--truecolor-face-cache
       (clrhash xterm-color--truecolor-face-cache)
       (xterm-color--message "Cleared truecolor face attribute cache")))


;;;
;;; Tests
;;;


(defmacro xterm-color--bench (path &optional repetitions)
  `(benchmark-run-compiled ,repetitions
     (with-temp-buffer
       (insert-file-contents-literally ,path)
       (xterm-color-colorize-buffer))))

(defvar xterm-color--test-do-filter t)

(cl-defmacro xterm-color--with-tests (&body body)
  `(cl-labels ((ansi-filter (msg &rest args)
                            (insert
                             (if xterm-color--test-do-filter
                                 (xterm-color-filter
                                  (apply 'format msg args))
                               (apply 'format msg args))))
               (test (name &rest attribs)
                     (ansi-filter "\x1b[0;%smThis is only a test!\x1b[0m\t --[ %s\n"
                                  (mapconcat 'identity attribs ";")
                                  name)))
     ,@body))

(defun xterm-color--test-ansi ()
  (xterm-color--with-tests
   (let ((test-attributes
          '(("1"    . "bright")
            ("51"   . "frame")
            ("3"    . "italic")
            ("4"    . "underline")
            ("7"    . "negative")
            ("9"    . "strike through")
            ("53"   . "overline")
            ("1;51" . "bright + frame")
            ("1;3"  . "bright + italic")
            ("1;4"  . "bright + underline")
            ("1;7"  . "bright + negative")
            ("1;9"  . "bright + strike through")
            ("1;53" . "bright + overline"))))

     ;; Attributes (no color)
     (insert "* ANSI attributes (default colors)\n")

     (if xterm-color-use-bold-for-bright
         (insert "  Expect: Bold instead of bright, if current Emacs font has bold variant")
       (insert "  Expect: Bright not to be rendered since no foreground color is set"))
     (insert "\n\n")

     (cl-loop for (attrib . name) in test-attributes
              do (test name attrib)
              finally (insert "\n"))

     (insert "* ANSI attributes (blue foreground)\n")

     (if xterm-color-use-bold-for-bright
         (insert "  Expect: Bold instead of bright, if current Emacs font has bold variant")
       (insert "  Expect: Bright rendered as bright color"))
     (insert "\n\n")

     (cl-loop for (attrib . name) in test-attributes
              do (test name "34" attrib)
              finally (insert "\n"))

     (insert "* ANSI attributes (blue background)\n")

     (if xterm-color-use-bold-for-bright
         (insert "  Expect: Bold instead of bright, if current Emacs font has bold variant")
       (insert "  Expect: Bright not to be rendered since no foreground color is set"))
     (insert "\n\n")

     (cl-loop for (attrib . name) in test-attributes
              do (test name "44" attrib)
              finally (insert "\n"))

     (insert "* ANSI attributes (AIXTERM blue foreground)\n")

     (if xterm-color-use-bold-for-bright
         (insert "  Expect: Bold instead of bright, if current Emacs font has bold variant")
       (insert "  Expect: Bright color everywhere due to AIXTERM"))
     (insert "\n\n")

     (cl-loop for (attrib . name) in test-attributes
              do (test name "94" attrib)
              finally (insert "\n"))

     (insert "* ANSI attributes (AIXTERM red background)\n")
     (insert "  Expect: Bright background color due to AIXTERM\n")
     (if xterm-color-use-bold-for-bright
         (insert "  Expect: Bold instead of bright for foreground, if current Emacs font has bold variant\n\n")
       (insert "\n"))

     (cl-loop for (attrib . name) in test-attributes
              do (test name "101" attrib)
              finally (insert "\n"))

     (insert "* Misc\n")
     (if xterm-color-use-bold-for-bright
         (progn
           (insert "  Expect: Bold instead of bright, if current Emacs font has bold variant\n")
           (insert "          Otherwise bright rendered as normal intensity\n\n"))
       (insert "\n"))

     (ansi-filter "Default \x1b[34;1mBright blue\x1b[39m Reset-fg-color \x1b[34mBlue (should be bright)\x1b[0m\t --[ Resetting FG color should not affect other SGR bits\n")
     (ansi-filter "Default \x1b[94mBright blue\x1b[34m Switch-to-blue (should be normal intensity)\x1b[0m\t --[ AIXTERM bright color should not set bright SGR bit\n")
     (insert "\n"))))

(defmacro xterm-color--test-truecolor ()
  `(cl-flet ((insert-truecolor-sequences
              (rgb-fn)
              (dolist (seq (list (number-sequence 0 127)
                                 (reverse (number-sequence 255 128))))
                (dolist (i seq)
                  (apply #'ansi-filter "\x1b[48;2;%s;%s;%sm \x1b[0m" (funcall rgb-fn i))))
              (insert "\n"))
             (rainbow-color
              (i)
              (let* ((h (/ i 43))
                     (f (- i (* 43 h)))
                     (t_ (/ (* 255 f) 43))
                     (q (- 255 t_)))
                (cl-case h
                  (0 `(255 ,t_ 0))
                  (1 `(,q 255 0))
                  (2 `(0 255 ,t_))
                  (3 `(0 ,q 255))
                  (4 `(,t_ 0 255))
                  (5 `(255 0 ,q))))))
     (insert-truecolor-sequences (lambda (i) `(,i 0 0)))
     (insert-truecolor-sequences (lambda (i) `(0 ,i 0)))
     (insert-truecolor-sequences (lambda (i) `(0 0 ,i)))
     (insert-truecolor-sequences #'rainbow-color)))

(defun xterm-color--test-xterm ()
  (xterm-color--with-tests
   ;; System colors
   (cl-loop for color from 40 to 47
            do (ansi-filter "\x1b[0;%sm  " color)
            finally (ansi-filter "\x1b[0m * ANSI system colors\n"))

   ;; Normal ANSI colors mapped to XTERM
   (cl-loop for color from 0 to 7
            do (ansi-filter "\x1b[48;5;%sm  " color)
            finally (ansi-filter "\x1b[0m * ANSI colors mapped to XTERM\n"))

   ;; Bright ANSI colors mapped to XTERM
   (cl-loop for color from 8 to 15
            do (ansi-filter "\x1b[48;5;%sm  " color)
            finally (ansi-filter "\x1b[0m * ANSI bright colors mapped to XTERM\n\n"))

   ;; XTERM 256 color cubes
   (insert "*  XTERM 256 color cubes\n\n")

   (cl-loop for green from 0 to 5 do
            (cl-loop for red from 0 to 5 do
                     (cl-loop for blue from 0 to 5
                              for color = (+ 16 (* 36 red) (* green 6) blue)
                              do (ansi-filter "\x1b[48;5;%sm  \x1b[0m" color))
                     (ansi-filter "\x1b[0m "))
            (insert "\n"))

   ;; Truecolor color ramps
   (insert "\n")
   (insert "*  Truecolor color ramps\n\n")
   (xterm-color--test-truecolor)

   (insert "\n")
   (insert "*  XTERM color grayscale ramp\n\n")

   (cl-loop for color from 232 to 255
            do (ansi-filter "\x1b[48;5;%sm  " color)
            finally (ansi-filter "\x1b[0m\n\n"))))

;;;###autoload
(defun xterm-color-test ()
  "Create/display and render a new buffer that contains ANSI control sequences."
  (interactive)
  (let* ((name (generate-new-buffer-name "*xterm-color-test*"))
         (buf (get-buffer-create name)))
    (switch-to-buffer buf))

  (xterm-color--test-xterm)

  (let ((xterm-color-use-bold-for-bright nil))
    (xterm-color--test-ansi))
  (xterm-color-clear-cache)

  (insert "; Temporarily setting `xterm-color-use-bold-for-bright' to T\n")
  (insert "; Current Emacs font needs to have a bold variant\n\n")

  (let ((xterm-color-use-bold-for-bright t))
    (xterm-color--test-ansi))

  (setq buffer-read-only t)
  (goto-char (point-min)))

;;;###autoload
(defun xterm-color-test-raw ()
  "Create and display a new buffer that contains ANSI SGR control sequences.
ANSI sequences will not be processed. One can use a different Emacs package
(e.g. ansi-color.el) to do so. This is really meant to be used for
easy comparisons/benchmarks with libraries that offer similar functionality."
  (interactive)
  (let* ((name (generate-new-buffer-name "*xterm-color-test-raw*"))
         (buf (get-buffer-create name)))
    (switch-to-buffer buf))

  (let (xterm-color--test-do-filter)
    (xterm-color--test-xterm)
    (xterm-color--test-ansi))
  (goto-char (point-min)))

(provide 'xterm-color)
;;; xterm-color.el ends here
