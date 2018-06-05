;;; large structure tests

(require libc.scm)
(load "s7test-block.so" (sublet (curlet) (cons 'init_func 'block_init)))

(set! (*s7* 'max-vector-length) (ash 1 33))
(set! (*s7* 'max-string-length) (ash 1 33))

(define bold-text (format #f "~C[1m" #\escape))
(define unbold-text (format #f "~C[22m" #\escape))  

(define-macro (test a b)
  (format *stderr* "~S~%" a)
  `(if (not (equal? ,a ,b))
       (format *stderr* "    ~A~S -> ~S?~A~%" bold-text ',a ,a unbold-text)))

(define (clear-and-gc)
  (do ((x 0.0) (i 0 (+ i 1))) ((= i 256)) (set! x (complex i i))) ; clear temps
  (gc) (gc))

(define total-memory (with-let *libc* (* (sysconf _SC_PHYS_PAGES) (sysconf _SC_PAGESIZE)))) ; not quite what we want, but...
;; there's no point in overallocating and looking for malloc->null -- malloc doesn't work that way in Linux

(define big-size 2500000000)
(define fft-size (ash 1 16))
(define little-size 1000000)


;; --------------------------------------------------------------------------------
(format () "strings...~%")

(when (> total-memory (* 2 big-size))
  (clear-and-gc)
  (let ((bigstr (make-string big-size #\space)))
    (define (big-string-filler)
      (do ((i 0 (+ i 1)))
	  ((= i big-size))
	(string-set! bigstr i #\null)))
    (test (length bigstr) big-size)
    (string-set! bigstr (- big-size 10000000) #\a)
    (test (string-ref bigstr (- big-size 10000000)) #\a)
    (reverse! bigstr)
    (test (string-ref bigstr (- 10000000 1)) #\a)
    (fill! bigstr #\b)
    (test (string-ref bigstr (- big-size 10000000)) #\b)
    (test (char-position #\a bigstr) #f)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (string-set! bigstr i #\c))
    (test (string-ref bigstr (ash 1 31)) #\c)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (set! (bigstr i) #\d))
    (test (bigstr (ash 1 31)) #\d)
    (let-temporarily (((*s7* 'print-length) 100))
      (let ((big1 (copy bigstr)))
	(test (equal? big1 bigstr) #t)
	(test (string=? big1 bigstr) #t)
	(test (string>? big1 bigstr) #f)
	;(test (string-ci<=? big1 bigstr) #t)
	(test (morally-equal? big1 bigstr) #t)
	(set! (big1 (- big-size 1)) #\f)
	(test (equal? big1 bigstr) #f)
	(test (string=? big1 bigstr) #f)
	(test (morally-equal? big1 bigstr) #f)
	(let ((big2 (substring big1 (- (ash 1 31) 10) (+ (ash 1 31) 10))))
	  (test big2 "dddddddddddddddddddd")
	  (test (length big2) 20)
	  (let ((big3 (make-string 20 #\null)))
	    (copy bigstr big3 (- (ash 1 31) 10) (+ (ash 1 31) 10))
	    (test (string=? big2 big3) #t)))))
    (let ((bstr (string-upcase bigstr)))
      (test (string-ref bstr 0) #\B)
      (test (string-ref bstr (- (ash 1 31) 1)) #\D)
      (test (string-position "DDDD" bstr) (- (ash 1 31) 10)))
    (let ((p (call-with-output-string 
	       (lambda (p)
		 (write-string bigstr p (- (ash 1 31) 10) (+ (ash 1 31) 10))))))
      (test (length p) 20)
      (test p "dddddddddddddddddddd"))
    (big-string-filler)
    (let ((bv (string->byte-vector bigstr)))
      (test (byte-vector? bv) #t)
      (test (length bv) (length bigstr))
      (test (byte-vector-ref bv (- (ash 1 31) 100)) (char->integer (string-ref bigstr (- (ash 1 31) 100))))))

  (clear-and-gc)
  (let ((size little-size))
    (let ((vs (make-vector size)))
      (define (string-sorter)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (vector-set! vs i (make-string (+ 1 (random 200)) (integer->char (random 256))))))
      (string-sorter)
      (sort! vs string<?)
      (define (string-checker)
	(do ((i 1 (+ i 1))
	     (j 0 (+ j 1)))
	    ((= i size))
	  (if (string>? (vector-ref vs j) (vector-ref vs i))
	      (display "oops"))))
      (string-checker)))

  (clear-and-gc)
  (let ((size little-size))
    (let ((str (make-string size)))
      (define (string-filler)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (string-set! str i #\a)))
      (string-filler)
      (let ((str1 (make-string size)))
	(define (string-writer)
	  (do ((i 0 (+ i 1))
	       (j (integer->char (random 256)) (integer->char (random 256))))
	      ((= i size))
	  (string-set! str i (string-ref (make-string (+ 1 (random 200)) j) 0))
	  (string-set! str1 i j)))
	(string-writer)
	(test (string=? str str1) #t))))
      
  (clear-and-gc)
  (let ((bigstr (make-string (* 2 big-size) #\space)))
    (test (length bigstr) (* 2 big-size))
    (string-set! bigstr (- big-size 10000000) #\a)
    (test (string-ref bigstr (- big-size 10000000)) #\a)
    (do ((i (- (ash 1 32) 10) (+ i 1)))
	((= i (+ (ash 1 32) 10)))
      (string-set! bigstr i #\e))
    (test (string-ref bigstr (ash 1 32)) #\e)))

(when (> total-memory (* 4 big-size))
  (clear-and-gc)
  (let ((bigstr1 (make-string big-size #\+))
	(bigstr2 (make-string big-size #\-)))
    (let ((bigstr3 (append bigstr1 bigstr2)))
      (test (length bigstr3) (* 2 big-size))
      (test (string-ref bigstr3 (- big-size 1)) #\+)
      (test (string-ref bigstr3 (+ big-size 1)) #\-)
      (test (char-position #\- bigstr3) big-size))))
(clear-and-gc)


;; --------------------------------------------------------------------------------
(format () "~%byte-vectors...~%")

(when (> total-memory (* 4 big-size))
  (let ((bigstr (make-byte-vector big-size 32)))
    (test (length bigstr) big-size)
    (byte-vector-set! bigstr (- big-size 10000000) 65)
    (test (byte-vector-ref bigstr (- big-size 10000000)) 65)
    (reverse! bigstr)
    (test (byte-vector-ref bigstr (- 10000000 1)) 65)
    (fill! bigstr 66)
    (test (byte-vector-ref bigstr (- big-size 10000000)) 66))

  (clear-and-gc)
  (let ((size little-size))
    (let ((vs (make-byte-vector size)))
      (define (byte-vector-sorter)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (byte-vector-set! vs i (random 256))))
      (byte-vector-sorter)
      (sort! vs <)
      (define (byte-vector-checker)
	(do ((i 1 (+ i 1))
	     (j 0 (+ j 1)))
	    ((= i size))
	  (if (> (byte-vector-ref vs j) (byte-vector-ref vs i))
	      (display "oops"))))
      (byte-vector-checker)))

  (clear-and-gc)
  (let ((size little-size))
    (let ((str (make-byte-vector size)))
      (define (byte-vector-filler)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (byte-vector-set! str i 65)))
      (byte-vector-filler)
      (let ((str1 (make-byte-vector size)))
	(define (byte-vector-writer)
	  (do ((i 0 (+ i 1))
	       (j (random 256) (random 256)))
	      ((= i size))
	  (byte-vector-set! str i (byte-vector-ref (make-byte-vector (+ 1 (random 200)) j) 0))
	  (byte-vector-set! str1 i j)))
	(byte-vector-writer)
	(test (equal? str str1) #t)))))


;; --------------------------------------------------------------------------------
(format () "~%float-vectors...~%")

(when (> total-memory (* 18 big-size))
  (format () "test 1~%")
  (clear-and-gc)
  (let ((bigfv (make-float-vector big-size 0.5)))
    (let-temporarily (((*s7* 'print-length) 100))
      (let ((big1 (copy bigfv)))
	(test (morally-equal? big1 bigfv) #t)
	(set! (big1 (- big-size 1)) 0.25)
	(test (morally-equal? big1 bigfv) #f)
	(let ((big2 (make-shared-vector big1 (list 20) (- (ash 1 31) 10))))
	  (test big2 (make-float-vector 20 0.5))
	  (test (length big2) 20)
	  (let ((big3 (make-float-vector 20 0.0)))
	    (copy bigfv big3 (- (ash 1 31) 10) (+ (ash 1 31) 10))
	    (test (morally-equal? big2 big3) #t)))))
    (define (big-float-vector-filler)
      (do ((i 0 (+ i 1)))
	  ((= i big-size))
	(float-vector-set! bigfv i 1.0)))
    (big-float-vector-filler)
    (test (bigfv 1) 1.0)))

(when (> total-memory (* 16 little-size))
  (format () "test 2~%")
  (clear-and-gc)
  (let ((size little-size))
    (let ((vs (make-float-vector size)))
      (define (float-vector-sorter)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (float-vector-set! vs i (float-vector-ref (make-float-vector (+ 1 (random 200)) (random 100.0)) 0))))
      (float-vector-sorter)
      (sort! vs <)
      (define (float-vector-checker)
	(do ((i 1 (+ i 1))
	     (j 0 (+ j 1)))
	    ((= i size))
	  (if (> (vector-ref vs j) (vector-ref vs i))
	      (display "oops"))))
      (float-vector-checker)))

  (clear-and-gc)
  (let ((size little-size))
    (let ((str (make-float-vector size)))
      (define (float-vector-filler)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (float-vector-set! str i 5.0)))
      (float-vector-filler)
      (let ((str1 (make-float-vector size)))
	(define (float-vector-writer)
	  (do ((i 0 (+ i 1))
	       (j (random 100.0) (random 100.0)))
	      ((= i size))
	    (float-vector-set! str i (float-vector-ref (make-float-vector (+ 1 (random 200)) j) 0))
	    (float-vector-set! str1 i j)))
	(float-vector-writer)
	(test (morally-equal? str str1) #t)))))

(when (> total-memory (* 16 big-size))
  (format () "test 3~%")
  (clear-and-gc)
  (let ((bigfv1 (make-float-vector (/ big-size 2) 1.0))
	(bigfv2 (make-float-vector (/ big-size 2) 2.0)))
    (let ((bigfv3 (append bigfv1 bigfv2)))
      (test (length bigfv3) big-size)
      (test (float-vector-ref bigfv3 (- (/ big-size 2) 1)) 1.0)
      (test (float-vector-ref bigfv3 (+ (/ big-size 2) 1)) 2.0))))

(when (> total-memory (* 32 big-size))
  (format () "test 3a~%")
  (clear-and-gc)
  (let ((bigfv1 (make-float-vector (list 2 (/ big-size 2)) 1.0))
	(bigfv2 (make-float-vector (list 2 (/ big-size 2)) 2.0)))
    (test (float-vector-ref bigfv1 0 (- (/ big-size 2) 1)) 1.0)
    (test (float-vector-ref bigfv2 1 (- (/ big-size 2) 1)) 2.0)
    (let ((bigfv3 (append bigfv1 bigfv2)))
      (test (length bigfv3) big-size)
      (test (float-vector-ref bigfv3 (- (/ big-size 2) 1)) 1.0)
      (test (float-vector-ref bigfv3 (+ (/ big-size 2) 1)) 2.0))))

(when (> total-memory (* 9 big-size))
  (format () "test 4~%")
  (clear-and-gc)
  (let ((bigfv (make-float-vector big-size)))
    (test (length bigfv) big-size)
    (float-vector-set! bigfv (- big-size 10000000) 1.0)
    (test (float-vector-ref bigfv (- big-size 10000000)) 1.0)
    (reverse! bigfv)
    (test (float-vector-ref bigfv (- 10000000 1)) 1.0)
    (fill! bigfv 0.0)
    (test (bigfv (- big-size 10000000)) 0.0)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (float-vector-set! bigfv i 2.0))
    (test (float-vector-ref bigfv (ash 1 31)) 2.0)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (set! (bigfv i) pi))
    (test (bigfv (ash 1 31)) pi))
  (clear-and-gc)
  )

(define (float-vector-fft rl im n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (float-vector-ref rl j))
	      (tempi (float-vector-ref im j)))
	  (float-vector-set! rl j (float-vector-ref rl i))
	  (float-vector-set! im j (float-vector-ref im i))
	  (float-vector-set! rl i tempr)
	  (float-vector-set! im i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (float-vector-ref rl j)) (* wi (float-vector-ref im j))))
		  (tempi (+ (* wr (float-vector-ref im j)) (* wi (float-vector-ref rl j)))))
	      (float-vector-set! rl j (- (float-vector-ref rl i) tempr))
	      (float-vector-set! rl i (+ (float-vector-ref rl i) tempr))
	      (float-vector-set! im j (- (float-vector-ref im i) tempi))
	      (float-vector-set! im i (+ (float-vector-ref im i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (make-float-vector fft-size))
      (fvi (make-float-vector fft-size 0.0)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (float-vector-set! fvr i (sin x)))
  (float-vector-fft fvr fvi fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (float-vector-ref fvr i))
	   (vi (float-vector-ref fvi i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (float-vector-set! fvr 4 0.0)
  (float-vector-set! fvi 4 0.0)
  (float-vector-set! fvr (- fft-size 4) 0.0)
  (float-vector-set! fvi (- fft-size 4) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (float-vector-ref fvr i)) (abs (float-vector-ref fvi i))))))
(clear-and-gc)

(define (float-2d-fft vals n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (float-vector-ref vals 0 j))
	      (tempi (float-vector-ref vals 1 j)))
	  (float-vector-set! vals 0 j (float-vector-ref vals 0 i))
	  (float-vector-set! vals 1 j (float-vector-ref vals 1 i))
	  (float-vector-set! vals 0 i tempr)
	  (float-vector-set! vals 1 i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (float-vector-ref vals 0 j)) (* wi (float-vector-ref vals 1 j))))
		  (tempi (+ (* wr (float-vector-ref vals 1 j)) (* wi (float-vector-ref vals 0 j)))))
	      (float-vector-set! vals 0 j (- (float-vector-ref vals 0 i) tempr))
	      (float-vector-set! vals 0 i (+ (float-vector-ref vals 0 i) tempr))
	      (float-vector-set! vals 1 j (- (float-vector-ref vals 1 i) tempi))
	      (float-vector-set! vals 1 i (+ (float-vector-ref vals 1 i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  vals)

(let ((fvr (make-float-vector (list 2 fft-size) 0.0)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (float-vector-set! fvr 0 i (sin x)))
  (float-2d-fft fvr fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (float-vector-ref fvr 0 i))
	   (vi (float-vector-ref fvr 1 i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (float-vector-set! fvr 0 4 0.0)
  (float-vector-set! fvr 1 4 0.0)
  (float-vector-set! fvr 0 (- fft-size 4) 0.0)
  (float-vector-set! fvr 1 (- fft-size 4) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (float-vector-ref fvr 0 i)) (abs (float-vector-ref fvr 1 i))))))
(clear-and-gc)


;; --------------------------------------------------------------------------------
(format () "~%int-vectors...~%")  

(when (> total-memory (* 18 big-size))
  (format () "test 1~%")
  (clear-and-gc)
  (let ((bigfv (make-int-vector big-size 5)))
    (let-temporarily (((*s7* 'print-length) 100))
      (let ((big1 (copy bigfv)))
	(test (morally-equal? big1 bigfv) #t)
	(set! (big1 (- big-size 1)) 25)
	(test (morally-equal? big1 bigfv) #f)
	(let ((big2 (make-shared-vector big1 (list 20) (- (ash 1 31) 10))))
	  (test big2 (make-int-vector 20 5))
	  (test (length big2) 20)
	  (let ((big3 (make-int-vector 20 0)))
	    (copy bigfv big3 (- (ash 1 31) 10) (+ (ash 1 31) 10))
	    (test (morally-equal? big2 big3) #t)))))
    (define (big-int-vector-filler)
      (do ((i 0 (+ i 1)))
	  ((= i big-size))
	(int-vector-set! bigfv i 1)))
    (big-int-vector-filler)
    (test (bigfv 1) 1)))

(when (> total-memory (* 16 little-size))
  (format () "test 2~%")
  (clear-and-gc)
  (let ((size little-size))
    (let ((vs (make-int-vector size)))
      (define (int-vector-sorter)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (int-vector-set! vs i (int-vector-ref (make-int-vector (+ 1 (random 200)) (random 100)) 0))))
      (int-vector-sorter)
      (sort! vs <)
      (define (int-vector-checker)
	(do ((i 1 (+ i 1))
	     (j 0 (+ j 1)))
	    ((= i size))
	  (if (> (vector-ref vs j) (vector-ref vs i))
	      (display "oops"))))
      (int-vector-checker)))

  (clear-and-gc)
  (let ((size little-size))
    (let ((str (make-int-vector size)))
      (define (int-vector-filler)
	(do ((i 0 (+ i 1)))
	    ((= i size))
	  (int-vector-set! str i 5)))
      (int-vector-filler)
      (let ((str1 (make-int-vector size)))
	(define (int-vector-writer)
	  (do ((i 0 (+ i 1))
	       (j (random 100) (random 100)))
	      ((= i size))
	    (int-vector-set! str i (int-vector-ref (make-int-vector (+ 1 (random 200)) j) 0))
	    (int-vector-set! str1 i j)))
	(int-vector-writer)
	(test (morally-equal? str str1) #t)))))

(when (> total-memory (* 16 big-size))
  (format () "test 3~%")
  (clear-and-gc)
  (let ((bigfv1 (make-int-vector (/ big-size 2) 1))
	(bigfv2 (make-int-vector (/ big-size 2) 2)))
    (let ((bigfv3 (append bigfv1 bigfv2)))
      (test (length bigfv3) big-size)
      (test (int-vector-ref bigfv3 (- (/ big-size 2) 1)) 1)
      (test (int-vector-ref bigfv3 (+ (/ big-size 2) 1)) 2))))

(when (> total-memory (* 9 big-size))
  (format () "test 4~%")
  (clear-and-gc)
  (let ((bigfv (make-int-vector big-size)))
    (test (length bigfv) big-size)
    (int-vector-set! bigfv (- big-size 10000000) 1)
    (test (int-vector-ref bigfv (- big-size 10000000)) 1)
    (reverse! bigfv)
    (test (int-vector-ref bigfv (- 10000000 1)) 1)
    (fill! bigfv 0)
    (test (bigfv (- big-size 10000000)) 0)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (int-vector-set! bigfv i 2))
    (test (int-vector-ref bigfv (ash 1 31)) 2)
    (do ((i (- (ash 1 31) 10) (+ i 1)))
	((= i (+ (ash 1 31) 10)))
      (set! (bigfv i) 3))
    (test (bigfv (ash 1 31)) 3))
  (clear-and-gc))


(define (int-vector-fft rl im n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (int-vector-ref rl j))
	      (tempi (int-vector-ref im j)))
	  (int-vector-set! rl j (int-vector-ref rl i))
	  (int-vector-set! im j (int-vector-ref im i))
	  (int-vector-set! rl i tempr)
	  (int-vector-set! im i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (int-vector-ref rl j)) (* wi (int-vector-ref im j))))
		  (tempi (+ (* wr (int-vector-ref im j)) (* wi (int-vector-ref rl j)))))
	      (int-vector-set! rl j (round (- (int-vector-ref rl i) tempr)))
	      (int-vector-set! rl i (round (+ (int-vector-ref rl i) tempr)))
	      (int-vector-set! im j (round (- (int-vector-ref im i) tempi)))
	      (int-vector-set! im i (round (+ (int-vector-ref im i) tempi)))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (make-int-vector fft-size))
      (fvi (make-int-vector fft-size 0)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (int-vector-set! fvr i (round (* 1000 (sin x)))))
  (int-vector-fft fvr fvi fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (sqrt mx) (* 500 fft-size)) mx1-loc (/ (sqrt mx1) (* 500 fft-size))))
    (let* ((vr (int-vector-ref fvr i))
	   (vi (int-vector-ref fvi i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (int-vector-set! fvr 4 0)
  (int-vector-set! fvi 4 0)
  (int-vector-set! fvr (- fft-size 4) 0)
  (int-vector-set! fvi (- fft-size 4) 0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (int-vector-ref fvr i)) (abs (int-vector-ref fvi i))))))
(clear-and-gc)


;; --------------------------------------------------------------------------------
(format () "~%vectors...~%")
(when (> total-memory (* 9 big-size))
  (let ((bigv (make-vector big-size)))
    (test (length bigv) big-size)
    (vector-set! bigv (- big-size 10000000) 'asdf)
    (test (vector-ref bigv (- big-size 10000000)) 'asdf)
    (reverse! bigv)
    (test (vector-ref bigv (- 10000000 1)) 'asdf)
    (fill! bigv ())
    (test (vector-ref bigv (- 10000000 1)) ())
    ))
(clear-and-gc)

(when (> total-memory (* 68 big-size))
  (let ((v (make-vector big-size)))
    (do ((i 0 (+ i 1)))
	((= i big-size))
      (vector-set! v i (* 2.0 i)))
    (test (vector-ref v 100000000000) (* 2 100000000000))
    (test (vector-ref v (- big-size 10000000)) (* 2 (- big-size 10000000)))))
(clear-and-gc)

(define (vector-fft rl im n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (vector-ref rl j))
	      (tempi (vector-ref im j)))
	  (vector-set! rl j (vector-ref rl i))
	  (vector-set! im j (vector-ref im i))
	  (vector-set! rl i tempr)
	  (vector-set! im i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (vector-ref rl j)) (* wi (vector-ref im j))))
		  (tempi (+ (* wr (vector-ref im j)) (* wi (vector-ref rl j)))))
	      (vector-set! rl j (- (vector-ref rl i) tempr))
	      (vector-set! rl i (+ (vector-ref rl i) tempr))
	      (vector-set! im j (- (vector-ref im i) tempi))
	      (vector-set! im i (+ (vector-ref im i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (make-vector fft-size))
      (fvi (make-vector fft-size 0.0)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (vector-set! fvr i (sin x)))
  (vector-fft fvr fvi fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (vector-ref fvr i))
	   (vi (vector-ref fvi i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (vector-set! fvr 4 0.0)
  (vector-set! fvi 4 0.0)
  (vector-set! fvr (- fft-size 4) 0.0)
  (vector-set! fvi (- fft-size 4) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (vector-ref fvr i)) (abs (vector-ref fvi i))))))
(clear-and-gc)

(define (2d-fft vals n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (vector-ref vals 0 j))
	      (tempi (vector-ref vals 1 j)))
	  (vector-set! vals 0 j (vector-ref vals 0 i))
	  (vector-set! vals 1 j (vector-ref vals 1 i))
	  (vector-set! vals 0 i tempr)
	  (vector-set! vals 1 i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (vector-ref vals 0 j)) (* wi (vector-ref vals 1 j))))
		  (tempi (+ (* wr (vector-ref vals 1 j)) (* wi (vector-ref vals 0 j)))))
	      (vector-set! vals 0 j (- (vector-ref vals 0 i) tempr))
	      (vector-set! vals 0 i (+ (vector-ref vals 0 i) tempr))
	      (vector-set! vals 1 j (- (vector-ref vals 1 i) tempi))
	      (vector-set! vals 1 i (+ (vector-ref vals 1 i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  vals)

(let ((fvr (make-vector (list 2 fft-size) 0.0)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (vector-set! fvr 0 i (sin x)))
  (2d-fft fvr fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (vector-ref fvr 0 i))
	   (vi (vector-ref fvr 1 i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (vector-set! fvr 0 4 0.0)
  (vector-set! fvr 1 4 0.0)
  (vector-set! fvr 0 (- fft-size 4) 0.0)
  (vector-set! fvr 1 (- fft-size 4) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (vector-ref fvr 0 i)) (abs (vector-ref fvr 1 i))))))
(clear-and-gc)


;; --------------------------------------------------------------------------------
(format () "~%blocks...~%")

(when (> total-memory (* 5 big-size))
  (clear-and-gc)
  (let ((bigv (make-block big-size)))
    (test (length bigv) big-size)
    (set! (bigv (- big-size 10000000)) 1.0)
    (test (bigv (- big-size 10000000)) 1.0)
    (reverse! bigv)
    (test (bigv (- 10000000 1)) 1.0)
    (fill! bigv 0.0); (- big-size 9000000))
    (test (bigv (- big-size 10000000)) 0.0)
    ))
(clear-and-gc)

(define (block-fft rl im n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (rl j))
	      (tempi (im j)))
	  (set! (rl j) (rl i))
	  (set! (im j) (im i))
	  (set! (rl i) tempr)
	  (set! (im i) tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (rl j)) (* wi (im j))))
		  (tempi (+ (* wr (im j)) (* wi (rl j)))))
	      (set! (rl j) (- (rl i) tempr))
	      (set! (rl i) (+ (rl i) tempr))
	      (set! (im j) (- (im i) tempi))
	      (set! (im i) (+ (im i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (make-block fft-size))
      (fvi (make-block fft-size)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (set! (fvr i) (sin x)))
  (block-fft fvr fvi fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (fvr i))
	   (vi (fvi i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (set! (fvr 4) 0.0)
  (set! (fvi 4) 0.0)
  (set! (fvr (- fft-size 4)) 0.0)
  (set! (fvi (- fft-size 4)) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (fvr i)) (abs (fvi i))))))


;; --------------------------------------------------------------------------------
;; hash-tables round up to the next power of 2

(format () "~%hash-tables...~%")

(when (> total-memory (* 9 2147483648))
  (clear-and-gc)

  (set! big-size 2000000000)
  (let ((bigv (make-hash-table big-size)))
    (test (length bigv) 2147483648)
    (hash-table-set! bigv 'asdf 12)
    (test (hash-table-ref bigv 'asdf) 12)
    (hash-table-set! bigv (- big-size 10000000) 'asdf)
    (test (hash-table-ref bigv (- big-size 10000000)) 'asdf)
    )
  (clear-and-gc)
  )

(when (> total-memory (* 9 4294967296)) ; add some slack
  (let ((bigv (make-hash-table big-size)))
    (test (length bigv) 4294967296)
    (hash-table-set! bigv 'asdf 12)
    (test (hash-table-ref bigv 'asdf) 12)
    (hash-table-set! bigv (- big-size 10000000) 'asdf)
    (test (hash-table-ref bigv (- big-size 10000000)) 'asdf)
    )
  (clear-and-gc)
  )

(define (hash-table-fft rl im n dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (hash-table-ref rl j))
	      (tempi (hash-table-ref im j)))
	  (hash-table-set! rl j (hash-table-ref rl i))
	  (hash-table-set! im j (hash-table-ref im i))
	  (hash-table-set! rl i tempr)
	  (hash-table-set! im i tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (hash-table-ref rl j)) (* wi (hash-table-ref im j))))
		  (tempi (+ (* wr (hash-table-ref im j)) (* wi (hash-table-ref rl j)))))
	      (hash-table-set! rl j (- (hash-table-ref rl i) tempr))
	      (hash-table-set! rl i (+ (hash-table-ref rl i) tempr))
	      (hash-table-set! im j (- (hash-table-ref im i) tempi))
	      (hash-table-set! im i (+ (hash-table-ref im i) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (make-hash-table fft-size))
      (fvi (make-hash-table fft-size)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (hash-table-set! fvr i (sin x))
    (hash-table-set! fvi i 0.0))
  (hash-table-fft fvr fvi fft-size 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (hash-table-ref fvr i))
	   (vi (hash-table-ref fvi i))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (hash-table-set! fvr 4 0.0)
  (hash-table-set! fvi 4 0.0)
  (hash-table-set! fvr (- fft-size 4) 0.0)
  (hash-table-set! fvi (- fft-size 4) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (hash-table-ref fvr i)) (abs (hash-table-ref fvi i))))))
(clear-and-gc)

(define (hash-symbol-fft rl im n rl-syms im-syms dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (hash-table-ref rl (vector-ref rl-syms j)))
	      (tempi (hash-table-ref im (vector-ref im-syms j))))
	  (hash-table-set! rl (vector-ref rl-syms j) (hash-table-ref rl (vector-ref rl-syms i)))
	  (hash-table-set! im (vector-ref im-syms j) (hash-table-ref im (vector-ref im-syms i)))
	  (hash-table-set! rl (vector-ref rl-syms i) tempr)
	  (hash-table-set! im (vector-ref im-syms i) tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (hash-table-ref rl (vector-ref rl-syms j))) (* wi (hash-table-ref im (vector-ref im-syms j)))))
		  (tempi (+ (* wr (hash-table-ref im (vector-ref im-syms j))) (* wi (hash-table-ref rl (vector-ref rl-syms j))))))
	      (hash-table-set! rl (vector-ref rl-syms j) (- (hash-table-ref rl (vector-ref rl-syms i)) tempr))
	      (hash-table-set! rl (vector-ref rl-syms i) (+ (hash-table-ref rl (vector-ref rl-syms i)) tempr))
	      (hash-table-set! im (vector-ref im-syms j) (- (hash-table-ref im (vector-ref im-syms i)) tempi))
	      (hash-table-set! im (vector-ref im-syms i) (+ (hash-table-ref im (vector-ref im-syms i)) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(let ((fvr (hash-table))
      (fvi (hash-table))
      (rl-syms (make-vector fft-size))
      (im-syms (make-vector fft-size)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (vector-set! rl-syms i (gensym "rl"))
    (vector-set! im-syms i (gensym "im"))
    (hash-table-set! fvr (vector-ref rl-syms i) (sin x))
    (hash-table-set! fvi (vector-ref im-syms i) 0.0))
  (hash-symbol-fft fvr fvi fft-size rl-syms im-syms 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (hash-table-ref fvr (vector-ref rl-syms i)))
	   (vi (hash-table-ref fvi (vector-ref im-syms i)))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (hash-table-set! fvr (vector-ref rl-syms 4) 0.0)
  (hash-table-set! fvi (vector-ref im-syms 4) 0.0)
  (hash-table-set! fvr (vector-ref rl-syms (- fft-size 4)) 0.0)
  (hash-table-set! fvi (vector-ref im-syms (- fft-size 4)) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (hash-table-ref fvr (vector-ref rl-syms i))) (abs (hash-table-ref fvi (vector-ref im-syms i)))))))
(clear-and-gc)


;; --------------------------------------------------------------------------------

(format () "~%lets~%")

(define (let-fft rl im n rl-syms im-syms dir)
  (do ((i 0 (+ i 1))
       (j 0))
      ((= i n))
    (if (> j i)
	(let ((tempr (let-ref rl (vector-ref rl-syms j)))
	      (tempi (let-ref im (vector-ref im-syms j))))
	  (let-set! rl (vector-ref rl-syms j) (let-ref rl (vector-ref rl-syms i)))
	  (let-set! im (vector-ref im-syms j) (let-ref im (vector-ref im-syms i)))
	  (let-set! rl (vector-ref rl-syms i) tempr)
	  (let-set! im (vector-ref im-syms i) tempi)))
    (let ((m (/ n 2)))
      (do () 
	  ((or (< m 2) (< j m)))
	(set! j (- j m))
	(set! m (/ m 2)))
      (set! j (+ j m))))
  (let ((ipow (floor (log n 2)))
	(prev 1))
    (do ((lg 0 (+ lg 1))
	 (mmax 2 (* mmax 2))
	 (pow (/ n 2) (/ pow 2))
	 (theta (* pi dir) (* theta 0.5)))
	((= lg ipow))
      (let ((wpr (cos theta))
	    (wpi (sin theta))
	    (wr 1.0)
	    (wi 0.0))
	(do ((ii 0 (+ ii 1)))
	    ((= ii prev))
	  (do ((jj 0 (+ jj 1))
	       (i ii (+ i mmax))
	       (j (+ ii prev) (+ j mmax)))
	      ((>= jj pow))
	    (let ((tempr (- (* wr (let-ref rl (vector-ref rl-syms j))) (* wi (let-ref im (vector-ref im-syms j)))))
		  (tempi (+ (* wr (let-ref im (vector-ref im-syms j))) (* wi (let-ref rl (vector-ref rl-syms j))))))
	      (let-set! rl (vector-ref rl-syms j) (- (let-ref rl (vector-ref rl-syms i)) tempr))
	      (let-set! rl (vector-ref rl-syms i) (+ (let-ref rl (vector-ref rl-syms i)) tempr))
	      (let-set! im (vector-ref im-syms j) (- (let-ref im (vector-ref im-syms i)) tempi))
	      (let-set! im (vector-ref im-syms i) (+ (let-ref im (vector-ref im-syms i)) tempi))))
	  (let ((wtemp wr))
	    (set! wr (- (* wr wpr) (* wi wpi)))
	    (set! wi (+ (* wi wpr) (* wtemp wpi)))))
	(set! prev mmax))))
  rl)

(set! fft-size 2048) ; above 65536
(let ((fvr (inlet))
      (fvi (inlet))
      (rl-syms (make-vector fft-size))
      (im-syms (make-vector fft-size)))
  (do ((i 0 (+ i 1))
       (x 0.0 (+ x (/ (* 8 pi) fft-size))))
      ((= i fft-size))
    (vector-set! rl-syms i (gensym "rl-"))
    (vector-set! im-syms i (gensym "im-"))
    (varlet fvr (vector-ref rl-syms i) (sin x))
    (varlet fvi (vector-ref im-syms i) 0.0))
  (let-fft fvr fvi fft-size rl-syms im-syms 1)
  (do ((mx 0.0)
       (mxloc 0)
       (mx1 0.0)
       (mx1-loc 0)
       (i 0 (+ i 1)))
      ((= i fft-size) 
       (format () "~A ~A (~A ~A)~%" mxloc (/ (* 2 (sqrt mx)) fft-size) mx1-loc (/ (* 2 (sqrt mx1)) fft-size)))
    (let* ((vr (let-ref fvr (vector-ref rl-syms i)))
	   (vi (let-ref fvi (vector-ref im-syms i)))
	   (pk (+ (* vr vr) (* vi vi))))
      (when (> pk mx)
	(set! mx1 mx)
	(set! mx1-loc mxloc)
	(set! mx pk)
	(set! mxloc i))))
  (let-set! fvr (vector-ref rl-syms 4) 0.0)
  (let-set! fvi (vector-ref im-syms 4) 0.0)
  (let-set! fvr (vector-ref rl-syms (- fft-size 4)) 0.0)
  (let-set! fvi (vector-ref im-syms (- fft-size 4)) 0.0)
  (do ((mx 0.0)
       (i 0 (+ i 1)))
      ((= i fft-size)
       (format () "noise: ~A~%" mx))
    (set! mx (max mx (abs (let-ref fvr (vector-ref rl-syms i))) (abs (let-ref fvi (vector-ref im-syms i)))))))

(clear-and-gc)


;; 4-june: 41+27: 232.3, 40.6+27.4, 37+25
