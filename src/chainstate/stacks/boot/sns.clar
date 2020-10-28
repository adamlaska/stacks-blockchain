;;;; Errors
(define-constant err-panic 0)
(define-constant err-namespace-preorder-not-found 1001)
(define-constant err-namespace-preorder-expired 1002)
(define-constant err-namespace-preorder-already-exists 1003)
(define-constant err-namespace-unavailable 1004)
(define-constant err-namespace-not-found 1005)
(define-constant err-namespace-already-exists 1006)
(define-constant err-namespace-not-launched 1007)
(define-constant err-namespace-price-function-invalid 1008)
(define-constant err-namespace-preorder-claimability-expired 1009)
(define-constant err-namespace-launchability-expired 1010)
(define-constant err-namespace-operation-unauthorized 1011)
(define-constant err-namespace-stx-burnt-insufficient 1012)
(define-constant err-namespace-blank 1013)
(define-constant err-namespace-already-launched 1014)
(define-constant err-namespace-hash-malformed 1015)
(define-constant err-namespace-charset-invalid 1016)

(define-constant err-name-preorder-not-found 2001)
(define-constant err-name-preorder-expired 2002)
(define-constant err-name-preorder-funds-insufficient 2003)
(define-constant err-name-unavailable 2004)
(define-constant err-name-operation-unauthorized 2006)
(define-constant err-name-stx-burnt-insufficient 2007)
(define-constant err-name-expired 2008)
(define-constant err-name-grace-period 2009)
(define-constant err-name-blank 2010)
(define-constant err-name-already-claimed 2011)
(define-constant err-name-claimability-expired 2012)
(define-constant err-name-not-found 2013)
(define-constant err-name-revoked 2014)
(define-constant err-name-transfer-failed 2015)
(define-constant err-name-preorder-already-exists 2016)
(define-constant err-name-hash-malformed 2017)
(define-constant err-name-preordered-before-namespace-launch 2018)
(define-constant err-name-not-resolvable 2019)
(define-constant err-name-could-not-be-minted 2020)
(define-constant err-name-could-not-be-transfered 2021)
(define-constant err-name-charset-invalid 2022)

(define-constant err-principal-already-associated 3001)
(define-constant err-insufficient-funds 4001)
(define-constant err-zonefile-not-found 5001)

