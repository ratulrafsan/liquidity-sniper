// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWBNB {
    function withdraw(uint) external;
    function deposit() external payable;
}

interface ICustomRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract Trigger is Ownable {

    address private wbnb;

    address payable private administrator;
    address private customRouter;

    uint private wbnbIn;
    uint private minTknOut;

    address private tokenToBuy;
    address private tokenPaired;

    bool private targetLock;

    constructor(address _wbnb) public {
        administrator = payable(msg.sender);
        wbnb = _wbnb;
    }
    
    receive() external payable {
        IWBNB(wbnb).deposit{value: msg.value}();
    }

    // Trigger is the smart contract in charge or performing liquidity sniping.
    // Its role is to hold the BNB, perform the swap once ax-50 detect the tx in the mempool and if all checks are passed; then route the tokens sniped to the owner.
    // It requires a first call to configreProcess in order to be armed. Then, it can snipe on whatever pair no matter the paired token (BUSD / WBNB etc..).
    // This contract uses a custtom router which is a copy of uniswapv2 router but with modified selectors, so that our tx are more difficult to listen than those directly going through the usual router.
    
    // perform the liquidity sniping
    function targetListing() external returns(bool success) {
        require(IERC20(wbnb).balanceOf(address(this)) >= wbnbIn, "notice: not enough wbnb on the contract");
        IERC20(wbnb).approve(customRouter, wbnbIn);
        require(targetLock == false, "notice: target is locked. See configure");
        targetLock = true;
        
        address[] memory path;
        if (tokenPaired != wbnb) {
            path = new address[](3);
            path[0] = wbnb;
            path[1] = tokenPaired;
            path[2] = tokenToBuy;
        } else {
            path = new address[](2);
            path[0] = wbnb;
            path[1] = tokenToBuy;
        }

        ICustomRouter(customRouter).swapExactTokensForTokens(
              wbnbIn,
              minTknOut,
              path, 
              administrator,
              block.timestamp + 120
        );
        return true;
    }
    
    function getAdministrator() external view onlyOwner returns(address payable) {
        return administrator;
    }

    function setAdministrator(address payable _newAdmin) external onlyOwner returns(bool success) {
        administrator = _newAdmin;
        return true;
    }
    
    function getCustomRouter() external view onlyOwner returns(address) {
        return customRouter;
    }
    
    function setCustomRouter(address _newRouter) external onlyOwner returns(bool success) {
        customRouter = _newRouter;
        return true;
    }

    function setWBNBAddress(address _wbnb) external onlyOwner returns(bool success) {
        wbnb = _wbnb;
        return true;
    }

    function getWBNBAddress() external view onlyOwner returns(address) {
        return wbnb;
    }
    
    // must be called before sniping
    function configreProcess(address _tokenPaired, uint _amountIn, address _tknToBuy, uint _amountOutMin) external onlyOwner returns(bool success) {
        tokenPaired = _tokenPaired;
        wbnbIn = _amountIn;
        tokenToBuy = _tknToBuy;
        minTknOut = _amountOutMin;
        targetLock = false;
        return true;
    }
    
    function getSnipeConfiguration() external view onlyOwner returns(address, uint, address, uint, bool) {
        return (tokenPaired, wbnbIn, tokenToBuy, minTknOut, targetLock);
    }
    
    // here we precise amount param as certain bep20 tokens uses strange tax system preventing to send back whole balance
    function emmergencyWithdrawTkn(address _token, uint _amount) external onlyOwner returns(bool success) {
        require(IERC20(_token).balanceOf(address(this)) >= _amount, "not enough tokens in contract");
        IERC20(_token).transfer(administrator, _amount);
        return true;
    }
    
    // shouldn't be of any use as receive function automatically wrap bnb incoming
    function emmergencyWithdrawBnb() external onlyOwner returns(bool success) {
        require(address(this).balance > 0 , "contract has an empty BNB balance");
        administrator.transfer(address(this).balance);
        return true;
    }
}