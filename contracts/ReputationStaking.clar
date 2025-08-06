;; Reputation Staking & Validator Network Contract
;; Enables users to stake reputation and become validators in the network

(define-map validator-stakes
    { validator: principal }
    {
        staked-reputation: uint,
        stake-height: uint,
        unlock-height: uint,
        active: bool,
        rewards-earned: uint,
        validation-count: uint,
        slash-count: uint
    }
)

(define-map validation-tasks
    { task-id: uint }
    {
        task-type: (string-ascii 30),
        target-principal: principal,
        required-validators: uint,
        completed-validations: uint,
        reward-pool: uint,
        created-height: uint,
        deadline: uint,
        status: (string-ascii 20),
        creator: principal
    }
)

(define-map validator-responses
    { task-id: uint, validator: principal }
    {
        response: bool,
        submitted-height: uint,
        stake-weight: uint
    }
)

(define-map delegation-bonds
    { delegator: principal, validator: principal }
    {
        bonded-reputation: uint,
        share-percentage: uint,
        bond-height: uint,
        unlock-height: uint,
        rewards-claimed: uint
    }
)

(define-map validator-metadata
    { validator: principal }
    {
        commission-rate: uint,
        description: (string-utf8 200),
        website: (optional (string-ascii 100)),
        accepting-delegations: bool,
        total-delegated: uint,
        max-delegation: uint
    }
)

(define-map slashing-events
    { slash-id: uint }
    {
        validator: principal,
        amount: uint,
        reason: (string-ascii 100),
        height: uint,
        reporter: principal,
        resolved: bool
    }
)

(define-map consensus-rounds
    { round-id: uint }
    {
        proposal-data: (string-ascii 200),
        participating-validators: uint,
        consensus-reached: bool,
        round-start: uint,
        round-end: uint,
        final-result: (optional bool)
    }
)

(define-map validator-round-votes
    { round-id: uint, validator: principal }
    {
        vote: bool,
        vote-weight: uint,
        timestamp: uint
    }
)

(define-data-var min-stake-amount uint u500)
(define-data-var min-stake-period uint u1000)
(define-data-var max-validators uint u50)
(define-data-var task-counter uint u0)
(define-data-var active-validator-count uint u0)
(define-data-var base-reward-rate uint u10)
(define-data-var slash-counter uint u0)
(define-data-var round-counter uint u0)
(define-data-var consensus-threshold uint u66)

(define-public (become-validator (stake-amount uint) (lock-period uint))
    (let (
        (user-rep (get-user-reputation tx-sender))
        (current-validators (var-get active-validator-count))
    )
        (asserts! (>= user-rep stake-amount) (err u1))
        (asserts! (>= stake-amount (var-get min-stake-amount)) (err u2))
        (asserts! (>= lock-period (var-get min-stake-period)) (err u3))
        (asserts! (< current-validators (var-get max-validators)) (err u4))
        (asserts! (is-none (map-get? validator-stakes { validator: tx-sender })) (err u5))
        
        (map-set validator-stakes
            { validator: tx-sender }
            {
                staked-reputation: stake-amount,
                stake-height: stacks-block-height,
                unlock-height: (+ stacks-block-height lock-period),
                active: true,
                rewards-earned: u0,
                validation-count: u0,
                slash-count: u0
            })
        
        (var-set active-validator-count (+ current-validators u1))
        
        (ok true)
    )
)

(define-public (setup-validator-profile 
    (commission uint) 
    (description (string-utf8 200)) 
    (website (optional (string-ascii 100)))
    (max-delegation uint))
    (let (
        (validator-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u1)))
    )
        (asserts! (get active validator-stake) (err u2))
        (asserts! (<= commission u100) (err u3))
        
        (ok (map-set validator-metadata
            { validator: tx-sender }
            {
                commission-rate: commission,
                description: description,
                website: website,
                accepting-delegations: true,
                total-delegated: u0,
                max-delegation: max-delegation
            }))
    )
)

