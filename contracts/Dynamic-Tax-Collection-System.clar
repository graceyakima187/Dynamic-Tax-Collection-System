(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INVALID_TAX_RATE (err u103))
(define-constant ERR_TRANSFER_FAILED (err u104))
(define-constant ERR_INVALID_RECIPIENT (err u105))
(define-constant ERR_DISTRIBUTION_FAILED (err u106))

(define-constant ERR_INVALID_SCHEDULE_BLOCK (err u110))
(define-constant ERR_NO_SCHEDULED_RATE (err u111))

(define-data-var next-schedule-id uint u1)

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

(define-constant ERR_ACCOUNT_FROZEN (err u112))
(define-constant ERR_ALREADY_FROZEN (err u113))
(define-constant ERR_NOT_FROZEN (err u114))

(define-data-var total-frozen-accounts uint u0)
(define-data-var freeze-enabled bool true)

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

(define-constant ERR_INSUFFICIENT_REBATE_POINTS (err u107))
(define-constant ERR_INVALID_REBATE_AMOUNT (err u108))
(define-constant ERR_REBATE_DISABLED (err u109))

(define-data-var rebate-rate uint u100)
(define-data-var rebate-enabled bool true)
(define-data-var max-rebate-discount uint u5000)

(define-map user-rebate-points principal uint)
(define-map user-rebate-history principal {earned: uint, redeemed: uint, transactions: uint})

(define-read-only (get-rebate-points (user principal))
  (default-to u0 (map-get? user-rebate-points user))
)

(define-read-only (get-rebate-history (user principal))
  (default-to {earned: u0, redeemed: u0, transactions: u0} (map-get? user-rebate-history user))
)

(define-read-only (min (a uint) (b uint))
  (if (<= a b) a b)
)

(define-read-only (calculate-rebate-discount (points uint) (tax-amount uint))
  (let ((discount-rate (min (/ points u100) (var-get max-rebate-discount))))
    (min (/ (* tax-amount discount-rate) u10000) tax-amount)
  )
)

(define-read-only (get-rebate-rate)
  (var-get rebate-rate)
)

(define-public (earn-rebate-points (user principal) (transaction-amount uint))
  (let (
    (points-to-earn (/ (* transaction-amount (var-get rebate-rate)) u10000))
    (current-points (get-rebate-points user))
    (current-history (get-rebate-history user))
  )
    (asserts! (var-get rebate-enabled) ERR_REBATE_DISABLED)
    (asserts! (> points-to-earn u0) ERR_INVALID_REBATE_AMOUNT)
    
    (map-set user-rebate-points user (+ current-points points-to-earn))
    (map-set user-rebate-history user {
      earned: (+ (get earned current-history) points-to-earn),
      redeemed: (get redeemed current-history),
      transactions: (+ (get transactions current-history) u1)
    })
    (ok points-to-earn)
  )
)

(define-public (redeem-rebate-points (points uint))
  (let (
    (current-points (get-rebate-points tx-sender))
    (current-history (get-rebate-history tx-sender))
  )
    (asserts! (var-get rebate-enabled) ERR_REBATE_DISABLED)
    (asserts! (> points u0) ERR_INVALID_REBATE_AMOUNT)
    (asserts! (>= current-points points) ERR_INSUFFICIENT_REBATE_POINTS)
    
    (map-set user-rebate-points tx-sender (- current-points points))
    (map-set user-rebate-history tx-sender {
      earned: (get earned current-history),
      redeemed: (+ (get redeemed current-history) points),
      transactions: (get transactions current-history)
    })
    (ok points)
  )
)

(define-public (set-rebate-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_REBATE_AMOUNT)
    (var-set rebate-rate new-rate)
    (ok new-rate)
  )
)

(define-public (toggle-rebate-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set rebate-enabled (not (var-get rebate-enabled)))
    (ok (var-get rebate-enabled))
  )
)


(define-map scheduled-rates uint {rate: uint, activation-block: uint, active: bool})
(define-map schedule-by-block uint uint)

(define-read-only (get-scheduled-rate (schedule-id uint))
  (map-get? scheduled-rates schedule-id)
)

(define-read-only (get-next-rate-change)
  (let ((current-block stacks-block-height))
    (fold check-next-activation (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) none)
  )
)

