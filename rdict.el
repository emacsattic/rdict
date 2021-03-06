;;; rdict.el --- Interface to rus<->eng online dictionary.

;; Copyright (c) 2003-2008 by Zajcev Evgeny.

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Maintainer: none, if you want be a maintainer please e-mail me
;; Created: 21 Mar 2003
;; Keywords: dictionary, hypermedia
;; Version: 0.6

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;; 
;; rdict is is Emacs interface to the online Rissian<-->English
;; dictionary lingvo located at http://lingvo.yandex.ru.
;;
;; It requires w3 (the Emacs web browser) package to be installed.
;;
;; To install rdict add following to your .emacs:
;;
;;   (autoload 'rdict "rdict"
;;             "Lookup words in the online rus<->eng dictionary" t)
;;
;; Also you may need to customize some rdict variables to make it work
;; properly:
;;
;; `rdict-history-length' - (int) maximum length of rdict history.
;;
;; `rdict-mode-hook' - you may add your own hooks, it will runs after
;; rdict processing.

;;; History:
;;
;; Version 0.6:
;;   - Mule support added

;; Version 0.5:
;;   - Support for different dictionaries added.

;; Version 0.4:
;;   - Support for additional languages added.

;; Version 0.3:
;;   - koi8-r <--> utf-8 translation added.

;;; TODO:
;;
;; * History transcription -- Done.
;;
;; * Advanced history navigation  -- Done.
;;    - visit tree
;;
;; * Movements enhancement.
;;
;; * Vocabulary
;;    - Navigation
;;    - Save/restore
;;    - Words rating
;;    - FlashCard exporter

;;; Code:

