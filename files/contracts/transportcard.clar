;; CommutePass - Digital Transport Card Smart Contract
;; MVP v0.1 - Prepaid Wallets & QR Code Payment System

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_VEHICLE_NOT_FOUND (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_DAILY_LIMIT_EXCEEDED (err u104))
(define-constant ERR_VEHICLE_ALREADY_REGISTERED (err u105))
(define-constant ERR_INVALID_FARE (err u106))

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var platform-fee-rate uint u25) ;; 0.25% platform fee (25 basis points)

;; Data Maps
(define-map user-wallets 
  principal 
  {
    balance: uint,
    daily-spent: uint,
    daily-limit: uint,
    last-activity-day: uint
  }
)

(define-map registered-vehicles
  {vehicle-id: (string-ascii 64)}
  {
    driver: principal,
    fare-amount: uint,
    active: bool,
    total-rides: uint,
    total-earnings: uint
  }
)

(define-map daily-spending
  {user: principal, day: uint}
  uint
)

;; Read-only functions
(define-read-only (get-user-wallet (user principal))
  (default-to 
    {balance: u0, daily-spent: u0, daily-limit: u50000000, last-activity-day: u0} ;; 50 STX daily limit default
    (map-get? user-wallets user)
  )
)

(define-read-only (get-vehicle-info (vehicle-id (string-ascii 64)))
  (map-get? registered-vehicles {vehicle-id: vehicle-id})
)

(define-read-only (get-contract-info)
  {
    active: (var-get contract-active),
    platform-fee-rate: (var-get platform-fee-rate),
    total-vehicles: u0 ;; Could be tracked with a counter if needed
  }
)

(define-read-only (get-current-day)
  (/ stacks-block-height u144) ;; Approximate days (144 blocks per day)
)

;; Private functions
(define-private (reset-daily-spending-if-new-day (user principal) (wallet {balance: uint, daily-spent: uint, daily-limit: uint, last-activity-day: uint}))
  (let ((current-day (get-current-day)))
    (if (> current-day (get last-activity-day wallet))
      (merge wallet {daily-spent: u0, last-activity-day: current-day})
      wallet
    )
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Public functions

;; Top up wallet with STX
(define-public (top-up-wallet (amount uint))
  (let (
    (current-wallet (get-user-wallet tx-sender))
    (updated-wallet (reset-daily-spending-if-new-day tx-sender current-wallet))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update user wallet
    (map-set user-wallets tx-sender 
      (merge updated-wallet {balance: (+ (get balance updated-wallet) amount)})
    )
    
    (ok {
      new-balance: (+ (get balance updated-wallet) amount),
      amount-added: amount
    })
  )
)

;; Register a new vehicle (for drivers)
(define-public (register-vehicle (vehicle-id (string-ascii 64)) (fare-amount uint))
  (let ((existing-vehicle (get-vehicle-info vehicle-id)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-vehicle) ERR_VEHICLE_ALREADY_REGISTERED)
    (asserts! (> fare-amount u0) ERR_INVALID_FARE)
    
    (map-set registered-vehicles 
      {vehicle-id: vehicle-id}
      {
        driver: tx-sender,
        fare-amount: fare-amount,
        active: true,
        total-rides: u0,
        total-earnings: u0
      }
    )
    
    (ok {vehicle-id: vehicle-id, fare-amount: fare-amount, driver: tx-sender})
  )
)

;; Pay fare using QR code/vehicle ID
(define-public (pay-fare (vehicle-id (string-ascii 64)))
  (let (
    (vehicle-info (unwrap! (get-vehicle-info vehicle-id) ERR_VEHICLE_NOT_FOUND))
    (current-wallet (get-user-wallet tx-sender))
    (updated-wallet (reset-daily-spending-if-new-day tx-sender current-wallet))
    (fare-amount (get fare-amount vehicle-info))
    (platform-fee (calculate-platform-fee fare-amount))
    (driver-amount (- fare-amount platform-fee))
    (new-daily-spent (+ (get daily-spent updated-wallet) fare-amount))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (get active vehicle-info) ERR_VEHICLE_NOT_FOUND)
    (asserts! (>= (get balance updated-wallet) fare-amount) ERR_INSUFFICIENT_FUNDS)
    (asserts! (<= new-daily-spent (get daily-limit updated-wallet)) ERR_DAILY_LIMIT_EXCEEDED)
    
    ;; Update rider wallet
    (map-set user-wallets tx-sender 
      (merge updated-wallet {
        balance: (- (get balance updated-wallet) fare-amount),
        daily-spent: new-daily-spent
      })
    )
    
    ;; Transfer fare to driver (minus platform fee)
    (try! (as-contract (stx-transfer? driver-amount tx-sender (get driver vehicle-info))))
    
    ;; Update vehicle stats
    (map-set registered-vehicles 
      {vehicle-id: vehicle-id}
      (merge vehicle-info {
        total-rides: (+ (get total-rides vehicle-info) u1),
        total-earnings: (+ (get total-earnings vehicle-info) driver-amount)
      })
    )
    
    (ok {
      fare-paid: fare-amount,
      platform-fee: platform-fee,
      driver-received: driver-amount,
      remaining-balance: (- (get balance updated-wallet) fare-amount),
      vehicle-id: vehicle-id
    })
  )
)

;; Update daily spending limit
(define-public (set-daily-limit (new-limit uint))
  (let ((current-wallet (get-user-wallet tx-sender)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> new-limit u0) ERR_INVALID_AMOUNT)
    
    (map-set user-wallets tx-sender 
      (merge current-wallet {daily-limit: new-limit})
    )
    
    (ok {new-daily-limit: new-limit})
  )
)

;; Update vehicle fare (driver only)
(define-public (update-vehicle-fare (vehicle-id (string-ascii 64)) (new-fare uint))
  (let ((vehicle-info (unwrap! (get-vehicle-info vehicle-id) ERR_VEHICLE_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get driver vehicle-info)) ERR_UNAUTHORIZED)
    (asserts! (> new-fare u0) ERR_INVALID_FARE)
    
    (map-set registered-vehicles 
      {vehicle-id: vehicle-id}
      (merge vehicle-info {fare-amount: new-fare})
    )
    
    (ok {vehicle-id: vehicle-id, new-fare: new-fare})
  )
)

;; Toggle vehicle active status (driver only)
(define-public (toggle-vehicle-status (vehicle-id (string-ascii 64)))
  (let ((vehicle-info (unwrap! (get-vehicle-info vehicle-id) ERR_VEHICLE_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get driver vehicle-info)) ERR_UNAUTHORIZED)
    
    (map-set registered-vehicles 
      {vehicle-id: vehicle-id}
      (merge vehicle-info {active: (not (get active vehicle-info))})
    )
    
    (ok {vehicle-id: vehicle-id, active: (not (get active vehicle-info))})
  )
)

;; Admin functions (contract owner only)
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT) ;; Max 10% fee
    (var-set platform-fee-rate new-rate)
    (ok {new-platform-fee-rate: new-rate})
  )
)

(define-public (toggle-contract-status)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok {contract-active: (var-get contract-active)})
  )
)

;; Emergency withdraw (contract owner only)
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok {withdrawn: amount})
  )
)
