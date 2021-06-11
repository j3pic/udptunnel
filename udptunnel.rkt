#lang racket

(require racket/udp)
(require mzlib/match)

(define (make-inbound-socket port)
  (let ((sock (udp-open-socket)))
    (udp-bind! sock #f port)
    sock))

(define (make-outbound-socket host port)
  (let ((sock (udp-open-socket)))
    (udp-bind! sock #f 0)
    (udp-connect! sock host port)
    sock))

(define *max-buffer-size* 1000000)

(define (next-datagram sock)
  (let ((buffer (make-bytes *max-buffer-size*)))
    (let-values (((bytes-read ip port) (udp-receive! sock buffer)))
      (values (subbytes buffer 0 bytes-read) ip port))))

(define (encode-msb integer nbytes)
  (let loop ((bytes '())
	     (integer integer)
	     (n nbytes))
    (if (= n 0)
	(list->bytes bytes)
	(loop (cons (bitwise-and integer #xff) bytes)
	      (arithmetic-shift integer -8)
	      (sub1 n)))))

(define (decode-msb bytes)
  (let loop ((bytes (bytes->list bytes))
	     (result 0)
	     (n (bytes-length bytes)))
    (if (null? bytes)
	result
	(loop (cdr bytes)
	      (bitwise-ior result
			   (arithmetic-shift (car bytes)
					     (* 8 (sub1 n))))
	      (sub1 n)))))
    
(define (serialize-datagram datagram)
  (bytes-append (encode-msb (bytes-length datagram) 4)
		datagram))

(define (read-datagram-from-stream stream)
  (let ((length (decode-msb (read-bytes 4 stream))))
    (read-bytes length stream)))

(define (write-datagram datagram stream)
  (write-bytes (serialize-datagram datagram) stream))

(define (udp->stream insock outstream)
  (let loop ()
    (let-values (((dgram ip port) (next-datagram insock)))
      ;; Connect to whoever sent this datagram, so that the
      ;; return datagram processed by stream->udp knows
      ;; where to go.
      (udp-connect! insock ip port)
      (write-datagram dgram outstream))
    (loop)))

(define (stream->udp instream outsock)
  (let loop ()
    (udp-send outsock (read-datagram-from-stream instream))
    (loop)))

(define (cmdline)
  (vector->list (current-command-line-arguments)))

;;; Operating Modes
;;;
;;; Listen:
;;; udptunnel <port>
;;;
;;; Originate:
;;; udptunnel <host> <port>
;;;
;;; Stream from/to command: -e option.


(define (base-args* cmdline)
  (let loop ((args cmdline)
	     (result '()))
    (cond ((null? args)
	   (reverse result))
	  ((equal? (car args) "-e")
	   (loop (if (null? (cdr args))
		     '()
		     (cddr args))
		 result))
	  (else
	   (loop (cdr args)
		 (cons (car args) result))))))

(define (base-args)
  (base-args* (cmdline)))

(define (option* cmdline opt)
  (let loop ((cmdline cmdline))
    (cond ((null? cmdline)
	   #f)
	  ((and (equal? (car cmdline) opt)
		(not (null? (cdr cmdline))))
	   (cadr cmdline))
	  (else (loop (cdr cmdline))))))

(define (option opt)
  (option* (cmdline) opt))

(define (open-pipe cmd)
  (let-values (((blah in out err) (subprocess #f #f #f "/bin/sh" "-c" cmd)))
    (thread (λ () (let loop ()
		    (if (eof-object? (read-byte err))
			(close-input-port err)
			(loop)))))
    (file-stream-buffer-mode in 'none)
    (file-stream-buffer-mode out 'none)
    (values in out)))

(define sock (match (base-args)
	       ((port)
		(make-inbound-socket (string->number port)))
	       ((host port)
		(make-outbound-socket host (string->number port)))
	       (_ (error "Usage: udptunnel [<host>] <port> [-e shellcommand]"))))
	       
(define in-stream #f)
(define out-stream #f)

(if (option "-e")
    (let-values (((in out) (open-pipe (option "-e"))))
      (set! in-stream in)
      (set! out-stream out))
    (begin
      (set! in-stream (current-input-port))
      (set! out-stream (current-output-port))))

(define (other-thread)
  (thread (λ ()
	     (udp->stream sock out-stream)))
  (void))

(other-thread)

(stream->udp in-stream sock)