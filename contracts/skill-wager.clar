;; ------------------------------------------------------------
;; Skill-Based Wagering - Two-Player STX Escrow (Clarity v3)
;; ------------------------------------------------------------

;; ---------- Constants ----------
(define-constant ERR-BAD-ARGS      (err u100))
(define-constant ERR-NOT-FOUND     (err u101))
(define-constant ERR-UNAUTHORIZED  (err u102))
(define-constant ERR-STATE         (err u103))
(define-constant ERR-INSUFFICIENT  (err u104))
(define-constant ERR-TOO-EARLY     (err u105))
(define-constant ERR-TOO-LATE      (err u106))

;; ---------- Storage ----------
(define-data-var next-id uint u1)
(define-data-var current-block-height uint u0)

;; status: 0=open (p1 funded), 1=active (both funded), 2=settled, 3=canceled
(define-map matches
  { id: uint }
  {
    p1: principal,
    p2: (optional principal),
    stake: uint,              ;; STX amount each player escrows
    referee: principal,       ;; trusted arbiter to decide winner
    join-deadline: uint,      ;; block-height cutoff to join
    result-deadline: uint,    ;; block-height cutoff to settle
    status: uint
  })

;; ---------- Helpers ----------
(define-read-only (now) 
  (var-get current-block-height))

(define-read-only (get-match (id uint))
  (ok (unwrap! (map-get? matches { id: id }) ERR-NOT-FOUND)))

;; ---------- Create (Player1 funds) ----------
;; @returns (response uint) - Returns the ID of the created match
(define-public (create-match (stake uint) (referee principal) (join-deadline uint) (result-deadline uint))
  (begin
    ;; Validate inputs
    (asserts! (> stake u0) ERR-BAD-ARGS)
    (asserts! (not (is-eq referee tx-sender)) ERR-BAD-ARGS) ;; Referee can't be player1
    (asserts! (> join-deadline (now)) ERR-BAD-ARGS)
    (asserts! (> result-deadline join-deadline) ERR-BAD-ARGS)
    (asserts! (< (- result-deadline (now)) u10000) ERR-BAD-ARGS) ;; Reasonable timeout window
    
    ;; escrow Player1 stake
    (asserts! (is-ok (stx-transfer? stake tx-sender (as-contract tx-sender))) ERR-INSUFFICIENT)

    (let ((id (var-get next-id)))
      (map-set matches { id: id }
        {
          p1: tx-sender,
          p2: none,
          stake: stake,
          referee: referee,
          join-deadline: join-deadline,
          result-deadline: result-deadline,
          status: u0
        })
      (var-set next-id (+ id u1))
      (ok id))))

;; ---------- Join (Player2 funds) ----------
;; @returns (response bool) - Returns true if join was successful
(define-public (join-match (id uint))
  (match (map-get? matches { id: id }) m
    (begin
      (asserts! (is-eq (get status m) u0) ERR-STATE)
      (asserts! (<= (now) (get join-deadline m)) ERR-TOO-LATE)
      (asserts! (not (is-eq tx-sender (get p1 m))) ERR-BAD-ARGS)
      (asserts! (not (is-eq tx-sender (get referee m))) ERR-BAD-ARGS) ;; Referee can't be player2

      ;; escrow Player2 stake
      (asserts! (is-ok (stx-transfer? (get stake m) tx-sender (as-contract tx-sender))) ERR-INSUFFICIENT)

      (map-set matches { id: id } {
        p1: (get p1 m),
        p2: (some tx-sender),
        stake: (get stake m),
        referee: (get referee m),
        join-deadline: (get join-deadline m),
        result-deadline: (get result-deadline m),
        status: u1
      })
      (ok true))
    ERR-NOT-FOUND))

;; ---------- Cancel (no join by deadline) -> refund Player1 ----------
(define-public (cancel-if-unjoined (id uint))
  (match (map-get? matches { id: id }) m
    (begin
      (asserts! (is-eq (get status m) u0) ERR-STATE)
      (asserts! (> (now) (get join-deadline m)) ERR-TOO-EARLY)
      (asserts! (is-eq tx-sender (get p1 m)) ERR-UNAUTHORIZED)

      ;; refund Player1 stake
      (asserts! (is-ok (stx-transfer? (get stake m) (as-contract tx-sender) (get p1 m))) ERR-INSUFFICIENT)
      (map-set matches { id: id } {
        p1: (get p1 m),
        p2: (get p2 m),
        stake: (get stake m),
        referee: (get referee m),
        join-deadline: (get join-deadline m),
        result-deadline: (get result-deadline m),
        status: u3
      })
      (ok true))
    ERR-NOT-FOUND))

;; ---------- Referee settles winner (takes full pot) ----------
(define-public (settle (id uint) (winner principal))
  (match (map-get? matches { id: id }) m
    (begin
      (asserts! (is-eq (get status m) u1) ERR-STATE)
      (asserts! (<= (now) (get result-deadline m)) ERR-TOO-LATE)
      (asserts! (is-eq tx-sender (get referee m)) ERR-UNAUTHORIZED)

      (let ((p1 (get p1 m))
            (p2 (unwrap-panic (get p2 m))))
        (asserts! (or (is-eq winner p1) (is-eq winner p2)) ERR-BAD-ARGS)
        (let ((pot (* u2 (get stake m))))
          (asserts! (is-ok (stx-transfer? pot (as-contract tx-sender) winner)) ERR-INSUFFICIENT)
          (map-set matches { id: id } {
            p1: (get p1 m),
            p2: (get p2 m),
            stake: (get stake m),
            referee: (get referee m),
            join-deadline: (get join-deadline m),
            result-deadline: (get result-deadline m),
            status: u2
          })
          (ok winner))))
    ERR-NOT-FOUND))

;; ---------- Fallback: split if no settlement by deadline ----------
;; @returns (response {p1: uint, p2: uint}) - Returns the amounts sent to each player
(define-public (split-if-timeout (id uint))
  (match (map-get? matches { id: id }) m
    (begin
      (asserts! (is-eq (get status m) u1) ERR-STATE)
      (asserts! (> (now) (get result-deadline m)) ERR-TOO-EARLY)

      (let ((p1 (get p1 m))
            (p2 (unwrap-panic (get p2 m)))
            (stake (get stake m))
            (pot (* u2 (get stake m)))) ;; Simple multiplication
        (let ((half (/ pot u2))
              (rem (if (is-eq pot u0) u0 (- pot (* u2 (/ pot u2)))))) ;; remainder (0 or 1 microSTX)
          (asserts! (is-ok (stx-transfer? half (as-contract tx-sender) p1)) ERR-INSUFFICIENT)
          (asserts! (is-ok (stx-transfer? (+ half rem) (as-contract tx-sender) p2)) ERR-INSUFFICIENT)
          (map-set matches { id: id } {
            p1: (get p1 m),
            p2: (get p2 m),
            stake: (get stake m),
            referee: (get referee m),
            join-deadline: (get join-deadline m),
            result-deadline: (get result-deadline m),
            status: u2
          })
          (ok { p1: half, p2: (+ half rem) }))))
    ERR-NOT-FOUND))

;; ---------- Views ----------
(define-read-only (status-of (id uint))
  (match (map-get? matches { id: id })
    m (ok (get status m))
    ERR-NOT-FOUND))

(define-read-only (pot-of (id uint))
  (match (map-get? matches { id: id })
    m (ok (if (is-eq (get status m) u0) (get stake m) (* u2 (get stake m))))
    ERR-NOT-FOUND))
