// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {EProp} from "../src/eProp.sol";
import {DeployEProp} from "../script/DeployeProp.s.sol";
import {MintNft} from "../script/interaction.s.sol";

contract EPropTest is Test {
    enum PropType {
        LAND,
        HOUSE,
        APARTMENT
    }
    DeployEProp public deployer;
    EProp public eProp;
    address public USER = makeAddr("User");
    address public USER2 = makeAddr("User2");
    uint256 constant SELL_PRICE = 1 ether;
    uint256 bidAmount = SELL_PRICE * 2;

    function setUp() public {
        deployer = new DeployEProp();
        eProp = deployer.run();
    }

    function testMintProp() public {
        eProp.mintProp(USER, 44, 65, 0, 0, 0);
        EProp.PropSpec memory specs;
        (specs.length, specs.width) = eProp.getSpec(0);
        console.log(specs.length);
        console.log(specs.width);
    }

    function testTokenUri() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        console.log(eProp.tokenURI(0));
    }

    //------------- sale tests -------------

    function testListTokenForSale() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        vm.expectRevert();
        eProp.listTokenForSale(2, SELL_PRICE);

        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        vm.prank(USER);
        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        eProp.listTokenForSale(0, SELL_PRICE);

        assert(eProp.tokenIdToIsListed(0));
        assert(eProp.getTokenPrice(0) == SELL_PRICE);
    }

    function testPayForListedToken() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        hoax(USER2, SELL_PRICE);
        eProp.payForToken{value: SELL_PRICE}(0);

        assert(eProp.ownerOf(0) == USER2);
        assert(USER.balance == SELL_PRICE);
    }

    function testSellToken() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        hoax(USER2, 2 ether);
        console.log(address(USER2));
        eProp.payForToken{value: SELL_PRICE}(0);

        assert(eProp.ownerOf(0) == USER2);
        assert(USER.balance == SELL_PRICE);
    }

    function testSubmitBuyerOrlistRevertWhenInAuction() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);
    }

    function testSubmitBuyerRevertWhenNotTokenOwner() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__NotTokenOwnerOrApproved.selector);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);
    }

    function testSubmitBuyerAgainRevert() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.prank(USER);
        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);
    }

    function testSubmitBuyerRevertWhenBuyerIsOwner() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__WrongTokenIdEntered.selector);
        vm.prank(USER);
        eProp.submitBuyer(USER, 0, SELL_PRICE);
    }

    function testCancelSale() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.prank(USER);
        eProp.cancelSaleOrUnlist(0);

        vm.prank(USER);
        address buyer = eProp.getBuyer(0);

        vm.prank(USER);
        uint256 price = eProp.getTokenPrice(0);

        assert(buyer == address(0));
        assert(price == 0);

        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        vm.prank(USER);
        eProp.cancelSaleOrUnlist(0);

        vm.prank(USER);
        price = eProp.getTokenPrice(0);
        assert(price == 0);
    }

    function testCancelSaleRevertWhenNotOnSale() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__TokenNotOnSaleOrListed.selector);
        vm.prank(USER);
        eProp.cancelSaleOrUnlist(0);
    }

    function testPayForTokenRevertWhenNotBuyer() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        hoax(address(3), 2 ether);
        vm.expectRevert(
            EProp.EProp__TokenNotForSaleForThisAddressOrListed.selector
        );
        eProp.payForToken{value: SELL_PRICE}(0);
    }

    function testPayForTokenRevertWhenTokenNotForSale() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        eProp.mintProp(USER, 86, 45, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.expectRevert(
            EProp.EProp__TokenNotForSaleForThisAddressOrListed.selector
        );
        hoax(USER2, 2 ether);
        eProp.payForToken{value: SELL_PRICE}(1);
    }

    function testPayForTokenRevertWhenNotPaidEnough() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__PaidAmountIsNotEnough.selector);
        hoax(USER2, 2 ether);
        eProp.payForToken{value: SELL_PRICE - 1000}(0);
    }

    function testMakeOffer() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER2);
        eProp.makeOffer(0, 1 ether);

        vm.prank(address(3));
        eProp.makeOffer(0, 2 ether);

        vm.prank(USER);
        EProp.Offer[] memory offers = eProp.getOffers(0);

        assert(offers[0].sender == USER2);
        assert(offers[0].offerdAmount == 1 ether);
        assert(offers[1].sender == address(3));
        assert(offers[1].offerdAmount == 2 ether);
    }

    function testMakeOfferRevertWhenAlreadyOnSale() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        vm.prank(USER2);
        vm.expectRevert(EProp.EProp__TokenAlreadyInSaleOrAuction.selector);
        eProp.makeOffer(0, 1 ether);
    }

    function testMakeOfferRevertWhenTokenNotExist() public {
        vm.prank(USER2);
        vm.expectRevert(EProp.EProp__WrongTokenIdEntered.selector);
        eProp.makeOffer(0, 1 ether);
    }

    function testMakeOfferRevertWhenOwnerOffers() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        vm.prank(USER);
        vm.expectRevert(EProp.EProp__WrongTokenIdEntered.selector);
        eProp.makeOffer(0, 1 ether);
    }

    function testAcceptOffer() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER2);
        eProp.makeOffer(0, 1 ether);

        vm.expectRevert(EProp.EProp__NotTokenOwnerOrApproved.selector);
        vm.prank(USER2);
        eProp.acceptOffer(0, 0);

        vm.prank(USER);
        eProp.acceptOffer(0, 0);

        vm.prank(USER);
        address buyer = eProp.getBuyer(0);

        vm.prank(USER);
        uint256 price = eProp.getTokenPrice(0);

        assert(price == 1 ether);
        assert(buyer == USER2);
    }

    function testGetTokenPriceRevertWhenNotBuyer() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.submitBuyer(USER2, 0, SELL_PRICE);

        vm.expectRevert(
            EProp.EProp__TokenNotForSaleForThisAddressOrListed.selector
        );
        eProp.getTokenPrice(0);
    }

    //-------------- Auction tests --------------

    function testOpenAuction() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        assert(eProp.tokenIdToHighestBid(0) == SELL_PRICE);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.OPEN);
    }

    function testOpenAuctionRevertWhenNotOwner() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER2);
        vm.expectRevert(EProp.EProp__NotTokenOwnerOrApproved.selector);
        eProp.openAuction(0, SELL_PRICE);
    }

    function testOpenAuctionRevertWhenAlreadyInAuction() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.prank(USER);
        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        eProp.openAuction(0, SELL_PRICE);
    }

    function testOpenAuctionRevertWhenAlreadyListed() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.prank(USER);
        eProp.listTokenForSale(0, SELL_PRICE);

        vm.prank(USER);
        vm.expectRevert(EProp.EProp__AlreadyOnSaleOrInAuction.selector);
        eProp.openAuction(0, SELL_PRICE);
    }

    function testMakeBid() public {
        uint256 startingBalance = address(eProp).balance;
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 10)}(0, bidAmount);

        vm.prank(USER);
        (address lastBidder, uint256 prePaymentAmount) = eProp.getLatestBidInfo(
            0
        );

        assert(lastBidder == USER2);
        assert(prePaymentAmount == bidAmount / 10);
        assert(eProp.tokenIdToHighestBid(0) == bidAmount);
        assert(address(eProp).balance == startingBalance + bidAmount / 10);
        assert(USER2.balance == bidAmount - prePaymentAmount);

        bidAmount *= 2;

        hoax(address(3), bidAmount);
        uint256 bidTime = block.timestamp;
        eProp.makeBid{value: (bidAmount / 10)}(0, bidAmount);

        vm.prank(USER);
        (lastBidder, prePaymentAmount) = eProp.getLatestBidInfo(0);
        vm.prank(address(3));
        uint256 storedLastBidTime = eProp.getlastBidTime(0);

        assert(USER2.balance == bidAmount / 2);
        assert(lastBidder == address(3));
        assert(prePaymentAmount == bidAmount / 10);
        assert(eProp.tokenIdToHighestBid(0) == bidAmount);
        assert(address(eProp).balance == startingBalance + bidAmount / 10);
        assert(address(3).balance == bidAmount - prePaymentAmount);
        assert(storedLastBidTime == bidTime);
    }

    function testMakeBidRevertWhenAuctionisClosed() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__NoOpenAuctionForThisToken.selector);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 10)}(0, bidAmount);
    }

    function testMakeBidRevertWhenPrePaymentNotEnough() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__PaidLessThanRequiredForBidAmount.selector);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 200)}(0, bidAmount);
    }

    function testMakeBidRevertWhenBidAmountIsLessThanHighestBid() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__BidedLessThanHighestBid.selector);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, SELL_PRICE);
    }

    function testMakeBidRevertWhenOwnerBids() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__WrongTokenIdEntered.selector);
        hoax(USER, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
    }

    function testCloseAuctionWithoutBidders() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.prank(USER);
        eProp.closeAuction(0);

        assert(eProp.tokenIdToHighestBid(0) == 0);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.CLOSED);
    }

    function testCloseAuctionWithBidders() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        (, uint256 prePaymentAmount) = eProp.getLatestBidInfo(0);

        vm.prank(USER);
        eProp.closeAuction(0);
        uint256 closeTime = block.timestamp;
        vm.prank(USER);
        uint256 storedCloseTime = eProp.getCloseTime(0);

        assert(USER.balance == prePaymentAmount);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.PENDING);
        assert(storedCloseTime == closeTime);
    }

    function testCloseAuctionRevertWhenAuctionNotOpen() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__NoOpenAuctionForThisToken.selector);
        vm.prank(USER);
        eProp.closeAuction(0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        vm.expectRevert(EProp.EProp__NoOpenAuctionForThisToken.selector);
        vm.prank(USER);
        eProp.closeAuction(0);
    }

    function testCancelAuction() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 1);

        vm.prank(USER);
        eProp.cancelAuction(0);

        vm.prank(USER);
        (address lastBidder, uint256 prePaymentAmount) = eProp.getLatestBidInfo(
            0
        );
        vm.prank(USER);
        uint256 storedCloseTime = eProp.getCloseTime(0);

        assert(eProp.tokenIdToHighestBid(0) == 0);
        assert(lastBidder == address(0));
        assert(prePaymentAmount == 0);
        assert(storedCloseTime == 0);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.CLOSED);
    }

    function testCancelAuctionWhenAuctionNotOnPending() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__NoOnPendingAuctionForThisToken.selector);
        vm.prank(USER);
        eProp.cancelAuction(0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__NoOnPendingAuctionForThisToken.selector);
        vm.prank(USER);
        eProp.cancelAuction(0);
    }

    function testCancelAuctionRevertWhenWeekNotPassed() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        vm.expectRevert(EProp.EProp__SevenDaysNotPassed.selector);
        vm.prank(USER);
        eProp.cancelAuction(0);
    }

    function testPayForTokenInAuction() public {
        //Setting up
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        //Function
        vm.prank(USER2);
        eProp.payForTokenInAuction{value: bidAmount - bidAmount / 100}(0);

        //Assertion
        vm.prank(USER2);
        uint256 storedCloseTime = eProp.getCloseTime(0);
        vm.prank(USER2);
        (address lastBidder, uint256 prePaymentAmount) = eProp.getLatestBidInfo(
            0
        );

        assert(eProp.ownerOf(0) == USER2);
        assert(USER.balance == bidAmount);
        assert(eProp.tokenIdToHighestBid(0) == 0);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.CLOSED);
        assert(lastBidder == address(0));
        assert(storedCloseTime == 0);
        assert(prePaymentAmount == 0);
    }

    function testPayForTokenInAuctionRevertWhenNotWinner() public {
        //Setting up
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        hoax(address(3), bidAmount + 1);
        eProp.makeBid{value: ((bidAmount + 1) / 100)}(0, bidAmount + 1);
        vm.prank(USER);
        eProp.closeAuction(0);

        //Assertion
        vm.expectRevert(EProp.EProp__NotAuctionWinner.selector);
        vm.prank(USER2);
        eProp.payForTokenInAuction{value: bidAmount - bidAmount / 100}(0);
    }

    function testPayForTokenInAuctionRevertWhenNotPaidEnough() public {
        //Setting up
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        //Assertion
        vm.expectRevert(EProp.EProp__PaidAmountIsNotEnough.selector);
        vm.prank(USER2);
        eProp.payForTokenInAuction{value: bidAmount / 100}(0);
    }

    function testCancelBid() public {
        //Setting up
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.warp(block.timestamp + 7 days);
        vm.roll(block.number + 1);

        //Function
        vm.prank(USER2);
        eProp.cancelBid(0);

        //Assertion
        vm.prank(USER);
        uint256 storedCloseTime = eProp.getCloseTime(0);
        vm.prank(USER);
        (address lastBidder, uint256 prePaymentAmount) = eProp.getLatestBidInfo(
            0
        );
        assert(USER2.balance == bidAmount);
        assert(eProp.tokenIdToHighestBid(0) == 0);
        assert(eProp.tokenIdToAuctionState(0) == EProp.AuctionState.CLOSED);
        assert(lastBidder == address(0));
        assert(storedCloseTime == 0);
        assert(prePaymentAmount == 0);
    }

    function testCancelBidRevertWhenAuctionNotOpen() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);

        vm.expectRevert(EProp.EProp__NoOpenAuctionForThisToken.selector);
        vm.prank(USER2);
        eProp.cancelBid(0);

        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);
        vm.prank(USER);
        eProp.closeAuction(0);

        vm.expectRevert(EProp.EProp__NoOpenAuctionForThisToken.selector);
        vm.prank(USER2);
        eProp.cancelBid(0);
    }

    function testCancelBidRevertWhenNotLastBidder() public {
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);

        vm.expectRevert(EProp.EProp__NotAuctionWinner.selector);
        vm.prank(address(3));
        eProp.cancelBid(0);

        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);

        vm.expectRevert(EProp.EProp__NotAuctionWinner.selector);
        vm.prank(address(3));
        eProp.cancelBid(0);
    }

    function testCancelBidRevertWhenWeekNotPassed() public {
        //Setting up
        eProp.mintProp(USER, 44, 65, 1, 1, 0);
        vm.prank(USER);
        eProp.openAuction(0, SELL_PRICE);
        hoax(USER2, bidAmount);
        eProp.makeBid{value: (bidAmount / 100)}(0, bidAmount);

        vm.expectRevert(EProp.EProp__SevenDaysNotPassed.selector);
        vm.prank(USER2);
        eProp.cancelBid(0);
    }
}
