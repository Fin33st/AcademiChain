;; AcademiChain - A decentralized academic credential verification platform
;; Enables transparent credential tracking from institution to employer

;; Data storage
(define-map institution-profiles principal {
  active: bool,
  accreditations: (list 10 uint),
  reputation: uint,
  last-action: uint,
  transaction-count: uint
})

(define-map credential-records uint {
  issuer: principal,
  quantity: uint,
  quality-score: uint,
  active: bool,
  credential-type: uint,
  total-transfers: uint,
  created-at: uint
})

(define-map verification-records {verifier: principal, credential-id: uint} {
  timestamp: uint,
  verified: bool
})

(define-map credential-types uint (string-ascii 64))

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_INSTITUTION_NOT_FOUND (err u102))
(define-constant ERR_CREDENTIAL_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_QUANTITY (err u104))
(define-constant ERR_ALREADY_REGISTERED (err u105))
(define-constant ERR_ALREADY_VERIFIED (err u106))
(define-constant ERR_INVALID_PRINCIPAL (err u107))
(define-constant ERR_INVALID_VALUE (err u108))
(define-constant ERR_CREDENTIAL_TYPE_NOT_FOUND (err u109))

(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_QUALITY_SCORE u1)
(define-constant MAX_QUALITY_SCORE u1000)
(define-constant MIN_CREDENTIAL_QUANTITY u1000)
(define-constant MAX_CREDENTIAL_TYPE_ID u1000)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-credential-id uint u1)
(define-data-var network-fee-percent uint u5)
(define-data-var network-balance uint u0)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR_INVALID_PRINCIPAL)
    (ok (var-set contract-owner new-owner))))

(define-public (set-network-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (<= new-fee u20) ERR_INVALID_PARAMS)
    (ok (var-set network-fee-percent new-fee))))

(define-public (add-credential-type (type-id uint) (type-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len type-name) u0) ERR_INVALID_PARAMS)
    (asserts! (< type-id MAX_CREDENTIAL_TYPE_ID) ERR_INVALID_PARAMS)
    (asserts! (is-none (map-get? credential-types type-id)) ERR_ALREADY_REGISTERED)
    (ok (map-set credential-types type-id type-name))))

;; Institution functions
(define-public (register-institution (accreditations (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? institution-profiles tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (validate-accreditations accreditations) ERR_INVALID_PARAMS)
    (ok (map-set institution-profiles tx-sender {
      active: true,
      accreditations: accreditations,
      reputation: u0,
      last-action: u0,
      transaction-count: u0
    }))))

(define-public (update-accreditations (accreditations (list 10 uint)))
  (let ((institution-profile (unwrap! (map-get? institution-profiles tx-sender) ERR_INSTITUTION_NOT_FOUND)))
    (asserts! (validate-accreditations accreditations) ERR_INVALID_PARAMS)
    (ok (map-set institution-profiles tx-sender (merge institution-profile {accreditations: accreditations})))))

(define-public (deactivate-institution)
  (let ((institution-profile (unwrap! (map-get? institution-profiles tx-sender) ERR_INSTITUTION_NOT_FOUND)))
    (ok (map-set institution-profiles tx-sender (merge institution-profile {active: false})))))

(define-public (reactivate-institution)
  (let ((institution-profile (unwrap! (map-get? institution-profiles tx-sender) ERR_INSTITUTION_NOT_FOUND)))
    (ok (map-set institution-profiles tx-sender (merge institution-profile {active: true})))))

;; Credential issuance functions
(define-public (issue-credential (quantity uint) (quality-score uint) (credential-type uint) (stx-amount uint))
  (begin
    (asserts! (>= quantity MIN_CREDENTIAL_QUANTITY) ERR_INVALID_PARAMS)
    (asserts! (and (>= quality-score MIN_QUALITY_SCORE) (<= quality-score MAX_QUALITY_SCORE)) ERR_INVALID_PARAMS)
    (asserts! (is-some (map-get? credential-types credential-type)) ERR_CREDENTIAL_TYPE_NOT_FOUND)
    (asserts! (>= stx-amount quantity) ERR_INSUFFICIENT_QUANTITY)
    
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((credential-id (var-get next-credential-id)))
      (map-set credential-records credential-id {
        issuer: tx-sender,
        quantity: quantity,
        quality-score: quality-score,
        active: true,
        credential-type: credential-type,
        total-transfers: u0,
        created-at: u0
      })
      
      (var-set next-credential-id (+ credential-id u1))
      (ok credential-id))))

