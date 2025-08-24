# AcademiChain

A decentralized academic credential verification platform built on Stacks blockchain that enables transparent credential tracking from educational institutions to employers.

## Features

- **Institution Registration**: Educational institutions can register and manage their accreditation profiles
- **Credential Issuance**: Institutions can issue verifiable digital credentials
- **Verification System**: Employers and other institutions can verify credential authenticity
- **Reputation Tracking**: Built-in reputation system for institutions based on verification activity
- **Fee Management**: Network fee system for sustainable platform operation

## Smart Contract Functions

### Admin Functions
- `set-contract-owner`: Transfer contract ownership
- `set-network-fee`: Adjust network fee percentage
- `add-credential-type`: Register new credential types

### Institution Functions
- `register-institution`: Register as a credential-issuing institution
- `update-accreditations`: Update institution accreditation list
- `issue-credential`: Issue new digital credentials
- `verify-credential`: Verify credentials from other institutions

### User Functions
- `claim-reputation`: Claim earned reputation tokens
- `get-institution-profile`: View institution details
- `get-credential`: View credential information

## Getting Started

1. Deploy the contract to Stacks blockchain
2. Register credential types through admin functions
3. Institutions register with their accreditations
4. Begin issuing and verifying credentials

## License

MIT License
\`\`\`

```clarity file="project-2-artchain/contracts/artchain.clar"
;; ArtChain - A decentralized digital art provenance tracking platform
;; Enables transparent artwork tracking from artist to collector

;; Data storage
(define-map artist-profiles principal {
  active: bool,
  specializations: (list 10 uint),
  reputation: uint,
  last-action: uint,
  transaction-count: uint
})

(define-map artwork-collections uint {
  creator: principal,
  quantity: uint,
  quality-score: uint,
  active: bool,
  art-style: uint,
  total-transfers: uint,
  created-at: uint
})

(define-map provenance-records {collector: principal, collection-id: uint} {
  timestamp: uint,
  verified: bool
})

(define-map art-styles uint (string-ascii 64))

;; Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMS (err u101))
(define-constant ERR_ARTIST_NOT_FOUND (err u102))
(define-constant ERR_COLLECTION_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_QUANTITY (err u104))
(define-constant ERR_ALREADY_REGISTERED (err u105))
(define-constant ERR_ALREADY_COLLECTED (err u106))
(define-constant ERR_INVALID_PRINCIPAL (err u107))
(define-constant ERR_INVALID_VALUE (err u108))
(define-constant ERR_ART_STYLE_NOT_FOUND (err u109))

(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)
(define-constant MIN_QUALITY_SCORE u1)
(define-constant MAX_QUALITY_SCORE u1000)
(define-constant MIN_COLLECTION_QUANTITY u1000)
(define-constant MAX_ART_STYLE_ID u1000)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-collection-id uint u1)
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
    (asserts! (&lt;= new-fee u20) ERR_INVALID_PARAMS)
    (ok (var-set network-fee-percent new-fee))))

(define-public (add-art-style (style-id uint) (style-name (string-ascii 64)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> (len style-name) u0) ERR_INVALID_PARAMS)
    (asserts! (&lt; style-id MAX_ART_STYLE_ID) ERR_INVALID_PARAMS)
    (asserts! (is-none (map-get? art-styles style-id)) ERR_ALREADY_REGISTERED)
    (ok (map-set art-styles style-id style-name))))

;; Artist functions
(define-public (register-artist (specializations (list 10 uint)))
  (begin
    (asserts! (is-none (map-get? artist-profiles tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (validate-specializations specializations) ERR_INVALID_PARAMS)
    (ok (map-set artist-profiles tx-sender {
      active: true,
      specializations: specializations,
      reputation: u0,
      last-action: u0,
      transaction-count: u0
    }))))

(define-public (update-specializations (specializations (list 10 uint)))
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) ERR_ARTIST_NOT_FOUND)))
    (asserts! (validate-specializations specializations) ERR_INVALID_PARAMS)
    (ok (map-set artist-profiles tx-sender (merge artist-profile {specializations: specializations})))))

