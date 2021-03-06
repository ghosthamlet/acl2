; APT Domain Restriction Transformation -- Reference Documentation
;
; Copyright (C) 2017 Kestrel Institute (http://www.kestrel.edu)
;
; License: A 3-clause BSD license. See the LICENSE file distributed with ACL2.
;
; Author: Alessandro Coglio (coglio@kestrel.edu)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "APT")

(include-book "xdoc/top" :dir :system)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defxdoc restrict

  :parents (reference)

  :short "Domain restriction transformation:
          restrict the effective domain of a function."

  :long

  "<h3>
   Introduction
   </h3>

   <p>
   Even though functions are total in ACL2
   (i.e. their domain is always the whole ACL2 universe of values),
   the guard of a function can be regarded as its effective domain
   (i.e. where it is well-defined).
   This transformation adds restrictions to the guard,
   and wraps the body with a test for the restrictions,
   which may enable further optimizations
   by taking advantage of the added restrictions.
   </p>

   <h3>
   Form
   </h3>

   @({
     (restrict old
               restriction
               &key
               :new-name        ; default :auto
               :new-enable      ; default :auto
               :thm-name        ; default :arrow
               :thm-enable      ; default t
               :non-executable  ; default :auto
               :verify-guards   ; default :auto
               :hints           ; default nil
               :verbose         ; default nil
               :show-only       ; default nil
       )
   })

   <h3>
   Inputs
   </h3>

   <p>
   @('old')
   </p>

     <blockquote>

     <p>
     Denotes the target function to transform.
     </p>

     <p>
     It must be the name of a function,
     or a <see topic='@(url acl2::numbered-names)'>numbered name</see>
     with a wildcard index that
     <see topic='@(url resolve-numbered-name-wildcard)'>resolves</see>
     to the name of a function.
     In the rest of this documentation page, for expository convenience,
     it is assumed that @('old') is the name of the denoted function.
     </p>

     <p>
     @('old') must
     be in logic mode,
     be defined,
     have at least one formal argument,
     return a non-<see topic='@(url mv)'>multiple</see> value, and
     have no input or output @(see acl2::stobj)s.
     If @('old') is recursive, it must
     be singly (not mutually) recursive,
     not have a @(':?') measure (see @(':measure') in @(tsee xargs)), and
     not occur in its own <see topic='@(url tthm)'>termination theorem</see>
     (i.e. not occur in the tests and arguments of its own recursive calls).
     If the @(':verify-guards') input is @('t'),
     @('old') must be guard-verified.
     </p>

     <p>
     In the rest of this documentation page:
     </p>

     <ul>

       <li>
       Let @('x1'), ..., @('xn') be the formal arguments of @('old'),
       where @('n') &gt; 0.
       </li>

       <li>
       Let @('old-guard<x1,...,xn>') be the guard term of @('old').
       </li>

       <li>
       If @('old') is not recursive, let
       @({
         old-body<x1,...,xn>
       })
       be the body of @('old').
       </li>

       <li>
       If @('old') is recursive, let
       @({
         old-body<x1,...,xn,
                  (old update1-x1<x1,...,xn>
                       ...
                       update1-xn<x1,...,xn>)
                  ...
                  (old updatem-x1<x1,...,xn>
                       ...
                       updatem-xn<x1,...,xn>)>
       })
       be the body of @('old'),
       where @('m') &gt; 0 is the number of recursive calls
       in the body of @('old')
       and each @('updatej-xi<x1,...,xn>') is
       the @('i')-th actual argument passed to the @('j')-th recursive call.
       Furthermore,
       let @('contextj<x1,...,xn>') be the context (i.e. controlling tests)
       in which the @('j')-th recursive call occurs.
       </li>

     </ul>

     </blockquote>

   <p>
   @('restriction')
   </p>

     <blockquote>

     <p>
     Denotes the restricting predicate for the domain of @('old'),
     i.e. the predicate that will be added to the guard
     and as the test that wraps the body.
     </p>

     <p>
     It must be a term
     that includes no free variables other than @('x1'), ..., @('xn'),
     that only calls logic-mode functions,
     that returns a non-<see topic='@(url mv)'>multiple</see> value,
     and that has no output @(see acl2::stobj)s.
     If the generated function is guard-verified
     (which is determined by the @(':verify-guards') input; see below),
     then the term must only call guard-verified functions,
     except possibly in the @(':logic') subterms of @(tsee mbe)s.
     </p>

     <p>
     The term denotes the predicate @('(lambda (x1 ... xn) restriction)').
     </p>

     <p>
     In order to highlight the dependence on @('x1'), ..., @('xn'),
     in the rest of this documentation page,
     @('restriction<x1,...,xn>') is used for @('restriction').
     </p>

     </blockquote>

   <p>
   @(':new-name') &mdash; default @(':auto')
   </p>

     <blockquote>

     <p>
     Determines the name of the generated new function:
     </p>

     <ul>

       <li>
       @(':auto'),
       to use the <see topic='@(url acl2::numbered-names)'>numbered name</see>
       obtained by <see topic='@(url next-numbered-name)'>incrementing</see>
       the index of @('old').
       </li>

       <li>
       Any other symbol
       (that is not in the main Lisp package and that is not a keyword),
       to use as the name of the function.
       </li>

     </ul>

     <p>
     In the rest of this documentation page, let @('new') be this function.
     </p>

     </blockquote>

   <p>
   @(':new-enable') &mdash; default @(':auto')
   </p>

     <blockquote>

     <p>
     Determines whether @('new') is enabled:
     </p>

     <ul>

       <li>
       @('t'), to enable it.
       </li>

       <li>
       @('nil'), to disable it.
       </li>

       <li>
       @(':auto'), to enable it iff @('old') is enabled.
       </li>

     </ul>

     </blockquote>

   <p>
   @(':thm-name') &mdash; default @(':arrow')
   </p>

     <blockquote>

     <p>
     Determines the name of the theorem that relates @('old') to @('new'):
     </p>

     <ul>

       <li>
       @(':arrow'),
       to use the concatenation of
       the name of @('old'),
       @('-~>-'),
       and the name of @('new').
       </li>

       <li>
       @(':becomes'),
       to use the concatenation of
       the name of @('old'),
       @('-becomes-'),
       and the name of @('new').
       </li>

       <li>
       @(':is'),
       to use the concatenation of
       the name of @('old'),
       @('-is-'),
       and the name of @('new').
       </li>

       <li>
       Any other symbol
       (that is not in the main Lisp package and that is not a keyword),
       to use as the name of the theorem.
       </li>

     </ul>

     <p>
     In the rest of this documentation page,
     let @('old-to-new') be this theorem.
     </p>

     </blockquote>

   <p>
   @(':thm-enable') &mdash; default @('t')
   </p>

     <blockquote>

     <p>
     Determines whether @('old-to-new') is enabled:
     </p>

     <ul>

       <li>
       @('t'), to enable it.
       </li>

       <li>
       @('nil'), to disable it.
       </li>

     </ul>

     </blockquote>

   <p>
   @(':non-executable') &mdash; default @(':auto')
   </p>

     <blockquote>

     <p>
     Determines whether @('new') is @(see acl2::non-executable):
     </p>

     <ul>

       <li>
       @('t'), to make it non-executable.
       </li>

       <li>
       @('nil'), to not make it non-executable.
       </li>

       <li>
       @(':auto'), to make it non-executable iff @('old') is non-executable.
       </li>

     </ul>

     </blockquote>

   <p>
   @(':verify-guards') &mdash; default @(':auto')
   </p>

     <blockquote>

     <p>
     Determines whether @('new') is guard-verified:
     </p>

     <ul>

       <li>
       @('t'), to guard-verify it.
       </li>

       <li>
       @('nil'), to not guard-verify it.
       </li>

       <li>
       @(':auto'), to guard-verify it iff @('old') is guard-verified.
       </li>

     </ul>

     </blockquote>

   <p>
   @(':hints') &mdash; default @('nil')
   </p>

     <blockquote>

     <p>
     Hints to prove the applicability conditions below.
     </p>

     <p>
     It must be a list of doublets
     @('((appcond1 hints1) ... (appcondp hintsp))')
     where each @('appcondk') is a symbol (in any package)
     that names one of the applicability conditions below,
     and each @('hintsk') consists of hints as may appear
     just after @(':hints') in a @(tsee defthm).
     The hints @('hintsk') are used
     to prove applicability condition @('appcondk').
     </p>

     <p>
     The @('appcond1'), ..., @('appcondp') names must be all distinct.
     </p>

     <p>
     An @('appcondk') is allowed in the @(':hints') input iff
     the named applicability condition is present, as specified below.
     </p>

     </blockquote>

   <p>
   @(':verbose') &mdash; default @('nil')
   </p>

     <blockquote>

     <p>
     Controls the amount of screen output:
     </p>

     <ul>

       <li>
       @('t'), to show all the output.
       </li>

       <li>
       @('nil'), to suppress all the non-error output.
       </li>

     </ul>

     </blockquote>

   <p>
   @(':show-only') &mdash; default @('nil')
   </p>

     <blockquote>

     <p>
     Determines whether the events generated by the transformation
     should be submitted or only shown on the screen:
     </p>

     <ul>

       <li>
       @('nil'), to submit the events.
       </li>

       <li>
       @('t'), to only show the events.
       </li>

     </ul>

     </blockquote>

   <h3>
   Applicability Conditions
   </h3>

   <p>
   The following conditions must be provable
   in order for the transformation to apply.
   </p>

   <p>
   @('restriction-of-rec-calls')
   </p>

     <blockquote>

     <p>
     @('(lambda (x1 ... xn) restriction<x1,...,xn>)')
     is preserved across the recursive calls of @('old'):
     </p>

     @({
       (implies restriction<x1,...,xn>
                (and (implies context1<x1,...,xn>
                              restriction<update1-x1<x1,...,xn>,
                                          ...,
                                          update1-xn<x1,...,xn>>)
                     ...
                     (implies contextm<x1,...,xn>
                              restriction<updatem-x1<x1,...,xn>,
                                          ...,
                                          updatem-xn<x1,...,xn>>)))
     })

     <p>
     This applicability condition is present iff @('old') is recursive.
     </p>

     </blockquote>

   <p>
   @('restriction-guard')
   </p>

     <blockquote>

     <p>
     The restricting predicate is well-defined (according to its guard)
     on every value in the guard of @('old'):
     </p>

     @({
       (implies old-guard<x1,...,xn>
                restriction-guard<x1,...,xn>)
     })

     <p>
     where @('restriction-guard<x1,...,xn>') is
     the guard obligation of @('restriction<x1,...,xn>').
     </p>

     <p>
     This applicability condition is present iff
     the generated function is guard-verified
     (which is determined by the @(':verify-guards') input; see above).
     </p>

     </blockquote>

   <h3>
   Generated Function and Theorem
   </h3>

   <p>
   @('new')
   </p>

     <blockquote>

     <p>
     Domain-restricted version of @('old'):
     </p>

     @({
       ;; when old is not recursive:
       (defun new (x1 ... xn)
         (if restriction<x1,...,xn>
             old-body<x1,...,xn>
           :undefined))

       ;; when old is recursive:
       (defun new (x1 ... xn)
         (if restriction<x1,...,xn>
             old-body<x1,...,xn,
                      (new update1-x1<x1,...,xn>
                           ...
                           update1-xn<x1,...,xn>)
                      ...
                      (new updatem-x1<x1,...,xn>
                           ...
                           updatem-xn<x1,...,xn>)>
           :undefined))
     })

     <p>
     If @('old') is recursive,
     the measure term and well-founded relation of @('new')
     are the same as @('old').
     </p>

     <p>
     The guard is @('(and old-guard<x1,...,xn> restriction<x1,...,xn>)'),
     where @('old-guard<x1,...,xn>') is the guard term of @('old').
     </p>

     </blockquote>

   <p>
   @('old-to-new')
   </p>

     <blockquote>

     <p>
     Theorem that relates @('old') to @('new'):
     </p>

     @({
       (defthm old-to-new
         (implies restriction<x1,...,xn>
                  (equal (old x1 ... xn)
                         (new x1 ... xn))))
     })

     </blockquote>")
