access(all) contract MultiSign {
    pub var requiredVotesToPass : UInt
    pub var eligibleToVote: {Address: Bool}
    pub var proposals: {String:Proposal}
    pub var voteExpireDuration: UFix64

    pub resource RemoteControl{
        pub fun createProposal(name: String, code: String){
            if !MultiSign.eligibleToVote[self.owner!.address]!{
               panic("you are not eligible to create proposal")
            }
            MultiSign.createProposal(proposer: self.owner!.address, name: name, code: code)
        }
        pub fun vote(proposalID: String, vote: Bool){
            if !MultiSign.eligibleToVote[self.owner!.address]!{
               panic("you are not eligible to vote")
            }
            MultiSign.vote(voter: self.owner!.address, proposalID: proposalID, vote: vote)
        }
        pub fun deleteProposal(proposalID: String) {
            if !MultiSign.eligibleToVote[self.owner!.address]!{
               panic("you are not eligible to delete proposal")
            }
            MultiSign.deleteProposal(proposalID: proposalID)
        }
    }
    pub fun createRemoteControl() : @RemoteControl{
        return <- create RemoteControl()
    }

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
            if self.finished{
                panic("voting already finished")
            }
            if self.votes[voter]!=nil{
                panic("you have already voted")
            }
            self.votes.insert(key: voter, vote)
            self.votesReverse[vote]!.append(voter)

            if vote && (self.votesReverse[vote]!).length>=MultiSign.requiredVotesToPass{
                self.finished = true
                var trampoline = "pub contract Trampoline{\n pub fun execute(){\n if self.account.load<Bool>(from: /storage/shouldRun)!=nil{\n"
                trampoline = trampoline.concat(self.name)
                trampoline = trampoline.concat("(self.account)\n} \n}  \n}")
                MultiSign.account.contracts.update__experimental(name: "Transactions", code: self.code.utf8)
                MultiSign.account.contracts.update__experimental(name: "Trampoline", code: trampoline.utf8)
                MultiSign.account.save(true, to: /storage/shouldRun)
            }
        }
    }

    access(contract) fun deleteProposal(proposalID: String) {
        var proposal = self.proposals[proposalID]!
        if proposal.finished || getCurrentBlock().timestamp - proposal.created_at > Multisign.voteExpireDuration{ 
            self.proposals.remove(key: proposalID)
        }
    }

    access(contract) fun createProposal(proposer: Address, name: String, code: String) {
        var proposal = Proposal(proposer: proposer , name: name, code: code) 
        self.proposals[proposal.id] = proposal
    }

    access(contract) fun vote(voter: Address, proposalID: String, vote: Bool) {
        self.proposals[proposalID]!.vote(voter: voter, proposalID: proposalID, vote: vote)
    }

    access(account) fun setVoters(voters: {Address: Bool}}{
        self.eligibleToVote = voters
    }

    init(voters: {Address: Bool}, requiredVotes: UInt){
        self.proposals = {}
        self.requiredVotesToPass = requiredVotes
        self.voteExpireDuration = UFix64( 1440.0 * 60.0 * 7.0 ) //7 days
        self.eligibleToVote =  voters
        MultiSign.account.contracts.add(name: "Trampoline", code:  "pub contract Trampoline{}".utf8)
        MultiSign.account.contracts.add(name: "Transactions", code:  "pub contract Transactions{}".utf8)
    }

    pub fun deployTo(acc: AuthAccount, voters: {Address:Bool}, requiredVotes: UInt){
        acc.contracts.add(
            name: "MultiSign", 
            code: self.account.contracts.get(name: "MultiSign")!.code, 
            voters:{Address:Bool}, 
            requiredVotes: requiredVotes
        )
    }
}
