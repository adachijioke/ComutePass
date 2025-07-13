# CommutePass - Digital Transport Card Smart Contract

A blockchain-based digital transport card system built on Stacks, enabling prepaid wallet functionality and QR code-based fare payments for public transportation.

## 🚀 Features

### MVP v0.1 Core Features
- **Prepaid Wallets**: Users can top up their wallets with STX tokens
- **QR Code Payment System**: Scan vehicle QR codes to pay fares instantly
- **Driver Vehicle Registration**: Drivers can register vehicles and set fare amounts
- **Daily Spending Limits**: Configurable daily spending caps for security
- **Platform Fee System**: Small platform fee for sustainability (0.25% default)

### Security Features
- Daily spending limits with automatic reset
- Vehicle ownership verification
- Contract pause functionality
- Emergency withdrawal for admin

## 🛠️ Technical Stack

- **Blockchain**: Stacks (Bitcoin Layer 2)
- **Smart Contract Language**: Clarity v2.4
- **Development Framework**: Clarinet
- **Testing**: Clarinet Test Framework

## 📋 Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks CLI](https://docs.stacks.co/docs/cli) (optional)
- Node.js 16+ (for testing)

## 🚀 Quick Start

### 1. Clone and Setup
\`\`\`bash
git clone <repository-url>
cd commutepass
clarinet check
\`\`\`

### 2. Run Tests
\`\`\`bash
clarinet test
\`\`\`

### 3. Deploy to Testnet
\`\`\`bash
clarinet deploy --testnet
\`\`\`

## 📖 Usage Guide

### For Riders

#### 1. Top Up Wallet
\`\`\`clarity
(contract-call? .commutepass top-up-wallet u1000000) ;; Top up 1 STX
\`\`\`

#### 2. Pay Fare
\`\`\`clarity
(contract-call? .commutepass pay-fare "BUS001") ;; Pay fare for vehicle BUS001
\`\`\`

#### 3. Set Daily Limit
\`\`\`clarity
(contract-call? .commutepass set-daily-limit u75000000) ;; Set 75 STX daily limit
\`\`\`

### For Drivers

#### 1. Register Vehicle
\`\`\`clarity
(contract-call? .commutepass register-vehicle "BUS001" u500000) ;; Register vehicle with 0.5 STX fare
\`\`\`

#### 2. Update Fare
\`\`\`clarity
(contract-call? .commutepass update-vehicle-fare "BUS001" u750000) ;; Update to 0.75 STX
\`\`\`

#### 3. Toggle Vehicle Status
\`\`\`clarity
(contract-call? .commutepass toggle-vehicle-status "BUS001") ;; Activate/deactivate vehicle
\`\`\`

## 🔍 Contract Functions

### Read-Only Functions
- \`get-user-wallet\`: Get user wallet information
- \`get-vehicle-info\`: Get vehicle registration details
- \`get-contract-info\`: Get contract status and settings

### Public Functions
- \`top-up-wallet\`: Add STX to user wallet
- \`pay-fare\`: Pay fare using vehicle ID
- \`register-vehicle\`: Register new vehicle (drivers)
- \`update-vehicle-fare\`: Update vehicle fare amount
- \`set-daily-limit\`: Set personal daily spending limit

### Admin Functions
- \`set-platform-fee-rate\`: Update platform fee percentage
- \`toggle-contract-status\`: Pause/unpause contract
- \`emergency-withdraw\`: Emergency fund withdrawal

## 🧪 Testing

The contract includes comprehensive tests covering:
- Wallet top-up functionality
- Vehicle registration and fare payment
- Daily spending limit enforcement
- Error handling scenarios

Run tests with:
\`\`\`bash
clarinet test
\`\`\`

## 🔒 Security Considerations

- **Daily Limits**: Automatic daily spending limits prevent excessive usage
- **Vehicle Verification**: Only registered vehicle owners can modify vehicle settings
- **Platform Fees**: Reasonable fee structure (0.25% default, max 10%)
- **Emergency Controls**: Admin can pause contract and withdraw funds if needed

## 🗺️ Roadmap

### Phase 2 Features (Future)
- Multi-token support (fiat-pegged tokens)
- Offline top-up via verified agents
- Monthly/weekly pass systems
- Route-based pricing
- Loyalty rewards system

## 📄 License

MIT License - see LICENSE file for details

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