(require 'url)

(defgroup rdict nil
  "Interface to the lingvo rus <-> eng dictionary"
  :prefix "rdict-"
  :group 'hypermedia)

(defcustom rdict-language "en"
  "*Default language."
  :type '(choice (const :tag "English" "en")
                 (const :tag "Deutsche" "de")
                 (const :tag "Francaise" "fr")
                 (const :tag "Italiano" "it")
                 (const :tag "Espanola" "es"))
  :group 'rdict)

(defcustom rdict-dictionaries '("AB" "GH" "EF")
  "List of dictionaries to use when translating.
???ˉ?
  AB - ?Ŋ ????  CD -  ?Ώ????
  EF - ??Вχ??ɒ?N?
  JK - ????œˉʊ  NO - 텄????
  PQ - ?ĉ???
  GH - ?????œˉʊ  V  - ?R???????ŒÉ?
?Ńˉ?
  CD - ?Ŋ ????  IJ -  ?Ώ????
  EF - ????œˉʊ  KL - 텄????
  GH - ?ĉ???

撁??ˉ?
  CD - ?Ŋ ????  GH - ??œˉʊ  EF - ?ĉ???

锁?ю??:
  C  - ?Ŋ ????  AB - ??Ώ?????  EF - ????œˉʊ
铐N??:
  CD - ?Ŋ ????")

(defface rdict-gray-face
  (` ((((class grayscale) (background light))
       (:background "Gray90"))
      (((class grayscale) (background dark))
       (:foreground "Gray80"))
      (((class color) (background light)) 
       (:foreground "dimgray"))
      (((class color) (background dark)) 
       (:foreground "gray"))
      (t (:bold t :underline t))))
  "Face for gray text."
  :group 'rdict)

(defface rdict-abbrev-face
  (` ((((class grayscale) (background light))
       (:background "Gray90" :italic t))
      (((class grayscale) (background dark))
       (:foreground "Gray80" :italic t))
      (((class color) (background light)) 
       (:foreground "brown" :italic t))
      (((class color) (background dark)) 
       (:foreground "brown4" :italic t))
      (t (:bold t :underline t))))
  "Font lock faces used to highlight abbrevs"
  :group 'rdict)

(defface rdict-link-face
  (` ((((class grayscale) (background light))
       (:background "Gray90" :italic t :underline t))
      (((class grayscale) (background dark))
       (:foreground "Gray80" :italic t :underline t :bold t))
      (((class color) (background light)) 
       (:foreground "blue"))
      (((class color) (background dark)) 
       (:foreground "cyan" :bold t))
      (t (:bold t :underline t))))
  "Font lock face used to highlight links to other words"
  :group 'rdict)

(defcustom rdict-item-regex "^\\([0-9]+\\.\\|[IVX]+\\) "
  "Item regexp for `\\<rdict-mode-map>\\[rdict-next]' and `\\<rdict-mode-map>\\[rdict-prev]' commands."
  :type 'string
  :group 'rdict)

(defcustom rdict-history-length 100
  "*Maximum words to remember in history."
  :type 'number
  :group 'rdict)

(defcustom rdict-mode-hook nil
  "*Hook to run before entering rdict-mode."
  :type 'hook
  :group 'rdict)

(defcustom rdict-fill-column 80
  "*Fill column for rdict buffer."
  :type 'number
  :group 'rdict)

(defcustom rdict-margin-offset 2
  "*Margin offset to use for different text levels."
  :type 'number
  :group 'rdict)

(defcustom rdict-dir (expand-file-name "~/.rdict" user-init-directory)
  "*Directory where rdict stores its files."
  :type 'directory
  :group 'rdict)


(defvar rdict-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") 'next-line)
    (define-key map (kbd "p") 'previous-line)
    (define-key map (kbd "<") 'beginning-of-buffer)
    (define-key map (kbd ">") 'end-of-buffer)
    (define-key map (kbd "s") 'isearch-forward)
    (define-key map (kbd "r") 'isearch-backward)
    (define-key map (kbd "?") 'describe-mode)
    (define-key map (kbd "SPC") 'scroll-up)
    (define-key map (kbd "DEL") 'scroll-down)
    (define-key map (kbd "BS") 'scroll-down)

    (define-key map (kbd "q") 'rdict-restore-windows)
    (define-key map (kbd "]") 'rdict-next)
    (define-key map (kbd "[") 'rdict-prev)
    (define-key map (kbd "TAB") 'rdict-next-link)
    (define-key map (kbd "RET") 'rdict-follow-link)
    (define-key map (kbd "w") 'rdict)

    ;; History navigation
    (define-key map (kbd "h n") 'rdict-hist-next)
    (define-key map (kbd "h p") 'rdict-hist-prev)
    (define-key map (kbd "h >") 'rdict-hist-last)
    (define-key map (kbd "h <") 'rdict-hist-first)
    (define-key map (kbd "h l") 'rdict-hist-list)

    ;; Vocabulary
    (define-key map (kbd "v p") 'rdict-vocab-put)
    (define-key map (kbd "v r") 'rdict-vocab-search-related)
    (define-key map (kbd "v l") 'rdict-vocab-list)
    map)
  "Keymap used in RDICT mode.")

(defvar rdict-history nil "List of previous searches.")
(defvar rdict-hist-point 0
  "Nth element in `rdict-hist' we currently active.")

(defvar rdict-read-history nil "History for `read-string'.")
(defvar rdict-current-word "" "Currently translated word.")
(defvar rdict-saved-window-condition nil)

(defconst rdict-lingvo-url "http://lingvo.yandex.ru"
  "URL to use in order to search for words.")

(defconst rdict-rus-encoding-koi8r
  (concat
   "\301\302\327\307\304\305\243\326\332"
   "\311\312\313\314\315\316\317\320"
   "\322\323\324\325\306\310\303\336"
   "\333\335\337\331\330\334\300\321"
   "\341\342\367\347\344\345\263\366\372"
   "\351\352\353\354\355\356\357\360"
   "\362\363\364\365\346\350\343\376"
   "\373\375\377\371\370\374\340\361"))

(defconst rdict-rus-encoding-cp1251
  (concat
   "\340\341\342\343\344\345\270\346\347"
   "\350\351\352\353\354\355\356\357"
   "\360\361\362\363\364\365\366\367"
   "\370\371\372\373\374\375\376\377"
   "\300\301\302\303\304\305\250\306\307"
   "\310\311\312\313\314\315\316\317"
   "\320\321\322\323\324\325\326\327"
   "\330\331\332\333\334\335\336\337"))


(defun rdict-koi2win (str)
  "Translate STR from koi8 to cp1251."
  (if (featurep 'mule)
      (encode-coding-string str 'windows-1251)
    (let ((tt (make-vector 256 nil))
          (idx 0))
      (while (< idx (length rdict-rus-encoding-cp1251))
        (aset tt (char-to-int (aref rdict-rus-encoding-koi8r idx))
              (char-to-string (aref rdict-rus-encoding-cp1251 idx)))
        (incf idx))
      (mapconcat #'(lambda (chr)
                     (or (aref tt (char-to-int chr))
                         (char-to-string chr)))
                 str nil))))

(unless (boundp 'header-line)
  (defface header-line
    '((((class color) (background light))
       (:foreground "Gray20" :background "Gray90"))
      (((class color) (background dark))
       (:foreground "Gray90" :background "Gray20"))
      (((class grayscale) (background light))
       (:background "LightGray" :bold t))
      (((class grayscale) (background dark))
       (:foreground "DimGray" :bold t))
      (t (:bold t)))
    "Face used for displaying header-line."
    :group 'ibuffer-faces)
  (defvar header-line 'header-line))

(defun rdict-insert-header ()
  "Insert rdict header."
  (mapcar* #'(lambda (str faces)
               (rdict-ins-faces
                (point) (progn (insert str) (point)) faces))
           (list "Word: " (or rdict-current-word "UNKNOWN")
                 (format ", History point: %d/%d"
                         rdict-hist-point (length rdict-history)))
           (list '(header-line) '(header-line bold) '(header-line)))
  (insert "\n"))

;;;###autoload
(defun rdict-word (word &optional lang)
  (let ((url (format "%s?text=%s" (or lang rdict-language) word)))
    (message "url = %s" url))
  (pop-to-buffer
   (rdict-do-url
    (format "%s?text=%s" (or lang rdict-language) (rdict-koi2win word)) word)))

;;;###autoload
(defun rdict (&optional lang)
  "Lookup word in Lingvo Online Dictionary.
If prefix ARG is given, then select language."
  (interactive
   (list
    (if current-prefix-arg
        (completing-read "Language: " '(("en") ("de")) nil t rdict-language)
      rdict-language)))

  (let* ((rdict-language lang)
         (cur-word (current-word))
         (word (read-string (format "Translate word [%s]: " cur-word)
                            nil 'rdict-read-history)))
    (when (string= word "")
      (setq word cur-word))
    (let ((url (format "%s?text=%s" rdict-language word)))
      (message "url = %s" url))
    (pop-to-buffer
     (rdict-do-url
      (format "%s?text=%s" rdict-language (rdict-koi2win word)) word))))

;;;###autoload
(defun rdict-do-url (url &optional word)
  "Fetch and view URL"
  (let ((cur-buf (current-buffer))
        buf)
    (unless (eq major-mode 'rdict-mode)
      (setq rdict-saved-window-condition (current-window-configuration)))

    (setq buf (get-buffer-create "*RDict*"))
    (save-excursion
      (set-buffer buf)
      (setq buffer-read-only nil)
      (erase-buffer)

      (rdict-fetch-url url)
      (rdict-proc-output url)

      ;; Save into history
      (rdict-history-push word url cur-buf)

      (rdict-mode word))
    buf))

(defvar rdict-chars-need-hexify '(?\x20 ?\;)
  "List of characters that need to be url encoded.")

(defun rdict-fetch-url (url)
  "Fetch rdict data from URL."
  (url-insert-file-contents
   (concat rdict-lingvo-url
           (if (eq (aref url 0) ?/) "" "/")
	   (mapconcat
	    #'(lambda (char)
                (if (memq char rdict-chars-need-hexify)
                    (if (< char 16)
                        (upcase (format "%%0%x" char))
                      (upcase (format "%%%x" char)))
                  (char-to-string char)))
	    url ""))))

;  (if (featurep 'mule)
;      (decode-coding-region (point-min) (point-max) 'utf-8)
;    (shell-command-on-region (point-min) (point-max)
;                             "iconv -c -f utf-8 -t koi8-r" nil t))

(defun rdict-proc-output-for-w3m (word)
  (goto-char (point-min))
  (let ((found nil))
    (save-excursion
      (let ((case-fold-search nil))
        (when (re-search-forward "<div class=\"lingvo-article ?\">")
          (delete-region (point-min) (point))

          (when (re-search-forward "<\\(strong\\|/tbody\\)>" nil t)
            (delete-region (match-beginning 0) (point-max)))
          (setq found t))))))

(defun rdict-proc-output (word)
  "Prepare buffer for viewing"
  ;; UTF8 -> KOI8-R
  (if (featurep 'mule)
      (decode-coding-region (point-min) (point-max) 'utf-8)
    (shell-command-on-region (point-min) (point-max)
                             "iconv -c -f utf-8 -t koi8-r" nil t))

  (goto-char (point-min))
  (let ((found nil))
    (save-excursion
      (let ((case-fold-search nil))
        (when (re-search-forward "<div class=\"lingvo-article ?\">")
          (delete-region (point-min) (point))

          (when (re-search-forward "<!--Found by Translate<br>-->" nil t)
            (delete-region (point-min) (point)))

          (when (re-search-forward "<h1><b><span>" nil t)
            (delete-region (point-min) (point)))

;          (when (re-search-forward "</script>" nil t)
;            (delete-region (point-min) (point)))

          (when (re-search-forward "</DIV>" nil t)
            (delete-region (match-beginning 0) (point-max)))

          (when (re-search-forward "</tbody>" nil t)
            (delete-region (match-beginning 0) (point-max)))

          (when (re-search-forward "<strong>" nil t)
            (delete-region (match-beginning 0) (point-max)))
          (setq found t))))

    (when (and t found)
      (save-excursion
	(while (re-search-forward "\r\\|\n" nil t)
	  (replace-match "" nil nil)))

      ;; invisible symbols
      (save-excursion
        (while (search-forward (char-to-string (int-to-char 160)) nil t)
          (replace-match " " nil nil)))

      ;; &nbsp; -> ' '
      (save-excursion
	(while (re-search-forward "&[nN][bB][sS][pP];" nil t)
	  (replace-match " " nil nil)))

      ;; margin
      (save-excursion
	(while (re-search-forward
		"<[pP] [cC][lL][aA][sS][sS]=[lL]\\([0-9]\\)>" nil t)
	  (let* ((marg (* rdict-margin-offset
                          (string-to-int (match-string 1))))
		 (margstr (make-string marg ?\ )))
            ;; Only first margin level needs newline at the beginning
	    (replace-match (concat (if (= marg (* 1 rdict-margin-offset))
                                       "\n" "")
                                   margstr) nil nil)
	    (let ((cpn (point))
		  (enp)
		  (bestr))
	      (when (re-search-forward "</[pP]>" nil t)
		(replace-match "\n" nil nil)
		(setq enp (point))
		(setq bestr (replace-in-string 
			     (buffer-substring cpn enp)
			     "<[bB][rR]>" (concat "\n" margstr)))
		(delete-region cpn enp)
		(insert bestr))))))

      ;; <br> -> '\n'
      (save-excursion
	(while (re-search-forward "<[bB][rR]>" nil t)
	  (replace-match "\n" nil nil)))

      ;; <p> -> '\n\n'
      (save-excursion
        (while (re-search-forward "<[pP] class=\"L\\([0-9]\\)\"[^>]*>" nil t)
          (let ((ms (string-to-int (match-string 1))))
            (replace-match (concat "\n" (make-string (* ms 2) ?\ ))
                           nil nil))))
      (save-excursion
        (while (re-search-forward "<[pP][^>]*>" nil t)
          (replace-match "\n\n" nil nil)))

      (save-excursion
	(while (re-search-forward
		"<[sS][pP][aA][nN][ \t]*[lL][aA][nN][gG]=en-us>" nil t)
	  (replace-match "" nil nil)
	  (re-search-forward "</[sS][pP][aA][nN]>" nil t)
	  (replace-match "" nil nil)))

      ;; gray
      (save-excursion
	(while (re-search-forward
		"<[sS][pP][aA][nN] [sS][tT][yY][lL][eE]=\"color: ?gray;\"[^>]*>" nil t)
	  (replace-match "" nil nil)
	  (let ((cpont (point)))
	    (re-search-forward "</[sS][pP][aA][nN]>" nil t)
	    (replace-match "" nil nil)
	    (rdict-ins-faces cpont (point) '(rdict-gray-face)))))

      ;; brown
      (save-excursion
	(while (re-search-forward
		"<[sS][pP][aA][nN] [sS][tT][yY][lL][eE]=\"color: ?brown;\"[^>]*>" nil t)
	  (replace-match "" nil nil)
	  (let ((cpont (point)))
	    (re-search-forward "</[sS][pP][aA][nN]>" nil t)
	    (replace-match "" nil nil)
	    (rdict-ins-faces cpont (point) '(rdict-abbrev-face)))))

      ;; <I> italic
      (save-excursion
	(while (re-search-forward "<[iI]>" nil t)
	  (replace-match "" nil nil)
	  (let ((cpont (point)))
	    (re-search-forward "</[iI]>" nil t)
	    (replace-match "" nil nil)
	    (rdict-ins-faces cpont (point) '(italic)))))

      ;; <B> bold
      (save-excursion
	(while (re-search-forward "<[bB]>\\|<strong>" nil t)
	  (replace-match "" nil nil)

	  ;; for stupid fill-region :)
	  (let ((substr (substring (current-word t) 0 1)))
	    (cond ((string-match "[IVXLM]" substr) (insert "\n"))
		  ((string-match "[0-9]" substr) (insert "\n"))
		  (t nil)))

	  (let ((cpont (point)))
	    (re-search-forward "</[bB]>\\|</strong>" nil t)
	    (replace-match "" nil nil)
	    (rdict-ins-faces cpont (point) '(bold)))))

      ;; <a href=" -> insert rdict-url prop
      (save-excursion
	(while (re-search-forward "<a href=[\"']\\([^<>]*\\)[\"']>" nil t)
	  (let ((url-str (match-string 1))
		cpont)

	    (replace-match "" nil nil)
	    (setq cpont (point))

	    (re-search-forward "</[aA]>" nil t)
	    (replace-match "" nil nil)
                
	    ;; Fix URL-STR
	    (setq url-str (replace-in-string url-str "&[aA][mM][pP][;]" "&"))
	    ;; XXX
	    (when url-str
	      (when (string= (substring url-str 0 9) "/cgi-bin/")
		(setq url-str (substring url-str 9 (length url-str)))))

	    (rdict-add-url-link cpont (point) url-str)
	    (rdict-ins-faces cpont (point) '(rdict-link-face)))))

      ;; <DIV .. > -> \n
      (save-excursion
	(while (re-search-forward "<[Dd][Ii][Vv][^<>]*>" nil t)
	  (replace-match "\n" nil nil)))

      ;; remove not img tags
      (save-excursion
	(while (re-search-forward "<[/]?[^Ii][^Mm]?[^Gg]?[^<>]*>" nil t)
	  (replace-match "" nil nil)))

      ;; remove empty lines
      (save-excursion
	(let ((nd t))
	  (while nd
	    (if (eq (char-before (1+ (point))) ?\n)
		(kill-line)
	      (setq nd nil)))))

      ;; long dash
      (save-excursion
	(while (search-forward (char-to-string (int-to-char 102583)) nil t)
	  (replace-match "--" nil nil)))

      ;; big dot
      (save-excursion
	(while (search-forward (char-to-string (int-to-char 135334)) nil t)
	  (replace-match "*" nil nil)))

      ;; ^G -> ""
      (save-excursion
	(while (re-search-forward "\007" nil t)
	  (replace-match "" nil nil)))

      ;; \232 -> SPACE
      (save-excursion
	(while (search-forward "\232" nil t)
	  (replace-match " " nil nil)))

      ;; \227 -> --
      (save-excursion
	(while (search-forward "\227" nil t)
	  (replace-match "--" nil nil)))

      ;; &#8212; -> --
      (save-excursion
        (while (search-forward "&#8212;" nil t)
          (replace-match "--" nil nil)))

      ;; &#8226; -> *
      (save-excursion
	(while (search-forward "&#8226;" nil t)
	  (replace-match "*" nil nil)))

      ;; \225 -> *
      (save-excursion
	(while (search-forward "\225" nil t)
	  (replace-match "*" nil nil)))

      ;; \236 -> *
      (save-excursion
	(while (search-forward "\236" nil t)
	  (replace-match "*" nil nil)))

      ;; finally fill buffer
      (let ((fill-column rdict-fill-column))
        (save-excursion
          (fill-region (point-min) (point-max))))

      ;; TRANSCRIPTION
      (save-excursion
	(let ((nlist nil) (mbeg nil))
	  (while (re-search-forward "<[^>]*\\(src=\"[^\"]*/i/93.gif\"[^>]*>\\)\\|<[^<>]*/i/\\([0-9]*\\).gif\"[^>]*>" nil t)
	    (let* ((ma1 (match-string 1))
		   (manum (match-string 2))
		   prop)
	      (if ma1			; transcription
		  (save-excursion
		    (delete-region mbeg (match-end 1))
		    (setq mbeg nil)
		    ;;update trans property
		    (setq prop (cons (list (point) (nreverse (cons 93 nlist)))
				     (get-text-property (point-min)
							'trans)))
			
		    (put-text-property (point-min) (1+ (point-min)) 'trans prop)
		    (setq nlist nil))

		(progn
		  (if (null mbeg) (setq mbeg (match-beginning 0)))
		  (setq nlist (cons (string-to-int manum) nlist))))))))

      ;; Finally show the transcription
      (rdict-show-transcription))))

(defun rdict-mode (&optional word)
  "Major mode for browsing LINGVO output.

Bindings:
\\{rdict-mode-map}"
  (interactive)

  (setq rdict-current-word word)

  ;; Insert rdict header
  (save-excursion
    (goto-char (point-min))
    (rdict-insert-header))

  (use-local-map rdict-mode-map)
  (setq major-mode 'rdict-mode
	mode-name "Rdict"
	buffer-read-only t)
  (set-buffer-modified-p nil)

  ;; Remove duplicable extents, they were needed for history.
  (map-extents #'(lambda (ex &rest skip)
                   (set-extent-property ex 'duplicable nil)))

  ;; Finally run hooks
  (run-hooks 'rdict-mode-hook))

(defun rdict-restore-windows ()
  "Restore original windows layout."
  (interactive)
  (bury-buffer "*RDict*")
  (when rdict-saved-window-condition
    (set-window-configuration rdict-saved-window-condition)))

(defun rdict-ins-faces (from to face-list)
  "Add face properties of text from FROM to TO."
  (let ((ext (make-extent from to)))
    (set-extent-property ext 'duplicable t)
    (set-extent-property ext 'unique t)
    (set-extent-property ext 'start-open t)
    (set-extent-property ext 'end-open t)
    (set-extent-property ext 'face face-list)))

(defun rdict-add-url-link (from to url)
  "Add URL property TO text."
  (add-text-properties from to (list 'rdict-url url)))

(defun rdict-get-url ()
  "Return rdict-url property at point."
  (get-text-property (point) 'rdict-url))

;; Transcription
(defun rdict-show-tr (number pnt)
  "Insert pixmap."
  (let* ((isym (intern (format "rdict-%d-xpm" number)))
         ;; Workaround lingvo transcription bug
         (img (and (boundp isym)
                   (make-glyph (symbol-value isym)))))
    (when img
      (set-extent-end-glyph
       (make-extent pnt pnt) img))))

(defun rdict-show-trans (nlist)
  "Insert transcription constructed from NLIST."
  (let* ((nl nlist)
	 (cpoi (car nl))
	 (ctr (cdr nl)))
    (while ctr
      (rdict-show-tr (car ctr) cpoi)
      (setq ctr (cdr ctr)))))

(defun rdict-show-transcription ()
  "Insert transcription."
  (let ((nl (get-text-property (point-min) 'trans))
	 cpoi ctr)

    (while nl
      (setq cpoi (car (car nl)))
      (setq ctr (car (cdr (car nl))))

      (while ctr
	(rdict-show-tr (car ctr) cpoi)
	(setq ctr (cdr ctr)))
      (setq nl (cdr nl)))))

;; Browsing links
(defun rdict-follow-link (url)
  "Goto link URL."
  (interactive (list (rdict-get-url)))

  (when url
    (rdict-do-url url)))

(defun rdict-next-link (&optional n)
  "Jump to next N link."
  (interactive "p")

  (let ((furl (rdict-get-url))
	 url pnt done)

    ;; Search for next link
    (setq url furl)
    (save-excursion
      (while (and (not done) (> n 0) (not (eobp)))
	(forward-char 1)
	(setq url (rdict-get-url))
	(when (and (not (null url))
                   (not (eq url furl)))
          (setq pnt (point)
                done t))))

    ;; Jump to link if found
    (when done
      (goto-char pnt)
      (message (format "Link: -> \"%s\"" url)))))


;; History
(defun rdict-history-push (word &optional url buf)
  "Push WORD into rdict history."
  ;; truncate history
  (when (> (length rdict-history) rdict-history-length)
    (setq rdict-history (butlast rdict-history)))

  (push (list (buffer-string) :url url :word word :buffer buf) rdict-history)
  (setq rdict-hist-point 0))

(defun rdict-history-show ()
  "Show history buffer according to `rdict-hist-point' value."
  (let ((hi (nth rdict-hist-point rdict-history)))
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert (car hi))
    (rdict-show-transcription)
    (goto-char (point-min))
    (rdict-mode (plist-get (cdr hi) :word))))

;; If this is called we should be already in the *RDict* buffer.
(defun rdict-hist-goto (direction &optional n)
  "Navigate history N times.
DIRECTION is one of 'next or 'prev."
  (interactive)

  (setq n (% n (length rdict-history)))

  ;; Calculate position
  ;; X: 0, 1, 2,...,n		;dir = nil
  ;; Y: n, n-1, n-2,...0	;dir = t
  ;;
  ;; X->Y == Y->X: n-(x|y) where n == length of list minus 1
  (when (eq direction 'next)            ; X -> Y
    (setq rdict-hist-point (- (length rdict-history) 1 rdict-hist-point)))

  (setq rdict-hist-point (% (+ n rdict-hist-point) (length rdict-history))) ;offset

  (when (eq direction 'next)            ; back Y -> X
    (setq rdict-hist-point (- (length rdict-history) 1 rdict-hist-point)))

  (when (= (length rdict-history) 1)
    (error "Only one entry in history"))

  (rdict-history-show))

(defun rdict-hist-prev (&optional n)
  "Goto N previous word in history."
  (interactive "p")
  (rdict-hist-goto 'prev n))

(defun rdict-hist-next (&optional n)
  "Goto N next word in history."
  (interactive "p")
  (rdict-hist-goto 'next n))

(defun rdict-hist-first ()
  "Goto the first item in rdict history."
  (interactive)
  (setq rdict-hist-point (1- (length rdict-history)))
  (rdict-history-show))

(defun rdict-hist-last ()
  "Goto the last item in rdict history."
  (interactive)
  (setq rdict-hist-point 0)
  (rdict-history-show))

(defun rdict-hist-list ()
  "List history items."
  (interactive)
  (with-current-buffer (get-buffer-create "*RDict-history*")
    (erase-buffer)
    (insert (format "%-24s%-32s%s\n" "Word" "URL" "Buffer"))
    (insert (format "%-24s%-32s%s\n" "----" "---" "------"))
    (mapc #'(lambda (he)
              (let ((word (plist-get (cdr he) :word))
                    (url (plist-get (cdr he) :url))
                    (buffer (plist-get (cdr he) :buffer)))
                (insert (format "%-24s%-32S%S\n"
                                (or word "UNKNOWN") url (buffer-name buffer)))))
          rdict-history)
    (set-window-buffer (selected-window) (current-buffer))
    ))


;; Vocabulary support
(defcustom rdict-vocab-file
  (expand-file-name "vocabulary" rdict-dir)
  "File to store vocabulary."
  :type 'file
  :group 'rdict)

(defun rdict-vocab-put ()
  "Put current word into vocabulary."
  (interactive)
  (error "`rdict-vocab-put' not implemented"))

(defun rdict-vocab-save-file ()
  "Save rdict vocabulary."
  (interactive)
  (error "`rdict-vocab-save' not implemented"))

(defun rdict-vocab-read-file ()
  "Read rdict's vocabulary file `rdict-vocab-file'."
  (interactive)
  (error "`rdict-vocab-read-file' not implemented"))

(defun rdict-vocab-search-related ()
  "Search related(to current word) entries in vocabulary."
  (interactive)
  (error "`rdict-vocab-search-related' not implemented"))

(defun rdict-vocab-list ()
  "Interactively browse list of vocabulary entries."
  (interactive)
  (error "`rdict-vocab-list' not implemented"))


(defun rdict-next ()
  "Goto next Item."
  (interactive)
  (let ((pnt nil))
    (save-excursion
      (forward-char 1)
      (when (re-search-forward rdict-item-regex nil t)
	(setq pnt (match-beginning 0))))

    (when pnt
      (goto-char pnt))))

(defun rdict-prev ()
  "Goto next Item."
  (interactive)
  (let ((pnt nil))
    (save-excursion
      (backward-char 1)
      (when (re-search-backward rdict-item-regex nil t)
	(setq pnt (match-beginning 0))))

    (when pnt
      (goto-char pnt))))


;;; Pics
(defvar rdict-100-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"...   . .\","
			      "\".. ...  .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-101-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...   ...\","
			      "\".. ... ..\","
			      "\". ..... .\","
			      "\".       .\","
			      "\". .......\","
			      "\". .......\","
			      "\". ..... .\","
			      "\".. ... ..\","
			      "\"...   ...\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-102-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\"...  \","
			      "\".. ..\","
			      "\".. ..\","
			      "\"     \","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-103-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...   . .\","
			      "\".. ...  .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"...... ..\","
			      "\"..    ...\""
			      "};"))

(defvar rdict-104-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\","
			      "\". .   ...\","
			      "\".  ... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-105-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\""
			      "};"))

(defvar rdict-106-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\" ..\""
			      "};"))

(defvar rdict-107-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\". ......\","
			      "\". ......\","
			      "\". ......\","
			      "\". .... .\","
			      "\". ... ..\","
			      "\". .. ...\","
			      "\". . ....\","
			      "\".   ....\","
			      "\". .. ...\","
			      "\". ... ..\","
			      "\". .... .\","
			      "\". ..... \","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-108-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\""
			      "};"))

(defvar rdict-109-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"13 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".         ...\","
			      "\". .... ... ..\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\""
			      "};"))

(defvar rdict-110-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".     ...\","
			      "\". .... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-111-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...   ...\","
			      "\".. ... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ... ..\","
			      "\"...   ...\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-112-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".     ...\","
			      "\". .... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". .... ..\","
			      "\".     ...\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\""
			      "};"))

(defvar rdict-113-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...     .\","
			      "\".. .... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. .... .\","
			      "\"...     .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"....... .\""
			      "};"))

(defvar rdict-114-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\". .  \","
			      "\".  ..\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-115-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"..    ..\","
			      "\". .... .\","
			      "\". ......\","
			      "\". ......\","
			      "\"..    ..\","
			      "\"...... .\","
			      "\"...... .\","
			      "\". .... .\","
			      "\"..    ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-116-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"     \","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"... .\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-117-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-118-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"7 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\" ..... \","
			      "\" ..... \","
			      "\". ... .\","
			      "\". ... .\","
			      "\".. . ..\","
			      "\".. . ..\","
			      "\"... ...\","
			      "\"... ...\","
			      "\"... ...\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\""
			      "};"))

(defvar rdict-119-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"11 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\" ......... \","
			      "\" .... .... \","
			      "\". ... ... .\","
			      "\". ... ... .\","
			      "\".. . . . ..\","
			      "\".. . . . ..\","
			      "\"... ... ...\","
			      "\"... ... ...\","
			      "\"... ... ...\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\""
			      "};"))

(defvar rdict-120-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"7 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\" ..... \","
			      "\". ... .\","
			      "\". ... .\","
			      "\".. . ..\","
			      "\"... ...\","
			      "\".. . ..\","
			      "\". ... .\","
			      "\". ... .\","
			      "\" ..... \","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\""
			      "};"))

(defvar rdict-121-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"7 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\" ..... \","
			      "\" ..... \","
			      "\". ... .\","
			      "\". ... .\","
			      "\".. . ..\","
			      "\".. . ..\","
			      "\"... ...\","
			      "\"... ...\","
			      "\".. ....\","
			      "\".. ....\","
			      "\". .....\","
			      "\". .....\","
			      "\" ......\""
			      "};"))

(defvar rdict-122-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\".      .\","
			      "\"...... .\","
			      "\"..... ..\","
			      "\".... ...\","
			      "\"... ....\","
			      "\"... ....\","
			      "\".. .....\","
			      "\". ......\","
			      "\".      .\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-123-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\"... .\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\". ...\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"... .\","
			      "\".....\""
			      "};"))

(defvar rdict-124-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-125-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\". ...\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"... .\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\". ...\","
			      "\".....\""
			      "};"))

(defvar rdict-126-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"..  ... .\","
			      "\". .. .. .\","
			      "\". ...  ..\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-127-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".   .\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-15-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\". ..... .\","
			     "\"..     ..\","
			     "\".. ... ..\","
			     "\".. ... ..\","
			     "\".. ... ..\","
			     "\"..     ..\","
			     "\". ..... .\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-176-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"4 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\". ..\","
			      "\"....\","
			      "\"....\","
			      "\". ..\","
			      "\". ..\","
			      "\". . \","
			      "\". ..\","
			      "\". ..\","
			      "\". ..\","
			      "\". . \","
			      "\". ..\","
			      "\". ..\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\""
			      "};"))

(defvar rdict-177-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"10 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\".      ...\","
			      "\"....... ..\","
			      "\"....... . \","
			      "\"..      ..\","
			      "\". ..... ..\","
			      "\". ..... ..\","
			      "\". ..... . \","
			      "\". ..... ..\","
			      "\"..     . .\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\""
			      "};"))

(defvar rdict-178-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"10 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"...   ....\","
			      "\".. ... ...\","
			      "\". ..... . \","
			      "\"....... ..\","
			      "\"....... ..\","
			      "\"....... ..\","
			      "\". ..... . \","
			      "\".. ... ...\","
			      "\"...   ....\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\""
			      "};"))

(defvar rdict-179-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"10 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\". ..... ..\","
			      "\". ..... ..\","
			      "\". ..... . \","
			      "\". ..... ..\","
			      "\". ..... ..\","
			      "\". ..... ..\","
			      "\". ..... . \","
			      "\".. ...  ..\","
			      "\"...   . ..\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\""
			      "};"))

(defvar rdict-180-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"10 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"...   ....\","
			      "\".. ... ...\","
			      "\". ..... . \","
			      "\"....... ..\","
			      "\"....... ..\","
			      "\".       ..\","
			      "\". ..... . \","
			      "\".. ... ...\","
			      "\"...   ....\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\","
			      "\"..........\""
			      "};"))

(defvar rdict-181-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".... ....\","
			      "\".... ....\","
			      "\".... ....\","
			      "\"... . ...\","
			      "\"... . ...\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-182-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"...   ..\","
			      "\".. ... .\","
			      "\". ..... \","
			      "\"....... \","
			      "\"....... \","
			      "\".       \","
			      "\". ..... \","
			      "\".. ... .\","
			      "\"...   ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-183-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"14 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"...   ...   ..\","
			      "\".. ... . ... .\","
			      "\". ..... ..... \","
			      "\".......       \","
			      "\"....... ......\","
			      "\".       ......\","
			      "\". ..... ..... \","
			      "\".. ... . ... .\","
			      "\"...   ...   ..\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\","
			      "\"..............\""
			      "};"))

(defvar rdict-184-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"...   ..\","
			      "\".. ... .\","
			      "\". ..... \","
			      "\"....... \","
			      "\"....... \","
			      "\"....... \","
			      "\". ..... \","
			      "\".. ... .\","
			      "\"...   ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-185-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".. . ....\","
			      "\"... .....\","
			      "\".. . ....\","
			      "\"..... ...\","
			      "\"...... ..\","
			      "\"...    ..\","
			      "\".. .... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ... ..\","
			      "\"...   ...\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-186-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".       .\","
			      "\". .... ..\","
			      "\"..... ...\","
			      "\".... ....\","
			      "\"... .....\","
			      "\"..    ...\","
			      "\"...... ..\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\". ..... .\","
			      "\".. ... ..\","
			      "\"...   ...\""
			      "};"))

(defvar rdict-187-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"16 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"................\","
			      "\"................\","
			      "\"................\","
			      "\"................\","
			      "\"....... ........\","
			      "\"....... ........\","
			      "\"....... ........\","
			      "\"...   . .       \","
			      "\".. ...  . .... .\","
			      "\". ..... ..... ..\","
			      "\". ..... .... ...\","
			      "\". ..... ... ....\","
			      "\". ..... ..    ..\","
			      "\". ..... ...... .\","
			      "\".. ...  ....... \","
			      "\"...   . ....... \","
			      "\"............... \","
			      "\"......... ..... \","
			      "\".......... ... .\","
			      "\"...........   ..\""
			      "};"))

(defvar rdict-188-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\". .   ..\","
			      "\".  ... .\","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\"....... \","
			      "\"....... \","
			      "\"...... .\","
			      "\"..    ..\""
			      "};"))

(defvar rdict-189-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-190-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"...   ..\","
			      "\".. ... .\","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\".       \","
			      "\". ..... \","
			      "\". ..... \","
			      "\". ..... \","
			      "\".. ... .\","
			      "\"...   ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-191-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\"... .\","
			      "\".. . \","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\" . ..\","
			      "\". ...\""
			      "};"))

(defvar rdict-192-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".. .... .\","
			      "\".. ... . \","
			      "\".. ... ..\","
			      "\"     . ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\".. ... ..\","
			      "\"... .. ..\","
			      "\"...... ..\","
			      "\"...... ..\","
			      "\".... . ..\","
			      "\"..... ...\""
			      "};"))

(defvar rdict-193-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\""
			      "};"))

(defvar rdict-194-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...   ...\","
			      "\".. ... ..\","
			      "\". ..... .\","
			      "\".       .\","
			      "\". .......\","
			      "\". .......\","
			      "\". ..... .\","
			      "\".. ... ..\","
			      "\"...   ...\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-195-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".     ...\","
			      "\". .... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". .... ..\","
			      "\".     ...\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\""
			      "};"))

(defvar rdict-196-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\","
			      "\". .   ...\","
			      "\".  ... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".  ... ..\","
			      "\". .   ...\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-197-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"13 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".         ...\","
			      "\". .... ... ..\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\". .... .... .\","
			      "\".............\","
			      "\".............\","
			      "\".............\","
			      "\".............\""
			      "};"))

(defvar rdict-198-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"11 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\" ......... \","
			      "\" .... .... \","
			      "\". ... ... .\","
			      "\". ... ... .\","
			      "\".. . . . ..\","
			      "\".. . . . ..\","
			      "\"... ... ...\","
			      "\"... ... ...\","
			      "\"... ... ...\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\","
			      "\"...........\""
			      "};"))

(defvar rdict-199-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\"...  \","
			      "\".. ..\","
			      "\".. ..\","
			      "\"     \","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-20-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"8 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"..      \","
			     "\".    . .\","
			     "\".    . .\","
			     "\".    . .\","
			     "\".    . .\","
			     "\"..   . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\".... . .\","
			     "\"........\","
			     "\"........\","
			     "\"........\""
			     "};"))

(defvar rdict-200-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"7 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\" ..... \","
			      "\" ..... \","
			      "\". ... .\","
			      "\". ... .\","
			      "\".. . ..\","
			      "\".. . ..\","
			      "\"... ...\","
			      "\"... ...\","
			      "\"... ...\","
			      "\".......\","
			      "\".......\","
			      "\".......\","
			      "\".......\""
			      "};"))

(defvar rdict-201-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"..    ..\","
			      "\". .... .\","
			      "\". ......\","
			      "\". ......\","
			      "\"..    ..\","
			      "\"...... .\","
			      "\"...... .\","
			      "\". .... .\","
			      "\"..    ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-202-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\".      .\","
			      "\"...... .\","
			      "\"..... ..\","
			      "\".... ...\","
			      "\"... ....\","
			      "\"... ....\","
			      "\".. .....\","
			      "\". ......\","
			      "\".      .\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-203-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"     \","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\".. ..\","
			      "\"... .\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-204-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"...   . .\","
			      "\".. ...  .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-205-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".     ...\","
			      "\". .... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-206-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\""
			      "};"))

(defvar rdict-207-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\". .  \","
			      "\".  ..\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\". ...\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-208-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\". ......\","
			      "\". ......\","
			      "\". ......\","
			      "\". .... .\","
			      "\". ... ..\","
			      "\". .. ...\","
			      "\". . ....\","
			      "\".   ....\","
			      "\". .. ...\","
			      "\". ... ..\","
			      "\". .... .\","
			      "\". ..... \","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-209-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\"...   . .\","
			      "\".. ...  .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".. ...  .\","
			      "\"...   . .\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"...... ..\","
			      "\"..    ...\""
			      "};"))

(defvar rdict-21-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\".. ......\","
			     "\"..  .....\","
			     "\". .. ....\","
			     "\". ... ...\","
			     "\".. ... ..\","
			     "\"... ... .\","
			     "\".... .. .\","
			     "\".....  ..\","
			     "\"...... ..\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-210-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\". .......\","
			      "\". .......\","
			      "\". .......\","
			      "\". .   ...\","
			      "\".  ... ..\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-211-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"3 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\"...\","
			      "\"...\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\". .\","
			      "\" ..\""
			      "};"))

(defvar rdict-212-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"8 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"..    ..\","
			      "\". .... .\","
			      "\". ......\","
			      "\". ......\","
			      "\"..   ...\","
			      "\". ......\","
			      "\". ......\","
			      "\". .... .\","
			      "\"..    ..\","
			      "\"........\","
			      "\"........\","
			      "\"........\","
			      "\"........\""
			      "};"))

(defvar rdict-213-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"9 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".      ..\","
			      "\"....... .\","
			      "\"....... .\","
			      "\"..      .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\". ..... .\","
			      "\"..     . \","
			      "\".........\","
			      "\".........\","
			      "\".........\","
			      "\".........\""
			      "};"))

(defvar rdict-22-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"5 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".   .\","
			     "\".   .\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\""
			     "};"))

(defvar rdict-249-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"5 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".   .\","
			      "\".   .\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\","
			      "\".....\""
			      "};"))

(defvar rdict-250-xpm (concat "/* XPM */"
			      "static char *magick[] = {"
			      "/* columns rows colors chars-per-pixel */"
			      "\"4 20 2 1\","
			      "\"  c #000000000000\","
			      "\". c None\","
			      "/* pixels */"
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"..  \","
			      "\".. .\","
			      "\". ..\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\","
			      "\"....\""
			      "};"))

(defvar rdict-32-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-33-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-34-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"6 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\". .. .\","
			     "\". .. .\","
			     "\". .. .\","
			     "\". .. .\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\""
			     "};"))

(defvar rdict-35-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"... .. ..\","
			     "\"... .. ..\","
			     "\"... .. ..\","
			     "\".       .\","
			     "\".. .. ...\","
			     "\".. .. ...\","
			     "\".. .. ...\","
			     "\".. .. ...\","
			     "\"       ..\","
			     "\". .. ....\","
			     "\". .. ....\","
			     "\". .. ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-36-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".... ....\","
			     "\"..     ..\","
			     "\". .. .. .\","
			     "\". .. .. .\","
			     "\". .. ....\","
			     "\". .. ....\","
			     "\"..     ..\","
			     "\".... .. .\","
			     "\".... .. .\","
			     "\".... .. .\","
			     "\". .. .. .\","
			     "\". .. .. .\","
			     "\"..     ..\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-37-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"14 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"..............\","
			     "\"..............\","
			     "\"..............\","
			     "\"..............\","
			     "\"..    ...... .\","
			     "\". .... .... ..\","
			     "\". .... ... ...\","
			     "\". .... .. ....\","
			     "\"..    .. .....\","
			     "\"....... ......\","
			     "\"...... .......\","
			     "\"..... ..    ..\","
			     "\".... .. .... .\","
			     "\"... ... .... .\","
			     "\".. .... .... .\","
			     "\". ......    ..\","
			     "\"..............\","
			     "\"..............\","
			     "\"..............\","
			     "\"..............\""
			     "};"))

(defvar rdict-38-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"11 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"...........\","
			     "\"...........\","
			     "\"...........\","
			     "\"...........\","
			     "\"...  ......\","
			     "\".. .. .....\","
			     "\".. .. .....\","
			     "\".. .. .....\","
			     "\"...  ......\","
			     "\"...  ......\","
			     "\".. .. .....\","
			     "\". .... .. .\","
			     "\". ..... . .\","
			     "\". ...... ..\","
			     "\". ..... . .\","
			     "\"..     ... \","
			     "\"...........\","
			     "\"...........\","
			     "\"...........\","
			     "\"...........\""
			     "};"))

(defvar rdict-39-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"3 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\". .\","
			     "\". .\","
			     "\". .\","
			     "\". .\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\","
			     "\"...\""
			     "};"))

(defvar rdict-40-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"5 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\"... .\","
			     "\".. ..\","
			     "\".. ..\","
			     "\".. ..\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\". ...\","
			     "\".. ..\","
			     "\".. ..\","
			     "\".. ..\","
			     "\"... .\","
			     "\".....\""
			     "};"))

(defvar rdict-41-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"5 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\". ...\","
			     "\".. ..\","
			     "\".. ..\","
			     "\".. ..\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\"... .\","
			     "\".. ..\","
			     "\".. ..\","
			     "\".. ..\","
			     "\". ...\","
			     "\".....\""
			     "};"))

(defvar rdict-42-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"6 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"... ..\","
			     "\". . . \","
			     "\"..   .\","
			     "\".. . .\","
			     "\". ... \","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\","
			     "\"......\""
			     "};"))

(defvar rdict-43-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".       .\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-44-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\". ..\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-45-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"5 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\"     \","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\""
			     "};"))

(defvar rdict-46-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-47-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"... \","
			     "\"... \","
			     "\"... \","
			     "\"... \","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\" ...\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-48-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-49-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".... ....\","
			     "\"..   ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-50-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\"....... .\","
			     "\"...... ..\","
			     "\"..... ...\","
			     "\".... ....\","
			     "\"... .....\","
			     "\".. ......\","
			     "\". .......\","
			     "\".       .\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-51-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". .... ..\","
			     "\"...   ...\","
			     "\"...... ..\","
			     "\"....... .\","
			     "\"....... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-52-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...... ..\","
			     "\".....  ..\","
			     "\".....  ..\","
			     "\".... . ..\","
			     "\"... .. ..\","
			     "\"... .. ..\","
			     "\".. ... ..\","
			     "\". .... ..\","
			     "\".       .\","
			     "\"...... ..\","
			     "\"...... ..\","
			     "\"...... ..\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-53-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".       .\","
			     "\". .......\","
			     "\". .......\","
			     "\". .......\","
			     "\".     ...\","
			     "\"...... ..\","
			     "\"....... .\","
			     "\"....... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-54-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". .......\","
			     "\".     ...\","
			     "\". .... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-55-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".       .\","
			     "\"....... .\","
			     "\"....... .\","
			     "\"...... ..\","
			     "\"...... ..\","
			     "\"..... ...\","
			     "\"..... ...\","
			     "\"..... ...\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-56-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-57-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".. .... .\","
			     "\"...     .\","
			     "\"....... .\","
			     "\". ..... .\","
			     "\".. ... ..\","
			     "\"...   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-58-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-59-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".. .\","
			     "\". ..\","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-60-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"......  .\","
			     "\"....  ...\","
			     "\"..  .....\","
			     "\". .......\","
			     "\"..  .....\","
			     "\"....  ...\","
			     "\"......  .\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-61-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".       .\","
			     "\".........\","
			     "\".........\","
			     "\".       .\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-62-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".  ......\","
			     "\"...  ....\","
			     "\".....  ..\","
			     "\"....... .\","
			     "\".....  ..\","
			     "\"...  ....\","
			     "\".  ......\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-63-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"...   ...\","
			     "\".. ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\"....... .\","
			     "\"...... ..\","
			     "\"..... ...\","
			     "\".... ....\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".... ....\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-64-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"16 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"................\","
			     "\"................\","
			     "\"................\","
			     "\"................\","
			     "\"......      ....\","
			     "\"....  ...... ...\","
			     "\"... ......... ..\","
			     "\".. ....   .... .\","
			     "\".. ... ... ... .\","
			     "\". ... .... ... .\","
			     "\". ... .... ... .\","
			     "\". ... ...  .. ..\","
			     "\". ....   .   ...\","
			     "\".. .............\","
			     "\"...  ......  ...\","
			     "\".....      .....\","
			     "\"................\","
			     "\"................\","
			     "\"................\","
			     "\"................\""
			     "};"))

(defvar rdict-7-xpm (concat "/* XPM */"
			    "static char *magick[] = {"
			    "/* columns rows colors chars-per-pixel */"
			    "\"5 20 2 1\","
			    "\"  c #000000000000\","
			    "\". c None\","
			    "/* pixels */"
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".. ..\","
			    "\".   .\","
			    "\".   .\","
			    "\".. ..\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\","
			    "\".....\""
			    "};"))

(defvar rdict-91-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".  .\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\".  .\","
			     "\"....\""
			     "};"))

(defvar rdict-92-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\" ...\","
			     "\" ...\","
			     "\" ...\","
			     "\" ...\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\". ..\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\"... \","
			     "\"....\","
			     "\"....\","
			     "\"....\""
			     "};"))

(defvar rdict-93-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"4 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\"....\","
			     "\".  .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".. .\","
			     "\".  .\","
			     "\"....\""
			     "};"))

(defvar rdict-94-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"7 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\"... ...\","
			     "\".. . ..\","
			     "\". ... .\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\","
			     "\".......\""
			     "};"))

(defvar rdict-95-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\"         \","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-96-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"5 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\". ...\","
			     "\".. ..\","
			     "\"... .\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\","
			     "\".....\""
			     "};"))

(defvar rdict-97-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".      ..\","
			     "\"....... .\","
			     "\"....... .\","
			     "\"..      .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\"..     . \","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-98-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"9 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\". .......\","
			     "\". .......\","
			     "\". .......\","
			     "\". .   ...\","
			     "\".  ... ..\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\". ..... .\","
			     "\".  ... ..\","
			     "\". .   ...\","
			     "\".........\","
			     "\".........\","
			     "\".........\","
			     "\".........\""
			     "};"))

(defvar rdict-99-xpm (concat "/* XPM */"
			     "static char *magick[] = {"
			     "/* columns rows colors chars-per-pixel */"
			     "\"8 20 2 1\","
			     "\"  c #000000000000\","
			     "\". c None\","
			     "/* pixels */"
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"...   ..\","
			     "\".. ... .\","
			     "\". ..... \","
			     "\". ......\","
			     "\". ......\","
			     "\". ......\","
			     "\". ..... \","
			     "\".. ... .\","
			     "\"...   ..\","
			     "\"........\","
			     "\"........\","
			     "\"........\","
			     "\"........\""
			     "};"))


(provide 'rdict)

;;; rdict.el ends here
