// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SalientYachtsStream.sol";
import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SalientYachtsSYONE_v07 is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    uint8   private constant MINT_LIMT              = 20;
    uint256 private constant TEN_YEAR_DEPOSIT       = 2399999999999765395680;
    uint8   private constant NFT_PRICE_DECIMALS     = 18;
    uint256 private constant NFT_MINT_PRICE_USD     = 100 * (10 ** NFT_PRICE_DECIMALS); //mint price fixed at $100
    uint256 private constant NFT_MINT_PRICE_ETH     = 400000000000000000; //0.40 BNB
    uint16  private constant SUPPLY_LIMIT           = 20000; //assume Yacht price is $2,000,000 -> we will have 20000 tokens at $100 each
    uint256 private constant TEN_YEARS              = 315569520; //10 years -> 315,569,520 seconds

    enum NFTType {
        Common,
        Rare,
        Ultra
    }
    struct NFTTypeData {
        string uriPart;
        uint256 mintPrice;
        uint256 rewardAmount;
        uint8   multiplier;
        bool    isSet;
    }
    struct NFTSale {
        uint256 saleDate;
        uint256 numberOfNfts;
        NFTType nftType;
    }

    bool public saleActive = false;
    SalientYachtsStream public streamContract;
    bool public useFixedAvaxPrice = true;

    mapping(NFTType => NFTTypeData) private nftTypeToData;
    address private priceFeedAddr;
    AggregatorV3Interface internal priceFeed;
    Counters.Counter private _tokenIdCounter; 
    address private rewardContractAddress;
    mapping(address => mapping(uint256 => uint256)) private nftOwnerToTokenIdToStreamId;
    uint256 private mintedNFTScaledCount;
    mapping(bytes32 => NFTSale[]) private affiliateSales;
    uint256 private nftPriceSlippage = 20000000000000000; // 0.02 

    event AffiliateSale(bytes32 indexed _affiliateId, uint256 _numberOfTokens, NFTType _nftType);

    error InsufficientPayment(uint256 paymentAmount, uint256 paymentRequired, uint256 diffPerc);
    
    constructor(address _rewardContractAddress, address _priceFeedAddr) ERC721("Salient Yachts", "SYONE") {
        rewardContractAddress = _rewardContractAddress;
        priceFeedAddr = _priceFeedAddr;
        priceFeed = AggregatorV3Interface(priceFeedAddr);
        streamContract = new SalientYachtsStream();
        
        nftTypeToData[NFTType.Common] = NFTTypeData('bafyreihmx5rptcqfl2uwxdk5kategwa3ygssfmusj2fxlkdldbf7ezc5q4/metadata.json', 
            NFT_MINT_PRICE_ETH, TEN_YEAR_DEPOSIT, 1, true);

        nftTypeToData[NFTType.Rare]   = NFTTypeData('bafyreid46czh77qyamtnlsit4qieaoynu6sjn2klcjfvlwbp3gju2o5mly/metadata.json', 
            NFT_MINT_PRICE_ETH * 10, TEN_YEAR_DEPOSIT * 10, 10, true);

        nftTypeToData[NFTType.Ultra]  = NFTTypeData('bafyreig6zlp6b5mdpuw4kgyibae4kgoma6nczqmgqdjvpem54xfrqgsllm/metadata.json', 
            NFT_MINT_PRICE_ETH * 100, TEN_YEAR_DEPOSIT * 100, 100, true);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    function toggleSaleActive() public onlyOwner {
        saleActive = !saleActive;
    }

    function toggleUseFixedAvaxPrice() public onlyOwner returns (bool) {
        useFixedAvaxPrice = !useFixedAvaxPrice;
        return useFixedAvaxPrice;
    }

    function buyYachtNFT(uint256 numberOfTokens, NFTType nftType, string memory affiliateId) public payable {
        require(saleActive, "Sale is not active");
        require(numberOfTokens <= MINT_LIMT, "No more than 20 yacht NFT's at a time");
        uint256 currentNFTPrice = uint256(getLatestNFTPrice(NFT_PRICE_DECIMALS, nftType));
        console.log("currentNFTPrice: %s", currentNFTPrice);
        uint256 amtReq = currentNFTPrice * numberOfTokens;
        console.log("amtReq: %s", amtReq);
        if (amtReq > msg.value) {
            console.log("amtReq > msg.value");
            uint256 priceDiff = amtReq - msg.value;
            console.log("priceDiff: %s", priceDiff);
            if (useFixedAvaxPrice) {
                revert InsufficientPayment(msg.value, amtReq, priceDiff);
            } else {
                if (priceDiff > nftPriceSlippage) {
                    console.log("priceDiff > nftPriceSlippage");
                    revert InsufficientPayment(msg.value, amtReq, priceDiff);
                }
            }
        }
        // require(msg.value >= currentNFTPrice * numberOfTokens, "Insufficient payment");
        NFTTypeData storage nftTypeData = nftTypeToData[nftType];
        require(nftTypeData.isSet, "Can't obtain NFT type data. Invalid NFT type");
        require(mintedNFTScaledCount + (nftTypeData.multiplier * numberOfTokens)  <= SUPPLY_LIMIT, "Not enough yacht NFT's left");
        
        //mint the NFT(s)
        mintedNFTScaledCount += nftTypeData.multiplier * numberOfTokens;
        uint256 startTime = block.timestamp + 60; // 1 minute from now
        uint256 stopTime = block.timestamp + TEN_YEARS + 60; // 10 years and 1 minute from now
        uint256 deposit = numberOfTokens * nftTypeData.rewardAmount;
        IERC20(rewardContractAddress).approve(address(streamContract), deposit);

        for(uint i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(msg.sender, tokenId);
            console.log("buyYachtNFT: minted NFT with tokenId: %s", tokenId);
            _setTokenURI(tokenId, nftTypeData.uriPart);
            console.log("buyYachtNFT: tokenURI: %s", tokenURI(tokenId));

            uint256 streamId = streamContract.createStream(address(this), msg.sender, nftTypeData.rewardAmount, rewardContractAddress, startTime, 
                stopTime, tokenId);
            nftOwnerToTokenIdToStreamId[msg.sender][tokenId] = streamId;
            console.log("buyYachtNFT: created reward stream with streamId: %s", streamId);
        }

        if (bytes(affiliateId).length > 0) {
            bytes32 affIdHash = keccak256(abi.encode(affiliateId));
            NFTSale memory theSale = NFTSale(block.timestamp, numberOfTokens, nftType);
            affiliateSales[affIdHash].push(theSale);
            emit AffiliateSale(affIdHash, numberOfTokens, nftType);
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
            nftOwnerToTokenIdToStreamId[from][tokenId] = 0;
            streamContract.cancelStream(fromStreamId);
            console.log("_beforeTokenTransfer cancelled stream: %s - from: %s", fromStreamId, from);

            //create a new stream for "to"
            uint256 startTime = block.timestamp;
            uint256 stopTime = oldStreamStopTime;
            uint256 duration = stopTime - startTime;
            uint256 streamAmt = oldStreamRemainingBalance - (oldStreamRemainingBalance % duration);
            IERC20(rewardContractAddress).approve(address(streamContract), streamAmt);
            uint256 toStreamId = streamContract.createStream(address(this), to, streamAmt, rewardContractAddress, startTime, stopTime, 
                oldStreamNftTokenId);
            nftOwnerToTokenIdToStreamId[to][tokenId] = toStreamId;
            console.log("_beforeTokenTransfer created reward stream with streamId: %s for address: %s", toStreamId, to);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function getLatestNFTPrice(uint8 _decimals, NFTType nftType) internal view returns (int256) {
        NFTTypeData storage nftTypeData = nftTypeToData[nftType];
        console.log("getLatestNFTPrice::nftTypeData.isSet %s", nftTypeData.isSet);
        require(nftTypeData.isSet, "Can't obtain NFT price. Invalid NFT type");
        if (useFixedAvaxPrice) {
            return int256(nftTypeData.mintPrice);
        } else {
            return initNFTPrice(_decimals, nftTypeData);
        }
    }

    function initNFTPrice(uint8 _decimals, NFTTypeData storage _nftTypeData) internal view returns (int256) {
        int256 decimals = int256(10 ** uint256(_decimals));
        uint8 baseDecimals = priceFeed.decimals();
        (, int price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Could not retrieve price of AVAX/USD");
        int256 basePrice = scalePrice(price, baseDecimals, _decimals);
        int256 newPrice = (int256(NFT_MINT_PRICE_USD) * decimals * int256(int8(_nftTypeData.multiplier))) / basePrice;
        return newPrice;
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

    function getRemainingNFTBalance() public view returns (uint256) {
        if (SUPPLY_LIMIT >= mintedNFTScaledCount) {
            return SUPPLY_LIMIT - mintedNFTScaledCount;
        } else {
            return 0;
        }
    }

    function getAffiliateSales(string memory inAffiliateId) public view returns (NFTSale[] memory) {
        require(bytes(inAffiliateId).length > 0, "Affiliate Id is blank");
        bytes32 affIdHash = keccak256(abi.encode(inAffiliateId));
        return affiliateSales[affIdHash];
    }

    function withdrawFunds() public onlyOwner {
        require(address(this).balance > 0, 'The balance is zero, nothing to withdraw');
        (bool sent, ) = owner().call{value: address(this).balance}("");
        require(sent, "Failed to send balance to the contract owner");
    }

    function setNftPriceSlippage(uint256 _nftPriceSlippage) public onlyOwner {
        require(_nftPriceSlippage > 0, "New value must be greater than 0");
        nftPriceSlippage = _nftPriceSlippage;
    }
}