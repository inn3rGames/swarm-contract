// SPDX-License-Identifier: MIT

// Update to the latest Solidity version
pragma solidity ^0.8.27;

/// @title Parimutuel Betting Contract
/// @notice This contract allows users to place bets on various predictions with multiple options.
/// @dev The contract uses a parimutuel betting system where all bets are pooled together.
contract ParimutuelBetting {
    /// @notice Struct representing a prediction in the betting system.
    struct Prediction {
        uint256 id; // Unique identifier for the prediction
        string title; // Title of the prediction
        string description; // Description of the prediction
        mapping(string => bool) options; // Available betting options
        string[] optionList; // List of options for easier retrieval
        uint256 endBidTime; // Block number when betting ends
        bool isActive; // Status of the prediction
        string winner; // Winning option
        mapping(string => uint256) totalBets; // Total bets placed on each option
        mapping(address => mapping(string => uint256)) bets; // User bets per option
        address[] participants; // List of participants who placed bets
    }

    /// @notice Address of the contract owner.
    address public immutable owner;
    /// @notice Counter for tracking predictions.
    uint256 public predictionCounter;
    /// @notice Mapping of prediction IDs to Prediction structs.
    mapping(uint256 => Prediction) public predictions;
    /// @notice Mapping to track if a prediction exists.
    mapping(uint256 => bool) public predictionExistsMap;
    /// @notice Mapping of admin addresses.
    mapping(address => bool) public admins;
    /// @notice Flag indicating if the contract is paused.
    bool private paused;
    /// @notice Prevents reentrant calls.
    bool private locked;

    uint256 public constant MAX_OPTIONS = 10; // Maximum number of options per prediction
    uint256 public constant TIME_BUFFER = 1 hours; // Time buffer for predictions

    /// @notice Event emitted when a new admin is added.
    event AdminAdded(address indexed newAdmin);
    /// @notice Event emitted when an admin is removed.
    event AdminRemoved(address indexed removedAdmin);
    /// @notice Event emitted when a new prediction is created.
    event PredictionCreated(
        uint256 id,
        string title,
        string description,
        string[] options,
        uint256 endBidTime
    );
    /// @notice Event emitted when a bet is placed.
    event BetPlaced(
        address indexed user,
        uint256 predictionId,
        string option,
        uint256 amount
    );
    /// @notice Event emitted when a prediction ends.
    event PredictionEnded(uint256 id, string winner);
    /// @notice Event emitted when a payout becomes available.
    event PayoutAvailable(
        address indexed user,
        uint256 predictionId,
        uint256 amount
    );
    /// @notice Event emitted when a payout is claimed.
    event PayoutClaimed(
        address indexed user,
        uint256 predictionId,
        uint256 amount
    );
    /// @notice Event emitted when the contract is paused.
    event Paused(address account);
    /// @notice Event emitted when the contract is unpaused.
    event Unpaused(address account);

    /// @notice Constructor that initializes the contract.
    constructor() {
        owner = msg.sender;
        admins[owner] = true; // Owner is also an admin
    }

    /// @notice Modifier to restrict access to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    /// @notice Modifier to restrict access to admins.
    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin can perform this action");
        _;
    }

    /// @notice Modifier to ensure the contract is not paused.
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /// @notice Modifier to ensure the contract is paused.
    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    /// @notice Modifier to prevent reentrant calls.
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    /// @notice Modifier to check if a prediction exists.
    modifier predictionExists(uint256 predictionId) {
        require(predictionExistsMap[predictionId], "Prediction does not exist");
        _;
    }

    /// @notice Modifier to check if a prediction is active.
    modifier predictionActive(uint256 predictionId) {
        require(predictions[predictionId].isActive, "Prediction is not active");
        _;
    }

    /// @notice Modifier to check if a prediction has ended.
    modifier predictionEnded(uint256 predictionId) {
        require(
            block.number > predictions[predictionId].endBidTime,
            "Prediction has not ended yet"
        );
        _;
    }

    /// @notice Creates a new prediction.
    /// @param title Title of the prediction.
    /// @param description Description of the prediction.
    /// @param options Array of options for betting.
    /// @param durationInBlocks Duration of the betting period in blocks.
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

    /// @notice Places a bet on a prediction.
    /// @param predictionId The ID of the prediction.
    /// @param option The betting option chosen by the user.
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

    /// @notice Ends a prediction and declares a winner.
    /// @param predictionId The ID of the prediction to end.
    /// @param winner The option that won the prediction.
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

    /// @notice Calculates payouts for participants based on the winning option.
    /// @param predictionId The ID of the prediction for which to calculate payouts.
    /// @param winner The winning option for the prediction.
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

    /// @notice Claims the payout for the winning bet.
    /// @param predictionId The ID of the prediction to claim the payout from.
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

        prediction.bets[msg.sender][prediction.winner] = 0; // Reset the user's bet

        emit PayoutClaimed(msg.sender, predictionId, payout);

        payable(msg.sender).transfer(payout); // Transfer the payout to the user
    }

    /// @notice Adds a new admin to the contract.
    /// @param newAdmin The address of the new admin to be added.
    function addAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "New admin address cannot be zero");
        require(!admins[newAdmin], "Address is already an admin");

        admins[newAdmin] = true; // Add the new admin
        emit AdminAdded(newAdmin);
    }

    /// @notice Removes an existing admin from the contract.
    /// @param admin The address of the admin to be removed.
    function removeAdmin(address admin) external onlyOwner {
        require(admin != address(0), "Admin address cannot be zero");
        require(admin != owner, "Cannot remove owner as admin");
        admins[admin] = false; // Remove the admin
        emit AdminRemoved(admin);
    }

    /// @notice Pauses the contract, preventing bets from being placed.
    function pause() external onlyOwner whenNotPaused {
        paused = true; // Set the paused flag
        emit Paused(msg.sender);
    }

    /// @notice Unpauses the contract, allowing bets to be placed again.
    function unpause() external onlyOwner whenPaused {
        paused = false; // Reset the paused flag
        emit Unpaused(msg.sender);
    }

    /// @notice Retrieves the list of options for a specific prediction.
    /// @param predictionId The ID of the prediction.
    /// @return An array of strings representing the available options.
    function getOptions(
        uint256 predictionId
    ) external view returns (string[] memory) {
        return predictions[predictionId].optionList; // Return the option list
    }

    /// @notice Allows the contract owner to withdraw the contract's balance.
    function withdrawBalance() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner).transfer(balance); // Transfer the balance to the owner
    }
}
