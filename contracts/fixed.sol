// SPDX-License-Identifier: MIT

// Update to the latest Solidity version
pragma solidity ^0.8.27;

contract ParimutuelBetting {
    struct Prediction {
        uint256 id;
        string title;
        string description;
        string[] options;
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
    mapping(address => bool) public admins;

    constructor() {
        owner = msg.sender;
        admins[owner] = true;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin can perform this action");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier predictionExists(uint256 _id) {
        require(predictions[_id].id == _id, "Prediction does not exist");
        _;
    }

    modifier predictionActive(uint256 _id) {
        require(predictions[_id].isActive, "Prediction is not active");
        _;
    }

    modifier predictionEnded(uint256 _id) {
        require(
            block.timestamp > predictions[_id].endBidTime,
            "Prediction has not ended yet"
        );
        _;
    }

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
    event Payout(address indexed user, uint256 amount);

    function createPrediction(
        string memory _title,
        string memory _description,
        string[] memory _options,
        uint256 _endBidTime
    ) external onlyAdmin {
        require(
            _endBidTime > block.timestamp,
            "End bid time must be in the future"
        );

        Prediction storage newPrediction = predictions[predictionCounter];
        newPrediction.id = predictionCounter;
        newPrediction.title = _title;
        newPrediction.description = _description;
        newPrediction.options = _options;
        newPrediction.endBidTime = _endBidTime;
        newPrediction.isActive = true;

        emit PredictionCreated(
            predictionCounter,
            _title,
            _description,
            _options,
            _endBidTime
        );
        predictionCounter++;
    }

    function placeBet(
        uint256 _predictionId,
        string memory _option
    )
        external
        payable
        predictionExists(_predictionId)
        predictionActive(_predictionId)
    {
        require(msg.value > 0, "Bet amount must be greater than zero");
        require(
            block.timestamp <= predictions[_predictionId].endBidTime,
            "Cannot place bet after bidding time has ended"
        );

        Prediction storage prediction = predictions[_predictionId];
        bool validOption = false;
        for (uint256 i = 0; i < prediction.options.length; i++) {
            if (
                keccak256(abi.encodePacked(prediction.options[i])) ==
                keccak256(abi.encodePacked(_option))
            ) {
                validOption = true;
                break;
            }
        }
        require(validOption, "Invalid betting option");

        if (prediction.bets[msg.sender][_option] == 0) {
            prediction.participants.push(msg.sender);
        }

        prediction.bets[msg.sender][_option] += msg.value;
        prediction.totalBets[_option] += msg.value;

        emit BetPlaced(msg.sender, _predictionId, _option, msg.value);
    }

    function endPrediction(
        uint256 _predictionId,
        string memory _winner
    )
        external
        onlyAdmin
        predictionExists(_predictionId)
        predictionEnded(_predictionId)
    {
        Prediction storage prediction = predictions[_predictionId];
        require(prediction.isActive, "Prediction already ended");

        bool validOption = false;
        for (uint256 i = 0; i < prediction.options.length; i++) {
            if (
                keccak256(abi.encodePacked(prediction.options[i])) ==
                keccak256(abi.encodePacked(_winner))
            ) {
                validOption = true;
                break;
            }
        }
        require(validOption, "Invalid winning option");

        prediction.isActive = false;
        prediction.winner = _winner;

        emit PredictionEnded(_predictionId, _winner);

        _distributeWinnings(_predictionId, _winner);
    }

    function _distributeWinnings(
        uint256 _predictionId,
        string memory _winner
    ) internal {
        Prediction storage prediction = predictions[_predictionId];
        uint256 totalPool = prediction.totalBets[_winner];

        require(totalPool > 0, "No bets placed on winning option");

        uint256 totalCorrectBets = prediction.totalBets[_winner];

        for (uint256 i = 0; i < prediction.participants.length; i++) {
            address participant = prediction.participants[i];
            uint256 userBet = prediction.bets[participant][_winner];
            if (userBet > 0) {
                // Prevent reentrancy attacks
                (bool success, ) = participant.call{
                    value: (userBet * address(this).balance) / totalCorrectBets
                }("");
                require(success, "Payout failed");
                emit Payout(
                    participant,
                    (userBet * address(this).balance) / totalCorrectBets
                );
            }
        }
    }

    function withdrawBalance() external onlyOwner {
        // Prevent gas limit issues by using call instead of transfer
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // Prevent 0 admin address
    function addAdmin(address _newAdmin) external onlyOwner {
        require(_newAdmin != address(0), "New admin address cannot be zero");
        admins[_newAdmin] = true;
        emit AdminAdded(_newAdmin);
    }

    // Prevent 0 admin address
    function removeAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Admin address cannot be zero");
        admins[_admin] = false;
        emit AdminRemoved(_admin);
    }
}
