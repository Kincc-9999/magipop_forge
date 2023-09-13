/// @dev Core Library Imports for the Traits outside the Starknet Contract
use starknet::ContractAddress;
use starknet::get_caller_address;

/// @dev Trait defining the functions that can be implemented or called by the Starknet Contract
#[starknet::interface]
trait VoteTrait<T> {
    /// @dev Function that returns the current vote status
    fn get_vote_status(self: @T) -> (u8, u8, u8, u8);
    /// @dev Function that checks if the user at the specified address is allowed to vote
    fn voter_can_vote(self: @T, user_address: ContractAddress) -> bool;
    /// @dev Function that checks if the specified address is registered as a voter
    fn is_voter_registered(self: @T, address: ContractAddress) -> bool;
    /// @dev Function that allows a user to vote
    fn vote(ref self: T, vote: u8);
}

trait IContract<TContractState> {
    fn is_owner(self: @TContractState) -> bool;
    fn is_role_editor(self: @TContractState) -> bool;
    fn only_owner(self: @TContractState);
    fn only_role_editor(self: @TContractState);
    fn only_allowed(self: @TContractState);
    fn set_role_editor(ref self: TContractState, _target: ContractAddress, _active: bool);
    fn role_editor_action(ref self: ContractState);
    fn allowed_action(ref self: ContractState);
}

/// @dev Starknet Contract allowing three registered voters to vote on a proposal
#[starknet::contract]
mod MagipopVote {
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    const YES: u8 = 1_u8;
    const NO: u8 = 0_u8;

    /// @dev Structure that stores vote counts and voter states
    #[storage]
    struct Storage {
        yes_votes: u8,
        no_votes: u8,
        can_vote: LegacyMap::<ContractAddress, bool>,
        registered_voter: LegacyMap::<ContractAddress, bool>,
        
        // Role 'owner': only one address
        owner: ContractAddress,
        // Role 'role_editor': a set of addresses
        role_editor: LegacyMap::<ContractAddress, bool>
    }

    /// @dev Contract constructor initializing the contract with a list of registered voters and 0 vote count
    #[constructor]
    fn constructor(
        ref self: ContractState,
        voter_1: ContractAddress,
        voter_2: ContractAddress,
        voter_3: ContractAddress
    ) {
        // Register all voters by calling the _register_voters function
        self._register_voters(voter_1, voter_2, voter_3);

        self.owner.write(get_caller_address());
        self.role_editor.write(voter_1, true);
        self.role_editor.write(voter_2, true);
        self.role_editor.write(voter_3, true);

        // Initialize the vote count to 0
        self.yes_votes.write(0_u8);
        self.no_votes.write(0_u8);
    }

