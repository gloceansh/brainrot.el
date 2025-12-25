;;; brainrot.el --- Rot your brain even more while coding -*- lexical-binding: t; -*--

(require 'flycheck)
(require 'seq)
(require 'cl-lib)
(require 'posframe)

(defgroup brainrot nil
  "Configuration for brainrot"
  :group 'tools)

;;; --- Configuration ---

(defcustom brainrot-assets-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Root directory for brainrot assets."
  :type 'directory)

(defcustom brainrot-phonk-duration 2.5
  "Duration of the celebration in seconds."
  :type 'float)

(defcustom brainrot-min-error-duration 0.5
  "How long errors must exist before a fix triggers a reward."
  :type 'float)

(defcustom brainrot-boom-volume 50
  "Volume for the boom sound (0-100)."
  :type 'integer)

(defcustom brainrot-phonk-volume 50
  "Volume for the phonk music (0-100)."
  :type 'integer)

;;; --- Internal State ---

(defvar-local brainrot--prev-errors (make-hash-table :test 'equal)
  "Stores hash keys of errors from the previous check (Buffer Local).")

(defvar-local brainrot--error-start-time nil
  "Time when the error count first went above 0 (Buffer Local).")

(defvar brainrot--active-overlay nil
  "Stores the dimming overlay for the buffer text.")

(defvar brainrot--remap-cookies nil
  "Stores cookies for face remappings (modeline, line-numbers).")

(defvar brainrot--celebrating nil
  "State to prevent double celebrations.")

(defconst brainrot--posframe-buffer " *brainrot-posframe*"
  "Name of the posframe buffer.")

;;; --- Asset Helpers ---

(defun brainrot--get-files (subdir ext-regexp)
  "Return list of files in SUBDIR matching EXT-REGEXP."
  (let ((dir (expand-file-name subdir brainrot-assets-dir)))
    (when (file-exists-p dir)
      (directory-files dir t ext-regexp))))

(defun brainrot--random-file (subdir ext-regexp)
  "Pick a random file."
  (let ((files (brainrot--get-files subdir ext-regexp)))
    (when files
      (nth (random (length files)) files))))

;;; --- Audio Player ---

(defun brainrot--play-sound (file volume &optional duration)
  "Play FILE with mpv at VOLUME. Optional DURATION kills it early."
  (let* ((args `("--no-video"
                 "--no-terminal"
                 ,(format "--volume=%d" volume)
                 ,@(when duration (list (format "--length=%s" duration)))
                 ,file)))
    (make-process
     :name "brainrot-audio"
     :command `("mpv" ,@args)
     :noquery t
     :sentinel #'ignore)))

;;; --- Visual Effects ---

(defun brainrot--dim-environment ()
  "Darken the buffer, modeline, and line numbers."
  (setq brainrot--active-overlay (make-overlay (window-start) (window-end)))
  (overlay-put brainrot--active-overlay 'face '(:background "black" :extend t))
  (overlay-put brainrot--active-overlay 'window (selected-window))

  (let ((dim-face '(:background "#1a1a1a" :foreground "#555555" :box nil))
        (black-face '(:background "black" :foreground "#333333"))
        (faces-to-dim '(mode-line mode-line-inactive
                                  doom-modeline doom-modeline-buffer-path doom-modeline-buffer-file
                                  doom-modeline-project-dir doom-modeline-project-parent-dir
                                  doom-modeline-project-root-dir)))
    (setq brainrot--remap-cookies
          (delq nil
                (mapcar (lambda (face)
                          (when (facep face)
                            (face-remap-add-relative face dim-face)))
                        faces-to-dim)))
    
    (push (face-remap-add-relative 'line-number black-face) brainrot--remap-cookies)
    (push (face-remap-add-relative 'line-number-current-line black-face) brainrot--remap-cookies)
    (when (facep 'fringe)
      (push (face-remap-add-relative 'fringe black-face) brainrot--remap-cookies))))

(defun brainrot--show-image-posframe ()
  "Show a random brainrot image using posframe (floating overlay)."
  (let ((img-path (brainrot--random-file "images" "\\.\\(png\\|jpg\\|jpeg\\|webp\\)$")))
    (when img-path
      (let* ((img (create-image img-path nil nil :scale 1.0))
             (buf (get-buffer-create brainrot--posframe-buffer)))
        
        (with-current-buffer buf
          (erase-buffer)
          (insert " ")
          (put-text-property (point-min) (point-max) 'display img))
        
        (posframe-show buf
                       :position (point)
                       :poshandler #'posframe-poshandler-window-center
                       :background-color "black"
                       :internal-border-width 0
                       :accept-focus nil)))))

(defun brainrot--cleanup ()
  "Remove overlays, restore faces, and hide posframe."
  (when brainrot--active-overlay
    (delete-overlay brainrot--active-overlay)
    (setq brainrot--active-overlay nil))
  
  (dolist (cookie brainrot--remap-cookies)
    (face-remap-remove-relative cookie))
  (setq brainrot--remap-cookies nil)
  
  (posframe-hide brainrot--posframe-buffer)
  
  (setq brainrot--celebrating nil))

;;; --- Actions ---

(defun brainrot-boom ()
  "Play the boom sound."
  (let ((boom (expand-file-name "boom.ogg" brainrot-assets-dir)))
    (when (file-exists-p boom)
      (brainrot--play-sound boom brainrot-boom-volume))))

(defun brainrot-phonk ()
  "Trigger the phonk manually"
  (unless brainrot--celebrating
    (setq brainrot--celebrating t)
    (let ((song (brainrot--random-file "phonks" "\\.\\(mp3\\|ogg\\|wav\\|flac\\)$")))
      (when song
        (brainrot--play-sound song brainrot-phonk-volume brainrot-phonk-duration)
        (brainrot--dim-environment)
        (brainrot--show-image-posframe)
        (run-at-time brainrot-phonk-duration nil #'brainrot--cleanup)))))

;;; --- Logic ---

(defun brainrot--get-diag-key (err)
  "Generate a unique key for a flycheck error (line:column:message)."
  (format "%d:%d:%s" 
          (flycheck-error-line err)
          (or (flycheck-error-column err) 0)
          (flycheck-error-message err)))

(defun brainrot-check ()
  "Compare previous errors to current errors to determine Boom or Phonk."
  (when (boundp 'flycheck-current-errors)
    (let* ((current-list flycheck-current-errors)
           (current-errors (cl-remove-if-not 
                            (lambda (e) (eq (flycheck-error-level e) 'error))
                            current-list))
           (current-hash (make-hash-table :test 'equal))
           (current-count (length current-errors))
           (prev-count (hash-table-count brainrot--prev-errors)))

      (dolist (err current-errors)
        (puthash (brainrot--get-diag-key err) t current-hash))

      (when (and (> prev-count 0) (= current-count 0))
        (let ((duration-active (if brainrot--error-start-time
                                   (float-time (time-subtract (current-time) brainrot--error-start-time))
                                 0)))
          (when (>= duration-active brainrot-min-error-duration)
            (brainrot-phonk)))
        (setq brainrot--error-start-time nil))

      (when (and (= prev-count 0) (> current-count 0))
        (setq brainrot--error-start-time (current-time)))

      (let ((new-error-found nil))
        (maphash (lambda (key _val)
                   (unless (gethash key brainrot--prev-errors)
                     (setq new-error-found t)))
                 current-hash)
        (when new-error-found
          (brainrot-boom)))

      (setq brainrot--prev-errors current-hash))))

;;; --- Mode Setup ---

;;;###autoload
(define-minor-mode brainrot-mode
  "Global brainrot mode"
  :global t
  (if brainrot-mode
      (add-hook 'flycheck-after-syntax-check-hook #'brainrot-check)
    (remove-hook 'flycheck-after-syntax-check-hook #'brainrot-check)))

(provide 'brainrot)