(define-public (deactivate-artist)
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) ERR_ARTIST_NOT_FOUND)))
    (ok (map-set artist-profiles tx-sender (merge artist-profile {active: false})))))

(define-public (reactivate-artist)
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) ERR_ARTIST_NOT_FOUND)))
    (ok (map-set artist-profiles tx-sender (merge artist-profile {active: true})))))

;; Collection creation functions
(define-public (create-artwork-collection (quantity uint) (quality-score uint) (art-style uint) (stx-amount uint))
  (begin
    (asserts! (>= quantity MIN_COLLECTION_QUANTITY) ERR_INVALID_PARAMS)
    (asserts! (and (>= quality-score MIN_QUALITY_SCORE) (&lt;= quality-score MAX_QUALITY_SCORE)) ERR_INVALID_PARAMS)
    (asserts! (is-some (map-get? art-styles art-style)) ERR_ART_STYLE_NOT_FOUND)
    (asserts! (>= stx-amount quantity) ERR_INSUFFICIENT_QUANTITY)
    
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    
    (let ((collection-id (var-get next-collection-id)))
      (map-set artwork-collections collection-id {
        creator: tx-sender,
        quantity: quantity,
        quality-score: quality-score,
        active: true,
        art-style: art-style,
        total-transfers: u0,
        created-at: u0
      })
      
      (var-set next-collection-id (+ collection-id u1))
      (ok collection-id))))

(define-public (retire-collection (collection-id uint))
  (let ((collection (unwrap! (map-get? artwork-collections collection-id) ERR_COLLECTION_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator collection)) ERR_NOT_AUTHORIZED)
    (ok (map-set artwork-collections collection-id (merge collection {active: false})))))

(define-public (reactivate-collection (collection-id uint))
  (let ((collection (unwrap! (map-get? artwork-collections collection-id) ERR_COLLECTION_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator collection)) ERR_NOT_AUTHORIZED)
    (ok (map-set artwork-collections collection-id (merge collection {active: true})))))

(define-public (add-collection-quantity (collection-id uint) (additional-quantity uint))
  (let ((collection (unwrap! (map-get? artwork-collections collection-id) ERR_COLLECTION_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get creator collection)) ERR_NOT_AUTHORIZED)
    (asserts! (> additional-quantity u0) ERR_INVALID_PARAMS)
    
    (try! (stx-transfer? additional-quantity tx-sender (as-contract tx-sender)))
    
    (ok (map-set artwork-collections collection-id 
      (merge collection {quantity: (+ (get quantity collection) additional-quantity)})))))

;; Helper function to check specialization match
(define-private (check-specialization-match (art-style uint) (specializations (list 10 uint)))
  (or
    (and (> (len specializations) u0) (is-eq art-style (unwrap-panic (element-at specializations u0))))
    (and (> (len specializations) u1) (is-eq art-style (unwrap-panic (element-at specializations u1))))
    (and (> (len specializations) u2) (is-eq art-style (unwrap-panic (element-at specializations u2))))
    (and (> (len specializations) u3) (is-eq art-style (unwrap-panic (element-at specializations u3))))
    (and (> (len specializations) u4) (is-eq art-style (unwrap-panic (element-at specializations u4))))
    (and (> (len specializations) u5) (is-eq art-style (unwrap-panic (element-at specializations u5))))
    (and (> (len specializations) u6) (is-eq art-style (unwrap-panic (element-at specializations u6))))
    (and (> (len specializations) u7) (is-eq art-style (unwrap-panic (element-at specializations u7))))
    (and (> (len specializations) u8) (is-eq art-style (unwrap-panic (element-at specializations u8))))
    (and (> (len specializations) u9) (is-eq art-style (unwrap-panic (element-at specializations u9))))
  ))

