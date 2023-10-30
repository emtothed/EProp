// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {ERC721} from "@OpenZeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@OpenZeppelin/contracts/utils/Base64.sol";
import {Strings} from "@OpenZeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@OpenZeppelin/contracts/security/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";

/**
 * @title EProp
 * @author Mohammad Asadi
 * @dev Implements a ERC721-based property ownership contract with its token and marketplace features such as:
 * - Allowing the owner of the token to list and unlist the token for sale
 * - Allowing the owner of the token to set an address as a buyer with a cerain price
 * - Allowing users to make an offer for a token
 * - Allowing the owner of the token to put the token up for auction
 */
contract EProp is ERC721, ReentrancyGuard {
    // A struct for maintaining property specifications
    using Strings for uint256;

    struct PropSpec {
        uint256 length;
        uint256 width;
        uint256 x;
        uint256 y;
        PropType propType;
    }

    // A struct for maintaining offers made by users
    struct Offer {
        address sender;
        uint256 offerdAmount;
    }

    // A type that holds the type of the property
    enum PropType {
        LAND,
        HOUSE,
        APARTMENT
    }

    // a type that holds the state of an auction
    enum AuctionState {
        CLOSED,
        PENDING,
        OPEN
    }

    mapping(uint256 => PropSpec) public tokenIdToSpec; // Mapping from token ID to property specifications struct
    mapping(uint256 => uint256) public tokenIdToHighestBid; // Mapping from token ID to the highest bid made for token in auction
    mapping(uint256 => AuctionState) public tokenIdToAuctionState; // Mapping from token ID to the state of the token auction
    mapping(uint256 => bool) public tokenIdToIsListed; // Mapping from token ID to listing status

    mapping(uint256 => uint256) private s_tokenIdToPrice; // Mapping from token ID to its price
    mapping(uint256 => address) private s_tokenIdToBuyer; // Mapping from token ID to the buyer set by token owner
    mapping(uint256 => address) private s_tokenIdToLastBidder; // Mapping from token ID to last user bided in auction for the token
    mapping(uint256 => uint256) private s_tokenIdToPrePaymentAmount; // Mapping from token ID to amount of prepayment paid by the last bidder
    mapping(uint256 => uint256) private s_tokenIdToCloseTime; // Mapping from token ID to the closing time of the auction by the token owner
    mapping(uint256 => Offer[]) private s_tokenIdToOffers; // Mapping from token ID to offers for the token
    mapping(uint256 => uint256) private s_tokenIdTolastBidTime; // Mapping from token ID to the time of the last bid

    address private immutable i_owner; // Owner of the contract
    uint256 private s_tokenCounter; // A counter for the tokens
    string private s_imageUri; // URI of the token image

    error EProp__NotTokenOwnerOrApproved();
    error EProp__TokenNotForSaleForThisAddressOrListed();
    error EProp__PaidAmountIsNotEnough();
    error EProp__AlreadyOnSaleOrInAuction();
    error EProp__PaidLessThanRequiredForBidAmount();
    error EProp__BidedLessThanHighestBid();
    error EProp__NoOpenAuctionForThisToken();
    error EProp__NotAuctionWinner();
    error EProp__SevenDaysNotPassed();
    error EProp__WrongTokenIdEntered();
    error EProp__TokenAlreadyInSaleOrAuction();
    error EProp__TokenNotOnSaleOrListed();
    error EProp__NoOnPendingAuctionForThisToken();
    error EProp__NoOfferWithThisIndex();

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert();
        }
        _;
    }

    modifier onlyTokenOwner(uint256 tokenId) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert EProp__NotTokenOwnerOrApproved();
        }
        _;
    }

    constructor(string memory imageUri) ERC721("eProp", "EPR") {
        i_owner = msg.sender;
        s_imageUri = imageUri;
    }

    //  ========================= Token functions =========================

    /**
     * @notice This function is originally usable only by the owner of the contract
     * but the modifier is commented so that everyone can mint a token and test the contract.
     * @dev Mints token for the given address with the given specifications.
     * @param propOwner The address of the owner of the token.
     * @param length The length of the property.
     * @param width The width of the property.
     * @param x Geographical location of the property.
     * @param y Geographical location of the property.
     * @param propType property type e.g. LAND.
     */
    function mintProp(address propOwner, uint256 length, uint256 width, uint256 x, uint256 y, uint8 propType)
        public /*onlyOwner*/
    {
        _safeMint(propOwner, s_tokenCounter);
        PropSpec memory propSpec = PropSpec(length, width, x, y, PropType(propType));
        tokenIdToSpec[s_tokenCounter] = propSpec;
        console.log("EProp Minted with tokenID: ", s_tokenCounter);
        s_tokenCounter++;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }

    /**
     * @dev Returns the URI of the 'tokenId' token.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory length = Strings.toString(tokenIdToSpec[tokenId].length);
        string memory width = Strings.toString(tokenIdToSpec[tokenId].width);
        string memory location =
            string.concat(Strings.toString(tokenIdToSpec[tokenId].x), " , ", Strings.toString(tokenIdToSpec[tokenId].y));
        string memory propType = propTypeToString(tokenIdToSpec[tokenId].propType);
        return string(
            abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            name(),
                            '","description":"EProp is a decentralized property ownership system.","attributes":[{"Length":"',
                            length,
                            '","Width":"',
                            width,
                            '","Location":"',
                            location,
                            '","Property type":"',
                            propType,
                            '"}],"image":"',
                            s_imageUri,
                            '"}'
                        )
                    )
                )
            )
        );
    }

    //  ========================= Sale functions =========================

    /**
     * @dev Allows the token owner to list 'tokenId' token for sale with a 'price' as its price.
     *
     *  Requirements:
     * - The token should not be in auction.
     */
    function listTokenForSale(uint256 tokenId, uint256 price) public onlyTokenOwner(tokenId) {
        if (!_exists(tokenId)) {
            revert EProp__WrongTokenIdEntered();
        }
        if (tokenIdToIsListed[tokenId] || tokenIdToAuctionState[tokenId] != AuctionState.CLOSED) {
            revert EProp__AlreadyOnSaleOrInAuction();
        }
        tokenIdToIsListed[tokenId] = true;
        s_tokenIdToPrice[tokenId] = price;
    }

    /**
     * @dev Allows the token owner to set an address as buyer with a certain price for 'tokenId' token.
     *
     *  Requirements:
     * - The token should not be listed or in auction.
     */
    function submitBuyer(address buyer, uint256 tokenId, uint256 price) public onlyTokenOwner(tokenId) {
        if (!_exists(tokenId) || buyer == msg.sender) {
            revert EProp__WrongTokenIdEntered();
        }
        if (
            s_tokenIdToBuyer[tokenId] != address(0) || tokenIdToIsListed[tokenId]
                || tokenIdToAuctionState[tokenId] != AuctionState.CLOSED
        ) {
            revert EProp__AlreadyOnSaleOrInAuction();
        }
        s_tokenIdToBuyer[tokenId] = buyer;
        s_tokenIdToPrice[tokenId] = price;
        console.log("Sale submited successfuly");
    }

    /**
     * @dev Allows the owner of 'tokenId' token to unlist or remove the defined buyer of the token.
     */
    function cancelSaleOrUnlist(uint256 tokenId) public onlyTokenOwner(tokenId) {
        if (s_tokenIdToPrice[tokenId] == 0) {
            revert EProp__TokenNotOnSaleOrListed();
        }
        delete s_tokenIdToBuyer[tokenId];
        delete s_tokenIdToPrice[tokenId];
        delete tokenIdToIsListed[tokenId];
    }

    /**
     * @dev Allows the defined buyer of 'tokenId',or any user when the token is listed, to pay for the token
     * and when the price is paid, the paid amount will be transfers to the token owner and the token will be
     * trasferd to the payer.
     */
    function payForToken(uint256 tokenId) public payable {
        if (s_tokenIdToBuyer[tokenId] == msg.sender || tokenIdToIsListed[tokenId]) {
            if (msg.value < s_tokenIdToPrice[tokenId]) {
                revert EProp__PaidAmountIsNotEnough();
            }
            (bool paid,) = ownerOf(tokenId).call{value: msg.value}("");
            if (paid) {
                _safeTransfer(ownerOf(tokenId), msg.sender, tokenId, "");
                delete s_tokenIdToBuyer[tokenId];
                delete s_tokenIdToPrice[tokenId];
                delete s_tokenIdToOffers[tokenId];
            } else {
                revert();
            }
        } else {
            revert EProp__TokenNotForSaleForThisAddressOrListed();
        }
    }

    /**
     * @dev Allows users to make an offer for 'tokenId' token with 'offerdPrice' as price
     * and adds the offer to the array of offers of the token
     *
     *  Requirements:
     * - The token should not be listed or in auction.
     */
    function makeOffer(uint256 tokenId, uint256 offeredPrice) public {
        if (!_exists(tokenId) || ownerOf(tokenId) == msg.sender) {
            revert EProp__WrongTokenIdEntered();
        }
        if (tokenIdToHighestBid[tokenId] != 0 || tokenIdToIsListed[tokenId]) {
            revert EProp__TokenAlreadyInSaleOrAuction();
        }
        Offer memory offer = Offer(msg.sender, offeredPrice);
        s_tokenIdToOffers[tokenId].push(offer);
    }

    /**
     * @dev Allows the Owner of 'tokenId' token to accept an offer and
     * set the sender of the offer as buyer and 'offeredPrice' as price .
     */
    function acceptOffer(uint256 tokenId, uint256 offerIndex) public onlyTokenOwner(tokenId) {
        if (s_tokenIdToOffers[tokenId][offerIndex].sender != address(0)) {
            Offer memory offer = s_tokenIdToOffers[tokenId][offerIndex];
            submitBuyer(offer.sender, tokenId, offer.offerdAmount);
        } else {
            revert EProp__NoOfferWithThisIndex();
        }
    }

    //  ========================= Auction functions =========================

    /**
     * @dev Allows the owner of 'tokenId' token to put the token up for auction
     *  with 'startingPrice' as starting price.
     *
     *   Requirements:
     * - The token should not be on sale.
     */
    function openAuction(uint256 tokenId, uint256 startingPrice) public onlyTokenOwner(tokenId) {
        if (s_tokenIdToPrice[tokenId] != 0 || tokenIdToAuctionState[tokenId] != AuctionState.CLOSED) {
            revert EProp__AlreadyOnSaleOrInAuction();
        } else {
            tokenIdToHighestBid[tokenId] = startingPrice;
            tokenIdToAuctionState[tokenId] = AuctionState.OPEN;
        }
    }

    /**
     * @dev Allows the owner of 'tokenId' token to close the auction.
     * if there is a bidder, the prepayment amount is sent to the owner of the token and auction state is changed to 'PENDING'
     * otherwise,the variables related to the auction is set to default value and auction gets closed.
     */
    function closeAuction(uint256 tokenId) public nonReentrant onlyTokenOwner(tokenId) {
        if (tokenIdToAuctionState[tokenId] != AuctionState.OPEN) {
            revert EProp__NoOpenAuctionForThisToken();
        }
        if (s_tokenIdToLastBidder[tokenId] == address(0)) {
            delete tokenIdToAuctionState[tokenId];
            delete tokenIdToHighestBid[tokenId];
        } else {
            (bool success,) = msg.sender.call{value: s_tokenIdToPrePaymentAmount[tokenId]}("");
            if (!success) {
                revert();
            }
            tokenIdToAuctionState[tokenId] = AuctionState.PENDING;
            s_tokenIdToCloseTime[tokenId] = block.timestamp;
        }
    }

    /**
     * @dev Allows the owner of 'tokenId' token to cancel the auction only if the auction winner
     * has not paid for the token and a week has passed since the closing of the auction.
     */
    function cancelAuction(uint256 tokenId) public onlyTokenOwner(tokenId) {
        if (tokenIdToAuctionState[tokenId] != AuctionState.PENDING) {
            revert EProp__NoOnPendingAuctionForThisToken();
        }
        if (block.timestamp >= s_tokenIdToCloseTime[tokenId] + 7 days) {
            delete tokenIdToHighestBid[tokenId];
            delete s_tokenIdToPrePaymentAmount[tokenId];
            delete s_tokenIdToCloseTime[tokenId];
            delete s_tokenIdToLastBidder[tokenId];
            delete tokenIdToAuctionState[tokenId];
            delete s_tokenIdTolastBidTime[tokenId];
        } else {
            revert EProp__SevenDaysNotPassed();
        }
    }

    /**
     * @dev Allows the users to make a bid for 'tokenId' token with 'bidAmount' as bid amount.
     *
     *  Requirements:
     * - the token must be auctioned
     * - The bid amount must not be less than the last highest bid amount.
     * - The bidder must send one percent of the bid amount as prepayment.
     */
    function makeBid(uint256 tokenId, uint256 bidAmount) public payable nonReentrant {
        if (msg.sender == ownerOf(tokenId)) {
            revert EProp__WrongTokenIdEntered();
        }
        if (tokenIdToAuctionState[tokenId] != AuctionState.OPEN) {
            revert EProp__NoOpenAuctionForThisToken();
        }
        if (msg.value < (bidAmount / 100)) {
            revert EProp__PaidLessThanRequiredForBidAmount();
        }
        if (bidAmount <= tokenIdToHighestBid[tokenId]) {
            revert EProp__BidedLessThanHighestBid();
        }
        if (s_tokenIdToLastBidder[tokenId] != address(0)) {
            (bool success,) = s_tokenIdToLastBidder[tokenId].call{value: s_tokenIdToPrePaymentAmount[tokenId]}("");
            if (!success) {
                revert();
            }
        }
        s_tokenIdToLastBidder[tokenId] = msg.sender;
        s_tokenIdToPrePaymentAmount[tokenId] = msg.value;
        tokenIdToHighestBid[tokenId] = bidAmount;
        s_tokenIdTolastBidTime[tokenId] = block.timestamp;
    }

    /**
     * @dev Allows the last bidder for 'tokenId' token to cancel the bid and take the prepayment back
     * when a week has passed since the bid date and the token owner does not close the auction.
     * then it sets the variables related to the auction to default values and closes the auction.
     */
    function cancelBid(uint256 tokenId) public nonReentrant {
        if (tokenIdToAuctionState[tokenId] != AuctionState.OPEN) {
            revert EProp__NoOpenAuctionForThisToken();
        }
        if (s_tokenIdToLastBidder[tokenId] != msg.sender) {
            revert EProp__NotAuctionWinner();
        }
        if (block.timestamp >= s_tokenIdTolastBidTime[tokenId] + 7 days) {
            (bool success,) = msg.sender.call{value: s_tokenIdToPrePaymentAmount[tokenId]}("");
            if (success) {
                delete tokenIdToHighestBid[tokenId];
                delete s_tokenIdToPrePaymentAmount[tokenId];
                delete s_tokenIdToLastBidder[tokenId];
                delete tokenIdToAuctionState[tokenId];
                delete s_tokenIdTolastBidTime[tokenId];
            } else {
                revert();
            }
        } else {
            revert EProp__SevenDaysNotPassed();
        }
    }

    /**
     * @dev Allows the winner of the auction to pay for the 'tokenId' token and if the paid amount is enough,
     * the paid amount is transfered to the owner of the 'tokenId' token and the token is transferd to the payer.
     */
    function payForTokenInAuction(uint256 tokenId) public payable {
        if (s_tokenIdToLastBidder[tokenId] != msg.sender) {
            revert EProp__NotAuctionWinner();
        }
        if (msg.value < (tokenIdToHighestBid[tokenId] - s_tokenIdToPrePaymentAmount[tokenId])) {
            revert EProp__PaidAmountIsNotEnough();
        }

        (bool paid,) = ownerOf(tokenId).call{value: msg.value}("");
        if (paid) {
            _safeTransfer(ownerOf(tokenId), msg.sender, tokenId, "");
            delete tokenIdToHighestBid[tokenId];
            delete s_tokenIdToPrePaymentAmount[tokenId];
            delete s_tokenIdToCloseTime[tokenId];
            delete s_tokenIdToLastBidder[tokenId];
            delete tokenIdToAuctionState[tokenId];
            delete s_tokenIdTolastBidTime[tokenId];
            delete s_tokenIdToOffers[tokenId];
        } else {
            revert();
        }
    }

    //  =========================  Getter functions  =========================

    /**
     * @dev Returns the price of the 'tokenId' token to the buyer, owner, or everyone if the token is listed.
     */
    function getTokenPrice(uint256 tokenId) external view returns (uint256 price) {
        if (s_tokenIdToBuyer[tokenId] == msg.sender || tokenIdToIsListed[tokenId] || msg.sender == ownerOf(tokenId)) {
            price = s_tokenIdToPrice[tokenId];
        } else {
            revert EProp__TokenNotForSaleForThisAddressOrListed();
        }
    }

    /**
     * @dev Returns the address of the defined buyer to the owner of 'tokenId' token.
     */
    function getBuyer(uint256 tokenId) external view onlyTokenOwner(tokenId) returns (address) {
        return s_tokenIdToBuyer[tokenId];
    }

    /**
     * @dev Returns the array of offers for the token to the owner of 'tokenId' token.
     */
    function getOffers(uint256 tokenId) external view onlyTokenOwner(tokenId) returns (Offer[] memory) {
        return s_tokenIdToOffers[tokenId];
    }

    /**
     * @dev Returns the specifications of 'tokenId' token.
     */
    function getSpec(uint256 tokenId) external view returns (uint256, uint256) {
        return (tokenIdToSpec[tokenId].length, tokenIdToSpec[tokenId].width);
    }

    /**
     * @dev Returns the last bidder address and the prepayment amount to the owner of 'tokenId' token.
     */
    function getLatestBidInfo(uint256 tokenId) external view onlyTokenOwner(tokenId) returns (address, uint256) {
        return (s_tokenIdToLastBidder[tokenId], s_tokenIdToPrePaymentAmount[tokenId]);
    }

    /**
     * @dev Returns the auction closing time to the owner of 'tokenId' token.
     */
    function getCloseTime(uint256 tokenId) external view onlyTokenOwner(tokenId) returns (uint256) {
        return s_tokenIdToCloseTime[tokenId];
    }

    /**
     * @dev Returns the bid time to the last bidder of 'tokenId' token.
     */
    function getlastBidTime(uint256 tokenId) external view returns (uint256) {
        if (s_tokenIdToLastBidder[tokenId] == msg.sender) {
            return s_tokenIdTolastBidTime[tokenId];
        } else {
            revert();
        }
    }

    /**
     * @dev Returns the propType converted to string.
     */
    function propTypeToString(PropType pT) internal pure returns (string memory) {
        if (pT == PropType.APARTMENT) {
            return "APARTMENT";
        } else if (pT == PropType.HOUSE) {
            return "HOUSE";
        } else {
            return "LAND";
        }
    }
}
