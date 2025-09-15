(define-map insurance-pools
    { pool-id: uint }
    {
        name: (string-ascii 50),
        total-coverage: uint,
        total-contributions: uint,
        max-claim: uint,
        premium-rate: uint,
        active: bool,
        created-height: uint
    }
)

(define-map user-policies
    { user: principal, pool-id: uint }
    {
        coverage-amount: uint,
        premium-paid: uint,
        last-payment: uint,
        active: bool,
        claims-made: uint
    }
)

(define-map insurance-claims
    { claim-id: uint }
    {
        claimant: principal,
        pool-id: uint,
        amount: uint,
        reason: (string-utf8 200),
        status: (string-ascii 20),
        filed-height: uint,
        validator: (optional principal),
        votes-for: uint,
        votes-against: uint
    }
)

(define-map pool-contributions
    { user: principal, pool-id: uint }
    {
        contributed-reputation: uint,
        share-percentage: uint,
        last-contribution: uint
    }
)

(define-data-var pool-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var min-pool-size uint u1000)
(define-data-var claim-validation-period uint u144)

(define-public (create-insurance-pool
    (name (string-ascii 50))
    (max-claim uint)
    (premium-rate uint))
    (let (
        (new-pool-id (+ (var-get pool-counter) u1))
        (creator-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= creator-rep u500) (err u1))
        (asserts! (> max-claim u0) (err u2))
        (asserts! (<= premium-rate u100) (err u3))
        
        (var-set pool-counter new-pool-id)
        
        (ok (map-set insurance-pools
            { pool-id: new-pool-id }
            {
                name: name,
                total-coverage: u0,
                total-contributions: u0,
                max-claim: max-claim,
                premium-rate: premium-rate,
                active: true,
                created-height: stacks-block-height
            }))
    )
)

(define-public (contribute-to-pool (pool-id uint) (reputation-amount uint))
    (let (
        (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) (err u1)))
        (contributor-rep (get-user-reputation tx-sender))
        (current-contribution (default-to 
            { contributed-reputation: u0, share-percentage: u0, last-contribution: u0 }
            (map-get? pool-contributions { user: tx-sender, pool-id: pool-id })))
    )
        (asserts! (get active pool) (err u2))
        (asserts! (>= contributor-rep reputation-amount) (err u3))
        (asserts! (> reputation-amount u0) (err u4))
        
        (let (
            (new-total-contributions (+ (get total-contributions pool) reputation-amount))
            (new-share (/ (* reputation-amount u100) new-total-contributions))
        )
            (map-set insurance-pools
                { pool-id: pool-id }
                (merge pool { total-contributions: new-total-contributions }))
            
            (map-set pool-contributions
                { user: tx-sender, pool-id: pool-id }
                {
                    contributed-reputation: (+ (get contributed-reputation current-contribution) reputation-amount),
                    share-percentage: new-share,
                    last-contribution: stacks-block-height
                })
            
            (ok true)
        )
    )
)

(define-public (purchase-policy 
    (pool-id uint) 
    (coverage-amount uint))
    (let (
        (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) (err u1)))
        (user-rep (get-user-reputation tx-sender))
        (premium-cost (/ (* coverage-amount (get premium-rate pool)) u100))
    )
        (asserts! (get active pool) (err u2))
        (asserts! (<= coverage-amount (get max-claim pool)) (err u3))
        (asserts! (>= user-rep premium-cost) (err u4))
        (asserts! (>= (get total-contributions pool) (var-get min-pool-size)) (err u5))
        
        (ok (map-set user-policies
            { user: tx-sender, pool-id: pool-id }
            {
                coverage-amount: coverage-amount,
                premium-paid: premium-cost,
                last-payment: stacks-block-height,
                active: true,
                claims-made: u0
            }))
    )
)

