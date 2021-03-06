; Copyright (C) 2016, Regents of the University of Texas
; Marijn Heule, Warren A. Hunt, Jr., and Matt Kaufmann
; License: A 3-clause BSD license.  See the LICENSE file distributed with ACL2.

; See ../../README.

(in-package "ACL2")

(defmacro defwrapper (name args &rest rest)

; Use defun-notinline below if you want to profile name; else use defabbrev.

  (let (;; (mac 'defun-notinline)
        (mac 'defun-inline)
        ;; (mac 'defabbrev)
        )
    `(,mac ,name ,args
           ,@(and (not (eq mac 'defabbrev))
                  '((declare (xargs :guard t))))
           ,@rest)))

(defun literalp (x)
  (declare (xargs :guard t))
  (and (integerp x)
       (not (equal x 0))))

(defthm literalp-compound-recognizer
  (equal (literalp x)
         (and (integerp x)
              (not (equal x 0))))
  :rule-classes :compound-recognizer)

(in-theory (disable literalp))

(defun literal-listp (x)
  (declare (xargs :guard t))
  (if (atom x)
      (null x)
    (and (literalp (car x))
         (literal-listp (cdr x)))))

(defmacro negate (x)
  `(- ,x))

(defun unique-literalsp (x)
  (declare (xargs :guard (literal-listp x)))
  (if (atom x)
      t
    (and (not (member (car x) (cdr x)))
         (unique-literalsp (cdr x)))))

(defun conflicting-literalsp (x)
  (declare (xargs :guard (literal-listp x)))
  (if (atom x)
      nil
    (or (member (negate (car x)) (cdr x))
        (conflicting-literalsp (cdr x)))))

(defun clause-or-assignment-p (clause)
  (declare (xargs :guard t))
  (and (literal-listp clause)
       (unique-literalsp clause)
       (not (conflicting-literalsp clause))))

(defthm clause-or-assignment-p-forward-to-literal-listp
  (implies (clause-or-assignment-p x)
           (literal-listp x))
  :rule-classes :forward-chaining)

(defthm literal-listp-forward-to-eqlable-listp
  (implies (literal-listp x)
           (eqlable-listp x))
  :rule-classes :forward-chaining)

(defconst *deleted-clause* 0)

(defmacro deleted-clause-p (val)
  `(eql ,val *deleted-clause*))

(defun formula-fal-p (fal)

; Ensure tat every index is bound to a clause or *deleted-clause*.

  (declare (xargs :guard t))
  (if (atom fal)
      (null fal)
    (let ((pair (car fal)))
      (and (consp pair)
           (posp (car pair))
           (let ((val (cdr pair)))
             (or (deleted-clause-p val)
                 (clause-or-assignment-p val)))
           (formula-fal-p (cdr fal))))))

(defun formula-fal-max (fal)
  (declare (xargs :guard (formula-fal-p fal)))
  (cond ((atom fal) 0)
        ((deleted-clause-p (cdar fal))
         (formula-fal-max (cdr fal)))
        (t (max (caar fal)
                (formula-fal-max (cdr fal))))))

(defmacro formula-fal (formula)
  formula)

(defmacro make-formula (fal)
  fal)

(defun formula-p (formula)
  (declare (xargs :guard t))
  (formula-fal-p formula))

(defun clause-listp (x)
  (declare (xargs :guard t))
  (if (atom x)
      (null x)
    (and (clause-or-assignment-p (car x))
         (clause-listp (cdr x)))))

(defmacro index-listp (x)
  `(pos-listp ,x))

(defun drat-hint-p (x)
  (declare (xargs :guard t))
  (and (consp x)
       (posp (car x)) ; index
       (index-listp (cdr x))))

(defun drat-hint-listp (x)
  (declare (xargs :guard t))
  (cond ((atom x) (null x))
        (t (and (drat-hint-p (car x))
                (drat-hint-listp (cdr x))))))

(defthm drat-hint-listp-forward-to-alistp
  (implies (drat-hint-listp x)
           (alistp x))
  :rule-classes :forward-chaining)

(defrec add-step
  ((index . clause)
   .
   (rup-indices . drat-hints))
  t)

(defun add-step-p (x)
  (declare (xargs :guard t))
  (and (weak-add-step-p x)
       (posp (access add-step x :index))
       (clause-or-assignment-p (access add-step x :clause))
       (index-listp (access add-step x :rup-indices))
       (drat-hint-listp (access add-step x :drat-hints))))

(defun proof-entry-p (entry)

; This function recognizes a "line" in the proof, which can have either of the
; following two formats.

; Deletion: (T i1 i2 ...), indicating deletion of the specified (by index)
; clauses.

; Addition: an ADD-STEP record indication addition of a clause with a given
; index and suitable unit propagation hints.

  (declare (xargs :guard t))
  (cond ((and (consp entry)
              (eq (car entry) t)) ; deletion
         (index-listp (cdr entry)))
        (t (add-step-p entry))))

(defmacro proof-entry-deletion-p (entry)

; assumes (proof-entry-p entry)

  `(eq (car ,entry) t))

(defmacro proof-entry-deletion-indices (entry)

; assumes (proof-entry-p entry) and (proof-entry-deletion-p entry)

  `(cdr ,entry))

(defun proofp (proof) ; primitive

; A proof is a true-list of proof-entry-p structures.

  (declare (xargs :guard t))
  (if (atom proof)
      (null proof)
    (and (proof-entry-p (car proof))
         (proofp (cdr proof)))))

(defthm proofp-forward-to-true-listp
  (implies (proofp x)
           (true-listp x))
  :rule-classes :forward-chaining)

(defun negate-clause-or-assignment (clause) ; primitive
  (declare (xargs :guard (clause-or-assignment-p clause)))
  (if (atom clause)
      nil
    (cons (negate (car clause))
          (negate-clause-or-assignment (cdr clause)))))

(defun-inline undefp (x)
  (declare (xargs :guard t))
  (not (booleanp x)))

(defun evaluate-literal (literal assignment)
  (declare (xargs :guard (and (literalp literal)
                              (clause-or-assignment-p assignment))))
  (cond
   ((member literal assignment) t)
   ((member (negate literal) assignment) nil)
   ;; When undefined, return 0.
   (t 0)))

(defun evaluate-clause (clause assignment)
  (declare (xargs :guard (and (clause-or-assignment-p clause)
                              (clause-or-assignment-p assignment))))
  (if (atom clause)
      nil
    (let* ((literal (car clause))
           (literal-value (evaluate-literal literal assignment)))
      (if (eq literal-value t)
          t
        (let* ((remaining-clause (cdr clause))
               (remaining-clause-value (evaluate-clause remaining-clause
                                                        assignment)))
          (cond
           ((eq remaining-clause-value t) t)
           ((undefp literal-value) 0)
           (t remaining-clause-value)))))))

(in-theory (disable clause-or-assignment-p))

(defthm clause-or-assignment-p-cdr
  (implies (clause-or-assignment-p clause)
           (clause-or-assignment-p (cdr clause)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defun is-unit-clause (clause assignment)

; If clause is a (pseudo) unit clause under assignment, return the unique
; unassigned literal (the others will be false).  Otherwise return nil unless
; the clause is false under assignment, in which case return t.

  (declare (xargs :guard (and (clause-or-assignment-p clause)
                              (clause-or-assignment-p assignment))
                  :guard-hints
                  (("Goal" :in-theory (enable clause-or-assignment-p)))))
  (if (atom clause)
      t ; top-level clause is false under assignment
    (let ((val (evaluate-literal (car clause) assignment)))
      (cond
       ((eq val t) nil)
       ((undefp val)
        (if (null (evaluate-clause (cdr clause) assignment))
            (car clause)
          nil))
       (t ; (null val)
        (is-unit-clause (cdr clause) assignment))))))

(defthm booleanp-evaluate-clause-monotone
  (implies (booleanp (evaluate-clause cl a))
           (booleanp (evaluate-clause cl (cons lit a)))))

(defmacro unit-propagation-error (msg formula indices assignment)
  `(prog2$ (er hard? 'unit-propagation "~@0" ,msg)
           (unit-propagation ,formula (cdr ,indices) ,assignment)))

(defwrapper my-hons-get (key alist)
  (hons-get key alist))

(defun unit-propagation (formula indices assignment)

; Return an extension of assignment by unit-propagation restricted to the given
; indices in formula, except that if a contradiction is found, return t
; instead.

  (declare (xargs :guard (and (formula-p formula)
                              (index-listp indices)
                              (clause-or-assignment-p assignment))
                  :verify-guards nil))
  (cond
   ((endp indices) assignment)
   (t (let* ((pair (my-hons-get (car indices) (formula-fal formula)))
             (clause (and pair
                          (not (deleted-clause-p (cdr pair)))
                          (cdr pair)))
             (unit-literal (and clause
                                (is-unit-clause clause assignment))))

; Note that (member (- unit-literal) assignment) is false, because of how
; unit-literal is chosen.  So we don't need to consider that case.

        (cond ((not unit-literal)

; This case is surprising.  See the long comment about the previous surprising
; case, above, for a discussion of why we handle surprising cases this way.

               (unit-propagation-error
                (msg "Unit-propagation has failed for index ~x0 because ~
                      ~@1."
                     (car indices)
                     (cond ((null pair)
                            "no formula was found for that index")
                           ((null clause)
                            "that clause had been deleted")
                           (t
                            "that clause is not a unit")))
                formula indices assignment))
              ((eq unit-literal t) ; found contradiction
               t)
              (t (unit-propagation formula
                                   (cdr indices)
                                   (add-to-set unit-literal assignment))))))))

(defthm literalp-is-unit-clause
  (implies (force (literal-listp clause))
           (or (literalp (is-unit-clause clause assignment))
               (booleanp (is-unit-clause clause assignment))))
  :rule-classes :type-prescription)

(defthm clause-or-assignment-p-cdr-hons-assoc-equal
  (let ((clause (cdr (hons-assoc-equal index fal))))
    (implies (and (formula-fal-p fal)
                  (not (deleted-clause-p clause)))
             (clause-or-assignment-p clause))))

(defthm backchain-to-clause-or-assignment-p
  (implies (clause-or-assignment-p clause)
           (and (literal-listp clause)
                (unique-literalsp clause)
                (not (conflicting-literalsp clause))))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defthm not-member-complement-unit-clause-assignment
  (implies (and (clause-or-assignment-p clause)
                (clause-or-assignment-p assignment))
           (not (member-equal (negate (is-unit-clause clause assignment))
                              assignment)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(verify-guards unit-propagation
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defun remove-literal (literal clause)
  (declare (xargs :guard (and (literalp literal)
                              (clause-or-assignment-p clause))))
  (if (atom clause)
      nil
    (if (equal (car clause) literal)
        (remove-literal literal (cdr clause))
      (cons (car clause)
            (remove-literal literal (cdr clause))))))

(defthm literal-listp-union-equal
  (implies (true-listp x)
           (equal (literal-listp (union-equal x y))
                  (and (literal-listp x)
                       (literal-listp y)))))

(defthm member-equal-remove-literal
  (implies (not (member-equal a x))
           (not (member-equal a (remove-literal b x)))))

(defthm clause-or-assignment-p-remove-literal
  (implies (clause-or-assignment-p y)
           (clause-or-assignment-p (remove-literal x y)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defthm literal-listp-remove-literal
  (implies (literal-listp x)
           (literal-listp (remove-literal a x))))

(defthm literal-listp-negate-clause-or-assignment
  (implies (literal-listp x)
           (literal-listp (negate-clause-or-assignment x))))

(defthm unique-literalsp-remove-literal
  (implies (unique-literalsp x)
           (unique-literalsp (remove-literal a x))))

(defthm member-equal-negate-clause-or-assignment
  (implies (literalp x1)
           (iff (member-equal x1
                              (negate-clause-or-assignment x2))
                (member-equal (negate x1) x2))))

(defthm member-equal-union-equal
  (iff (member-equal a (union-equal x y))
       (or (member-equal a x)
           (member-equal a y))))

(defthm unique-literalsp-union-equal
  (implies (and (unique-literalsp x)
                (unique-literalsp y))
           (unique-literalsp (union-equal x y))))

(defthm unique-literalsp-negate-clause-or-assignment
  (implies (and (literal-listp x)
                (unique-literalsp x))
           (unique-literalsp (negate-clause-or-assignment x))))

(defun rat-assignment (assignment nlit clause)

; This is approximately a tail-recursive, optimized version of:

; (union$ assignment
;         (negate-clause-or-assignment
;          (remove-literal nlit clause)))

; However, if a contradiction is discovered, then we return t.

  (declare (xargs :guard
                  (and (clause-or-assignment-p assignment)
                       (literalp nlit)
                       (clause-or-assignment-p clause))
                  :guard-hints
                  (("Goal" :in-theory (enable clause-or-assignment-p)))))
  (cond ((endp clause) assignment)
        ((or (eql (car clause) nlit)
             (member (negate (car clause)) assignment))
         (rat-assignment assignment nlit (cdr clause)))
        ((member (car clause) assignment)
         t)
        (t
         (rat-assignment (cons (negate (car clause)) assignment)
                         nlit
                         (cdr clause)))))

(defthm minus-minus
  (implies (acl2-numberp x)
           (equal (- (- x)) x)))

(defthm clause-or-assignment-p-rat-assignment
  (implies (and (clause-or-assignment-p assignment)
                (clause-or-assignment-p clause)
                (not (equal (rat-assignment assignment nlit clause)
                            t)))
           (clause-or-assignment-p
            (rat-assignment assignment nlit clause)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defun RATp1 (alist formula nlit drat-hints assignment)

; We think of assignment as being the result of having extended the global
; assignment with the negation of the current proof clause (to check that that
; clause is redundant with respect to formula).

  (declare (xargs :guard (and (formula-fal-p alist)
                              (formula-p formula)
                              (literalp nlit)
                              (drat-hint-listp drat-hints)
                              (clause-or-assignment-p assignment))
                  :verify-guards nil
                  :guard-hints
                  (("Goal" :in-theory (enable clause-or-assignment-p)))))
  (if (endp alist)
      t
    (let* ((index (caar alist))
           (clause (cdar alist)))
      (cond
       ((deleted-clause-p clause)
        (RATp1 (cdr alist) formula nlit drat-hints assignment))
       ((eql index (caar drat-hints)) ; perform RAT
        (let ((new-assignment (rat-assignment assignment nlit clause)))
          (if (eq new-assignment t)
              (RATp1 (cdr alist) formula nlit (cdr drat-hints) assignment)
            (and (eq t
                     (unit-propagation formula
                                       (cdar drat-hints)
                                       new-assignment))
                 (RATp1 (cdr alist) formula nlit (cdr drat-hints)
                        assignment)))))
       ((or (not (member nlit clause))
            (deleted-clause-p (cdr (my-hons-get index
                                                (formula-fal formula)))))
        (RATp1 (cdr alist) formula nlit drat-hints assignment))
       (t ; !! RATP can give a better error message using proof index
        (er hard? 'ratp1 ; semantically, nil
            "Index ~x0 required a RAT check for literal ~x1 of clause ~x2 but ~
             wasn't given as a hint."
            index (negate nlit) clause))))))

; Start proof of (verify-guards RATp1).

(defthm not-conflicting-literalsp-negate-clause-or-assignment
  (implies (and (literal-listp x)
                (not (conflicting-literalsp x)))
           (not (conflicting-literalsp (negate-clause-or-assignment x)))))

(defthm clause-or-assignment-p-negate-clause-or-assignment
  (implies (clause-or-assignment-p x)
           (clause-or-assignment-p (negate-clause-or-assignment x)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defthm clause-or-assignment-p-union-equal
  (implies (and (clause-or-assignment-p x)
                (clause-or-assignment-p y)
                (not (conflicting-literalsp (union-equal x y))))
           (clause-or-assignment-p (union-equal x y)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defthm clause-or-assignment-p-unit-propagation
  (implies (and (formula-p formula)
                (clause-or-assignment-p x)
                (not (equal (unit-propagation formula indices x) t)))
           (clause-or-assignment-p (unit-propagation formula indices x)))
  :hints (("Goal" :in-theory (enable clause-or-assignment-p))))

(defthm true-listp-lookup-formula-index
  (implies (formula-fal-p x)
           (or (true-listp (cdr (hons-assoc-equal index x)))
               (equal (cdr (hons-assoc-equal index x)) 0)))
  :rule-classes :type-prescription)

(verify-guards RATp1)

(defun RATp (formula literal drat-hints assignment)
  (declare (xargs :guard (and (formula-p formula)
                              (literalp literal)
                              (drat-hint-listp drat-hints)
                              (clause-or-assignment-p assignment))))
  (RATp1 (formula-fal formula) formula (negate literal) drat-hints assignment))

(defun remove-deleted-clauses (fal acc)
  (declare (xargs :guard (alistp fal)))
  (cond ((endp fal) (make-fast-alist acc))
        (t (remove-deleted-clauses (cdr fal)
                                   (if (deleted-clause-p (cdar fal))
                                       acc
                                     (cons (car fal) acc))))))

(defthm formula-fal-p-forward-to-alistp
  (implies (formula-fal-p x)
           (alistp x))
  :rule-classes :forward-chaining)

(defthm alistp-fast-alist-fork
  (implies (and (alistp x)
                (alistp y))
           (alistp (fast-alist-fork x y))))

(local
 (defthm cdr-last-of-alistp
   (implies (alistp x)
            (equal (cdr (last x))
                   nil))))

(defund shrink-formula-fal (fal)
  (declare (xargs :guard (formula-fal-p fal)))
  (let ((fal2 (fast-alist-clean fal)))
    (fast-alist-free-on-exit fal2 (remove-deleted-clauses fal2 nil))))

(defun maybe-shrink-formula (ncls ndel formula factor)
  (declare (xargs :guard (and (integerp ncls) ; really natp; see verify-clause
                              (natp ndel)
                              (formula-p formula)
                              (rationalp factor))))
  (cond ((> ndel (* factor ncls))
         (let ((fal (shrink-formula-fal (formula-fal formula))))
           #+skip ; This is a nice check but we don't want to pay the price.
           (assert$ (or (eql ncls (fast-alist-len fal))
                        (cw "ERROR: ncls = ~x0, (fast-alist-len fal) = ~x1"
                            ncls (fast-alist-len fal)))
                    (mv ncls 0 (make-formula fal)))
           (mv ncls 0 (make-formula fal))))
        (t (mv ncls ndel formula))))

(defthm formula-fal-p-remove-deleted-clauses
  (implies (and (formula-fal-p fal1)
                (formula-fal-p fal2))
           (formula-fal-p (remove-deleted-clauses fal1 fal2))))

(defthm formula-fal-p-fast-alist-fork
  (implies (and (formula-fal-p fal1)
                (formula-fal-p fal2))
           (formula-fal-p (fast-alist-fork fal1 fal2))))

(defthm formula-fal-max-remove-deleted-clauses
  (implies (formula-fal-p fal1)
           (equal (formula-fal-max (remove-deleted-clauses fal1 fal2))
                  (max (formula-fal-max fal1)
                       (formula-fal-max fal2)))))

; Start proof of formula-fal-max-fast-alist-fork.

(defthm formula-fal-max-fast-alist-fork-1
  (implies (and (hons-assoc-equal k fal)
                (formula-fal-p fal)
                (clause-or-assignment-p (cdr (hons-assoc-equal k fal))))
           (>= (formula-fal-max fal)
               k))
  :rule-classes :linear)

(defthm formula-fal-max-fast-alist-fork
  (implies (and (formula-fal-p fal1)
                (formula-fal-p fal2))
           (<= (formula-fal-max (fast-alist-fork fal1 fal2))
               (max (formula-fal-max fal1)
                    (formula-fal-max fal2))))
  :rule-classes :linear)

(defthm natp-formula-fal-max
  (implies (force (formula-fal-p fal))
           (natp (formula-fal-max fal)))
  :rule-classes :type-prescription)

(defthm formula-fal-max-fast-alist-fork-nil
  (implies (formula-fal-p fal1)
           (<= (formula-fal-max (fast-alist-fork fal1 nil))
               (formula-fal-max fal1)))
  :hints (("Goal" :use ((:instance formula-fal-max-fast-alist-fork
                                   (fal2 nil)))))
  :rule-classes :linear)

(defthm formula-fal-p-shrink-formula-fal
  (implies (formula-fal-p fal)
           (formula-fal-p (shrink-formula-fal fal)))
  :hints (("Goal" :in-theory (enable shrink-formula-fal))))

(defun verify-clause (formula proof-clause rup-indices drat-hints ncls ndel)
  (declare (xargs
            :guard (and (formula-p formula)
                        (clause-or-assignment-p proof-clause)
                        (index-listp rup-indices)
                        (drat-hint-listp drat-hints)
                        (integerp ncls) ; really natp; see verify-proof-rec
                        (natp ndel))
            :guard-hints
            (("Goal" :in-theory (enable clause-or-assignment-p)))))
  (let* ((assignment (negate-clause-or-assignment proof-clause))
         (assignment (unit-propagation formula rup-indices assignment)))
    (cond
     ((eq assignment t)
      (maybe-shrink-formula ncls ndel formula
; shrink when ndel > 10 * ncls; factor can be changed
                            10))
     ((consp proof-clause)
      (mv-let
        (ncls ndel formula)
        (maybe-shrink-formula ncls ndel formula
; shrink when ndel > 1/3 * ncls; factor can be changed
                              1/3)
        (cond
         ((RATp formula (car proof-clause) drat-hints assignment)
          (mv ncls ndel formula))
         (t (mv nil nil nil)))))
     (t (mv nil nil nil)))))

(defun delete-clauses-fal (index-list fal)
  (declare (xargs :guard (index-listp index-list)))
  (cond ((endp index-list) fal)
        (t (delete-clauses-fal
            (cdr index-list)
            (hons-acons (car index-list) *deleted-clause* fal)))))

(defun delete-clauses (index-list formula)
  (declare (xargs :guard (and (index-listp index-list)
                              (formula-p formula))))
  (make-formula (delete-clauses-fal index-list (formula-fal formula))))

(defun add-proof-clause (index clause formula)
  (declare (xargs :guard (and (posp index)
                              (formula-p formula))))
  (make-formula (hons-acons index clause (formula-fal formula))))

(defun verify-proof-rec (ncls ndel formula proof)
  (declare (xargs :guard (and (integerp ncls) ; really natp; see comment below
                              (natp ndel)
                              (formula-p formula)
                              (proofp proof))))
  (cond
   ((atom proof) t)
   (t
    (let* ((entry (car proof))
           (delete-flg (proof-entry-deletion-p entry)))
      (cond
       (delete-flg
        (let* ((indices (proof-entry-deletion-indices entry))
               (new-formula (delete-clauses indices formula))
               (len (length indices))
               (ncls

; We expect that (<= len ncls).  It is tempting to assert that here (with
; assert$), but it's not necessary so we avoid the overhead (mostly in proof,
; but perhaps also a bit in execution).

                              (- ncls len))
               (ndel (+ ndel len)))
          (verify-proof-rec ncls ndel new-formula (cdr proof))))
       (t ; addition
        (let ((clause (access add-step entry :clause))
              (indices (access add-step entry :rup-indices))
              (drat-hints (access add-step entry :drat-hints)))
          (mv-let (ncls ndel new-formula)
            (verify-clause formula clause indices drat-hints ncls ndel)
            (and ncls ; success
                 (let ((index (access add-step entry :index)))
                   (verify-proof-rec
                    (1+ ncls)
                    ndel
                    (add-proof-clause index clause new-formula)
                    (cdr proof))))))))))))

(defun verify-proof (formula proof)
  (declare (xargs :guard (and (formula-p formula)
                              (proofp proof))))
  (verify-proof-rec (fast-alist-len (formula-fal formula))
                    0
                    formula
                    proof))

(defun proof-contradiction-p (proof)
  (declare (xargs :guard (proofp proof)))
  (if (endp proof)
      nil
    (or (let ((entry (car proof)))
          (and (not (proof-entry-deletion-p entry)) ; addition
               (null (access add-step entry :clause))))
        (proof-contradiction-p (cdr proof)))))

(defun valid-proofp (formula proof incomplete-okp)
  (declare (xargs :guard (formula-p formula)))
  (and (proofp proof)
       (or incomplete-okp
           (proof-contradiction-p proof))
       (verify-proof formula proof)))

; The functions defined below are only relevant to the correctness statement.

(defun refutation-p (proof formula)
  (declare (xargs :guard (formula-p formula)))
  (and (valid-proofp formula proof nil)
       (proof-contradiction-p proof)))

(defun-sk formula-truep (formula assignment)
  (forall index
          (let ((pair (hons-get index formula)))
            (implies (and pair
                          (not (equal (cdr pair) *deleted-clause*)))
                     (equal (evaluate-clause (cdr pair) assignment)
                            t)))))

(defun solution-p (assignment formula)
  (and (clause-or-assignment-p assignment)
       (formula-truep formula assignment)))

(defun-sk satisfiable (formula)
  (exists assignment (solution-p assignment formula)))

(in-theory (disable maybe-shrink-formula formula-truep satisfiable))

; Goal:
#||
(defthm main-theorem
  (implies (and (formula-p formula)
                (refutation-p proof formula))
           (not (satisfiable formula))))
||#
