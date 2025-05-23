use fortichain_contracts::interfaces::IMockUsdc::{IMockUsdcDispatcher, IMockUsdcDispatcherTrait};
#[starknet::contract]
mod Fortichain {
    use core::array::{Array, ArrayTrait};
    use core::num::traits::Zero;
    use core::option::OptionTrait;
    use core::traits::Into;
    use fortichain_contracts::MockUsdc::MockUsdc;
    use fortichain_contracts::interfaces::IFortichain::IFortichain;
    use starknet::storage::{
        Map, Mutable, MutableVecTrait, StorageBase, StorageMapReadAccess, StorageMapWriteAccess,
        StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::base::errors::Errors::{ONLY_CREATOR_CAN_CLOSE, PROJECT_NOT_FOUND};
    use crate::base::types::{Escrow, Project};
    use super::IMockUsdcDispatcherTrait;

    #[storage]
    struct Storage {
        projects: Map<u256, Project>,
        escrows: Map<u256, Escrow>,
        escrows_balance: Map<u256, u256>,
        escrows_is_active: Map<u256, bool>,
        project_count: u256,
        escrows_count: u256,
        completed_projects: Map<u256, bool>,
        in_progress_projects: Map<u256, bool>,
        strk_token_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ProjectStatusChanged: ProjectStatusChanged,
        EscrowCreated: EscrowCreated,
        EscrowFundingPulled: EscrowFundingPulled,
        EscrowFundsAdded: EscrowFundsAdded,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProjectStatusChanged {
        pub project_id: u256,
        pub status: bool // true for completed, false for in-progress
    }

    #[derive(Drop, starknet::Event)]
    pub struct EscrowCreated {
        pub escrow_id: u256,
        pub owner: ContractAddress,
        pub unlock_time: u64,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EscrowFundsAdded {
        pub escrow_id: u256,
        pub owner: ContractAddress,
        pub new_amount: u256,
    }


    #[derive(Drop, starknet::Event)]
    pub struct EscrowFundingPulled {
        pub escrow_id: u256,
        pub owner: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, erc20: ContractAddress) {
        self.strk_token_address.write(erc20);
    }

    #[abi(embed_v0)]
    impl FortichainImpl of IFortichain<ContractState> {
        fn register_project(
            ref self: ContractState,
            name: felt252,
            description: ByteArray,
            category: ByteArray,
            smart_contract_address: ContractAddress,
            contact: ByteArray,
            supporting_document_url: ByteArray,
            logo_url: ByteArray,
            repository_provider: felt252,
            repository_url: ByteArray,
            signature_request: bool,
        ) -> u256 {
            let timestamp: u64 = get_block_timestamp();
            let id: u256 = self.project_count.read() + 1;
            let caller = get_caller_address();
            let project = Project {
                id,
                creator_address: caller,
                name,
                description,
                category,
                smart_contract_address,
                contact,
                supporting_document_url,
                logo_url,
                repository_provider,
                repository_url,
                signature_request,
                is_active: true,
                is_completed: false,
                created_at: timestamp,
                updated_at: timestamp,
            };

            self.projects.write(id, project);
            self.project_count.write(id);
            self.in_progress_projects.write(id, true);

            id
        }

        fn edit_project(
            ref self: ContractState,
            id: u256,
            name: felt252,
            description: ByteArray,
            category: ByteArray,
            smart_contract_address: ContractAddress,
            contact: ByteArray,
            supporting_document_url: ByteArray,
            logo_url: ByteArray,
            repository_provider: felt252,
            repository_url: ByteArray,
            signature_request: bool,
            is_active: bool,
            is_completed: bool,
        ) {
            let project: Project = self.projects.read(id);
            assert(project.id > 0, PROJECT_NOT_FOUND);
            let caller = get_caller_address();
            assert(project.creator_address == caller, ONLY_CREATOR_CAN_CLOSE);
            let mut project = self.projects.read(id);
            let timestamp: u64 = get_block_timestamp();
            if project.name != name {
                project.name = name;
            }
            if project.description != description {
                project.description = description;
            }
            if project.category != category {
                project.category = category;
            }
            if project.smart_contract_address != smart_contract_address {
                project.smart_contract_address = smart_contract_address;
            }
            if project.contact != contact {
                project.contact = contact;
            }
            if project.supporting_document_url != supporting_document_url {
                project.supporting_document_url = supporting_document_url;
            }
            if project.logo_url != logo_url {
                project.logo_url = logo_url;
            }
            if project.repository_provider != repository_provider {
                project.repository_provider = repository_provider;
            }
            if project.repository_url != repository_url {
                project.repository_url = repository_url;
            }
            if project.signature_request != signature_request {
                project.signature_request = signature_request;
            }
            if project.is_active != is_active {
                project.is_active = is_active;
            }
            if project.is_completed != is_completed {
                project.is_completed = is_completed;
            }
            project.updated_at = timestamp;

            self.projects.write(project.id, project);
        }

        fn close_project(
            ref self: ContractState, id: u256, creator_address: ContractAddress,
        ) -> bool {
            let project: Project = self.projects.read(id);
            assert(project.id > 0, PROJECT_NOT_FOUND);
            assert(project.creator_address == creator_address, ONLY_CREATOR_CAN_CLOSE);
            let mut project = self.projects.read(id);
            let timestamp: u64 = get_block_timestamp();
            project.is_active = false;
            project.is_completed = true;
            project.updated_at = timestamp;
            self.projects.write(project.id, project);

            self.in_progress_projects.write(id, false);
            self.completed_projects.write(id, true);

            true
        }

        fn view_project(self: @ContractState, id: u256) -> Project {
            let project = self.projects.read(id);
            assert(project.id > 0, PROJECT_NOT_FOUND);
            project
        }
        fn view_escrow(self: @ContractState, id: u256) -> Escrow {
            let escrow = self.escrows.read(id);
            assert(escrow.id > 0, 'ESCROW not found');
            escrow
        }

        fn total_projects(self: @ContractState) -> u256 {
            let total: u256 = self.project_count.read();
            total
        }

        fn all_completed_projects(self: @ContractState) -> Array<Project> {
            self.get_project_by_completion_status(true)
        }

        fn all_in_progress_projects(self: @ContractState) -> Array<Project> {
            self.get_project_by_completion_status(false)
        }

        fn mark_project_completed(ref self: ContractState, id: u256) {
            let caller = get_caller_address();
            let mut project = self.projects.read(id);

            assert(project.creator_address == caller, ONLY_CREATOR_CAN_CLOSE);

            project.is_active = false;
            project.is_completed = true;
            project.updated_at = get_block_timestamp();
            self.projects.write(id, project);

            self.update_project_completion_status(id, true);

            self
                .emit(
                    Event::ProjectStatusChanged(
                        ProjectStatusChanged { project_id: id, status: true },
                    ),
                );
        }

        fn mark_project_in_progress(ref self: ContractState, id: u256) {
            let caller = get_caller_address();
            let mut project = self.projects.read(id);

            assert(project.creator_address == caller, ONLY_CREATOR_CAN_CLOSE);

            project.is_active = true;
            project.is_completed = false;
            project.updated_at = get_block_timestamp();
            self.projects.write(id, project);

            self.update_project_completion_status(id, false);

            self
                .emit(
                    Event::ProjectStatusChanged(
                        ProjectStatusChanged { project_id: id, status: false },
                    ),
                );
        }

        fn fund_project(
            ref self: ContractState, project_id: u256, amount: u256, lockTime: u64,
        ) -> u256 {
            assert(amount > 0, 'Invalid fund amount');
            assert(lockTime > 0, 'unlock time not in the future');
            let caller = get_caller_address();
            let timestamp: u64 = get_block_timestamp();
            let receiver = get_contract_address();
            let id: u256 = self.escrows_count.read() + 1;
            let mut project = self.view_project(project_id);
            assert(project.creator_address == caller, 'Can only fund your project');

            let success = self.process_payment(caller, amount, receiver);
            assert(success, 'Tokens transfer failed');

            let escrow = Escrow {
                id,
                project_name: project.name,
                projectOwner: caller,
                amount: amount,
                isLocked: true,
                lockTime: timestamp + lockTime,
                is_active: true,
                created_at: timestamp,
                updated_at: timestamp,
            };

            self.escrows_count.write(id);
            self.escrows_is_active.write(id, true);
            self.escrows_balance.write(id, amount);
            self.escrows.write(id, escrow);

            self
                .emit(
                    Event::EscrowCreated(
                        EscrowCreated {
                            escrow_id: id, owner: caller, unlock_time: lockTime, amount: amount,
                        },
                    ),
                );

            id
        }
        fn pull_escrow_funding(ref self: ContractState, escrow_id: u256) -> bool {
            let cur_escrow_count = self.escrows_count.read();

            let caller = get_caller_address();
            let timestamp: u64 = get_block_timestamp();
            let contract = get_contract_address();

            assert((escrow_id > 0) && (escrow_id >= cur_escrow_count), 'invalid escrow id');
            let mut escrow = self.view_escrow(escrow_id);

            assert(escrow.lockTime <= timestamp, 'Unlock time in the future');
            assert(caller == escrow.projectOwner, 'not your escrow');

            assert(escrow.is_active, 'No funds to pull out');

            let amount = escrow.amount;

            escrow.amount = 0;
            escrow.lockTime = 0;
            escrow.isLocked = false;
            escrow.is_active = false;
            escrow.updated_at = timestamp;

            self.escrows_is_active.write(escrow_id, false);
            self.escrows_balance.write(escrow_id, 0);
            self.escrows.write(escrow_id, escrow);

            let token = self.strk_token_address.read();

            let erc20_dispatcher = super::IMockUsdcDispatcher { contract_address: token };

            let contract_bal = erc20_dispatcher.get_balance(contract);
            assert(contract_bal >= amount, 'Insufficient funds');
            let success = erc20_dispatcher.transferFrom(contract, caller, amount);
            assert(success, 'token withdrawal fail...');

            self
                .emit(
                    Event::EscrowFundingPulled(
                        EscrowFundingPulled { escrow_id: escrow_id, owner: caller },
                    ),
                );

            true
        }

        fn add_escrow_funding(ref self: ContractState, escrow_id: u256, amount: u256) -> bool {
            let cur_escrow_count = self.escrows_count.read();

            let caller = get_caller_address();
            let timestamp: u64 = get_block_timestamp();
            let contract = get_contract_address();

            assert((escrow_id > 0) && (escrow_id >= cur_escrow_count), 'invalid escrow id');
            let mut escrow = self.view_escrow(escrow_id);

            assert(escrow.lockTime >= timestamp, 'Escrow has Matured');
            assert(escrow.is_active, 'escrow not active');
            assert(caller == escrow.projectOwner, 'not your escrow');

            let success = self.process_payment(caller, amount, contract);
            assert(success, 'Tokens transfer failed');
            escrow.amount += amount;

            escrow.updated_at = timestamp;

            self.escrows_balance.write(escrow_id, escrow.amount);
            self.escrows.write(escrow_id, escrow);

            self
                .emit(
                    Event::EscrowFundsAdded(
                        EscrowFundsAdded {
                            escrow_id: escrow_id, owner: caller, new_amount: escrow.amount,
                        },
                    ),
                );

            true
        }

        fn process_payment(
            ref self: ContractState,
            payer: ContractAddress,
            amount: u256,
            recipient: ContractAddress,
        ) -> bool { // TODO: Uncomment code after ERC20 implementation
            let token = self.strk_token_address.read();

            let erc20_dispatcher = super::IMockUsdcDispatcher { contract_address: token };
            erc20_dispatcher.approve_user(get_contract_address(), amount);
            let contract_allowance = erc20_dispatcher.get_allowance(payer, get_contract_address());
            assert(contract_allowance >= amount, 'INSUFFICIENT_ALLOWANCE');
            let user_bal = erc20_dispatcher.get_balance(payer);
            assert(user_bal >= amount, 'Insufficient funds');
            let success = erc20_dispatcher.transferFrom(payer, recipient, amount);
            assert(success, 'token withdrawal fail...');
            success
        }

        fn get_erc20_address(self: @ContractState) -> ContractAddress {
            let token = self.strk_token_address.read();
            token
        }
    }
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn get_completed_projects_as_array(self: @ContractState) -> Array<u256> {
            let mut projects = ArrayTrait::new();
            let project_count = self.project_count.read();
            for i in 1..=project_count {
                if self.completed_projects.read(i) {
                    projects.append(i);
                }
            }
            projects
        }

        fn get_in_progress_projects_as_array(self: @ContractState) -> Array<u256> {
            let mut projects = ArrayTrait::new();
            let project_count = self.project_count.read();
            for i in 1..=project_count {
                if self.in_progress_projects.read(i) {
                    projects.append(i);
                }
            }
            projects
        }

        fn get_project_by_completion_status(
            self: @ContractState, completed: bool,
        ) -> Array<Project> {
            let project_ids = if completed {
                self.get_completed_projects_as_array()
            } else {
                self.get_in_progress_projects_as_array()
            };

            let mut projects = ArrayTrait::new();
            for i in 0..project_ids.len() {
                let project_id = *project_ids[i];
                let project = self.projects.read(project_id);
                projects.append(project);
            }
            projects
        }

        fn update_project_completion_status(
            ref self: ContractState, project_id: u256, completed: bool,
        ) {
            if completed {
                self.add_to_completed(project_id);
            } else {
                self.add_to_in_progress(project_id);
            }
        }

        fn add_to_completed(ref self: ContractState, project_id: u256) {
            self.completed_projects.write(project_id, true);
            self.in_progress_projects.write(project_id, false);
        }

        fn add_to_in_progress(ref self: ContractState, project_id: u256) {
            self.in_progress_projects.write(project_id, true);
            self.completed_projects.write(project_id, false);
        }

        fn contains_project(self: @ContractState, project_id: u256) -> bool {
            self.completed_projects.read(project_id) || self.in_progress_projects.read(project_id)
        }
    }
}