(define-public (revoke-credential (credential-id uint))
  (let ((credential (unwrap! (map-get? credential-records credential-id) ERR_CREDENTIAL_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get issuer credential)) ERR_NOT_AUTHORIZED)
    (ok (map-set credential-records credential-id (merge credential {active: false})))))

(define-public (reactivate-credential (credential-id uint))
  (let ((credential (unwrap! (map-get? credential-records credential-id) ERR_CREDENTIAL_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get issuer credential)) ERR_NOT_AUTHORIZED)
    (ok (map-set credential-records credential-id (merge credential {active: true})))))

(define-public (add-credential-quantity (credential-id uint) (additional-quantity uint))
  (let ((credential (unwrap! (map-get? credential-records credential-id) ERR_CREDENTIAL_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get issuer credential)) ERR_NOT_AUTHORIZED)
    (asserts! (> additional-quantity u0) ERR_INVALID_PARAMS)
    
    (try! (stx-transfer? additional-quantity tx-sender (as-contract tx-sender)))
    
    (ok (map-set credential-records credential-id 
      (merge credential {quantity: (+ (get quantity credential) additional-quantity)})))))

;; Helper function to check accreditation match
(define-private (check-accreditation-match (credential-type uint) (accreditations (list 10 uint)))
  (or
    (and (> (len accreditations) u0) (is-eq credential-type (unwrap-panic (element-at accreditations u0))))
    (and (> (len accreditations) u1) (is-eq credential-type (unwrap-panic (element-at accreditations u1))))
    (and (> (len accreditations) u2) (is-eq credential-type (unwrap-panic (element-at accreditations u2))))
    (and (> (len accreditations) u3) (is-eq credential-type (unwrap-panic (element-at accreditations u3))))
    (and (> (len accreditations) u4) (is-eq credential-type (unwrap-panic (element-at accreditations u4))))
    (and (> (len accreditations) u5) (is-eq credential-type (unwrap-panic (element-at accreditations u5))))
    (and (> (len accreditations) u6) (is-eq credential-type (unwrap-panic (element-at accreditations u6))))
    (and (> (len accreditations) u7) (is-eq credential-type (unwrap-panic (element-at accreditations u7))))
    (and (> (len accreditations) u8) (is-eq credential-type (unwrap-panic (element-at accreditations u8))))
    (and (> (len accreditations) u9) (is-eq credential-type (unwrap-panic (element-at accreditations u9))))
  ))

;; Verification functions
(define-public (verify-credential (credential-id uint))
  (let (
    (institution-profile (unwrap! (map-get? institution-profiles tx-sender) ERR_INSTITUTION_NOT_FOUND))
    (credential (unwrap! (map-get? credential-records credential-id) ERR_CREDENTIAL_NOT_FOUND))
    (verification-key {verifier: tx-sender, credential-id: credential-id})
  )
    (asserts! (get active institution-profile) ERR_INSTITUTION_NOT_FOUND)
    (asserts! (get active credential) ERR_CREDENTIAL_NOT_FOUND)
    (asserts! (is-none (map-get? verification-records verification-key)) ERR_ALREADY_VERIFIED)
    (asserts! (>= (get quantity credential) (get quality-score credential)) ERR_INSUFFICIENT_QUANTITY)
    (asserts! (check-accreditation-match (get credential-type credential) (get accreditations institution-profile)) ERR_INVALID_PARAMS)
    
    (let (
      (quality-score (get quality-score credential))
      (network-fee (/ (* quality-score (var-get network-fee-percent)) u100))
      (institution-reputation (- quality-score network-fee))
    )
      (map-set verification-records verification-key {timestamp: u0, verified: true})
      
      (map-set credential-records credential-id (merge credential {
        quantity: (- (get quantity credential) quality-score),
        total-transfers: (+ (get total-transfers credential) u1)
      }))
      
      (map-set institution-profiles tx-sender (merge institution-profile {
        reputation: (+ (get reputation institution-profile) institution-reputation),
        transaction-count: (+ (get transaction-count institution-profile) u1)
      }))
      
      (var-set network-balance (+ (var-get network-balance) network-fee))
      
      (ok institution-reputation))))

