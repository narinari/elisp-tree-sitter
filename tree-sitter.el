;;; tree-sitter.el --- Incremental parsing system -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2019  Tuấn-Anh Nguyễn
;;
;; Author: Tuấn-Anh Nguyễn <ubolonton@gmail.com>
;; Keywords: parser dynamic-module tree-sitter
;; Homepage: https://github.com/ubolonton/emacs-tree-sitter
;; Version: 0.1.0
;; Package-Requires: ((emacs "25.1"))
;; License: MIT

;;; Commentary:

;; This is an Emacs binding for tree-sitter, an incremental parsing system
;; (https://tree-sitter.github.io/tree-sitter/). It includes both the core APIs, and a minor mode
;; that provides a buffer-local up-to-date syntax tree.
;;
;; (progn
;;   (setq tree-sitter-language (ts-load-language "rust"))
;;   (tree-sitter-mode +1))

;;; Code:

(require 'tree-sitter-core)

(defvar-local tree-sitter-tree nil)
(defvar-local tree-sitter-parser nil)
(defvar-local tree-sitter-language nil)

(defvar-local tree-sitter--start-byte 0)
(defvar-local tree-sitter--old-end-byte 0)
(defvar-local tree-sitter--new-end-byte 0)
(defvar-local tree-sitter--start-point [0 0])
(defvar-local tree-sitter--old-end-point [0 0])
(defvar-local tree-sitter--new-end-point [0 0])

(defun tree-sitter--point (position)
  "Convert POSITION to a valid (0-based indexed) tree-sitter point."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char position)
      (let ((row (- (line-number-at-pos position) 1))
            ;; TODO XXX: The doc says this takes chars' width into account. tree-sitter probably
            ;; only wants to count chars (bytes?). Triple-check!!!
            (column (current-column)))
        (vector row column)))))

(defun tree-sitter--before-change (begin end)
  (setq tree-sitter--start-byte (- (position-bytes begin) 1)
        tree-sitter--old-end-byte (- (position-bytes end) 1)
        ;; TODO: Keep mutating the same vector instead of creating a new one each time.
        tree-sitter--start-point (tree-sitter--point begin)
        tree-sitter--old-end-point (tree-sitter--point end)))

;;; TODO XXX: The doc says that `after-change-functions' can be called multiple times, with
;;; different regions enclosed in the region passed to `before-change-functions'. Therefore what we
;;; are doing may be a bit too naive. Several questions to investigate:
;;;
;;; 1. Are the *after* regions recorded all at once, or one after another? Are they disjointed
;;; (would imply the former)?.
;;;
;;; 2. Are the *after* regions recorded at the same time as the *before* region? If not, how can the
;;; latter possibly enclose the former, e.g. in case of inserting a bunch of text?
;;;
;;; 3. How do we batch *after* hooks to re-parse only once? Maybe using `run-with-idle-timer' with
;;; 0-second timeout?
;;;
;;; 4. What's the deal with several primitives calling `after-change-functions' *zero* or more
;;; times? Does that mean we can't rely on this hook at all?
(defun tree-sitter--after-change (_begin end _length)
  (setq tree-sitter--new-end-byte (- (position-bytes end) 1)
        tree-sitter--new-end-point (tree-sitter--point end))
  (when tree-sitter-tree
    (ts-edit-tree tree-sitter-tree
                  tree-sitter--start-byte
                  tree-sitter--old-end-byte
                  tree-sitter--new-end-byte
                  tree-sitter--start-point
                  tree-sitter--old-end-point
                  tree-sitter--new-end-point)
    (let ((old-tree tree-sitter-tree))
      (tree-sitter--do-parse))))

(defun tree-sitter--do-parse ()
  (setq tree-sitter-tree
        (ts-parse tree-sitter-parser #'ts-buffer-input tree-sitter-tree))
  ;; (let ((inhibit-message t))
  ;;   (message "--------------------------------------------------\n%s"
  ;;            (ts-pp-to-string tree-sitter-tree)))
  )

(defun tree-sitter--enable ()
  ;; TODO: Determine the language symbol based on `major-mode' and some fallback rules.
  (unless tree-sitter-language
    (error "tree-sitter-language must be set"))
  (setq tree-sitter-parser (ts-make-parser)
        tree-sitter-tree nil)
  (ts-set-language tree-sitter-parser tree-sitter-language)
  (tree-sitter--do-parse)
  (add-hook 'before-change-functions #'tree-sitter--before-change 'append 'local)
  (add-hook 'after-change-functions #'tree-sitter--after-change 'append 'local))

(defun tree-sitter--disable ()
  (remove-hook 'before-change-functions #'tree-sitter--before-change 'local)
  (remove-hook 'after-change-functions #'tree-sitter--after-change 'local)
  (setq tree-sitter-tree nil
        tree-sitter-parser nil))

(define-minor-mode tree-sitter-mode
  "Minor mode that keeps an up-to-date syntax tree using incremental parsing."
  :init-value nil
  :lighter "tree-sitter"
  (if tree-sitter-mode
      (tree-sitter--enable)
    (tree-sitter--disable)))

(provide 'tree-sitter)
;;; tree-sitter.el ends here