    /// @dev Event that gets emitted when a vote is cast
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        VoteCast: VoteCast,
        UnauthorizedAttempt: UnauthorizedAttempt,
    }

    /// @dev Represents a vote that was cast
    #[derive(Drop, starknet::Event)]
    struct VoteCast {
        voter: ContractAddress,
        vote: u8,
    }

    /// @dev Represents an unauthorized attempt to vote
    #[derive(Drop, starknet::Event)]
    struct UnauthorizedAttempt {
        unauthorized_address: ContractAddress,
    }

    /// @dev Implementation of VoteTrait for ContractState
    #[external(v0)]
    impl VoteImpl of super::VoteTrait<ContractState> {
        /// @dev Returns the voting results
        fn get_vote_status(self: @ContractState) -> (u8, u8, u8, u8) {
            let (n_yes, n_no) = self._get_voting_result();
            let (yes_percentage, no_percentage) = self._get_voting_result_in_percentage();
            return (n_yes, n_no, yes_percentage, no_percentage);
        }

        /// @dev Check whether a voter is allowed to vote
        fn voter_can_vote(self: @ContractState, user_address: ContractAddress) -> bool {
            self.can_vote.read(user_address)
        }

        /// @dev Check whether an address is registered as a voter
        fn is_voter_registered(self: @ContractState, address: ContractAddress) -> bool {
            self.registered_voter.read(address)
        }

        /// @dev Submit a vote
        fn vote(ref self: ContractState, vote: u8) {
            assert(vote == NO || vote == YES, 'VOTE_0_OR_1');
            let caller: ContractAddress = get_caller_address();
            self._assert_allowed(caller);
            self.can_vote.write(caller, false);

            if (vote == NO) {
                self.no_votes.write(self.no_votes.read() + 1_u8);
            }
            if (vote == YES) {
                self.yes_votes.write(self.yes_votes.read() + 1_u8);
            }

            self.emit(VoteCast { voter: caller, vote: vote, });
        }
    }

    /// @dev Internal Functions implementation for the Vote contract
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        /// @dev Registers the voters and initializes their voting status to true (can vote)
        fn _register_voters(
            ref self: ContractState,
            voter_1: ContractAddress,
            voter_2: ContractAddress,
            voter_3: ContractAddress
        ) {
            self.registered_voter.write(voter_1, true);
            self.can_vote.write(voter_1, true);

            self.registered_voter.write(voter_2, true);
            self.can_vote.write(voter_2, true);

            self.registered_voter.write(voter_3, true);
            self.can_vote.write(voter_3, true);
        }
    }

    /// @dev Asserts implementation for the Vote contract
    #[generate_trait]
    impl AssertsImpl of AssertsTrait {
        // @dev Internal function that checks if an address is allowed to vote
        fn _assert_allowed(ref self: ContractState, address: ContractAddress) {
            let is_voter: bool = self.registered_voter.read((address));
            let can_vote: bool = self.can_vote.read((address));

            if (can_vote == false) {
                self.emit(UnauthorizedAttempt { unauthorized_address: address, });
            }

            assert(is_voter == true, 'USER_NOT_REGISTERED');
            assert(can_vote == true, 'USER_ALREADY_VOTED');
        }
    }

    /// @dev Implement the VotingResultTrait for the Vote contract
    #[generate_trait]
    impl VoteResultFunctionsImpl of VoteResultFunctionsTrait {
        // @dev Internal function to get the voting results (yes and no vote counts)
        fn _get_voting_result(self: @ContractState) -> (u8, u8) {
            let n_yes: u8 = self.yes_votes.read();
            let n_no: u8 = self.no_votes.read();

            return (n_yes, n_no);
        }

        // @dev Internal function to calculate the voting results in percentage
        fn _get_voting_result_in_percentage(self: @ContractState) -> (u8, u8) {
            let n_yes: u8 = self.yes_votes.read();
            let n_no: u8 = self.no_votes.read();

            let total_votes: u8 = n_yes + n_no;

            let yes_percentage: u8 = (n_yes * 100_u8) / (total_votes);
            let no_percentage: u8 = (n_no * 100_u8) / (total_votes);

            return (yes_percentage, no_percentage);
        }
    }

    // Guard functions to check roles

    impl Contract of IContract<ContractState> {
        #[inline(always)]
        fn is_owner(self: @ContractState) -> bool {
            self.owner.read() == get_caller_address()
        }

        #[inline(always)]
        fn is_role_editor(self: @ContractState) -> bool {
            self.role_editor.read(get_caller_address())
        }

        #[inline(always)]
        fn only_owner(self: @ContractState) {
            assert(Contract::is_owner(self), 'Not owner');
        }

        #[inline(always)]
        fn only_role_editor(self: @ContractState) {
            assert(Contract::is_role_editor(self), 'Not role editor');
        }

        // You can easily combine guards to perfom complex checks
        fn only_allowed(self: @ContractState) {
            assert(Contract::is_owner(self) || Contract::is_role_editor(self), 'Not allowed');
        }

        // Functions to manage roles

        fn set_role_editor(ref self: ContractState, _target: ContractAddress, _active: bool) {
            Contract::only_owner(@self);
            self.role_editor.write(_target, _active);
        }

        // You can now focus on the business logic of your contract
        // and reduce the complexity of your code by using guard functions

        fn role_editor_action(ref self: ContractState) {
            Contract::only_role_editor(@self);
        // ...
        }

        fn allowed_action(ref self: ContractState) {
            Contract::only_allowed(@self);
        // ...
        }
    }
}