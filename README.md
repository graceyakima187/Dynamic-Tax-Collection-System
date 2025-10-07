# 💰 Dynamic Tax Collection System

A Clarity smart contract that automatically collects and redistributes taxes or service fees from transactions in a token ecosystem on the Stacks blockchain.

## 🚀 Features

- **Automatic Tax Collection**: Configurable tax rate applied to all transfers
- **Tax Exemptions**: Whitelist users who are exempt from paying taxes
- **Beneficiary System**: Add multiple beneficiaries with custom share percentages
- **Treasury Management**: Secure storage and distribution of collected taxes
- **Transaction History**: Complete audit trail of all transactions
- **Emergency Controls**: Owner can pause distributions and emergency withdraw

## 📋 Contract Functions

### 💳 User Functions

- `deposit(amount)` - Deposit STX tokens into the system
- `transfer(recipient, amount)` - Transfer tokens with automatic tax deduction
- `withdraw(amount)` - Withdraw your tokens from the system

### 👑 Owner Functions

- `set-tax-rate(new-rate)` - Set tax rate (0-1000 basis points, max 10%)
- `add-tax-exemption(user)` - Exempt a user from paying taxes
- `remove-tax-exemption(user)` - Remove tax exemption
- `add-beneficiary(beneficiary, share)` - Add beneficiary with share percentage
- `remove-beneficiary(beneficiary)` - Remove a beneficiary
- `distribute-taxes()` - Trigger tax distribution to beneficiaries
- `emergency-withdraw()` - Emergency withdraw all treasury funds

### 📊 Read-Only Functions

- `get-tax-rate()` - Current tax rate
- `get-treasury-balance()` - Current treasury balance
- `get-user-balance(user)` - User's token balance
- `get-total-collected()` - Total taxes collected
- `calculate-tax(amount)` - Calculate tax for given amount
- `get-contract-stats()` - Complete contract statistics

## 🛠️ Usage Examples

### Deploy and Setup

```bash
clarinet deploy
```

### Basic Operations

1. **Deposit tokens**:
   ```clarity
   (contract-call? .Dynamic-Tax-Collection-System deposit u1000000)
   ```

2. **Transfer with tax**:
   ```clarity
   (contract-call? .Dynamic-Tax-Collection-System transfer 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u500000)
   ```

3. **Set tax rate to 2.5%**:
   ```clarity
   (contract-call? .Dynamic-Tax-Collection-System set-tax-rate u250)
   ```

4. **Add beneficiary with 50% share**:
   ```clarity
   (contract-call? .Dynamic-Tax-Collection-System add-beneficiary 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u5000)
   ```

## ⚙️ Configuration

- **Default Tax Rate**: 2.5% (250 basis points)
- **Minimum Distribution**: 1 STX
- **Maximum Tax Rate**: 10% (1000 basis points)
- **Share Percentages**: 0-100% (0-10000 basis points)

## 🔒 Security Features

- Owner-only administrative functions
- Input validation on all parameters
- Safe math operations
- Emergency withdrawal capability
- Transaction history for auditing

## 📈 Tax Distribution

The system collects taxes from transfers and stores them in a treasury. The owner can:
- Add multiple beneficiaries with custom share percentages
- Distribute collected taxes proportionally
- Set minimum distribution thresholds
- Enable/disable automatic distributions

## 🧪 Testing

```bash
clarinet test
```

## 📝 License

This project is open source and available under the MIT License.

---

Built with ❤️ using Clarity and Clarinet
```

**Git Commit Message:**
```
feat: implement dynamic tax collection system with automatic redistribution
```

**GitHub Pull Request Title:**
```
🚀 Add Dynamic Tax Collection System Smart Contract
```

**GitHub Pull Request Description:**
```
## 📋 Summary
Added a comprehensive Dynamic Tax Collection System smart contract that automatically collects and redistributes taxes from token transactions.

## ✨ Features Added
- **Automatic tax collection** with configurable rates (0-10%)
- **User balance management** with deposit/withdraw functionality  
- **Tax exemption system** for whitelisted users
- **Multi-beneficiary distribution** with custom share percentages
- **Complete transaction history** and audit trail
- **Emergency controls** and treasury management
- **Read-only functions** for contract statistics and calculations

## 🔧 Technical Details
- 150+ lines of production-ready Clarity code
- Comprehensive error handling with custom error codes
- Owner-only administrative functions with proper access control
- Safe math operations and input validation
- Updated to use `stacks-block-height` for Stacks 2.1 compatibility

## 📚 Documentation
- Complete README with usage examples and API documentation
- Clear function descriptions and configuration options
- Testing instructions and security considerations

Ready for deployment and integration into token ecosystems requiring automated tax collection and redistribution mechanisms.
