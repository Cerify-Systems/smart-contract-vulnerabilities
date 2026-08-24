// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import '../interfaces/IUniswapV2Pair.sol';
import '../interfaces/IUniswapV3Pool.sol';
import '../interfaces/ITridentCLPool.sol';
import '../interfaces/IBentoBoxMinimal.sol';
import '../interfaces/IPool.sol';
import '../interfaces/IWETH.sol';
import './InputStream.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

address constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address constant IMPOSSIBLE_POOL_ADDRESS = 0x0000000000000000000000000000000000000001;

uint160 constant MIN_SQRT_RATIO = 4295128739;
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

/// @title A route processor for the Sushi Aggregator
/// @author Ilya Lyalin
contract RouteProcessor2 {
  using SafeERC20 for IERC20;
  using InputStream for uint256;

  IBentoBoxMinimal public immutable bentoBox;
  address private lastCalledPool;

  uint private unlocked = 1;
  modifier lock() {
      require(unlocked == 1, 'RouteProcessor is locked');
      unlocked = 2;
      _;
      unlocked = 1;
  }

  constructor(address _bentoBox) {
      bentoBox = IBentoBoxMinimal(_bentoBox);
      lastCalledPool = IMPOSSIBLE_POOL_ADDRESS;
  }

  receive() external payable {}

  function processRoute(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMin,
    address to,
    bytes memory route
  ) external payable lock returns (uint256 amountOut) {
    return processRouteInternal(tokenIn, amountIn, tokenOut, amountOutMin, to, route);
  }

  function transferValueAndprocessRoute(
    address payable transferValueTo,
    uint256 amountValueTransfer,
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMin,
    address to,
    bytes memory route
  ) external payable lock returns (uint256 amountOut) {
    (bool success, bytes memory returnBytes) =
        transferValueTo.call{value: amountValueTransfer}('');
    require(success, string(abi.encodePacked(returnBytes)));
    return processRouteInternal(tokenIn, amountIn, tokenOut, amountOutMin, to, route);
  }

  function processRouteInternal(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMin,
    address to,
    bytes memory route
  ) private returns (uint256 amountOut) {
    uint256 balanceInInitial =
        tokenIn == NATIVE_ADDRESS
            ? address(this).balance
            : IERC20(tokenIn).balanceOf(msg.sender);

    uint256 balanceOutInitial =
        tokenOut == NATIVE_ADDRESS
            ? address(to).balance
            : IERC20(tokenOut).balanceOf(to);

    uint256 stream = InputStream.createStream(route);

    while (stream.isNotEmpty()) {
      uint8 commandCode = stream.readUint8();

      if (commandCode == 1) processMyERC20(stream);
      else if (commandCode == 2) processUserERC20(stream, amountIn);
      else if (commandCode == 3) processNative(stream);
      else if (commandCode == 4) processOnePool(stream);
      else if (commandCode == 5) processInsideBento(stream);
      else revert('RouteProcessor: Unknown command code');
    }

    uint256 balanceInFinal =
        tokenIn == NATIVE_ADDRESS
            ? address(this).balance
            : IERC20(tokenIn).balanceOf(msg.sender);

    require(
        balanceInFinal + amountIn >= balanceInInitial,
        'RouteProcessor: Minimal imput balance violation'
    );

    uint256 balanceOutFinal =
        tokenOut == NATIVE_ADDRESS
            ? address(to).balance
            : IERC20(tokenOut).balanceOf(to);

    require(
        balanceOutFinal >= balanceOutInitial + amountOutMin,
        'RouteProcessor: Minimal ouput balance violation'
    );

    amountOut = balanceOutFinal - balanceOutInitial;
  }

  function processNative(uint256 stream) private {
    uint256 amountTotal = address(this).balance;
    distributeAndSwap(stream, address(this), NATIVE_ADDRESS, amountTotal);
  }

  function processMyERC20(uint256 stream) private {
    address token = stream.readAddress();
    uint256 amountTotal = IERC20(token).balanceOf(address(this));

    unchecked {
      if (amountTotal > 0) amountTotal -= 1;
    }

    distributeAndSwap(stream, address(this), token, amountTotal);
  }

  function processUserERC20(uint256 stream, uint256 amountTotal) private {
    address token = stream.readAddress();
    distributeAndSwap(stream, msg.sender, token, amountTotal);
  }

  function distributeAndSwap(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountTotal
  ) private {
    uint8 num = stream.readUint8();

    unchecked {
      for (uint256 i = 0; i < num; ++i) {
        uint16 share = stream.readUint16();
        uint256 amount = (amountTotal * share) / 65535;
        amountTotal -= amount;
        swap(stream, from, tokenIn, amount);
      }
    }
  }

  function processOnePool(uint256 stream) private {
    address token = stream.readAddress();
    swap(stream, address(this), token, 0);
  }

  function processInsideBento(uint256 stream) private {
    address token = stream.readAddress();
    uint8 num = stream.readUint8();

    uint256 amountTotal = bentoBox.balanceOf(token, address(this));

    unchecked {
      if (amountTotal > 0) amountTotal -= 1;

      for (uint256 i = 0; i < num; ++i) {
        uint16 share = stream.readUint16();
        uint256 amount = (amountTotal * share) / 65535;
        amountTotal -= amount;
        swap(stream, address(this), token, amount);
      }
    }
  }

  function swap(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    uint8 poolType = stream.readUint8();

    if (poolType == 0) swapUniV2(stream, from, tokenIn, amountIn);
    else if (poolType == 1) swapUniV3(stream, from, tokenIn, amountIn);
    else if (poolType == 2) wrapNative(stream, from, tokenIn, amountIn);
    else if (poolType == 3) bentoBridge(stream, from, tokenIn, amountIn);
    else if (poolType == 4) swapTrident(stream, from, tokenIn, amountIn);
    else if (poolType == 5) swapTridentCL(stream, from, tokenIn, amountIn);
    else revert('RouteProcessor: Unknown pool type');
  }

  function wrapNative(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    uint8 directionAndFake = stream.readUint8();
    address to = stream.readAddress();

    if (directionAndFake & 1 == 1) {
      address wrapToken = stream.readAddress();

      if (directionAndFake & 2 == 0)
        IWETH(wrapToken).deposit{value: amountIn}();

      if (to != address(this))
        IERC20(wrapToken).safeTransfer(to, amountIn);
    } else {
      if (directionAndFake & 2 == 0) {
        if (from != address(this))
          IERC20(tokenIn).safeTransferFrom(from, address(this), amountIn);

        IWETH(tokenIn).withdraw(amountIn);
      }

      payable(to).transfer(address(this).balance);
    }
  }

  function bentoBridge(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    uint8 direction = stream.readUint8();
    address to = stream.readAddress();

    if (direction > 0) {
      if (amountIn != 0) {
        if (from == address(this))
          IERC20(tokenIn).safeTransfer(address(bentoBox), amountIn);
        else
          IERC20(tokenIn).safeTransferFrom(from, address(bentoBox), amountIn);
      } else {
        amountIn =
            IERC20(tokenIn).balanceOf(address(bentoBox)) +
            bentoBox.strategyData(tokenIn).balance -
            bentoBox.totals(tokenIn).elastic;
      }

      bentoBox.deposit(tokenIn, address(bentoBox), to, amountIn, 0);
    } else {
      if (amountIn > 0) {
        bentoBox.transfer(tokenIn, from, address(this), amountIn);
      } else {
        amountIn = bentoBox.balanceOf(tokenIn, address(this));
      }

      bentoBox.withdraw(tokenIn, address(this), to, 0, amountIn);
    }
  }

  function swapUniV2(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    address pool = stream.readAddress();
    uint8 direction = stream.readUint8();
    address to = stream.readAddress();

    (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pool).getReserves();

    require(r0 > 0 && r1 > 0, 'Wrong pool reserves');

    (uint256 reserveIn, uint256 reserveOut) =
        direction == 1 ? (r0, r1) : (r1, r0);

    if (amountIn != 0) {
      if (from == address(this))
        IERC20(tokenIn).safeTransfer(pool, amountIn);
      else
        IERC20(tokenIn).safeTransferFrom(from, pool, amountIn);
    } else {
      amountIn = IERC20(tokenIn).balanceOf(pool) - reserveIn;
    }

    uint256 amountInWithFee = amountIn * 997;
    uint256 amountOut =
        (amountInWithFee * reserveOut) /
        (reserveIn * 1000 + amountInWithFee);

    (uint256 amount0Out, uint256 amount1Out) =
        direction == 1
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));

    IUniswapV2Pair(pool).swap(
        amount0Out,
        amount1Out,
        to,
        new bytes(0)
    );
  }

  function swapTrident(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    address pool = stream.readAddress();
    bytes memory swapData = stream.readBytes();

    if (amountIn != 0) {
      bentoBox.transfer(tokenIn, from, pool, amountIn);
    }

    IPool(pool).swap(swapData);
  }

  function swapUniV3(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    address pool = stream.readAddress();
    bool zeroForOne = stream.readUint8() > 0;
    address recipient = stream.readAddress();

    lastCalledPool = pool;

    IUniswapV3Pool(pool).swap(
      recipient,
      zeroForOne,
      int256(amountIn),
      zeroForOne
        ? MIN_SQRT_RATIO + 1
        : MAX_SQRT_RATIO - 1,
      abi.encode(tokenIn, from)
    );

    require(
      lastCalledPool == IMPOSSIBLE_POOL_ADDRESS,
      'RouteProcessor.swapUniV3: unexpected'
    );
  }

  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external {
    require(
      msg.sender == lastCalledPool,
      'RouteProcessor.uniswapV3SwapCallback: call from unknown source'
    );

    lastCalledPool = IMPOSSIBLE_POOL_ADDRESS;

    (address tokenIn, address from) =
        abi.decode(data, (address, address));

    int256 amount =
        amount0Delta > 0 ? amount0Delta : amount1Delta;

    require(
      amount > 0,
      'RouteProcessor.uniswapV3SwapCallback: not positive amount'
    );

    if (from == address(this))
      IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount));
    else
      IERC20(tokenIn).safeTransferFrom(
          from,
          msg.sender,
          uint256(amount)
      );
  }

  function swapTridentCL(
    uint256 stream,
    address from,
    address tokenIn,
    uint256 amountIn
  ) private {
    address pool = stream.readAddress();
    bool zeroForOne = stream.readUint8() > 0;
    address recipient = stream.readAddress();

    lastCalledPool = pool;

    ITridentCLPool(pool).swap(
      recipient,
      zeroForOne,
      int256(amountIn),
      zeroForOne
        ? MIN_SQRT_RATIO + 1
        : MAX_SQRT_RATIO - 1,
      false,
      abi.encode(tokenIn, from)
    );

    require(
      lastCalledPool == IMPOSSIBLE_POOL_ADDRESS,
      'RouteProcessor.swapTridentCL: unexpected'
    );
  }

  function tridentCLSwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external {
    require(
      msg.sender == lastCalledPool,
      'RouteProcessor.TridentCLSwapCallback: call from unknown source'
    );

    lastCalledPool = IMPOSSIBLE_POOL_ADDRESS;

    (address tokenIn, address from) =
        abi.decode(data, (address, address));

    int256 amount =
        amount0Delta > 0 ? amount0Delta : amount1Delta;

    require(
      amount > 0,
      'RouteProcessor.TridentCLSwapCallback: not positive amount'
    );

    if (from == address(this))
      IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount));
    else
      IERC20(tokenIn).safeTransferFrom(
          from,
          msg.sender,
          uint256(amount)
      );
  }
}
