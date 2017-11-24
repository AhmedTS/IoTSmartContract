pragma solidity ^0.4.0;

contract IoTSmartContract{
    struct topic{
      uint topicID;
      string topicName;
      uint ratePerHour;
    }
    struct subscription{
      uint32 subscriptionID;
      address customer;
      uint topicID;
      uint balance;
    }
    event Deposited(address from, uint value);
    event TopicAdded(uint ID, string name, uint rate);
    event Subscribed(address customer, uint topicID, uint amount);
    event Accessed(address customer, uint TopicID, uint amount);
    event Refunded(address customer, uint amount);
    address private owner;
    Broker private broker;
    topic[] private topics;
    mapping (address => uint) public deposits;
    mapping (address => subscription[]) subscriptions;
    uint32 totalSubscriptions = 1;
    uint32 internal totalAccesses = 1;
    mapping (address => uint[]) accessing;
    modifier onlyOwner{
      require(msg.sender == owner);
      _;
    }
    modifier notOwner{
      require(msg.sender != owner);
      _;
    }
    modifier onlyBroker{
      require(msg.sender == address(broker));
      _;
    }
    function IoTSmartContract(address b, string name, uint rate) public{
        owner = msg.sender;
        broker = Broker(b);
        topics.push(topic(topics.length,name,rate));
        broker.addTopic(topics.length-1);
        TopicAdded(0,name,rate);
    }
    function addTopic(string name, uint rate) onlyOwner public{
        topics.push(topic(topics.length,name,rate));
        broker.addTopic(topics.length-1);
        TopicAdded(topics.length-1,name,rate);
    }
    function deposit() payable notOwner public{
        deposits[msg.sender] += msg.value;
        Deposited(msg.sender,msg.value);
    }
    function getDeposit() public notOwner view returns(uint){
        return deposits[msg.sender];
    }
    function subscribe(uint topicID, uint amount) notOwner public{
        require(topicID<topics.length && amount<=deposits[msg.sender]);
        bool found = false;
        for(uint i=0; i < subscriptions[msg.sender].length; i++){
          if(subscriptions[msg.sender][i].topicID==topicID){
              subscriptions[msg.sender][i].balance += amount;
              found = true;
              break;
          }
        }
        if(!found){
          subscriptions[msg.sender].push(subscription(totalSubscriptions,msg.sender,topicID,amount));
          totalSubscriptions++;
        }
        deposits[msg.sender] -= amount;
        Subscribed(msg.sender,topicID,amount);
    }
    function isAccessing(address customer, uint topicID) internal view returns(bool){
        for(uint i=0;i<accessing[customer].length;i++)
            if(accessing[customer][i]==topicID)
                return true;
                
        return false;
    }
    function removeAccessing(address customer, uint topicID) internal{
        bool found = false;
        uint index = 0;
        for(uint i=0;i<accessing[customer].length;i++)
            if(accessing[customer][i]==topicID){
                found = true;
                index = i;
            }
        if(found){
           accessing[customer][index] = accessing[customer][accessing[customer].length-1];
           accessing[customer].length--;
        }
    }
    function access(uint topicID) public notOwner returns(address, uint, bytes32){
        require(!isAccessing(msg.sender,topicID));
        bool found = false;
        uint balance = 0;
        for(uint i=0; i < subscriptions[msg.sender].length; i++){
          if(subscriptions[msg.sender][i].topicID==topicID){
              if(subscriptions[msg.sender][i].balance != 0){
                  balance = subscriptions[msg.sender][i].balance;
                  found = true;
              }
              break;
          }
        }
        require(found);
        uint accessTime = balance/topics[topicID].ratePerHour;
        uint temp = block.timestamp%3;
        bytes32 token;
        if( temp == 0)
            token = keccak256(msg.sender,totalAccesses,owner,topicID);
        else if(temp == 1)
            token = keccak256(topicID,totalAccesses,owner,msg.sender);
        else
            token = keccak256(owner,totalAccesses,msg.sender,topicID);
        totalAccesses++;
        accessing[msg.sender].push(topicID);
        broker.addSubscriberAccess(msg.sender,topicID,token,accessTime);
        return (address(broker),accessTime,token);
    }
    function getTopicRate(uint topicID) private view returns (uint){
        return topics[topicID].ratePerHour;
    }
    function updateSubscriptionTime(address customer,uint topicID, uint time) public onlyBroker{
        uint usage = time * getTopicRate(topicID);
        for(uint i = 0; i < subscriptions[customer].length; i++){
          if(subscriptions[customer][i].topicID == topicID){
              subscriptions[customer][i].balance -= usage;
          }
        }
        owner.transfer(usage);
        removeAccessing(customer,topicID);
        Accessed(customer,topicID,usage);
    }
    function refund() public{
        require(accessing[msg.sender].length == 0);
        uint totalAmount = deposits[msg.sender];
        for(uint i = 0; i < subscriptions[msg.sender].length; i++){
           totalAmount += subscriptions[msg.sender][i].balance;
        }
        msg.sender.transfer(totalAmount);
        Refunded(msg.sender,totalAmount);
        deposits[msg.sender] = 0;
        for(uint j = 0; j < subscriptions[msg.sender].length; j++){
           subscriptions[msg.sender][j].balance = 0;
           broker.clearSubscription(msg.sender,subscriptions[msg.sender][i].topicID);
        }
    }
}
contract Broker{
    struct topicAccess{
       uint topicID;
       bytes32 token;
       uint time;
    }
    event customerAccessStart(address customer, uint topicID, uint duration);
    event customerAccessEnded(address customer, uint topicID, uint duration);
    mapping (address => uint[]) publishers;
    mapping (address => topicAccess[]) subscribers;
    function Broker() public{}
    function addTopic(uint topicID) public{
        publishers[msg.sender].push(topicID);
    }
    function addSubscriberAccess(address customer, uint tID, bytes32 token, uint time) public{
        bool found = false;
        for( uint i=0; i < publishers[msg.sender].length; i++){
           if(publishers[msg.sender][i]==tID){
               found = true;
           }
        }
        require(found);
        subscribers[customer].push(topicAccess(tID,token,time));
    }
    function access(uint topic, bytes32 token) public{
        bool found = false;
        uint index = 0;
        uint duration = 0;
        for( uint i=0; i < subscribers[msg.sender].length; i++){
           if(subscribers[msg.sender][i].topicID==topic && subscribers[msg.sender][i].token==token){
               found = true;
               index = i;
               duration = subscribers[msg.sender][i].time;
           }
        }
        require(found);
        clearSubscription(msg.sender,topic);
        customerAccessStart(msg.sender,topic,duration);
        //send Data off the chain
    }
    function accessEnded(address d, address c, uint topic, uint time) public{
        customerAccessEnded(c,topic,time);
        IoTSmartContract device = IoTSmartContract(d);
        device.updateSubscriptionTime(c,topic,time);
    }
    function clearSubscription(address customer, uint topicID) public{
        bool found = false;
        uint index = 0;
        for(uint i=0; i < subscribers[customer].length; i++){
           if(topicID == subscribers[customer][i].topicID){
               index = i;
               found = true;
               break;
           }
        }
        if(found){
           subscribers[customer][index] = subscribers[customer][subscribers[customer].length-1];
           subscribers[customer].length--;
        }
    }
}
