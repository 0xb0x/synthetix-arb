// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import { FlashLoanReceiverBase } from "./FlashLoanReceiverBase.sol";
import { ILendingPool, ILendingPoolAddressesProvider, IERC20, IEtherCollateral, IEtherWrappr } from "./Interfaces.sol";
import { SafeMath } from "./Libraries.sol";


contract SynthetixArb is FlashLoanReceiverBase {
    using SafeMath for uint256;

    IEtherCollateral public etherCollateral;
    IEtherWrappr public etherWrappr;
    IERC20 public sETH;       

    constructor(ILendingPoolAddressesProvider _addressProvider, 
        address etherCollateralAddr, 
        address etherWrapprAddr,
        address sEthAddr
        ) 
        FlashLoanReceiverBase(_addressProvider) 
            public {
                etherCollateral  = IEtherCollateral(etherCollateralAddr);
                etherWrappr = IEtherWrappr(etherWrapprAddr);
                sETH = IERC20(sEthAddr);
            }



    function executeArb(
        address token,
        uint256 amount,
        address[] calldata _loanCreatorsAddresses, 
        uint256[] calldata _loanIDs
    ) public {
        require(_loanCreatorsAddresses.length == _loanIDs.length);

        address receiverAddress = address(this);

        address[] memory assets = new address[](1);
        assets[0] = token; // Eth

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(_loanCreatorsAddresses, _loanIDs);
        uint16 referralCode = 0;


        _lendingPool.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
            );
        

        uint profit = address(this).balance;
        (bool success, ) = msg.sender.call{value: profit}("");
        require(success, "Failed to send Ether");

    }

    

    /**
        This function is called after your contract has received the flash loaned amount
     */

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {

        (address[] memory _loanCreatorsAddresses, uint256[] memory _loanIDs) = abi.decode(params, (address[], uint256[]));

        etherWrappr.mint(amounts[0]);

        for(uint i = 0; i < _loanCreatorsAddresses.length; i++){
            etherCollateral.liquidateUnclosedLoan(_loanCreatorsAddresses[i], _loanIDs[i]);
        }
        
        uint256 burnAmt = sETH.balanceOf(address(this));
        // 
        uint256 dust = 0 ;// uint(99).mul(burnAmt).div(100);

        // burn remaining sETH
        etherWrappr.burn(burnAmt.sub(dust));
        

        uint amountOwing = amounts[0].add(premiums[0]);
        IERC20(assets[0]).approve(address(_lendingPool), amountOwing);

        return true;
        
    }

}
