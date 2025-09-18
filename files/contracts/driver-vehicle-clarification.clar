;; CommutePass - Driver & Vehicle Verification Layer
;; v1.0 - Government/Union ID Verification & Vehicle Token System

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_ALREADY_VERIFIED (err u201))
(define-constant ERR_NOT_VERIFIED (err u202))
(define-constant ERR_INVALID_ID (err u203))
(define-constant ERR_VEHICLE_TOKEN_EXISTS (err u204))
(define-constant ERR_INVALID_TOKEN (err u205))
(define-constant ERR_VERIFICATION_PENDING (err u206))
(define-constant ERR_VERIFICATION_REJECTED (err u207))

;; Verification Status Types
(define-constant VERIFICATION_PENDING u0)
(define-constant VERIFICATION_APPROVED u1)
(define-constant VERIFICATION_REJECTED u2)

;; ID Types
(define-constant ID_TYPE_GOVERNMENT u1)
(define-constant ID_TYPE_UNION u2)

;; Data Variables
(define-data-var verification-active bool true)
(define-data-var next-vehicle-token-id uint u1)
(define-data-var verification-fee uint u1000000) ;; 1 STX verification fee

;; Driver Verification Data
(define-map driver-verifications
  principal
  {
    id-number: (string-ascii 64),
    id-type: uint,
    full-name: (string-ascii 128),
    verification-status: uint,
    verified-at: uint,
    verified-by: (optional principal),
    expiry-block: uint
  }
)

;; Vehicle Token System
(define-map vehicle-tokens
  uint ;; token-id
  {
    owner: principal,
    vehicle-plate: (string-ascii 32),
    vehicle-type: (string-ascii 64),
    registration-number: (string-ascii 64),
    created-at: uint,
    active: bool,
    verification-hash: (string-ascii 128)
  }
)

;; Vehicle Token Ownership
(define-map vehicle-token-owners
  {owner: principal, token-id: uint}
  bool
)

;; Authorized Verifiers (government officials, union representatives)
(define-map authorized-verifiers
  principal
  {
    name: (string-ascii 128),
    organization: (string-ascii 128),
    active: bool,
    added-at: uint
  }
)

;; Verification Applications Queue
(define-map verification-applications
  principal
  {
    id-number: (string-ascii 64),
    id-type: uint,
    full-name: (string-ascii 128),
    submitted-at: uint,
    documents-hash: (string-ascii 128)
  }
)

;; Read-only functions
(define-read-only (get-driver-verification (driver principal))
  (map-get? driver-verifications driver)
)

(define-read-only (is-driver-verified (driver principal))
  (match (get-driver-verification driver)
    verification-data (is-eq (get verification-status verification-data) VERIFICATION_APPROVED)
    false
  )
)

(define-read-only (get-vehicle-token (token-id uint))
  (map-get? vehicle-tokens token-id)
)

(define-read-only (is-vehicle-token-owner (owner principal) (token-id uint))
  (default-to false (map-get? vehicle-token-owners {owner: owner, token-id: token-id}))
)

(define-read-only (get-authorized-verifier (verifier principal))
  (map-get? authorized-verifiers verifier)
)

(define-read-only (is-authorized-verifier (verifier principal))
  (match (get-authorized-verifier verifier)
    verifier-data (get active verifier-data)
    false
  )
)

(define-read-only (get-verification-application (applicant principal))
  (map-get? verification-applications applicant)
)

(define-read-only (get-next-token-id)
  (var-get next-vehicle-token-id)
)

(define-read-only (get-contract-info)
  {
    verification-active: (var-get verification-active),
    next-token-id: (var-get next-vehicle-token-id),
    verification-fee: (var-get verification-fee)
  }
)

;; Private functions
(define-private (is-valid-id-type (id-type uint))
  (or (is-eq id-type ID_TYPE_GOVERNMENT) (is-eq id-type ID_TYPE_UNION))
)

(define-private (increment-token-id)
  (let ((current-id (var-get next-vehicle-token-id)))
    (var-set next-vehicle-token-id (+ current-id u1))
    current-id
  )
)

;; Public functions

;; Apply for driver verification
(define-public (apply-for-verification 
  (id-number (string-ascii 64))
  (id-type uint)
  (full-name (string-ascii 128))
  (documents-hash (string-ascii 128))
)
  (begin
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-valid-id-type id-type) ERR_INVALID_ID)
    (asserts! (> (len id-number) u0) ERR_INVALID_ID)
    (asserts! (> (len full-name) u0) ERR_INVALID_ID)
    (asserts! (is-none (get-driver-verification tx-sender)) ERR_ALREADY_VERIFIED)
    
    ;; Pay verification fee
    (try! (stx-transfer? (var-get verification-fee) tx-sender (as-contract tx-sender)))
    
    ;; Store application
    (map-set verification-applications tx-sender {
      id-number: id-number,
      id-type: id-type,
      full-name: full-name,
      submitted-at: stacks-block-height,
      documents-hash: documents-hash
    })
    
    (ok {
      applicant: tx-sender,
      id-type: id-type,
      submitted-at: stacks-block-height
    })
  )
)