;;;; Constants
(define-constant burn-address 'S0000000000000000000002AA028H)

;; TTL
;; todo(ludo): add real-life values
(define-constant namespace-preorder-claimability-ttl u10)
(define-constant namespace-launchability-ttl u10)
(define-constant name-preorder-claimability-ttl u10)
(define-constant name-grace-period-duration u5)

(define-constant attachments-inv-page-size u8)
(define-data-var attachments-inv-index-cursor uint u0)
(define-data-var attachments-inv-page-cursor uint u0)
(define-map attachments-inv 
    ((page uint) (index uint)) 
    ((content-hash (buff 20))))

;; Price tables
(define-constant namespace-prices-tiers (list
  u96000 
  u9600 u9600 
  u960 u960 u960 u960 
  u96 u96 u96 u96 u96 u96 u96 u96 u96 u96 u96 u96 u96))

;;;; Data
(define-map namespaces
  ((namespace (buff 19)))
  ((namespace-import principal)
   (revealed-at uint)
   (launched-at (optional uint))
   (namespace-version uint)
   (renewal-rule uint)
   (price-function (tuple 
    (buckets (list 16 uint)) 
    (base uint) 
    (coeff uint) 
    (nonalpha-discount uint) 
    (no-vowel-discount uint)))))

(define-map namespace-preorders
  ((hashed-salted-namespace (buff 20)) (buyer principal))
  ((created-at uint) (claimed bool) (stx-burned uint)))

(define-non-fungible-token names (tuple (name (buff 16)) (namespace (buff 19))))

(define-map owner-name ((owner principal)) ((name (buff 16)) (namespace (buff 19))))

(define-map name-properties
  ((name (buff 16)) (namespace (buff 19)))
  ((registered-at (optional uint))
   (imported-at (optional uint))
   (revoked-at (optional uint))
   (zonefile-hash (buff 20))))

(define-map name-preorders
  ((hashed-salted-fqn (buff 20)) (buyer principal))
  ((created-at uint) (claimed bool) (stx-burned uint)))

(define-private (min (a uint) (b uint))
  (if (<= a b) a b))

(define-private (max (a uint) (b uint))
  (if (> a b) a b))

(define-read-only (compute-namespace-price? (namespace (buff 19)))
  (let ((namespace-len (len namespace)))
    (asserts!
      (> namespace-len u0)
      (err err-namespace-blank))
    (ok (get value (fold 
      element-at 
      namespace-prices-tiers 
      (tuple (limit (min u8 namespace-len)) (cursor u0) (value u0)))))))

(define-private (element-at (i uint) (acc (tuple (limit uint) (cursor uint) (value uint))))
  (if (is-eq (get cursor acc) (get limit acc))
    (tuple (limit (get limit acc)) (cursor (+ u1 (get cursor acc))) (value i))
    (tuple (limit (get limit acc)) (cursor (+ u1 (get cursor acc))) (value (get value acc)))))
  
(define-private (get-exp-at-index (buckets (list 16 uint)) (index uint))
  (get value (fold element-at buckets (tuple (limit index) (cursor u0) (value u0)))))

(define-private (is-digit (char (buff 1)))
  (or 
    (is-eq char 0x30) ;; 0
    (is-eq char 0x31) ;; 1
    (is-eq char 0x32) ;; 2
    (is-eq char 0x33) ;; 3
    (is-eq char 0x34) ;; 4
    (is-eq char 0x35) ;; 5
    (is-eq char 0x36) ;; 6
    (is-eq char 0x37) ;; 7
    (is-eq char 0x38) ;; 8
    (is-eq char 0x39))) ;; 9

(define-private (is-downcased-alpha (char (buff 1)))
  (or 
    (is-eq char 0x61) ;; a
    (is-eq char 0x62) ;; b
    (is-eq char 0x63) ;; c
    (is-eq char 0x64) ;; d
    (is-eq char 0x65) ;; e
    (is-eq char 0x66) ;; f
    (is-eq char 0x67) ;; g
    (is-eq char 0x68) ;; h
    (is-eq char 0x69) ;; i
    (is-eq char 0x6a) ;; j
    (is-eq char 0x6b) ;; k
    (is-eq char 0x6c) ;; l
    (is-eq char 0x6d) ;; m
    (is-eq char 0x6e) ;; n
    (is-eq char 0x6f) ;; o
    (is-eq char 0x70) ;; p
    (is-eq char 0x71) ;; q
    (is-eq char 0x72) ;; r
    (is-eq char 0x73) ;; s
    (is-eq char 0x74) ;; t
    (is-eq char 0x75) ;; u
    (is-eq char 0x76) ;; v
    (is-eq char 0x77) ;; w
    (is-eq char 0x78) ;; x
    (is-eq char 0x79) ;; y
    (is-eq char 0x7a))) ;; z

(define-private (is-vowel (char (buff 1)))
  (or 
    (is-eq char 0x61) ;; a
    (is-eq char 0x65) ;; e
    (is-eq char 0x69) ;; i
    (is-eq char 0x6f) ;; o
    (is-eq char 0x75) ;; u
    (is-eq char 0x79))) ;; y

(define-private (is-special-char (char (buff 1)))
  (or 
    (is-eq char 0x2d) ;; -
    (is-eq char 0x5f))) ;; _

(define-private (is-char-valid (char (buff 1)))
  (or 
    (is-downcased-alpha char)
    (is-digit char)
    (is-special-char char)))

(define-private (is-nonalpha (char (buff 1)))
  (or 
    (is-digit char)
    (is-special-char char)))

(define-private (has-vowels-chars (name (buff 16)))
  (> (len (filter is-vowel name)) u0))

(define-private (has-nonalpha-chars (name (buff 16)))
  (> (len (filter is-nonalpha name)) u0))

(define-private (has-invalid-chars (name (buff 19)))
  (< (len (filter is-char-valid name)) (len name)))

(define-private (compute-name-price (name (buff 16))
                                    (price-function (tuple (buckets (list 16 uint)) (base uint) (coeff uint) (nonalpha-discount uint) (no-vowel-discount uint))))
  (let (
    (exponent (get-exp-at-index (get buckets price-function) (min u15 (- (len name) u1))))
    (no-vowel-discount (if (not (has-vowels-chars name)) (get no-vowel-discount price-function) u1))
    (nonalpha-discount (if (has-nonalpha-chars name) (get nonalpha-discount price-function) u1)))
    (*
      (/
        (*
          (get coeff price-function)
          (pow (get base price-function) exponent))
        (max nonalpha-discount no-vowel-discount))
      u10))) ;; 10 = name_cost (100) * "old_price_multiplier" (0.1) - todo(ludo): sort this out.

(define-private (is-name-lease-expired? (namespace (buff 19)) (name (buff 16)))
  (let (
    (namespace-props (unwrap! 
      (map-get? namespaces ((namespace namespace))) 
      (err err-namespace-not-found)))
    (name-props (unwrap! 
      (map-get? name-properties ((namespace namespace) (name name))) 
      (err err-name-not-found))))
    (if (and (is-none (get registered-at name-props)) (is-some (get imported-at name-props)))
      (ok false) ;; The name was imported and not launched - not subject to expiration, however should they expire if the namespace expire? - if so, todo(ludo)
      (let (      ;; The name was registered
        (registered-at (unwrap! 
          (get registered-at name-props) (err err-panic)))
        (lifetime 
          (get renewal-rule namespace-props)))
        (if (is-eq lifetime u0)
          (ok false)
          (ok (> block-height (+ lifetime registered-at))))))))

;; todo(ludo): should be refactored - based on (is-name-lease-expired?)
(define-read-only (is-name-in-grace-period? (namespace (buff 19)) (name (buff 16)))
  (let (
    (namespace-props (unwrap! 
      (map-get? namespaces ((namespace namespace))) 
      (err err-namespace-not-found)))
    (name-props (unwrap! 
      (map-get? name-properties ((namespace namespace) (name name))) 
      (err err-name-not-found))))
    (if (is-none (get registered-at name-props))
      (ok false) ;; The name was imported - not subject to expiration
      (let (      ;; The name was registered
        (registered-at (unwrap! 
          (get registered-at name-props) (err err-panic)))
        (lifetime 
          (get renewal-rule namespace-props)))
        (if (is-eq lifetime u0)
          (ok false)
          (ok (and 
            (> block-height (+ lifetime registered-at)) 
            (<= block-height (+ (+ lifetime registered-at) name-grace-period-duration)))))))))

(define-private (update-name-ownership? (namespace (buff 19)) 
                                        (name (buff 16)) 
                                        (from principal) 
                                        (to principal))
  (if (is-eq from to)
    (ok true)
    (begin
      (unwrap!
        (nft-transfer? names (tuple (name name) (namespace namespace)) from to)
        (err err-name-could-not-be-transfered))
      (map-delete owner-name ((owner from)))
      (map-set owner-name
        ((owner to))
        ((namespace namespace) (name name)))
      (ok true))))

(define-private (update-zonefile-and-props (namespace (buff 19))
                                           (name (buff 16))
                                           (registered-at (optional uint)) 
                                           (imported-at (optional uint)) 
                                           (revoked-at (optional uint)) 
                                           (zonefile-hash (buff 20)))
  (let 
    ((current-page (var-get attachments-inv-page-cursor))
    (current-index (var-get attachments-inv-index-cursor)))
    (let 
      ((next-page (if (is-eq (+ current-index u1) attachments-inv-page-size)
        (+ current-page u1)
        current-page))
      (next-index (mod (+ current-index u1) attachments-inv-page-size)))
      ;; Emit event used as a system hinter
      (print { 
        hash: zonefile-hash,
        page-index: next-page,
        position-in-page: next-index,
        metadata: {
          name: name,
          namespace: namespace,
        }})
      ;; Update attachments-inv
      (map-set attachments-inv
        ((page next-page) (index next-index))
        ((content-hash zonefile-hash)))
      ;; Update cursors
      (var-set attachments-inv-page-cursor next-page)
      (var-set attachments-inv-index-cursor next-index)
      (map-set name-properties
        ((namespace namespace) (name name))
        ((registered-at registered-at)
          (imported-at imported-at)
          (revoked-at revoked-at)
          (zonefile-hash zonefile-hash))))))

(define-read-only (get-attachments-inv-info)
  (ok { 
    pages-count: (+ (var-get attachments-inv-page-cursor) u1),
    last-page-len: (var-get attachments-inv-index-cursor),
    page-size: attachments-inv-page-size
  }))

;;;; NAMESPACES
;; NAMESPACE_PREORDER
;; This step registers the salted hash of the namespace with SNS nodes, and burns the requisite amount of cryptocurrency.
;; Additionally, this step proves to the SNS nodes that user has honored the SNS consensus rules by including a recent
;; consensus hash in the transaction.
;; Returns pre-order's expiration date (in blocks).
(define-public (namespace-preorder (hashed-salted-namespace (buff 20))
                                   (stx-to-burn uint))
  (let 
    ((former-preorder 
      (map-get? namespace-preorders ((hashed-salted-namespace hashed-salted-namespace) (buyer contract-caller)))))
    ;; Ensure eventual former pre-order expired 
    (asserts! 
      (if (is-none former-preorder)
        true
        (>= block-height (+ namespace-preorder-claimability-ttl
                            (unwrap! (get created-at former-preorder) (err err-panic)))))
      (err err-namespace-preorder-already-exists))
          (asserts! (> stx-to-burn u0) (err err-namespace-stx-burnt-insufficient))
    ;; Ensure that the hashed namespace is 20 bytes long
    (asserts! (is-eq (len hashed-salted-namespace) u20) (err err-namespace-hash-malformed))
    ;; Ensure that user will be burning a positive amount of tokens
    (asserts! (> stx-to-burn u0) (err err-namespace-stx-burnt-insufficient))
    ;; Burn the tokens
    (unwrap! (stx-transfer? stx-to-burn contract-caller burn-address) (err err-insufficient-funds))
    ;; Register the preorder
    (map-set namespace-preorders
      ((hashed-salted-namespace hashed-salted-namespace) (buyer contract-caller))
      ((created-at block-height) (claimed false) (stx-burned stx-to-burn)))
    (ok (+ block-height namespace-preorder-claimability-ttl))))

;; NAMESPACE_REVEAL
;; This second step reveals the salt and the namespace ID (pairing it with its NAMESPACE_PREORDER). It reveals how long
;; names last in this namespace before they expire or must be renewed, and it sets a price function for the namespace
;; that determines how cheap or expensive names its will be.
(define-public (namespace-reveal (namespace (buff 19))
                                 (namespace-version uint)
                                 (namespace-salt (buff 20))
                                 (p-func-base uint)
                                 (p-func-coeff uint)
                                 (p-func-b1 uint)
                                 (p-func-b2 uint)
                                 (p-func-b3 uint)
                                 (p-func-b4 uint)
                                 (p-func-b5 uint)
                                 (p-func-b6 uint)
                                 (p-func-b7 uint)
                                 (p-func-b8 uint)
                                 (p-func-b9 uint)
                                 (p-func-b10 uint)
                                 (p-func-b11 uint)
                                 (p-func-b12 uint)
                                 (p-func-b13 uint)
                                 (p-func-b14 uint)
                                 (p-func-b15 uint)
                                 (p-func-b16 uint)
                                 (p-func-non-alpha-discount uint)
                                 (p-func-no-vowel-discount uint)
                                 (renewal-rule uint)
                                 (namespace-import principal))
  ;; The salt and namespace must hash to a preorder entry in the `namespace_preorders` table.
  ;; The sender must match the principal in the preorder entry (implied)
  (let (
    (hashed-salted-namespace (hash160 (concat namespace namespace-salt)))
    (price-function (tuple 
      (buckets (list
        p-func-b1
        p-func-b2
        p-func-b3
        p-func-b4
        p-func-b5
        p-func-b6
        p-func-b7
        p-func-b8
        p-func-b9
        p-func-b10
        p-func-b11
        p-func-b12
        p-func-b13
        p-func-b14
        p-func-b15
        p-func-b16))
      (base p-func-base)
      (coeff p-func-coeff)
      (nonalpha-discount p-func-non-alpha-discount)
      (no-vowel-discount p-func-no-vowel-discount))))
    (let (
      (preorder (unwrap!
        (map-get? namespace-preorders ((hashed-salted-namespace hashed-salted-namespace) (buyer contract-caller)))
        (err err-namespace-preorder-not-found)))
      (namespace-price (unwrap! 
        (compute-namespace-price? namespace)
        (err err-namespace-blank))))
    ;; The namespace must only have valid chars
    (asserts!
      (not (has-invalid-chars namespace))
      (err err-namespace-charset-invalid))
    ;; The namespace must not exist yet in the `namespaces` table
    (asserts!
      (is-none (map-get? namespaces ((namespace namespace))))
      (err err-namespace-already-exists))
    ;; The amount burnt must be equal to or greater than the cost of the namespace
    (asserts!
      (>= (get stx-burned preorder) namespace-price)
      (err err-namespace-stx-burnt-insufficient))
    ;; This transaction must arrive within 24 hours of its `NAMESPACE_PREORDER`
    (asserts!
      (< block-height (+ (get created-at preorder) namespace-preorder-claimability-ttl))
      (err err-namespace-preorder-claimability-expired))
    ;; The preorder record for this namespace will be marked as "claimed"
    (map-set namespace-preorders
      ((hashed-salted-namespace hashed-salted-namespace) (buyer contract-caller))
      ((created-at (get created-at preorder)) (claimed true) (stx-burned (get stx-burned preorder))))
    ;; The namespace will be set as "revealed" but not "launched", its price function, its renewal rules, its version,
    ;; and its import principal will be written to the  `namespaces` table.
    (map-set namespaces
      ((namespace namespace))
      ((namespace-import namespace-import)
       (revealed-at block-height)
       (launched-at none)
       (namespace-version namespace-version)
       (renewal-rule renewal-rule)
       (price-function price-function)))
    (ok true))))

;; NAME_IMPORT
;; Once a namespace is revealed, the user has the option to populate it with a set of names. Each imported name is given
;; both an owner and some off-chain state. This step is optional; Namespace creators are not required to import names.
(define-public (name-import (namespace (buff 19))
                            (name (buff 16))
                            (zonefile-hash (buff 20)))
  (let (
    (namespace-props (unwrap!
      (map-get? namespaces ((namespace namespace)))
      (err err-namespace-not-found)))
    (name-currently-owned (map-get? owner-name ((owner contract-caller)))))
    (let ( 
        (can-sender-register-name (if (is-none name-currently-owned)
                                 true
                                  (unwrap! 
                                    (is-name-lease-expired?
                                      (unwrap! (get namespace name-currently-owned) (err err-panic))
                                      (unwrap! (get name name-currently-owned) (err err-panic)))
                                    (err err-panic)))))
      ;; The sender principal must match the namespace's import principal
      (asserts!
        (is-eq (get namespace-import namespace-props) contract-caller)
        (err err-namespace-operation-unauthorized))
      ;; The name's namespace must not be launched
      (asserts!
        (is-none (get launched-at namespace-props))
        (err err-namespace-already-launched))
      ;; The principal can register a name. Should we enable this condition in case of NAME-IMPORT
      ;; (asserts!
      ;;   can-sender-register-name
      ;;   (err err-principal-already-associated))
      ;; Less than 1 year must have passed since the namespace was "revealed"
      (asserts!
        (< block-height (+ (get revealed-at namespace-props) namespace-launchability-ttl))
        (err err-namespace-launchability-expired))
      ;; Mint the new name
      (unwrap! 
        (nft-mint? names (tuple (namespace namespace) (name name)) contract-caller)
        (err err-name-unavailable))
      ;; Attach the new name
      (map-set owner-name
        ((owner contract-caller))
        ((namespace namespace) (name name)))
      ;; Update zonefile and props
      (update-zonefile-and-props
        namespace 
        name  
        none
        (some block-height) ;; Set imported-at
        none
        zonefile-hash)
      (ok true))))

;; NAMESPACE_READY
;; The final step of the process launches the namespace and makes the namespace available to the public. Once a namespace
;; is launched, anyone can register a name in it if they pay the appropriate amount of cryptocurrency.
(define-public (namespace-ready (namespace (buff 19)))
  (let (
      (namespace-props (unwrap!
        (map-get? namespaces ((namespace namespace)))
        (err err-namespace-not-found)))
      (owned-name (map-get? owner-name ((owner contract-caller)))))
    ;; The sender principal must match the namespace's import principal
    (asserts!
      (is-eq (get namespace-import namespace-props) contract-caller)
      (err err-namespace-operation-unauthorized))
    ;; The name's namespace must not be launched
    (asserts!
      (is-none (get launched-at namespace-props))
      (err err-namespace-already-launched))
    ;; Less than 1 year must have passed since the namespace was "revealed"
    (asserts!
      (< block-height (+ (get revealed-at namespace-props) namespace-launchability-ttl))
      (err err-namespace-launchability-expired))
    ;; Update eventual name-props
    (if (is-none owned-name)
      true
      (let ((name (unwrap! (get name owned-name) (err err-panic))))
        (let ((name-props (unwrap! (map-get? name-properties ((name name) (namespace namespace))) (err err-panic))))
          ;; Unset imported-at, Set registered-at
          (map-set name-properties
            ((name name) (namespace namespace))
            ((registered-at (some block-height))
            (imported-at none)
            (revoked-at none)
            (zonefile-hash (get zonefile-hash name-props)))))))
    ;; The namespace will be set to "launched"
    (map-set namespaces
      ((namespace namespace))
      ((launched-at (some block-height))
       (namespace-import (get namespace-import namespace-props))
       (revealed-at (get revealed-at namespace-props))
       (namespace-version (get namespace-version namespace-props))
       (renewal-rule (get renewal-rule namespace-props))
       (price-function (get price-function namespace-props))))
    (ok true)))

;;;; NAMES

;; NAME_PREORDER
;; This is the first transaction to be sent. It tells all SNS nodes the salted hash of the SNS name,
;; and it pays the registration fee to the namespace owner's designated address
(define-public (name-preorder (hashed-salted-fqn (buff 20))
                              (stx-to-burn uint))
  (let 
    ((former-preorder 
      (map-get? name-preorders ((hashed-salted-fqn hashed-salted-fqn) (buyer contract-caller)))))
    ;; Ensure eventual former pre-order expired 
    (asserts! 
      (if (is-none former-preorder)
        true
        (>= block-height (+ name-preorder-claimability-ttl
                            (unwrap! (get created-at former-preorder) (err err-panic)))))
      (err err-name-preorder-already-exists))
          (asserts! (> stx-to-burn u0) (err err-namespace-stx-burnt-insufficient))    
    ;; Ensure that the hashed fqn is 20 bytes long
    (asserts! (is-eq (len hashed-salted-fqn) u20) (err err-name-hash-malformed))
    ;; Ensure that user will be burning a positive amount of tokens
    (asserts! (> stx-to-burn u0) (err err-name-stx-burnt-insufficient))
    ;; Burn the tokens
    (unwrap! (stx-transfer? stx-to-burn contract-caller burn-address) (err err-insufficient-funds))
    ;; Register the pre-order
    (map-set name-preorders
      ((hashed-salted-fqn hashed-salted-fqn) (buyer contract-caller))
      ((created-at block-height) (stx-burned stx-to-burn) (claimed false)))
    (ok (+ block-height name-preorder-claimability-ttl))))

;; NAME_REGISTRATION
;; This is the second transaction to be sent. It reveals the salt and the name to all SNS nodes,
;; and assigns the name an initial public key hash and zone file hash
(define-public (name-register (namespace (buff 19))
                              (name (buff 16))
                              (salt (buff 20))
                              (zonefile-hash (buff 20)))
  (let (
    (hashed-salted-fqn (hash160 (concat (concat (concat name 0x2e) namespace) salt)))
    (name-currently-owned (map-get? owner-name ((owner contract-caller)))))
    (let ( 
        (preorder (unwrap!
          (map-get? name-preorders ((hashed-salted-fqn hashed-salted-fqn) (buyer contract-caller)))
          (err err-name-preorder-not-found)))
        (namespace-props (unwrap!
          (map-get? namespaces ((namespace namespace)))
          (err err-namespace-not-found)))
        (current-owner (nft-get-owner? names (tuple (name name) (namespace namespace))))
        (can-sender-register-name (if (is-none name-currently-owned)
                                 true
                                  (unwrap! 
                                    (is-name-lease-expired?
                                      (unwrap! (get namespace name-currently-owned) (err err-panic))
                                      (unwrap! (get name name-currently-owned) (err err-panic)))
                                    (err err-panic)))))
      ;; The name must only have valid chars
      (asserts!
        (not (has-invalid-chars name))
        (err err-name-charset-invalid))
      ;; The name must not exist yet, or be expired
      (if (is-none current-owner)
        true
        (asserts!
          (unwrap! (is-name-lease-expired? namespace name) (err err-panic))
          (err err-name-unavailable)))
      ;; The name's namespace must be launched
      (asserts!
        (is-some (get launched-at namespace-props))
        (err err-namespace-not-launched))
      ;; The preorder must have been created after the launch of the namespace
      (asserts!
        (> (get created-at preorder) (unwrap! (get launched-at namespace-props) (err err-panic)))
        (err err-name-preordered-before-namespace-launch))
      ;; The preorder entry must be unclaimed - todo(ludo): is this assertion redundant?
      (asserts!
        (is-eq (get claimed preorder) false)
        (err err-name-already-claimed))
      ;; Less than 24 hours must have passed since the name was preordered
      (asserts!
        (< block-height (+ (get created-at preorder) name-preorder-claimability-ttl))
        (err err-name-claimability-expired))
      ;; The amount burnt must be equal to or greater than the cost of the name
      (asserts!
        (>= (get stx-burned preorder) (compute-name-price name (get price-function namespace-props)))
        (err err-name-stx-burnt-insufficient))
      ;; The principal can register a name
      (asserts!
        can-sender-register-name
        (err err-principal-already-associated))
      ;; Mint the name if new, transfer the name otherwise.
      (if (is-none current-owner)
        (begin
          (unwrap! 
            (nft-mint? 
              names 
              (tuple (namespace namespace) (name name)) 
              contract-caller)
            (err err-name-could-not-be-minted))
          (map-set owner-name
            ((owner contract-caller))
            ((namespace namespace) (name name))))
        (if (is-eq contract-caller (unwrap! current-owner (err err-panic)))
          true
          (let ((previous-owner (unwrap! current-owner (err err-panic)))) 
            (unwrap!
              (update-name-ownership? namespace name previous-owner contract-caller)
              (err err-name-could-not-be-transfered)))))
      ;; Update name's metadata / properties
      (map-set name-properties
        ((namespace namespace) (name name))
        ((registered-at (some block-height))
        (imported-at none)
        (revoked-at none)
        (zonefile-hash zonefile-hash)))
      (ok true))))

;; NAME_UPDATE
;; A NAME_UPDATE transaction changes the name's zone file hash. You would send one of these transactions 
;; if you wanted to change the name's zone file contents. 
;; For example, you would do this if you want to deploy your own Gaia hub and want other people to read from it.
(define-public (name-update (namespace (buff 19))
                            (name (buff 16))
                            (zonefile-hash (buff 20)))
  (let (
    (owner (unwrap!
      (nft-get-owner? names (tuple (name name) (namespace namespace)))
      (err err-name-not-found))) ;; The name must exist
    (name-props (unwrap!
      (map-get? name-properties ((name name) (namespace namespace)))
      (err err-name-not-found)))) ;; The name must exist
    ;; The sender must match the name's current owner
    (asserts!
      (is-eq owner contract-caller)
      (err err-name-operation-unauthorized))
    ;; The name must not be in the renewal grace period
    (asserts!
      (is-eq (unwrap! (is-name-in-grace-period? namespace name) (err err-panic)) false)
      (err err-name-grace-period))
    ;; The name must not be expired 
    (asserts!
      (is-eq (unwrap! (is-name-lease-expired? namespace name) (err err-panic)) false)
      (err err-name-expired))
    ;; The name must not be revoked
    (asserts!
      (is-none (get revoked-at name-props))
      (err err-name-revoked))
    ;; Update the zonefile
    (update-zonefile-and-props
      namespace 
      name  
      (get registered-at name-props)
      (get imported-at name-props)
      none
      zonefile-hash)
    (ok true)))

;; NAME_TRANSFER
;; A NAME_TRANSFER transaction changes the name's public key hash. You would send one of these transactions if you wanted to:
;; - Change your private key
;; - Send the name to someone else
;; When transferring a name, you have the option to also clear the name's zone file hash (i.e. set it to null). 
;; This is useful for when you send the name to someone else, so the recipient's name does not resolve to your zone file.
(define-public (name-transfer (namespace (buff 19))
                              (name (buff 16))
                              (new-owner principal)
                              (zonefile-hash (optional (buff 20))))
  (let (
    (current-owned-name (map-get? owner-name ((owner new-owner))))
    (namespace-props (unwrap!
      (map-get? namespaces ((namespace namespace)))
      (err err-namespace-not-found))))
    (let (
      (owner (unwrap!
        (nft-get-owner? names (tuple (name name) (namespace namespace)))
        (err err-name-not-found))) ;; The name must exist
      (name-props (unwrap!
        (map-get? name-properties ((name name) (namespace namespace)))
        (err err-name-not-found))) ;; The name must exist
      (can-new-owner-get-name (if (is-none current-owned-name)
                                  true
                                  (unwrap! 
                                    (is-name-lease-expired?
                                      (unwrap! (get namespace current-owned-name) (err err-panic))
                                      (unwrap! (get name current-owned-name) (err err-panic)))
                                    (err err-panic)))))
      ;; The namespace must be launched
      (asserts!
        (is-some (get launched-at namespace-props))
        (err err-namespace-not-launched))
      ;; The sender must match the name's current owner
      (asserts!
        (is-eq owner contract-caller)
        (err err-name-operation-unauthorized))
      ;; The name must have been registered (vs imported)
      (unwrap!
        (get registered-at name-props)
        (err err-name-operation-unauthorized))
      ;; The name must not be in the renewal grace period
      (asserts!
        (is-eq (unwrap! (is-name-in-grace-period? namespace name) (err err-panic)) false)
        (err err-name-grace-period))
      ;; The name must not be expired
      (asserts!
        (is-eq (unwrap! (is-name-lease-expired? namespace name) (err err-panic)) false)
        (err err-name-expired))
      ;; The name must not be revoked
      (asserts!
        (is-none (get revoked-at name-props))
        (err err-name-revoked))
      ;; The new owner does not own a name
      (asserts!
        can-new-owner-get-name
        (err err-principal-already-associated))
      ;; Transfer the name
      (unwrap!
        (update-name-ownership? namespace name contract-caller new-owner)
        (err err-name-transfer-failed))
      ;; Update or clear the zonefile
      (update-zonefile-and-props
          namespace 
          name  
          (get registered-at name-props)
          (get imported-at name-props)
          none
          (if (is-none zonefile-hash)
            0x
            (unwrap! zonefile-hash (err err-panic))))
      (ok true))))

;; NAME_REVOKE
;; A NAME_REVOKE transaction makes a name unresolvable. The SNS consensus rules stipulate that once a name 
;; is revoked, no one can change its public key hash or its zone file hash. 
;; The name's zone file hash is set to null to prevent it from resolving.
;; You should only do this if your private key is compromised, or if you want to render your name unusable for whatever reason.
(define-public (name-revoke (namespace (buff 19))
                            (name (buff 16)))
  (let (
    (owner (unwrap!
      (nft-get-owner? names (tuple (name name) (namespace namespace)))
      (err err-name-not-found))) ;; The name must exist
    (namespace-props (unwrap!
      (map-get? namespaces ((namespace namespace)))
      (err err-namespace-not-found)))
    (name-props (unwrap!
      (map-get? name-properties ((name name) (namespace namespace)))
      (err err-name-not-found)))) ;; The name must exist
    ;; The namespace must be launched
    (asserts!
      (is-some (get launched-at namespace-props))
      (err err-namespace-not-launched))
    ;; The sender must match the name's current owner
    (asserts!
      (is-eq owner contract-caller)
      (err err-name-operation-unauthorized))
    ;; The name must not be expired
    (asserts!
      (is-eq (unwrap! (is-name-lease-expired? namespace name) (err err-panic)) false)
      (err err-name-expired))
    ;; The name must not be in the renewal grace period
    (asserts!
      (is-eq (unwrap! (is-name-in-grace-period? namespace name) (err err-panic)) false)
      (err err-name-grace-period))
    ;; The name must not be revoked
    (asserts!
      (is-none (get revoked-at name-props))
      (err err-name-revoked))
    ;; Clear the zonefile
    (update-zonefile-and-props
        namespace 
        name  
        (get registered-at name-props)
        (get imported-at name-props)
        (some block-height)
        0x)
    (ok true)))

;; NAME_RENEWAL
;; Depending in the namespace rules, a name can expire. For example, names in the .id namespace expire after 2 years. 
;; You need to send a NAME_RENEWAL every so often to keep your name.
;; You will pay the registration cost of your name to the namespace's designated burn address when you renew it.
;; When a name expires, it enters a month-long "grace period" (5000 blocks). 
;; It will stop resolving in the grace period, and all of the above operations will cease to be honored by the SNS consensus rules.
;; You may, however, send a NAME_RENEWAL during this grace period to preserve your name.
;; If your name is in a namespace where names do not expire, then you never need to use this transaction.
(define-public (name-renewal (namespace (buff 19))
                             (name (buff 16))
                             (stx-to-burn uint)
                             (new-owner (optional principal))
                             (zonefile-hash (optional (buff 20))))
  (let (
    (namespace-props (unwrap!
      (map-get? namespaces ((namespace namespace)))
      (err err-namespace-not-found)))
    (owner (unwrap!
      (nft-get-owner? names (tuple (name name) (namespace namespace)))
      (err err-name-not-found))) ;; The name must exist
    (name-props (unwrap!
      (map-get? name-properties ((name name) (namespace namespace)))
      (err err-name-not-found)))) ;; The name must exist
    ;; The namespace must be launched
    (asserts!
      (is-some (get launched-at namespace-props))
      (err err-namespace-not-launched))
    ;; The namespace should require renewals
    (asserts!
      (> (get renewal-rule namespace-props) u0)
      (err err-name-operation-unauthorized))
    ;; The sender must match the name's current owner
    (asserts!
      (is-eq owner contract-caller)
      (err err-name-operation-unauthorized))
    ;; The name must have been registered (vs imported)
    (unwrap!
      (get registered-at name-props)
      (err err-name-operation-unauthorized))
    ;; If expired, the name must not be in the renewal grace period.
    (if (unwrap! (is-name-lease-expired? namespace name) (err err-panic))
      (asserts!
        (is-eq (unwrap! (is-name-in-grace-period? namespace name) (err err-panic)) true)
        (err err-name-expired))
      true)    
    ;; The amount burnt must be equal to or greater than the cost of the namespace
    (asserts!
      (>= stx-to-burn (compute-name-price name (get price-function namespace-props)))
      (err err-name-stx-burnt-insufficient))
    ;; The name must not be revoked
    (asserts!
      (is-none (get revoked-at name-props))
      (err err-name-revoked))
    ;; Transfer the name, if any new-owner
    (if (is-none new-owner)
      (ok true) 
      (let ((owner-unwrapped (unwrap! new-owner (err err-panic))))
        (let ((current-owned-name (map-get? owner-name ((owner owner-unwrapped)))))
          (let ((can-new-owner-get-name (if (is-none current-owned-name)
                                  true
                                  (unwrap! 
                                    (is-name-lease-expired?
                                      (unwrap! (get namespace current-owned-name) (err err-panic))
                                      (unwrap! (get name current-owned-name) (err err-panic)))
                                    (err err-panic)))))
            (asserts!
              can-new-owner-get-name
              (err err-principal-already-associated))
            (unwrap!
              (update-name-ownership? namespace name contract-caller owner-unwrapped)
              (err err-name-could-not-be-transfered))
            (ok true)))))
    ;; Update the zonefile, if any.
    (if (is-none zonefile-hash)
      (map-set name-properties
        ((namespace namespace) (name name))
        ((registered-at (some block-height))
         (imported-at none)
         (revoked-at none)
         (zonefile-hash (get zonefile-hash name-props))))
      (update-zonefile-and-props
              namespace 
              name
              (some block-height)
              none
              none
              (unwrap! zonefile-hash (err err-panic))))  
    (ok true)))

;; Additionals public methods

(define-public (can-name-be-registered (namespace (buff 19)) (name (buff 16)))
  (let (
      (wrapped-name-props (map-get? name-properties ((namespace namespace) (name name))))
      (current-owner (map-get? owner-name ((owner contract-caller))))
      (namespace-props (unwrap! (map-get? namespaces ((namespace namespace))) (ok false))))
    ;; Ensure that namespace has been launched 
    (unwrap! (get launched-at namespace-props) (ok false))
    ;; Early return - Name has never be minted
    (asserts! (is-none (nft-get-owner? names (tuple (name name) (namespace namespace)))) (ok true))
    ;; Integrity check - Ensure that we have some entries in nft && owner-name && name-props
    (asserts! 
      (and 
        (is-some wrapped-name-props)
        (is-some current-owner))
      (err err-panic))
    (let ((name-props (unwrap! wrapped-name-props (err err-panic))))
      ;; Early return - Name has been revoked and can be registered
      (asserts! (is-some (get revoked-at name-props)) (ok true))
      ;; Integrity check - Ensure that the name was either "imported" or "registered".
      (asserts! 
        (or 
          (and (is-some (get registered-at name-props)) (is-none (get imported-at name-props)))
          (and (is-some (get imported-at name-props)) (is-none (get registered-at name-props))))
        (err err-panic))
      ;; Is lease expired?
      (is-name-lease-expired? namespace name))))

(define-read-only (name-resolve (namespace (buff 19)) (name (buff 16)))
  (let (
    (owner (unwrap!
      (nft-get-owner? names (tuple (name name) (namespace namespace)))
      (err err-name-not-found))) ;; The name must exist
    (name-props (unwrap!
      (map-get? name-properties ((name name) (namespace namespace)))
      (err err-name-not-found)))
    (namespace-props (unwrap! 
      (map-get? namespaces ((namespace namespace))) 
      (err err-namespace-not-found)))
    (is-lease-expired (is-name-lease-expired? namespace name)))
    ;; The namespace must be launched
    (asserts!
      (is-some (get launched-at namespace-props))
      (err err-namespace-not-launched))
    ;; The name must not be in the renewal grace period
    (asserts!
      (is-eq (unwrap! (is-name-in-grace-period? namespace name) (err err-panic)) false)
      (err err-name-grace-period))
    ;; The name must not be expired
    (if (is-ok is-lease-expired)
      (asserts! (not (unwrap! is-lease-expired (err err-panic))) (err err-name-expired))
      true)
    ;; The name must not be revoked
    (asserts!
      (is-none (get revoked-at name-props))
      (err err-name-revoked))
    ;; Get the zonefile
    (ok (get zonefile-hash name-props))))

;; (begin
;;   (ft-mint? stx u10000000000 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
;;   (ft-mint? stx u10000000 'S02J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKPVKG2CE)
;;   (ft-mint? stx u10000000 'SZ2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKQ9H6DPR)
;;   (ft-mint? stx u10000000 'SPMQEKN07D1VHAB8XQV835E3PTY3QWZRZ5H0DM36))