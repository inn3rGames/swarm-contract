pragma ton-solidity >= 0.35.0;

contract ParimutuelBetting {
    struct Prediction {
        uint256 id;
        string title;
        string description;
        mapping(uint256 => bool) options;
        string[] optionList;
        uint256 endBidTime;
        bool isActive;
        uint256 winner;
        mapping(uint256 => uint128) totalBets;
        mapping(address => mapping(uint256 => uint128)) bets;
        address[] participants;
    }

    address public owner;
    uint256 public predictionCounter;
    mapping(uint256 => Prediction) public predictions;
    mapping(uint256 => bool) public predictionExistsMap;
    mapping(address => bool) public admins;
    bool private paused;
    bool private locked;

    uint8 public constant MAX_OPTIONS = 10;

    event AdminAdded(address newAdmin);
    event AdminRemoved(address removedAdmin);
    event PredictionCreated(
        uint256 id,
        string title,
        string description,
        string[] options,
        uint256 endBidTime
    );
    event BetPlaced(
        address user,
        uint256 predictionId,
        uint256 optionId,
        uint128 amount
    );
    event PredictionEnded(uint256 id, uint256 winnerId);
    event PayoutAvailable(
        address user,
        uint256 predictionId,
        uint128 amount
    );
    event PayoutClaimed(
        address user,
        uint256 predictionId,
        uint128 amount
    );
    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        tvm.accept();
        owner = msg.sender;
        admins[owner] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 101);
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], 102);
        _;
    }

    modifier whenNotPaused() {
        require(!paused, 103);
        _;
    }

    modifier whenPaused() {
        require(paused, 104);
        _;
    }

    modifier nonReentrant() {
        require(!locked, 105);
        locked = true;
        _;
        locked = false;
    }

    modifier predictionExists(uint256 predictionId) {
        require(predictionExistsMap[predictionId], 106);
        _;
    }

    modifier predictionActive(uint256 predictionId) {
        require(predictions[predictionId].isActive, 107);
        _;
    }

    modifier predictionEnded(uint256 predictionId) {
        require(
            block.timestamp > predictions[predictionId].endBidTime,
            108
        );
        _;
    }

    function createPrediction(
        string title,
        string description,
        string[] options,
        uint256 durationInSeconds
    ) public onlyAdmin whenNotPaused {
        require(durationInSeconds > 0, 109);
        require(
            options.length > 1 && options.length <= MAX_OPTIONS,
            110
        );

        tvm.accept();

        uint256 endBidTime = block.timestamp + durationInSeconds;

        Prediction prediction = predictions[predictionCounter];
        prediction.id = predictionCounter;
        prediction.title = title;
        prediction.description = description;
        prediction.endBidTime = endBidTime;
        prediction.isActive = true;

        for (uint256 i = 0; i < options.length; i++) {
            require(!prediction.options[i], 111);
            prediction.options[i] = true;
            prediction.optionList.push(options[i]);
        }

        predictionExistsMap[predictionCounter] = true;

        emit PredictionCreated(
            predictionCounter,
            title,
            description,
            options,
            endBidTime
        );
        predictionCounter++;
    }

    function placeBet(
        uint256 predictionId,
        uint256 optionId
    )
        public
        nonReentrant
        whenNotPaused
        predictionExists(predictionId)
        predictionActive(predictionId)
    {
        require(msg.value > 0, 112);
        require(
            block.timestamp <= predictions[predictionId].endBidTime,
            113
        );

        tvm.accept();

        Prediction prediction = predictions[predictionId];
        require(prediction.options[optionId], 114);

        if (prediction.bets[msg.sender][optionId] == 0) {
            prediction.participants.push(msg.sender);
        }

        prediction.bets[msg.sender][optionId] += uint128(msg.value);
        prediction.totalBets[optionId] += uint128(msg.value);

        emit BetPlaced(msg.sender, predictionId, optionId, uint128(msg.value));
    }

    function endPrediction(
        uint256 predictionId,
        uint256 winnerId
    )
        public
        onlyAdmin
        predictionExists(predictionId)
        predictionEnded(predictionId)
    {
        tvm.accept();

        Prediction prediction = predictions[predictionId];
        require(prediction.isActive, 115);
        require(prediction.options[winnerId], 116);

        prediction.isActive = false;
        prediction.winner = winnerId;

        emit PredictionEnded(predictionId, winnerId);

        _calculatePayouts(predictionId, winnerId);
    }

    function _calculatePayouts(
        uint256 predictionId,
        uint256 winnerId
    ) private {
        Prediction prediction = predictions[predictionId];
        uint128 totalPool = prediction.totalBets[winnerId];

        require(totalPool > 0, 117);

        for (uint256 i = 0; i < prediction.participants.length; i++) {
            address participant = prediction.participants[i];
            uint128 userBet = prediction.bets[participant][winnerId];

            if (userBet > 0) {
                uint128 payout = math.muldiv(userBet, uint128(address(this).balance), totalPool);
                if (payout > 0) {
                    emit PayoutAvailable(participant, predictionId, payout);
                }
            }
        }
    }

    function claimPayout(
        uint256 predictionId
    ) public nonReentrant whenNotPaused {
        tvm.accept();

        Prediction prediction = predictions[predictionId];
        require(!prediction.isActive, 118);

        uint128 userBet = prediction.bets[msg.sender][prediction.winner];
        require(userBet > 0, 119);

        uint128 totalPool = prediction.totalBets[prediction.winner];
        uint128 payout = math.muldiv(userBet, uint128(address(this).balance), totalPool);
        require(payout > 0, 120);

        prediction.bets[msg.sender][prediction.winner] = 0;

        emit PayoutClaimed(msg.sender, predictionId, payout);

        _safeTransfer(msg.sender, payout);
    }

    function addAdmin(address newAdmin) public onlyOwner {
        require(newAdmin != address(0), 121);
        require(!admins[newAdmin], 122);

        tvm.accept();

        admins[newAdmin] = true;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address admin) public onlyOwner {
        require(admin != address(0), 123);
        require(admin != owner, 124);

        tvm.accept();

        admins[admin] = false;
        emit AdminRemoved(admin);
    }

    function pause() public onlyOwner whenNotPaused {
        tvm.accept();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        tvm.accept();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function getOptions(
        uint256 predictionId
    ) public view returns (string[]) {
        return predictions[predictionId].optionList;
    }

    function withdrawBalance() public onlyOwner {
        tvm.accept();
        uint128 balance = uint128(address(this).balance);
        require(balance > 0, 125);
       _safeTransfer(msg.sender, balance);
    }

    function _safeTransfer(address recipient, uint128 amount) internal {
        tvm.accept();
        uint16 maxTransfer = type(uint16).max;  // Maximum value for uint16
        while (amount > 0) {
            if (amount > maxTransfer) {
                recipient.transfer(maxTransfer, false, 0);
                amount -= maxTransfer;
            } else {
                recipient.transfer(uint16(amount), false, 0);
                amount = 0;
            }
        }
    }
}