(define-public (delegate-to-validator (validator principal) (amount uint) (lock-period uint))
    (let (
        (user-rep (get-user-reputation tx-sender))
        (validator-meta (unwrap! (map-get? validator-metadata { validator: validator }) (err u1)))
        (validator-stake (unwrap! (map-get? validator-stakes { validator: validator }) (err u2)))
        (current-delegation (default-to 
            { bonded-reputation: u0, share-percentage: u0, bond-height: u0, unlock-height: u0, rewards-claimed: u0 }
            (map-get? delegation-bonds { delegator: tx-sender, validator: validator })))
    )
        (asserts! (>= user-rep amount) (err u3))
        (asserts! (get active validator-stake) (err u4))
        (asserts! (get accepting-delegations validator-meta) (err u5))
        (asserts! (<= (+ (get total-delegated validator-meta) amount) (get max-delegation validator-meta)) (err u6))
        
        (let (
            (new-total-delegated (+ (get total-delegated validator-meta) amount))
            (share-percent (/ (* amount u100) new-total-delegated))
        )
            (map-set validator-metadata
                { validator: validator }
                (merge validator-meta { total-delegated: new-total-delegated }))
            
            (map-set delegation-bonds
                { delegator: tx-sender, validator: validator }
                {
                    bonded-reputation: (+ (get bonded-reputation current-delegation) amount),
                    share-percentage: share-percent,
                    bond-height: stacks-block-height,
                    unlock-height: (+ stacks-block-height lock-period),
                    rewards-claimed: (get rewards-claimed current-delegation)
                })
            
            (ok true)
        )
    )
)

(define-public (create-validation-task 
    (task-type (string-ascii 30)) 
    (target principal) 
    (required-validators uint)
    (reward-pool uint)
    (duration uint))
    (let (
        (new-task-id (+ (var-get task-counter) u1))
        (creator-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= creator-rep u200) (err u1))
        (asserts! (> required-validators u0) (err u2))
        (asserts! (<= required-validators (var-get active-validator-count)) (err u3))
        (asserts! (> reward-pool u0) (err u4))
        
        (var-set task-counter new-task-id)
        
        (ok (map-set validation-tasks
            { task-id: new-task-id }
            {
                task-type: task-type,
                target-principal: target,
                required-validators: required-validators,
                completed-validations: u0,
                reward-pool: reward-pool,
                created-height: stacks-block-height,
                deadline: (+ stacks-block-height duration),
                status: "pending",
                creator: tx-sender
            }))
    )
)

(define-public (submit-validation (task-id uint) (validation-result bool))
    (let (
        (task (unwrap! (map-get? validation-tasks { task-id: task-id }) (err u1)))
        (validator-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u2)))
    )
        (asserts! (get active validator-stake) (err u3))
        (asserts! (is-eq (get status task) "pending") (err u4))
        (asserts! (<= stacks-block-height (get deadline task)) (err u5))
        (asserts! (is-none (map-get? validator-responses { task-id: task-id, validator: tx-sender })) (err u6))
        
        (map-set validator-responses
            { task-id: task-id, validator: tx-sender }
            {
                response: validation-result,
                submitted-height: stacks-block-height,
                stake-weight: (get staked-reputation validator-stake)
            })
        
        (let (
            (new-completed (+ (get completed-validations task) u1))
        )
            (map-set validation-tasks
                { task-id: task-id }
                (merge task { completed-validations: new-completed }))
            
            (map-set validator-stakes
                { validator: tx-sender }
                (merge validator-stake { validation-count: (+ (get validation-count validator-stake) u1) }))
            
            (ok true)
        )
    )
)

(define-public (finalize-validation-task (task-id uint))
    (let (
        (task (unwrap! (map-get? validation-tasks { task-id: task-id }) (err u1)))
    )
        (asserts! (is-eq (get status task) "pending") (err u2))
        (asserts! (>= (get completed-validations task) (get required-validators task)) (err u3))
        
        (map-set validation-tasks
            { task-id: task-id }
            (merge task { status: "completed" }))
        
        (ok true)
    )
)

(define-public (distribute-validation-rewards (task-id uint))
    (let (
        (task (unwrap! (map-get? validation-tasks { task-id: task-id }) (err u1)))
        (caller-response (unwrap! (map-get? validator-responses { task-id: task-id, validator: tx-sender }) (err u2)))
        (caller-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u3)))
    )
        (asserts! (is-eq (get status task) "completed") (err u4))
        
        (let (
            (base-reward (/ (get reward-pool task) (get completed-validations task)))
            (weight-bonus (/ (* base-reward (get stake-weight caller-response)) u1000))
            (total-reward (+ base-reward weight-bonus))
        )
            (map-set validator-stakes
                { validator: tx-sender }
                (merge caller-stake { rewards-earned: (+ (get rewards-earned caller-stake) total-reward) }))
            
            (ok total-reward)
        )
    )
)

(define-public (initiate-consensus-round (proposal-data (string-ascii 200)) (duration uint))
    (let (
        (new-round-id (+ (var-get round-counter) u1))
        (caller-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u1)))
    )
        (asserts! (get active caller-stake) (err u2))
        (asserts! (>= (get staked-reputation caller-stake) u1000) (err u3))
        
        (var-set round-counter new-round-id)
        
        (ok (map-set consensus-rounds
            { round-id: new-round-id }
            {
                proposal-data: proposal-data,
                participating-validators: u0,
                consensus-reached: false,
                round-start: stacks-block-height,
                round-end: (+ stacks-block-height duration),
                final-result: none
            }))
    )
)

