access(all) contract MultiSign {
    
    //config variables 
    pub var requiredVotesToPass : UInt
    pub var eligibleToVote: {Address: Bool}
    pub var voteExpireDuration: UFix64
    
    //proposals
    pub var proposals: {String:Proposal}
    
    //helper functions later to manage config parameters
    access(account) fun setVoters(voters: {Address: Bool}){
        self.eligibleToVote = voters
    }
    
    access(account) fun setRequiredVotesToPass(count: UInt){
        self.requiredVotesToPass = count
    }
    
    access(account) fun setVoteExpiteDuration(duration: UFix64){
        self.voteExpireDuration = duration
    }
    
    //remove control resource to store at voters' accounts
    pub resource RemoteControl{
        pub fun createProposal(name: String, code: String){
            pre{
                self.owner!=nil && MultiSign.eligibleToVote[self.owner!.address]! : "you are not eligible to perform this action"
            }
            MultiSign.createProposal(proposer: self.owner!.address, name: name, code: code)
        }
        pub fun vote(proposalID: String, vote: Bool){
            pre{
                self.owner!=nil && MultiSign.eligibleToVote[self.owner!.address]! : "you are not eligible to perform this action"
            }
            MultiSign.vote(voter: self.owner!.address, proposalID: proposalID, vote: vote)
        }
        pub fun deleteProposal(proposalID: String) {
            pre{
                self.owner!=nil && MultiSign.eligibleToVote[self.owner!.address]! : "you are not eligible to perform this action"
            }
            MultiSign.deleteProposal(proposalID: proposalID)
        }
    }

    pub fun createRemoteControl() : @RemoteControl{
        return <- create RemoteControl()
    }

    //proposal
    pub struct Proposal{
        pub var id: String
        pub var created_at: UFix64
        pub var proposer: Address
        pub var name: String
        pub var code: String
        pub var votes: {Address: Bool}
        pub var votesReverse: {Bool: [Address]}
        pub var finished: Bool

        init(proposer: Address, name: String, code: String){
            self.votes = {}
            self.votesReverse = {true:[], false:[]}
            self.id = String.encodeHex(HashAlgorithm.SHA3_256.hash(name.concat(code).utf8))
            self.proposer = proposer
            self.name = name
            self.code = code
            self.created_at = getCurrentBlock().timestamp
            self.finished = false
        }

        access(contract) fun vote(voter: Address, proposalID: String, vote: Bool){
            pre{
                self.finished==false: "voting already finished"
                self.votes[voter]==nil: "you have already voted"
            }
            
            self.votes.insert(key: voter, vote)
            self.votesReverse[vote]!.append(voter)

            if vote && (self.votesReverse[vote]!).length>=Int(MultiSign.requiredVotesToPass){
                self.finished = true
                MultiSign.account.contracts.update__experimental(name: "Transactions", code: self.code.utf8)
                log(self.code)
                MultiSign.account.save(true, to: /storage/shouldRun)
            }
        }
    }

    //proposal functions
    access(contract) fun deleteProposal(proposalID: String) {
        var proposal = self.proposals[proposalID]!
        if proposal.finished || getCurrentBlock().timestamp - proposal.created_at > MultiSign.voteExpireDuration{ 
            self.proposals.remove(key: proposalID)
        }
    }

    access(contract) fun createProposal(proposer: Address, name: String, code: String) {
        var proposal = Proposal(proposer: proposer , name: name, code: code) 
        self.proposals.insert(key:proposal.id, proposal)
    }

    access(contract) fun vote(voter: Address, proposalID: String, vote: Bool) {
        self.proposals[proposalID]!.vote(voter: voter, proposalID: proposalID, vote: vote)
    }

    
    init(){
        self.proposals = {}
        self.requiredVotesToPass = 1
        self.voteExpireDuration = UFix64( 1440.0 * 60.0 * 7.0 ) //default 7 days
        self.eligibleToVote =  {Address(0xf8d6e0586b0a20c7):true}
        MultiSign.account.contracts.add(name: "Trampoline", code:  "pub contract Trampoline{}".utf8)
        MultiSign.account.contracts.add(name: "Transactions", code:  "pub contract Transactions{}".utf8)
    }

    pub fun deployTo(acc: AuthAccount){
        acc.contracts.add(
            name: "MultiSign", 
            code: self.account.contracts.get(name: "MultiSign")!.code, 
        )
    }
}