(define-public (claim-reputation)
  (let ((institution-profile (unwrap! (map-get? institution-profiles tx-sender) ERR_INSTITUTION_NOT_FOUND)))
    (let ((reputation (get reputation institution-profile)))
      (asserts! (> reputation u0) ERR_INSUFFICIENT_QUANTITY)
      
      (try! (as-contract (stx-transfer? reputation tx-sender tx-sender)))
      
      (map-set institution-profiles tx-sender (merge institution-profile {
        reputation: u0,
        last-action: u0
      }))
      
      (ok reputation))))

(define-public (withdraw-network-fees)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (let ((amount (var-get network-balance)))
      (asserts! (> amount u0) ERR_INSUFFICIENT_QUANTITY)
      
      (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))
      
      (var-set network-balance u0)
      
      (ok amount))))

;; Helper functions
(define-private (is-valid-credential-type (credential-type uint))
  (is-some (map-get? credential-types credential-type)))

(define-private (count-valid-credential-types (accreditations (list 10 uint)))
  (+ 
    (if (and (> (len accreditations) u0) (is-valid-credential-type (unwrap-panic (element-at accreditations u0)))) u1 u0)
    (if (and (> (len accreditations) u1) (is-valid-credential-type (unwrap-panic (element-at accreditations u1)))) u1 u0)
    (if (and (> (len accreditations) u2) (is-valid-credential-type (unwrap-panic (element-at accreditations u2)))) u1 u0)
    (if (and (> (len accreditations) u3) (is-valid-credential-type (unwrap-panic (element-at accreditations u3)))) u1 u0)
    (if (and (> (len accreditations) u4) (is-valid-credential-type (unwrap-panic (element-at accreditations u4)))) u1 u0)
    (if (and (> (len accreditations) u5) (is-valid-credential-type (unwrap-panic (element-at accreditations u5)))) u1 u0)
    (if (and (> (len accreditations) u6) (is-valid-credential-type (unwrap-panic (element-at accreditations u6)))) u1 u0)
    (if (and (> (len accreditations) u7) (is-valid-credential-type (unwrap-panic (element-at accreditations u7)))) u1 u0)
    (if (and (> (len accreditations) u8) (is-valid-credential-type (unwrap-panic (element-at accreditations u8)))) u1 u0)
    (if (and (> (len accreditations) u9) (is-valid-credential-type (unwrap-panic (element-at accreditations u9)))) u1 u0)
  ))

(define-private (validate-accreditations (accreditations (list 10 uint)))
  (let ((accreds-len (len accreditations)))
    (and 
      (> accreds-len u0)
      (<= accreds-len u10)
      (is-eq accreds-len (count-valid-credential-types accreditations)))))

;; Read-only functions
(define-read-only (get-institution-profile (institution principal))
  (map-get? institution-profiles institution))

(define-read-only (get-credential (credential-id uint))
  (map-get? credential-records credential-id))

(define-read-only (get-credential-type (type-id uint))
  (map-get? credential-types type-id))

(define-read-only (get-network-fee)
  (var-get network-fee-percent))

(define-read-only (get-network-balance)
  (var-get network-balance))

(define-read-only (get-verification-record (verifier principal) (credential-id uint))
  (map-get? verification-records {verifier: verifier, credential-id: credential-id}))
