;; -------------------------------
;; Loyalty Ride Tracking Contract
;; -------------------------------

(define-constant ERR_UNAUTHORIZED (err u100))

;; -------------------------------
;; Data structures
;; -------------------------------

(define-map user-loyalty-stats
  { user: principal }
  {
    total-rides: uint,
    free-rides-earned: uint,
    last-ride-block: uint
  }
)

(define-map streak-bonuses
  { user: principal }
  {
    streak: uint,
    bonus-amount: uint
  }
)

(define-data-var loyalty-active bool true)

;; -------------------------------
;; Dummy external helpers
;; (replace with your real ones)
;; -------------------------------

(define-read-only (get-user-loyalty-stats (user principal))
  (default-to
    { total-rides: u0, free-rides-earned: u0, last-ride-block: u0 }
    (map-get? user-loyalty-stats { user: user })
  )
)

(define-read-only (calculate-free-rides-earned (total uint))
  (/ total u10)
)

(define-public (mint-free-ride-nft (rider principal) (rides uint))
  (ok { nft-id: rides, recipient: rider, rides-completed: rides })
)

(define-public (award-streak-bonus (rider principal) (streak uint))
  (ok { user: rider, streak: streak, bonus-amount: (* u10 streak) })
)

(define-public (update-streak-bonus (rider principal))
  ;; In real code: update map, calculate streak
  (ok u1) ;; always streak = 1 for example
)

;; -------------------------------
;; Core function: record-ride
;; -------------------------------

(define-public (record-ride (rider principal))
  (let
    (
      (current (get-user-loyalty-stats rider))
      (prev-total (get total-rides current))
      (prev-free (get free-rides-earned current))
      (new-total (+ prev-total u1))
      (new-free (calculate-free-rides-earned new-total))
    )

    ;; Ensure loyalty program is active
    (asserts! (var-get loyalty-active) ERR_UNAUTHORIZED)

    ;; Update streak (unwrap response safely)
    (let ((new-streak (unwrap-panic (update-streak-bonus rider))))

      ;; Persist new stats
      (map-set user-loyalty-stats { user: rider }
        { total-rides: new-total, free-rides-earned: new-free, last-ride-block: stacks-block-height }
      )

      ;; Normalize NFT mint
      (let (
        (mint-record
          (if (> new-free prev-free)
            (unwrap-panic (mint-free-ride-nft rider new-total))
            { nft-id: u0, recipient: rider, rides-completed: u0 }
          )
        )
        ;; Normalize streak bonus
        (streak-record
          (if (is-eq (mod new-streak u7) u0)
            (unwrap-panic (award-streak-bonus rider new-streak))
            { user: rider, streak: u0, bonus-amount: u0 }
          )
        )
      )
        ;; Unified response
        (ok {
          rider: rider,
          total-rides: new-total,
          free-rides-earned: new-free,
          current-streak: new-streak,
          free-ride-nft: (if (> (get nft-id mint-record) u0) (some mint-record) none),
          streak-bonus: (if (> (get bonus-amount streak-record) u0) (some streak-record) none)
        })
      )
    )
  )
)