(define-public (file-claim 
    (pool-id uint) 
    (amount uint) 
    (reason (string-utf8 200)))
    (let (
        (policy (unwrap! (map-get? user-policies { user: tx-sender, pool-id: pool-id }) (err u1)))
        (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) (err u2)))
        (new-claim-id (+ (var-get claim-counter) u1))
    )
        (asserts! (get active policy) (err u3))
        (asserts! (<= amount (get coverage-amount policy)) (err u4))
        (asserts! (< (get claims-made policy) u3) (err u5))
        
        (var-set claim-counter new-claim-id)
        
        (ok (map-set insurance-claims
            { claim-id: new-claim-id }
            {
                claimant: tx-sender,
                pool-id: pool-id,
                amount: amount,
                reason: reason,
                status: "pending",
                filed-height: stacks-block-height,
                validator: none,
                votes-for: u0,
                votes-against: u0
            }))
    )
)

(define-public (validate-claim (claim-id uint) (approve bool))
    (let (
        (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) (err u1)))
        (validator-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= validator-rep u200) (err u2))
        (asserts! (is-eq (get status claim) "pending") (err u3))
        (asserts! (not (is-eq tx-sender (get claimant claim))) (err u4))
        
        (map-set insurance-claims
            { claim-id: claim-id }
            (merge claim {
                validator: (some tx-sender),
                votes-for: (if approve (+ (get votes-for claim) validator-rep) (get votes-for claim)),
                votes-against: (if approve (get votes-against claim) (+ (get votes-against claim) validator-rep))
            }))
        
        (ok true)
    )
)

(define-public (process-claim (claim-id uint))
    (let (
        (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) (err u1)))
        (pool (unwrap! (map-get? insurance-pools { pool-id: (get pool-id claim) }) (err u2)))
        (policy (unwrap! (map-get? user-policies 
            { user: (get claimant claim), pool-id: (get pool-id claim) }) (err u3)))
        (validation-deadline (+ (get filed-height claim) (var-get claim-validation-period)))
    )
        (asserts! (>= stacks-block-height validation-deadline) (err u4))
        (asserts! (is-eq (get status claim) "pending") (err u5))
        
        (if (> (get votes-for claim) (get votes-against claim))
            (begin
                (map-set insurance-claims
                    { claim-id: claim-id }
                    (merge claim { status: "approved" }))
                
                (map-set user-policies
                    { user: (get claimant claim), pool-id: (get pool-id claim) }
                    (merge policy { claims-made: (+ (get claims-made policy) u1) }))
                
                (ok true)
            )
            (begin
                (map-set insurance-claims
                    { claim-id: claim-id }
                    (merge claim { status: "rejected" }))
                (ok false)
            )
        )
    )
)

(define-public (distribute-rewards (pool-id uint))
    (let (
        (pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) (err u1)))
        (caller-contribution (unwrap! (map-get? pool-contributions 
            { user: tx-sender, pool-id: pool-id }) (err u2)))
        (reward-amount (/ (* (get contributed-reputation caller-contribution) u5) u100))
    )
        (asserts! (> (get contributed-reputation caller-contribution) u0) (err u3))
        (asserts! (> (- stacks-block-height (get last-contribution caller-contribution)) u1000) (err u4))
        
        (ok reward-amount)
    )
)

(define-private (get-user-reputation (user principal))
    (match (contract-call? .RBG get-user-reputation user)
        rep (get score rep)
        u0
    )
)

(define-read-only (get-pool-info (pool-id uint))
    (map-get? insurance-pools { pool-id: pool-id })
)

(define-read-only (get-user-policy (user principal) (pool-id uint))
    (map-get? user-policies { user: user, pool-id: pool-id })
)

(define-read-only (get-claim-details (claim-id uint))
    (map-get? insurance-claims { claim-id: claim-id })
)

(define-read-only (get-contribution-details (user principal) (pool-id uint))
    (map-get? pool-contributions { user: user, pool-id: pool-id })
)

(define-read-only (calculate-premium (pool-id uint) (coverage-amount uint))
    (match (map-get? insurance-pools { pool-id: pool-id })
        pool (/ (* coverage-amount (get premium-rate pool)) u100)
        u0
    )
)
