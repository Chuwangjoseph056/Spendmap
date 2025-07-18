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
(define-constant ERR-BUDGET-EXCEEDED (err u109))
(define-constant ERR-INVALID-BUDGET (err u110))
(define-constant ERR-BUDGET-NOT-FOUND (err u111))
(define-constant ERR-INVALID-THRESHOLD (err u112))

(define-fungible-token access-token)

(define-data-var next-record-id uint u1)
(define-data-var token-price uint u1000000)
(define-data-var verification-threshold uint u3)
(define-data-var contract-paused bool false)
(define-data-var next-budget-id uint u1)
(define-data-var alert-threshold-percentage uint u80)

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

(define-map budget-allocations
  { budget-id: uint }
  {
    constituency: (string-ascii 50),
    department: (string-ascii 50),
    allocated-amount: uint,
    spent-amount: uint,
    fiscal-year: uint,
    created-at: uint,
    status: (string-ascii 20),
    alert-triggered: bool
  }
)

(define-map budget-alerts
  { alert-id: uint }
  {
    budget-id: uint,
    alert-type: (string-ascii 30),
    percentage-used: uint,
    triggered-at: uint,
    acknowledged: bool
  }
)

(define-map fiscal-year-budgets
  { constituency: (string-ascii 50), fiscal-year: uint }
  { total-allocated: uint, total-spent: uint, budget-count: uint }
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

(define-read-only (get-budget-allocation (budget-id uint))
  (map-get? budget-allocations { budget-id: budget-id })
)

(define-read-only (get-budget-alerts (budget-id uint))
  (map-get? budget-alerts { alert-id: budget-id })
)

(define-read-only (get-fiscal-year-budget (constituency (string-ascii 50)) (fiscal-year uint))
  (map-get? fiscal-year-budgets { constituency: constituency, fiscal-year: fiscal-year })
)

(define-read-only (get-budget-utilization (budget-id uint))
  (match (map-get? budget-allocations { budget-id: budget-id })
    budget-info (let (
      (spent (get spent-amount budget-info))
      (allocated (get allocated-amount budget-info))
      (percentage (if (> allocated u0) (/ (* spent u100) allocated) u0))
    )
      (ok {
        budget-id: budget-id,
        allocated: allocated,
        spent: spent,
        remaining: (- allocated spent),
        percentage-used: percentage,
        is-overspent: (> spent allocated)
      })
    )
    ERR-BUDGET-NOT-FOUND
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

(define-public (create-budget-allocation 
  (constituency (string-ascii 50))
  (department (string-ascii 50))
  (allocated-amount uint)
  (fiscal-year uint)
)
  (let (
    (budget-id (var-get next-budget-id))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> allocated-amount u0) ERR-INVALID-BUDGET)
    (asserts! (> fiscal-year u0) ERR-INVALID-BUDGET)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set budget-allocations
      { budget-id: budget-id }
      {
        constituency: constituency,
        department: department,
        allocated-amount: allocated-amount,
        spent-amount: u0,
        fiscal-year: fiscal-year,
        created-at: stacks-block-height,
        status: "active",
        alert-triggered: false
      }
    )
    
    (match (map-get? fiscal-year-budgets { constituency: constituency, fiscal-year: fiscal-year })
      existing (map-set fiscal-year-budgets
                 { constituency: constituency, fiscal-year: fiscal-year }
                 {
                   total-allocated: (+ (get total-allocated existing) allocated-amount),
                   total-spent: (get total-spent existing),
                   budget-count: (+ (get budget-count existing) u1)
                 })
      (map-set fiscal-year-budgets
        { constituency: constituency, fiscal-year: fiscal-year }
        { total-allocated: allocated-amount, total-spent: u0, budget-count: u1 })
    )
    
    (var-set next-budget-id (+ budget-id u1))
    (ok budget-id)
  )
)

(define-public (update-budget-spending (budget-id uint) (spending-amount uint))
  (let (
    (budget-info (unwrap! (map-get? budget-allocations { budget-id: budget-id }) ERR-BUDGET-NOT-FOUND))
    (new-spent (+ (get spent-amount budget-info) spending-amount))
    (allocated (get allocated-amount budget-info))
    (percentage-used (if (> allocated u0) (/ (* new-spent u100) allocated) u0))
    (alert-threshold (var-get alert-threshold-percentage))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> spending-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set budget-allocations
      { budget-id: budget-id }
      (merge budget-info { spent-amount: new-spent })
    )
    
    (match (map-get? fiscal-year-budgets { constituency: (get constituency budget-info), fiscal-year: (get fiscal-year budget-info) })
      existing (map-set fiscal-year-budgets
                 { constituency: (get constituency budget-info), fiscal-year: (get fiscal-year budget-info) }
                 (merge existing { total-spent: (+ (get total-spent existing) spending-amount) }))
      false
    )
    
    (if (and (>= percentage-used alert-threshold) (not (get alert-triggered budget-info)))
      (begin
        (unwrap-panic (trigger-budget-alert budget-id percentage-used))
        (map-set budget-allocations
          { budget-id: budget-id }
          (merge budget-info { spent-amount: new-spent, alert-triggered: true })
        )
      )
      true
    )
    
    (ok new-spent)
  )
)

(define-public (trigger-budget-alert (budget-id uint) (percentage-used uint))
  (let (
    (alert-id (var-get next-budget-id))
    (alert-type (if (>= percentage-used u100) "BUDGET_EXCEEDED" "BUDGET_WARNING"))
  )
    (map-set budget-alerts
      { alert-id: alert-id }
      {
        budget-id: budget-id,
        alert-type: alert-type,
        percentage-used: percentage-used,
        triggered-at: stacks-block-height,
        acknowledged: false
      }
    )
    
    (ok alert-id)
  )
)

(define-public (acknowledge-budget-alert (alert-id uint))
  (let (
    (alert-info (unwrap! (map-get? budget-alerts { alert-id: alert-id }) ERR-RECORD-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set budget-alerts
      { alert-id: alert-id }
      (merge alert-info { acknowledged: true })
    )
    
    (ok true)
  )
)

(define-public (set-alert-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (and (> new-threshold u0) (<= new-threshold u100)) ERR-INVALID-THRESHOLD)
    
    (var-set alert-threshold-percentage new-threshold)
    (ok true)
  )
)

(define-public (close-budget (budget-id uint))
  (let (
    (budget-info (unwrap! (map-get? budget-allocations { budget-id: budget-id }) ERR-BUDGET-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    
    (map-set budget-allocations
      { budget-id: budget-id }
      (merge budget-info { status: "closed" })
    )
    
    (ok true)
  )
)


