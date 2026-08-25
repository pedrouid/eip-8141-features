// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

contract CanonicalPaymaster {
    uint256 public constant WITHDRAWAL_DELAY = 12 hours;

    address private constant ENTRY_POINT = address(0xaa);

    uint256 private constant MODE_DEFAULT = 0;
    uint256 private constant MODE_VERIFY = 1;
    uint256 private constant APPROVE_PAYMENT = 0x01;
    uint256 private constant APPROVE_EXECUTION = 0x02;
    uint256 private constant APPROVE_GUARANTEE = 0x04;
    uint256 private constant SECP256K1 = 0x01;
    uint256 private constant P256 = 0x02;
    uint256 private constant MIN_BUMP_EXECUTION_GAS = 40_000;
    uint256 private constant NONCE_SLOT_STATE_GAS = 97_920;
    uint256 private constant LEGACY_NONCE_STATE_GAS = 183_600;
    uint256 private constant NONCELESS_MAX_STATE_GAS = 391_680;
    uint256 private constant NONCE_KEY_MAX = type(uint256).max;
    uint256 private constant BUMP_NONCE_DATA_LEN = 68;

    address public owner;
    address payable public pendingWithdrawalTo;
    uint256 public pendingWithdrawalAmount;
    uint256 public pendingWithdrawalReadyAt;
    mapping(address sender => uint256 nonce) public guarantor_nonce;

    error NotOwner();
    error NotEntryPoint();
    error ZeroAddress();
    error InvalidSignature();
    error InvalidNonce();
    error InvalidBumpNonceFrame();
    error NotInDefaultFrame();
    error NoPrecedingGuarantee();
    error NoPendingWithdrawal();
    error WithdrawalNotReady();
    error WithdrawalExceedsBalance();
    error TransferFailed();

    event WithdrawalRequested(address indexed to, uint256 amount, uint256 readyAt);
    event WithdrawalExecuted(address indexed to, uint256 amount);

    constructor(address owner_) payable {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
    }

    receive() external payable {}

    fallback() external payable {
        if (msg.data.length != 1) revert InvalidSignature();

        uint256 signatureIndex = uint8(msg.data[0]);
        uint256 currentFrame = _currentFrameIndex();
        uint256 allowedScope = _frameAllowedScope(currentFrame);

        _validateSignature(signatureIndex);

        if (allowedScope == APPROVE_PAYMENT) {
            _approvePayment();
        } else if (allowedScope == APPROVE_GUARANTEE) {
            _validateGuarantorFrames(currentFrame);
            _approveGuarantee();
        } else {
            revert InvalidSignature();
        }
    }

    function bumpNonce(address sender, uint256 payerNonce) external {
        if (msg.sender != ENTRY_POINT) revert NotEntryPoint();

        uint256 currentFrame = _currentFrameIndex();
        if (_frameMode(currentFrame) != MODE_DEFAULT) revert NotInDefaultFrame();
        if (currentFrame < 2) revert NoPrecedingGuarantee();

        uint256 guaranteeFrame = currentFrame - 2;
        uint256 senderFrame = currentFrame - 1;

        if (_frameTarget(guaranteeFrame) != address(this)) revert NoPrecedingGuarantee();
        if (_frameMode(guaranteeFrame) != MODE_VERIFY) revert NoPrecedingGuarantee();
        if (_frameStatus(guaranteeFrame) != 1) revert NoPrecedingGuarantee();
        if (_frameApprovedScope(guaranteeFrame) != APPROVE_GUARANTEE) {
            revert NoPrecedingGuarantee();
        }
        if (_frameMode(senderFrame) != MODE_VERIFY) revert NoPrecedingGuarantee();
        if (_frameAllowedScope(senderFrame) != APPROVE_EXECUTION) {
            revert NoPrecedingGuarantee();
        }
        if (sender != _txSender()) revert InvalidNonce();

        uint256 senderStatus = _frameStatus(senderFrame);
        uint256 senderApprovedScope = _frameApprovedScope(senderFrame);
        if (senderStatus == 1 && senderApprovedScope == APPROVE_EXECUTION) {
            _approvePayment();
            return;
        }
        if (senderStatus > 1 || senderApprovedScope != 0) revert InvalidNonce();
        if (guarantor_nonce[sender] != payerNonce) revert InvalidNonce();
        if (payerNonce == type(uint256).max) revert InvalidNonce();

        unchecked {
            guarantor_nonce[sender] = payerNonce + 1;
        }
    }

    function requestWithdrawal(address payable to, uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        if (to == address(0)) revert ZeroAddress();
        if (amount > address(this).balance) revert WithdrawalExceedsBalance();

        pendingWithdrawalTo = to;
        pendingWithdrawalAmount = amount;
        pendingWithdrawalReadyAt = block.timestamp + WITHDRAWAL_DELAY;

        emit WithdrawalRequested(to, amount, pendingWithdrawalReadyAt);
    }

    function executeWithdrawal() external {
        if (msg.sender != owner) revert NotOwner();

        address payable to = pendingWithdrawalTo;
        uint256 amount = pendingWithdrawalAmount;
        uint256 readyAt = pendingWithdrawalReadyAt;

        if (readyAt == 0) revert NoPendingWithdrawal();
        if (block.timestamp < readyAt) revert WithdrawalNotReady();

        delete pendingWithdrawalTo;
        delete pendingWithdrawalAmount;
        delete pendingWithdrawalReadyAt;

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit WithdrawalExecuted(to, amount);
    }

    function _validateSignature(uint256 signatureIndex) internal {
        uint256 scheme = _signatureScheme(signatureIndex);
        if (scheme != SECP256K1 && scheme != P256) revert InvalidSignature();
        if (_signatureSigner(signatureIndex) != owner) revert InvalidSignature();
        if (_signatureMessage(signatureIndex) != bytes32(0)) revert InvalidSignature();
    }

    function _validateGuarantorFrames(uint256 currentFrame) internal {
        uint256 senderFrame = currentFrame + 1;
        uint256 bumpFrame = currentFrame + 2;

        if (bumpFrame >= _numFrames()) revert InvalidBumpNonceFrame();
        if (_frameMode(senderFrame) != MODE_VERIFY) revert InvalidBumpNonceFrame();
        if (_frameAllowedScope(senderFrame) != APPROVE_EXECUTION) {
            revert InvalidBumpNonceFrame();
        }
        address sender = _txSender();
        if (_frameTarget(senderFrame) != sender) revert InvalidBumpNonceFrame();

        if (_frameTarget(bumpFrame) != address(this)) revert InvalidBumpNonceFrame();
        if (_frameMode(bumpFrame) != MODE_DEFAULT) revert InvalidBumpNonceFrame();
        if (_frameFlags(bumpFrame) != APPROVE_PAYMENT) revert InvalidBumpNonceFrame();
        if (_frameExecutionLimit(bumpFrame) < MIN_BUMP_EXECUTION_GAS) {
            revert InvalidBumpNonceFrame();
        }
        uint256 nonceKeyCount = _nonceKeyCount();
        uint256 requiredStateGas = nonceKeyCount * NONCE_SLOT_STATE_GAS;
        if (nonceKeyCount == 1 && _firstNonceKey() == 0) {
            requiredStateGas = LEGACY_NONCE_STATE_GAS;
        } else if (nonceKeyCount == 1 && _firstNonceKey() == NONCE_KEY_MAX) {
            requiredStateGas = NONCELESS_MAX_STATE_GAS;
        }
        if (_frameStateLimit(bumpFrame) < requiredStateGas) {
            revert InvalidBumpNonceFrame();
        }
        if (_frameDataLen(bumpFrame) != BUMP_NONCE_DATA_LEN) {
            revert InvalidBumpNonceFrame();
        }

        bytes32 firstWord = _frameDataLoad(bumpFrame, 0);
        if (bytes4(firstWord) != this.bumpNonce.selector) revert InvalidBumpNonceFrame();
        if (address(uint160(uint256(_frameDataLoad(bumpFrame, 4)))) != sender) {
            revert InvalidBumpNonceFrame();
        }

        uint256 payerNonce = uint256(_frameDataLoad(bumpFrame, 36));
        if (guarantor_nonce[sender] != payerNonce) revert InvalidNonce();
    }

    function _txSender() internal returns (address value) {
        assembly {
            value := verbatim_0i_1o(hex"6002b0")
        }
    }

    function _numFrames() internal returns (uint256 value) {
        assembly {
            value := verbatim_0i_1o(hex"6009b0")
        }
    }

    function _currentFrameIndex() internal returns (uint256 value) {
        assembly {
            value := verbatim_0i_1o(hex"600ab0")
        }
    }

    function _nonceKeyCount() internal returns (uint256 value) {
        assembly {
            value := verbatim_0i_1o(hex"600eb0")
        }
    }

    function _firstNonceKey() internal returns (uint256 value) {
        assembly {
            value := verbatim_0i_1o(hex"6010b0")
        }
    }

    function _frameTarget(uint256 index) internal returns (address value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x00, index)
        }
    }

    function _frameExecutionLimit(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x01, index)
        }
    }

    function _frameMode(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x02, index)
        }
    }

    function _frameFlags(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x03, index)
        }
    }

    function _frameDataLen(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x04, index)
        }
    }

    function _frameStatus(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x05, index)
        }
    }

    function _frameAllowedScope(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x06, index)
        }
    }

    function _frameStateLimit(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x09, index)
        }
    }

    function _frameApprovedScope(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b3", 0x0c, index)
        }
    }

    function _frameDataLoad(uint256 index, uint256 offset) internal returns (bytes32 value) {
        assembly {
            value := verbatim_2i_1o(hex"b1", index, offset)
        }
    }

    function _signatureSigner(uint256 index) internal returns (address value) {
        assembly {
            value := verbatim_2i_1o(hex"b4", 0x00, index)
        }
    }

    function _signatureScheme(uint256 index) internal returns (uint256 value) {
        assembly {
            value := verbatim_2i_1o(hex"b4", 0x01, index)
        }
    }

    function _signatureMessage(uint256 index) internal returns (bytes32 value) {
        assembly {
            value := verbatim_2i_1o(hex"b4", 0x02, index)
        }
    }

    function _approvePayment() internal {
        assembly {
            verbatim_0i_0o(hex"600160006000aa")
        }
    }

    function _approveGuarantee() internal {
        assembly {
            verbatim_0i_0o(hex"600460006000aa")
        }
    }
}