;; Provenance tracking
(define-public (verify-provenance (collection-id uint))
  (let (
    (artist-profile (unwrap! (map-get? artist-profiles tx-sender) ERR_ARTIST_NOT_FOUND))
    (collection (unwrap! (map-get? artwork-collections collection-id) ERR_COLLECTION_NOT_FOUND))
    (provenance-key {collector: tx-sender, collection-id: collection-id})
  )
    (asserts! (get active artist-profile) ERR_ARTIST_NOT_FOUND)
    (asserts! (get active collection) ERR_COLLECTION_NOT_FOUND)
    (asserts! (is-none (map-get? provenance-records provenance-key)) ERR_ALREADY_COLLECTED)
    (asserts! (>= (get quantity collection) (get quality-score collection)) ERR_INSUFFICIENT_QUANTITY)
    (asserts! (check-specialization-match (get art-style collection) (get specializations artist-profile)) ERR_INVALID_PARAMS)
    
    (let (
      (quality-score (get quality-score collection))
      (network-fee (/ (* quality-score (var-get network-fee-percent)) u100))
      (artist-reputation (- quality-score network-fee))
    )
      (map-set provenance-records provenance-key {timestamp: u0, verified: true})
      
      (map-set artwork-collections collection-id (merge collection {
        quantity: (- (get quantity collection) quality-score),
        total-transfers: (+ (get total-transfers collection) u1)
      }))
      
      (map-set artist-profiles tx-sender (merge artist-profile {
        reputation: (+ (get reputation artist-profile) artist-reputation),
        transaction-count: (+ (get transaction-count artist-profile) u1)
      }))
      
      (var-set network-balance (+ (var-get network-balance) network-fee))
      
      (ok artist-reputation))))

(define-public (claim-reputation)
  (let ((artist-profile (unwrap! (map-get? artist-profiles tx-sender) ERR_ARTIST_NOT_FOUND)))
    (let ((reputation (get reputation artist-profile)))
      (asserts! (> reputation u0) ERR_INSUFFICIENT_QUANTITY)
      
      (try! (as-contract (stx-transfer? reputation tx-sender tx-sender)))
      
      (map-set artist-profiles tx-sender (merge artist-profile {
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
(define-private (is-valid-art-style (art-style uint))
  (is-some (map-get? art-styles art-style)))

(define-private (count-valid-art-styles (specializations (list 10 uint)))
  (+ 
    (if (and (> (len specializations) u0) (is-valid-art-style (unwrap-panic (element-at specializations u0)))) u1 u0)
    (if (and (> (len specializations) u1) (is-valid-art-style (unwrap-panic (element-at specializations u1)))) u1 u0)
    (if (and (> (len specializations) u2) (is-valid-art-style (unwrap-panic (element-at specializations u2)))) u1 u0)
    (if (and (> (len specializations) u3) (is-valid-art-style (unwrap-panic (element-at specializations u3)))) u1 u0)
    (if (and (> (len specializations) u4) (is-valid-art-style (unwrap-panic (element-at specializations u4)))) u1 u0)
    (if (and (> (len specializations) u5) (is-valid-art-style (unwrap-panic (element-at specializations u5)))) u1 u0)
    (if (and (> (len specializations) u6) (is-valid-art-style (unwrap-panic (element-at specializations u6)))) u1 u0)
    (if (and (> (len specializations) u7) (is-valid-art-style (unwrap-panic (element-at specializations u7)))) u1 u0)
    (if (and (> (len specializations) u8) (is-valid-art-style (unwrap-panic (element-at specializations u8)))) u1 u0)
    (if (and (> (len specializations) u9) (is-valid-art-style (unwrap-panic (element-at specializations u9)))) u1 u0)
  ))

(define-private (validate-specializations (specializations (list 10 uint)))
  (let ((specs-len (len specializations)))
    (and 
      (> specs-len u0)
      (&lt;= specs-len u10)
      (is-eq specs-len (count-valid-art-styles specializations)))))

;; Read-only functions
(define-read-only (get-artist-profile (artist principal))
  (map-get? artist-profiles artist))

(define-read-only (get-collection (collection-id uint))
  (map-get? artwork-collections collection-id))

(define-read-only (get-art-style (style-id uint))
  (map-get? art-styles style-id))

(define-read-only (get-network-fee)
  (var-get network-fee-percent))

(define-read-only (get-network-balance)
  (var-get network-balance))

(define-read-only (get-provenance-record (collector principal) (collection-id uint))
  (map-get? provenance-records {collector: collector, collection-id: collection-id}))
