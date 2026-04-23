-- Ledger Update: Spot Transfers --
CREATE TABLE IF NOT EXISTS ledger_spot_transfers AS TEMPLATE_EVENT;
ALTER TABLE ledger_spot_transfers
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS usdc_value                  String,
    ADD COLUMN IF NOT EXISTS usdc_value_num              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS destination                 String,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS fee_num                     Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS native_token_fee            String,
    ADD COLUMN IF NOT EXISTS native_token_fee_num        Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS nonce                       UInt64,
    ADD COLUMN IF NOT EXISTS fee_token                   String;

-- Ledger Update: C Staking Transfers --
CREATE TABLE IF NOT EXISTS ledger_c_staking_transfers AS TEMPLATE_EVENT;
ALTER TABLE ledger_c_staking_transfers
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_deposit                  Bool;

-- Ledger Update: Account Class Transfers --
CREATE TABLE IF NOT EXISTS ledger_account_class_transfers AS TEMPLATE_EVENT;
ALTER TABLE ledger_account_class_transfers
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS to_perp                     Bool;

-- Ledger Update: Internal Transfers --
CREATE TABLE IF NOT EXISTS ledger_internal_transfers AS TEMPLATE_EVENT;
ALTER TABLE ledger_internal_transfers
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS destination                 String,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS fee_num                     Float64 DEFAULT 0;

-- Ledger Update: Sub Account Transfers --
CREATE TABLE IF NOT EXISTS ledger_sub_account_transfers AS TEMPLATE_EVENT;
ALTER TABLE ledger_sub_account_transfers
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS destination                 String;

-- Ledger Update: Send --
CREATE TABLE IF NOT EXISTS ledger_sends AS TEMPLATE_EVENT;
ALTER TABLE ledger_sends
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS destination                 String,
    ADD COLUMN IF NOT EXISTS source_dex                  String,
    ADD COLUMN IF NOT EXISTS destination_dex             String,
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS usdc_value                  String,
    ADD COLUMN IF NOT EXISTS usdc_value_num              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS fee_num                     Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS native_token_fee            String,
    ADD COLUMN IF NOT EXISTS native_token_fee_num        Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS nonce                       UInt64,
    ADD COLUMN IF NOT EXISTS fee_token                   String;

-- Ledger Update: Deposits --
CREATE TABLE IF NOT EXISTS ledger_deposits AS TEMPLATE_EVENT;
ALTER TABLE ledger_deposits
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0;

-- Ledger Update: Withdrawals --
CREATE TABLE IF NOT EXISTS ledger_withdrawals AS TEMPLATE_EVENT;
ALTER TABLE ledger_withdrawals
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS nonce                       UInt64,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS fee_num                     Float64 DEFAULT 0;

-- Ledger Update: Vault Deposits --
CREATE TABLE IF NOT EXISTS ledger_vault_deposits AS TEMPLATE_EVENT;
ALTER TABLE ledger_vault_deposits
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS vault                       String,
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0;

-- Ledger Update: Rewards Claims --
CREATE TABLE IF NOT EXISTS ledger_rewards_claims AS TEMPLATE_EVENT;
ALTER TABLE ledger_rewards_claims
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS token                       String;

-- Ledger Update: Vault Withdrawals --
CREATE TABLE IF NOT EXISTS ledger_vault_withdrawals AS TEMPLATE_EVENT;
ALTER TABLE ledger_vault_withdrawals
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS vault                       String,
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS requested_usd               String,
    ADD COLUMN IF NOT EXISTS requested_usd_num           Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS commission                  String,
    ADD COLUMN IF NOT EXISTS commission_num              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS closing_cost                String,
    ADD COLUMN IF NOT EXISTS closing_cost_num            Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS basis                       String,
    ADD COLUMN IF NOT EXISTS basis_num                   Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS net_withdrawn_usd           String,
    ADD COLUMN IF NOT EXISTS net_withdrawn_usd_num       Float64 DEFAULT 0;

-- Ledger Update: Vault Leader Commissions --
CREATE TABLE IF NOT EXISTS ledger_vault_leader_commissions AS TEMPLATE_EVENT;
ALTER TABLE ledger_vault_leader_commissions
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0;

-- Ledger Update: Deploy Gas Auctions --
CREATE TABLE IF NOT EXISTS ledger_deploy_gas_auctions AS TEMPLATE_EVENT;
ALTER TABLE ledger_deploy_gas_auctions
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0;

-- Ledger Update: Account Activation Gas --
CREATE TABLE IF NOT EXISTS ledger_account_activation_gas AS TEMPLATE_EVENT;
ALTER TABLE ledger_account_activation_gas
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS token                       String;

-- Ledger Update: Activate Dex Abstraction --
CREATE TABLE IF NOT EXISTS ledger_activate_dex_abstractions AS TEMPLATE_EVENT;
ALTER TABLE ledger_activate_dex_abstractions
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS dex                         String,
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0;

-- Ledger Update: Liquidations --
CREATE TABLE IF NOT EXISTS ledger_liquidations AS TEMPLATE_EVENT;
ALTER TABLE ledger_liquidations
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS liquidated_ntl_pos          String,
    ADD COLUMN IF NOT EXISTS liquidated_ntl_pos_num      Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS account_value               String,
    ADD COLUMN IF NOT EXISTS account_value_num           Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS leverage_type               String COMMENT 'LEVERAGE_TYPE_CROSS or LEVERAGE_TYPE_ISOLATED',
    ADD COLUMN IF NOT EXISTS liquidated_positions        String COMMENT 'JSON array of liquidated positions';

-- Ledger Update: Spot Genesis --
CREATE TABLE IF NOT EXISTS ledger_spot_genesis AS TEMPLATE_EVENT;
ALTER TABLE ledger_spot_genesis
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0;

-- Ledger Update: Vault Distributions --
CREATE TABLE IF NOT EXISTS ledger_vault_distributions AS TEMPLATE_EVENT;
ALTER TABLE ledger_vault_distributions
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS vault                       String,
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0;

-- Ledger Update: Borrow Lend --
CREATE TABLE IF NOT EXISTS ledger_borrow_lends AS TEMPLATE_EVENT;
ALTER TABLE ledger_borrow_lends
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS token                       String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS interest_amount             String,
    ADD COLUMN IF NOT EXISTS interest_amount_num         Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS operation                   String;

-- Ledger Update: Vault Create --
CREATE TABLE IF NOT EXISTS ledger_vault_creates AS TEMPLATE_EVENT;
ALTER TABLE ledger_vault_creates
    ADD COLUMN IF NOT EXISTS users                       String COMMENT 'Comma-separated list of users involved in the ledger update',
    ADD COLUMN IF NOT EXISTS vault                       String,
    ADD COLUMN IF NOT EXISTS usdc                        String,
    ADD COLUMN IF NOT EXISTS usdc_num                    Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS fee_num                     Float64 DEFAULT 0;
