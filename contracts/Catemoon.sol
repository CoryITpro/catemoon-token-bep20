// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * MM     MM EEEEEEEE  OOOOOO  WW     WW
 * MMM   MMM EE       OO    OO WW  W  WW
 * MMMM MMMM EEEEEE   OO    OO WWwW WWWW
 * MM  M  MM EE       OO    OO WWW   WWW
 * MM     MM EEEEEEEE  OOOOOO  WW     WW
 *
 *
 * CATEMOON | CTM
 * #LIQ
 * 
 * # Catemoon features:
 *    5% fee auto add to the LP to locked forever when selling
 *    50% supply is burned at the start
 */

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./Ownable.sol";

contract Catemoon is Context, IERC20, IERC20Metadata, Ownable {
  using Address for address;

  mapping(address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;

  mapping(address => bool) private _isExcludedFromFee;

  uint256 private constant TOTAL_SUPPLY = 2 * 10**2 * 10**9 * 10**18; // Total supply is 200 billion

  string private _name = "Catemoon";
  string private _symbol = "CTM";
  uint8 private _decimals = 18;
  uint256 private _totalSupply;

  // 5% liquidity fee
  uint256 public _liquidityFee = 5;
  uint256 private _previousLiquidityFee = _liquidityFee;

  uint256 public _maxTxAmount = 2 * 10**9 * 10**18; // 2% of total supply
  uint256 private numTokensSellToAddToLiquidity = 5 * 10**7 * 10**18; // 0.05% of total supply

  IUniswapV2Router02 public immutable uniswapV2Router;
  address public immutable uniswapV2Pair;

  bool inSwapAndLiquify;
  bool public swapAndLiquifyEnabled = true;

  event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
  event SwapAndLiquifyEnabledUpdated(bool enabled);
  event SwapAndLiquify(
    uint256 tokensSwapped,
    uint256 ethReceived,
    uint256 tokensIntoLiqudity
  );

  modifier lockTheSwap {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  constructor () {
    
    // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    // 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // Create a uniswap pair for this new token
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

    // set the rest of the contract variables
    uniswapV2Router = _uniswapV2Router;

    _isExcludedFromFee[owner()] = true;
    _isExcludedFromFee[address(this)] = true;

    _mint(msg.sender, TOTAL_SUPPLY);
    _burn(msg.sender, TOTAL_SUPPLY / 2);
  }

  function name() public view virtual returns (string memory) {
    return _name;
  }

  function symbol() public view virtual returns (string memory) {
    return _symbol;
  }

  function decimals() public view virtual returns (uint8) {
    return _decimals;
  }

  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address account) public view virtual override returns (uint256) {
    return _balances[account];
  }

  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) public view virtual override returns (uint256) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) public virtual override returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
      _transfer(sender, recipient, amount);
      uint256 currentAllowance = _allowances[sender][_msgSender()];
      require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
      unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
      }

      return true;
  }

  function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
    uint256 currentAllowance = _allowances[_msgSender()][spender];
    require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
      _approve(_msgSender(), spender, currentAllowance - subtractedValue);
    }

    return true;
  }

  function isExcludedFromFee(address account) public view returns(bool) {
    return _isExcludedFromFee[account];
  }

  function includeInFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = false;
  }

  function excludeFromFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = true;
  }

  function removeAllFee() private {
    if(_liquidityFee == 0) return;
    
    _previousLiquidityFee = _liquidityFee;
    _liquidityFee = 0;
  }
  
  function restoreAllFee() private {
    _liquidityFee = _previousLiquidityFee;
  }

  // This method is responsible for taking all fee, if takeFee is true
  function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
    if(!takeFee) {
      removeAllFee();
    }
    
    // Calculate liquidity fee and actual transfer amount
    (uint256 transferAmount, uint256 liquidityFee) = _getValues(amount);

    uint256 senderBalance = _balances[sender];
    require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
      // Decrease sender balance
      _balances[sender] = senderBalance - amount;
    }
    // Increase recipient balance
    _balances[recipient] += transferAmount;

    // Increase contract balance with liquidity fee
    _balances[address(this)] = _balances[address(this)] + liquidityFee;

    // Emit token transfer event
    emit Transfer(sender, recipient, transferAmount);
    
    if(!takeFee) {
      restoreAllFee();
    }
  }

  function _getValues(uint256 _amount) private view returns (uint256, uint256) {
    uint256 liquidityFee = calculateLiquidityFee(_amount);
    uint256 transferAmount = _amount - liquidityFee;
    return (transferAmount, liquidityFee);
  }

  function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
    return _amount * _liquidityFee / 10**2;
  }

  function _transfer(address sender, address recipient, uint256 amount) internal virtual {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "ERC20: Transfer amount must be greater than zero");

    if(sender != owner() && recipient != owner()) {
      require(amount <= _maxTxAmount, "ERC20: Transfer amount exceeds the maxTxAmount.");
    }

    uint256 contractTokenBalance = balanceOf(address(this));
    if(contractTokenBalance >= _maxTxAmount)
    {
      contractTokenBalance = _maxTxAmount;
    }
    bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;

    // When the balance of the contract reaches the minimum available amount 
    // and it is not in the middle of swap and when the swap and liquify feature has been enabled, 
    // when it is for the sell.
    if (overMinTokenBalance && !inSwapAndLiquify && sender != uniswapV2Pair && swapAndLiquifyEnabled) {
      contractTokenBalance = numTokensSellToAddToLiquidity;
      //add liquidity
      swapAndLiquify(contractTokenBalance);
    }

    //indicates if fee should be deducted from transfer
    bool takeFee = false;
    
    if(recipient == uniswapV2Pair){
      takeFee = true;
    }

    //if any account belongs to _isExcludedFromFee account then remove the fee
    if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]){
      takeFee = false;
    }
    
    //transfer amount, it will take tax, burn, liquidity fee
    _tokenTransfer(sender, recipient, amount, takeFee);
  }

  function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
    // split the contract balance into halves
    uint256 half = contractTokenBalance / 2;
    uint256 otherHalf = contractTokenBalance - half;

    // capture the contract's current ETH balance.
    // this is so that we can capture exactly the amount of ETH that the
    // swap creates, and not make the liquidity event include any ETH that
    // has been manually sent to the contract
    uint256 initialBalance = address(this).balance;

    // swap tokens for ETH
    swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap + liquify is triggered

    // how much ETH did we just swap into?
    uint256 newBalance = address(this).balance - initialBalance;

    // add liquidity to uniswap
    addLiquidity(otherHalf, newBalance);
    
    emit SwapAndLiquify(half, newBalance, otherHalf);
  }

  function swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    // approve token transfer to cover all possible scenarios
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // add the liquidity
    uniswapV2Router.addLiquidityETH{value: ethAmount}(
      address(this),
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      owner(),
      block.timestamp
    );
  }

  function _mint(address account, uint256 amount) internal virtual {
    require(account != address(0), "ERC20: mint to the zero address");

    _totalSupply += amount;
    _balances[account] += amount;
    emit Transfer(address(0), account, amount);
  }

  function _burn(address account, uint256 amount) internal virtual {
    require(account != address(0), "ERC20: burn from the zero address");

    uint256 accountBalance = _balances[account];
    require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
      _balances[account] = accountBalance - amount;
    }
    _totalSupply -= amount;

    emit Transfer(account, address(0), amount);
  }

  function _approve(address owner, address spender, uint256 amount) internal virtual {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
    swapAndLiquifyEnabled = _enabled;
    emit SwapAndLiquifyEnabledUpdated(_enabled);
  }

  function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
    _liquidityFee = liquidityFee;
  }

  function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner() {
    _maxTxAmount = _totalSupply * maxTxPercent / 10**2;
  }
  
  //to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}
}