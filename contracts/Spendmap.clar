(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-RECORD-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-PRINCIPAL (err u106))
(define-constant ERR-EXPIRED (err u107))
(define-constant ERR-NOT-VERIFIED (err u108))

(define-fungible-token access-token)

(define-data-var next-record-id uint u1)
(define-data-var token-price uint u1000000)
(define-data-var verification-threshold uint u3)
(define-data-var contract-paused bool false)

(define-map spending-records
  { record-id: uint }
  {
    constituency: (string-ascii 50),
    department: (string-ascii 50),
    amount: uint,
    description: (string-ascii 200),
    date: uint,
    submitter: principal,
    verified: bool,
    verification-count: uint,
    block-submitted: uint
  }
)

(define-map authorized-submitters
  { user: principal }
  { 
    authorized: bool,
    reputation: uint,
    records-submitted: uint
  }
)

(define-map record-verifications
  { record-id: uint, verifier: principal }
  { verified: bool, timestamp: uint }
)

(define-map access-passes
  { holder: principal }
  {
    tokens: uint,
    expiry: uint,
    tier: uint
  }
)

(define-map constituency-totals
  { constituency: (string-ascii 50) }
  { total-spent: uint, record-count: uint }
)

(define-read-only (get-contract-info)
  {
    owner: CONTRACT-OWNER,
    paused: (var-get contract-paused),
    token-price: (var-get token-price),
    verification-threshold: (var-get verification-threshold),
    total-records: (- (var-get next-record-id) u1)
  }
)

(define-read-only (get-spending-record (record-id uint))
  (map-get? spending-records { record-id: record-id })
)

(define-read-only (get-user-access (user principal))
  (map-get? access-passes { holder: user })
)

(define-read-only (get-submitter-info (user principal))
  (map-get? authorized-submitters { user: user })
)

(define-read-only (get-constituency-total (constituency (string-ascii 50)))
  (map-get? constituency-totals { constituency: constituency })
)

(define-read-only (has-access (user principal))
  (match (map-get? access-passes { holder: user })
    pass-info (and 
                (> (get tokens pass-info) u0)
                (> (get expiry pass-info) stacks-block-height))
    false
  )
)

(define-read-only (is-authorized-submitter (user principal))
  (match (map-get? authorized-submitters { user: user })
    submitter-info (get authorized submitter-info)
    false
  )
)

(define-public (purchase-access (tier uint))
  (let (
    (cost (* (var-get token-price) tier))
    (expiry (+ stacks-block-height (* tier u1440)))
  )
    (asserts! (> tier u0) ERR-INVALID-AMOUNT)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (try! (stx-transfer? cost tx-sender CONTRACT-OWNER))
    
    (map-set access-passes
      { holder: tx-sender }
      {
        tokens: (* tier u10),
        expiry: expiry,
        tier: tier
      }
    )
    
    (ok true)
  )
)

(define-public (authorize-submitter (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-submitters
      { user: user }
      {
        authorized: true,
        reputation: u100,
        records-submitted: u0
      }
    )
    
    (ok true)
  )
)

(define-public (submit-spending-record 
  (constituency (string-ascii 50))
  (department (string-ascii 50))
  (amount uint)
  (description (string-ascii 200))
  (date uint)
)
  (let (
    (record-id (var-get next-record-id))
    (submitter-info (unwrap! (map-get? authorized-submitters { user: tx-sender }) ERR-NOT-AUTHORIZED))
  )
    (asserts! (get authorized submitter-info) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set spending-records
      { record-id: record-id }
      {
        constituency: constituency,
        department: department,
        amount: amount,
        description: description,
        date: date,
        submitter: tx-sender,
        verified: false,
        verification-count: u0,
        block-submitted: stacks-block-height
      }
    )
    
    (map-set authorized-submitters
      { user: tx-sender }
      (merge submitter-info { records-submitted: (+ (get records-submitted submitter-info) u1) })
    )
    
    (match (map-get? constituency-totals { constituency: constituency })
      existing (map-set constituency-totals
                 { constituency: constituency }
                 {
                   total-spent: (+ (get total-spent existing) amount),
                   record-count: (+ (get record-count existing) u1)
                 })
      (map-set constituency-totals
        { constituency: constituency }
        { total-spent: amount, record-count: u1 })
    )
    
    (var-set next-record-id (+ record-id u1))
    (ok record-id)
  )
)

(define-public (verify-record (record-id uint))
  (let (
    (record-info (unwrap! (map-get? spending-records { record-id: record-id }) ERR-RECORD-NOT-FOUND))
    (access-info (unwrap! (map-get? access-passes { holder: tx-sender }) ERR-NOT-AUTHORIZED))
  )
    (asserts! (has-access tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? record-verifications { record-id: record-id, verifier: tx-sender })) ERR-ALREADY-EXISTS)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set record-verifications
      { record-id: record-id, verifier: tx-sender }
      { verified: true, timestamp: stacks-block-height }
    )
    
    (let (
      (new-verification-count (+ (get verification-count record-info) u1))
      (is-now-verified (>= new-verification-count (var-get verification-threshold)))
    )
      (map-set spending-records
        { record-id: record-id }
        (merge record-info {
          verification-count: new-verification-count,
          verified: is-now-verified
        })
      )
      
      (map-set access-passes
        { holder: tx-sender }
        (merge access-info { tokens: (- (get tokens access-info) u1) })
      )
      
      (ok is-now-verified)
    )
  )
)

(define-public (set-token-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-price u0) ERR-INVALID-AMOUNT)
    
    (var-set token-price new-price)
    (ok true)
  )
)

(define-public (set-verification-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-threshold u0) ERR-INVALID-AMOUNT)
    
    (var-set verification-threshold new-threshold)
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (withdraw-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (stx-transfer? amount (as-contract tx-sender) CONTRACT-OWNER)
  )
)


