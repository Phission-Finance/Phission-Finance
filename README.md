# Phission

Excuse the awful code, this is a WIP. This readme is just a disorganized todo list with some notes

to run tests: `./test.sh <rpc url> <etherscan api key>`

forge doesn't support values larger than uint64 for block.difficulty, so for the live deployment `MIN_RANDAO` in `Oracle.sol` should be set to a higher value (1e30 or so)

zap: 
    settable fees (in upgrade?)
    sell <<<<<< math
        fee before
        fee after
    lp <<<<<< math
        buy: fee before fee after
        sell: fee before fee after
    eth -> gov(s/w)
    gov(s/w) -> eth
        buy: fee before fee after
        sell: fee before fee after

treasury:
    [x] redeem

ZAP not upgradable, just deploy a new one

- [x] treasury lp calls
  - [x] both directions
- [ ] treasury lp^2
- [ ] zap math for flat fee on input amount
  - [x] buy
  - [x] sell
  - [ ] buy lp
  - [ ] sell lp
- [ ] staking contract

=> launch testnet test without staking rewards

[ ] replace convertToLp math function with new one 
[ ] replace same math for the sell one

### deployment steps
NOTE: (for testing)
* deploy fork oracle (mock oracle)
* deploy split factory
* create some weth, create weth split, approve weth to split
* mint some ETHw/ETHs tokens. add liq to uniswap pool
* deploy univ2 oracle for ETHw/ETHs
* mint some LPw/LPs tokens. add liq to uniswap pool
* deploy univ2 oracle for LPs/LPw
* deploy gov token PHI
* team allocation in a multisig (hotwallet)
( change treasury & zap to use injected weth)
* mint some PHIw/PHIs tokens
* deploy treasury
* add liq to PHIw/PHIs and move LP tokens to treasury 
* deploy zap contract

* add liq to PHI eth pool uniswap pool?? 
* deploy staking contracts 
* put gov token in them