(define-public (cast-consensus-vote (round-id uint) (vote bool))
    (let (
        (round (unwrap! (map-get? consensus-rounds { round-id: round-id }) (err u1)))
        (validator-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u2)))
    )
        (asserts! (get active validator-stake) (err u3))
        (asserts! (<= stacks-block-height (get round-end round)) (err u4))
        (asserts! (not (get consensus-reached round)) (err u5))
        (asserts! (is-none (map-get? validator-round-votes { round-id: round-id, validator: tx-sender })) (err u6))
        
        (map-set validator-round-votes
            { round-id: round-id, validator: tx-sender }
            {
                vote: vote,
                vote-weight: (get staked-reputation validator-stake),
                timestamp: stacks-block-height
            })
        
        (map-set consensus-rounds
            { round-id: round-id }
            (merge round { participating-validators: (+ (get participating-validators round) u1) }))
        
        (ok true)
    )
)

(define-public (slash-validator (validator principal) (amount uint) (reason (string-ascii 100)))
    (let (
        (reporter-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u1)))
        (target-stake (unwrap! (map-get? validator-stakes { validator: validator }) (err u2)))
        (new-slash-id (+ (var-get slash-counter) u1))
    )
        (asserts! (get active reporter-stake) (err u3))
        (asserts! (>= (get staked-reputation reporter-stake) u1000) (err u4))
        (asserts! (<= amount (get staked-reputation target-stake)) (err u5))
        (asserts! (not (is-eq tx-sender validator)) (err u6))
        
        (var-set slash-counter new-slash-id)
        
        (map-set slashing-events
            { slash-id: new-slash-id }
            {
                validator: validator,
                amount: amount,
                reason: reason,
                height: stacks-block-height,
                reporter: tx-sender,
                resolved: false
            })
        
        (ok new-slash-id)
    )
)

(define-public (unstake-reputation)
    (let (
        (validator-stake (unwrap! (map-get? validator-stakes { validator: tx-sender }) (err u1)))
    )
        (asserts! (get active validator-stake) (err u2))
        (asserts! (>= stacks-block-height (get unlock-height validator-stake)) (err u3))
        (asserts! (is-eq (get slash-count validator-stake) u0) (err u4))
        
        (map-set validator-stakes
            { validator: tx-sender }
            (merge validator-stake { active: false }))
        
        (var-set active-validator-count (- (var-get active-validator-count) u1))
        
        (ok (get staked-reputation validator-stake))
    )
)

(define-public (claim-delegation-rewards (validator principal))
    (let (
        (delegation (unwrap! (map-get? delegation-bonds { delegator: tx-sender, validator: validator }) (err u1)))
        (validator-stake (unwrap! (map-get? validator-stakes { validator: validator }) (err u2)))
        (validator-meta (unwrap! (map-get? validator-metadata { validator: validator }) (err u3)))
    )
        (asserts! (>= stacks-block-height (get unlock-height delegation)) (err u4))
        
        (let (
            (total-rewards (get rewards-earned validator-stake))
            (commission (/ (* total-rewards (get commission-rate validator-meta)) u100))
            (delegator-share (/ (* (- total-rewards commission) (get share-percentage delegation)) u100))
        )
            (map-set delegation-bonds
                { delegator: tx-sender, validator: validator }
                (merge delegation { rewards-claimed: (+ (get rewards-claimed delegation) delegator-share) }))
            
            (ok delegator-share)
        )
    )
)

(define-private (get-user-reputation (user principal))
    (match (contract-call? .RBG get-user-reputation user)
        rep (get score rep)
        u0
    )
)

(define-read-only (get-validator-info (validator principal))
    (map-get? validator-stakes { validator: validator })
)

(define-read-only (get-validator-metadata (validator principal))
    (map-get? validator-metadata { validator: validator })
)

(define-read-only (get-validation-task (task-id uint))
    (map-get? validation-tasks { task-id: task-id })
)

(define-read-only (get-delegation-info (delegator principal) (validator principal))
    (map-get? delegation-bonds { delegator: delegator, validator: validator })
)

(define-read-only (get-consensus-round (round-id uint))
    (map-get? consensus-rounds { round-id: round-id })
)

(define-read-only (get-network-stats)
    {
        active-validators: (var-get active-validator-count),
        total-tasks: (var-get task-counter),
        consensus-rounds: (var-get round-counter),
        min-stake: (var-get min-stake-amount)
    }
)


