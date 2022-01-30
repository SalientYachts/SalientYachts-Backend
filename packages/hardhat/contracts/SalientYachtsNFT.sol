// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SalientYachtsStream.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SalientYachtsNFT is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    //assume Yacht price is $600,000 -> we will have 6000 tokens at $100 each
    //assume AVAX is $100 (might considuer using Chainlink AVAX / USD) -> supply is 6000 tokens
    //uint256 public constant mintPrice = 1 ether; // assume AVAX is $100 -> $1000 = 10 AVAX
    uint8   private constant mintLimit          = 20;
    uint256 private constant tenYearDeposit     = 2399999999999765395680;
    uint8   private constant nftPriceDecimals   = 18;
    uint256 private constant nftMintPrice       = 100 * (10 ** nftPriceDecimals); //mint price fixed at $100
    uint16  private constant supplyLimit        = 6000; //assume Yacht price is $600,000 -> we will have 6000 tokens at $100 each
    uint256 private constant TEN_YEARS          = 315569520; //10 years -> 315,569,520 seconds
    uint256 private constant NFT_FIXED_AVAX_PRICE = 10000000000000000; //0.01 AVAX (for testing purposes)

    address private priceFeedAddr;
    AggregatorV3Interface internal priceFeed;
    Counters.Counter private _tokenIdCounter; 
    bool public saleActive = false;                           
    address private rewardContractAddress;
    SalientYachtsStream public streamContract;
    mapping(address => mapping(uint256 => uint256)) private nftOwnerToTokenIdToStreamId;
    uint256 private priceCheckInterval = 10 minutes;
    bool private useFixedAvaxPrice = true;
    
    struct NFTPrice {
        int256 price;
        uint256 lastRetreivedAt;
    }
    NFTPrice private nftPrice;

    constructor(address _rewardContractAddress, address _priceFeedAddr) ERC721("Salient Yachts", "SYONE") {
        rewardContractAddress = _rewardContractAddress;
        priceFeedAddr = _priceFeedAddr;
        priceFeed = AggregatorV3Interface(priceFeedAddr);
        streamContract = new SalientYachtsStream();
        nftPrice = NFTPrice({price : getLatestNFTPrice(nftPriceDecimals), lastRetreivedAt : block.timestamp});
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://nft.salientyachts.com";
    }

    function toggleSaleActive() public onlyOwner {
        saleActive = !saleActive;
    }

    function toggleUseFixedAvaxPrice() public onlyOwner {
        useFixedAvaxPrice = !useFixedAvaxPrice;
    }

    function setPriceCheckInterval(uint256 _priceCheckInterval) public onlyOwner {
        priceCheckInterval = _priceCheckInterval;
    }

    function buyYachtNFT(uint numberOfTokens) public payable {
        require(saleActive, "Sale is not active");
        require(numberOfTokens <= mintLimit, "No more than 20 yacht NFT's at a time");
        uint256 currentNFTPrice = uint256(getLatestNFTPrice(nftPriceDecimals));
        require(msg.value >= currentNFTPrice * numberOfTokens, "Insufficient payment");
        require(totalSupply() + numberOfTokens <= supplyLimit, "Not enough yacht NFT's left");
        
        //mint the NFT(s)
        uint256 startTime = block.timestamp + 60; // 1 minute from now
        uint256 stopTime = block.timestamp + TEN_YEARS + 60; // 10 years and 1 minute from now
        uint256 deposit = numberOfTokens * tenYearDeposit;
        IERC20(rewardContractAddress).approve(address(streamContract), deposit);

        for(uint i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(msg.sender, tokenId);
            console.log("buyYachtNFT: minted NFT with tokenId: %s", tokenId);

            uint256 streamId = streamContract.createStream(address(this), msg.sender, tenYearDeposit, rewardContractAddress, startTime, 
                stopTime, tokenId);
            nftOwnerToTokenIdToStreamId[msg.sender][tokenId] = streamId;
            console.log("buyYachtNFT: created reward stream with streamId: %s", streamId);
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
        console.log("_beforeTokenTransfer called - from: %s, to: %s, tokenId: %s", from, to, tokenId);
        
        if (from != address(0) && to != address(0) && from != to) {
            //cancel the reward stream for "from"
            uint256 fromStreamId = nftOwnerToTokenIdToStreamId[from][tokenId];
            require(fromStreamId > 0, "From stream id not found");
            (,,,,,uint256 oldStreamStopTime,uint256 oldStreamRemainingBalance,,uint256 oldStreamNftTokenId) = streamContract.getStream(fromStreamId);
            streamContract.cancelStream(fromStreamId);
            console.log("_beforeTokenTransfer cancelled stream: %s - from: %s", fromStreamId, from);

            //create a new stream for "to"
            uint256 startTime = block.timestamp;
            uint256 stopTime = oldStreamStopTime;
            uint256 duration = stopTime - startTime;
            uint256 streamAmt = oldStreamRemainingBalance - (oldStreamRemainingBalance % duration);
            IERC20(rewardContractAddress).approve(address(streamContract), tenYearDeposit);
            uint256 toStreamId = streamContract.createStream(address(this), to, streamAmt, rewardContractAddress, startTime, stopTime, 
                oldStreamNftTokenId);
            nftOwnerToTokenIdToStreamId[to][tokenId] = toStreamId;
            console.log("_beforeTokenTransfer created reward stream with streamId: %s for address: %s", toStreamId, to);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getLatestNFTPrice(uint8 _decimals) internal returns (int256) {
        if (useFixedAvaxPrice) {
            return int256(NFT_FIXED_AVAX_PRICE);
        } else {
            if (block.timestamp - nftPrice.lastRetreivedAt <= 10 minutes) {
                return nftPrice.price;
            } else {
                int256 decimals = int256(10 ** uint256(_decimals));
                uint8 baseDecimals = priceFeed.decimals();
                (
                    uint80 roundID, 
                    int price,
                    uint startedAt,
                    uint timeStamp,
                    uint80 answeredInRound
                ) = priceFeed.latestRoundData();
                require(price > 0, "Could not retrieve price of AVAX/USD");
                int256 basePrice = scalePrice(price, baseDecimals, _decimals);
                int256 newPrice = (int256(nftMintPrice) * decimals) / basePrice;
                nftPrice.price = newPrice;
                nftPrice.lastRetreivedAt = block.timestamp;
                return nftPrice.price;
            }
        }
    }

    function scalePrice(int256 _price, uint8 _priceDecimals, uint8 _decimals)
        internal
        pure
        returns (int256) 
    {
        if (_priceDecimals < _decimals) {
            return _price * int256(10 ** uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10 ** uint256(_priceDecimals - _decimals));
        }
        return _price;
    }

    function getCurrentPrice() public view returns (int256) {
        return nftPrice.price;
    }
}