(define-read-only (check-next-activation (schedule-id uint) (current-result (optional {rate: uint, activation-block: uint})))
  (match (map-get? scheduled-rates schedule-id)
    schedule-data
    (if (and (get active schedule-data) 
             (> (get activation-block schedule-data) stacks-block-height)
             (or (is-none current-result)
                 (< (get activation-block schedule-data) (get activation-block (unwrap-panic current-result)))))
      (some {rate: (get rate schedule-data), activation-block: (get activation-block schedule-data)})
      current-result)
    current-result
  )
)

(define-public (schedule-tax-rate-change (new-rate uint) (activation-block uint))
  (let ((schedule-id (var-get next-schedule-id)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_TAX_RATE)
    (asserts! (> activation-block stacks-block-height) ERR_INVALID_SCHEDULE_BLOCK)
    
    (map-set scheduled-rates schedule-id {
      rate: new-rate,
      activation-block: activation-block,
      active: true
    })
    (map-set schedule-by-block activation-block schedule-id)
    (var-set next-schedule-id (+ schedule-id u1))
    (ok schedule-id)
  )
)

(define-public (cancel-scheduled-rate (schedule-id uint))
  (match (map-get? scheduled-rates schedule-id)
    schedule-data
    (begin
      (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
      (asserts! (get active schedule-data) ERR_NO_SCHEDULED_RATE)
      (map-set scheduled-rates schedule-id (merge schedule-data {active: false}))
      (ok true)
    )
    ERR_NO_SCHEDULED_RATE
  )
)

(define-private (check-and-apply-scheduled-rates)
  (let ((current-block stacks-block-height))
    (match (map-get? schedule-by-block current-block)
      schedule-id
      (match (map-get? scheduled-rates schedule-id)
        schedule-data
        (if (and (get active schedule-data) (>= current-block (get activation-block schedule-data)))
          (begin
            (var-set tax-rate (get rate schedule-data))
            (map-set scheduled-rates schedule-id (merge schedule-data {active: false}))
            true
          )
          true
        )
        true
      )
      true
    )
  )
)

(define-public (trigger-scheduled-rate-check)
  (begin
    (check-and-apply-scheduled-rates)
    (ok true)
  )
)


(define-map frozen-accounts principal {frozen: bool, freeze-block: uint, reason: (string-ascii 50)})
(define-map freeze-history uint {account: principal, action: (string-ascii 10), block: uint, reason: (string-ascii 50)})
(define-data-var freeze-counter uint u0)

(define-read-only (is-account-frozen (account principal))
  (match (map-get? frozen-accounts account)
    freeze-data (get frozen freeze-data)
    false
  )
)

(define-read-only (get-freeze-details (account principal))
  (map-get? frozen-accounts account)
)

(define-read-only (get-freeze-stats)
  {
    total-frozen: (var-get total-frozen-accounts),
    freeze-enabled: (var-get freeze-enabled),
    total-freeze-actions: (var-get freeze-counter)
  }
)

(define-read-only (get-freeze-history-entry (entry-id uint))
  (map-get? freeze-history entry-id)
)

(define-public (freeze-account (account principal) (reason (string-ascii 50)))
  (let ((freeze-id (+ (var-get freeze-counter) u1)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (var-get freeze-enabled) ERR_UNAUTHORIZED)
    (asserts! (not (is-account-frozen account)) ERR_ALREADY_FROZEN)
    
    (map-set frozen-accounts account {
      frozen: true,
      freeze-block: stacks-block-height,
      reason: reason
    })
    (map-set freeze-history freeze-id {
      account: account,
      action: "freeze",
      block: stacks-block-height,
      reason: reason
    })
    (var-set freeze-counter freeze-id)
    (var-set total-frozen-accounts (+ (var-get total-frozen-accounts) u1))
    (ok true)
  )
)

(define-public (unfreeze-account (account principal) (reason (string-ascii 50)))
  (let ((freeze-id (+ (var-get freeze-counter) u1)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-account-frozen account) ERR_NOT_FROZEN)
    
    (map-delete frozen-accounts account)
    (map-set freeze-history freeze-id {
      account: account,
      action: "unfreeze",
      block: stacks-block-height,
      reason: reason
    })
    (var-set freeze-counter freeze-id)
    (var-set total-frozen-accounts (- (var-get total-frozen-accounts) u1))
    (ok true)
  )
)

(define-public (toggle-freeze-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set freeze-enabled (not (var-get freeze-enabled)))
    (ok (var-get freeze-enabled))
  )
)