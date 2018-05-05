;; iteration tests

;(set! (*s7* 'gc-stats) 2)

;;; do/let/rec/tc/iter

(define with-blocks #f)
(when with-blocks
  (let ((new-env (sublet (curlet) (cons 'init_func 'block_init)))) ; load calls init_func if possible
    (load "s7test-block.so" new-env)))

(define-constant (find-if-a iter)
  (or (string? (iterate iter))
      (and (not (iterator-at-end? iter))
	   (find-if-a iter))))

(define-constant (find-if-b iter)
  (call-with-exit
   (lambda (return)
     (for-each (lambda (arg)
		 (if (string? arg) (return #t)))
	       iter)
     #f)))

(define-constant (find-if-c iter)
  (let loop ()
    (or (string? (iterate iter))
	(and (not (iterator-at-end? iter))
	     (loop)))))

(define-constant (find-if-d iter)
  (do ((i 0 (+ i 1)))
      ((= i 1)
       (not (iterator-at-end? iter)))
    (do ()
	((or (string? (iterate iter)) (iterator-at-end? iter))))))
       

(define (test)
  (for-each
   (lambda (size)
     (format *stderr* "~D: " size)
     (let ((a (let ((lst (make-list size #f)))
		(list (find-if-a (make-iterator lst))
		      (find-if-b (make-iterator lst))
		      (find-if-c (make-iterator lst))
		      (find-if-d (make-iterator lst)))))
	   (b (let ((str (make-string size #\space)))
		(list (find-if-a (make-iterator str))
		      (find-if-b (make-iterator str))
		      (find-if-c (make-iterator str))
		      (find-if-d (make-iterator str)))))
	   (c (let ((vc (make-vector size #f)))
		(list (find-if-a (make-iterator vc))
		      (find-if-b (make-iterator vc))
		      (find-if-c (make-iterator vc))
		      (find-if-d (make-iterator vc)))))
	   (d (let ((fv (make-float-vector size 1.0)))
		(list (find-if-a (make-iterator fv))
		      (find-if-b (make-iterator fv))
		      (find-if-c (make-iterator fv))
		      (find-if-d (make-iterator fv)))))
	   (e (let ((iv (make-int-vector size 0)))
		(list (find-if-a (make-iterator iv))
		      (find-if-b (make-iterator iv))
		      (find-if-c (make-iterator iv))
		      (find-if-d (make-iterator iv)))))
	   (f (let ((ht (let ((ht1 (make-hash-table size)))
			  (do ((i 0 (+ i 1)))
			      ((= i size) ht1)
			    (hash-table-set! ht1 i i))))
		    (p (cons #f #f)))
		(list (find-if-a (make-iterator ht p))
		      (find-if-b (make-iterator ht p))
		      (find-if-c (make-iterator ht p))
		      (find-if-d (make-iterator ht p)))))
	   (g (let ((lt (apply inlet (make-list (* 2 size) 'abc)))
		    (p (cons #f #f)))
		(list (find-if-a (make-iterator lt p))
		      (find-if-b (make-iterator lt p))
		      (find-if-c (make-iterator lt p))
		      (find-if-d (make-iterator lt p)))))
	   (h (and with-blocks
		   (let ((blk (make-block size)))
		     (list (find-if-a (make-iterator blk))
			   (find-if-b (make-iterator blk))
			   (find-if-c (make-iterator blk))
			   (find-if-d (make-iterator blk)))))))
       
       (if (not (equal? a '(#f #f #f #f))) (format *stderr* "a: ~A " a))
       (if (not (equal? b '(#f #f #f #f))) (format *stderr* "b: ~A " b))
       (if (not (equal? c '(#f #f #f #f))) (format *stderr* "c: ~A " c))
       (if (not (equal? d '(#f #f #f #f))) (format *stderr* "d: ~A " d))
       (if (not (equal? e '(#f #f #f #f))) (format *stderr* "e: ~A " e))
       (if (not (equal? f '(#f #f #f #f))) (format *stderr* "f: ~A " f))
       (if (not (equal? g '(#f #f #f #f))) (format *stderr* "g: ~A " g))
       (if (and with-blocks (not (equal? h '(#f #f #f #f)))) (format *stderr* "h: ~A " h))
       ))
   (list 1 10 100 1000 10000 100000 1000000)))

(test)

(s7-version)	
(exit)

