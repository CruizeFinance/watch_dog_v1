// SPDX-License-Identifier: MI
pragma solidity =0.8.6;
import "./CruizeVault.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
contract Cruize  {





    function depositETH(uint _amount) public payable{
      require(msg.value >= _amount);
    //   mint token 
    }
    function depositERC20(address _token,uint _amount) external {
        require(_token != address(0),"null token address");
        require(_amount > 0,"amount can't be zero");
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender,address(this), _amount));
        //   mint token 

        
    }

    function withdraw(        
        address _to,
        address _token,
        uint _amount,
        bytes[] memory _signature) external  {
        //check if user have enough balance.
        //  _transferTo(_to,_token,_amount,_signature);
        //brun token .
        }




   receive() external payable {}






}
