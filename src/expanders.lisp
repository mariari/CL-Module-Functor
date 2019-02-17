(defpackage #:expanders
  (:documentation "Gives the ability to write custom expanders so that defmodules
can properly export the symbols to the right namespace")
  (:use #:cl)
  (:export #:make-handler
           #:add-handler
           #:recusively
           #:stop
           #:stop-p
           #:recursively-p
           #:get-handler))

(in-package #:expanders)

;;;; Types--------------------------------------------------------------------------------
(deftype handle ()
  "Serves as the sum type of recursively and stop. Recursively allows defmodule to continue
where the handler stops, and stop just takes where the handler stops as the full syntax"
  `(or (satisfies recursively-p)
      (satisfies stop-p)))

(defstruct recursively
  "the CHANGED field is aliased augmented syntax to up to a point,
the RESUME-AT field allows defmodule to augment the rest of the given sexp
The EXPORT fields tells defmodule what functions should be exported if no signature is given
(mimicing, no signature export all!!) and the EXPORT-LOCAL states that the bindings are local
to the sexp that is left"
  (changed      '() :type list)
  (resume-at    '() :type list)
  (export       '() :type list)
  (export-local '() :type list))

(defstruct stop
  "the CHANGED field is aliased augmented syntax of the entire sexp, defmodule will do no
extra work The EXPORT fields tells defmodule what functions should be exported if no
signature is given (mimicing, no signature export all!!)"
  (changed '() :type list)
  (export  '() :type list))

(defstruct change-params
  "holds the updated changed-set for external definitions, those symbols, so we can pass
exported data, and the updated syntax"
  syntax
  changed-set
  exports)

;;;; Global expander table----------------------------------------------------------------

;; we use equal for the test as we have to convert symbols to strings
(defvar *expander-table*
  (make-hash-table :test #'equal))

;;;; Functions for the end user to make their own handlers--------------------------------

(declaim (ftype (function (list &key (:resume-at list)
                                     (:export list)
                                     (:export-local list))
                          handle)
                make-handler))
(defun make-handler (changed &key export resume-at export-local)
  "makes a handler that either stops at the namespace changes in CHANGED, or
we can hand off this responsibility and let the system resume where you left off
and convert the rest of the syntax!"
  (if resume-at
      (make-recursively :changed      changed
                        :export       export
                        :resume-at    resume-at
                        :export-local export-local)
      (make-stop :changed changed
                 :export  export)))

;; symbol -> #1=(list -> utility:package-designator -> handle) -> #1#
(declaim
 (ftype (function (symbol #1=(function (list utility:package-designator bindle.set:fset) handle)) #1#)
        add-handler))
(defun add-handler (symbol-trigger trigger)
  "adds a module alias handler to the global table of changing handlers
the SYMBOL-TRIGGER is the symbol you wish for it to go off on. and
TRIGGER is a function which takes a syntax and package and returns a handler
the trigger function also takes a set that determines what symbols to export if need be"
  (setf (gethash (utility:intern-sym symbol-trigger 'keyword)
                 *expander-table*)
        trigger))

(defun get-handler (symbol-trigger)
  (gethash (utility:intern-sym symbol-trigger 'keyword)
           *expander-table*))

(declaim (ftype (function (list utility:package-designator bindle.set:fset) change-params)
                recursively-change))
(defun recursively-change (syntax package change-set)
  "This does the job of defmacro and recursively expands the syntax to what it should be
keeping in mind what symbols should be changed via change-set.
Returns back change-params"
  (declare (ignore syntax package change-set))
  (error "function not yet defined"))

;;;; Predefined handlers------------------------------------------------------------------
(defun cadr-handler (syntax package change-set)
  "handler that changes the cadr, but keeps the cddr the same"
  (declare (ignore change-set))
  (let ((new-cadr (utility:intern-sym (cadr syntax) package)))
    (make-handler (list (car syntax) new-cadr)
                  :export (list new-cadr)
                  :resume-at (cddr syntax))))

(add-handler 'defparameter
             #'cadr-handler)

(add-handler 'defvar
             #'cadr-handler)

;; make a local change function that updates the syntax of all symbols and adds them
;; to the locallly change

;; Don't use this implementation. Move the arguments of the defun into the namespace
;; (add-handler 'defun
;;              #'cadr-handler)

(defun defclass-handler (syntax package change-set)
  (declare (ignore change-set))
  (let* ((class-name    (utility:intern-sym (cadr syntax) package))
         (super-classes (caddr syntax))
         (slots         (cadddr syntax))
         (options       (cddddr syntax))
         (export        (list class-name)))
    (labels ((handle-slot-options (options)
               (mapcan (lambda (key-default)
                         (if (member (car key-default)
                                     (list :accessor :reader :writer)
                                     :test #'eq)
                             (let ((new-accessor (utility:intern-sym (cadr key-default) package)))
                               (push new-accessor export)
                               (list (car key-default) new-accessor))
                             key-default))
                       (utility:group 2 options))))
      (make-handler
       (list* (car syntax)
              class-name
              super-classes
              (mapcar (lambda (accessors)
                        (if (listp accessors)
                            (cons (car accessors) (handle-slot-options (cdr accessors)))
                            accessors))
                      slots)
              options)
       :export export))))

(add-handler 'defclass
             #'defclass-handler)

(defun let*-handler (syntax package change-set)
  (let* ((curr-set     change-set)
         (exports      nil)
         (export-local nil)
         (change-bindings
          (mapcar (lambda (binding-pair)
                    (push (car binding-pair) export-local)
                    (let ((changed (recursively-change (cdr binding-pair) package curr-set)))
                      (setf curr-set
                            (bindle.set:add (car binding-pair)
                                            (change-params-changed-set changed)))
                      (mapc (lambda (x) (push x exports))
                            (change-params-exports changed))
                      (cons (car (utility:intern-sym binding-pair package))
                            (change-params-syntax changed))))
                  (cadr syntax))))
        (make-handler (cons (car syntax) change-bindings)
                      :resume-at (cddr syntax)
                      :export-local export-local
                      :export exports)))
