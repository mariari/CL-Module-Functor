(defpackage #:bindle.diff-list
  (:documentation "A functional diff list using continuations. Allows O(1) append and can be
into a classic list whenever needed")
  (:use #:cl)
  (:shadowing-import-from #:cl #:member)
  (:export #:diff-list
           #:d-cons
           #:d-append
           #:d-snoc
           #:to-list
           #:+empty+
           #:of-list
           #:nof-list))

(in-package #:bindle.diff-list)

;; an empty difference list is equivalent to
;; the identity function
(defparameter empty
  (lambda (k) k))

(defstruct (diff-list
             (:print-function
              (lambda (p s k)
                (declare (ignore k))
                (format s "~A" (funcall (diff-list-cont p) '())))))
  (cont empty :type (function (t) list)))

(defparameter +empty+
  (make-diff-list :cont empty))

(defun d-cons (x d-list)
  ;; to cons a difference list we must first apply the
  ;; continuation `cont` to a valid list but we haven't
  ;; got one yet. Thus we delay the construction by
  ;; instead returning a lambda function binding `k`
  ;; which `cont` is then later applied to. This lambda
  ;; is a continuation.
  (make-diff-list
   :cont (lambda (k)
           (cons x                                       ; the scalar value to be joined
                 (funcall (diff-list-cont d-list) k))))) ; application of the continuation


;; append of two difference lists is the application
;; of the continuation `cont-x` to the result of
;; applying the continuation `cont-y` to `k`. `k` is
;; given by the lambda binding thus this is also
;; just another continuation.
(defun d-append (d-list-x d-list-y)
  (let ((cont-x (diff-list-cont d-list-x))
        (cont-y (diff-list-cont d-list-y)))
    (make-diff-list
     :cont (lambda (k)
             (funcall cont-x (funcall cont-y k))))))

(defun d-snoc (d-list x)
  ;; to add a value at the end we construct another
  ;; continuation but this time fill in before `cont`
  (let ((cont (diff-list-cont d-list)))
    (make-diff-list
     :cont (lambda (k)
             (funcall cont (cons x k))))))

(defun to-list (cont)
  (funcall (diff-list-cont cont) '()))

(defun of-list (lis)
  (nof-list (copy-list lis)))

(defun nof-list (lis)
  "Like of-list, except when we evaluate the cont, we mutate
the given list. Since this is lazy, beware this may happen at any time!!!"
  (if lis
      (make-diff-list
       :cont (lambda (k)
               (setf (cdr (last lis)) k)
               lis))
      +empty+))
