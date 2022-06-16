// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SalientYachtsSYNFT is ERC721, ERC721URIStorage, Pausable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct NFTAttribute {
        string attrName;
        string attrValue;
    }

    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => bool) private tokenIdToDelivery;
    string private nftName;
    string private nftDescription;
    string private nftImage;
    string private nftExtURL;
    string private nftAnimationURL;
    mapping(uint256 => uint256) private tokenIdToNumOfAttr;
    mapping(uint256 => mapping(uint256 => NFTAttribute)) private tokenIdToAttributes;

    constructor() ERC721("Salient Yachts", "SYNFT") {}

    function safeMint(address to, string memory _nftName, string memory _nftDescription, string memory _nftImage, 
            string memory _nftExtURL, string memory _nftAnimationURL) public onlyOwner returns (uint256) {
        require(bytes(_nftName).length > 0, "NFT Name is empty");
        require(bytes(_nftImage).length > 0, "NFT Image URL is empty");
        nftName = _nftName;
        nftDescription = _nftDescription;
        nftImage = _nftImage;
        nftExtURL = _nftExtURL;
        nftAnimationURL = _nftAnimationURL;
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function safeMint(address to, string memory _nftName, string memory _nftDescription, string memory _nftImage, 
            string memory _nftExtURL, string memory _nftAnimationURL,
            string[] memory _attrNames, string[] memory _attrValues) public onlyOwner returns (uint256) {
        require(bytes(_nftName).length > 0, "NFT Name is empty");
        require(bytes(_nftImage).length > 0, "NFT Image URL is empty");
        require(_attrNames.length == _attrValues.length, "NFT attribute names and values arrays do not match in length");
        nftName = _nftName;
        nftDescription = _nftDescription;
        nftImage = _nftImage;
        nftExtURL = _nftExtURL;
        nftAnimationURL = _nftAnimationURL;
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        tokenIdToNumOfAttr[tokenId] = _attrNames.length;
        for (uint256 i = 0; i < _attrNames.length; i++) {
            tokenIdToAttributes[tokenId][i] = NFTAttribute(_attrNames[i], _attrValues[i]);
        }
        return tokenId;
    }

    function setDeliveryFlag(uint256 _tokenId, bool _isDelivered) public onlyOwner {
        require(_exists(_tokenId), "NFT does not exist");
        tokenIdToDelivery[_tokenId] = _isDelivered;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, tokenId);
        if (from != address(0) && to != address(0) && from != to) {
            require(_exists(tokenId), "NFT does not exist");
            bool canTransfer = false;
            if (!tokenIdToDelivery[tokenId] || (tokenIdToDelivery[tokenId] && to == owner())) {
                canTransfer = true;
            }
            // require(!tokenIdToDelivery[tokenId], "Yacht delivered, NFT transfer not allowed");
            require(canTransfer, "NFT transfer not allowed");
        }
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_exists(tokenId), "NFT does not exist");
        string memory isDelivered = (tokenIdToDelivery[tokenId] ? 'true' : 'false');

        string memory attrStr = '';
        uint256 numOfAttr = tokenIdToNumOfAttr[tokenId];
        if (numOfAttr > 0) {
            for (uint256 i = 0; i < numOfAttr; i++) {
                NFTAttribute storage nftAttr = tokenIdToAttributes[tokenId][i];
                attrStr = string(abi.encodePacked(attrStr, 
                    ',{"trait_type": "', nftAttr.attrName, '", "value": "', nftAttr.attrValue, '"}'
                ));
            }
        }

        return 
            string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                nftName,
                                '", "description":"',
                                nftDescription,
                                '", "image": "',
                                nftImage,
                                '", "external_url": "',
                                nftExtURL,
                                '", "animation_url": "',
                                nftAnimationURL,
                                '", "background_color": ""',
                                ', "attributes": [{"trait_type": "yacht_delivered", "value":"',
                                isDelivered,
                                '"}',
                                attrStr,
                                ']', 
                                '}'
                            )
                        )
                    )
                )
            );
    }
}
