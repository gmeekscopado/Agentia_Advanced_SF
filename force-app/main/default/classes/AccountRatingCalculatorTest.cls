/**
 * @description Test coverage for AccountRatingCalculator: validates Hot/Warm/Cold
 *              scoring tiers, zero and null value edge cases, bulk execution, and the
 *              Flow invocable entry point.
 */
@isTest
private class AccountRatingCalculatorTest {

    @testSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Hot Value Account', AnnualRevenue = 12000000, NumberOfEmployees = 1200),
            new Account(Name = 'Warm Value Account', AnnualRevenue = 6000000, NumberOfEmployees = 600),
            new Account(Name = 'Cold Value Account', AnnualRevenue = 1200000, NumberOfEmployees = 120),
            new Account(Name = 'Zero Value Account', AnnualRevenue = 0, NumberOfEmployees = 0),
            new Account(Name = 'Null Value Account', AnnualRevenue = null, NumberOfEmployees = null)
        };
        insert accounts;

        Map<String, Account> accountsByName = new Map<String, Account>();
        for (Account acc : accounts) {
            accountsByName.put(acc.Name, acc);
        }

        List<Opportunity> opportunities = new List<Opportunity>();
        opportunities.addAll(createOpportunities(accountsByName.get('Hot Value Account').Id, 12));
        opportunities.addAll(createOpportunities(accountsByName.get('Warm Value Account').Id, 1));
        opportunities.addAll(createOpportunities(accountsByName.get('Cold Value Account').Id, 1));
        insert opportunities;
    }

    private static List<Opportunity> createOpportunities(Id accountId, Integer count) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opps.add(new Opportunity(
                Name = 'Test Opportunity ' + i,
                AccountId = accountId,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        return opps;
    }

    @isTest
    static void testHighValueAccountReturnsHotRating() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Hot Value Account' LIMIT 1];

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Hot', rating, 'High-value Account should score Hot.');
    }

    @isTest
    static void testMidValueAccountReturnsWarmRating() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Warm Value Account' LIMIT 1];

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Warm', rating, 'Mid-value Account should score Warm.');
    }

    @isTest
    static void testLowValueAccountReturnsColdRating() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Cold Value Account' LIMIT 1];

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Low-value Account should score Cold.');
    }

    @isTest
    static void testZeroValueAccountReturnsColdRating() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Zero Value Account' LIMIT 1];

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Zero-value Account should score Cold, not error.');
    }

    @isTest
    static void testNullValueAccountReturnsColdRatingWithoutError() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Null Value Account' LIMIT 1];

        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(acc.Id);
        Test.stopTest();

        System.assertEquals('Cold', rating, 'Null revenue/employee values should be treated as zero and score Cold.');
    }

    @isTest
    static void testCalculateAccountRatingWithNullIdReturnsNull() {
        Test.startTest();
        String rating = AccountRatingCalculator.calculateAccountRating(null);
        Test.stopTest();

        System.assertEquals(null, rating, 'A null Account Id should return a null rating without throwing.');
    }

    @isTest
    static void testUpdateAccountRatingsPersistsRatingOnAccount() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Hot Value Account' LIMIT 1];

        Test.startTest();
        AccountRatingCalculator.updateAccountRatings(new Set<Id>{ acc.Id });
        Test.stopTest();

        Account updated = [SELECT Rating FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Hot', updated.Rating, 'Rating field should be persisted to the database.');
    }

    @isTest
    static void testInvocableMethodFromFlowUpdatesRating() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Warm Value Account' LIMIT 1];

        AccountRatingCalculator.FlowRequest request = new AccountRatingCalculator.FlowRequest();
        request.accountId = acc.Id;

        Test.startTest();
        AccountRatingCalculator.updateAccountRatingFromFlow(
            new List<AccountRatingCalculator.FlowRequest>{ request }
        );
        Test.stopTest();

        Account updated = [SELECT Rating FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Warm', updated.Rating, 'Invocable method should persist the calculated rating.');
    }

    @isTest
    static void testInvocableMethodWithEmptyOrNullListIsNoOp() {
        Test.startTest();
        AccountRatingCalculator.updateAccountRatingFromFlow(new List<AccountRatingCalculator.FlowRequest>());
        AccountRatingCalculator.updateAccountRatingFromFlow(null);
        Test.stopTest();

        System.assert(true, 'Empty or null Flow request lists should be handled gracefully without error.');
    }

    @isTest
    static void testBulkAccountRatingCalculationIsGovernorSafe() {
        List<Account> bulkAccounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            bulkAccounts.add(new Account(
                Name = 'Bulk Account ' + i,
                AnnualRevenue = 2000000,
                NumberOfEmployees = 150
            ));
        }
        insert bulkAccounts;

        Set<Id> bulkIds = new Map<Id, Account>(bulkAccounts).keySet();

        Test.startTest();
        AccountRatingCalculator.updateAccountRatings(bulkIds);
        Test.stopTest();

        List<Account> updatedAccounts = [SELECT Rating FROM Account WHERE Id IN :bulkIds];
        for (Account acc : updatedAccounts) {
            System.assertNotEquals(null, acc.Rating, 'Every Account in the bulk batch should receive a rating.');
        }
    }

    @isTest
    static void testCalculateAccountRatingsWithEmptySetReturnsEmptyMap() {
        Test.startTest();
        Map<Id, String> ratings = AccountRatingCalculator.calculateAccountRatings(new Set<Id>());
        Test.stopTest();

        System.assert(ratings.isEmpty(), 'An empty Id set should return an empty ratings map.');
    }
}