// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////////////////
            Imports
///////////////////////////////////*/
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/FunctionsClient.sol";

/*///////////////////////////////////
           Libraries
///////////////////////////////////*/
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";

/**
    *@title Chainlink Functions Example
    *@author i3arba - 77 Innovation Labs
    *@notice This is an example of Chainlink Functions implementation
             and have intentional points of improvement for students to correct
    *@dev do not use this is production. It's not audited and can have bugs.
*/
contract ChainlinkFunctions is FunctionsClient, Ownable{

    /*///////////////////////////////////
            Type declarations
    ///////////////////////////////////*/
    using FunctionsRequest for FunctionsRequest.Request;

    /*///////////////////////////////////
                Variables
    ///////////////////////////////////*/
    struct RequestInfo{
        uint256 requestTime;
        uint256 returnedValue;
        string target;
        bool isFulfilled;
    }

    ///@notice Chainlink Functions donId for the specific chain.
    bytes32 immutable i_donId;
    ///@notice Chainlink Subscription ID to process requests
    uint64 immutable i_subscriptionId;

    ///@notice the amount of gas needed to complete the call
    uint32 constant CALLBACK_GAS_LIMIT = 200_000;
    ///@notice Constant variable to hold the JS Script to be executed off-chain.
    string constant SOURCE_CODE = 'const e=await import("npm:ethers@6.10.0");class P extends e.JsonRpcProvider{constructor(u){super(u),this.url=u}async _send(p){return(await fetch(this.url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(p)})).json()}}const r=new P("https://ethereum.publicnode.com");if(!args?.[0]||!e.isAddress(args[0]))throw new Error("Invalid address");return Functions.encodeUint256(await r.getBalance(args[0]))';

    ///@notice magic numbers removal
    uint8 constant ZERO = 0;

    ///@notice mapping to store requests informatio
    ///@dev IMPROVEMENT: for security reasons it's better to use internal instead of public for state variables
    mapping(bytes32 requestId => RequestInfo) internal s_requestStorage;

    /*///////////////////////////////////
                Events
    ///////////////////////////////////*/
    ///@notice event emitted when a new CLF request is initialized
    event ChainlinkFunctions_FunctionsRequestSent(bytes32 requestId);
    ///@notice event emitted when functions returns 
    event ChainlinkFunctions_Response(bytes32 requestId, uint256 returnedValue);
    ///@notice event emitted when an CLF fails
    event ChainlinkFunctions_RequestFailed(bytes32 requestId, bytes err);

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    ///@notice error emitted when the requestId is not valid
    error ChainlinkFunctions_UnexpectedRequestID(bytes32 requestId);
    ///@notice error emitted when a callback tries to fulfill an already fulfilled request
    error ChainlinkFunctions_RequestAlreadyFulfilled(bytes32 requestId);

    /*///////////////////////////////////
                constructor
    ///////////////////////////////////*/
    constructor(
        address _router, 
        address _owner, 
        bytes32 _donId, 
        uint64 _subscriptionId
    ) FunctionsClient(_router) Ownable(_owner){
        i_donId = _donId;
        i_subscriptionId = _subscriptionId;
    }

    /*///////////////////////////////////
                external
    ///////////////////////////////////*/
    /**
     * @notice Function to initiate a CLF simple request and query the eth balance of a address
     * @param _args List of arguments accessible from within the source code
     * @param _bytesArgs Array of bytes arguments, represented as hex strings
     */
    function sendRequest(
        string[] memory _args,
        bytes[] memory _bytesArgs
    ) external onlyOwner returns (bytes32 requestId_) {

        FunctionsRequest.Request memory req;

        req._initializeRequestForInlineJavaScript(SOURCE_CODE);

        if (_args.length > 0) req._setArgs(_args);
        if (_bytesArgs.length > 0) req._setBytesArgs(_bytesArgs);

        requestId_ = _sendRequest(
            req._encodeCBOR(),
            i_subscriptionId,
            CALLBACK_GAS_LIMIT,
            i_donId
        );

        s_requestStorage[requestId_] = RequestInfo({
            requestTime: block.timestamp,
            returnedValue: 0,
            target: _args[0],
            isFulfilled: false
        });

        emit ChainlinkFunctions_FunctionsRequestSent(requestId_);
    }

    /*///////////////////////////////////
                internal
    ///////////////////////////////////*/
    /**
     * @notice Store latest result/error
     * @param _requestId The request ID, returned by sendRequest()
     * @param _response Aggregated response from the user code
     * @param _err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function _fulfillRequest(
        bytes32 _requestId,
        bytes memory _response,
        bytes memory _err
    ) internal override {
        RequestInfo storage request = s_requestStorage[_requestId];
        if (request.requestTime == ZERO) revert ChainlinkFunctions_UnexpectedRequestID(_requestId);
        if (request.isFulfilled) revert ChainlinkFunctions_RequestAlreadyFulfilled(_requestId);

        if(_response.length > ZERO){
            uint256 returnedValue = abi.decode(_response, (uint256));

            request.returnedValue = returnedValue;
            request.isFulfilled = true;

            emit ChainlinkFunctions_Response(_requestId, returnedValue);
        } else {
            emit ChainlinkFunctions_RequestFailed(_requestId, _err);
        }
    }
}