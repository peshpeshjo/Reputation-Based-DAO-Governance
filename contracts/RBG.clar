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



(define-data-var emergency-threshold uint u800)

(define-public (emergency-cancel-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err u3))))
        (asserts! (>= (get-reputation tx-sender) (var-get emergency-threshold)) (err u1))
        (ok (map-set proposals 
            { proposal-id: proposal-id }
            (merge proposal { status: "cancelled" })))
    )
)




(define-map boost-events 
    { event-id: uint } 
    { multiplier: uint, end-block: uint })

(define-data-var boost-event-count uint u0)

(define-public (create-boost-event (multiplier uint) (duration uint))
    (let ((new-id (+ (var-get boost-event-count) u1)))
        (asserts! (>= (get-reputation tx-sender) u500) (err u1))
        (ok (map-set boost-events 
            { event-id: new-id }
            { multiplier: multiplier, end-block: (+ stacks-block-height duration) }))
    )
)




(define-map category-requirements
    { category: (string-ascii 20) }
    { min-reputation: uint })

(define-public (set-category-requirement (category (string-ascii 20)) (min-rep uint))
    (begin
        (asserts! (>= (get-reputation tx-sender) u1000) (err u1))
        (ok (map-set category-requirements 
            { category: category }
            { min-reputation: min-rep }))
    )
)



;; Define milestone levels and rewards
(define-map reputation-milestones 
    { level: uint }
    { threshold: uint, bonus: uint })

(define-public (check-milestone (user principal))
    (let ((user-rep (get-reputation user)))
        (match (map-get? reputation-milestones 
            { level: (/ user-rep u100) })
            milestone (begin
                (unwrap! (reward-participation user) (err u1))
                (ok true))
            (ok false))))



(define-map voting-power-multiplier
    { user: principal }
    { last-vote: uint, multiplier: uint })

(define-public (calculate-voting-power (user principal))
    (let ((blocks-since-last-vote (- stacks-block-height 
            (default-to u0 (get last-vote (map-get? voting-power-multiplier { user: user }))))))
        (ok (map-set voting-power-multiplier
            { user: user }
            { 
                last-vote: stacks-block-height,
                multiplier: (+ u100 (/ blocks-since-last-vote u100))
            }))))




(define-map proposal-challenges
    { proposal-id: uint }
    { challenger: principal, reason: (string-ascii 100), status: (string-ascii 10) })

(define-public (challenge-proposal (proposal-id uint) (reason (string-ascii 100)))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep u200) (err u1))
        (ok (map-set proposal-challenges
            { proposal-id: proposal-id }
            { challenger: tx-sender, reason: reason, status: "pending" }))))



(define-map reputation-loans
    { borrower: principal }
    { lender: principal, amount: uint, due-block: uint })

(define-public (lend-reputation (borrower principal) (amount uint) (duration uint))
    (let ((lender-rep (get-reputation tx-sender)))
        (asserts! (>= lender-rep amount) (err u1))
        (ok (map-set reputation-loans
            { borrower: borrower }
            { lender: tx-sender, amount: amount, due-block: (+ stacks-block-height duration) }))))




(define-map proposal-templates
    { template-id: uint }
    { 
        name: (string-ascii 20),
        description: (string-ascii 100),
        category: (string-ascii 20),
        duration: uint
    })

(define-public (create-template 
    (name (string-ascii 20))
    (description (string-ascii 100))
    (category (string-ascii 20))
    (duration uint))
    (let ((template-id (+ (var-get proposal-count) u1)))
        (ok (map-set proposal-templates
            { template-id: template-id }
            { 
                name: name,
                description: description,
                category: category,
                duration: duration
            }))))




(define-map reputation-recovery
    { user: principal }
    { tasks-completed: uint, recovery-amount: uint })

(define-public (complete-recovery-task (user principal))
    (let ((current-tasks (default-to 
            { tasks-completed: u0, recovery-amount: u0 }
            (map-get? reputation-recovery { user: user }))))
        (ok (map-set reputation-recovery
            { user: user }
            { 
                tasks-completed: (+ (get tasks-completed current-tasks) u1),
                recovery-amount: (+ (get recovery-amount current-tasks) u5)
            }))))


