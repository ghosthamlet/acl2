;; AUTHORS:
;; Shilpi Goel <shigoel@cs.utexas.edu>
;; Robert Krug <rkrug@cs.utexas.edu>
;; Thanks to Dmitry Nadezhin for proving the equivalence of rm/wm128
;; to rb/wb.

(in-package "X86ISA")
(include-book "x86-ia32e-segmentation" :ttags (:undef-flg))
(include-book "centaur/bitops/merge" :dir :system)

;; ======================================================================

(local (include-book "guard-helpers"))
(local (include-book "centaur/bitops/ihs-extensions" :dir :system))
(local (include-book "centaur/bitops/signed-byte-p" :dir :system))
(local (include-book "arithmetic/top-with-meta" :dir :system))
(local (include-book "std/basic/inductions" :dir :system))

;; ======================================================================

(defsection x86-top-level-memory
  :parents (machine)
  :short "Top-Level Memory Accessor and Updater Functions"
  :long "<p>First, a quick note about virtual, linear, and physical
  addresses:</p>

<ul>
<li><i>Linear (or Virtual) Address:</i> In the flat memory model (see
Intel Vol. 1, Section 3.3.1), memory appears to a program as a single,
continuous address space, called a linear (or virtual) address
space. An address for any byte in linear address space is called a
linear address.  When paging is disabled, then a linear address is the
same as a physical address.</li>

<li><i>Physical Address:</i> The memory that the processor addresses
on its bus is called physical memory. Physical memory is organized as
a sequence of 8-bit bytes. Each byte is assigned a unique address,
called a physical address. When employing the processor s memory
management facilities, programs do not directly address physical
memory.</li>

</ul>" )

(local (xdoc::set-default-parents x86-top-level-memory))

;; ======================================================================

;; Some utilities to generate numerous (but efficient) RoW and WoW
;; kinda theorems:

(defun remove-elements-from-list (elems lst)
  (if (or (endp lst) (endp elems))
      lst
    (if (member (car lst) elems)
        (remove-elements-from-list (remove (car lst) elems) (cdr lst))
      (cons (car lst) (remove-elements-from-list elems (cdr lst))))))

(defun search-and-replace-once (search-term replace-term lst)
  (if (endp lst)
      nil
    (if (equal search-term (car lst))
        (cons replace-term (cdr lst))
      (cons (car lst) (search-and-replace-once search-term replace-term (cdr lst))))))

(defun generate-read-fn-over-xw-thms-1 (xw-fld read-fn read-fn-formals output-index hyps-term double-rewrite-in-concl?)
  ;; (generate-read-fn-over-xw-thms-1 :RGF 'gather-all-paging-structure-qword-addresses '(x86) -1 t t)
  (b* ((body
        (if (equal output-index -1)
            `(equal (,read-fn ,@(search-and-replace-once 'x86 `(XW ,xw-fld index val x86) read-fn-formals))
                    (,read-fn ,@(if double-rewrite-in-concl?
                                    (search-and-replace-once 'x86 '(double-rewrite x86) read-fn-formals)
                                  read-fn-formals)))
          `(equal (mv-nth ,output-index (,read-fn ,@(search-and-replace-once 'x86 `(XW ,xw-fld index val x86) read-fn-formals)))
                  (mv-nth ,output-index (,read-fn ,@(if double-rewrite-in-concl?
                                                        (search-and-replace-once 'x86 '(double-rewrite x86) read-fn-formals)
                                                      read-fn-formals)))))))
    `(defthm ,(mk-name (if (equal output-index -1) read-fn (mk-name "MV-NTH-" output-index "-" read-fn))  "-XW-" xw-fld)
       ,(if (atom hyps-term)
            body
          `(implies ,hyps-term ,body)))))

(defun generate-read-fn-over-xw-thms-aux (xw-flds read-fn read-fn-formals output-index hyps-term double-rewrite-in-concl?)
  (if (endp xw-flds)
      nil
    (cons
     (generate-read-fn-over-xw-thms-1 (car xw-flds) read-fn read-fn-formals output-index hyps-term double-rewrite-in-concl?)
     (generate-read-fn-over-xw-thms-aux (cdr xw-flds) read-fn read-fn-formals output-index hyps-term double-rewrite-in-concl?))))

(define generate-read-fn-over-xw-thms
  (xw-flds read-fn read-fn-formals
           &key
           (output-index '-1)
           (hyps 't)
           (double-rewrite? 'nil)
           (prepwork 'nil))
  :verify-guards nil
  ;; (generate-read-fn-over-xw-thms
  ;;  *x86-field-names-as-keywords*
  ;;  'rvm08
  ;;  (acl2::formals 'rvm08$inline (w state))
  ;;  :prepwork '((local (in-theory (e/d* () (xw))))))
  `(encapsulate ()
     ,@(or prepwork nil)
     ,@(generate-read-fn-over-xw-thms-aux xw-flds read-fn read-fn-formals output-index hyps double-rewrite?)))


(defun generate-write-fn-over-xw-thms-1 (xw-fld write-fn write-fn-formals output-index hyps-term)
  ;; (generate-write-fn-over-xw-thms-1 :RGF 'rvm08 '(addr x86) 2 t)
  (b* ((body
        (if (equal output-index -1)
            `(equal (,write-fn ,@(search-and-replace-once 'x86 `(XW ,xw-fld index val x86) write-fn-formals))
                    (XW ,xw-fld index val ,(cons write-fn write-fn-formals)))
          `(equal (mv-nth ,output-index (,write-fn ,@(search-and-replace-once 'x86 `(XW ,xw-fld index val x86) write-fn-formals)))
                  (XW ,xw-fld index val (mv-nth ,output-index ,(cons write-fn write-fn-formals)))))))
    `(defthm ,(mk-name (if (equal output-index -1) write-fn (mk-name "MV-NTH-" output-index "-" write-fn))  "-XW-" xw-fld)
       ,(if (atom hyps-term)
            body
          `(implies ,hyps-term ,body)))))

(defun generate-write-fn-over-xw-thms-aux (xw-flds write-fn write-fn-formals output-index hyps-term)
  (if (endp xw-flds)
      nil
    (cons (generate-write-fn-over-xw-thms-1 (car xw-flds) write-fn write-fn-formals output-index hyps-term)
          (generate-write-fn-over-xw-thms-aux (cdr xw-flds) write-fn write-fn-formals output-index hyps-term))))

