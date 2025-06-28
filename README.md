# Spendmap - Constituency Spending Tracker

A Clarity smart contract for transparent government spending tracking with token-gated access control.

## Overview

Spendmap enables citizens to track government spending records through a decentralized system with token-based access control. Government departments can submit spending records, which are then verified by token holders to ensure transparency and accountability.

## Features

- **Token-Gated Access**: Purchase access tokens to view and verify spending records
- **Authorized Submissions**: Only authorized government submitters can add spending records
- **Verification System**: Community verification of spending records with reputation tracking
- **Constituency Tracking**: Aggregate spending data by constituency
- **Access Control**: Owner-managed authorization and contract controls

## Contract Functions

### Public Functions

#### `purchase-access (tier uint)`
Purchase access tokens for a specified tier level. Higher tiers provide more tokens and longer access.
- `tier`: Access tier level (1-3 recommended)
- Returns: `(ok true)` on success

#### `submit-spending-record (constituency department amount description date)`
Submit a new spending record (authorized submitters only).
- `constituency`: Geographic area (max 50 chars)
- `department`: Government department (max 50 chars)  
- `amount`: Spending amount in microSTX
- `description`: Spending description (max 200 chars)
- `date`: Unix timestamp of spending
- Returns: `(ok record-id)` on success

#### `verify-record (record-id uint)`
Verify a spending record using access tokens.
- `record-id`: ID of record to verify
- Returns: `(ok verified-status)` on success

#### `authorize-submitter (user principal)`
Authorize a user to submit spending records (owner only).
- `user`: Principal to authorize
- Returns: `(ok true)` on success

### Read-Only Functions

#### `get-spending-record (record-id uint)`
Retrieve a spending record by ID.
- Returns: Record details or `none`

#### `has-access (user principal)`
Check if user has valid access tokens.
- Returns: `true` if user has access

#### `get-constituency-total (constituency string-ascii)`
Get total spending for a constituency.
- Returns: Total amount and record count

#### `get-contract-info`
Get contract status and configuration.
- Returns: Contract metadata

## Usage Example

### 1. Purchase Access
```clarity
(contract-call? .spendmap purchase-access u2)
```

### 2. Submit Spending Record (Authorized users only)
```clarity
(contract-call? .spendmap submit-spending-record 
  "District-A" 
  "Education" 
  u5000000000 
  "School renovation project" 
  u1703097600)
```

### 3. Verify Record
```clarity
(contract-call? .spendmap verify-record u1)
```

### 4. Query Records
```clarity
(contract-call? .spendmap get-spending-record u1)
(contract-call? .spendmap get-constituency-total "District-A")
```

## Access Tiers

- **Tier 1**: 10 tokens, 1440 blocks validity (~10 days)
- **Tier 2**: 20 tokens, 2880 blocks validity (~20 days)  
- **Tier 3**: 30 tokens, 4320 blocks validity (~30 days)

## Error Codes

- `u100`: Owner only operation
- `u101`: Not authorized
- `u102`: Invalid amount
- `u103`: Record not found
- `u104`: Already exists
- `u105`: Insufficient balance
- `u106`: Invalid principal
- `u107`: Expired access
- `u108`: Not verified

## Deployment

1. Deploy contract using Clarinet
2. Authorize government submitters using `authorize-submitter`
3. Set appropriate token pricing with `set-token-price`
4. Configure verification threshold with `set-verification-threshold`

## Security Features

- Contract pause/unpause functionality
- Owner-only administrative functions
- Token expiration system
- Verification threshold requirements
- Reputation tracking for submitters

## Development

Built with Clarinet framework for Stacks blockchain deployment.
