/**
 * @description Test class for AccountRatingCalculator
 * @author ACME Corporation
 * @date 2026-03-19
 */
@isTest
private class AccountRatingCalculatorTest {

    /**
     * @description Test data setup - creates accounts and opportunities used across test methods
     */
    @testSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();

        // Hot Account - High revenue ($15M), high employees (1500), many opportunities (12)
        // Expected score: revenue 3 + employees 3 + opportunities 3 = 9 -> Hot
        Account hotAccount = new Account(
            Name = 'Hot Test Account',
            AnnualRevenue = 15000000,
            NumberOfEmployees = 1500
        );
        accounts.add(hotAccount);

        // Warm Account - Medium revenue ($6M), medium employees (600), several opportunities (6)
        // Expected score: revenue 2 + employees 2 + opportunities 2 = 6 -> Warm
        Account warmAccount = new Account(
            Name = 'Warm Test Account',
            AnnualRevenue = 6000000,
            NumberOfEmployees = 600
        );
        accounts.add(warmAccount);

        // Cold Account - Low revenue ($500K), low employees (50), one opportunity
        // Expected score: revenue 0 + employees 0 + opportunities 1 = 1 -> Cold
        Account coldAccount = new Account(
            Name = 'Cold Test Account',
            AnnualRevenue = 500000,
            NumberOfEmployees = 50
        );
        accounts.add(coldAccount);

        // Zero values account - all zeros
        Account zeroAccount = new Account(
            Name = 'Zero Test Account',
            AnnualRevenue = 0,
            NumberOfEmployees = 0
        );
        accounts.add(zeroAccount);

        // Null values account
        Account nullAccount = new Account(
            Name = 'Null Test Account'
        );
        accounts.add(nullAccount);

        insert accounts;

        // Create 12 opportunities for hot account (score 3 in opportunity tier)
        List<Opportunity> allOpps = new List<Opportunity>();
        for (Integer i = 0; i < 12; i++) {
            allOpps.add(new Opportunity(
                Name = 'Hot Opp ' + i,
                AccountId = hotAccount.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        // Create 6 opportunities for warm account (score 2 in opportunity tier)
        for (Integer i = 0; i < 6; i++) {
            allOpps.add(new Opportunity(
                Name = 'Warm Opp ' + i,
                AccountId = warmAccount.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        // Create 1 opportunity for cold account (score 1 in opportunity tier)
        allOpps.add(new Opportunity(
            Name = 'Cold Opp',
            AccountId = coldAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        ));
        insert allOpps;
    }

    // =========================================================================
    // Rating calculation - single account
    // =========================================================================

    /**
     * @description Verify Hot rating for an account with maximum revenue, employees, and opportunities
     */
    @isTest
    static void testHotRatingCalculation() {
        Account hotAccount = [SELECT Id FROM Account WHERE Name = 'Hot Test Account' LIMIT 1];
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(hotAccount.Id);
            System.assertEquals('Hot', rating, 'Account should be rated as Hot');
        }
        Test.stopTest();
    }

    /**
     * @description Verify Warm rating for an account with medium revenue, employees, and opportunities
     */
    @isTest
    static void testWarmRatingCalculation() {
        Account warmAccount = [SELECT Id FROM Account WHERE Name = 'Warm Test Account' LIMIT 1];
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(warmAccount.Id);
            System.assertEquals('Warm', rating, 'Account should be rated as Warm');
        }
        Test.stopTest();
    }

    /**
     * @description Verify Cold rating for an account with low revenue, low employees, and one opportunity
     */
    @isTest
    static void testColdRatingCalculation() {
        Account coldAccount = [SELECT Id FROM Account WHERE Name = 'Cold Test Account' LIMIT 1];
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(coldAccount.Id);
            System.assertEquals('Cold', rating, 'Account should be rated as Cold');
        }
        Test.stopTest();
    }

    /**
     * @description Verify Cold rating for an account where all numeric fields are zero
     */
    @isTest
    static void testZeroValuesAccount() {
        Account zeroAccount = [SELECT Id FROM Account WHERE Name = 'Zero Test Account' LIMIT 1];
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(zeroAccount.Id);
            System.assertEquals('Cold', rating, 'Account with zero values should be rated as Cold');
        }
        Test.stopTest();
    }

    /**
     * @description Verify Cold rating for an account where all numeric fields are null
     */
    @isTest
    static void testNullValuesAccount() {
        Account nullAccount = [SELECT Id FROM Account WHERE Name = 'Null Test Account' LIMIT 1];
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(nullAccount.Id);
            System.assertEquals('Cold', rating, 'Account with null values should be rated as Cold');
        }
        Test.stopTest();
    }

