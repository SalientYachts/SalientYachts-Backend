// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract SalientYachtsStream is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Stream {
        uint256 deposit;
        uint256 ratePerSecond;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime;
        address recipient;
        address sender;
        address tokenAddress;
        bool    isEntity;
        uint256 nftTokenId;
    }

    /**
     * @notice Counter for new stream ids.
     */
    uint256 public nextStreamId;

    /**
     * @notice The stream objects identifiable by their unsigned integer ids.
     */
    mapping(uint256 => Stream) private streams;

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     */
    modifier onlySenderOrRecipient(uint256 streamId) {
        require(
            msg.sender == streams[streamId].sender || msg.sender == streams[streamId].recipient,
            "caller is not the sender or the recipient of the stream"
        );
        _;
    }

    modifier onlySender(uint256 streamId) {
        require(
            msg.sender == streams[streamId].sender,
            "caller is not the sender of the stream"
        );
        _;
    }

    /**
     * @dev Throws if the provided id does not point to a valid stream.
     */
    modifier streamExists(uint256 streamId) {
        require(streams[streamId].isEntity, "stream does not exist");
        _;
    }

    /**
     * @notice Emits when a stream is successfully created.
     */
    event CreateStream(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 nftTokenId,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint256 ratePerSecond
    );

    /**
     * @notice Emits when the recipient of a stream withdraws a portion or all their pro rata share of the stream.
     */
    event WithdrawFromStream(uint256 indexed streamId, address indexed recipient, uint256 amount);

    event WithdrawFromStreams(uint256[] streamIdList, address indexed recipient, uint256 amount);

    /**
     * @notice Emits when a stream is successfully cancelled and tokens are transferred back on a pro rata basis.
     */
    event CancelStream(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 nftTokenId,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    constructor() {
        nextStreamId = 200000;
    }

    /**
     * @notice Returns the stream with all its properties.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream to query.
     * @return sender stream sender,
       @return recipient stream recipient,
       @return deposit stream deposit amount,
       @return tokenAddress stream token address,
       @return startTime stream start time,
       @return stopTime stream stop time,
       @return remainingBalance stream remaining balance,
       @return ratePerSecond stream rate per second
     */
    function getStream(uint256 streamId)
        external
        view
        streamExists(streamId)
        returns (
            address sender,
            address recipient,
            uint256 deposit,
            address tokenAddress,
            uint256 startTime,
            uint256 stopTime,
            uint256 remainingBalance,
            uint256 ratePerSecond,
            uint256 nftTokenId
        )
    {
        sender = streams[streamId].sender;
        recipient = streams[streamId].recipient;
        deposit = streams[streamId].deposit;
        tokenAddress = streams[streamId].tokenAddress;
        startTime = streams[streamId].startTime;
        stopTime = streams[streamId].stopTime;
        remainingBalance = streams[streamId].remainingBalance;
        ratePerSecond = streams[streamId].ratePerSecond;
        nftTokenId = streams[streamId].nftTokenId;
    }

    /**
     * @notice Returns either the delta in seconds between `block.timestamp` and `startTime` or
     *  between `stopTime` and `startTime, whichever is smaller. If `block.timestamp` is before
     *  `startTime`, it returns 0.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the delta.
     * @return delta The time delta in seconds.
     */
    function deltaOf(uint256 streamId) public view streamExists(streamId) returns (uint256 delta) {
        Stream memory stream = streams[streamId];
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp < stream.stopTime) return block.timestamp - stream.startTime;
        return stream.stopTime - stream.startTime;
    }

    struct BalanceOfLocalVars {
        uint256 recipientBalance;
        uint256 withdrawalAmount;
        uint256 senderBalance;
    }

     /**
     * @notice Returns the available funds for the given stream id and address.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the balance.
     * @param who The address for which to query the balance.
     * @return balance The total funds allocated to `who` as uint256.
     */
    function balanceOf(uint256 streamId, address who) public view streamExists(streamId) returns (uint256 balance) {
        Stream memory stream = streams[streamId];
        BalanceOfLocalVars memory vars;

        uint256 delta = deltaOf(streamId);
        console.log("balanceOf: delta = %s", delta);
        vars.recipientBalance = delta * stream.ratePerSecond;
        console.log("balanceOf: vars.recipientBalance = %s", vars.recipientBalance);

        /*
         * If the stream `balance` does not equal `deposit`, it means there have been withdrawals.
         * We have to subtract the total amount withdrawn from the amount of money that has been
         * streamed until now.
         */
        if (stream.deposit > stream.remainingBalance) {
            vars.withdrawalAmount = stream.deposit - stream.remainingBalance;
            vars.recipientBalance = vars.recipientBalance - vars.withdrawalAmount;
            /* `withdrawalAmount` cannot and should not be bigger than `recipientBalance`. */
        }

        if (who == stream.recipient) return vars.recipientBalance;
        if (who == stream.sender) {
            vars.senderBalance = stream.remainingBalance - vars.recipientBalance;
            /* `recipientBalance` cannot and should not be bigger than `remainingBalance`. */
            return vars.senderBalance;
        }
        return 0;
    }

    function balanceOfStreams(uint256[] memory streamIdList, address who) public view returns (uint256 totalBalance) {
        require(streamIdList.length > 0, "Stream id list is empty");
        require(streamIdList.length <= 20, "Can only get balances for 20 streams at a time");
        require(who != address(0), "Zero address is not allowed");
        for (uint256 i = 0; i < streamIdList.length; i++) {
            totalBalance += balanceOf(streamIdList[i], who);
        }
    }

    struct CreateStreamLocalVars {
        uint256 duration;
        uint256 ratePerSecond;
    }

    /**
     * @notice Creates a new stream funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the deposit is 0.
     *  Throws if the start time is before `block.timestamp`.
     *  Throws if the stop time is before the start time.
     *  Throws if the duration calculation has a math error.
     *  Throws if the deposit is smaller than the duration.
     *  Throws if the deposit is not a multiple of the duration.
     *  Throws if the rate calculation has a math error.
     *  Throws if the next stream id calculation has a math error.
     *  Throws if the contract is not allowed to transfer enough tokens.
     *  Throws if there is a token transfer failure.
     * @param _recipient The address towards which the money is streamed.
     * @param _deposit The amount of money to be streamed.
     * @param _tokenAddress The ERC20 token to use as streaming currency.
     * @param _startTime The unix timestamp for when the stream starts.
     * @param _stopTime The unix timestamp for when the stream stops.
     * @param _nftTokenId the token Id of the NFT for which this stream is being created.
     * @return The uint256 id of the newly created stream.
     */
    function createStream(address _sender, address _recipient, uint256 _deposit, address _tokenAddress, uint256 _startTime, 
            uint256 _stopTime, uint256 _nftTokenId)
        public
        onlyOwner 
        returns (uint256)
    {
        require(_recipient != address(0x00), "stream to the zero address");
        require(_recipient != address(this), "stream to the contract itself");
        require(_recipient != _sender, "stream to the caller");
        require(_deposit > 0, "deposit is zero");
        require(_startTime >= block.timestamp, "start time before block.timestamp");
        require(_stopTime > _startTime, "stop time before the start time");

        CreateStreamLocalVars memory vars;
        vars.duration = _stopTime - _startTime;

        /* Without this, the rate per second would be zero. */
        require(_deposit >= vars.duration, "deposit smaller than time delta");

        /* This condition avoids dealing with remainders */
        require(_deposit % vars.duration == 0, "deposit not multiple of time delta");

        vars.ratePerSecond = _deposit / vars.duration;

        /* Create and store the stream object. */
        uint256 streamId = nextStreamId;
        streams[streamId] = Stream({
            remainingBalance: _deposit,
            deposit: _deposit,
            isEntity: true,
            ratePerSecond: vars.ratePerSecond,
            recipient: _recipient,
            sender: _sender,
            startTime: _startTime,
            stopTime: _stopTime,
            tokenAddress: _tokenAddress,
            nftTokenId: _nftTokenId
        });

        /* Increment the next stream id. */
        nextStreamId = nextStreamId + uint256(1);

        IERC20(_tokenAddress).safeTransferFrom(_sender, address(this), _deposit);
        emit CreateStream(streamId, _sender, _recipient, _nftTokenId, _deposit, _tokenAddress, _startTime, _stopTime, vars.ratePerSecond);
        return streamId;
    }

    /**
     * @notice Withdraws from the contract to the recipient's account.
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the caller is not the sender or the recipient of the stream.
     *  Throws if the amount exceeds the available balance.
     *  Throws if there is a token transfer failure.
     * @param streamId The id of the stream to withdraw tokens from.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawFromStream(uint256 streamId, uint256 amount)
        external
        nonReentrant
        streamExists(streamId)
        onlySenderOrRecipient(streamId)
        returns (bool)
    {
        require(amount > 0, "amount is zero");
        Stream memory stream = streams[streamId];

        uint256 balance = balanceOf(streamId, stream.recipient);
        require(balance >= amount, "amount exceeds the available balance");

        streams[streamId].remainingBalance = stream.remainingBalance - amount;

        if (streams[streamId].remainingBalance == 0) delete streams[streamId];

        IERC20(stream.tokenAddress).safeTransfer(stream.recipient, amount);
        emit WithdrawFromStream(streamId, stream.recipient, amount);
        return true;
    }

    function withdrawFromStreams(uint256[] memory streamIdList) external nonReentrant returns (bool) {
        require(streamIdList.length > 0, "Stream id list is empty");
        require(streamIdList.length <= 20, "Can only withdraw from 20 streams at a time");
        uint256 totalTokenWithdrawal;
        address streamTokenAddr;
        for (uint256 i = 0; i < streamIdList.length; i++) {
            uint256 streamId = streamIdList[i];
            require(streams[streamId].isEntity, "stream does not exist");
            Stream memory stream = streams[streamId];
            require(stream.tokenAddress == streamTokenAddr || streamTokenAddr == address(0), "Can not mix streams with different token addresses");
            streamTokenAddr = stream.tokenAddress;
            require(msg.sender == stream.recipient, "caller is not the recipient of the stream");
            uint256 amount = balanceOf(streamId, stream.recipient);
            totalTokenWithdrawal += amount;
            streams[streamId].remainingBalance = stream.remainingBalance - amount;
            if (streams[streamId].remainingBalance == 0) delete streams[streamId];
        }
        if (totalTokenWithdrawal > 0 && streamTokenAddr != address(0)) {
            IERC20(streamTokenAddr).safeTransfer(msg.sender, totalTokenWithdrawal);
            emit WithdrawFromStreams(streamIdList, msg.sender, totalTokenWithdrawal);
        }
        return true;
    }

    /**
     * @notice Cancels the stream and transfers the tokens back on a pro rata basis.
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the caller is not the sender or the recipient of the stream.
     *  Throws if there is a token transfer failure.
     * @param streamId The id of the stream to cancel.
     * @return bool true=success, otherwise false.
     */
    function cancelStream(uint256 streamId)
        external
        nonReentrant
        streamExists(streamId)
        onlySender(streamId)
        returns (bool)
    {
        Stream memory stream = streams[streamId];
        uint256 senderBalance = balanceOf(streamId, stream.sender);
        uint256 recipientBalance = balanceOf(streamId, stream.recipient);

        delete streams[streamId];

        IERC20 token = IERC20(stream.tokenAddress);
        if (recipientBalance > 0) token.safeTransfer(stream.recipient, recipientBalance);
        if (senderBalance > 0) token.safeTransfer(stream.sender, senderBalance);

        emit CancelStream(streamId, stream.sender, stream.recipient, stream.nftTokenId, senderBalance, recipientBalance);
        return true;
    }
}