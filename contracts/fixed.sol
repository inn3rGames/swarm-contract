// SPDX-License-Identifier: MIT

// Update to the latest Solidity version
pragma solidity ^0.8.27;

contract ParimutuelBetting {
    struct Prediction {
        uint256 id;
        string title;
        string description;
        mapping(string => bool) options;
        string[] optionList;
        uint256 endBidTime;
        bool isActive;
        string winner;
        mapping(string => uint256) totalBets;
        mapping(address => mapping(string => uint256)) bets;
        address[] participants;
    }

    // Fix mutable owner
    address public immutable owner;
    uint256 public predictionCounter;
    mapping(uint256 => Prediction) public predictions;
    mapping(uint256 => bool) public predictionExistsMap;
    mapping(address => bool) public admins;
    bool private paused;
    bool private locked;

    uint256 public constant MAX_OPTIONS = 10;
    uint256 public constant TIME_BUFFER = 1 hours;

    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed removedAdmin);
    event PredictionCreated(
        uint256 id,
        string title,
        string description,
        string[] options,
        uint256 endBidTime
    );
    event BetPlaced(
        address indexed user,
        uint256 predictionId,
        string option,
        uint256 amount
    );
    event PredictionEnded(uint256 id, string winner);
    event PayoutAvailable(
        address indexed user,
        uint256 predictionId,
        uint256 amount
    );
    event PayoutClaimed(
        address indexed user,
        uint256 predictionId,
        uint256 amount
    );
    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        owner = msg.sender;
        admins[owner] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin can perform this action");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    modifier predictionExists(uint256 predictionId) {
        require(predictionExistsMap[predictionId], "Prediction does not exist");
        _;
    }

    modifier predictionActive(uint256 predictionId) {
        require(predictions[predictionId].isActive, "Prediction is not active");
        _;
    }

    modifier predictionEnded(uint256 predictionId) {
        require(
            block.number > predictions[predictionId].endBidTime,
            "Prediction has not ended yet"
        );
        _;
    }

    function createPrediction(
        string memory title,
        string memory description,
        string[] memory options,
        uint256 durationInBlocks
    ) external onlyAdmin whenNotPaused {
        require(durationInBlocks > 0, "Duration must be greater than zero");
        require(
            options.length > 1 && options.length <= MAX_OPTIONS,
            "Invalid number of options"
        );

        uint256 endBidBlock = block.number + durationInBlocks;

        Prediction storage newPrediction = predictions[predictionCounter];
        newPrediction.id = predictionCounter;
        newPrediction.title = title;
        newPrediction.description = description;
        newPrediction.endBidTime = endBidBlock;
        newPrediction.isActive = true;

        for (uint256 i = 0; i < options.length; i++) {
            require(!newPrediction.options[options[i]], "Duplicate option");
            newPrediction.options[options[i]] = true;
            newPrediction.optionList.push(options[i]);
        }

        predictionExistsMap[predictionCounter] = true; // Update prediction map

        emit PredictionCreated(
            predictionCounter,
            title,
            description,
            options,
            endBidBlock
        );
        predictionCounter++;
    }

    function placeBet(
        uint256 predictionId,
        string memory option
    )
        external
        payable
        nonReentrant
        whenNotPaused
        predictionExists(predictionId)
        predictionActive(predictionId)
    {
        require(msg.value > 0, "Bet amount must be greater than zero");
        require(
            block.number <= predictions[predictionId].endBidTime,
            "Cannot place bet after bidding time has ended"
        );

        Prediction storage prediction = predictions[predictionId];
        require(prediction.options[option], "Invalid betting option");

        if (prediction.bets[msg.sender][option] == 0) {
            prediction.participants.push(msg.sender);
        }

        prediction.bets[msg.sender][option] += msg.value;
        prediction.totalBets[option] += msg.value;

        emit BetPlaced(msg.sender, predictionId, option, msg.value);
    }

    function endPrediction(
        uint256 predictionId,
        string memory winner
    )
        external
        onlyAdmin
        predictionExists(predictionId)
        predictionEnded(predictionId)
    {
        Prediction storage prediction = predictions[predictionId];
        require(prediction.isActive, "Prediction already ended");
        require(prediction.options[winner], "Invalid winning option");

        prediction.isActive = false;
        prediction.winner = winner;

        emit PredictionEnded(predictionId, winner);

        _calculatePayouts(predictionId, winner);
    }

    function _calculatePayouts(
        uint256 predictionId,
        string memory winner
    ) internal {
        Prediction storage prediction = predictions[predictionId];
        uint256 totalPool = prediction.totalBets[winner];

        require(totalPool > 0, "No bets placed on winning option");

        for (uint256 i = 0; i < prediction.participants.length; i++) {
            address participant = prediction.participants[i];
            uint256 userBet = prediction.bets[participant][winner];

            if (userBet > 0) {
                uint256 payout = (userBet * address(this).balance) / totalPool;
                if (payout > 0) {
                    emit PayoutAvailable(participant, predictionId, payout);
                }
            }
        }
    }

    function claimPayout(
        uint256 predictionId
    ) external nonReentrant whenNotPaused {
        Prediction storage prediction = predictions[predictionId];
        require(!prediction.isActive, "Prediction is still active");

        uint256 userBet = prediction.bets[msg.sender][prediction.winner];
        require(userBet > 0, "No winning bet to claim");

        uint256 totalPool = prediction.totalBets[prediction.winner];
        uint256 payout = (userBet * address(this).balance) / totalPool;
        require(payout > 0, "No payout available");

        prediction.bets[msg.sender][prediction.winner] = 0;

        emit PayoutClaimed(msg.sender, predictionId, payout);

        payable(msg.sender).transfer(payout);
    }

    function addAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "New admin address cannot be zero");
        require(!admins[newAdmin], "Address is already an admin");

        admins[newAdmin] = true;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address admin) external onlyOwner {
        require(admin != address(0), "Admin address cannot be zero");
        require(admin != owner, "Cannot remove owner as admin");
        admins[admin] = false;
        emit AdminRemoved(admin);
    }

    function pause() external onlyOwner whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function getOptions(
        uint256 predictionId
    ) external view returns (string[] memory) {
        return predictions[predictionId].optionList;
    }

    function withdrawBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner).transfer(balance);
    }
}
