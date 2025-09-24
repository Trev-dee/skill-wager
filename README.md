# Skill-Based Wagering Smart Contract

A Clarity v3 smart contract that enables trustless skill-based wagering between two players with referee arbitration on the Stacks blockchain.

## Overview

This contract implements a two-player STX (Stacks token) escrow system where players can:
- Create matches with defined stakes and deadlines
- Join existing matches by matching the stake
- Have results settled by a trusted referee
- Get automatic refunds for unjoined matches
- Fall back to 50/50 splits if referee fails to act

## Features

- ✅ Two-player escrow system
- ✅ Trusted referee arbitration
- ✅ Configurable deadlines
- ✅ Automatic refund mechanism
- ✅ Fallback split functionality
- ✅ Full state tracking
- ✅ Comprehensive error handling

## Contract Functions

### Core Functions

```clarity
create-match (stake uint) (referee principal) (join-deadline uint) (result-deadline uint)
join-match (id uint)
settle (id uint) (winner principal)
cancel-if-unjoined (id uint)
split-if-timeout (id uint)
```

### Read-Only Functions

```clarity
get-match (id uint)
status-of (id uint)
pot-of (id uint)
```

## Error Codes

- `ERR-BAD-ARGS (100)`: Invalid arguments
- `ERR-NOT-FOUND (101)`: Match not found
- `ERR-UNAUTHORIZED (102)`: Unauthorized access
- `ERR-STATE (103)`: Invalid state transition
- `ERR-INSUFFICIENT (104)`: Insufficient funds
- `ERR-TOO-EARLY (105)`: Action attempted too early
- `ERR-TOO-LATE (106)`: Action attempted too late

## Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- [Stacks Wallet](https://www.hiro.so/wallet)

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy
```

## Security Considerations

- Referee cannot be player1 or player2
- Enforces reasonable timeout windows
- Safe arithmetic operations
- Protected state transitions
- Role-based access control

Built with ❤️ for the Stacks ecosystem
