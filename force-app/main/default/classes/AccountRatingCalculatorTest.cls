/**
 * @description Unit test suite for AccountRatingCalculator.
 *              Covers all scoring tiers, boundary conditions, bulk behaviour,
 *              security (System.runAs), and the Flow invocable entry point.
 *
 *              Protocol  : Unified Metadata Generation Protocol v8
 *              PMD rules : ApexPMD_Ruleset (zero Blocker/Critical/Major violations)
 *              Coverage  : 100 % target on AccountRatingCalculator
 *
 * @author      Agentia Orchestrate Agent
 * @story       AA-118
 */
@IsTest
private class AccountRatingCalculatorTest {

    // -------------------------------------------------------------------------
    // Test data helpers
    // -------------------------------------------------------------------------

    /**
     * Creates and inserts a test Account with the supplied financial attributes.
     * @param name              Account name (must be unique per test method).
     * @param annualRevenue     Annual Revenue value (nullable).
     * @param numberOfEmployees Number of Employees (nullable).
     * @return Inserted Account.
     */
    private static Account createAccount(String name, Decimal annualRevenue, Integer numberOfEmployees) {
        Account acc = new Account(
            Name              = name,
            AnnualRevenue     = annualRevenue,
            NumberOfEmployees = numberOfEmployees
        );
        insert acc;
        return acc;
    }

