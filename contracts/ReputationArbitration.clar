;; Reputation Arbitration System Contract
;; Provides dispute resolution mechanisms for reputation-related issues

(define-map arbitration-cases
    { case-id: uint }
    {
        plaintiff: principal,
        defendant: principal,
        case-type: (string-ascii 30),
        description: (string-utf8 500),
        evidence-hash: (string-ascii 64),
        disputed-amount: uint,
        status: (string-ascii 20),
        created-height: uint,
        deadline: uint,
        arbitrator: (optional principal),
        ruling: (optional bool),
        compensation: uint,
        final: bool
    }
)

(define-map arbitrator-pool
    { arbitrator: principal }
    {
        reputation-threshold: uint,
        cases-handled: uint,
        successful-rulings: uint,
        available: bool,
        specialization: (string-ascii 30),
        fee-rate: uint
    }
)

(define-map case-votes
    { case-id: uint, voter: principal }
    {
        vote: bool,
        reasoning: (string-utf8 200),
        vote-weight: uint,
        timestamp: uint
    }
)

(define-map arbitrator-applications
    { applicant: principal }
    {
        application-text: (string-utf8 300),
        specialization: (string-ascii 30),
        experience: uint,
        endorsements: uint,
        status: (string-ascii 15),
        applied-height: uint
    }
)

(define-map dispute-appeals
    { appeal-id: uint }
    {
        original-case: uint,
        appellant: principal,
        appeal-reason: (string-utf8 300),
        new-evidence: (optional (string-ascii 64)),
        status: (string-ascii 15),
        appeal-fee: uint,
        filed-height: uint
    }
)

(define-map community-jury
    { case-id: uint, juror: principal }
    {
        selected: bool,
        vote-cast: bool,
        final-vote: (optional bool),
        selection-height: uint
    }
)

(define-data-var case-counter uint u0)
(define-data-var appeal-counter uint u0)
(define-data-var min-arbitrator-reputation uint u1000)
(define-data-var case-fee uint u50)
(define-data-var appeal-fee uint u100)
(define-data-var jury-size uint u5)
(define-data-var case-timeout uint u2016) ;; ~2 weeks
(define-data-var min-evidence-stake uint u25)

(define-public (file-arbitration-case 
    (defendant principal)
    (case-type (string-ascii 30))
    (description (string-utf8 500))
    (evidence-hash (string-ascii 64))
    (disputed-amount uint))
    (let (
        (plaintiff-rep (get-user-reputation tx-sender))
        (new-case-id (+ (var-get case-counter) u1))
    )
        (asserts! (>= plaintiff-rep (var-get case-fee)) (err u1))
        (asserts! (> disputed-amount u0) (err u2))
        (asserts! (not (is-eq tx-sender defendant)) (err u3))
        
        (var-set case-counter new-case-id)
        
        (map-set arbitration-cases
            { case-id: new-case-id }
            {
                plaintiff: tx-sender,
                defendant: defendant,
                case-type: case-type,
                description: description,
                evidence-hash: evidence-hash,
                disputed-amount: disputed-amount,
                status: "pending",
                created-height: stacks-block-height,
                deadline: (+ stacks-block-height (var-get case-timeout)),
                arbitrator: none,
                ruling: none,
                compensation: u0,
                final: false
            })
        
        (ok new-case-id)
    )
)

(define-public (apply-for-arbitrator 
    (application-text (string-utf8 300))
    (specialization (string-ascii 30))
    (experience uint))
    (let (
        (applicant-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= applicant-rep (var-get min-arbitrator-reputation)) (err u1))
        (asserts! (is-none (map-get? arbitrator-pool { arbitrator: tx-sender })) (err u2))
        
        (ok (map-set arbitrator-applications
            { applicant: tx-sender }
            {
                application-text: application-text,
                specialization: specialization,
                experience: experience,
                endorsements: u0,
                status: "pending",
                applied-height: stacks-block-height
            }))
    )
)

(define-public (approve-arbitrator (applicant principal))
    (let (
        (application (unwrap! (map-get? arbitrator-applications { applicant: applicant }) (err u1)))
        (approver-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= approver-rep u1500) (err u2))
        (asserts! (is-eq (get status application) "pending") (err u3))
        
        (map-set arbitrator-applications
            { applicant: applicant }
            (merge application { status: "approved" }))
        
        (ok (map-set arbitrator-pool
            { arbitrator: applicant }
            {
                reputation-threshold: (var-get min-arbitrator-reputation),
                cases-handled: u0,
                successful-rulings: u0,
                available: true,
                specialization: (get specialization application),
                fee-rate: u20
            }))
    )
)

(define-public (assign-arbitrator (case-id uint))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
        (arbitrator-rep (get-user-reputation tx-sender))
        (arbitrator-data (unwrap! (map-get? arbitrator-pool { arbitrator: tx-sender }) (err u2)))
    )
        (asserts! (is-eq (get status case-data) "pending") (err u3))
        (asserts! (get available arbitrator-data) (err u4))
        (asserts! (is-none (get arbitrator case-data)) (err u5))
        
        (map-set arbitration-cases
            { case-id: case-id }
            (merge case-data { 
                arbitrator: (some tx-sender),
                status: "assigned"
            }))
        
        (ok true)
    )
)

