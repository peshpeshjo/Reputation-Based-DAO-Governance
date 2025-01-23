;; reputation-dao.cft
;; Reputation-Based DAO Governance

(define-data-var min-reputation uint u100)
(define-map user-reputation { user: principal } { score: uint })
(define-map proposals 
    { proposal-id: uint } 
    { 
        title: (string-ascii 50),
        creator: principal,
        votes-for: uint,
        votes-against: uint,
        status: (string-ascii 10),
        end-block: uint
    }
)

(define-data-var proposal-count uint u0)

;; Initialize user reputation
(define-public (initialize-reputation)
    (begin
        (try! (is-dao-member))
        (ok (map-set user-reputation 
            { user: tx-sender }
            { score: u100 }))
    )
)

;; Create new proposal
(define-public (create-proposal (title (string-ascii 50)) (blocks uint))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep (var-get min-reputation)) (err u1))
        (let ((new-id (+ (var-get proposal-count) u1)))
            (map-set proposals
                { proposal-id: new-id }
                {
                    title: title,
                    creator: tx-sender,
                    votes-for: u0,
                    votes-against: u0,
                    status: "active",
                    end-block: (+ stacks-block-height blocks)
                }
            )
            (var-set proposal-count new-id)
            (ok new-id)
        )
    )
)

;; Vote on proposal
(define-public (vote (proposal-id uint) (vote-for bool))
    (let (
        (user-rep (get-reputation tx-sender))
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u3)))
    )
        (asserts! (> user-rep u0) (err u1))
        (asserts! (is-eq (get status proposal) "active") (err u2))
        (asserts! (<= stacks-block-height (get end-block proposal)) (err u4))
        
        (if vote-for
            (map-set proposals { proposal-id: proposal-id }
                (merge proposal { votes-for: (+ (get votes-for proposal) user-rep) }))
            (map-set proposals { proposal-id: proposal-id }
                (merge proposal { votes-against: (+ (get votes-against proposal) user-rep) }))
        )
        (ok true)
    )
)

;; Helper to get user reputation
(define-private (get-reputation (user principal))
    (default-to u0 (get score (map-get? user-reputation { user: user })))
)

;; Check if caller is DAO member
(define-private (is-dao-member)
    (if (is-some (map-get? user-reputation { user: tx-sender }))
        (ok true)
        (err u403)
    )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-user-reputation (user principal))
    (map-get? user-reputation { user: user })
)


(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u3)))
    )
        (asserts! (is-eq (get status proposal) "active") (err u2))
        (asserts! (> stacks-block-height (get end-block proposal)) (err u4))
        
        (if (> (get votes-for proposal) (get votes-against proposal))
            (begin
                (map-set proposals { proposal-id: proposal-id }
                    (merge proposal { status: "passed" }))
                (ok true))
            (begin
                (map-set proposals { proposal-id: proposal-id }
                    (merge proposal { status: "failed" }))
                (ok true))
        )
    )
)


(define-public (reward-participation (user principal))
    (let ((current-score (get-reputation user)))
        (map-set user-reputation 
            { user: user }
            { score: (+ current-score u1) })
        (ok true)
    )
)


(define-map proposal-metadata 
    { proposal-id: uint }
    {
        description: (string-utf8 500),
        url: (optional (string-utf8 256)),
        category: (string-ascii 20)
    }
)

(define-public (add-proposal-metadata 
    (proposal-id uint) 
    (description (string-utf8 500))
    (url (optional (string-utf8 256)))
    (category (string-ascii 20)))
    (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u3))))
        (asserts! (is-eq tx-sender (get creator proposal)) (err u5))
        (ok (map-set proposal-metadata
            { proposal-id: proposal-id }
            {
                description: description,
                url: url,
                category: category
            }))
    )
)


(define-data-var decay-rate uint u5)

(define-public (apply-reputation-decay (user principal))
    (let (
        (current-score (get-reputation user))
        (decay-amount (/ (* current-score (var-get decay-rate)) u100))
    )
        (asserts! (> current-score u0) (err u1))
        (map-set user-reputation
            { user: user }
            { score: (- current-score decay-amount) })
        (ok true)
    )
)



;; Add this map to track delegations
(define-map vote-delegations 
    { delegator: principal } 
    { delegate: principal })

(define-public (delegate-votes (delegate-to principal))
    (begin
        (asserts! (> (get-reputation tx-sender) u0) (err u1))
        (ok (map-set vote-delegations 
            { delegator: tx-sender }
            { delegate: delegate-to }))
    )
)



(define-map proposal-tags 
    { proposal-id: uint } 
    { tags: (list 5 (string-ascii 20)) })

(define-public (add-proposal-tags (proposal-id uint) (tags (list 5 (string-ascii 20))))
    (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u3))))
        (asserts! (is-eq tx-sender (get creator proposal)) (err u5))
        (ok (map-set proposal-tags { proposal-id: proposal-id } { tags: tags }))
    )
)



(define-map staked-reputation 
    { user: principal } 
    { amount: uint, lock-until: uint })

(define-public (stake-reputation (amount uint) (lock-blocks uint))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep amount) (err u1))
        (ok (map-set staked-reputation 
            { user: tx-sender }
            { amount: amount, lock-until: (+ stacks-block-height lock-blocks) }))
    )
)



(define-map user-achievements 
    { user: principal } 
    { proposals-created: uint, successful-votes: uint })

(define-public (update-achievements (user principal))
    (let ((current-achievements (default-to { proposals-created: u0, successful-votes: u0 }
            (map-get? user-achievements { user: user }))))
        (ok (map-set user-achievements 
            { user: user }
            { 
                proposals-created: (+ (get proposals-created current-achievements) u1),
                successful-votes: (get successful-votes current-achievements)
            }))
    )
)