    /**
     * Creates and inserts n Opportunities linked to the given Account.
     * @param accountId  Parent Account Id.
     * @param count      Number of Opportunities to create.
     */
    private static void createOpportunities(Id accountId, Integer count) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opps.add(new Opportunity(
                Name      = 'Test Opp ' + i,
                AccountId = accountId,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;
    }

    // -------------------------------------------------------------------------
    // 1. Rating = Cold  (score 0-3)
    // -------------------------------------------------------------------------

    @IsTest
    static void testRatingCold_ZeroValues() {
        Account acc = createAccount('Cold Zero', 0, 0);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Zero revenue/employees/opps should yield Cold');
    }

    @IsTest
    static void testRatingCold_BelowAllThresholds() {
        Account acc = createAccount('Cold Below', 50000, 5);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Revenue < 100 k, employees < 10, 0 opps -> Cold');
    }

    @IsTest
    static void testRatingCold_NullFields() {
        Account acc = createAccount('Cold Null', null, null);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Null revenue and employees should be treated as 0 -> Cold');
    }

    // -------------------------------------------------------------------------
    // 2. Rating = Warm  (score 4-6)
    // -------------------------------------------------------------------------

    @IsTest
    static void testRatingWarm_RevenueAndEmployees() {
        Account acc = createAccount('Warm RevEmp', 1000000, 100);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Warm', rating, 'Revenue >=1M + Employees >=100 = 4pts -> Warm');
    }

    @IsTest
    static void testRatingWarm_WithOpportunities() {
        Account acc = createAccount('Warm Opps', 100000, 10);
        createOpportunities(acc.Id, 5);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Warm', rating, '1+1+2=4pts -> Warm');
    }

    @IsTest
    static void testRatingWarm_BoundaryScore5() {
        Account acc = createAccount('Warm Score5', 1000000, 100);
        createOpportunities(acc.Id, 2);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Warm', rating, '2+2+1=5pts -> Warm');
    }

    // -------------------------------------------------------------------------
    // 3. Rating = Hot   (score 7-9)
    // -------------------------------------------------------------------------

    @IsTest
    static void testRatingHot_MaxScore() {
        Account acc = createAccount('Hot Max', 10000000, 1000);
        createOpportunities(acc.Id, 10);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Hot', rating, '3+3+3=9pts -> Hot');
    }

    @IsTest
    static void testRatingHot_Score7() {
        Account acc = createAccount('Hot Score7', 10000000, 1000);
        createOpportunities(acc.Id, 1);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Hot', rating, '3+3+1=7pts -> Hot');
    }

    @IsTest
    static void testRatingHot_BoundaryRevenue() {
        Account acc = createAccount('Hot BndRev', 10000000, 1000);
        createOpportunities(acc.Id, 5);

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Hot', rating, 'Revenue exactly 10M -> 3+3+2=8pts -> Hot');
    }

    // -------------------------------------------------------------------------
    // 4. Bulk behaviour (200 accounts, no opps: 3+3+0=6 -> Warm)
    //    This test validates the bulk DML path and governor limit compliance,
    //    not the Hot-score path (tested individually above).
    // -------------------------------------------------------------------------

    @IsTest
    static void testBulkUpdateAccountRatings() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(
                Name              = 'Bulk Account ' + i,
                AnnualRevenue     = 10000000,   // tier 3 -> 3 pts
                NumberOfEmployees = 1000         // tier 3 -> 3 pts
                // No opportunities -> 0 pts   Total = 6 -> Warm
            ));
        }
        insert accounts;

        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }

        Test.startTest();
        AccountRatingCalculator.updateAccountRatings(accountIds);
        Test.stopTest();

        // Revenue(3) + Employees(3) + Opps(0) = 6 -> Warm
        List<Account> updated = [SELECT Id, Rating FROM Account WHERE Id IN :accountIds];
        for (Account acc : updated) {
            System.assertEquals('Warm', acc.Rating, 'Bulk account without opps: 3+3+0=6pts -> Warm');
        }
    }

    // -------------------------------------------------------------------------
    // 5. Edge cases - null / empty inputs
    // -------------------------------------------------------------------------

    @IsTest
    static void testCalculateAccountRating_NullId() {
        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(null);
        Test.stopTest();

        System.assertEquals(null, rating, 'Null accountId should return null');
    }

    @IsTest
    static void testCalculateAccountRatings_EmptySet() {
        Test.startTest();
        Map<Id, String> result = AccountRatingCalculator.calculateAccountRatings(new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result map should not be null for empty input');
        System.assertEquals(0, result.size(), 'Result map should be empty for empty input');
    }

    @IsTest
    static void testUpdateAccountRatings_NullSet() {
        Test.startTest();
        AccountRatingCalculator.updateAccountRatings(null);
        Test.stopTest();
        System.assert(true, 'No exception should be thrown for null input');
    }

    // -------------------------------------------------------------------------
    // 6. Invocable / Flow entry point
    // -------------------------------------------------------------------------

    @IsTest
    static void testUpdateAccountRatingFromFlow_ValidRequest() {
        Account acc = createAccount('Flow Hot', 10000000, 1000);
        createOpportunities(acc.Id, 10);

        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = acc.Id;

        Test.startTest();
        AccountRatingCalculator.updateAccountRatingFromFlow(
            new List<AccountRatingCalculator.FlowRequest>{ req }
        );
        Test.stopTest();

        Account updated = [SELECT Rating FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Hot', updated.Rating, 'Flow entry point should persist Hot rating');
    }

    @IsTest
    static void testUpdateAccountRatingFromFlow_NullRequest() {
        Test.startTest();
        AccountRatingCalculator.updateAccountRatingFromFlow(null);
        Test.stopTest();
        System.assert(true, 'Null requests list should be handled gracefully');
    }

    @IsTest
    static void testUpdateAccountRatingFromFlow_NullAccountId() {
        AccountRatingCalculator.FlowRequest req = new AccountRatingCalculator.FlowRequest();
        req.accountId = null;

        Test.startTest();
        AccountRatingCalculator.updateAccountRatingFromFlow(
            new List<AccountRatingCalculator.FlowRequest>{ req }
        );
        Test.stopTest();
        System.assert(true, 'Null accountId inside FlowRequest should be handled gracefully');
    }

    // -------------------------------------------------------------------------
    // 7. Security - System.runAs
    // -------------------------------------------------------------------------

    @IsTest
    static void testSecurityRunAs_StandardUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias             = 'stdusr',
            Email             = 'stduser_arc@example.com',
            EmailEncodingKey  = 'UTF-8',
            FirstName         = 'Test',
            LastName          = 'User ARC',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            UserName          = 'stduser_arc_aa118@example.com'
        );
        insert testUser;

        Id accId;
        System.runAs(testUser) {
            Account acc = createAccount('RunAs Hot', 10000000, 1000);
            createOpportunities(acc.Id, 10);
            accId = acc.Id;

            Test.startTest();
            AccountRatingCalculator.updateAccountRatings(new Set<Id>{ accId });
            Test.stopTest();
        }

        Account updated = [SELECT Rating FROM Account WHERE Id = :accId];
        System.assertEquals('Hot', updated.Rating, 'Standard User context should result in Hot rating');
    }
}