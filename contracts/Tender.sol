// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Tender {
    using Counters for Counters.Counter;
    Counters.Counter private _counter;

    address public owner;

    enum Status {
        PendingApproval,
        Approved,
        Rejected,
        Revoked
    }

    struct Contractor {
        address contractor;
        string name;
        Status status;
    }

    struct Contract {
        uint contractId;
        string description;
        uint bidDeadline;
        uint bidAmount;
        uint dailyPenaltyPerThousand;
        uint maxPenaltyPercent;
        address awardedTo;
        ContractStatus contractStatus;
        uint[] bidIds;
        bool isPaid;
        uint plannedDuration;
        uint workStarted;
        uint workCompleted;
    }

    enum ContractStatus {
        Open,
        Closed,
        Awarded,
        Canceled,
        WorkInProgress,
        WorkCompleted
    }

    struct Bid {
        uint bidId;
        address contractor;
        uint amount;
        uint duration;
        uint contractId;
        BidStatus bidStatus;
    }

    enum BidStatus {
        Submitted,
        Awarded,
        Rejected,
        Withdrawn
    }

    mapping(address => Contractor) public contractors;
    mapping(uint => Contract) public contracts;
    mapping(uint => Bid) public bids;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    modifier onlyApprovedContractors() {
        require(getContractorStatus(msg.sender) == Status.Approved, "Only approved contractors can call this function."
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    event ContractorAdded(address indexed contractor, string name);
    event ContractorApproved(address indexed contractor);
    event ContractorRejected(address indexed contractor);
    event ContractorRevoked(address indexed contractor);
    event ContractorStatusChange(address indexed contractor, Status status);
    event ContractCreated(
        uint indexed contractId,
        string description,
        uint bidDeadline,
        uint dailyPenaltyPerThousand,
        uint maxPenaltyPercent
    );
    event ContractCanceled(uint indexed contractId);
    event ContractClosed(uint indexed contractId);
    event ContractStatusChanged(
        uint indexed contractId,
        ContractStatus contractStatus
    );
    event BidCreated(
        uint indexed bidId,
        uint amount,
        uint duration,
        uint indexed contractId
    );
    event BidSubmitted(
        uint indexed bidId,
        uint indexed contractId,
        uint amount,
        uint duration
    );
    event BidWithdrawn(uint indexed bidId);
    event BidAwarded(
        uint indexed bidId,
        address indexed contractor,
        uint bidAmount
    );
    event BidderPaid(address indexed contractor, uint paymentAmount);

    function changeContractorStatus(address contractor, Status status) internal onlyOwner {
        require(isContractor(contractor), "Contractor does not exist.");
        contractors[contractor].status = status;

        emit ContractorStatusChange(
            contractors[contractor].contractor,
            contractors[contractor].status
        );
    }

    function addContractor(string calldata name) external {
        require(!isContractor(msg.sender), "Contractor already exists.");
        contractors[msg.sender] = Contractor(
            msg.sender,
            name,
            Status.PendingApproval
        );

        emit ContractorAdded(msg.sender, contractors[msg.sender].name);
    }

    function approveContractor(address contractor) external onlyOwner {
        require(isContractor(contractor), "Contractor does not exist");
        require(
            getContractorStatus(contractor) == Status.PendingApproval,
            "Contractor is not pending approval"
        );

        changeContractorStatus(contractor, Status.Approved);

        emit ContractorApproved(contractors[contractor].contractor);
    }

    function rejectContractor(address contractor) external onlyOwner {
        require(isContractor(contractor), "Contractor does not exist.");
        require(getContractorStatus(contractor) == Status.PendingApproval);

        changeContractorStatus(contractor, Status.Rejected);

        emit ContractorRejected(contractor);
    }

    function revokeContractor(address contractor) external onlyOwner {
        require(isContractor(contractor), "Contractor does not exist");
        require(getContractorStatus(contractor) == Status.Approved);

        changeContractorStatus(contractor, Status.Revoked);

        emit ContractorRevoked(contractor);
    }

    function createContract(
        string calldata _description,
        uint _bidDeadline,
        uint _dailyPenaltyPerThousand,
        uint _maxPenaltyPercent
    ) external onlyOwner {
        _counter.increment();
        uint256 contractId = _counter.current();

        contracts[contractId] = Contract(
            contractId,
            _description,
            _bidDeadline,
            0,
            _dailyPenaltyPerThousand,
            _maxPenaltyPercent,
            address(0),
            ContractStatus.Open,
            new uint[](0),
            false,
            0,
            0,
            0
        );
        emit ContractCreated(
            contractId,
            _description,
            _bidDeadline,
            _dailyPenaltyPerThousand,
            _maxPenaltyPercent
        );
    }

    function cancelContract(uint _contractId) public onlyOwner {
        require(
            getContractStatus(_contractId) != ContractStatus.Canceled,
            "Contract has already been canceled."
        );

        contracts[_contractId].contractStatus = ContractStatus.Canceled;
        contracts[_contractId].awardedTo = address(0);

        emit ContractCanceled(_contractId);
    }

    function closeContract(uint _contractId) public onlyOwner {
        require(isContract(_contractId), "Contract does not exist.");
        require(getContractStatus(_contractId) == ContractStatus.Open, "Contract is not open for bids.");
        require(block.timestamp > contracts[_contractId].bidDeadline, "Bid deadline has not passed yet.");

        changeContractStatus(_contractId, ContractStatus.Closed);

        emit ContractClosed(_contractId);
    }

    function submitBid(
        uint amount,
        uint duration,
        uint _contractId
    ) external onlyApprovedContractors {
        require(isContract(_contractId), "Contract does not exist.");
        require(isContractOpen(_contractId), "Contract is not open.");
        require(
            !isAlreadyBiddedByContractor(_contractId),
            "Only one bid can be submitted to a contract by same contractor."
        );

        _counter.increment();
        uint bidId = _counter.current();
        bids[bidId] = Bid(
            bidId,
            msg.sender,
            amount,
            duration,
            _contractId,
            BidStatus.Submitted
        );

        Contract storage payingContract = contracts[_contractId];
        payingContract.bidIds.push(bidId);

        emit BidSubmitted(bidId, _contractId, amount, duration);
    }

    function withdrawBid(uint _bidId) external onlyApprovedContractors {
        require(isContractor(msg.sender), "Contractor does not exist.");
        require(isBid(_bidId), "Bid does not exist.");
        require(getBidStatus(_bidId) == BidStatus.Submitted,
            "Only submitted bids can be withdrawn"
        );
        require(
            isContractOpen(bids[_bidId].contractId),
            "You can only withdraw bids from open contracts."
        );
        require(
            bids[_bidId].contractor == msg.sender,
            "Only bidder can withdraw the bid"
        );

        bids[_bidId].bidStatus = BidStatus.Withdrawn;

        emit BidWithdrawn(_bidId);
    }

    function awardBid(uint _bidId) external onlyOwner {
        require(isBid(_bidId), "Bid does not exist");
        uint contractId = bids[_bidId].contractId;
        require(isContract(contractId), "Contract does not exist");
        require(
            getContractStatus(contractId) == ContractStatus.Closed,
            "Contract is not closed."
        );
        require(
            getBidStatus(_bidId) == BidStatus.Submitted,
            "Only submitted bids can be awarded."
        );
        require(
            contracts[contractId].awardedTo == address(0),
            "Contract has already been awarded."
        );
        require(
            isBidSubmittedToContract(_bidId, contractId),
            "Bid is not submitted to this contract."
        );

        bids[_bidId].bidStatus = BidStatus.Awarded;
        contracts[contractId].awardedTo = bids[_bidId].contractor;
        contracts[contractId].bidAmount = bids[_bidId].amount;
        contracts[contractId].plannedDuration = bids[_bidId].duration;
        contracts[contractId].contractStatus = ContractStatus.Awarded;

        emit BidAwarded(
            bids[_bidId].bidId,
            bids[_bidId].contractor,
            bids[_bidId].amount
        );
    }

    function depositContractAmount(uint _contractId) public payable onlyOwner {
        require(
            msg.value >= contracts[_contractId].bidAmount,
            "Amount must be equal to or greater than bidAmount."
        );
        contracts[_contractId].bidAmount = msg.value;
    }

    function startWorkInContract(uint _contractId) external onlyOwner {
        require(isContract(_contractId), "Contract does not exist.");
        require(
            getContractStatus(_contractId) == ContractStatus.Awarded,
            "Contract is not awarded."
        );

        changeContractStatus(_contractId, ContractStatus.WorkInProgress);
        contracts[_contractId].workStarted = block.timestamp;
    }

    function completeWorkInContract(uint _contractId) external onlyOwner {
        require(isContract(_contractId), "Contract does not exist.");
        require(
            getContractStatus(_contractId) == ContractStatus.WorkInProgress,
            "Contract is not marked as InProgress."
        );

        changeContractStatus(_contractId, ContractStatus.WorkCompleted);
        contracts[_contractId].workCompleted = block.timestamp;
    }

    function payAwardedBid(uint _contractId) external onlyOwner {
        require(isContract(_contractId), "Contract does not exist");
        require(
            getContractStatus(_contractId) == ContractStatus.WorkCompleted,
            "Contract is not marked as WorkCompleted."
        );

        Contract storage payingContract = contracts[_contractId];
        require(payingContract.isPaid == false, "Contractor is already paid.");
        require(
            isContractor(payingContract.awardedTo),
            "Contractor does not exist."
        );

        uint paymentAmount = calculatePayment(_contractId);
        require(getContractBalance() >= paymentAmount);
        payable(payingContract.awardedTo).transfer(paymentAmount);
        payingContract.isPaid = true;

        emit BidderPaid(payingContract.awardedTo, paymentAmount);
    }

    function calculatePayment(uint _contractId) public view returns (uint) {
        require(isContract(_contractId), "Contract does not exist.");
        require(
            getContractStatus(_contractId) == ContractStatus.WorkCompleted,
            "Contract is not marked as WorkCompleted."
        );
        Contract storage payingContract = contracts[_contractId];

        uint workedDuration = (payingContract.workCompleted -
            payingContract.workStarted) / 86400;

        uint daysPassed = workedDuration - payingContract.plannedDuration;

        if (daysPassed <= 0) {
            return payingContract.bidAmount;
        }

        uint penaltyAmount = (payingContract.bidAmount *
            payingContract.dailyPenaltyPerThousand *
            daysPassed) / 1000;

        if (
            penaltyAmount >
            (payingContract.bidAmount * payingContract.maxPenaltyPercent) / 100
        ) {
            return
                (payingContract.bidAmount * payingContract.maxPenaltyPercent) /
                100;
        }

        return (payingContract.bidAmount - penaltyAmount);
    }

    function changeContractStatus(
        uint _contractId,
        ContractStatus _contractStatus
    ) internal onlyOwner {
        require(isContract(_contractId), "Contract does not exist.");
        contracts[_contractId].contractStatus = _contractStatus;

        emit ContractStatusChanged(
            contracts[_contractId].contractId,
            contracts[_contractId].contractStatus
        );
    }

    //FOR TESTING PURPOSES DELETE BEFORE DEPLOYING
    function resetContractor(address contractor) external onlyOwner {
        require(isContractor(contractor), "Contractor does not exist.");
        changeContractorStatus(contractor, Status.PendingApproval);
    }

    //FOR TESTING PURPOSES DELETE BEFORE DEPLOYING
    function resetContract(uint _contractId) external onlyOwner {
        require(isContract(_contractId), "Contract does not exist.");
        changeContractStatus(_contractId, ContractStatus.Open);
        contracts[_contractId].bidIds = new uint[](0);
    }

    // QUERY FUNCTIONS

    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    function isContractor(address contractor) private view returns (bool) {
        return contractors[contractor].contractor != address(0);
    }

    function getContractor(
        address contractor
    ) external view returns (Contractor memory) {
        require(isContractor(contractor), "Contractor does not exist.");
        return contractors[contractor];
    }

    function getContractorStatus(
        address contractor
    ) private view returns (Status) {
        require(isContractor(contractor), "Contractor does not exist.");
        return contractors[contractor].status;
    }

    function isContract(uint contractId) private view returns (bool) {
        return contracts[contractId].contractId != 0;
    }

    function isBid(uint _bidId) private view returns (bool) {
        return bids[_bidId].bidId != 0;
    }

    function getContract(
        uint _contractId
    ) external view returns (Contract memory) {
        require(isContract(_contractId), "Contract does not exist.");
        return contracts[_contractId];
    }

    function getBid(uint _bidId) external view returns (Bid memory) {
        require(isBid(_bidId), "Bid does not exist.");
        return bids[_bidId];
    }

    function getBidStatus(uint _bidId) private view returns (BidStatus) {
        require(isBid(_bidId), "Bid does not exist.");
        return bids[_bidId].bidStatus;
    }

    function getContractStatus(
        uint _contractId
    ) private view returns (ContractStatus) {
        require(isContract(_contractId), "Contract does not exist.");
        return contracts[_contractId].contractStatus;
    }

    function isContractOpen(uint _contractId) private view returns (bool) {
        require(isContract(_contractId), "Contract does not exist.");
        return contracts[_contractId].contractStatus == ContractStatus.Open;
    }

    function isBidSubmittedToContract(
        uint _bidId,
        uint _contractId
    ) public view returns (bool) {
        require(isBid(_bidId), "Bid does not exist.");
        require(isContract(_contractId), "Contract does not exist.");
        for (uint i = 0; i < contracts[_contractId].bidIds.length; i++) {
            if (contracts[_contractId].bidIds[i] == _bidId) {
                return true;
            }
        }
        return false;
    }

    function isAlreadyBiddedByContractor(
        uint _contractId
    ) public view returns (bool) {
        require(isContractor(msg.sender), "Contractor does not exist.");
        require(isContract(_contractId), "Contract does not exist.");
        uint[] memory bidsOfContract = getBidsOfContract(_contractId);
        for (uint i = 0; i < bidsOfContract.length; i++) {
            uint bidId = bidsOfContract[i];
            if (bids[bidId].contractor == msg.sender) {
                return true;
            }
        }
        return false;
    }

    function getBidsOfContract(
        uint _contractId
    ) private view returns (uint[] storage) {
        require(isContract(_contractId), "Contract does not exist.");

        return contracts[_contractId].bidIds;
    }
}