;; Define badge types and requirements
(define-map reputation-badges
    { user: principal }
    { badges: (list 10 (string-ascii 20)) })

(define-map badge-requirements
    { badge-name: (string-ascii 20) }
    { min-reputation: uint, min-proposals: uint })

(define-public (issue-badge (user principal) (badge-name (string-ascii 20)))
    (let (
        (user-rep (get-reputation user))
        (requirements (unwrap! (map-get? badge-requirements { badge-name: badge-name }) (err u1)))
        (current-badges (default-to { badges: (list) } (map-get? reputation-badges { user: user })))
    )
        (asserts! (>= user-rep (get min-reputation requirements)) (err u2))
        (ok (map-set reputation-badges
            { user: user }
            { badges: (unwrap! (as-max-len? (append (get badges current-badges) badge-name) u10) (err u3)) }))
    )
)

(define-map proposal-sponsors
    { proposal-id: uint }
    { sponsors: (list 5 principal), total-backing: uint })

(define-public (sponsor-proposal (proposal-id uint) (amount uint))
    (let (
        (user-rep (get-reputation tx-sender))
        (current-sponsors (default-to { sponsors: (list), total-backing: u0 } 
            (map-get? proposal-sponsors { proposal-id: proposal-id })))
    )
        (asserts! (>= user-rep amount) (err u1))
        (ok (map-set proposal-sponsors
            { proposal-id: proposal-id }
            {
                sponsors: (unwrap! (as-max-len? (append (get sponsors current-sponsors) tx-sender) u5) (err u2)),
                total-backing: (+ (get total-backing current-sponsors) amount)
            }))
    )
)


(define-map time-weighted-rep
    { user: principal }
    { last-active: uint, weight: uint })

(define-public (update-time-weight)
    (let (
        (current-data (default-to { last-active: u0, weight: u100 } 
            (map-get? time-weighted-rep { user: tx-sender })))
        (blocks-passed (- stacks-block-height (get last-active current-data)))
    )
        (ok (map-set time-weighted-rep
            { user: tx-sender }
            {
                last-active: stacks-block-height,
                weight: (+ u100 (/ blocks-passed u100))
            }))
    )
)


(define-map category-voting-rules
    { category: (string-ascii 20) }
    { min-rep: uint, voting-period: uint, approval-threshold: uint })

(define-public (set-category-rules 
    (category (string-ascii 20)) 
    (min-rep uint) 
    (voting-period uint)
    (threshold uint))
    (begin
        (asserts! (>= (get-reputation tx-sender) u1000) (err u1))
        (ok (map-set category-voting-rules
            { category: category }
            { min-rep: min-rep, voting-period: voting-period, approval-threshold: threshold }))
    )
)


(define-map staking-rewards
    { user: principal }
    { staked-amount: uint, start-block: uint, reward-rate: uint })

(define-public (stake-with-rewards (amount uint))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep amount) (err u1))
        (ok (map-set staking-rewards
            { user: tx-sender }
            { 
                staked-amount: amount,
                start-block: stacks-block-height,
                reward-rate: u5
            }))
    )
)


(define-map proposal-comments
    { proposal-id: uint, comment-id: uint }
    { author: principal, content: (string-utf8 500), timestamp: uint })

(define-data-var comment-count uint u0)

(define-public (add-comment (proposal-id uint) (content (string-utf8 500)))
    (let (
        (new-id (+ (var-get comment-count) u1))
        (user-rep (get-reputation tx-sender))
    )
        (asserts! (> user-rep u50) (err u1))
        (var-set comment-count new-id)
        (ok (map-set proposal-comments
            { proposal-id: proposal-id, comment-id: new-id }
            { 
                author: tx-sender,
                content: content,
                timestamp: stacks-block-height
            }))
    )
)

(define-map time-locked-delegations
    { delegator: principal }
    { delegate: principal, amount: uint, unlock-height: uint })

(define-public (delegate-with-timelock (delegate-to principal) (amount uint) (lock-period uint))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep amount) (err u1))
        (ok (map-set time-locked-delegations
            { delegator: tx-sender }
            { 
                delegate: delegate-to,
                amount: amount,
                unlock-height: (+ stacks-block-height lock-period)
            }))
    )
)
(define-map recovery-challenges
    { user: principal }
    { challenge-type: (string-ascii 20), target-score: uint, completed: bool })

