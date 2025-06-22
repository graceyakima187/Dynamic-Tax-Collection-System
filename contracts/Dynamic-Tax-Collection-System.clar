(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INVALID_TAX_RATE (err u103))
(define-constant ERR_TRANSFER_FAILED (err u104))
(define-constant ERR_INVALID_RECIPIENT (err u105))
(define-constant ERR_DISTRIBUTION_FAILED (err u106))

(define-data-var tax-rate uint u250)
(define-data-var treasury-balance uint u0)
(define-data-var total-collected uint u0)
(define-data-var distribution-enabled bool true)
(define-data-var min-distribution-amount uint u1000000)

(define-map user-balances principal uint)
(define-map tax-exemptions principal bool)
(define-map beneficiaries principal uint)
(define-map transaction-history uint {sender: principal, recipient: principal, amount: uint, tax-collected: uint, block-height: uint})

(define-data-var transaction-counter uint u0)
(define-data-var last-distribution-block uint u0)
(define-data-var total-beneficiaries uint u0)

(define-read-only (get-tax-rate)
  (var-get tax-rate)
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-total-collected)
  (var-get total-collected)
)

(define-read-only (is-tax-exempt (user principal))
  (default-to false (map-get? tax-exemptions user))
)

(define-read-only (get-beneficiary-share (beneficiary principal))
  (default-to u0 (map-get? beneficiaries beneficiary))
)

(define-read-only (get-transaction-details (tx-id uint))
  (map-get? transaction-history tx-id)
)

(define-read-only (calculate-tax (amount uint))
  (/ (* amount (var-get tax-rate)) u10000)
)

(define-read-only (get-net-amount (amount uint))
  (- amount (calculate-tax amount))
)

(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set user-balances tx-sender (+ (get-user-balance tx-sender) amount))
    (ok amount)
  )
)

(define-public (transfer (recipient principal) (amount uint))
  (let (
    (sender-balance (get-user-balance tx-sender))
    (tax-amount (if (is-tax-exempt tx-sender) u0 (calculate-tax amount)))
    (net-amount (- amount tax-amount))
    (total-required (+ net-amount tax-amount))
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= sender-balance total-required) ERR_INSUFFICIENT_BALANCE)
    (asserts! (not (is-eq tx-sender recipient)) ERR_INVALID_RECIPIENT)
    
    (map-set user-balances tx-sender (- sender-balance total-required))
    (map-set user-balances recipient (+ (get-user-balance recipient) net-amount))
    
    (if (> tax-amount u0)
      (begin
        (var-set treasury-balance (+ (var-get treasury-balance) tax-amount))
        (var-set total-collected (+ (var-get total-collected) tax-amount))
      )
      true
    )
    
    (let ((tx-id (+ (var-get transaction-counter) u1)))
      (var-set transaction-counter tx-id)
      (map-set transaction-history tx-id {
        sender: tx-sender,
        recipient: recipient,
        amount: amount,
        tax-collected: tax-amount,
        block-height: stacks-block-height
      })
    )
    
    (ok {transferred: net-amount, tax-collected: tax-amount})
  )
)

(define-public (withdraw (amount uint))
  (let ((user-balance (get-user-balance tx-sender)))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    (map-set user-balances tx-sender (- user-balance amount))
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (ok amount)
  )
)

(define-public (set-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_TAX_RATE)
    (var-set tax-rate new-rate)
    (ok new-rate)
  )
)

(define-public (add-tax-exemption (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set tax-exemptions user true)
    (ok true)
  )
)

(define-public (remove-tax-exemption (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete tax-exemptions user)
    (ok true)
  )
)

(define-public (add-beneficiary (beneficiary principal) (share uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> share u0) ERR_INVALID_AMOUNT)
    (asserts! (<= share u10000) ERR_INVALID_AMOUNT)
    
    (if (is-none (map-get? beneficiaries beneficiary))
      (var-set total-beneficiaries (+ (var-get total-beneficiaries) u1))
      true
    )
    
    (map-set beneficiaries beneficiary share)
    (ok share)
  )
)

(define-public (remove-beneficiary (beneficiary principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (if (is-some (map-get? beneficiaries beneficiary))
      (begin
        (map-delete beneficiaries beneficiary)
        (var-set total-beneficiaries (- (var-get total-beneficiaries) u1))
        (ok true)
      )
      (ok false)
    )
  )
)

(define-public (distribute-taxes)
  (let (
    (treasury-amount (var-get treasury-balance))
    (min-amount (var-get min-distribution-amount))
  )
    (asserts! (var-get distribution-enabled) ERR_UNAUTHORIZED)
    (asserts! (>= treasury-amount min-amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> (var-get total-beneficiaries) u0) ERR_DISTRIBUTION_FAILED)
    
    (var-set treasury-balance u0)
    (var-set last-distribution-block stacks-block-height)
    (ok treasury-amount)
  )
)

(define-public (claim-distribution (beneficiary principal))
  (let (
    (share (get-beneficiary-share beneficiary))
    (treasury-amount (var-get treasury-balance))
    (distribution-amount (/ (* treasury-amount share) u10000))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> share u0) ERR_UNAUTHORIZED)
    (asserts! (> distribution-amount u0) ERR_INSUFFICIENT_BALANCE)
    
    (try! (as-contract (stx-transfer? distribution-amount tx-sender beneficiary)))
    (ok distribution-amount)
  )
)

(define-public (emergency-withdraw)
  (let ((treasury-amount (var-get treasury-balance)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> treasury-amount u0) ERR_INSUFFICIENT_BALANCE)
    
    (var-set treasury-balance u0)
    (try! (as-contract (stx-transfer? treasury-amount tx-sender CONTRACT_OWNER)))
    (ok treasury-amount)
  )
)

(define-public (toggle-distribution)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set distribution-enabled (not (var-get distribution-enabled)))
    (ok (var-get distribution-enabled))
  )
)

(define-public (set-min-distribution-amount (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (var-set min-distribution-amount amount)
    (ok amount)
  )
)

(define-read-only (get-contract-stats)
  {
    tax-rate: (var-get tax-rate),
    treasury-balance: (var-get treasury-balance),
    total-collected: (var-get total-collected),
    total-transactions: (var-get transaction-counter),
    total-beneficiaries: (var-get total-beneficiaries),
    distribution-enabled: (var-get distribution-enabled),
    last-distribution-block: (var-get last-distribution-block)
  }
)