;; Approve driver verification (authorized verifiers only)
(define-public (approve-driver-verification 
  (driver principal)
  (expiry-blocks uint)
)
  (let ((application (unwrap! (get-verification-application driver) ERR_INVALID_ID)))
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-authorized-verifier tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-none (get-driver-verification driver)) ERR_ALREADY_VERIFIED)
    (asserts! (> expiry-blocks stacks-block-height) ERR_INVALID_ID)
    
    ;; Create verification record
    (map-set driver-verifications driver {
      id-number: (get id-number application),
      id-type: (get id-type application),
      full-name: (get full-name application),
      verification-status: VERIFICATION_APPROVED,
      verified-at: stacks-block-height,
      verified-by: (some tx-sender),
      expiry-block: expiry-blocks
    })
    
    ;; Remove application from queue
    (map-delete verification-applications driver)
    
    (ok {
      driver: driver,
      verified-by: tx-sender,
      expiry-block: expiry-blocks
    })
  )
)

;; Reject driver verification (authorized verifiers only)
(define-public (reject-driver-verification (driver principal))
  (let ((application (unwrap! (get-verification-application driver) ERR_INVALID_ID)))
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-authorized-verifier tx-sender) ERR_UNAUTHORIZED)
    
    ;; Remove application from queue
    (map-delete verification-applications driver)
    
    (ok {
      driver: driver,
      rejected-by: tx-sender,
      rejected-at: stacks-block-height
    })
  )
)

;; Mint vehicle token (verified drivers only)
(define-public (mint-vehicle-token
  (vehicle-plate (string-ascii 32))
  (vehicle-type (string-ascii 64))
  (registration-number (string-ascii 64))
  (verification-hash (string-ascii 128))
)
  (let ((token-id (increment-token-id)))
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-driver-verified tx-sender) ERR_NOT_VERIFIED)
    (asserts! (> (len vehicle-plate) u0) ERR_INVALID_TOKEN)
    (asserts! (> (len registration-number) u0) ERR_INVALID_TOKEN)
    
    ;; Create vehicle token
    (map-set vehicle-tokens token-id {
      owner: tx-sender,
      vehicle-plate: vehicle-plate,
      vehicle-type: vehicle-type,
      registration-number: registration-number,
      created-at: stacks-block-height,
      active: true,
      verification-hash: verification-hash
    })
    
    ;; Set ownership
    (map-set vehicle-token-owners {owner: tx-sender, token-id: token-id} true)
    
    (ok {
      token-id: token-id,
      owner: tx-sender,
      vehicle-plate: vehicle-plate,
      created-at: stacks-block-height
    })
  )
)

;; Transfer vehicle token
(define-public (transfer-vehicle-token (token-id uint) (new-owner principal))
  (let ((token-info (unwrap! (get-vehicle-token token-id) ERR_INVALID_TOKEN)))
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner token-info)) ERR_UNAUTHORIZED)
    (asserts! (is-driver-verified new-owner) ERR_NOT_VERIFIED)
    
    ;; Update token ownership
    (map-set vehicle-tokens token-id 
      (merge token-info {owner: new-owner})
    )
    
    ;; Update ownership mappings
    (map-delete vehicle-token-owners {owner: tx-sender, token-id: token-id})
    (map-set vehicle-token-owners {owner: new-owner, token-id: token-id} true)
    
    (ok {
      token-id: token-id,
      previous-owner: tx-sender,
      new-owner: new-owner
    })
  )
)

;; Toggle vehicle token status
(define-public (toggle-vehicle-token-status (token-id uint))
  (let ((token-info (unwrap! (get-vehicle-token token-id) ERR_INVALID_TOKEN)))
    (asserts! (var-get verification-active) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner token-info)) ERR_UNAUTHORIZED)
    
    (map-set vehicle-tokens token-id 
      (merge token-info {active: (not (get active token-info))})
    )
    
    (ok {
      token-id: token-id,
      active: (not (get active token-info))
    })
  )
)

;; Verification check for payment system integration
(define-read-only (can-receive-payment (driver principal) (vehicle-token-id uint))
  (and 
    (is-driver-verified driver)
    (match (get-vehicle-token vehicle-token-id)
      token-info (and 
        (is-eq (get owner token-info) driver)
        (get active token-info)
      )
      false
    )
  )
)

;; Admin functions (contract owner only)
(define-public (add-authorized-verifier 
  (verifier principal)
  (name (string-ascii 128))
  (organization (string-ascii 128))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_ID)
    
    (map-set authorized-verifiers verifier {
      name: name,
      organization: organization,
      active: true,
      added-at: stacks-block-height
    })
    
    (ok {verifier: verifier, organization: organization})
  )
)

(define-public (toggle-verifier-status (verifier principal))
  (let ((verifier-info (unwrap! (get-authorized-verifier verifier) ERR_UNAUTHORIZED)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set authorized-verifiers verifier 
      (merge verifier-info {active: (not (get active verifier-info))})
    )
    
    (ok {verifier: verifier, active: (not (get active verifier-info))})
  )
)

(define-public (set-verification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set verification-fee new-fee)
    (ok {new-verification-fee: new-fee})
  )
)

(define-public (toggle-verification-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set verification-active (not (var-get verification-active)))
    (ok {verification-active: (var-get verification-active)})
  )
)

;; Emergency functions
(define-public (revoke-driver-verification (driver principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete driver-verifications driver)
    (ok {revoked-driver: driver})
  )
)

(define-public (emergency-withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok {withdrawn: amount})
  )
)
