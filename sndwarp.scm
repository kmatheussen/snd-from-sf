;;; SNDWARP

(provide 'snd-sndwarp.scm)
(if (not (provided? 'snd-env.scm)) (load "env.scm")) ; normalize-envelope

;;;
;;; CLM 3 implementation of Richard Karpen's SNDWARP Csound Ugen.
;;; By Bret Battey. http://www.BatHatMedia.com
;;; translated to Scheme by Bill S Feb-05
;;;   changes for the optimizer 24-Oct-06
;;;
;;; Except as noted below, the parameters are modeled directly after
;;; the Csound version of sndwarp. 

;;; ISSUES
;;;
;;; Output in this new CLM version is seeming quite noisy/clipped (?)
;;; Varying stereo/mono input/output has not been tested in clm2 alterations.
;;; Hasn't been tested with differing input and output file sampling rates.
;;; Uses half-sine envelope only; doesn't support alternative windowing envs.
;;; Csound-style attack doesn't strictly match Csound results

;;; SNDWARP KEY PARAMETERS
;;;
;;; amp = Amplitude 
;;;       [number] 
;;;
;;; amp-env = Amplitude envelope 
;;;           [envelope]
;;;
;;; stretch = Stretch value or time pointer envelope (see 'time-ptr')
;;;           [number or envelope expressed in either stretch values 
;;;            (for stretch mode) or in seconds (in time-ptr mode)]
;;;
;;; srate = Resampling scalar (1 = same pitch, .5 = 1 octave lower, etc.)
;;;         A negative srate will read backwards into the soundfile from
;;;         the start of each read window (not available in Csound version).
;;;         [number or envelope]
;;;
;;; inputbeg = Source file input offset. In 'stretch' mode (see 'time-ptr'),
;;;            soundfile read will begin at inputbeg. In 'time-ptr' mode,
;;;            inputbeg will be added to the time pointer.  
;;;            [number, in seconds]
;;;
;;; wsize = Size of the sndwarp windows.
;;;         [number, in seconds]
;;;
;;; randw = Range of random values to be added to wsize
;;;         [number, in seconds]
;;;
;;; overlaps = number of window overlaps
;;;            [number per second]
;;;
;;; time-ptr = Flag to determine whether stretching or time-pointer mode
;;;            is to be used in interpreting the 'stretch' parameter.
;;;               In stretch mode, the value of 'stretch' will scale the time 
;;;            of the sound. For example, a value of 2 will stretch the sound 
;;;            by 2 times. Note that stretch values of or near 0 are not
;;;            viable since window advance times are determined by dividing
;;;            by the stretch value.
;;;               In time-ptr mode, the value(s) of stretch are readin pointers
;;;            into the soundfile. For example, to read through a file
;;;            backwards from 2 seconds at half speed, one would use a 
;;;            stretch envelope like [0 2 1 0] with a 4 second note duration.
;;;            [NIL = stretch mode, T = time-ptr mode]
;;;
;;; scale-time-ptr = Flag to determine whether the time-ptr envelope will be
;;;                  interpreted in absolute seconds or rescaled to fit the 
;;;                  duration of the input sound file.
;;;                  {not part of csound implementation}
;;;                  [NIL = absolute, T = rescale]
;;;
;;; zero-start-time-ptr = Flag to determine when in time-ptr mode whether
;;;                       the first section of windows will start at 
;;;                       time-ptr = 0.
;;;                       The csound sndwarp makes this assumption, so you
;;;                       always get a bit of the attack of the sound even
;;;                       if you try to run the time pointer starting in 
;;;                       the middle or end.
;;;                       [NIL = first section starts according to time-ptr,
;;;                        T = first section always starts at time-ptr = 0]
;;;
;;; sndwarp-window-offset = Flag to determine how the windows are offset
;;;                         in time. T = Csound sndwarp style, windows 
;;;                         in different layers line up.
;;;                         NIL = spread evenly.
;;;
;;; loc =  Stereo panning position, where 0 = left and 1 = right.
;;;        Uses simple sqrt method.
;;;        [number or envelope]
;;;
;;; rev = Scalar for reverb sending to a CLM  reverb instrument.
;;;       [number or envelope]
;;;
;;; status = Flag to control whether SNDWARP prints a window %-complete count
;;;          while working.
;;;          [NIL = no status printing, T = status printing]
;;;
;;; srcwidth = width of the sinc function used in the interpolation function of
;;;            CLM's "src" -- which provides the resampling in sndwarp. Defaults to
;;;            5. If you hear high-frequency artifacts in the output sound, try
;;;            increasing this number.
;;;      

;;; SNDWARP DEFAULTS

(define sndwarp-amp 1.0)
(define sndwarp-amp-env '(0 1 100 1))
(define sndwarp-stretch 1.0)
(define sndwarp-srate 1.0)
(define sndwarp-inputbeg 0.0)
(define sndwarp-wsize 0.1) ; csound manual recommended start = .1
(define sndwarp-randw 0.02) ; csound manual recommended start = .02
(define sndwarp-overlaps 15) ; csound manual recommended start = 15
(define sndwarp-time-ptr #f)
(define sndwarp-scale-time-ptr #f)
(define sndwarp-zero-start-time-ptr #f) ; #t to match csound
(define sndwarp-window-offset #f) ; #t to match csound
(define sndwarp-loc 0.5)
(define sndwarp-rev 0.1)
(define sndwarp-srcwidth 5)

;;; UTILITY FUNCTIONS

(define clmsw-2pi (* 2 pi))

;;; SNDWARP

(define* (sndwarp begtime dur file 
		  (amp sndwarp-amp)
		  (amp-env sndwarp-amp-env)
		  (stretch sndwarp-stretch)
		  (srate sndwarp-srate)
		  (inputbeg sndwarp-inputbeg)
		  (wsize sndwarp-wsize)
		  (randw sndwarp-randw)
		  (overlaps sndwarp-overlaps)
		  (time-ptr sndwarp-time-ptr)
		  (scale-time-ptr sndwarp-scale-time-ptr)
		  (zero-start-time-ptr sndwarp-zero-start-time-ptr)
		  (window-offset sndwarp-window-offset)
		  (loc sndwarp-loc) 
		  (rev sndwarp-rev)
		  (srcwidth sndwarp-srcwidth))

  (let* ((stereo-i (= (mus-sound-chans file) 2))
	 (f-a (make-readin file :channel 0))
	 (f-b (and stereo-i
		   (make-readin file :channel 1)))
	 (clmsw-envelope-or-number 
	  (lambda (in)
	    (if (number? in) (list 0 in 1 in) in)))
	 
	 (beg (seconds->samples begtime))
	 (fsr (mus-sound-srate file))
	 (rdA (make-src :input (lambda (dir) (readin f-a)) :srate 0.0 :width srcwidth))
	 (rdB (and stereo-i
		   (make-src :input (lambda (dir) (readin f-b)) :srate 0.0 :width srcwidth)))
	 (windf (make-oscil))
	 (wsizef (make-env (clmsw-envelope-or-number wsize) :duration dur))
	 
	 (ampf (make-env amp-env :scaler amp :duration dur))
	 (sratef (make-env (clmsw-envelope-or-number srate) :duration dur))
	 (timef (let ((time-env (clmsw-envelope-or-number stretch))
		      (fdur (mus-sound-duration file)))
		  (make-env
		   (if (and time-ptr scale-time-ptr)
		       (normalize-envelope time-env (- fdur inputbeg))
		       time-env)
		   :duration dur)))
	 (locf (make-env (clmsw-envelope-or-number loc) :duration dur))
	 
	 (end (+ beg (seconds->samples dur)))
         (stereo-o #f)
         (writestart 0)
         (readstart (round (* fsr inputbeg)))
         (eow-flag #f)
         (overlap-ratio 0.0000)
         (overlap-ratio-compl 0.0000)
         (outa-val 0.0000)
         (outb-val 0.0000))
    
    (do ((overlap 0 (+ 1 overlap)))
	((or eow-flag (= overlap overlaps)))
      (set! overlap-ratio (/ overlap overlaps))
      (set! overlap-ratio-compl (- 1 overlap-ratio))
      (set! eow-flag #f)
      (set! writestart beg)
      (set! (mus-location ampf) beg)
      (set! (mus-location locf) beg)
      (do ((section 0 (+ 1 section)))
	  ((or eow-flag (= overlap overlaps)))
	(set! (mus-location timef) writestart)
	(set! (mus-location sratef) writestart)
	(set! (mus-location wsizef) writestart)
	(set! wsize (env wsizef))
	(let* ((winlen (if (= overlap 0 section) ; first section of first overlap isn't randomized
			   wsize
			   (+ wsize (random randw))))
	       (winsamps (seconds->samples winlen))
	       (srate-val (env sratef)))
	  (let ((time-val (env timef)))
	    ;; Even for the first section's truncated envelopes, the frequency of the envelope must be as if the envelope were full duration.
	    (set! (mus-frequency windf) (* .5 (/ fsr winsamps)))
	    ;; Set windowing oscillator to starting phase and appropriate frequency to provide half-sine envelope over window.
	    ;; Phase must be altered for first envelope of each overlap stream.
	    (set! (mus-phase windf) 
		  (if (and (= section 0)
			   (not (= overlap 0)))
		      (* .5 clmsw-2pi overlap-ratio-compl)
		      0.0))
	    ;; Either use the absolute time pointer or a scaled increment.
	    ;; If first section in scaled mode, must initialize section readstart to beginning plus first overlap position.
	    ;; In both cases, need to alter readstart and length of first section's windows based on phase of overlap
	    (if time-ptr 
		;; TIME-PTR mode
		(if (= section 0)
		    ;; initial section
		    (let ((overlap-start 
			   (if (and window-offset
				    (not (= overlap 0)))
			       ;; Csound style - start each overlap series further into the soundfile
			       (round (* winlen overlap-ratio-compl))
			       ;; Alternative style - start each overlap series at 0
			       0))
			  ;; To match csound version, first section must start reading at 0. Using zero-start-time-ptr 
			  ;; flag = #f,  however, allows first section to start as determined by time-ptr instead.
			  (adj-time-val (if zero-start-time-ptr 0.0 time-val)))
		      (set! readstart (round (* fsr (+ inputbeg overlap-start adj-time-val))))
		      (if (not (= overlap 0)) (set! winsamps (floor (* winsamps overlap-ratio)))))
		    ;; remaining sections
		    (set! readstart (round (* fsr (+ inputbeg time-val)))))
		;; STRETCH mode
		(if (= section 0)
		    ;; initial section
		    (let ((init-read-start 
			   (if (and window-offset
				    (not (= overlap 0)))
			       ;; Csound style - start each overlap series further into the soundfile
			       (round (* winlen overlap-ratio-compl))
			       ;; Alternative style - start each overlap series at 0
			       0)))
		      (set! readstart (round (* fsr (+ inputbeg init-read-start))))
		      (if (not (= overlap 0)) (set! winsamps (floor (* winsamps overlap-ratio)))))
		    ;; remaining sections
		    (set! readstart (round (+ readstart (* fsr (/ winlen time-val))))))))
	  ;; Set readin position and sampling rate
	  (set! (mus-location f-a) readstart)
	  (set! (mus-increment rdA) srate-val)
	  (mus-reset rdA)
	  (if stereo-i
	      (begin
		(set! (mus-location f-b) readstart)
		(set! (mus-increment rdB) srate-val)
		(mus-reset rdB)))
	  ;; Write window out
	  (do ((k 0 (+ 1 k))
	       (i writestart (+ i 1)))
	      ((or eow-flag (= k winsamps)))
	    (if (> i end)
		(begin
		  (set! eow-flag #t)
		  (set! overlap (+ 1 overlaps)))
		(let* ((amp-val (env ampf))
		       (loc-val (env locf))
		       (win-val (oscil windf))
		       (sampa (* (src rdA) win-val))
		       (sampb (if stereo-i (* (src rdB) win-val))))
		  ;; channel panning
		  (if stereo-o
		      (let ((apan (sqrt loc-val))
			    (bpan (sqrt (- 1 loc-val))))
			(set! outa-val (* amp-val apan sampa))
			(set! outb-val (* amp-val bpan (if stereo-i sampb sampa))))
		      ;; stereo in, mono out
		      (set! outa-val (* amp-val (if stereo-i
						    (* (+ sampa sampb) .75)
						    ;; mono in, mono out
						    sampa))))
		  ;; output
		  (outa i outa-val)
		  (if stereo-o
		      (begin
			(outb i outb-val)	     
			(if *reverb* (outa i (* rev outa-val) *reverb*)))))))
	  (if (and (not eow-flag)   ;; For first section, have to backup readstart
		   (= section 0) 
		   (> overlap 0) 
		   (not time-ptr))
	      (set! readstart (- readstart (round (* fsr winlen overlap-ratio-compl)))))
	  (set! writestart (+ writestart winsamps)))))))
