# brainrot.el

An emacs package that plays a vine boom when you make an error, then plays phonk with a meme image once you clear all of them. Inspired by [brainrot.nvim](https://github.com/sahaj-b/brainrot.nvim)

https://github.com/user-attachments/assets/9da68f64-db5c-48c6-9063-ee029087628c

# Dependencies

  - **mpv:** Must be installed on your system to play audio (`brew install mpv` on macOS)
  - **flycheck:** This package relies on [flycheck](https://www.flycheck.org/en/latest/), it won't work with other linters

# Installation

Here is an example with [straight.el](https://github.com/radian-software/straight.el), with the default configuration options

```lisp
(use-package brainrot
  :straight (brainrot :type git :host github :repo "gloceansh/brainrot.el"
                      :files ("*.el" "boom.ogg" "images" "phonks"))
  :custom
  ;; Duration of the phonk in seconds, set to 0 to disable or a high number to play the full length
  (brainrot-phonk-duration 2.5)
  
  ;; How long errors must exist before a fix triggers the phonk
  (brainrot-min-error-duration 0.5)
  
  ;; Volume for the vine boom (0-100)
  (brainrot-boom-volume 50)
  
  ;; Volume for the phonk (0-100)
  (brainrot-phonk-volume 50)
  
  :config
  (brainrot-mode 1))
  ```