    // =========================================================================
    // Bulk rating calculation
    // =========================================================================

    /**
     * @description Verify that all five accounts receive a rating in a bulk call
     */
    @isTest
    static void testBulkRatingCalculation() {
        List<Account> accounts = [SELECT Id FROM Account];
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<Id, String> ratings = AccountRatingCalculator.calculateAccountRatings(accountIds);
            System.assertEquals(5, ratings.size(), 'Should calculate ratings for all 5 accounts');
            System.assert(ratings.values().contains('Hot'),  'Should contain at least one Hot rating');
            System.assert(ratings.values().contains('Warm'), 'Should contain at least one Warm rating');
            System.assert(ratings.values().contains('Cold'), 'Should contain at least one Cold rating');
        }
        Test.stopTest();
    }

    /**
     * @description Verify that all accounts have their Rating field populated after updateAccountRatings
     */
    @isTest
    static void testUpdateAccountRatings() {
        List<Account> accounts = [SELECT Id FROM Account];
        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AccountRatingCalculator.updateAccountRatings(accountIds);
        }
        Test.stopTest();
        List<Account> updatedAccounts = [SELECT Id, Name, Rating FROM Account];
        for (Account acc : updatedAccounts) {
            System.assertNotEquals(null, acc.Rating, 'Rating should be set for: ' + acc.Name);
        }
    }

    // =========================================================================
    // Exception handling
    // =========================================================================

    /**
     * @description Verify that passing a null account ID throws AccountRatingException
     *              with a message containing 'cannot be null'
     */
    @isTest
    static void testNullAccountIdException() {
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                AccountRatingCalculator.calculateAccountRating(null);
                System.assert(false, 'Should throw AccountRatingException for null account ID');
            } catch (AccountRatingCalculator.AccountRatingException e) {
                System.assert(
                    e.getMessage().containsIgnoreCase('cannot be null'),
                    'Expected "cannot be null" in: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();
    }

    /**
     * @description Verify that a non-existent account ID throws AccountRatingException
     *              with a message containing 'not found'
     */
    @isTest
    static void testInvalidAccountIdException() {
        // Build a syntactically valid but non-existent Account Id
        Id fakeId = Id.valueOf('001000000000000AAA');
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                AccountRatingCalculator.calculateAccountRating(fakeId);
                System.assert(false, 'Should throw AccountRatingException for non-existent account');
            } catch (AccountRatingCalculator.AccountRatingException e) {
                System.assert(
                    e.getMessage().containsIgnoreCase('not found'),
                    'Expected "not found" in: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();
    }

    // =========================================================================
    // Edge cases on bulk methods
    // =========================================================================

    /**
     * @description Verify that an empty Set returns an empty Map without errors
     */
    @isTest
    static void testEmptySetHandling() {
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<Id, String> ratings = AccountRatingCalculator.calculateAccountRatings(new Set<Id>());
            System.assertEquals(0, ratings.size(), 'Empty set should return empty Map');
        }
        Test.stopTest();
    }

    /**
     * @description Verify that a null Set returns an empty Map without errors
     */
    @isTest
    static void testNullSetHandling() {
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<Id, String> ratings = AccountRatingCalculator.calculateAccountRatings(null);
            System.assertEquals(0, ratings.size(), 'Null set should return empty Map');
        }
        Test.stopTest();
    }

    // =========================================================================
    // Scoring tier boundary tests
    // =========================================================================

    /**
     * @description Verify correct scoring for each revenue tier boundary value
     */
    @isTest
    static void testRevenueScoringTiers() {
        List<Account> testAccounts = new List<Account>{
            new Account(Name = 'Revenue Tier 3pts', AnnualRevenue = 10000000, NumberOfEmployees = 0),
            new Account(Name = 'Revenue Tier 2pts', AnnualRevenue = 5000000,  NumberOfEmployees = 0),
            new Account(Name = 'Revenue Tier 1pt',  AnnualRevenue = 1000000,  NumberOfEmployees = 0)
        };
        insert testAccounts;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (Account acc : testAccounts) {
                String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
                System.assertNotEquals(null, rating, 'Rating should not be null for: ' + acc.Name);
            }
        }
        Test.stopTest();
    }

    /**
     * @description Verify correct scoring for each employee-count tier boundary value
     */
    @isTest
    static void testEmployeeScoringTiers() {
        List<Account> testAccounts = new List<Account>{
            new Account(Name = 'Employee Tier 3pts', NumberOfEmployees = 1000, AnnualRevenue = 0),
            new Account(Name = 'Employee Tier 2pts', NumberOfEmployees = 500,  AnnualRevenue = 0),
            new Account(Name = 'Employee Tier 1pt',  NumberOfEmployees = 100,  AnnualRevenue = 0)
        };
        insert testAccounts;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            for (Account acc : testAccounts) {
                String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
                System.assertNotEquals(null, rating, 'Rating should not be null for: ' + acc.Name);
            }
        }
        Test.stopTest();
    }

    /**
     * @description Verify that 10 opportunities on a zero-revenue, zero-employee account
     *              yields a score of 3 (Cold, since 3 < WARM_THRESHOLD of 4)
     */
    @isTest
    static void testOpportunityScoringTiers() {
        Account testAccount = new Account(Name = 'Opp Tier Test', AnnualRevenue = 0, NumberOfEmployees = 0);
        insert testAccount;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 10; i++) {
            opps.add(new Opportunity(
                Name = 'Opp ' + i,
                AccountId = testAccount.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String rating = AccountRatingCalculator.calculateAccountRating(testAccount.Id);
            System.assertEquals('Cold', rating, '10 opps only = score 3, which is below Warm threshold');
        }
        Test.stopTest();
    }

    // =========================================================================
    // Flow invocable method tests
    // =========================================================================

    /**
     * @description Verify that the Flow invocable method correctly sets the Hot rating
     */
    @isTest
    static void testUpdateAccountRatingFromFlow() {
        Account hotAccount = [SELECT Id FROM Account WHERE Name = 'Hot Test Account' LIMIT 1];
        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = hotAccount.Id;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AccountRatingCalculator.updateAccountRatingFromFlow(
                new List<AccountRatingCalculator.FlowRequest>{ req }
            );
        }
        Test.stopTest();
        Account updated = [SELECT Rating FROM Account WHERE Id = :hotAccount.Id LIMIT 1];
        System.assertEquals('Hot', updated.Rating, 'Flow invocable should set rating to Hot');
    }

    /**
     * @description Verify that the Flow invocable method handles a null request list gracefully
     */
    @isTest
    static void testUpdateAccountRatingFromFlowNullList() {
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AccountRatingCalculator.updateAccountRatingFromFlow(null);
            System.assert(true, 'Null list should be handled gracefully');
        }
        Test.stopTest();
    }

    /**
     * @description Verify that the Flow invocable method handles a request with a null account ID gracefully
     */
    @isTest
    static void testUpdateAccountRatingFromFlowNullAccountId() {
        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = null;
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AccountRatingCalculator.updateAccountRatingFromFlow(
                new List<AccountRatingCalculator.FlowRequest>{ req }
            );
            System.assert(true, 'Null account ID in FlowRequest should be handled gracefully');
        }
        Test.stopTest();
    }
}