(define-public (submit-ruling (case-id uint) (ruling bool) (compensation uint))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
        (arbitrator-data (unwrap! (map-get? arbitrator-pool { arbitrator: tx-sender }) (err u2)))
    )
        (asserts! (is-eq (some tx-sender) (get arbitrator case-data)) (err u3))
        (asserts! (is-eq (get status case-data) "assigned") (err u4))
        (asserts! (<= stacks-block-height (get deadline case-data)) (err u5))
        (asserts! (<= compensation (get disputed-amount case-data)) (err u6))
        
        (map-set arbitration-cases
            { case-id: case-id }
            (merge case-data {
                ruling: (some ruling),
                compensation: compensation,
                status: "ruled",
                final: true
            }))
        
        (map-set arbitrator-pool
            { arbitrator: tx-sender }
            (merge arbitrator-data {
                cases-handled: (+ (get cases-handled arbitrator-data) u1),
                successful-rulings: (+ (get successful-rulings arbitrator-data) u1)
            }))
        
        (ok true)
    )
)

(define-public (file-appeal 
    (case-id uint)
    (appeal-reason (string-utf8 300))
    (new-evidence (optional (string-ascii 64))))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
        (appellant-rep (get-user-reputation tx-sender))
        (new-appeal-id (+ (var-get appeal-counter) u1))
    )
        (asserts! (is-eq (get status case-data) "ruled") (err u2))
        (asserts! (or (is-eq tx-sender (get plaintiff case-data)) 
                      (is-eq tx-sender (get defendant case-data))) (err u3))
        (asserts! (>= appellant-rep (var-get appeal-fee)) (err u4))
        
        (var-set appeal-counter new-appeal-id)
        
        (map-set dispute-appeals
            { appeal-id: new-appeal-id }
            {
                original-case: case-id,
                appellant: tx-sender,
                appeal-reason: appeal-reason,
                new-evidence: new-evidence,
                status: "pending",
                appeal-fee: (var-get appeal-fee),
                filed-height: stacks-block-height
            })
        
        (map-set arbitration-cases
            { case-id: case-id }
            (merge case-data { status: "appealed", final: false }))
        
        (ok new-appeal-id)
    )
)

(define-public (select-jury-members (case-id uint))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
        (selector-rep (get-user-reputation tx-sender))
    )
        (asserts! (>= selector-rep u500) (err u2))
        (asserts! (is-eq (get status case-data) "appealed") (err u3))
        
        (ok true)
    )
)

(define-public (cast-jury-vote (case-id uint) (vote bool) (reasoning (string-utf8 200)))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
        (juror-rep (get-user-reputation tx-sender))
        (jury-member (map-get? community-jury { case-id: case-id, juror: tx-sender }))
    )
        (asserts! (is-some jury-member) (err u2))
        (asserts! (not (get vote-cast (unwrap-panic jury-member))) (err u3))
        (asserts! (>= juror-rep u100) (err u4))
        
        (map-set case-votes
            { case-id: case-id, voter: tx-sender }
            {
                vote: vote,
                reasoning: reasoning,
                vote-weight: juror-rep,
                timestamp: stacks-block-height
            })
        
        (map-set community-jury
            { case-id: case-id, juror: tx-sender }
            (merge (unwrap-panic jury-member) { 
                vote-cast: true,
                final-vote: (some vote)
            }))
        
        (ok true)
    )
)

(define-public (finalize-jury-decision (case-id uint))
    (let (
        (case-data (unwrap! (map-get? arbitration-cases { case-id: case-id }) (err u1)))
    )
        (asserts! (is-eq (get status case-data) "appealed") (err u2))
        
        (map-set arbitration-cases
            { case-id: case-id }
            (merge case-data { 
                status: "jury-decided",
                final: true
            }))
        
        (ok true)
    )
)

(define-private (get-user-reputation (user principal))
    (match (contract-call? .RBG get-user-reputation user)
        rep (get score rep)
        u0
    )
)

(define-read-only (get-case-details (case-id uint))
    (map-get? arbitration-cases { case-id: case-id })
)

(define-read-only (get-arbitrator-info (arbitrator principal))
    (map-get? arbitrator-pool { arbitrator: arbitrator })
)

(define-read-only (get-appeal-details (appeal-id uint))
    (map-get? dispute-appeals { appeal-id: appeal-id })
)

(define-read-only (get-case-vote (case-id uint) (voter principal))
    (map-get? case-votes { case-id: case-id, voter: voter })
)

(define-read-only (get-system-stats)
    {
        total-cases: (var-get case-counter),
        total-appeals: (var-get appeal-counter),
        case-fee: (var-get case-fee),
        appeal-fee: (var-get appeal-fee),
        min-arbitrator-rep: (var-get min-arbitrator-reputation)
    }
)