(define generate-write-fn-over-xw-thms
  (xw-flds write-fn write-fn-formals
           &key
           (output-index '-1)
           (hyps 't)
           (prepwork 'nil))
  :verify-guards nil
  ;; (generate-write-fn-over-xw-thms
  ;;  *x86-field-names-as-keywords*
  ;;  'wvm08
  ;;  (acl2::formals 'wvm08$inline (w state))
  ;;  :prepwork '((local (in-theory (e/d* () (xw))))))
  `(encapsulate ()
     ,@(or prepwork nil)
     ,@(generate-write-fn-over-xw-thms-aux xw-flds write-fn write-fn-formals output-index hyps)))

(defun generate-xr-over-write-thms-1 (xr-fld write-fn write-fn-formals output-index hyps-term double-rewrite-in-concl?)
  ;; (generate-xr-over-write-thms-1 :RGF 'rb '(addr r-w-x x86) 2 t nil)
  (b* ((body
        (if (equal output-index -1)
            `(equal (XR ,xr-fld index ,(cons write-fn write-fn-formals))
                    (XR ,xr-fld index ,(if double-rewrite-in-concl?
                                           `(double-rewrite x86)
                                         `x86)))
          `(equal (XR ,xr-fld index (mv-nth ,output-index ,(cons write-fn write-fn-formals)))
                  (XR ,xr-fld index ,(if double-rewrite-in-concl?
                                         `(double-rewrite x86)
                                       `x86))))))
    `(defthm ,(mk-name "XR-" xr-fld "-" (if (equal output-index -1) write-fn (mk-name "MV-NTH-" output-index "-" write-fn)))
       ,(if (atom hyps-term)
            body
          `(implies ,hyps-term ,body)))))

(defun generate-xr-over-write-thms-aux (xr-flds write-fn write-fn-formals output-index hyps-term double-rewrite?)
  (if (endp xr-flds)
      nil
    (cons (generate-xr-over-write-thms-1 (car xr-flds) write-fn write-fn-formals output-index hyps-term double-rewrite?)
          (generate-xr-over-write-thms-aux (cdr xr-flds) write-fn write-fn-formals output-index hyps-term double-rewrite?))))

(define generate-xr-over-write-thms
  (xr-flds write-fn write-fn-formals
           &key
           (output-index '-1)
           (hyps 't)
           (double-rewrite? 'nil)
           (prepwork 'nil))
  :verify-guards nil
  ;; (generate-xr-over-write-thms
  ;;  *x86-field-names-as-keywords*
  ;;  'wvm08
  ;;  (acl2::formals 'wvm08$inline (w state))
  ;;  :prepwork '((local (in-theory (e/d* () (xw))))))
  `(encapsulate ()
     ,@(or prepwork nil)
     ,@(generate-xr-over-write-thms-aux xr-flds write-fn write-fn-formals output-index hyps double-rewrite?)))

;; ======================================================================

;; Some misc. arithmetic lemmas and macros:

(defthm signed-byte-p-limits-thm
  ;; i is positive, k is positive, k < i
  (implies (and (signed-byte-p n (+ i addr))
                (signed-byte-p n addr)
                (integerp k)
                (<= 0 k)
                (< k i))
           (signed-byte-p n (+ k addr))))

(local (in-theory (e/d* (rm16-guard-proof-helper
                         rb-and-rvm32-helper
                         rm32-guard-proof-helper
                         rb-and-rvm64-helper
                         rm64-guard-proof-helper)
                        ())))

(acl2::set-waterfall-parallelism t)

(defabbrev cpl (x86)
  (the (unsigned-byte 2)
    (seg-sel-layout-slice :rpl (the (unsigned-byte 16) (xr :seg-visible *cs* x86)))))

;; ======================================================================

#||

;; Help on the unraveling loghead meta rule by Matt Kaufmann.

;; Unraveling nests of loghead:

;; unravel-loghead-meta-lemma will help me avoid explicitly proving
;; theorems of the form loghead-12-of-x-+-3 used in the guard proofs
;; of rm* and wm* functions.

;; (defthm loghead-12-of-x-+-3
;;   (implies (integerp x)
;;            (equal (loghead 12 (+ 3 x))
;;                   (if (equal (loghead 12 x) (- (ash 1 12) 3))
;;                       0
;;                     (if (equal (loghead 12 x) (- (ash 1 12) 2))
;;                         1
;;                       (if (equal (loghead 12 x) (- (ash 1 12) 1))
;;                           2
;;                         (+ 3 (loghead 12 x))))))))


(defevaluator unravel-loghead-evl unravel-loghead-evl-list
  ((acl2::loghead$inline n x)
   (binary-+ m x)
   (if x y z)
   (car x)
   (cdr x)
   (integerp x)
   (natp x)
   (posp x)
   (equal x y)))

(defun unravel-loghead-1 (x n m m-copy)

  ;; Example invocation: (unravel-loghead-1 'x 12 5 5)

  ;; The args correspond to the args in the following call (with
  ;; m-copy being another copy of the arg m):
  ;; (loghead n (+ m x))

  (declare (xargs :guard (and (posp n)
                              (natp m)
                              (natp m-copy)
                              (<= m-copy m))))

  (if (zp m-copy)
      `(binary-+ (quote ,m) (acl2::loghead$inline (quote ,n) ,x))
    `(if (equal (acl2::loghead$inline (quote ,n) ,x) (quote ,(- (ash 1 n) m-copy)))
         (quote ,(- m m-copy))
       ,(unravel-loghead-1 x n m (1- m-copy)))))

(defthm pseudo-termp-unravel-loghead-1
  ;; Sanity check...
  (implies (and (natp n)
                (natp m)
                (natp m-copy)
                (symbolp x))
           (pseudo-termp (unravel-loghead-1 x n m m-copy))))

(defun unravel-loghead (term)
  (declare (xargs :guard (pseudo-termp term)))

  ;; Example invocation:
  ;; (unravel-loghead '(acl2::loghead$inline '12. (binary-+ '5. x)))

  (if (and (consp term)
           (equal (car term) 'acl2::loghead$inline)
           (quotep (cadr term)) ;; '12
           (equal (acl2::unquote (cadr term)) 12)
           (equal (len (caddr term)) 3)
           (equal (caaddr term) 'binary-+)
           (quotep (cadadr (cdr term)))
           (natp  (acl2::unquote (cadr (caddr term)))) ;; e.g., 5
           (< (acl2::unquote (cadr (caddr term))) 4096)
           (symbolp (cadr (cdaddr term)))) ;; x

      (unravel-loghead-1
       (cadr (cdaddr term))
       12 ;; (acl2::unquote (cadr term))
       (acl2::unquote (cadr (caddr term)))
       (acl2::unquote (cadr (caddr term)))
       )
    term))

(defthm pseudo-termp-unravel-loghead
  ;; Sanity check...
  (implies (pseudo-termp term)
           (pseudo-termp (unravel-loghead term))))

(defun unravel-loghead-hyp (term)
  ;; (unravel-loghead-hyp '(acl2::loghead$inline '12. (binary-+ '5. x)))
  (declare (xargs :guard (pseudo-termp term)))
  (if (and (consp term)
           (equal (car term) 'acl2::loghead$inline)
           (quotep (cadr term)) ;; '12
           (equal (acl2::unquote (cadr term)) 12)
           (equal (len (caddr term)) 3)
           (equal (caaddr term) 'binary-+)
           (quotep (cadadr (cdr term)))
           (natp  (acl2::unquote (cadr (caddr term)))) ;; e.g., 5
           (symbolp (cadr (cdaddr term))))             ;; x
      `(integerp ,(cadr (cdaddr term)))
    't))

(defthm pseudo-termp-unravel-loghead-hyp
  ;; Sanity check...
  (implies (pseudo-termp term)
           (pseudo-termp (unravel-loghead-hyp term))))

(encapsulate
  ()

  (local (include-book "arithmetic-5/top" :dir :system))

  (local (defthm equal-len-n
           (implies (and (syntaxp (quotep n))
                         (natp n))
                    (equal (equal (len x) n)
                           (if (equal n 0)
                               (atom x)
                             (and (consp x)
                                  (equal (len (cdr x)) (1- n))))))))

  (local
   (defthm loghead-12-bound
     (implies (integerp n)
              (<= (loghead 12 n) 4095))
     :hints (("Goal" :in-theory (enable loghead)))
     :rule-classes :linear))

  (local
   (defthm loghead-12-plus
     (implies (and (natp m)
                   (< m 4096)
                   (integerp n))
              (equal (loghead 12 (+ m n))
                     (if (< (+ m (loghead 12 n)) 4096)
                         (+ m (loghead 12 n))
                       (- (+ m (loghead 12 n))
                          4096))))
     :hints (("Goal" :in-theory (enable loghead)))))

  (local
   (defthm unravel-loghead-meta-lemma-main-lemma
     (implies
      (and (natp m)
           (natp m-copy)
           (<= m-copy m)
           (< m 4096)
           (alistp a)
           (symbolp x)
           (integerp (cdr (assoc-equal x a)))
           (not (and (<= (- 4096 m)
                         (loghead 12 (cdr (assoc-equal x a))))
                     (< (loghead 12 (cdr (assoc-equal x a)))
                        (- 4096 m-copy))))
           x)
      (equal (unravel-loghead-evl (unravel-loghead-1 x 12 m m-copy)
                                  a)
             (loghead 12
                      (+ m (cdr (assoc-equal x a))))))
     :hints (("Goal" :induct (unravel-loghead-1 x 12 m m-copy)))))

  (defthm unravel-loghead-meta-lemma
    (implies (and (pseudo-termp term)
                  (alistp a)
                  (unravel-loghead-evl (unravel-loghead-hyp term) a))
             (equal (unravel-loghead-evl term a)
                    (unravel-loghead-evl (unravel-loghead term) a)))
    :rule-classes ((:meta :trigger-fns (acl2::loghead$inline)))))

||#

;; ======================================================================
;; Events related to RB and WB:

(defsection reasoning-about-memory-reads-and-writes
  :parents (x86-top-level-memory)
  :short "Definitions of @(see rb) and @(see wb)"

  :long "<p>The functions @('rb') (read bytes) and @('wb') (write
 bytes) are used in reasoning about memory reads and writes. Functions
 like @('rm08'), @('rm16'), @('rm32'), and @('rm64') are reduced to
 @('rb'), and @('wm08'), @('wm16'), @('wm32'), and @('wm64') to
 @('wb') during reasoning.</p>"

  (local (xdoc::set-default-parents reasoning-about-memory-reads-and-writes))

  (define canonical-address-listp (lst)
    :short "Recognizer of a list of canonical addresses"
    :enabled t
    (if (equal lst nil)
        t
      (and (consp lst)
           (canonical-address-p (car lst))
           (canonical-address-listp (cdr lst))))
    ///
    (defthm cdr-canonical-address-listp
      (implies (canonical-address-listp x)
               (canonical-address-listp (cdr x)))))

  (define byte-listp (x)
    :short "Recognizer of a list of bytes"
    :enabled t
    (if (equal x nil)
        t
      (and (consp x)
           (n08p (car x))
           (byte-listp (cdr x))))
    ///

    (defthm byte-listp-implies-true-listp
      (implies (byte-listp x)
               (true-listp x))
      :rule-classes :forward-chaining)

    (defthm-usb n08p-element-of-byte-listp
      :hyp (and (byte-listp acc)
                (natp m)
                (< m (len acc)))
      :bound 8
      :concl (nth m acc)
      :gen-linear t
      :gen-type t)

    (defthm nthcdr-byte-listp
      (implies (byte-listp xs)
               (byte-listp (nthcdr n xs)))
      :rule-classes (:rewrite :type-prescription))

    (defthm len-of-nthcdr-byte-listp
      (implies (and (< m (len acc))
                    (natp m))
               (equal (len (nthcdr m acc))
                      (- (len acc) m))))

    (defthm byte-listp-revappend
      (implies (forced-and (byte-listp lst1)
                           (byte-listp lst2))
               (byte-listp (revappend lst1 lst2)))
      :rule-classes :type-prescription)

    (defthm true-listp-make-list-ac
      (implies (true-listp ac)
               (true-listp (make-list-ac n val ac)))
      :rule-classes :type-prescription)

    (defthm make-list-ac-byte-listp
      (implies (and (byte-listp x)
                    (natp n)
                    (n08p m))
               (byte-listp (make-list-ac n m x)))
      :rule-classes (:type-prescription :rewrite))

    (defthm reverse-byte-listp
      (implies (byte-listp x)
               (byte-listp (reverse x)))
      :rule-classes (:type-prescription :rewrite))

    (defthm byte-listp-append
      (implies (forced-and (byte-listp lst1)
                           (byte-listp lst2))
               (byte-listp (append lst1 lst2)))
      :rule-classes (:rewrite :type-prescription)))

  (define addr-byte-alistp (alst)
    :short "Recognizer of a list of address and byte pairs"
    :enabled t
    (if (atom alst)
        (equal alst nil)
      (if (atom (car alst))
          nil
        (let ((addr (caar alst))
              (byte (cdar alst))
              (rest (cdr  alst)))
          (and (canonical-address-p addr)
               (n08p byte)
               (addr-byte-alistp rest)))))
    ///

    (defthm addr-byte-alistp-fwd-chain-to-alistp
      (implies (addr-byte-alistp alst)
               (alistp alst))
      :rule-classes :forward-chaining)

    (defthm strip-cars-addr-byte-alistp-is-canonical-address-listp
      (implies (addr-byte-alistp alst)
               (canonical-address-listp (strip-cars alst)))
      :rule-classes (:type-prescription :rewrite))

    (defthm strip-cdrs-addr-byte-alistp-is-byte-listp
      (implies (addr-byte-alistp addr-lst)
               (byte-listp (strip-cdrs addr-lst)))
      :rule-classes (:type-prescription :rewrite))

    (defthm append-and-addr-byte-alistp
      (implies (and (addr-byte-alistp x)
                    (addr-byte-alistp y))
               (addr-byte-alistp (append x y)))))

  (defthm len-of-strip-cdrs
    (equal (len (strip-cdrs as)) (len as)))

  (defthm len-of-strip-cars
    (equal (len (strip-cars as)) (len as)))

  (define combine-bytes (bytes)
    :guard (byte-listp bytes)
    :enabled t
    (if (endp bytes)
        0
      (logior (car bytes)
              (ash (combine-bytes (cdr bytes)) 8)))

    ///
    (defthm natp-combine-bytes
      (implies (force (byte-listp bytes))
               (natp (combine-bytes bytes)))
      :rule-classes :type-prescription)

    (local
     (defthm plus-and-expt
       (implies (and (natp y)
                     (natp a)
                     (< a (expt 256 y))
                     (natp b)
                     (< b 256))
                (< (+ b (* 256 a))
                   (expt 256 (+ 1 y))))))

    (local (include-book "arithmetic-5/top" :dir :system))

    (local
     (in-theory (disable acl2::normalize-factors-gather-exponents
                         acl2::arith-5-active-flag
                         acl2::|(* c (expt d n))|)))

    (defthm size-of-combine-bytes
      (implies (and (byte-listp bytes)
                    (equal l (len bytes)))
               (< (combine-bytes bytes) (expt 2 (ash l 3))))
      :hints (("Goal" :in-theory (e/d* (logapp) ())))
      :rule-classes :linear)

    (defthm unsigned-byte-p-of-combine-bytes
      (implies (and (byte-listp bytes)
                    (equal n (ash (len bytes) 3)))
               (unsigned-byte-p n (combine-bytes bytes)))
      :rule-classes ((:rewrite)
                     (:linear
                      :corollary
                      (implies (and (byte-listp bytes)
                                    (equal n (ash (len bytes) 3)))
                               (<= 0 (combine-bytes bytes)))))))

  (define byte-ify-general
    ((n   natp)
     (val integerp)
     (acc byte-listp))

    :short "@('byte-ify-general') takes an integer @('val') and
  converts it into a list of @('n') bytes."

    :long "<p>The list produced by @('byte-ify-general') has the least
  significant byte as its the first element. Some clarifying examples
  are as follows:</p>

  <ul>
  <li><code>(byte-ify-general 6 #xAABBCCDDEEFF nil) = (#xFF #xEE #xDD #xCC #xBB #xAA)</code></li>
  <li><code>(byte-ify-general 4 #xAABBCCDDEEFF nil) = (#xFF #xEE #xDD #xCC)</code></li>
  <li><code>(byte-ify-general 8 #xAABBCCDDEEFF nil) = (#xFF #xEE #xDD #xCC #xBB #xAA  #x0 #x0)</code></li>
  <li><code>(byte-ify-general 8             -1 nil) = (#xFF #xFF #xFF #xFF #xFF #xFF #xFF #xFF)</code></li>
  </ul>"


    (if (mbt (byte-listp acc))

        (b* ((n (mbe :logic (nfix n) :exec n))
             (val (mbe :logic (ifix val) :exec val)))

          (if (zp n)
              (reverse acc)
            (b* ((acc (cons (loghead 8 val) acc))
                 (val (logtail 8 val)))
              (byte-ify-general (1- n) val acc))))
      nil)

    ///

    (defthm byte-listp-byte-ify-general
      (implies (byte-listp acc)
               (byte-listp (byte-ify-general n val acc)))
      :hints (("Goal" :in-theory
               (e/d ()
                    (force acl2::reverse-removal
                           reverse (force))))))

    (defthm len-of-byte-ify-general
      (implies (and (natp n)
                    (integerp val)
                    (byte-listp acc))
               (equal (len (byte-ify-general n val acc))
                      (+ n (len acc)))))

    (defthm consp-byte-ify-general
      (implies (and (natp n)
                    (integerp val)
                    (byte-listp acc)
                    (or (consp acc)
                        (< 0 n)))
               (consp (byte-ify-general n val acc))))

    (local (include-book "std/lists/nthcdr" :dir :system))

    (defthm consp-nthcdr-of-byte-ify-general
      (implies (and (integerp val)
                    (natp n)
                    (natp m)
                    (< m n)
                    (byte-listp acc))
               (consp (nthcdr m (byte-ify-general n val acc))))
      :rule-classes :type-prescription)

    (defthm len-of-nthcdr-of-byte-ify-general
      (implies (and (natp n)
                    (natp m)
                    (< m n)
                    (integerp val)
                    (byte-listp acc))
               (equal (len (nthcdr m (byte-ify-general n val acc)))
                      (- (+ n (len acc)) m)))
      :hints (("Goal" :in-theory (e/d (nfix) ())))
      :rule-classes :linear)

    (defthmd byte-ify-opener
      (implies (and (syntaxp (quotep n))
                    (posp n))
               (equal (byte-ify-general n val acc)
                      (byte-ify-general (1- n) (logtail 8 val) (cons (loghead 8 val) acc))))))

  (define byte-ify ((n natp) (val integerp))
    :short "@('byte-ify') takes an integer @('val') and converts it
  into a list of at least @('n') bytes."

    :long "<p>The least significant byte is the first element of the
  list produced by @('byte-ify'). A couple of clairifying examples are
  as follows:</p>

  <ul>
  <li><code>(byte-ify 6 #xAABBCCDDEEFF) = (#xFF #xEE #xDD #xCC #xBB #xAA)</code></li>
  <li><code>(byte-ify 8 #xAABBCCDDEEFF) = (#xFF #xEE #xDD #xCC #xBB #x0 #x0 #x0)</code></li>
  </ul>"

    ;; This is logically equal to just (byte-ify-general n val nil), but
    ;; reasoning about logheads and logtails in the common case is
    ;; easier. Anyway, the theorem byte-ify-and-byte-ify-general establishes a
    ;; relationship between byte-ify and byte-ify-general, but it's kept
    ;; disabled.
    (case n
      (0 nil)
      (1 (list (part-select val :low 0  :width 8)))
      (2 (list (part-select val :low 0  :width 8)
               (part-select val :low 8  :width 8)))
      (4 (list (part-select val :low 0  :width 8)
               (part-select val :low 8  :width 8)
               (part-select val :low 16 :width 8)
               (part-select val :low 24 :width 8)))
      (6 (list (part-select val :low 0  :width 8)
               (part-select val :low 8  :width 8)
               (part-select val :low 16 :width 8)
               (part-select val :low 24 :width 8)
               (part-select val :low 32 :width 8)
               (part-select val :low 40 :width 8)))
      (8 (list (part-select val :low 0  :width 8)
               (part-select val :low 8  :width 8)
               (part-select val :low 16 :width 8)
               (part-select val :low 24 :width 8)
               (part-select val :low 32 :width 8)
               (part-select val :low 40 :width 8)
               (part-select val :low 48 :width 8)
               (part-select val :low 56 :width 8)))
      (10 (list (part-select val :low 0   :width 8)
                (part-select val :low 8   :width 8)
                (part-select val :low 16  :width 8)
                (part-select val :low 24  :width 8)
                (part-select val :low 32  :width 8)
                (part-select val :low 40  :width 8)
                (part-select val :low 48  :width 8)
                (part-select val :low 56  :width 8)
                (part-select val :low 64  :width 8)
                (part-select val :low 72  :width 8)))
      (16 (list (part-select val :low 0   :width 8)
                (part-select val :low 8   :width 8)
                (part-select val :low 16  :width 8)
                (part-select val :low 24  :width 8)
                (part-select val :low 32  :width 8)
                (part-select val :low 40  :width 8)
                (part-select val :low 48  :width 8)
                (part-select val :low 56  :width 8)
                (part-select val :low 64  :width 8)
                (part-select val :low 72  :width 8)
                (part-select val :low 80  :width 8)
                (part-select val :low 88  :width 8)
                (part-select val :low 96  :width 8)
                (part-select val :low 104 :width 8)
                (part-select val :low 112 :width 8)
                (part-select val :low 120 :width 8)))
      (otherwise (byte-ify-general n val nil)))

    ///

    (defthmd byte-ify-and-byte-ify-general
      (equal (byte-ify n val)
             (byte-ify-general n val nil))
      :hints (("Goal" :in-theory (e/d* (byte-ify-opener
                                        byte-ify-general)
                                       ()))))
    (defthm byte-listp-byte-ify
      (byte-listp (byte-ify n val)))

    (defthm len-of-byte-ify
      (implies (and (natp n)
                    (integerp val))
               (equal (len (byte-ify n val)) n)))

    (defthm consp-byte-ify
      (implies (and (natp n)
                    (integerp val)
                    (< 0 n))
               (consp (byte-ify n val)))
      :hints (("Goal" :in-theory (e/d (byte-ify) ()))))

    (local (include-book "std/lists/nthcdr" :dir :system))

    (defthm consp-nthcdr-of-byte-ify
      (implies  (and (integerp val)
                     (natp n)
                     (natp m)
                     (< m n))
                (consp (nthcdr m (byte-ify n val))))
      :hints (("Goal" :in-theory (e/d (nfix) ())))
      :rule-classes :type-prescription)

    (defthm len-of-nthcdr-of-byte-ify
      (implies (and (natp n)
                    (natp m)
                    (< m n)
                    (integerp val))
               (equal (len (nthcdr m (byte-ify n val)))
                      (- n m)))
      :hints (("Goal" :in-theory (e/d (nfix) ())))))

  ;; Definition of RB and other related events:

  (local
   (defthm append-3
     (equal (append (append x y) z)
            (append x y z))))

  (define rb-1
    ((addresses)
     (r-w-x    :type (member  :r :x))
     (x86) (acc))

    :guard (and (canonical-address-listp addresses)
                (byte-listp acc))

    :enabled t

    (if (mbt (canonical-address-listp addresses))

        (if (endp addresses)
            (mv nil acc x86)
          (b* ((addr (car addresses))
               ;; rb-1 is used only in the programmer-level mode, so
               ;; it makes sense to use rvm08 here.
               ((mv flg byte x86)
                (rvm08 addr x86))
               ((when flg)
                ;; Note: the bytes returned are nil, not acc.
                (mv flg nil x86)))
            (rb-1 (cdr addresses) r-w-x x86 (append acc (list byte)))))

      (mv t acc x86))

    ///

    (defthm rb-1-returns-byte-listp
      (implies (and (byte-listp acc)
                    (x86p x86))
               (byte-listp (mv-nth 1 (rb-1 addresses r-w-x x86 acc))))
      :rule-classes (:rewrite :type-prescription))

    (defthm rb-1-returns-x86p
      (implies (x86p x86)
               (x86p (mv-nth 2 (rb-1 addresses r-w-x x86 acc)))))

    (defthm rb-1-returns-x86-programmer-level-mode
      (implies (programmer-level-mode x86)
               (equal (mv-nth 2 (rb-1 addresses r-w-x x86 acc))
                      x86)))

    (defthm rb-1-returns-no-error-programmer-level-mode
      (implies (and (canonical-address-listp addresses)
                    (programmer-level-mode x86))
               (equal (mv-nth 0 (rb-1 addresses r-w-x x86 acc))
                      nil))
      :hints (("Goal" :in-theory (e/d (rvm08) ()))))

    (local
     (defthm rb-1-accumulator-thm-helper
       (equal (mv-nth 1 (rb-1 addresses r-w-x x86 (append acc1 acc2)))
              (append acc1 (mv-nth 1 (rb-1 addresses r-w-x x86 acc2))))))

    (defthm rb-1-accumulator-thm
      (implies (and (syntaxp (not (and (quotep acc)
                                       (eq (car (acl2::unquote acc)) nil))))
                    (true-listp acc))
               (equal (mv-nth 1 (rb-1 addresses r-w-x x86 acc))
                      (append acc (mv-nth 1 (rb-1 addresses r-w-x x86 nil))))))

    (defthm len-of-rb-1-in-programmer-level-mode
      (implies (and (programmer-level-mode x86)
                    (canonical-address-listp addresses)
                    (byte-listp acc))
               (equal (len (mv-nth 1 (rb-1 addresses r-w-x x86 acc)))
                      (+ (len acc) (len addresses))))))

  (define las-to-pas
    (l-addrs
     (r-w-x :type (member :r :w :x))
     (cpl   :type (unsigned-byte 2))
     x86)
    :enabled t
    :guard (and (not (programmer-level-mode x86))
                (canonical-address-listp l-addrs))

    (if (atom l-addrs)
        (mv nil nil x86)

      (b* (((mv flg p-addr x86)
            (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86))
           ((when flg) (mv flg nil x86))
           ((mv flgs p-addrs x86)
            (las-to-pas (cdr l-addrs) r-w-x cpl x86)))
        (mv flgs (if flgs nil (cons p-addr p-addrs)) x86)))

    ///

    (defthm consp-mv-nth-1-las-to-pas
      (implies (and (not (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86)))
                    (consp l-addrs))
               (consp (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86))))
      :hints (("Goal" :in-theory (e/d* (las-to-pas) ())))
      :rule-classes (:rewrite :type-prescription))

    (defthm true-listp-mv-nth-1-las-to-pas
      (true-listp (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86)))
      :rule-classes (:rewrite :type-prescription))

    (defthm car-mv-nth-1-las-to-pas
      (implies (and (not (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86)))
                    (consp l-addrs))
               (equal (car (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86)))
                      (mv-nth 1 (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86))))
      :hints (("Goal" :in-theory (e/d* (las-to-pas) ()))))

    (defthm physical-address-listp-mv-nth-1-las-to-pas
      (physical-address-listp (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86))))

    (defthm x86p-mv-nth-2-las-to-pas
      (implies (x86p x86)
               (x86p (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))))

    (defthm las-to-pas-l-addrs=nil
      (and (equal (mv-nth 0 (las-to-pas nil r-w-x cpl x86)) nil)
           (equal (mv-nth 1 (las-to-pas nil r-w-x cpl x86)) nil)
           (equal (mv-nth 2 (las-to-pas nil r-w-x cpl x86)) x86)))

    (local
     (defthm xr-las-to-pas
       (implies
        (and (not (equal fld :mem))
             (not (equal fld :fault)))
        (equal (xr fld index (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))
               (xr fld index x86)))
       :hints (("Goal" :in-theory (e/d* () (force (force)))))))

    (make-event
     (generate-xr-over-write-thms
      (remove-elements-from-list
       '(:mem :fault)
       *x86-field-names-as-keywords*)
      'las-to-pas
      (acl2::formals 'las-to-pas (w state))
      :output-index 2))

    (defthm flgi-las-to-pas
      (equal (flgi index (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))
             (flgi index x86))
      :hints (("Goal" :in-theory (e/d* (flgi) (force (force))))))

    (defthm xr-fault-las-to-pas
      (implies (not (mv-nth 0 (las-to-pas l-addrs r-w-x cpl (double-rewrite x86))))
               (equal (xr :fault 0 (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))
                      (xr :fault 0 x86)))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (local (in-theory (e/d () (xr-las-to-pas))))

    ;; The following two make-events generate a bunch of rules that
    ;; together say the same thing as las-to-pas-xw-values, but these
    ;; rules are more efficient than las-to-pas-xw-values as they
    ;; match less frequently.
    (make-event
     (generate-read-fn-over-xw-thms
      (remove-elements-from-list
       '(:mem :rflags :fault :ctr :msr :programmer-level-mode :page-structure-marking-mode)
       *x86-field-names-as-keywords*)
      'las-to-pas
      (acl2::formals 'las-to-pas (w state))
      :output-index 0))

    (make-event
     (generate-read-fn-over-xw-thms
      (remove-elements-from-list
       '(:mem :rflags :fault :ctr :msr :programmer-level-mode :page-structure-marking-mode)
       *x86-field-names-as-keywords*)
      'las-to-pas
      (acl2::formals 'las-to-pas (w state))
      :output-index 1))

    (defthm las-to-pas-xw-rflags-not-ac
      (implies (equal (rflags-slice :ac value)
                      (rflags-slice :ac (rflags x86)))
               (and
                (equal (mv-nth 0 (las-to-pas l-addrs r-w-x cpl (xw :rflags 0 value x86)))
                       (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86)))
                (equal (mv-nth 1 (las-to-pas l-addrs r-w-x cpl (xw :rflags 0 value x86)))
                       (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86))))))

    ;; The following make-event generate a bunch of rules that
    ;; together say the same thing as las-to-pas-xw-state, but these
    ;; rules are more efficient than las-to-pas-xw-state as they match
    ;; less frequently.
    (make-event
     (generate-write-fn-over-xw-thms
      (remove-elements-from-list
       '(:mem :rflags :fault :ctr :msr :programmer-level-mode :page-structure-marking-mode)
       *x86-field-names-as-keywords*)
      'las-to-pas
      (acl2::formals 'las-to-pas (w state))
      :output-index 2))

    (defthm las-to-pas-xw-rflags-state-not-ac
      (implies (equal (rflags-slice :ac value)
                      (rflags-slice :ac (rflags x86)))
               (equal (mv-nth 2 (las-to-pas l-addrs r-w-x cpl (xw :rflags 0 value x86)))
                      (xw :rflags 0 value (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm mv-nth-2-las-to-pas-system-level-non-marking-mode
      (implies (and (not (page-structure-marking-mode x86))
                    (not (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86))))
               (equal (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86))
                      x86))
      :hints (("Goal" :in-theory (e/d (las-to-pas) (force (force))))))

    (defthm len-of-mv-nth-1-las-to-pas
      (implies (not (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86)))
               (equal (len (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86)))
                      (len l-addrs))))

    (defthm las-to-pas-values-and-!flgi
      (implies (and (not (equal index *ac*))
                    (x86p x86))
               (and (equal (mv-nth 0 (las-to-pas l-addrs r-w-x cpl (!flgi index value x86)))
                           (mv-nth 0 (las-to-pas l-addrs r-w-x cpl (double-rewrite x86))))
                    (equal (mv-nth 1 (las-to-pas l-addrs r-w-x cpl (!flgi index value x86)))
                           (mv-nth 1 (las-to-pas l-addrs r-w-x cpl (double-rewrite x86))))))
      :hints
      (("Goal"
        :do-not-induct t
        :cases ((equal index *iopl*))
        :use
        ((:instance rflags-slice-ac-simplify
                    (index index)
                    (rflags (xr :rflags 0 x86)))
         (:instance las-to-pas-xw-rflags-not-ac
                    (value (logior (loghead 32 (ash (loghead 1 value) (nfix index)))
                                   (logand (xr :rflags 0 x86)
                                           (loghead 32 (lognot (expt 2 (nfix index))))))))
         (:instance las-to-pas-xw-rflags-not-ac
                    (value (logior (ash (loghead 2 value) 12)
                                   (logand 4294955007 (xr :rflags 0 x86))))))
        :in-theory (e/d* (!flgi-open-to-xw-rflags)
                         (las-to-pas-xw-rflags-not-ac)))))

    (defthm las-to-pas-values-and-!flgi-undefined
      (implies (and (not (equal index *ac*))
                    (x86p x86))
               (and (equal (mv-nth 0 (las-to-pas l-addrs r-w-x cpl (!flgi-undefined index x86)))
                           (mv-nth 0 (las-to-pas l-addrs r-w-x cpl x86)))
                    (equal (mv-nth 1 (las-to-pas l-addrs r-w-x cpl (!flgi-undefined index x86)))
                           (mv-nth 1 (las-to-pas l-addrs r-w-x cpl x86)))))
      :hints (("Goal" :in-theory (e/d* (!flgi-undefined) (las-to-pas)))))

    (defthm mv-nth-2-las-to-pas-and-!flgi-not-ac-commute
      (implies (and (not (equal index *ac*))
                    (x86p x86))
               (equal (mv-nth 2 (las-to-pas l-addrs r-w-x cpl (!flgi index value x86)))
                      (!flgi index value (mv-nth 2 (las-to-pas l-addrs r-w-x cpl x86)))))
      :hints
      (("Goal"
        :do-not-induct t
        :cases ((equal index *iopl*))
        :use
        ((:instance rflags-slice-ac-simplify
                    (index index)
                    (rflags (xr :rflags 0 x86)))
         (:instance las-to-pas-xw-rflags-state-not-ac
                    (value (logior (loghead 32 (ash (loghead 1 value) (nfix index)))
                                   (logand (xr :rflags 0 x86)
                                           (loghead 32 (lognot (expt 2 (nfix index))))))))
         (:instance las-to-pas-xw-rflags-state-not-ac
                    (value (logior (ash (loghead 2 value) 12)
                                   (logand 4294955007 (xr :rflags 0 x86))))))
        :in-theory (e/d* (!flgi-open-to-xw-rflags)
                         (las-to-pas-xw-rflags-state-not-ac))))))

  (define las-to-pas-tailrec
    (l-addrs
     (p-addrs physical-address-listp)
     (r-w-x :type (member :r :w :x))
     (cpl   :type (unsigned-byte 2))
     x86)
    :short "Used to discharge @('mbe') proof obligations for @(see
    rm128) and @(see wm128)"
    :enabled t
    :guard (and (not (programmer-level-mode x86))
                (canonical-address-listp l-addrs))

    (if (atom l-addrs)
        (mv nil (acl2::rev p-addrs) x86)

      (b* (((mv flg p-addr x86)
            (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86))
           ((when flg) (mv flg nil x86)))
        (las-to-pas-tailrec
         (cdr l-addrs) (cons p-addr p-addrs) r-w-x cpl x86)))

    ///

    (defthmd las-to-pas-tailrec-opener
      (implies
       (consp l-addrs)
       (equal
        (las-to-pas-tailrec l-addrs p-addrs r-w-x cpl x86)
        (mv-let
          (flg p-addr x86)
          (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86)
          (if flg
              (mv flg () x86)
            (las-to-pas-tailrec (cdr l-addrs) (cons p-addr p-addrs) r-w-x cpl x86))))))

    (defthmd las-to-pas-tailrec-nil
      (equal
       (las-to-pas-tailrec () p-addrs r-w-x cpl x86)
       (mv nil (acl2::rev p-addrs) x86)))

    (local
     (defthmd las-to-pas-tailrec-as-las-to-pas-lemma
       (b* (((mv flg-new p-addrs-new x86-new)
             (las-to-pas l-addrs r-w-x cpl x86))
            ((mv flg-alt p-addrs-alt x86-alt)
             (las-to-pas-tailrec l-addrs p-addrs r-w-x cpl x86)))
         (and (equal flg-alt flg-new)
              (equal p-addrs-alt
                     (if flg-new
                         ()
                       (revappend p-addrs p-addrs-new)))
              (equal x86-alt x86-new)))
       :hints (("Goal" :induct (las-to-pas-tailrec
                                l-addrs p-addrs r-w-x cpl x86)))))

    (local
     (defthm las-to-pas-as-list
       (let ((mv (las-to-pas l-addrs r-w-x cpl x86)))
         (equal mv (list (mv-nth 0 mv)
                         (mv-nth 1 mv)
                         (mv-nth 2 mv))))
       :rule-classes ()))

    (local
     (defthm las-to-pas-tailrec-as-list
       (let ((mv (las-to-pas-tailrec l-addrs p-addrs r-w-x cpl x86)))
         (equal mv (list (mv-nth 0 mv)
                         (mv-nth 1 mv)
                         (mv-nth 2 mv))))
       :rule-classes ()))

    (local
     (defrule last-to-pas-when-flg
       (b* (((mv flg p-addrs ?x86) (las-to-pas l-addrs r-w-x cpl x86)))
         (implies flg (not p-addrs)))))

    (defthmd las-to-pas-as-las-to-pas-tailrec
      (equal (las-to-pas l-addrs r-w-x cpl x86)
             (las-to-pas-tailrec l-addrs () r-w-x cpl x86))
      :hints (("Goal" :use
               (las-to-pas-as-list
                (:instance las-to-pas-tailrec-as-list (p-addrs ()))
                (:instance las-to-pas-tailrec-as-las-to-pas-lemma (p-addrs ())))))))

  (define read-from-physical-memory
    ((p-addrs physical-address-listp)
     x86)
    :parents (reasoning-about-memory-reads-and-writes x86-physical-memory)
    :enabled t
    :guard (not (programmer-level-mode x86))
    :returns (lst byte-listp :hyp :guard)
    (if (endp p-addrs)
        nil
      (b* ((addr (car p-addrs))
           (byte (memi addr x86)))
        (cons byte (read-from-physical-memory (cdr p-addrs) x86))))

    ///

    (defthm len-of-read-from-physical-memory
      (equal (len (read-from-physical-memory p-addrs x86))
             (len p-addrs)))

    (defthm cdr-read-from-physical-memory
      (equal (cdr (read-from-physical-memory p-addrs x86))
             (read-from-physical-memory (cdr p-addrs) x86)))

    (defthm read-from-physical-memory-!flgi
      (equal (read-from-physical-memory p-addrs (!flgi index val x86))
             (read-from-physical-memory p-addrs x86)))

    (defthm read-from-physical-memory-xw-not-mem
      (implies (not (equal fld :mem))
               (equal (read-from-physical-memory p-addrs (xw fld index val x86))
                      (read-from-physical-memory p-addrs x86)))))

  (define rb ((l-addrs canonical-address-listp)
              (r-w-x :type (member :r :x))
              (x86))
    :enabled t

    (if (programmer-level-mode x86)
        (rb-1 l-addrs r-w-x x86 nil)
      (b* (((mv flgs p-addrs x86)
            (las-to-pas l-addrs r-w-x (cpl x86) x86))
           ((when flgs) (mv flgs nil x86))
           (bytes (read-from-physical-memory p-addrs x86)))
        (mv nil bytes x86)))

    ///

    (defthmd rb-is-rb-1-for-programmer-level-mode
      (implies (programmer-level-mode x86)
               (equal (rb l-addrs r-w-x x86)
                      (rb-1 l-addrs r-w-x x86 nil))))

    (defthm rb-returns-byte-listp
      (implies (x86p x86)
               (byte-listp (mv-nth 1 (rb addresses r-w-x x86))))
      :rule-classes (:rewrite :type-prescription))

    (defthm rb-returns-x86p
      (implies (x86p x86)
               (x86p (mv-nth 2 (rb l-addrs r-w-x x86)))))

    (defthm rb-returns-no-error-programmer-level-mode
      (implies (and (canonical-address-listp l-addrs)
                    (programmer-level-mode x86))
               (equal (mv-nth 0 (rb l-addrs r-w-x x86)) nil)))

    (defthm len-of-rb-in-programmer-level-mode
      (implies (and (programmer-level-mode x86)
                    (canonical-address-listp addresses))
               (equal (len (mv-nth 1 (rb addresses r-w-x x86)))
                      (len addresses))))

    (defthm rb-returns-x86-programmer-level-mode
      (implies (and (programmer-level-mode x86)
                    (x86p x86))
               (equal (mv-nth 2 (rb addresses r-w-x x86)) x86)))

    (defthm len-of-rb-in-system-level-mode
      (implies (and (not (mv-nth 0 (las-to-pas l-addrs r-w-x (cpl x86) x86)))
                    (not (xr :programmer-level-mode 0 x86)))
               (equal (len (mv-nth 1 (rb l-addrs r-w-x x86))) (len l-addrs)))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm rb-values-and-!flgi-in-system-level-mode
      (implies (and (not (equal index *ac*))
                    (not (programmer-level-mode x86))
                    (x86p x86))
               (and (equal (mv-nth 0 (rb lin-addr r-w-x (!flgi index value x86)))
                           (mv-nth 0 (rb lin-addr r-w-x x86)))
                    (equal (mv-nth 1 (rb lin-addr r-w-x (!flgi index value x86)))
                           (mv-nth 1 (rb lin-addr r-w-x x86)))))
      :hints (("Goal"
               :do-not-induct t
               :in-theory (e/d* (rb) ()))))

    (defthm rb-values-and-!flgi-undefined-in-system-level-mode
      (implies (and (not (equal index *ac*))
                    (not (programmer-level-mode x86))
                    (x86p x86))
               (and (equal (mv-nth 0 (rb lin-addr r-w-x (!flgi-undefined index x86)))
                           (mv-nth 0 (rb lin-addr r-w-x x86)))
                    (equal (mv-nth 1 (rb lin-addr r-w-x (!flgi-undefined index x86)))
                           (mv-nth 1 (rb lin-addr r-w-x x86)))))
      :hints (("Goal"
               :do-not-induct t
               :in-theory (e/d* (!flgi-undefined) ())))))

  ;; Definition of WB and other related events:

  (define page-faults-during-translation-p
    (l-addrs
     (r-w-x :type (member :r :w :x))
     (cpl   :type (unsigned-byte 2))
     x86)
    :enabled t
    :non-executable t
    :short "Returns the first error flag, if any, encountered during
    the translation of linear addresses @('l-addrs')"
    :guard (and (not (programmer-level-mode x86))
                (canonical-address-listp l-addrs))

    (if (atom l-addrs)
        (mv (not (eql l-addrs nil)) x86)
      (if (mv-nth 0 (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86))
          (mv (mv-nth 0 (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86))
              (mv-nth 2 (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86)))
        (page-faults-during-translation-p
         (cdr l-addrs) r-w-x cpl
         (mv-nth 2 (ia32e-la-to-pa (car l-addrs) r-w-x cpl x86)))))

    ///

    (defthm x86p-mv-nth-1-page-faults-during-translation-p
      (implies (x86p x86)
               (x86p (mv-nth 1 (page-faults-during-translation-p l-addrs r-w-x cpl x86)))))

    (defthm xr-page-faults-during-translation-p
      (implies (and (not (equal fld :mem))
                    (not (equal fld :fault)))
               (equal (xr fld index
                          (mv-nth 1
                                  (page-faults-during-translation-p
                                   l-addrs r-w-x cpl x86)))
                      (xr fld index x86)))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm page-faults-during-translation-p-xw-values
      (implies (and (not (equal fld :mem))
                    (not (equal fld :rflags))
                    (not (equal fld :fault))
                    (not (equal fld :ctr))
                    (not (equal fld :msr))
                    (not (equal fld :programmer-level-mode))
                    (not (equal fld :page-structure-marking-mode)))
               (equal (mv-nth 0 (page-faults-during-translation-p l-addrs r-w-x cpl (xw fld index value x86)))
                      (mv-nth 0 (page-faults-during-translation-p l-addrs r-w-x cpl x86)))))

    (defthm page-faults-during-translation-p-xw-rflags-not-ac
      (implies (equal (rflags-slice :ac value)
                      (rflags-slice :ac (rflags x86)))
               (equal (mv-nth 0
                              (page-faults-during-translation-p l-addrs r-w-x cpl
                                                                (xw :rflags 0 value x86)))
                      (mv-nth 0
                              (page-faults-during-translation-p l-addrs r-w-x cpl x86)))))

    (defthm page-faults-during-translation-p-xw-state
      (implies (and (not (equal fld :mem))
                    (not (equal fld :rflags))
                    (not (equal fld :fault))
                    (not (equal fld :ctr))
                    (not (equal fld :msr))
                    (not (equal fld :programmer-level-mode))
                    (not (equal fld :page-structure-marking-mode)))
               (equal (mv-nth 1
                              (page-faults-during-translation-p l-addrs r-w-x cpl
                                                                (xw fld index value x86)))
                      (xw fld index value
                          (mv-nth 1
                                  (page-faults-during-translation-p l-addrs r-w-x cpl
                                                                    x86)))))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm page-faults-during-translation-p-xw-rflags-state-not-ac
      (implies (equal (rflags-slice :ac value)
                      (rflags-slice :ac (rflags x86)))
               (equal (mv-nth 1
                              (page-faults-during-translation-p l-addrs r-w-x cpl
                                                                (xw :rflags 0 value x86)))
                      (xw :rflags 0 value
                          (mv-nth 1 (page-faults-during-translation-p l-addrs r-w-x cpl x86)))))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm mv-nth-2-page-faults-during-translation-p-system-level-non-marking-mode
      (implies (and (not (page-structure-marking-mode x86))
                    (not (mv-nth 0 (page-faults-during-translation-p
                                    l-addrs r-w-x cpl x86))))
               (equal (mv-nth 1 (page-faults-during-translation-p l-addrs r-w-x cpl x86))
                      x86))
      :hints (("Goal" :in-theory (e/d (page-faults-during-translation-p) (force (force)))))))

  (define wb-1 (addr-lst x86)

    :guard (addr-byte-alistp addr-lst)
    :enabled t

    (if (mbt (addr-byte-alistp addr-lst))

        (if (endp addr-lst)
            (mv nil x86)
          (b* ((addr (caar addr-lst))
               (byte (cdar addr-lst))
               ((mv flg x86)
                ;; wb-1 is used only in the programmer-level mode, so
                ;; it makes sense to use wvm08 here.
                (wvm08 addr byte x86))
               ((when flg)
                (mv flg x86)))
            (wb-1 (cdr addr-lst) x86)))

      (mv t x86))

    ///

    (defthm wb-1-returns-x86p
      (implies (x86p x86)
               (x86p (mv-nth 1 (wb-1 addr-lst x86)))))

    (defthm wb-1-returns-no-error-programmer-level-mode
      (implies (and (addr-byte-alistp addr-lst)
                    (programmer-level-mode x86))
               (equal (mv-nth 0 (wb-1 addr-lst x86))
                      nil))
      :hints (("Goal" :in-theory (e/d (wvm08) ())))))

  (define write-to-physical-memory
    ((p-addrs physical-address-listp)
     (bytes byte-listp)
     x86)
    :parents (reasoning-about-memory-reads-and-writes x86-physical-memory)
    :enabled t
    :guard (and (equal (len p-addrs) (len bytes))
                (not (programmer-level-mode x86)))
    :returns (x86 x86p :hyp :guard)
    (if (endp p-addrs)
        x86
      (b* ((addr (car p-addrs))
           (byte (car bytes))
           (x86 (!memi addr byte x86)))
        (write-to-physical-memory (cdr p-addrs) (cdr bytes) x86)))

    ///

    (defthm xr-not-mem-write-to-physical-memory
      (implies (not (equal fld :mem))
               (equal (xr fld index (write-to-physical-memory p-addrs bytes x86))
                      (xr fld index x86)))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthm write-to-physical-memory-xw-in-system-level-mode
      ;; Keep the state updated by write-to-physical-memory inside all other nests of writes.
      (implies (not (equal fld :mem))
               (equal (write-to-physical-memory p-addrs bytes (xw fld index value x86))
                      (xw fld index value (write-to-physical-memory p-addrs bytes x86))))
      :hints (("Goal" :in-theory (e/d* (write-to-physical-memory) ())))))

  (define wb (addr-lst x86)

    :guard (addr-byte-alistp addr-lst)
    :enabled t

    (if (programmer-level-mode x86)
        (wb-1 addr-lst x86)
      (b* (((mv flgs p-addrs x86)
            (las-to-pas (strip-cars addr-lst) :w (cpl x86) x86))
           ((when flgs) (mv flgs x86))
           (x86 (write-to-physical-memory p-addrs (strip-cdrs addr-lst) x86)))
        (mv nil x86)))

    ///

    (defthm wb-not-consp-addr-lst
      (implies (not (consp addr-lst))
               (equal (mv-nth 1 (wb addr-lst x86)) x86))
      :hints (("Goal" :in-theory (e/d* () (force (force))))))

    (defthmd wb-is-wb-1-for-programmer-level-mode
      (implies (programmer-level-mode x86)
               (equal (wb addr-lst x86)
                      (wb-1 addr-lst x86))))

    (defthm wb-returns-x86p
      (implies (and (addr-byte-alistp addr-lst)
                    (x86p x86))
               (x86p (mv-nth 1 (wb addr-lst x86)))))

    (defthm wb-returns-no-error-programmer-level-mode
      (implies (and (addr-byte-alistp addr-lst)
                    (programmer-level-mode x86))
               (equal (mv-nth 0 (wb addr-lst x86)) nil))))

  (defthm wb-by-wb-1-for-programmer-level-mode-induction-rule
    t
    :rule-classes ((:induction :pattern (wb addr-lst x86)
                               :condition (programmer-level-mode x86)
                               :scheme (wb-1 addr-lst x86))))

  (local (in-theory (e/d () (force (force)))))

  ;; Relating rb and xr/xw in the programmer-level mode:

  (defthm xr-rb-state-in-programmer-level-mode
    (implies (programmer-level-mode x86)
             (equal (xr fld index (mv-nth 2 (rb addr r-w-x x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ()))))

  (defthm rb-xw-values-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (and (equal (mv-nth 0 (rb addr r-w-x (xw fld index value x86)))
                         (mv-nth 0 (rb addr r-w-x x86)))
                  (equal (mv-nth 1 (rb addr r-w-x (xw fld index value x86)))
                         (mv-nth 1 (rb addr r-w-x x86)))))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ())
             :induct (rb-1 addr r-w-x x86 nil))))

  (defthm rb-xw-state-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :programmer-level-mode)))
             (equal (mv-nth 2 (rb addr r-w-x (xw fld index value x86)))
                    (xw fld index value (mv-nth 2 (rb addr r-w-x x86)))))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ()))))

  ;; Relating rb and xr/xw in the system-level mode:

  (defthm xr-rb-1-state-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :mem))
                  (not (equal fld :fault)))
             (equal (xr fld index (mv-nth 2 (rb-1 addr r-w-x x86 acc)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ())
             :induct (rb-1 addr r-w-x x86 acc))))

  ;; (defthm xr-rb-state-in-system-level-mode
  ;;   (implies (and (not (programmer-level-mode x86))
  ;;                 (not (equal fld :mem))
  ;;                 (not (equal fld :fault)))
  ;;            (equal (xr fld index (mv-nth 2 (rb addr r-w-x x86)))
  ;;                   (xr fld index x86)))
  ;;   :hints (("Goal" :in-theory (e/d* (rb) (force (force))))))

  ;; The following make-event generates a bunch of rules that together
  ;; say the same thing as xr-rb-state-in-system-level-mode, but these
  ;; rules are more efficient than xr-rb-state-in-system-level-mode as
  ;; they match less frequently.
  (make-event
   (generate-xr-over-write-thms
    (remove-elements-from-list
     '(:mem :fault)
     *x86-field-names-as-keywords*)
    'rb
    (acl2::formals 'rb (w state))
    :output-index 2))

  (defthm rb-1-xw-values-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :mem))
                  (not (equal fld :rflags))
                  (not (equal fld :ctr))
                  (not (equal fld :seg-visible))
                  (not (equal fld :msr))
                  (not (equal fld :fault))
                  (not (equal fld :programmer-level-mode))
                  (not (equal fld :page-structure-marking-mode)))
             (and (equal (mv-nth 0 (rb-1 addr r-w-x (xw fld index value x86) acc))
                         (mv-nth 0 (rb-1 addr r-w-x x86 acc)))
                  (equal (mv-nth 1 (rb-1 addr r-w-x (xw fld index value x86) acc))
                         (mv-nth 1 (rb-1 addr r-w-x x86 acc)))))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ())
             :induct (rb-1 addr r-w-x x86 acc))))

  ;; (defthm rb-xw-values-in-system-level-mode
  ;;   (implies (and (not (programmer-level-mode x86))
  ;;                 (not (equal fld :mem))
  ;;                 (not (equal fld :rflags))
  ;;                 (not (equal fld :ctr))
  ;;                 (not (equal fld :seg-visible))
  ;;                 (not (equal fld :msr))
  ;;                 (not (equal fld :fault))
  ;;                 (not (equal fld :programmer-level-mode))
  ;;                 (not (equal fld :page-structure-marking-mode)))
  ;;            (and (equal (mv-nth 0 (rb addr r-w-x (xw fld index value x86)))
  ;;                        (mv-nth 0 (rb addr r-w-x x86)))
  ;;                 (equal (mv-nth 1 (rb addr r-w-x (xw fld index value x86)))
  ;;                        (mv-nth 1 (rb addr r-w-x x86)))))
  ;;   :hints (("Goal" :in-theory (e/d* (rb) ()))))


  ;; The following make-events generate a bunch of rules that together
  ;; say the same thing as rb-xw-values-in-system-level-mode, but
  ;; these rules are more efficient than
  ;; rb-xw-values-in-system-level-mode as they match less frequently.
  (make-event
   (generate-read-fn-over-xw-thms
    (remove-elements-from-list
     '(:mem :rflags :ctr :seg-visible :msr :fault :programmer-level-mode :page-structure-marking-mode)
     *x86-field-names-as-keywords*)
    'rb
    (acl2::formals 'rb (w state))
    :output-index 0))

  (make-event
   (generate-read-fn-over-xw-thms
    (remove-elements-from-list
     '(:mem :rflags :ctr :seg-visible :msr :fault :programmer-level-mode :page-structure-marking-mode)
     *x86-field-names-as-keywords*)
    'rb
    (acl2::formals 'rb (w state))
    :output-index 1))

  (defthm rb-1-xw-rflags-not-ac-values-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (and (equal (mv-nth 0 (rb-1 addr r-w-x (xw :rflags 0 value x86) acc))
                         (mv-nth 0 (rb-1 addr r-w-x x86 acc)))
                  (equal (mv-nth 1 (rb-1 addr r-w-x (xw :rflags 0 value x86) acc))
                         (mv-nth 1 (rb-1 addr r-w-x x86 acc)))))
    :hints (("Goal" :induct (rb-1 addr r-w-x x86 acc)
             :in-theory (e/d* (rb rb-1) ()))))

  (defthm rb-xw-rflags-not-ac-values-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (and (equal (mv-nth 0 (rb addr r-w-x (xw :rflags 0 value x86)))
                         (mv-nth 0 (rb addr r-w-x x86)))
                  (equal (mv-nth 1 (rb addr r-w-x (xw :rflags 0 value x86)))
                         (mv-nth 1 (rb addr r-w-x x86)))))
    :hints (("Goal" :in-theory (e/d* (rb) ()))))

  (defthm rb-1-xw-state-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :mem))
                  (not (equal fld :rflags))
                  (not (equal fld :ctr))
                  (not (equal fld :seg-visible))
                  (not (equal fld :msr))
                  (not (equal fld :fault))
                  (not (equal fld :programmer-level-mode))
                  (not (equal fld :page-structure-marking-mode)))
             (equal (mv-nth 2 (rb-1 addr r-w-x (xw fld index value x86) acc))
                    (xw fld index value (mv-nth 2 (rb-1 addr r-w-x x86 acc)))))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ())
             :induct (rb-1 addr r-w-x x86 acc))))

  ;; (defthm rb-xw-state-in-system-level-mode
  ;;   (implies (and (not (programmer-level-mode x86))
  ;;                 (not (equal fld :mem))
  ;;                 (not (equal fld :rflags))
  ;;                 (not (equal fld :ctr))
  ;;                 (not (equal fld :seg-visible))
  ;;                 (not (equal fld :msr))
  ;;                 (not (equal fld :fault))
  ;;                 (not (equal fld :programmer-level-mode))
  ;;                 (not (equal fld :page-structure-marking-mode)))
  ;;            (equal (mv-nth 2 (rb addr r-w-x (xw fld index value x86)))
  ;;                   (xw fld index value (mv-nth 2 (rb addr r-w-x x86)))))
  ;;   :hints (("Goal" :in-theory (e/d* (rb) (force (force))))))

  ;; The following make-events generate a bunch of rules that together
  ;; say the same thing as rb-xw-state-in-system-level-mode but
  ;; these rules are more efficient than
  ;; rb-xw-state-in-system-level-mode as they match less frequently.
  (make-event
   (generate-write-fn-over-xw-thms
    (remove-elements-from-list
     '(:mem :rflags :ctr :seg-visible :msr :fault :programmer-level-mode :page-structure-marking-mode)
     *x86-field-names-as-keywords*)
    'rb
    (acl2::formals 'rb (w state))
    :output-index 2))

  (defthm rb-1-xw-rflags-not-ac-state-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (equal (mv-nth 2 (rb-1 addr r-w-x (xw :rflags 0 value x86) acc))
                    (xw :rflags 0 value (mv-nth 2 (rb-1 addr r-w-x x86 acc)))))
    :hints (("Goal" :in-theory (e/d* (rb rb-1) ())
             :induct (rb-1 addr r-w-x x86 acc))))

  (defthm rb-xw-rflags-not-ac-state-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (equal (mv-nth 2 (rb addr r-w-x (xw :rflags 0 value x86)))
                    (xw :rflags 0 value (mv-nth 2 (rb addr r-w-x x86)))))
    :hints (("Goal" :in-theory (e/d* (rb) (force (force))))))

  ;; Relating wb and xr/xw in the programmer-level mode:

  (defthm xr-wb-1-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem)))
             (equal (xr fld index (mv-nth 1 (wb-1 addr-lst x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* (wb-1) ()))))

  (defthm xr-wb-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem)))
             (equal (xr fld index (mv-nth 1 (wb addr-lst x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* (wb) ()))))

  (defthm wb-1-xw-in-programmer-level-mode
    ;; Keep the state updated by wb-1 inside all other nests of writes.
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (and (equal (mv-nth 0 (wb-1 addr-lst (xw fld index value x86)))
                         (mv-nth 0 (wb-1 addr-lst x86)))
                  (equal (mv-nth 1 (wb-1 addr-lst (xw fld index value x86)))
                         (xw fld index value (mv-nth 1 (wb-1 addr-lst x86))))))
    :hints (("Goal" :in-theory (e/d* (wb-1) ()))))

  (defthm wb-xw-in-programmer-level-mode
    ;; Keep the state updated by wb inside all other nests of writes.
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (and (equal (mv-nth 0 (wb addr-lst (xw fld index value x86)))
                         (mv-nth 0 (wb addr-lst x86)))
                  (equal (mv-nth 1 (wb addr-lst (xw fld index value x86)))
                         (xw fld index value (mv-nth 1 (wb addr-lst x86))))))
    :hints (("Goal" :in-theory (e/d* (wb) ()))))

  ;; Relating wb and xr/xw in the system-level mode:

  ;; The following make-events generate a bunch of rules that together
  ;; say the same thing as xr-wb-in-system-level-mode but
  ;; these rules are more efficient than
  ;; xr-wb-in-system-level-mode as they match less frequently.
  (make-event
   (generate-xr-over-write-thms
    (remove-elements-from-list
     '(:mem :fault)
     *x86-field-names-as-keywords*)
    'wb
    (acl2::formals 'wb (w state))
    :output-index 1))

  (defthm xr-fault-wb-in-system-level-marking-mode
    (implies
     (not (mv-nth 0 (las-to-pas (strip-cars addr-lst)
                                :w (cpl x86) (double-rewrite x86))))
     (equal (xr :fault 0 (mv-nth 1 (wb addr-lst x86)))
            (xr :fault 0 x86)))
    :hints
    (("Goal" :do-not-induct t
      :in-theory (e/d* (wb)
                       ((:meta acl2::mv-nth-cons-meta)
                        force (force))))))

  ;; The following make-events generate a bunch of rules that together
  ;; say the same thing as wb-xw-in-system-level-mode, but these rules
  ;; are more efficient than wb-xw-in-system-level-mode as they match
  ;; less frequently.  Note that wb is kept inside all other nests of
  ;; writes.
  (make-event
   (generate-read-fn-over-xw-thms
    (remove-elements-from-list
     '(:mem :rflags :ctr :seg-visible :msr :fault :programmer-level-mode :page-structure-marking-mode)
     *x86-field-names-as-keywords*)
    'wb
    (acl2::formals 'wb (w state))
    :output-index 0))

  (make-event
   (generate-write-fn-over-xw-thms
    (remove-elements-from-list
     '(:mem :rflags :ctr :seg-visible :msr :fault :programmer-level-mode :page-structure-marking-mode)
     *x86-field-names-as-keywords*)
    'wb
    (acl2::formals 'wb (w state))
    :output-index 1))

  (defthm wb-xw-rflags-not-ac-in-system-level-mode
    ;; Keep the state updated by wb inside all other nests of writes.
    (implies (equal (rflags-slice :ac value)
                    (rflags-slice :ac (rflags x86)))
             (and (equal (mv-nth 0 (wb addr-lst (xw :rflags 0 value x86)))
                         (mv-nth 0 (wb addr-lst x86)))
                  (equal (mv-nth 1 (wb addr-lst (xw :rflags 0 value x86)))
                         (xw :rflags 0 value (mv-nth 1 (wb addr-lst x86))))))
    :hints (("Goal" :in-theory (e/d* (wb) (write-to-physical-memory)))))

  ;; (defthm mv-nth-1-wb-and-!flgi-commute
  ;;   (implies (and (not (equal index *ac*))
  ;;                 (not (programmer-level-mode x86))
  ;;                 (not (page-structure-marking-mode x86)))
  ;;            (equal (mv-nth 1 (wb addr-lst (!flgi index val x86)))
  ;;                   (!flgi index val (mv-nth 1 (wb addr-lst x86)))))
  ;;   :hints (("Goal" :in-theory (e/d* (!flgi
  ;;                                     rflags-slice-ac-simplify
  ;;                                     !flgi-open-to-xw-rflags)
  ;;                                    (force (force))))))

  (defthm mv-nth-1-wb-and-!flgi-commute
    (implies (not (equal index *ac*))
             (equal (mv-nth 1 (wb addr-lst (!flgi index val x86)))
                    (!flgi index val (mv-nth 1 (wb addr-lst x86)))))
    :hints (("Goal" :in-theory (e/d* (!flgi rflags-slice-ac-simplify
                                            !flgi-open-to-xw-rflags)
                                     (force (force))))))

  (defthm mv-nth-1-wb-and-!flgi-undefined-commute
    (implies (and (not (equal index *ac*))
                  (not (programmer-level-mode x86))
                  (not (page-structure-marking-mode x86)))
             (equal (mv-nth 1 (wb addr-lst (!flgi-undefined index x86)))
                    (!flgi-undefined index (mv-nth 1 (wb addr-lst x86)))))
    :hints (("Goal" :in-theory (e/d* (!flgi-undefined) (wb !flgi)))))

  (defthm xr-fault-wb-in-system-level-mode
    (implies (and (not (mv-nth 0 (las-to-pas (strip-cars addr-lst) :w (cpl x86) x86)))
                  (not (page-structure-marking-mode x86)))
             (equal (xr :fault 0 (mv-nth 1 (wb addr-lst x86)))
                    (xr :fault 0 x86)))
    :hints
    (("Goal" :in-theory (e/d* (wb)
                              (write-to-physical-memory force (force))))))

  (define create-phy-addr-bytes-alist
    ((addr-list (physical-address-listp addr-list))
     (byte-list (byte-listp byte-list)))
    :guard (equal (len addr-list) (len byte-list))

    :long "<p>Given a true list of physical addresses @('addr-list') and
  a true list of bytes @('byte-list'),
  @('create-phy-addr-bytes-alist') creates an alist binding the
  @('n')-th address in @('addr-list') to the @('n')-th byte in
  @('byte-list').</p>"

    :enabled t

    :prepwork
    ((local (include-book "std/lists/nthcdr" :dir :system))
     (local (include-book "std/lists/nth" :dir :system)))

    (if (mbt (equal (len addr-list) (len byte-list)))
        (if (endp addr-list)
            nil
          (acons (car addr-list) (car byte-list)
                 (create-phy-addr-bytes-alist (cdr addr-list)
                                              (cdr byte-list))))
      nil)

    ///

    (defthm true-listp-create-phy-addr-bytes-alist
      (true-listp (create-phy-addr-bytes-alist l-addrs bytes))
      :rule-classes :type-prescription)

    (defthm consp-create-phy-addr-bytes-alist-in-terms-of-len
      (implies (and (not (zp (len byte-list)))
                    (equal (len addr-list) (len byte-list)))
               (consp (create-phy-addr-bytes-alist addr-list byte-list)))
      :rule-classes (:rewrite :type-prescription))

    (defthm consp-create-phy-addr-bytes-alist
      (implies (and (or (consp addr-list) (consp byte-list))
                    (equal (len addr-list) (len byte-list)))
               (consp (create-phy-addr-bytes-alist addr-list byte-list)))
      :rule-classes (:rewrite :type-prescription))

    (defthm create-phy-addr-bytes-alist-bytes=nil
      (equal (create-phy-addr-bytes-alist l-addrs nil) nil))

    (defthm create-phy-addr-bytes-alist-l-addrs=nil
      (equal (create-phy-addr-bytes-alist nil bytes) nil))

    (defthmd cdr-of-create-phy-addr-bytes-alist
      (equal (cdr (create-phy-addr-bytes-alist l-addrs bytes))
             (create-phy-addr-bytes-alist (cdr l-addrs) (cdr bytes))))

    (defthmd caar-of-create-phy-addr-bytes-alist
      (implies (equal (len l-addrs) (len bytes))
               (equal (car (car (create-phy-addr-bytes-alist l-addrs bytes)))
                      (car l-addrs))))

    (defthmd cdar-of-create-phy-addr-bytes-alist
      (implies (equal (len l-addrs) (len bytes))
               (equal (cdr (car (create-phy-addr-bytes-alist l-addrs bytes)))
                      (car bytes))))

    (defthm addr-byte-alistp-create-phy-addr-bytes-alist
      (implies (and (canonical-address-listp addrs)
                    (byte-listp bytes))
               (addr-byte-alistp (create-phy-addr-bytes-alist addrs bytes)))
      :rule-classes (:type-prescription :rewrite))

    (defthm strip-cars-of-create-phy-addr-bytes-alist
      (implies (and (true-listp addrs)
                    (equal (len addrs) (len bytes)))
               (equal (strip-cars (create-phy-addr-bytes-alist addrs bytes))
                      addrs)))

    (defthm strip-cdrs-of-create-phy-addr-bytes-alist
      (implies (and (byte-listp bytes)
                    (equal (len addrs) (len bytes)))
               (equal (strip-cdrs (create-phy-addr-bytes-alist addrs bytes))
                      bytes)))

    (defthm strip-cars-of-append-of-create-phy-addr-bytes-alist
      (implies (and (equal (len addrs1) (len bytes1))
                    (canonical-address-listp addrs2)
                    (equal (len addrs2) (len bytes2)))
               (equal (strip-cars
                       (append (create-phy-addr-bytes-alist addrs1 bytes1)
                               (create-phy-addr-bytes-alist addrs2 bytes2)))
                      (append addrs1 addrs2))))

    (defthm strip-cdrs-of-append-of-create-phy-addr-bytes-alist
      (implies (and (equal (len addrs1) (len bytes1))
                    (byte-listp bytes2)
                    (equal (len addrs2) (len bytes2)))
               (equal (strip-cdrs
                       (append (create-phy-addr-bytes-alist addrs1 bytes1)
                               (create-phy-addr-bytes-alist addrs2 bytes2)))
                      (append bytes1 bytes2))))

    (defthm len-of-create-phy-addr-bytes-alist
      (implies (and (not (zp (len byte-list)))
                    (equal (len addr-list) (len byte-list)))
               (equal (len (create-phy-addr-bytes-alist addr-list byte-list))
                      (len addr-list)))))

  (define create-addr-bytes-alist
    ((addr-list (canonical-address-listp addr-list))
     (byte-list (byte-listp byte-list)))
    :guard (equal (len addr-list) (len byte-list))

    :long "<p>Given a true list of canonical addresses @('addr-list')
  and a true list of bytes @('byte-list'),
  @('create-addr-bytes-alist') creates an alist binding the @('n')-th
  address in @('addr-list') to the @('n')-th byte in
  @('byte-list').</p>"

    :enabled t

    :prepwork
    ((local (include-book "std/lists/nthcdr" :dir :system))
     (local (include-book "std/lists/nth" :dir :system)))

    (if (mbt (equal (len addr-list) (len byte-list)))
        (if (endp addr-list)
            nil
          (acons (car addr-list) (car byte-list)
                 (create-addr-bytes-alist (cdr addr-list)
                                          (cdr byte-list))))
      nil)

    ///

    (defthm true-listp-create-addr-bytes-alist
      (true-listp (create-addr-bytes-alist l-addrs bytes))
      :rule-classes :type-prescription)

    (defthm alistp-create-addr-bytes-alist
      (implies (and (canonical-address-listp addrs)
                    (byte-listp bytes))
               (alistp (create-addr-bytes-alist addrs bytes)))
      :rule-classes (:type-prescription :rewrite))

    (defthm consp-create-addr-bytes-alist-in-terms-of-len
      (implies (and (not (zp (len byte-list)))
                    (equal (len addr-list) (len byte-list)))
               (consp (create-addr-bytes-alist addr-list byte-list)))
      :rule-classes (:rewrite :type-prescription))

    (defthm consp-create-addr-bytes-alist
      (implies (and (or (consp addr-list) (consp byte-list))
                    (equal (len addr-list) (len byte-list)))
               (consp (create-addr-bytes-alist addr-list byte-list)))
      :rule-classes (:rewrite :type-prescription))

    (defthm create-addr-bytes-alist-bytes=nil
      (equal (create-addr-bytes-alist l-addrs nil) nil))

    (defthm create-addr-bytes-alist-l-addrs=nil
      (equal (create-addr-bytes-alist nil bytes) nil))

    (defthmd cdr-of-create-addr-bytes-alist
      (equal (cdr (create-addr-bytes-alist l-addrs bytes))
             (create-addr-bytes-alist (cdr l-addrs) (cdr bytes))))

    (defthmd caar-of-create-addr-bytes-alist
      (implies (equal (len l-addrs) (len bytes))
               (equal (car (car (create-addr-bytes-alist l-addrs bytes)))
                      (car l-addrs))))

    (defthmd cdar-of-create-addr-bytes-alist
      (implies (equal (len l-addrs) (len bytes))
               (equal (cdr (car (create-addr-bytes-alist l-addrs bytes)))
                      (car bytes))))

    (defthm addr-byte-alistp-create-addr-bytes-alist
      (implies (and (canonical-address-listp addrs)
                    (byte-listp bytes))
               (addr-byte-alistp (create-addr-bytes-alist addrs bytes)))
      :rule-classes (:type-prescription :rewrite))

    (defthm strip-cars-of-create-addr-bytes-alist
      (implies (and (true-listp addrs)
                    (equal (len addrs) (len bytes)))
               (equal (strip-cars (create-addr-bytes-alist addrs bytes))
                      addrs)))

    (defthm strip-cdrs-of-create-addr-bytes-alist
      (implies (and (byte-listp bytes)
                    (equal (len addrs) (len bytes)))
               (equal (strip-cdrs (create-addr-bytes-alist addrs bytes))
                      bytes)))

    (defthm strip-cars-of-append-of-create-addr-bytes-alist
      (implies (and (equal (len addrs1) (len bytes1))
                    (canonical-address-listp addrs2)
                    (equal (len addrs2) (len bytes2)))
               (equal (strip-cars
                       (append (create-addr-bytes-alist addrs1 bytes1)
                               (create-addr-bytes-alist addrs2 bytes2)))
                      (append addrs1 addrs2))))

    (defthm strip-cdrs-of-append-of-create-addr-bytes-alist
      (implies (and (equal (len addrs1) (len bytes1))
                    (byte-listp bytes2)
                    (equal (len addrs2) (len bytes2)))
               (equal (strip-cdrs
                       (append (create-addr-bytes-alist addrs1 bytes1)
                               (create-addr-bytes-alist addrs2 bytes2)))
                      (append bytes1 bytes2))))

    (defthm len-of-create-addr-bytes-alist
      (implies (and (not (zp (len byte-list)))
                    (equal (len addr-list) (len byte-list)))
               (equal (len (create-addr-bytes-alist addr-list byte-list))
                      (len addr-list))))

    (defthm cons-and-create-addr-bytes-alist
      (implies (equal (len x) (len a))
               (equal (cons (cons xe ae)
                            (create-addr-bytes-alist x a))
                      (create-addr-bytes-alist (cons xe x) (cons ae a)))))

    (local (include-book "std/lists/len" :dir :system))
    (local (include-book "std/lists/append" :dir :system))

    (defthm append-and-create-addr-bytes-alist
      (implies (and (equal (len x) (len a))
                    (equal (len y) (len b)))
               (equal (append (create-addr-bytes-alist x a)
                              (create-addr-bytes-alist y b))
                      (create-addr-bytes-alist (append x y)
                                               (append a b))))))

  (define create-canonical-address-list (count addr)
    :guard (natp count)

    :long "<p>Given a canonical address @('addr'),
  @('create-canonical-address-list') creates a list of canonical
  addresses where the first address is @('addr') and the last address
  is the last canonical address in the range @('addr') to @('addr +
  count').</p>"
    :enabled t

    (if (or (zp count)
            (not (canonical-address-p addr)))
        nil
      (cons addr (create-canonical-address-list (1- count)
                                                (1+ addr))))
    ///

    (defthm true-listp-create-canonical-address-list
      (true-listp (create-canonical-address-list cnt lin-addr))
      :rule-classes (:rewrite :type-prescription))

    (defthm canonical-address-listp-create-canonical-address-list
      (canonical-address-listp
       (create-canonical-address-list count addr))
      :rule-classes (:rewrite :type-prescription))

    (defthm create-canonical-address-list-1
      (implies (canonical-address-p x)
               (equal (create-canonical-address-list 1 x)
                      (list x)))
      :hints (("Goal" :expand (create-canonical-address-list 1 x))))

    (defthm len-of-create-canonical-address-list
      (implies (and (canonical-address-p (+ -1 addr count))
                    (canonical-address-p addr)
                    (natp count))
               (equal (len (create-canonical-address-list count addr))
                      count)))

    (defthm car-create-canonical-address-list
      (implies (and (canonical-address-p addr)
                    (posp count))
               (equal (car (create-canonical-address-list count addr))
                      addr)))

    (defthm cdr-create-canonical-address-list
      (implies (and (canonical-address-p addr)
                    (posp count))
               (equal (cdr (create-canonical-address-list count addr))
                      (create-canonical-address-list (1- count) (1+ addr)))))

    (defthm consp-of-create-canonical-address-list
      (implies (and (canonical-address-p addr)
                    (natp count)
                    (< 0 count))
               (consp (create-canonical-address-list count addr)))
      :hints (("Goal" :in-theory (e/d (canonical-address-p
                                       signed-byte-p)
                                      ()))))

    (defthmd create-canonical-address-list-split
      (implies (and (canonical-address-p addr)
                    (canonical-address-p (+ k addr))
                    (natp j)
                    (natp k))
               (equal (create-canonical-address-list (+ k j) addr)
                      (append (create-canonical-address-list k addr)
                              (create-canonical-address-list j (+ k addr)))))
      :hints (("Goal" :in-theory (e/d* (canonical-address-p signed-byte-p)
                                       ())))))

  (define addr-range (count addr)
    :guard (natp count)

    :enabled t

    (if (zp count)
        nil
      (cons (ifix addr)
            (addr-range (1- count) (1+ (ifix addr)))))

    ///

    (defthm neg-addr-range=nil
      (implies (negp i) (equal (addr-range i n) nil)))

    (defthm true-listp-addr-range
      (true-listp (addr-range count addr))
      :rule-classes :type-prescription)

    (defthm addr-range-1
      (equal (addr-range 1 x)
             (list (ifix x)))
      :hints (("Goal" :expand (addr-range 1 x))))

    (defthm len-of-addr-range
      (implies (natp n)
               (equal (len (addr-range n val)) n))
      :hints (("Goal" :in-theory (e/d (addr-range) ()))))

    (defthm canonical-address-listp-addr-range
      (implies (and (canonical-address-p lin-addr)
                    (canonical-address-p (+ -1 n lin-addr)))
               (canonical-address-listp (addr-range n lin-addr)))
      :hints (("Goal" :in-theory (e/d (addr-range) ())))))

  ;; Some misc. lemmas:

  (defthmd split-rb-and-create-canonical-address-list-in-programmer-level-mode
    (implies (and (natp m)
                  (< m n)
                  (canonical-address-p lin-addr)
                  (canonical-address-p (+ -1 n lin-addr))
                  (programmer-level-mode x86))
             (equal (mv-nth 1 (rb (create-canonical-address-list n lin-addr) r-x x86))
                    (b* ((low  (mv-nth 1 (rb (create-canonical-address-list       m       lin-addr) r-x x86)))
                         (high (mv-nth 1 (rb (create-canonical-address-list (- n m) (+ m lin-addr)) r-x x86))))
                      (append low high)))))

  (defthmd push-ash-inside-logior
    (equal (ash (logior x y) n)
           (logior (ash x n) (ash y n)))
    :hints (("Goal" :in-theory (e/d* (ihsext-recursive-redefs
                                      ihsext-inductions)
                                     ()))))

  (defthmd combine-bytes-of-append-of-byte-lists
    (implies (byte-listp ys)
             (equal (combine-bytes (append xs ys))
                    (logior (combine-bytes xs)
                            (ash (combine-bytes ys)
                                 (* 8 (len xs))))))
    :hints (("Goal" :in-theory (e/d* (push-ash-inside-logior) ())))))

;; ======================================================================

;; Defining the 8, 16, 32, 48, and 64, 80, and 128 bit memory
;; read/write functions:

;; I haven't used physical memory functions like rm-low-* and wm-low-*
;; in the system-level mode below because the *-low-* functions take
;; one physical address as input and assume that the values to be read
;; or written are from contiguous physical memory locations. In the
;; functions below, there's no guarantee that the translation of
;; contiguous linear addresses will produce contiguous physical
;; addresses (though, IRL, that's likely the case). That's why there
;; are long and ugly sequences of memi and !memi below instead of nice
;; and pretty wrappers.

(local
 (defthm signed-byte-p-48-to-<-rule
   (implies (and (signed-byte-p 48 lin-addr)
                 (syntaxp (quotep n))
                 (natp n))
            (equal (signed-byte-p 48 (+ n lin-addr))
                   (< (+ n lin-addr) #.*2^47*)))))

(local (in-theory (e/d () (signed-byte-p))))

(define rm08
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal" :in-theory (e/d* (rvm08) ())))

  (if (mbt (canonical-address-p lin-addr))

      (mbe

       :logic
       (b* (((mv flg bytes x86)
             (rb (create-canonical-address-list 1 lin-addr) r-x x86))
            (result (combine-bytes bytes)))
         (mv flg result x86))

       :exec
       (if (programmer-level-mode x86)

           (rvm08 lin-addr x86)

         (b* ((cpl (cpl x86))
              ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr) x86)
               (la-to-pa lin-addr r-x cpl x86))
              ((when flag)
               (mv flag 0 x86))
              (byte (the (unsigned-byte 8) (memi p-addr x86))))
           (mv nil byte x86))))

    (mv 'rm08 0 x86))

  ///

  (defthm-usb n08p-mv-nth-1-rm08
    :hyp (force (x86p x86))
    :bound 8
    :concl (mv-nth 1 (rm08 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (unsigned-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (unsigned-byte-p) ())))
    :gen-type t)

  (defthm x86p-rm08
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm08 lin-addr r-x x86))))
    :rule-classes (:rewrite :type-prescription))

  (defthm rm08-value-when-error
    (implies (mv-nth 0 (rm08 addr :x x86))
             (equal (mv-nth 1 (rm08 addr :x x86)) 0))
    :hints (("Goal" :in-theory (e/d (rvm08) (force (force))))))

  (defthm rm08-does-not-affect-state-in-programmer-level-mode
    (implies (programmer-level-mode x86)
             (equal (mv-nth 2 (rm08 start-rip :x x86))
                    x86))
    :hints (("Goal" :in-theory (e/d (rvm08) (force (force))))))

  (defthm programmer-level-mode-rm08-no-error
    (implies (and (programmer-level-mode x86)
                  (canonical-address-p addr)
                  (x86p x86))
             (and (equal (mv-nth 0 (rm08 addr r-x x86))
                         nil)
                  (equal (mv-nth 1 (rm08 addr :x x86))
                         (memi (loghead 48 addr) x86))
                  (equal (mv-nth 2 (rm08 addr r-x x86))
                         x86)))
    :hints (("Goal" :in-theory (e/d (rvm08) (force (force))))))

  (defthm xr-rm08-state-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem)))
             (equal (xr fld index (mv-nth 2 (rm08 addr r-x x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* () (force (force))))))

  (defthm xr-rm08-state-in-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :mem))
                  (not (equal fld :fault)))
             (equal (xr fld index (mv-nth 2 (rm08 addr r-x x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* () (force (force))))))

  (defthm rm08-xw-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (and (equal (mv-nth 0 (rm08 addr r-x (xw fld index value x86)))
                         (mv-nth 0 (rm08 addr r-x x86)))
                  (equal (mv-nth 1 (rm08 addr r-x (xw fld index value x86)))
                         (mv-nth 1 (rm08 addr r-x x86)))
                  ;; No need for the conclusion about the state because
                  ;; "rm08-does-not-affect-state-in-programmer-level-mode".
                  ))
    :hints (("Goal" :in-theory (e/d* (rvm08) ()))))

  (defthm rm08-xw-system-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :fault))
                  (not (equal fld :seg-visible))
                  (not (equal fld :mem))
                  (not (equal fld :ctr))
                  (not (equal fld :msr))
                  (not (equal fld :rflags))
                  (not (equal fld :programmer-level-mode))
                  (not (equal fld :page-structure-marking-mode)))
             (and (equal (mv-nth 0 (rm08 addr r-x (xw fld index value x86)))
                         (mv-nth 0 (rm08 addr r-x x86)))
                  (equal (mv-nth 1 (rm08 addr r-x (xw fld index value x86)))
                         (mv-nth 1 (rm08 addr r-x x86)))
                  (equal (mv-nth 2 (rm08 addr r-x (xw fld index value x86)))
                         (xw fld index value (mv-nth 2 (rm08 addr r-x x86)))))))

  (defthm rm08-xw-system-mode-rflags-not-ac
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (and (equal (mv-nth 0 (rm08 addr r-x (xw :rflags 0 value x86)))
                         (mv-nth 0 (rm08 addr r-x x86)))
                  (equal (mv-nth 1 (rm08 addr r-x (xw :rflags 0 value x86)))
                         (mv-nth 1 (rm08 addr r-x x86)))
                  (equal (mv-nth 2 (rm08 addr r-x (xw :rflags 0 value x86)))
                         (xw :rflags 0 value (mv-nth 2 (rm08 addr r-x x86)))))))

  (defthm mv-nth-2-rm08-in-system-level-non-marking-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (page-structure-marking-mode x86))
                  (x86p x86)
                  (not (mv-nth 0 (rm08 lin-addr r-x x86))))
             (equal (mv-nth 2 (rm08 lin-addr r-x x86))
                    x86))))

(define rim08
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (mv-let (flag val x86)
    (rm08 lin-addr r-x x86)
    (mv flag (n08-to-i08 val) x86))
  ///

  (defthm-sb i08p-mv-nth-1-rim08
    :hyp (force (x86p x86))
    :bound 8
    :concl (mv-nth 1 (rim08 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) ())))
    :gen-type t)

  (defthm x86p-rim08
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rim08 lin-addr r-x x86))))
    :rule-classes (:rewrite :type-prescription)))

(define wm08
  ((lin-addr :type (signed-byte   #.*max-linear-address-size*))
   (val      :type (unsigned-byte 8))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal" :in-theory (e/d* (wvm08 byte-ify) ())))

  (if (mbt (canonical-address-p lin-addr))

      (mbe

       :logic
       (wb (create-addr-bytes-alist
            (create-canonical-address-list 1 lin-addr)
            (byte-ify 1 val))
           x86)

       :exec
       (if (programmer-level-mode x86)

           (wvm08 lin-addr val x86)

         (b* ((cpl (cpl x86))
              ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr) x86)
               (la-to-pa lin-addr :w cpl x86))
              ((when flag)
               (mv flag x86))
              (byte (mbe :logic (n08 val)
                         :exec val))
              (x86 (!memi p-addr byte x86)))
           (mv nil x86))))

    (mv 'wm08 x86))

  ///

  (defthm x86p-wm08
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm08 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d (byte-ify) (force (force)))))
    :rule-classes (:rewrite :type-prescription))

  (defthm programmer-level-mode-wm08-no-error
    (implies (and (programmer-level-mode x86)
                  (canonical-address-p addr))
             (equal (mv-nth 0 (wm08 addr val x86))
                    nil))
    :hints (("Goal" :in-theory (e/d (wm08 wvm08 byte-ify) ()))))

  (defthm xr-wm08-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem)))
             (equal (xr fld index (mv-nth 1 (wm08 addr val x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* (wvm08) ()))))

  (defthm xr-wm08-system-level-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :mem))
                  (not (equal fld :fault)))
             (equal (xr fld index (mv-nth 1 (wm08 addr val x86)))
                    (xr fld index x86)))
    :hints (("Goal" :in-theory (e/d* () (force (force))))))

  (defthm wm08-xw-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (and (equal (mv-nth 0 (wm08 addr val (xw fld index value x86)))
                         (mv-nth 0 (wm08 addr val x86)))
                  (equal (mv-nth 1 (wm08 addr val (xw fld index value x86)))
                         (xw fld index value (mv-nth 1 (wm08 addr val x86))))))
    :hints (("Goal" :in-theory (e/d* (wm08 wvm08) ()))))

  (defthm wm08-xw-system-mode
    (implies (and (not (programmer-level-mode x86))
                  (not (equal fld :fault))
                  (not (equal fld :seg-visible))
                  (not (equal fld :mem))
                  (not (equal fld :ctr))
                  (not (equal fld :rflags))
                  (not (equal fld :msr))
                  (not (equal fld :programmer-level-mode))
                  (not (equal fld :page-structure-marking-mode)))
             (and (equal (mv-nth 0 (wm08 addr val (xw fld index value x86)))
                         (mv-nth 0 (wm08 addr val x86)))
                  (equal (mv-nth 1 (wm08 addr val (xw fld index value x86)))
                         (xw fld index value (mv-nth 1 (wm08 addr val x86))))))
    :hints (("Goal" :in-theory (e/d* () (force (force))))))

  (defthm wm08-xw-system-mode-rflags-not-ac
    (implies (and (not (programmer-level-mode x86))
                  (equal (rflags-slice :ac value)
                         (rflags-slice :ac (rflags x86))))
             (and (equal (mv-nth 0 (wm08 addr val (xw :rflags 0 value x86)))
                         (mv-nth 0 (wm08 addr val x86)))
                  (equal (mv-nth 1 (wm08 addr val (xw :rflags 0 value x86)))
                         (xw :rflags 0 value (mv-nth 1 (wm08 addr val x86))))))
    :hints (("Goal" :in-theory (e/d* () (force (force)))))))

(define wim08
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (signed-byte 8))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (wm08 lin-addr (the (unsigned-byte 8) (n08 val)) x86)
  ///
  (defthm x86p-wim08
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wim08 lin-addr val x86))))
    :rule-classes (:rewrite :type-prescription)))

(define rm16
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal" :in-theory (e/d (rb-and-rvm16 rm08)
                                        ())))

  :prepwork

  ((defthmd rb-and-rvm16
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (1+ lin-addr)))
              (equal (rvm16 lin-addr x86)
                     (b* (((mv flg bytes x86)
                           (rb (create-canonical-address-list 2 lin-addr) r-x x86))
                          (result (combine-bytes bytes)))
                       (mv flg result x86))))
     :hints (("Goal" :in-theory (e/d (rm08 rvm08 rvm16) (force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((1+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (1+ (the (signed-byte #.*max-linear-address-size*)
                                 lin-addr)))))


        (if (mbe :logic (canonical-address-p 1+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            1+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 2 lin-addr) r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))
                 :exec
                 (if (programmer-level-mode x86)

                     (rvm16 lin-addr x86)

                   (let* ((cpl (cpl x86)))
                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (1+lin-addr
                           (the (signed-byte #.*max-linear-address-size+1*)
                             (1+ (the (signed-byte #.*max-linear-address-size*)
                                   lin-addr))))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) ?p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0 (the (unsigned-byte 8) (memi p-addr0 x86)))
                          (byte1 (the (unsigned-byte 8) (memi p-addr1 x86)))

                          (word (the (unsigned-byte 16)
                                  (logior (the (unsigned-byte 16) (ash byte1 8))
                                          byte0))))

                       (mv nil word x86)))))

          (mv 'rm16 0 x86)))

    (mv 'rm16 0 x86))

  ///

  (defthm-usb n16p-mv-nth-1-rm16
    :hyp (force (x86p x86))
    :bound 16
    :concl (mv-nth 1 (rm16 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) ())))
    :gen-type t)

  (defthm x86p-rm16
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm16 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (disable unsigned-byte-p signed-byte-p (force))))
    :rule-classes (:rewrite :type-prescription)))

(define rim16
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (mv-let (flag val x86)
    (rm16 lin-addr r-x x86)
    (mv flag (n16-to-i16 val) x86))
  ///

  (defthm-sb i16p-mv-nth-1-rim16
    :hyp (force (x86p x86))
    :bound 16
    :concl (mv-nth 1 (rim16 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) ())))
    :gen-type t)

  (defthm x86p-rim16
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rim16 lin-addr r-x x86))))
    :rule-classes (:rewrite :type-prescription)))

(define wm16
  ((lin-addr :type (signed-byte   #.*max-linear-address-size*))
   (val      :type (unsigned-byte 16))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  :guard-hints (("Goal" :in-theory (e/d (wb-and-wvm16 byte-ify) ())))

  :prepwork

  ((defthmd wb-and-wvm16
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (1+ lin-addr)))
              (equal (wvm16 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 2 lin-addr)
                          (byte-ify 2 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm16 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force
                                      (force)
                                      unsigned-byte-p
                                      (nth) nth
                                      (nthcdr)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((1+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (1+ (the (signed-byte #.*max-linear-address-size*)
                                 lin-addr)))))

        (if (mbe :logic (canonical-address-p 1+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            1+lin-addr)
                          #.*2^47*))

            (mbe :logic (wb (create-addr-bytes-alist
                             (create-canonical-address-list 2 lin-addr)
                             (byte-ify 2 val))
                            x86)
                 :exec

                 (if (programmer-level-mode x86)

                     (wvm16 lin-addr val x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr :w cpl x86))
                          ((when flag) (mv flag x86))

                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr :w cpl x86))
                          ((when flag) (mv flag x86))

                          (byte0 (mbe
                                  :logic (part-select val :low 0 :width 8)
                                  :exec (the (unsigned-byte 8) (logand #xff val))))
                          (byte1 (mbe
                                  :logic (part-select val :low 8 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -8)))))

                          (x86 (!memi p-addr0 byte0 x86))
                          (x86 (!memi p-addr1 byte1 x86)))
                       (mv nil x86)))))

          (mv 'wm16 x86)))

    (mv 'wm16 x86))

  ///

  (defthm x86p-wm16
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm16 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d (byte-ify) (unsigned-byte-p signed-byte-p force (force)))))
    :rule-classes (:rewrite :type-prescription)))

(define wim16
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (signed-byte 16))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (wm16 lin-addr (the (unsigned-byte 16) (n16 val)) x86)
  ///
  (defthm x86p-wim16
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wim16 lin-addr val x86))))
    :rule-classes (:rewrite :type-prescription)))

(define rm32
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal" :in-theory (e/d (rb-and-rvm32 rm08)
                                        (rb-1-accumulator-thm
                                         rb-1
                                         (:rewrite acl2::ash-0)
                                         (:rewrite acl2::zip-open)
                                         (:linear ash-monotone-2)
                                         (:linear bitops::logior-<-0-linear-2)
                                         (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                         (:rewrite bitops::logior-equal-0)
                                         (:linear memi-is-n08p)))))

  :prepwork

  ((defthmd rb-and-rvm32
     (implies (and (programmer-level-mode x86)
                   (x86p x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 3 lin-addr)))
              (equal
               (list
                nil
                (combine-bytes
                 (mv-nth 1 (rb-1 (create-canonical-address-list 4 lin-addr)
                                 r-x x86 nil)))
                x86)
               (rvm32 lin-addr x86)))
     :hints (("Goal"
              :in-theory (e/d (rm08 rvm08 rvm32) (force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((3+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (+ 3 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))

        (if (mbe :logic (canonical-address-p 3+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            3+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 4 lin-addr)
                           r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))

                 :exec
                 (if (programmer-level-mode x86)

                     (rvm32 lin-addr x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (1+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                                        (+ 1 (the (signed-byte #.*max-linear-address-size*)
                                               lin-addr))))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (2+lin-addr (the (signed-byte #.*max-linear-address-size+2*)
                                        (+ 2 (the (signed-byte #.*max-linear-address-size*)
                                               lin-addr))))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                           (la-to-pa 2+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (3+lin-addr (the (signed-byte #.*max-linear-address-size+3*)
                                        (+ 3 (the (signed-byte #.*max-linear-address-size*)
                                               lin-addr))))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                           (la-to-pa 3+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0 (the (unsigned-byte 8) (memi p-addr0 x86)))
                          (byte1 (the (unsigned-byte 8) (memi p-addr1 x86)))
                          (byte2 (the (unsigned-byte 8) (memi p-addr2 x86)))
                          (byte3 (the (unsigned-byte 8) (memi p-addr3 x86)))

                          (word0 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte1 8))
                                           byte0)))
                          (word1 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte3 8))
                                           byte2)))

                          (dword (the (unsigned-byte 32)
                                   (logior (the (unsigned-byte 32) (ash word1 16))
                                           word0))))

                       (mv nil dword x86)))))

          (mv 'rm32 0 x86)))

    (mv 'rm32 0 x86))

  ///

  (defthm-usb n32p-mv-nth-1-rm32
    :hyp (force (x86p x86))
    :bound 32
    :concl (mv-nth 1 (rm32 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) (force (force)))))
    :gen-type t)

  (defthm x86p-rm32
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm32 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (disable unsigned-byte-p signed-byte-p (force))))
    :rule-classes (:rewrite :type-prescription)))

(define rim32
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (mv-let (flag val x86)
    (rm32 lin-addr r-x x86)
    (mv flag (n32-to-i32 val) x86))
  ///

  (defthm-sb i32p-mv-nth-1-rim32
    :hyp (force (x86p x86))
    :bound 32
    :concl (mv-nth 1 (rim32 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) ())))
    :gen-type t)

  (defthm x86p-rim32
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rim32 lin-addr r-x x86))))
    :rule-classes (:rewrite :type-prescription)))

(define wm32
  ((lin-addr :type (signed-byte   #.*max-linear-address-size*))
   (val      :type (unsigned-byte 32))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  :guard-hints (("Goal" :in-theory (e/d (wb-and-wvm32 byte-ify)
                                        ((:rewrite acl2::ash-0)
                                         (:rewrite acl2::zip-open)
                                         (:linear ash-monotone-2)
                                         (:linear bitops::logior-<-0-linear-2)
                                         (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                         (:rewrite bitops::logior-equal-0)
                                         (:linear memi-is-n08p)))))

  :prepwork

  ((defthmd wb-and-wvm32
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 3 lin-addr)))
              (equal (wvm32 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 4 lin-addr)
                          (byte-ify 4 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm32 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((3+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (+ 3 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))


        (if (mbe :logic (canonical-address-p 3+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            3+lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list 4 lin-addr)
                  (byte-ify 4 val))
                 x86)
             :exec

             (if (programmer-level-mode x86)

                 (wvm32 lin-addr val x86)

               (let* ((cpl (cpl x86)))

                 (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                       (la-to-pa lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                       (+ 1 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                       (la-to-pa 1+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (2+lin-addr (the (signed-byte #.*max-linear-address-size+2*)
                                    (+ 2 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                       (la-to-pa 2+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (3+lin-addr (the (signed-byte #.*max-linear-address-size+3*)
                                    (+ 3 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                       (la-to-pa 3+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (byte0 (mbe
                              :logic (part-select val :low 0 :width 8)
                              :exec  (the (unsigned-byte 8) (logand #xff val))))
                      (byte1 (mbe
                              :logic (part-select val :low 8 :width 8)
                              :exec  (the (unsigned-byte 8)
                                       (logand #xff (ash val -8)))))
                      (byte2 (mbe
                              :logic (part-select val :low 16 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -16)))))
                      (byte3 (mbe
                              :logic (part-select val :low 24 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -24)))))

                      (x86 (!memi p-addr0 byte0 x86))
                      (x86 (!memi p-addr1 byte1 x86))
                      (x86 (!memi p-addr2 byte2 x86))
                      (x86 (!memi p-addr3 byte3 x86)))
                   (mv nil x86)))))

          (mv 'wm32 x86)))

    (mv 'wm32 x86))

  ///

  (defthm x86p-wm32
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm32 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (force (force)))))
    :rule-classes (:rewrite :type-prescription)))

(define wim32
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (signed-byte 32))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (wm32 lin-addr (the (unsigned-byte 32) (n32 val)) x86)
  ///
  (defthm x86p-wim32
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wim32 lin-addr val x86))))
    :rule-classes (:rewrite :type-prescription)))

(define rm48
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x      :type (member :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 6 lin-addr)
                          (create-canonical-address-list 5 (+ 1 lin-addr)))
                 :in-theory (e/d (rb-and-rvm48
                                  rm08
                                  member-equal
                                  rb-and-rm48-helper-1
                                  rb-and-rm48-helper-2)
                                 (not
                                  ash-monotone-2
                                  (:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                  (:rewrite bitops::logior-equal-0)
                                  (:linear memi-is-n08p)))))

  :prepwork
  ((local
    (defthmd rb-and-rvm48-helper
      (implies (and (programmer-level-mode x86)
                    (x86p x86)
                    (canonical-address-p lin-addr)
                    (canonical-address-p (+ 5 lin-addr)))
               (equal (rvm48 lin-addr x86)
                      (list nil
                            (logior (combine-bytes
                                     (mv-nth 1 (rb-1 (create-canonical-address-list 2 lin-addr)
                                                     r-x x86 nil)))
                                    (ash (combine-bytes
                                          (mv-nth 1
                                                  (rb-1 (create-canonical-address-list 4 (+ 2 lin-addr))
                                                        r-x x86 nil)))
                                         16))
                            x86)))
      :hints (("Goal" :use ((:instance rb-and-rvm16)
                            (:instance rb-and-rvm32 (lin-addr (+ 2 lin-addr))))
               :in-theory (e/d (rvm48)
                               (force (force)))))))

   (defthmd rb-and-rvm48
     (implies (and (programmer-level-mode x86)
                   (x86p x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 5 lin-addr)))
              (equal (rvm48 lin-addr x86)
                     (b* (((mv flg bytes x86)
                           (rb-1 (create-canonical-address-list 6 lin-addr)
                                 r-x x86 nil))
                          (result (combine-bytes bytes)))
                       (mv flg result x86))))
     :hints (("Goal"
              :in-theory (e/d (rb-and-rvm48-helper
                               rm48-guard-proof-helper)
                              (rb-and-rvm32-helper
                               logior-expt-to-plus-quotep
                               signed-byte-p
                               force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((5+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                              (+ 5 (the (signed-byte #.*max-linear-address-size*)
                                        lin-addr)))))


        (if (mbe :logic (canonical-address-p 5+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                               5+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 6 lin-addr)
                           r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))

                 :exec
                 (if (programmer-level-mode x86)

                     (rvm48 lin-addr x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                           (+ 1 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                           (+ 2 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                           (la-to-pa 2+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                           (+ 3 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                           (la-to-pa 3+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                           (+ 4 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                           (la-to-pa 4+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                           (+ 5 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                           (la-to-pa 5+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0 (memi p-addr0 x86))
                          (byte1 (memi p-addr1 x86))
                          (byte2 (memi p-addr2 x86))
                          (byte3 (memi p-addr3 x86))
                          (byte4 (memi p-addr4 x86))
                          (byte5 (memi p-addr5 x86))

                          (word0 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte1 8))
                                              byte0)))
                          (word1 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte3 8))
                                              byte2)))
                          (word2 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte5 8))
                                              byte4)))
                          (dword1 (the (unsigned-byte 32)
                                       (logior (the (unsigned-byte 32) (ash word2 16))
                                               word1)))
                          (value (the (unsigned-byte 48)
                                      (logior (the (unsigned-byte 48) (ash dword1 16))
                                              word0))))

                       (mv nil value x86)))))

          (mv 'rm48 0 x86)))

    (mv 'rm48 0 x86))

  ///

  (defthm-usb n48p-mv-nth-1-rm48
    :hyp (force (x86p x86))
    :bound 48
    :concl (mv-nth 1 (rm48 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p ash-monotone-2))))
    :otf-flg t
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) (ash-monotone-2 rb))))
    :gen-type t)

  (defthm x86p-rm48
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm48 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (e/d () ((force) unsigned-byte-p signed-byte-p))))
    :rule-classes (:rewrite :type-prescription)))

(define wm48
  ((lin-addr :type (signed-byte   #.*max-linear-address-size*))
   (val      :type (unsigned-byte 48))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 6 lin-addr)
                          (create-canonical-address-list 5 (+ 1 lin-addr)))
                 :in-theory (e/d (wb-and-wvm48 byte-ify)
                                 ((:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite bitops::logior-equal-0)
                                  (:linear memi-is-n08p)))))

  :prepwork

  ((defthmd wb-and-wvm48
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 5 lin-addr)))
              (equal (wvm48 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 6 lin-addr)
                          (byte-ify 6 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm16 wvm32 wvm48 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((5+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (+ 5 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))


        (if (mbe :logic (canonical-address-p 5+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            5+lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list 6 lin-addr)
                  (byte-ify 6 val))
                 x86)
             :exec

             (if (programmer-level-mode x86)

                 (wvm48 lin-addr val x86)

               (let* ((cpl (cpl x86)))

                 (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                       (la-to-pa lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                       (+ 1 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                       (la-to-pa 1+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (2+lin-addr (the (signed-byte #.*max-linear-address-size+2*)
                                    (+ 2 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                       (la-to-pa 2+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (3+lin-addr (the (signed-byte #.*max-linear-address-size+3*)
                                    (+ 3 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                       (la-to-pa 3+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (4+lin-addr (the (signed-byte #.*max-linear-address-size+4*)
                                    (+ 4 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                       (la-to-pa 4+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (5+lin-addr (the (signed-byte #.*max-linear-address-size+5*)
                                    (+ 5 (the (signed-byte #.*max-linear-address-size*)
                                           lin-addr))))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                       (la-to-pa 5+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (byte0 (mbe
                              :logic (part-select val :low 0 :width 8)
                              :exec  (the (unsigned-byte 8) (logand #xff val))))
                      (byte1 (mbe
                              :logic (part-select val :low 8 :width 8)
                              :exec  (the (unsigned-byte 8)
                                       (logand #xff (ash val -8)))))
                      (byte2 (mbe
                              :logic (part-select val :low 16 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -16)))))
                      (byte3 (mbe
                              :logic (part-select val :low 24 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -24)))))
                      (byte4 (mbe
                              :logic (part-select val :low 32 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -32)))))
                      (byte5 (mbe
                              :logic (part-select val :low 40 :width 8)
                              :exec (the (unsigned-byte 8)
                                      (logand #xff (ash val -40)))))

                      (x86 (!memi p-addr0 byte0 x86))
                      (x86 (!memi p-addr1 byte1 x86))
                      (x86 (!memi p-addr2 byte2 x86))
                      (x86 (!memi p-addr3 byte3 x86))
                      (x86 (!memi p-addr4 byte4 x86))
                      (x86 (!memi p-addr5 byte5 x86)))
                   (mv nil x86)))))

          (mv 'wm48 x86)))

    (mv 'wm48 x86))

  ///

  (defthm x86p-wm48
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm48 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (force (force)))))
    :rule-classes (:rewrite :type-prescription)))

(define rm64
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 8 lin-addr)
                          (create-canonical-address-list 7 (+ 1 lin-addr))
                          (create-canonical-address-list 6 (+ 2 lin-addr))
                          (create-canonical-address-list 5 (+ 3 lin-addr)))
                 :in-theory (e/d (rb-and-rvm64 rm08)
                                 (not
                                  ash-monotone-2
                                  (:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                  (:rewrite bitops::logior-equal-0)
                                  (:linear memi-is-n08p)))))

  :prepwork
  ((local
    (defthmd rb-and-rvm64-helper-1
      (implies (and (programmer-level-mode x86)
                    (x86p x86)
                    (canonical-address-p lin-addr)
                    (canonical-address-p (+ 7 lin-addr)))
               (equal (rvm64 lin-addr x86)
                      (list nil
                            (logior (combine-bytes
                                     (mv-nth 1 (rb-1 (create-canonical-address-list 4 lin-addr)
                                                     r-x x86 nil)))
                                    (ash (combine-bytes
                                          (mv-nth 1
                                                  (rb-1 (create-canonical-address-list 4 (+ 4 lin-addr))
                                                        r-x x86 nil)))
                                         32))
                            x86)))
      :hints (("Goal" :use ((:instance rb-and-rvm32)
                            (:instance rb-and-rvm32 (lin-addr (+ 4 lin-addr))))
               :in-theory (e/d (rvm64)
                               (force (force)))))))


   (local
    (defthmd rb-and-rvm64-helper-2
      (implies (and (programmer-level-mode x86)
                    (x86p x86)
                    (canonical-address-p lin-addr)
                    (canonical-address-p (+ 7 lin-addr)))
               (equal
                (logior
                 (combine-bytes (mv-nth 1
                                        (rb-1 (create-canonical-address-list 4 lin-addr)
                                              r-x x86 nil)))
                 (ash (combine-bytes
                       (mv-nth 1
                               (rb-1 (create-canonical-address-list 4 (+ 4 lin-addr))
                                     r-x x86 nil)))
                      32))
                (combine-bytes (mv-nth 1
                                       (rb-1 (create-canonical-address-list 8 lin-addr)
                                             r-x x86 nil)))))
      :hints (("Goal"
               :use ((:instance split-rb-and-create-canonical-address-list-in-programmer-level-mode
                                (n 8)
                                (m 4))
                     (:instance combine-bytes-of-append-of-byte-lists
                                (xs (mv-nth 1 (rb-1 (create-canonical-address-list 4 lin-addr) r-x x86 nil)))
                                (ys (mv-nth 1 (rb-1 (create-canonical-address-list 4 (+ 4 lin-addr)) r-x x86 nil)))))
               :in-theory (e/d () (force (force)))))))

   (defthmd rb-and-rvm64
     (implies (and (programmer-level-mode x86)
                   (x86p x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 7 lin-addr)))
              (equal (rvm64 lin-addr x86)
                     (b* (((mv flg bytes x86)
                           (rb-1 (create-canonical-address-list 8 lin-addr)
                                 r-x x86 nil))
                          (result (combine-bytes bytes)))
                       (mv flg result x86))))
     :hints (("Goal"
              :in-theory (e/d (rb-and-rvm64-helper-1
                               rb-and-rvm64-helper-2)
                              (rb-and-rvm32-helper
                               rm64-guard-proof-helper
                               logior-expt-to-plus-quotep
                               signed-byte-p
                               force (force))))))

   (local (in-theory (e/d* () (rb-and-rvm64-helper)))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((7+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (+ 7 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))


        (if (mbe :logic (canonical-address-p 7+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            7+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 8 lin-addr)
                           r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))

                 :exec
                 (if (programmer-level-mode x86)

                     (rvm64 lin-addr x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                           (+ 1 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                           (+ 2 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                           (la-to-pa 2+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                           (+ 3 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                           (la-to-pa 3+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                           (+ 4 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                           (la-to-pa 4+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                           (+ 5 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                           (la-to-pa 5+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                           (+ 6 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                           (la-to-pa 6+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                           (+ 7 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                           (la-to-pa 7+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0 (memi p-addr0 x86))
                          (byte1 (memi p-addr1 x86))
                          (byte2 (memi p-addr2 x86))
                          (byte3 (memi p-addr3 x86))
                          (byte4 (memi p-addr4 x86))
                          (byte5 (memi p-addr5 x86))
                          (byte6 (memi p-addr6 x86))
                          (byte7 (memi p-addr7 x86))

                          (word0 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte1 8))
                                           byte0)))
                          (word1 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte3 8))
                                           byte2)))
                          (dword0 (the (unsigned-byte 32)
                                    (logior (the (unsigned-byte 32) (ash word1 16))
                                            word0)))
                          (word2 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte5 8))
                                           byte4)))
                          (word3 (the (unsigned-byte 16)
                                   (logior (the (unsigned-byte 16) (ash byte7 8))
                                           byte6)))
                          (dword1 (the (unsigned-byte 32)
                                    (logior (the (unsigned-byte 32) (ash word3 16))
                                            word2)))
                          (qword (the (unsigned-byte 64)
                                   (logior (the (unsigned-byte 64) (ash dword1 32))
                                           dword0))))

                       (mv nil qword x86)))))

          (mv 'rm64 0 x86)))

    (mv 'rm64 0 x86))

  ///

  (defthm-usb n64p-mv-nth-1-rm64
    :hyp (force (x86p x86))
    :bound 64
    :concl (mv-nth 1 (rm64 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p ash-monotone-2))))
    :otf-flg t
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) (ash-monotone-2 rb))))
    :gen-type t)

  (defthm x86p-rm64
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm64 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (e/d () ((force) unsigned-byte-p signed-byte-p))))
    :rule-classes (:rewrite :type-prescription)))

(define rim64
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (mv-let (flag val x86)
    (rm64 lin-addr r-x x86)
    (mv flag (n64-to-i64 val) x86))
  ///

  (defthm-sb i64p-mv-nth-1-rim64
    :hyp (force (x86p x86))
    :bound 64
    :concl (mv-nth 1 (rim64 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p))))
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) ())))
    :gen-type t)

  (defthm x86p-rim64
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rim64 lin-addr r-x x86))))
    :rule-classes (:rewrite :type-prescription)))

(define wm64
  ((lin-addr :type (signed-byte   #.*max-linear-address-size*))
   (val      :type (unsigned-byte 64))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 8 lin-addr)
                          (create-canonical-address-list 7 (+ 1 lin-addr))
                          (create-canonical-address-list 6 (+ 2 lin-addr))
                          (create-canonical-address-list 5 (+ 3 lin-addr)))
                 :in-theory (e/d (wb-and-wvm64 byte-ify)
                                 ((:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                  (:rewrite bitops::logior-equal-0)
                                  (:linear memi-is-n08p)))))

  :prepwork

  ((defthmd wb-and-wvm64
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 7 lin-addr)))
              (equal (wvm64 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 8 lin-addr)
                          (byte-ify 8 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm32 wvm64 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force (force)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((7+lin-addr (the (signed-byte #.*max-linear-address-size+2*)
                           (+ 7 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))


        (if (mbe :logic (canonical-address-p 7+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            7+lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list 8 lin-addr)
                  (byte-ify 8 val))
                 x86)

             :exec
             (if (programmer-level-mode x86)

                 (wvm64 lin-addr val x86)


               (let* ((cpl (cpl x86)))

                 (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                       (la-to-pa lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                       (+ 1 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                       (la-to-pa 1+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                       (+ 2 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                       (la-to-pa 2+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                       (+ 3 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                       (la-to-pa 3+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                       (+ 4 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                       (la-to-pa 4+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                       (+ 5 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                       (la-to-pa 5+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                       (+ 6 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                       (la-to-pa 6+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                       (+ 7 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                       (la-to-pa 7+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (byte0 (mbe :logic (part-select val :low 0 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff val))))
                      (byte1 (mbe :logic (part-select val :low 8 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -8)))))
                      (byte2 (mbe :logic (part-select val :low 16 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -16)))))
                      (byte3 (mbe :logic (part-select val :low 24 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -24)))))
                      (byte4 (mbe :logic (part-select val :low 32 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -32)))))
                      (byte5 (mbe :logic (part-select val :low 40 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -40)))))
                      (byte6 (mbe :logic (part-select val :low 48 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -48)))))
                      (byte7 (mbe :logic (part-select val :low 56 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -56)))))

                      (x86 (!memi p-addr0 byte0 x86))
                      (x86 (!memi p-addr1 byte1 x86))
                      (x86 (!memi p-addr2 byte2 x86))
                      (x86 (!memi p-addr3 byte3 x86))
                      (x86 (!memi p-addr4 byte4 x86))
                      (x86 (!memi p-addr5 byte5 x86))
                      (x86 (!memi p-addr6 byte6 x86))
                      (x86 (!memi p-addr7 byte7 x86)))

                   (mv nil x86)))))

          (mv 'wm64 x86)))

    (mv 'wm64 x86))

  ///

  (defthm x86p-wm64
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm64 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (force (force) unsigned-byte-p signed-byte-p))))
    :rule-classes (:rewrite :type-prescription)))

(define wim64
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (signed-byte 64))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  (wm64 lin-addr (the (unsigned-byte 64) (n64 val)) x86)
  ///
  (defthm x86p-wim64
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wim64 lin-addr val x86))))
    :rule-classes (:rewrite :type-prescription)))

(define rm80
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 10 lin-addr)
                          (create-canonical-address-list  9 (+ 1 lin-addr))
                          (create-canonical-address-list  8 (+ 2 lin-addr))
                          (create-canonical-address-list  7 (+ 3 lin-addr)))
                 :in-theory (e/d (rb-and-rvm80
                                  rm80-in-system-level-mode-guard-proof-helper
                                  rm08)
                                 (not
                                  ash-monotone-2
                                  (:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                  (:rewrite bitops::logior-equal-0)))))

  :prepwork
  ((defthmd rb-and-rvm80
     (implies (and (programmer-level-mode x86)
                   (x86p x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 9 lin-addr)))
              (equal (rvm80 lin-addr x86)
                     (b* (((mv flg bytes x86)
                           (rb (create-canonical-address-list 10 lin-addr)
                               r-x x86))
                          (result (combine-bytes bytes)))
                       (mv flg result x86))))
     :hints (("Goal"

              :in-theory (e/d (rvm80 rb-and-rvm16 rb-and-rvm64 rm80-guard-proof-helper)
                              (force (force))))))

   (defthm combine-bytes-size-for-rm80
     (implies (and (signed-byte-p 48 lin-addr)
                   (x86p x86)
                   (signed-byte-p 48 (+ 9 lin-addr)))
              (< (combine-bytes (mv-nth 1
                                        (rb (create-canonical-address-list 10 lin-addr)
                                            r-x x86)))
                 *2^80*))
     :rule-classes :linear))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((9+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                              (+ 9 (the (signed-byte #.*max-linear-address-size*)
                                        lin-addr)))))

        (if (mbe :logic (canonical-address-p 9+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                               9+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 10 lin-addr)
                           r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))

                 :exec
                 (if (programmer-level-mode x86)

                     (rvm80 lin-addr x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                           (+ 1 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                           (+ 2 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                           (la-to-pa 2+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                           (+ 3 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                           (la-to-pa 3+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                           (+ 4 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                           (la-to-pa 4+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                           (+ 5 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                           (la-to-pa 5+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                           (+ 6 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                           (la-to-pa 6+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                           (+ 7 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                           (la-to-pa 7+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+8*) 8+lin-addr)
                           (+ 8 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr8) x86)
                           (la-to-pa 8+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+9*) 9+lin-addr)
                           (+ 9 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr9) x86)
                           (la-to-pa 9+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0  (memi p-addr0  x86))
                          (byte1  (memi p-addr1  x86))
                          (byte2  (memi p-addr2  x86))
                          (byte3  (memi p-addr3  x86))
                          (byte4  (memi p-addr4  x86))
                          (byte5  (memi p-addr5  x86))
                          (byte6  (memi p-addr6  x86))
                          (byte7  (memi p-addr7  x86))
                          (byte8  (memi p-addr8  x86))
                          (byte9  (memi p-addr9  x86))

                          (word0 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte1 8))
                                              byte0)))
                          (word1 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte3 8))
                                              byte2)))
                          (word2 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte5 8))
                                              byte4)))
                          (dword0 (the (unsigned-byte 32)
                                       (logior (the (unsigned-byte 32) (ash word2 16))
                                               word1)))
                          (word3 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte7 8))
                                              byte6)))
                          (word4 (the (unsigned-byte 16)
                                      (logior (the (unsigned-byte 16) (ash byte9 8))
                                              byte8)))
                          (dword1 (the (unsigned-byte 32)
                                       (logior (the (unsigned-byte 32) (ash word4 16))
                                               word3)))
                          (qword (the (unsigned-byte 64)
                                      (logior (the (unsigned-byte 64) (ash dword1 32))
                                              dword0)))
                          (value
                           (the (unsigned-byte 80)
                                (logior (the (unsigned-byte 80) (ash qword 16))
                                        word0))))

                       (mv nil value x86)))))

          (mv 'rm80 0 x86)))

    (mv 'rm80 0 x86))

  ///

  (defthm-usb n80p-mv-nth-1-rm80
    :hyp (force (x86p x86))
    :bound 80
    :concl (mv-nth 1 (rm80 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p ash-monotone-2 rb))))
    :otf-flg t
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) (ash-monotone-2 rb))))
    :gen-type t)

  (defthm x86p-rm80
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm80 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (e/d () (rb unsigned-byte-p signed-byte-p (force)))))
    :rule-classes (:rewrite :type-prescription)))

(define wm80
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (unsigned-byte 80))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints (("Goal"
                 :expand ((create-canonical-address-list 10 lin-addr)
                          (create-canonical-address-list 9 (+ 1 lin-addr))
                          (create-canonical-address-list 8 (+ 2 lin-addr))
                          (create-canonical-address-list 7 (+ 3 lin-addr)))
                 :in-theory (e/d (wb-and-wvm80 byte-ify)
                                 ((:rewrite acl2::ash-0)
                                  (:rewrite acl2::zip-open)
                                  (:linear ash-monotone-2)
                                  (:linear bitops::logior-<-0-linear-2)
                                  (:rewrite xr-and-ia32e-la-to-pa-in-non-marking-mode)
                                  (:rewrite bitops::logior-equal-0)))))

  :prepwork

  ((defthmd wb-and-wvm80
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 9 lin-addr)))
              (equal (wvm80 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 10 lin-addr)
                          (byte-ify 10 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm16 wvm32 wvm64 wvm80 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force (force) nthcdr-byte-listp))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((9+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                           (+ 9 (the (signed-byte #.*max-linear-address-size*)
                                  lin-addr)))))


        (if (mbe :logic (canonical-address-p 9+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            9+lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list 10 lin-addr)
                  (byte-ify 10 val))
                 x86)

             :exec
             (if (programmer-level-mode x86)

                 (wvm80 lin-addr val x86)

               (let* ((cpl (cpl x86)))

                 (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                       (la-to-pa lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                       (+ 1 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                       (la-to-pa 1+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                       (+ 2 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                       (la-to-pa 2+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                       (+ 3 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                       (la-to-pa 3+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                       (+ 4 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                       (la-to-pa 4+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                       (+ 5 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                       (la-to-pa 5+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                       (+ 6 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                       (la-to-pa 6+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                       (+ 7 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                       (la-to-pa 7+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+8*) 8+lin-addr)
                       (+ 8 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr8) x86)
                       (la-to-pa 8+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+9*) 9+lin-addr)
                       (+ 9 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr9) x86)
                       (la-to-pa 9+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (byte0 (mbe :logic (part-select val :low 0 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff val))))
                      (byte1 (mbe :logic (part-select val :low 8 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -8)))))
                      (byte2 (mbe :logic (part-select val :low 16 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -16)))))
                      (byte3 (mbe :logic (part-select val :low 24 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -24)))))
                      (byte4 (mbe :logic (part-select val :low 32 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -32)))))
                      (byte5 (mbe :logic (part-select val :low 40 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -40)))))
                      (byte6 (mbe :logic (part-select val :low 48 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -48)))))
                      (byte7 (mbe :logic (part-select val :low 56 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -56)))))
                      (byte8 (mbe :logic (part-select val :low 64 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -64)))))
                      (byte9 (mbe :logic (part-select val :low 72 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -72)))))

                      (x86 (!memi p-addr0 byte0 x86))
                      (x86 (!memi p-addr1 byte1 x86))
                      (x86 (!memi p-addr2 byte2 x86))
                      (x86 (!memi p-addr3 byte3 x86))
                      (x86 (!memi p-addr4 byte4 x86))
                      (x86 (!memi p-addr5 byte5 x86))
                      (x86 (!memi p-addr6 byte6 x86))
                      (x86 (!memi p-addr7 byte7 x86))
                      (x86 (!memi p-addr8 byte8 x86))
                      (x86 (!memi p-addr9 byte9 x86)))

                   (mv nil x86)))))

          (mv 'wm80 x86)))

    (mv 'wm80 x86))

  ///

  (defthm x86p-wm80
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm80 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (rb force (force) unsigned-byte-p signed-byte-p))))
    :rule-classes (:rewrite :type-prescription)))

(define rm128
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member  :r :x))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)
  :guard-hints
  (("Goal"
    :in-theory
    (e/d (rb-and-rvm128
          las-to-pas-as-las-to-pas-tailrec
          las-to-pas-tailrec-opener
          las-to-pas-tailrec-nil
          combine-bytes-as-merge-16-u8s)
         (rvm128
          page-structure-marking-mode$inline
          xr-and-ia32e-la-to-pa-in-non-marking-mode
          mv-nth-2-ia32e-la-to-pa-system-level-non-marking-mode
          acl2::loghead-identity
          loghead-zero-smaller
          (:meta acl2::mv-nth-cons-meta)
          las-to-pas
          combine-bytes
          not
          ash-monotone-2
          default-+-2
          default-+-1
          unsigned-byte-p))))

  :prepwork
  ((local
    (defthmd rb-and-rvm128-helper-1
      (implies (and (programmer-level-mode x86)
                    (x86p x86)
                    (canonical-address-p lin-addr)
                    (canonical-address-p (+ 15 lin-addr)))
               (equal (rvm128 lin-addr x86)
                      (list
                       nil
                       (logior (combine-bytes
                                (mv-nth
                                 1
                                 (rb-1 (create-canonical-address-list 8 lin-addr)
                                       r-x x86 nil)))
                               (ash (combine-bytes
                                     (mv-nth
                                      1
                                      (rb-1 (create-canonical-address-list 8 (+ 8 lin-addr))
                                            r-x x86 nil)))
                                    64))
                       x86)))
      :hints (("Goal"
               :in-theory (e/d (rvm128 rb-and-rvm64)
                               (force (force)))))))

   (local
    (defthmd rb-and-rvm128-helper-2
      (implies (and (programmer-level-mode x86)
                    (x86p x86)
                    (canonical-address-p lin-addr)
                    (canonical-address-p (+ 15 lin-addr)))
               (equal
                (logior
                 (combine-bytes (mv-nth 1
                                        (rb-1 (create-canonical-address-list 8 lin-addr)
                                              r-x x86 nil)))
                 (ash (combine-bytes
                       (mv-nth 1
                               (rb-1 (create-canonical-address-list 8 (+ 8 lin-addr))
                                     r-x x86 nil)))
                      64))
                (combine-bytes (mv-nth 1
                                       (rb-1 (create-canonical-address-list 16 lin-addr)
                                             r-x x86 nil)))))
      :hints (("Goal"
               :in-theory (e/d () (force (force)))
               :use
               ((:instance split-rb-and-create-canonical-address-list-in-programmer-level-mode
                           (n 16)
                           (m 8))
                (:instance combine-bytes-of-append-of-byte-lists
                           (xs (mv-nth
                                1
                                (rb-1 (create-canonical-address-list 8 lin-addr)
                                      r-x x86 nil)))
                           (ys (mv-nth
                                1
                                (rb-1 (create-canonical-address-list 8 (+ 8 lin-addr))
                                      r-x x86 nil)))))))))

   (defthmd rb-and-rvm128
     (implies (and (programmer-level-mode x86)
                   (x86p x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 15 lin-addr)))
              (equal (rvm128 lin-addr x86)
                     (b* (((mv flg bytes x86)
                           (rb (create-canonical-address-list 16 lin-addr)
                               r-x x86))
                          (result (combine-bytes bytes)))
                       (mv flg result x86))))
     :hints (("Goal"

              :in-theory (e/d (rb-and-rvm128-helper-1
                               rb-and-rvm128-helper-2)
                              (force (force))))))

   (defthm combine-bytes-size-for-rm128
     (implies (and (signed-byte-p 48 lin-addr)
                   (x86p x86)
                   (signed-byte-p 48 (+ 15 lin-addr)))
              (< (combine-bytes
                  (mv-nth 1
                          (rb (create-canonical-address-list 16 lin-addr)
                              r-x x86)))
                 *2^128*))
     :rule-classes :linear)

   (defthm-usb unsigned-byte-p-128-of-merge-16-u8s-linear
     :hyp (and (unsigned-byte-p 8 h7)
               (unsigned-byte-p 8 h6)
               (unsigned-byte-p 8 h5)
               (unsigned-byte-p 8 h4)
               (unsigned-byte-p 8 h3)
               (unsigned-byte-p 8 h2)
               (unsigned-byte-p 8 h1)
               (unsigned-byte-p 8 h0)
               (unsigned-byte-p 8 l7)
               (unsigned-byte-p 8 l6)
               (unsigned-byte-p 8 l5)
               (unsigned-byte-p 8 l4)
               (unsigned-byte-p 8 l3)
               (unsigned-byte-p 8 l2)
               (unsigned-byte-p 8 l1)
               (unsigned-byte-p 8 l0))
     :bound 128
     :concl (bitops::merge-16-u8s h7 h6 h5 h4 h3 h2 h1 h0 l7 l6 l5 l4 l3 l2 l1 l0)
     :hints (("Goal" :in-theory (e/d* () (unsigned-byte-p))))
     :hints-l (("Goal" :in-theory (e/d* (unsigned-byte-p) (bitops::unsigned-byte-p-128-of-merge-16-u8s))
                :use ((:instance bitops::unsigned-byte-p-128-of-merge-16-u8s))))
     :gen-linear t)

   (local
    (defthmd logior-ash-to-logapp
      (implies (unsigned-byte-p w x)
               (equal (logior x (ash y w))
                      (logapp w x y)))
      :hints(("Goal" :in-theory (e/d* (ihsext-inductions
                                       ihsext-recursive-redefs)
                                      (unsigned-byte-p))))))

   (local
    (defthmd logior-ash-to-logapp-2
      (implies (unsigned-byte-p w x)
               (equal (logior x (ash y w) z)
                      (logior (logapp w x y) z)))
      :hints (("Goal" :use ((:instance (:theorem
                                        (implies (equal a b)
                                                 (equal (logior a c)
                                                        (logior b c))))
                                       (a (logior (ash y w) x))
                                       (b (logapp w x y))))
               :in-theory (e/d (logior-ash-to-logapp))))))


   (local (defthm logior-0
            (equal (logior x 0) (ifix x))))

   (defthmd combine-bytes-as-merge-16-u8s
     (implies
      (and (unsigned-byte-p 8 b0)  (unsigned-byte-p 8 b1)  (unsigned-byte-p 8 b2)  (unsigned-byte-p 8 b3)
           (unsigned-byte-p 8 b4)  (unsigned-byte-p 8 b5)  (unsigned-byte-p 8 b6)  (unsigned-byte-p 8 b7)
           (unsigned-byte-p 8 b8)  (unsigned-byte-p 8 b9)  (unsigned-byte-p 8 b10) (unsigned-byte-p 8 b11)
           (unsigned-byte-p 8 b12) (unsigned-byte-p 8 b13) (unsigned-byte-p 8 b14) (unsigned-byte-p 8 b15))
      (equal
       (combine-bytes
        (list
         b0 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15))
       (bitops::merge-16-u8s
        b15 b14 b13 b12 b11 b10 b9 b8 b7 b6 b5 b4 b3 b2 b1 b0)))
     :hints (("goal" :in-theory (e/d (push-ash-inside-logior
                                      merge-16-u8s
                                      logior-ash-to-logapp)
                                     (unsigned-byte-p
                                      acl2::commutativity-of-logior))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((15+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                               (+ 15 (the (signed-byte #.*max-linear-address-size*)
                                          lin-addr)))))

        (if (mbe :logic (canonical-address-p 15+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                               15+lin-addr)
                          #.*2^47*))

            (mbe :logic
                 (b* (((mv flg bytes x86)
                       (rb (create-canonical-address-list 16 lin-addr)
                           r-x x86))
                      (result (combine-bytes bytes)))
                   (mv flg result x86))

                 :exec
                 (if (programmer-level-mode x86)

                     (rvm128 lin-addr x86)

                   (let* ((cpl (cpl x86)))

                     (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                           (la-to-pa lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                           (+ 1 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                           (la-to-pa 1+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                           (+ 2 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                           (la-to-pa 2+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                           (+ 3 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                           (la-to-pa 3+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                           (+ 4 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                           (la-to-pa 4+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                           (+ 5 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                           (la-to-pa 5+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                           (+ 6 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                           (la-to-pa 6+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                           (+ 7 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                           (la-to-pa 7+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+8*) 8+lin-addr)
                           (+ 8 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr8) x86)
                           (la-to-pa 8+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+9*) 9+lin-addr)
                           (+ 9 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr9) x86)
                           (la-to-pa 9+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+10*) 10+lin-addr)
                           (+ 10 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr10) x86)
                           (la-to-pa 10+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+11*) 11+lin-addr)
                           (+ 11 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr11) x86)
                           (la-to-pa 11+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+12*) 12+lin-addr)
                           (+ 12 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr12) x86)
                           (la-to-pa 12+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+13*) 13+lin-addr)
                           (+ 13 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr13) x86)
                           (la-to-pa 13+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+14*) 14+lin-addr)
                           (+ 14 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr14) x86)
                           (la-to-pa 14+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))
                          ((the (signed-byte #.*max-linear-address-size+15*) 15+lin-addr)
                           (+ 15 lin-addr))
                          ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr15) x86)
                           (la-to-pa 15+lin-addr r-x cpl x86))
                          ((when flag) (mv flag 0 x86))

                          (byte0  (memi p-addr0  x86))
                          (byte1  (memi p-addr1  x86))
                          (byte2  (memi p-addr2  x86))
                          (byte3  (memi p-addr3  x86))
                          (byte4  (memi p-addr4  x86))
                          (byte5  (memi p-addr5  x86))
                          (byte6  (memi p-addr6  x86))
                          (byte7  (memi p-addr7  x86))
                          (byte8  (memi p-addr8  x86))
                          (byte9  (memi p-addr9  x86))
                          (byte10 (memi p-addr10 x86))
                          (byte11 (memi p-addr11 x86))
                          (byte12 (memi p-addr12 x86))
                          (byte13 (memi p-addr13 x86))
                          (byte14 (memi p-addr14 x86))
                          (byte15 (memi p-addr15 x86))

                          (oword
                           (the (unsigned-byte 128)
                                (bitops::merge-16-u8s
                                 byte15 byte14 byte13 byte12
                                 byte11 byte10 byte9  byte8
                                 byte7  byte6  byte5  byte4
                                 byte3  byte2  byte1  byte0))))

                       (mv nil oword x86)))))

          (mv 'rm128 0 x86)))

    (mv 'rm128 0 x86))

  ///

  (defthm-usb n128p-mv-nth-1-rm128
    :hyp (force (x86p x86))
    :bound 128
    :concl (mv-nth 1 (rm128 lin-addr r-x x86))
    :hints (("Goal" :in-theory (e/d () (signed-byte-p ash-monotone-2 rb))))
    :otf-flg t
    :gen-linear t
    :hints-l (("Goal" :in-theory (e/d (signed-byte-p) (ash-monotone-2 rb))))
    :gen-type t)

  (defthm x86p-rm128
    (implies (force (x86p x86))
             (x86p (mv-nth 2 (rm128 lin-addr r-x x86))))
    :hints (("Goal" :in-theory (e/d () (rb unsigned-byte-p signed-byte-p (force)))))
    :rule-classes (:rewrite :type-prescription)))

(define wm128
  ((lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (unsigned-byte 128))
   (x86))

  :parents (x86-top-level-memory)
  :guard (canonical-address-p lin-addr)

  :guard-hints
  (("Goal"
    :in-theory (e/d (wb-and-wvm128
                     byte-ify
                     las-to-pas-as-las-to-pas-tailrec
                     las-to-pas-tailrec-opener
                     las-to-pas-tailrec-nil
                     create-addr-bytes-alist-opener)
                    (wvm128
                     las-to-pas))))

  :prepwork
  ((defthmd wb-and-wvm128
     (implies (and (programmer-level-mode x86)
                   (canonical-address-p lin-addr)
                   (canonical-address-p (+ 15 lin-addr)))
              (equal (wvm128 lin-addr val x86)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list 16 lin-addr)
                          (byte-ify 16 val))
                         x86)))
     :hints (("Goal" :in-theory (e/d (wm08 wvm08 wvm32 wvm64 wvm128 byte-ify)
                                     (append-and-create-addr-bytes-alist
                                      cons-and-create-addr-bytes-alist
                                      append-and-addr-byte-alistp
                                      force (force) nthcdr-byte-listp)))))

   (defthmd create-addr-bytes-alist-opener
     (implies
      (and (consp addr-list)
           (equal (len addr-list) (len byte-list)))
      (equal (create-addr-bytes-alist addr-list byte-list)
             (acons (car addr-list) (car byte-list)
                    (create-addr-bytes-alist (cdr addr-list)
                                             (cdr byte-list)))))))

  (if (mbt (canonical-address-p lin-addr))

      (let* ((15+lin-addr (the (signed-byte #.*max-linear-address-size+1*)
                            (+ 15 (the (signed-byte #.*max-linear-address-size*)
                                    lin-addr)))))


        (if (mbe :logic (canonical-address-p 15+lin-addr)
                 :exec (< (the (signed-byte #.*max-linear-address-size+1*)
                            15+lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list 16 lin-addr)
                  (byte-ify 16 val))
                 x86)

             :exec
             (if (programmer-level-mode x86)

                 (wvm128 lin-addr val x86)

               (let* ((cpl (cpl x86)))

                 (b* (((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr0) x86)
                       (la-to-pa lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+1*) 1+lin-addr)
                       (+ 1 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr1) x86)
                       (la-to-pa 1+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+2*) 2+lin-addr)
                       (+ 2 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr2) x86)
                       (la-to-pa 2+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+3*) 3+lin-addr)
                       (+ 3 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr3) x86)
                       (la-to-pa 3+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+4*) 4+lin-addr)
                       (+ 4 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr4) x86)
                       (la-to-pa 4+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+5*) 5+lin-addr)
                       (+ 5 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr5) x86)
                       (la-to-pa 5+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+6*) 6+lin-addr)
                       (+ 6 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr6) x86)
                       (la-to-pa 6+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+7*) 7+lin-addr)
                       (+ 7 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr7) x86)
                       (la-to-pa 7+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+8*) 8+lin-addr)
                       (+ 8 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr8) x86)
                       (la-to-pa 8+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+9*) 9+lin-addr)
                       (+ 9 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr9) x86)
                       (la-to-pa 9+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+10*) 10+lin-addr)
                       (+ 10 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr10) x86)
                       (la-to-pa 10+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+11*) 11+lin-addr)
                       (+ 11 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr11) x86)
                       (la-to-pa 11+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+12*) 12+lin-addr)
                       (+ 12 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr12) x86)
                       (la-to-pa 12+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+13*) 13+lin-addr)
                       (+ 13 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr13) x86)
                       (la-to-pa 13+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+14*) 14+lin-addr)
                       (+ 14 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr14) x86)
                       (la-to-pa 14+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))
                      ((the (signed-byte #.*max-linear-address-size+15*) 15+lin-addr)
                       (+ 15 lin-addr))
                      ((mv flag (the (unsigned-byte #.*physical-address-size*) p-addr15) x86)
                       (la-to-pa 15+lin-addr :w cpl x86))
                      ((when flag) (mv flag x86))

                      (byte0 (mbe :logic (part-select val :low 0 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff val))))
                      (byte1 (mbe :logic (part-select val :low 8 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -8)))))
                      (byte2 (mbe :logic (part-select val :low 16 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -16)))))
                      (byte3 (mbe :logic (part-select val :low 24 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -24)))))
                      (byte4 (mbe :logic (part-select val :low 32 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -32)))))
                      (byte5 (mbe :logic (part-select val :low 40 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -40)))))
                      (byte6 (mbe :logic (part-select val :low 48 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -48)))))
                      (byte7 (mbe :logic (part-select val :low 56 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -56)))))
                      (byte8 (mbe :logic (part-select val :low 64 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -64)))))
                      (byte9 (mbe :logic (part-select val :low 72 :width 8)
                                  :exec (the (unsigned-byte 8)
                                          (logand #xff (ash val -72)))))
                      (byte10 (mbe :logic (part-select val :low 80 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -80)))))
                      (byte11 (mbe :logic (part-select val :low 88 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -88)))))
                      (byte12 (mbe :logic (part-select val :low 96 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -96)))))
                      (byte13 (mbe :logic (part-select val :low 104 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -104)))))
                      (byte14 (mbe :logic (part-select val :low 112 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -112)))))
                      (byte15 (mbe :logic (part-select val :low 120 :width 8)
                                   :exec (the (unsigned-byte 8)
                                           (logand #xff (ash val -120)))))

                      (x86 (!memi p-addr0 byte0 x86))
                      (x86 (!memi p-addr1 byte1 x86))
                      (x86 (!memi p-addr2 byte2 x86))
                      (x86 (!memi p-addr3 byte3 x86))
                      (x86 (!memi p-addr4 byte4 x86))
                      (x86 (!memi p-addr5 byte5 x86))
                      (x86 (!memi p-addr6 byte6 x86))
                      (x86 (!memi p-addr7 byte7 x86))
                      (x86 (!memi p-addr8 byte8 x86))
                      (x86 (!memi p-addr9 byte9 x86))
                      (x86 (!memi p-addr10 byte10 x86))
                      (x86 (!memi p-addr11 byte11 x86))
                      (x86 (!memi p-addr12 byte12 x86))
                      (x86 (!memi p-addr13 byte13 x86))
                      (x86 (!memi p-addr14 byte14 x86))
                      (x86 (!memi p-addr15 byte15 x86)))

                   (mv nil x86)))))

          (mv 'wm128 x86)))

    (mv 'wm128 x86))

  ///

  (defthm x86p-wm128
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm128 lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (rb force (force) unsigned-byte-p signed-byte-p))))
    :rule-classes (:rewrite :type-prescription)))

;; ======================================================================

(defsection Parametric-Memory-Reads-and-Writes

  :parents (x86-top-level-memory)

  :short "Functions to read/write 8/16/32/64/128 bits into the memory:"

  (define rm-size
    ((nbytes :type (member 1 2 4 6 8 10 16))
     (addr   :type (signed-byte #.*max-linear-address-size*))
     (r-x  :type (member :r :x))
     (x86))
    :guard (natp nbytes)
    :inline t
    :enabled t
    (case nbytes
      (1 (rm08 addr r-x x86))
      (2 (rm16 addr r-x x86))
      (4 (rm32 addr r-x x86))
      (6
       ;; Use case: To fetch operands of the form m16:32 (see far jmp
       ;; instruction).
       (rm48 addr r-x x86))
      (8 (rm64 addr r-x x86))
      (10
       ;; Use case: The instructions LGDT and LIDT need to read 10
       ;; bytes at once.
       (rm80 addr r-x x86))
      (16 (rm128 addr r-x x86))
      (otherwise
       (if (mbe :logic (canonical-address-p (+ -1 nbytes addr))
                :exec (< (+ nbytes addr) #.*2^47-1*))
           (b* (((mv flg bytes x86)
                 (rb (create-canonical-address-list nbytes addr) r-x x86))
                ((when flg)
                 (mv flg 0 x86)))
             (mv nil (combine-bytes bytes) x86))
         (mv 'rm-size 0 x86))))

    ///

    (defthm x86p-of-mv-nth-2-of-rm-size
      (implies (force (x86p x86))
               (x86p (mv-nth 2 (rm-size bytes lin-addr r-x x86)))))

    (defthmd rm-size-to-rb
      (implies (and (canonical-address-p (+ -1 nbytes lin-addr))
                    (canonical-address-p lin-addr))
               (b* (((mv flg1 val x86-1)
                     (rm-size nbytes lin-addr r-x x86))
                    ((mv flg2 bytes x86-2)
                     (rb (create-canonical-address-list nbytes lin-addr) r-x x86)))
                 (and (equal flg1 flg2)
                      (equal val (if flg1 0 (combine-bytes bytes)))
                      (equal x86-1 x86-2))))
      :hints (("Goal" :in-theory (e/d* (signed-byte-p rm08 rm128 rm32 rm48 rm64 rm80 rm16)
                                       (create-canonical-address-list-1))))))

  (define rim-size
    ((nbytes :type (member 1 2 4 8))
     (addr   :type (signed-byte #.*max-linear-address-size*))
     (r-x  :type (member :r :x))
     (x86))
    :inline t
    :enabled t
    (case nbytes
      (1 (rim08 addr r-x x86))
      (2 (rim16 addr r-x x86))
      (4 (rim32 addr r-x x86))
      (8 (rim64 addr r-x x86))
      (otherwise
       (mv 'rim-size nbytes x86))))

  (define wm-size
    ((nbytes :type (member 1 2 4 6 8 10 16))
     (addr   :type (signed-byte #.*max-linear-address-size*))
     (val    :type (integer 0 *))
     (x86))
    :guard (case nbytes
             (1  (n08p val))
             (2  (n16p val))
             (4  (n32p val))
             (6  (n48p val))
             (8  (n64p val))
             (10 (n80p val))
             (16 (n128p val)))
    :inline t
    :enabled t
    (case nbytes
      (1 (wm08 addr val x86))
      (2 (wm16 addr val x86))
      (4 (wm32 addr val x86))
      (6
       ;; Use case: To store operands of the form m16:32.
       (wm48 addr val x86))
      (8 (wm64 addr val x86))
      (10
       ;; Use case: Instructions like SGDT and SIDT write 10 bytes to
       ;; the memory.
       (wm80 addr val x86))
      (16 (wm128 addr val x86))
      (otherwise
       (if (mbe :logic (canonical-address-p (+ -1 nbytes addr))
                :exec (< (+ nbytes addr) #.*2^47-1*))
           (b* (((mv flg x86)
                 (wb (create-addr-bytes-alist
                      (create-canonical-address-list nbytes addr)
                      (byte-ify nbytes val))
                     x86))
                ((when flg)
                 (mv flg x86)))
             (mv nil x86))
         (mv 'wm-size x86))))

    ///

    (defthm x86p-wm-size
      (implies (force (x86p x86))
               (x86p (mv-nth 1 (wm-size nbytes lin-addr val x86))))
      :hints (("Goal" :in-theory (e/d () (rb force (force) unsigned-byte-p signed-byte-p)))))

    (defthmd wm-size-to-wb
      (implies (and (canonical-address-p (+ -1 nbytes lin-addr))
                    (canonical-address-p lin-addr))
               (b* (((mv flg1 x86-1)
                     (wm-size nbytes lin-addr val x86))
                    ((mv flg2 x86-2)
                     (wb (create-addr-bytes-alist
                          (create-canonical-address-list nbytes lin-addr)
                          (byte-ify nbytes val))
                         x86)))
                 (and (equal flg1 flg2)
                      (equal x86-1 x86-2))))
      :hints (("Goal" :in-theory (e/d* (signed-byte-p
                                        las-to-pas
                                        byte-ify
                                        wm08 wm128 wm32 wm48 wm64 wm80 wm16)
                                       ())))))

  (define wim-size
    ((nbytes :type (member 1 2 4 8))
     (addr   :type (signed-byte #.*max-linear-address-size*))
     (val    :type integer)
     (x86))
    :guard (case nbytes
             (1 (i08p val))
             (2 (i16p val))
             (4 (i32p val))
             (8 (i64p val)))
    :inline t
    :enabled t
    (case nbytes
      (1 (wim08 addr val x86))
      (2 (wim16 addr val x86))
      (4 (wim32 addr val x86))
      (8 (wim64 addr val x86))
      (otherwise
       (mv 'wim-size x86)))))

#||

;; The following definitions of rm/wm-size are nicer in one sense that
;; their definition is in terms of rb/wb, unlike in the functions
;; above, where the equivalence of rm/wm-size to rb/wb is established
;; via a theorem.  However, these nicer definitions cause some proofs
;; to fail in x86-decoding-and-spec-utils.lisp, which I'd rather not
;; fix right now.

(define rm-size
  ((nbytes   :type (member 1 2 4 6 8 10 16))
   (lin-addr :type (signed-byte #.*max-linear-address-size*))
   (r-x    :type (member :r :x))
   (x86))
  :guard (natp nbytes)
  :guard-hints (("Goal"
                 :in-theory
                 (e/d* (signed-byte-p rm08 rm128 rm32 rm48 rm64 rm80 rm16)
                       (create-canonical-address-list-1))))
  :inline t

  (if (mbt (canonical-address-p lin-addr))

      (let* ((last-lin-addr (the (signed-byte 49)
                              (+ -1 nbytes lin-addr))))
        (if (mbe :logic (canonical-address-p last-lin-addr)
                 :exec (< (the (signed-byte 49) last-lin-addr)
                          #.*2^47*))

            (mbe
             :logic
             (b* (((mv flg bytes x86)
                   (rb (create-canonical-address-list nbytes lin-addr)
                       r-x x86))
                  (result (combine-bytes bytes)))
               (mv flg result x86))

             :exec

             (case nbytes
               (1 (rm08 lin-addr r-x x86))
               (2 (rm16 lin-addr r-x x86))
               (4 (rm32 lin-addr r-x x86))
               (6
                  ;; Use case: To fetch operands of the form m16:32 (see far jmp ;
                  ;; instruction). ;
                (rm48 lin-addr r-x x86))
               (8 (rm64 lin-addr r-x x86))
               (10
                  ;; Use case: The instructions LGDT and LIDT need to read 10 ;
                  ;; bytes at once. ;
                (rm80 lin-addr r-x x86))
               (16 (rm128 lin-addr r-x x86))
               (otherwise
                (b* (((mv flg bytes x86)
                      (rb (create-canonical-address-list nbytes lin-addr)
                          r-x x86))
                     ((when flg)
                      (mv flg 0 x86)))
                  (mv nil (combine-bytes bytes) x86)))))

          (mv 'rm-size 0 x86)))
    (mv 'rm-size 0 x86))

  ///

  (defthm x86p-of-mv-nth-2-of-rm-size
    (implies (and (signed-byte-p *max-linear-address-size* lin-addr)
                  (x86p x86))
             (x86p (mv-nth 2 (rm-size bytes lin-addr r-x x86))))))

(define wm-size
  ((nbytes   :type (member 1 2 4 6 8 10 16))
   (lin-addr :type (signed-byte #.*max-linear-address-size*))
   (val      :type (integer 0 *))
   (x86))
  :guard (and (natp nbytes)
              (case nbytes
                (1  (n08p val))
                (2  (n16p val))
                (4  (n32p val))
                (6  (n48p val))
                (8  (n64p val))
                (10 (n80p val))
                (16 (n128p val))))
  :guard-hints (("Goal" :in-theory (e/d* (signed-byte-p
                                          las-to-pas
                                          byte-ify
                                          wm08 wm128 wm32 wm48 wm64 wm80 wm16)
                                         ())))
  :inline t
  (if (mbt (canonical-address-p lin-addr))
      (let* ((last-lin-addr (the (signed-byte 49)
                              (+ -1 nbytes lin-addr))))
        (if
            (mbe :logic (canonical-address-p last-lin-addr)
                 :exec (< (the (signed-byte 49) last-lin-addr)
                          #.*2^47*))
            (mbe
             :logic
             (wb (create-addr-bytes-alist
                  (create-canonical-address-list nbytes lin-addr)
                  (byte-ify nbytes val))
                 x86)
             :exec
             (case nbytes
               (1 (wm08 lin-addr val x86))
               (2 (wm16 lin-addr val x86))
               (4 (wm32 lin-addr val x86))
               (6
                  ;; Use case: To store operands of the form m16:32. ;
                (wm48 lin-addr val x86))
               (8 (wm64 lin-addr val x86))
               (10
                  ;; Use case: Instructions like SGDT and SIDT write 10 bytes to ;
                  ;; the memory. ;
                (wm80 lin-addr val x86))
               (16 (wm128 lin-addr val x86))
               (otherwise
                (wb (create-addr-bytes-alist
                     (create-canonical-address-list nbytes lin-addr)
                     (byte-ify nbytes val))
                    x86))))

          (mv 'wm-size x86)))
    (mv 'wm-size x86))

  ///

  (defthm x86p-wm-size
    (implies (force (x86p x86))
             (x86p (mv-nth 1 (wm-size nbytes lin-addr val x86))))
    :hints (("Goal" :in-theory (e/d () (rb force (force) unsigned-byte-p signed-byte-p))))))

||#

;; ======================================================================

;; Writing canonical address to memory:

;; A short note on why I couldn't make do with wim64 to write a
;; canonical address to the memory:

;; Here's a small, compelling example.  The following is some
;; information provided by profile when running fib(24); here, wim64
;; was used to store a canonical address in the memory in the
;; specification of the CALL (#xE8) instruction.

;; (defun X86ISA::X86-CALL-E8-OP/EN-M calls     7.50E+4
;; ...
;; Heap bytes allocated                         4.80E+6; 33.3%
;; Heap bytes allocated per call                64

;; So, for fib(24), 4,801,792 bytes are allocated on the heap!  And
;; this is with paging turned off.

;; The reason why wim64 uses such a lot of memory is because it
;; creates bignums all the time.  But when I have to store a canonical
;; address in the memory, I *know* that I'm storing a quantity lesser
;; than 64-bits.  Thus, I use write-canonical-address-to-memory to
;; avoid the creation of bignums.  Like the other rm* and wm*
;; functions, I have an MBE inside write-canonical-address-to-memory,
;; where the :logic part is defined in terms of WB.

;; Note that write-canonical-address-to-memory is optimized in the
;; programmer-level mode only --- in the system-level mode, it's
;; merely a call of wm64.

(define write-canonical-address-to-memory-user-exec
  ((lin-addr          :type (signed-byte  #.*max-linear-address-size*))
   (canonical-address :type (signed-byte  #.*max-linear-address-size*))
   (x86))

  :inline t
  :parents (x86-top-level-memory)

  :guard (and (canonical-address-p lin-addr)
              (canonical-address-p (+ 7 lin-addr))
              (programmer-level-mode x86))
  :guard-hints (("Goal" :in-theory (e/d (n16-to-i16)
                                        ())))

  (if (mbt (and (programmer-level-mode x86)
                (canonical-address-p (+ 7 lin-addr))))

      (b* (((the (unsigned-byte 32) canonical-address-low-nat)
            (n32 canonical-address))
           ((the (signed-byte 32) canonical-address-high-int)
            (mbe
             :logic
             (n16-to-i16 (part-select canonical-address :low 32 :high 47))
             :exec
             (the (signed-byte 16)
               (ash canonical-address -32))))
           ((mv flg0 x86)
            (wm32 lin-addr canonical-address-low-nat x86))
           ((the (signed-byte #.*max-linear-address-size+1*) next-addr)
            (+ 4 lin-addr))
           ((when (mbe :logic (not (canonical-address-p next-addr))
                       :exec (<= #.*2^47*
                                 (the (signed-byte
                                       #.*max-linear-address-size+1*)
                                   next-addr))))
            (mv 'wm64-canonical-address-user-mode x86))
           ((mv flg1 x86)
            (wim32 next-addr canonical-address-high-int x86))
           ((when (or flg0 flg1))
            (mv 'wm64-canonical-address-user-mode x86)))
        (mv nil x86))

    (mv 'unreachable x86)))

(local (in-theory (e/d* () ((:meta acl2::mv-nth-cons-meta)))))

(local
 (defthm mv-nth-0-of-list-of-2-things
   (equal (mv-nth 0 (list x y)) x)))

(local
 (defthm mv-nth-1-of-list-of-2-things
   (equal (mv-nth 1 (list x y)) y)))

(local
 (defthm combining-wb-1
   (implies (and (addr-byte-alistp alst-1)
                 (addr-byte-alistp alst-2)
                 (programmer-level-mode x86)
                 (x86p x86))
            (equal
             (mv-nth 1 (wb-1 alst-2 (mv-nth 1 (wb-1 alst-1 x86))))
             (mv-nth 1 (wb-1 (append alst-1 alst-2) x86))))
   :hints (("Goal" :in-theory (e/d* (wb-1)
                                    ((:meta acl2::mv-nth-cons-meta)))))))

(local
 (defthmd wb-1-in-programmer-level-mode
   (implies (and (addr-byte-alistp addr-lst)
                 (x86p x86)
                 (programmer-level-mode x86))
            (equal (wb-1 addr-lst x86)
                   (mv
                    nil
                    (mv-nth 1 (wb-1 addr-lst x86)))))))


(local
 (defthm write-canonical-address-to-memory-user-exec-and-wb
   (implies (and (programmer-level-mode x86)
                 (canonical-address-p lin-addr)
                 (canonical-address-p canonical-address)
                 (canonical-address-p (+ 7 lin-addr))
                 (x86p x86))
            (equal (write-canonical-address-to-memory-user-exec
                    lin-addr canonical-address x86)
                   (wb (create-addr-bytes-alist
                        (create-canonical-address-list 8 lin-addr)
                        (byte-ify 8 canonical-address))
                       x86)))
   :hints (("Goal"
            :use ((:instance create-canonical-address-list-split
                             (j 4)
                             (k 4)
                             (addr lin-addr))
                  (:instance wb-1-in-programmer-level-mode
                             (addr-lst (create-addr-bytes-alist
                                        (create-canonical-address-list 8 lin-addr)
                                        (list (loghead 8 canonical-address)
                                              (loghead 8 (logtail 8 canonical-address))
                                              (loghead 8 (logtail 16 canonical-address))
                                              (loghead 8 (logtail 24 canonical-address))
                                              (loghead 8 (logtail 32 canonical-address))
                                              (loghead 8 (logtail 40 canonical-address))
                                              (loghead 8 (logtail 48 canonical-address))
                                              (loghead 8 (logtail 56 canonical-address)))))))
            :in-theory (e/d*
                        (write-canonical-address-to-memory-user-exec
                         wim32
                         wm32
                         byte-ify
                         wb-and-wvm64
                         wb-1)
                        ())))))

(define write-canonical-address-to-memory
  ((lin-addr          :type (signed-byte #.*max-linear-address-size*))
   (canonical-address :type (signed-byte #.*max-linear-address-size*))
   (x86))

  :parents (x86-top-level-memory)
  :guard-hints (("Goal" :in-theory (e/d (n16-to-i16)
                                        ())))

  (let* ((7+lin-addr (the (signed-byte #.*max-linear-address-size+2*)
                       (+ 7 lin-addr))))


    (if (mbe :logic (canonical-address-p 7+lin-addr)
             :exec (< (the (signed-byte #.*max-linear-address-size+2*)
                        7+lin-addr)
                      #.*2^47*))


        (if (programmer-level-mode x86)

            (mbe :logic
                 (wb (create-addr-bytes-alist
                      (create-canonical-address-list 8 lin-addr)
                      (byte-ify 8 canonical-address))
                     x86)
                 :exec
                 (write-canonical-address-to-memory-user-exec
                  lin-addr canonical-address x86))

          (b* ((canonical-address-unsigned-val
                (mbe :logic (loghead 64 canonical-address)
                     :exec (logand #.*2^64-1* canonical-address))))
            ;; Note that calling wm64 here will be a tad expensive ---
            ;; for one, there's an extra function call. Also, the
            ;; programmer-level-mode field will have to be checked
            ;; again inside wm64. However, this is better for
            ;; reasoning than laying down the code again. As it is,
            ;; performance in the system-level mode is quite less than
            ;; that in programmer-level mode.
            (wm64 lin-addr canonical-address-unsigned-val x86)))

      (mv 'write-canonical-address-to-memory-error x86)))

  ///

  (defthm x86p-write-canonical-address-to-memory
    (implies (force (x86p x86))
             (x86p (mv-nth
                    1
                    (write-canonical-address-to-memory
                     lin-addr canonical-address x86))))
    :rule-classes (:rewrite :type-prescription)))

;; ======================================================================

(define program-at (addresses bytes x86)

  :parents (x86-top-level-memory)
  :non-executable t

  :short "Predicate that makes a statement about a program's location
  in the memory"

  :long "<p>We use @('program-at') to state that a program, given by
  as a list of @('bytes'), is located at the list of @('addresses') in
  the memory of the x86 state.  Note that this function is
  non-executable; we use it only for reasoning about
  machine-code.</p>"

  :guard (and (canonical-address-listp addresses)
              (byte-listp bytes))

  (b* (((mv flg bytes-read ?x86)
        (rb addresses :x x86))
       ((when flg) nil))
    (equal bytes bytes-read))

  ///

  (defthm program-at-xw-in-programmer-level-mode
    (implies (and (programmer-level-mode x86)
                  (not (equal fld :mem))
                  (not (equal fld :programmer-level-mode)))
             (equal (program-at addresses bytes (xw fld index value x86))
                    (program-at addresses bytes x86)))
    :hints (("Goal" :in-theory (e/d* () (rb))))))

;; ======================================================================
