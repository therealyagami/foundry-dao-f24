// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MorphDaoGovernor} from "src/MorphDaoGovernor.sol";
import {MorphToken} from "src/MorphToken.sol";
import {Box} from "src/Box.sol";
import {TimeLock} from "src/TimeLock.sol";

contract MorphDaoTest is Test {
    MorphDaoGovernor governor;
    Box box;
    TimeLock timelock;
    MorphToken morphToken;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1hour -> After a vote passes
    uint256 public constant VOTING_DELAY = 1; // How many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    function setUp() public {
        morphToken = new MorphToken();
        morphToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        morphToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MorphDaoGovernor(morphToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, msg.sender);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 777;
        string memory description = "store 1 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 2. View the state
        console.log("Proposal State", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "coz life needs harmony";

        uint8 voteWay = 1; // Voting yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3 Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box value:", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