(define-public (create-recovery-challenge (challenge-type (string-ascii 20)) (target uint))
    (let ((current-rep (get-reputation tx-sender)))
        (asserts! (< current-rep u50) (err u1))
        (ok (map-set recovery-challenges
            { user: tx-sender }
            { 
                challenge-type: challenge-type,
                target-score: target,
                completed: false
            }))
    )
)


(define-map boost-periods 
    { period-id: uint }
    { multiplier: uint, start: uint, end: uint, active: bool })

(define-data-var boost-period-count uint u0)

(define-public (create-boost-period (multiplier uint) (duration uint))
    (let ((new-id (+ (var-get boost-period-count) u1)))
        (map-set boost-periods
            { period-id: new-id }
            { 
                multiplier: multiplier,
                start: stacks-block-height,
                end: (+ stacks-block-height duration),
                active: true
            })
        (var-set boost-period-count new-id)
        (ok new-id)
    )
)


(define-map category-weights
    { category: (string-ascii 20) }
    { weight: uint })

(define-public (set-category-weight (category (string-ascii 20)) (weight uint))
    (begin
        (asserts! (>= (get-reputation tx-sender) u1000) (err u1))
        (ok (map-set category-weights 
            { category: category }
            { weight: weight }))
    )
)







(define-map reputation-levels
    { user: principal }
    { level: uint, xp: uint })

(define-data-var xp-per-level uint u100)

(define-public (update-user-level (user principal))
    (let (
        (current-rep (get-reputation user))
        (current-level (default-to { level: u1, xp: u0 } 
            (map-get? reputation-levels { user: user })))
    )
        (ok (map-set reputation-levels
            { user: user }
            { 
                level: (+ (get level current-level) u1),
                xp: (+ (get xp current-level) current-rep)
            }))
    )
)

(define-map proposal-endorsements
    { proposal-id: uint }
    { endorsers: (list 10 principal), weight: uint })

(define-public (endorse-proposal (proposal-id uint))
    (let (
        (user-rep (get-reputation tx-sender))
        (current-endorsements (default-to { endorsers: (list), weight: u0 }
            (map-get? proposal-endorsements { proposal-id: proposal-id })))
    )
        (ok (map-set proposal-endorsements
            { proposal-id: proposal-id }
            {
                endorsers: (unwrap! (as-max-len? 
                    (append (get endorsers current-endorsements) tx-sender) u10) (err u2)),
                weight: (+ (get weight current-endorsements) user-rep)
            }))
    )
)


(define-map recovery-missions
    { mission-id: uint }
    { task: (string-ascii 50), reward: uint, completed: bool })

(define-data-var mission-count uint u0)

(define-public (create-recovery-mission (task (string-ascii 50)) (reward uint))
    (let ((new-id (+ (var-get mission-count) u1)))
        (map-set recovery-missions
            { mission-id: new-id }
            { task: task, reward: reward, completed: false })
        (var-set mission-count new-id)
        (ok new-id)
    )
)

(define-map locked-delegations
    { from: principal }
    { to: principal, amount: uint, unlock-height: uint })

(define-public (delegate-locked (to principal) (amount uint) (blocks uint))
    (let ((user-rep (get-reputation tx-sender)))
        (asserts! (>= user-rep amount) (err u1))
        (ok (map-set locked-delegations
            { from: tx-sender }
            { 
                to: to,
                amount: amount,
                unlock-height: (+ stacks-block-height blocks)
            }))
    )
)


(define-map user-achievements-extended
    { user: principal }
    { 
        proposals-created: uint,
        votes-cast: uint,
        endorsements: uint,
        reputation-score: uint
    })

(define-public (update-user-achievements (user principal))
    (let (
        (current-data (default-to 
            { proposals-created: u0, votes-cast: u0, endorsements: u0, reputation-score: u0 }
            (map-get? user-achievements-extended { user: user })))
    )
        (ok (map-set user-achievements-extended
            { user: user }
            { 
                proposals-created: (+ (get proposals-created current-data) u1),
                votes-cast: (get votes-cast current-data),
                endorsements: (get endorsements current-data),
                reputation-score: (get-reputation user)
            }))
    )
)